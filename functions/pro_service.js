// ═══════════════════════════════════════════════════════════════════════════
// AnySkill Pro — server-side evaluation helper (Phase 1, v15.x)
//
// Single source of truth for the badge-grant decision. Mirrors the Dart
// client logic in lib/services/pro_service.dart :: ProService
// .checkAndRefreshProStatus, but runs in Cloud Functions with the Admin
// SDK so it can write `isAnySkillPro` after the firestore.rules lock-down.
//
// Public surface: only `evaluateProStatus({db, uid, source, ...})`.
// All triggers + callables in functions/index.js call into here so the
// decision logic stays in one place.
//
// Audit log: every grant/revoke transition writes one document to
// `admin_audit_log/{auto-id}` so the admin dashboard + Watchtower can
// show "what happened, why, and who/what triggered it" without any
// extra plumbing.
// ═══════════════════════════════════════════════════════════════════════════

const admin = require("firebase-admin");
const { FieldValue } = require("firebase-admin/firestore");
const {
  buildGrantEmail,
  buildRevokeEmail,
  getRevocationCopy,
} = require("./pro_email_templates");

const ONE_DAY_MS    = 24 * 60 * 60 * 1000;
const THIRTY_D_MS   = 30 * ONE_DAY_MS;
const APP_LINK      = "https://anyskill-6fdf3.web.app";

// ── Default thresholds (match lib/services/pro_service.dart fallback) ──────
// Used when system_settings/pro doesn't exist or is missing keys.
const DEFAULT_THRESHOLDS = Object.freeze({
  minRating:           4.8,
  minOrders:           20,
  maxResponseMinutes:  15,
});

/**
 * Evaluate one provider's Pro eligibility and persist the result if it
 * changed. Idempotent — calling twice on a stable state is a no-op.
 *
 * @param {object}   args
 * @param {admin.firestore.Firestore} args.db
 * @param {string}   args.uid              Provider uid to evaluate.
 * @param {string}   args.source           One of: 'auto' | 'cron' | 'callable_self' | 'callable_admin'.
 * @param {string=}  args.triggerReason    Free-text context (e.g. 'job_completed:abc123').
 * @param {string=}  args.adminUid         Caller uid when source involves an admin.
 * @returns {Promise<{
 *   isPro: boolean,
 *   transition: 'granted'|'revoked'|'unchanged'|'manual_override_skip',
 *   skipped?: string,
 *   revokeReason?: string|null,
 * }>}
 */
async function evaluateProStatus({ db, uid, source = "auto", triggerReason = null, adminUid = null }) {
  if (!uid || typeof uid !== "string") {
    return { isPro: false, transition: "unchanged", skipped: "empty-uid" };
  }

  const [userSnap, thrSnap, completedCnt, cancelCnt] = await Promise.all([
    db.collection("users").doc(uid).get(),
    db.collection("system_settings").doc("pro").get(),
    _countCompletedOrders(db, uid),
    _countRecentExpertCancellations(db, uid),
  ]);

  if (!userSnap.exists) {
    return { isPro: false, transition: "unchanged", skipped: "no-user" };
  }
  const userData = userSnap.data() || {};

  // Manual override freezes the badge — admin decisions outrank auto-eval.
  if (userData.proManualOverride === true) {
    return {
      isPro: userData.isAnySkillPro === true,
      transition: "manual_override_skip",
    };
  }

  const thrData = thrSnap.exists ? (thrSnap.data() || {}) : {};
  const minRating       = _num(thrData.minRating,          DEFAULT_THRESHOLDS.minRating);
  const minOrders       = _num(thrData.minOrders,          DEFAULT_THRESHOLDS.minOrders);
  const maxResponseMins = _num(thrData.maxResponseMinutes, DEFAULT_THRESHOLDS.maxResponseMinutes);

  const rating          = _num(userData.rating,             0);
  const avgResponseMins = _num(userData.avgResponseMinutes, 0);

  // avgResponseMinutes == 0 → no data yet → don't penalise.
  const responseOk = avgResponseMins === 0 || avgResponseMins <= maxResponseMins;

  const isPro = rating >= minRating &&
    completedCnt >= minOrders &&
    responseOk &&
    cancelCnt === 0;

  const wasPro = userData.isAnySkillPro === true;
  if (wasPro === isPro) {
    return { isPro, transition: "unchanged" };
  }

  // ── State transition: write the user doc + audit-log entry ──────────────
  const previousGrantedAt = userData.anySkillProGrantedAt || null;
  const updatePayload = { isAnySkillPro: isPro };
  if (isPro) {
    // Per product decision (v15.x): refresh the timestamp on every new
    // grant. Historical grants live in admin_audit_log.previousGrantedAt.
    updatePayload.anySkillProGrantedAt = FieldValue.serverTimestamp();
  }
  // We deliberately do NOT clear anySkillProGrantedAt on revoke. The field
  // then represents "last held the badge" until the next grant.

  await db.collection("users").doc(uid).update(updatePayload);

  // Identify the criterion that broke (only meaningful on revoke).
  const revokeReason = isPro ? null : _identifyRevokeReason({
    rating, completedCnt, avgResponseMins, cancelCnt,
    minRating, minOrders, maxResponseMins,
  });

  await db.collection("admin_audit_log").add({
    action:           isPro ? "pro_granted" : "pro_revoked",
    targetUserId:     uid,
    targetUserName:   userData.name || userData.fullName || null,
    source,                  // 'auto' | 'cron' | 'callable_self' | 'callable_admin'
    triggerReason,           // optional context (e.g. 'job_completed:JOBID')
    adminUid,                // populated when an admin triggered the eval
    revocationReason: revokeReason,
    metricsSnapshot: {
      rating,
      completedOrders:     completedCnt,
      avgResponseMinutes:  avgResponseMins,
      recentCancellations: cancelCnt,
      thresholds: { minRating, minOrders, maxResponseMinutes: maxResponseMins },
    },
    previousGrantedAt,       // null on first grant; was-Date on re-grant
    createdAt:        FieldValue.serverTimestamp(),
    expireAt:         _ttl30Days(),  // §19 — admin_audit_log NOT TTL'd, but we
                                      // include expireAt as a forward-compat
                                      // hint. Removing the field is a one-line
                                      // change if policy reverses.
  });

  // ── Phase 2: notify the provider ──────────────────────────────────────
  // Three side-effects, all best-effort and isolated in try/catch so a
  // failure in one (e.g. missing FCM token, mail extension down) doesn't
  // abort the others or roll back the audit-log entry.
  const providerName = userData.name || userData.fullName || "שלום";
  const fcmToken     = userData.fcmToken || userData.deviceToken || null;
  const email        = userData.email || null;

  await _notifyProviderTransition({
    db,
    uid,
    providerName,
    fcmToken,
    email,
    isPro,
    metrics: {
      rating,
      completedDeals:   completedCnt,
      avgResponseTime:  avgResponseMins,
      cancellations:    cancelCnt,
      thresholds: { minRating, minOrders, maxResponseMinutes: maxResponseMins },
    },
  });

  return {
    isPro,
    transition: isPro ? "granted" : "revoked",
    revokeReason,
  };
}

// ── Notification fan-out (in-app + push + email) ───────────────────────────
// Best-effort — every channel wrapped in its own try/catch so a partial
// outage doesn't abort the whole transition. The audit log is the durable
// record; everything below is delivery.
async function _notifyProviderTransition({
  db, uid, providerName, fcmToken, email, isPro, metrics,
}) {
  const title = isPro
    ? "🏆 קיבלת את תג AnySkill Pro!"
    : "💙 עדכון לגבי תג AnySkill Pro שלך";
  const body = isPro
    ? `מזל טוב, ${providerName}! הצטרפת למועדון Pro של AnySkill.`
    : `${providerName}, התג הוסר זמנית. תוכל/י לחזור אליו — בדוק/י את הדשבורד לפרטים.`;

  // 1. In-app notification (always written — durable record).
  try {
    await db.collection("notifications").add({
      userId:    uid,
      title,
      body,
      type:      isPro ? "pro_granted" : "pro_revoked",
      isRead:    false,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (e) {
    console.error(`[pro_notify] notifications doc failed for ${uid}:`, e.message);
  }

  // 2. FCM push (skipped gracefully if no token).
  if (fcmToken) {
    try {
      await admin.messaging().send({
        token: fcmToken,
        notification: { title, body },
        android: {
          priority: "high",
          notification: { channelId: "anyskill_default" },
        },
        apns: {
          headers: { "apns-priority": "10" },
          payload: { aps: { sound: "default", contentAvailable: 1 } },
        },
        webpush: {
          notification: { icon: "/icons/Icon-192.png" },
          fcm_options:  { link: APP_LINK },
        },
        data: {
          type: isPro ? "pro_granted" : "pro_revoked",
          uid,
        },
      });
    } catch (e) {
      console.error(`[pro_notify] push failed for ${uid}:`, e.message);
    }
  } else {
    console.warn(`[pro_notify] uid=${uid} has no FCM token, push skipped`);
  }

  // 3. Email via Firebase Trigger Email extension (mail/{auto-id}).
  if (email && typeof email === "string" && email.includes("@")) {
    try {
      const tpl = isPro
        ? buildGrantEmail({ providerName, appLink: APP_LINK })
        : (() => {
            const copy = getRevocationCopy(metrics);
            return buildRevokeEmail({
              providerName,
              revocationReason: copy.reason,
              currentRating:    metrics.rating,
              completedDeals:   metrics.completedDeals,
              avgResponseTime:  metrics.avgResponseTime,
              cancellations:    metrics.cancellations,
              recoveryTip:      copy.tip,
              appLink:          APP_LINK,
            });
          })();
      await db.collection("mail").add({
        to:      email,
        message: { subject: tpl.subject, html: tpl.html },
      });
    } catch (e) {
      console.error(`[pro_notify] mail enqueue failed for ${uid}:`, e.message);
    }
  } else {
    console.warn(`[pro_notify] uid=${uid} has no email, skipping email`);
  }
}

// ── Internal helpers ───────────────────────────────────────────────────────

function _num(v, fallback) {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string" && v.trim() !== "") {
    const n = Number(v);
    if (Number.isFinite(n)) return n;
  }
  return fallback;
}

function _ttl30Days() {
  return admin.firestore.Timestamp.fromDate(new Date(Date.now() + THIRTY_D_MS));
}

async function _countCompletedOrders(db, uid) {
  const snap = await db.collection("jobs")
    .where("expertId", "==", uid)
    .where("status",   "==", "completed")
    .get();
  return snap.size;
}

async function _countRecentExpertCancellations(db, uid) {
  const cutoff = Date.now() - THIRTY_D_MS;
  const snap = await db.collection("jobs")
    .where("expertId", "==", uid)
    .where("status",   "==", "cancelled")
    .get();
  let count = 0;
  for (const doc of snap.docs) {
    const d = doc.data();
    if (d.cancelledBy !== "expert") continue;
    const ts = d.cancelledAt;
    let cancelledAtMs = null;
    if (ts && typeof ts.toMillis === "function") {
      cancelledAtMs = ts.toMillis();
    }
    if (cancelledAtMs !== null && cancelledAtMs > cutoff) count++;
  }
  return count;
}

function _identifyRevokeReason({ rating, completedCnt, avgResponseMins, cancelCnt, minRating, minOrders, maxResponseMins }) {
  // Order matches user-spec recovery-tip priority: cancellations first
  // (they're the most actionable), then quantitative shortfalls.
  if (cancelCnt > 0) {
    return `expert_cancellation_30d (count=${cancelCnt})`;
  }
  if (rating < minRating) {
    return `rating_below_threshold (current=${rating.toFixed(2)}, min=${minRating})`;
  }
  if (completedCnt < minOrders) {
    return `insufficient_orders (current=${completedCnt}, min=${minOrders})`;
  }
  if (avgResponseMins > maxResponseMins) {
    return `slow_response (current=${avgResponseMins}min, max=${maxResponseMins}min)`;
  }
  return "unknown";
}

module.exports = { evaluateProStatus };
