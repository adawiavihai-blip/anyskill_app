const { onDocumentCreated, onDocumentUpdated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
// @anthropic-ai/sdk v0.54 is a CJS package ("type":"commonjs").
// Using top-level require() instead of dynamic await import() avoids the
// "Anthropic is not a constructor" error that occurs because dynamic import()
// of a CJS module wraps module.exports as the `default` property (an object,
// not the class itself).
const { default: Anthropic } = require("@anthropic-ai/sdk");

// ── Secrets (set via: firebase functions:secrets:set ANTHROPIC_API_KEY) ────────
const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");

admin.initializeApp();

// ── Payment Cloud Functions ─────────────────────────────────────────────────
// PHASE 2 NOTE: Stripe Connect was removed pending integration with an
// Israeli payment provider. The legacy credits flow remains in this file
// (processPaymentRelease, processCancellation). When the new provider is
// wired up, re-introduce a payments module via:
//   const payments = require("./payments");
//   exports.<fnName> = payments.<fnName>;

// ── Financial rounding (NIS = 2 decimal places) ─────────────────────────────
// JavaScript floating point: 100 * 0.10 = 10.000000000000002
// This helper prevents ghost agorot and ensures fee + net = total exactly.
function roundNIS(n) { return Math.round(n * 100) / 100; }

// ── v9.7.0: Centralized admin check ────────────────────────────────────────
// Replaces 8 hardcoded email checks scattered across the codebase.
// Admin status is determined SOLELY by the Firestore `isAdmin` flag on the
// user's document. No email-based shortcuts — if the email is compromised,
// the attacker still needs the Firestore flag set by an existing admin.
//
// Usage:  if (!(await isAdminCaller(request))) throw ...
async function isAdminCaller(request) {
  if (!request.auth) return false;
  try {
    const callerSnap = await admin.firestore()
      .collection("users").doc(request.auth.uid).get();
    return callerSnap.exists && callerSnap.data().isAdmin === true;
  } catch (_) {
    return false;
  }
}

// PHASE 2 NOTE: All Stripe-backed exports were removed. The Flutter app no
// longer calls these endpoints (UI is gated behind a "coming soon"
// placeholder until the Israeli payment provider is integrated). Re-add
// new payment provider exports below this line.
//
// Removed exports:
//   createPaymentIntent, handleStripeWebhook, releaseEscrow, onboardProvider,
//   processRefund, listPaymentMethods, createSetupIntent,
//   createStripeSetupSession, createStripePaymentSession, updateStripeAccount,
//   detachPaymentMethod
//
// Active payment exports (legacy credits ledger, defined later in this file):
//   processPaymentRelease, processCancellation, resolveDisputeAdmin

// ── v10.1.0: Migrate existing providers to provider_listings collection ──────
// Admin-only callable. Creates a provider_listings doc (identityIndex: 0) for
// every provider who doesn't have one yet. Idempotent — safe to call multiple times.
exports.migrateProvidersToListings = onCall(async (request) => {
    if (!(await isAdminCaller(request))) {
        throw new HttpsError("permission-denied", "Admin only");
    }

    const db = admin.firestore();
    let migrated = 0;
    let skipped = 0;
    let pageToken = null;

    // Process in batches of 200
    do {
        let query = db.collection("users")
            .where("isProvider", "==", true)
            .orderBy("__name__")
            .limit(200);
        if (pageToken) query = query.startAfter(pageToken);

        const snap = await query.get();
        if (snap.empty) break;
        pageToken = snap.docs[snap.docs.length - 1];

        const batch = db.batch();
        let batchCount = 0;

        for (const doc of snap.docs) {
            const u = doc.data();
            const uid = doc.id;

            // Skip if already migrated
            if (u.listingIds && u.listingIds.length > 0) {
                skipped++;
                continue;
            }

            // Skip if no serviceType
            const serviceType = u.serviceType || "";
            if (!serviceType) {
                skipped++;
                continue;
            }

            const listingRef = db.collection("provider_listings").doc();
            batch.set(listingRef, {
                uid,
                identityIndex: 0,
                // Denormalized shared fields
                name: u.name || u.fullName || "",
                profileImage: u.profileImage || "",
                isVerified: u.isVerified || false,
                isHidden: u.isHidden || false,
                isDemo: u.isDemo || false,
                isVolunteer: u.isVolunteer || false,
                isOnline: u.isOnline || false,
                isAnySkillPro: u.isAnySkillPro || false,
                isPromoted: u.isPromoted || false,
                profileBoostUntil: u.profileBoostUntil || null,
                latitude: u.latitude || null,
                longitude: u.longitude || null,
                geohash: u.geohash || null,
                // Identity-specific
                serviceType,
                parentCategory: u.parentCategory || "",
                subCategory: u.subCategory || "",
                aboutMe: u.aboutMe || "",
                pricePerHour: u.pricePerHour || 0,
                gallery: u.gallery || [],
                categoryDetails: u.categoryDetails || {},
                priceList: u.priceList || {},
                quickTags: u.quickTags || [],
                workingHours: u.workingHours || {},
                cancellationPolicy: u.cancellationPolicy || "flexible",
                // Ratings (carry over from user doc)
                rating: u.rating || 5.0,
                reviewsCount: u.reviewsCount || 0,
                // Metadata
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Update user doc with listing reference
            batch.update(doc.ref, {
                listingIds: [listingRef.id],
                activeIdentityCount: 1,
            });

            batchCount++;
            migrated++;
        }

        if (batchCount > 0) await batch.commit();
        console.log(`[Migration] Batch done: ${batchCount} migrated, ${skipped} skipped`);

    } while (pageToken && migrated < 5000); // safety cap

    // Backfill reviews with listingId
    let reviewsBackfilled = 0;
    const reviewSnap = await db.collection("reviews")
        .where("listingId", "==", null)
        .limit(500)
        .get();

    if (!reviewSnap.empty) {
        const reviewBatch = db.batch();
        for (const revDoc of reviewSnap.docs) {
            const rev = revDoc.data();
            const revieweeId = rev.revieweeId || rev.expertId;
            if (!revieweeId) continue;

            // Find the primary listing for this reviewee
            const listingSnap = await db.collection("provider_listings")
                .where("uid", "==", revieweeId)
                .where("identityIndex", "==", 0)
                .limit(1)
                .get();
            if (!listingSnap.empty) {
                reviewBatch.update(revDoc.ref, { listingId: listingSnap.docs[0].id });
                reviewsBackfilled++;
            }
        }
        if (reviewsBackfilled > 0) await reviewBatch.commit();
    }

    console.log(`[Migration] Complete: ${migrated} providers migrated, ${reviewsBackfilled} reviews backfilled`);
    return { migrated, skipped, reviewsBackfilled };
});

// ── One-shot CORS setup for Firebase Storage ────────────────────────────────
// Call ONCE from admin panel or browser: setCorsOnStorage({})
// Replaces the need for `gsutil cors set cors.json gs://bucket`
exports.setCorsOnStorage = onCall(async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required");
    // Admin check
    const userDoc = await admin.firestore().collection("users").doc(request.auth.uid).get();
    if (!userDoc.exists || userDoc.data().isAdmin !== true) {
        throw new HttpsError("permission-denied", "Admin only");
    }
    try {
        const bucket = admin.storage().bucket();
        await bucket.setCorsConfiguration([{
            origin: ["*"],
            method: ["GET", "HEAD"],
            maxAgeSeconds: 3600,
            responseHeader: ["Content-Type", "Content-Length", "Content-Range", "Range"],
        }]);
        console.log("[CORS] Successfully set CORS on storage bucket");
        return { success: true, bucket: bucket.name };
    } catch (e) {
        console.error("[CORS] Failed:", e.message);
        throw new HttpsError("internal", "CORS setup failed: " + e.message);
    }
});

// ── Backward-compat grouped export ───────────────────────────────────────────
// PHASE 2 NOTE: The legacy `payments.createProviderOnboarding` alias was
// removed alongside Stripe Connect. Old cached Flutter clients calling this
// endpoint will receive `not-found` and should be prompted to update.

// מספר ה-shards לכל מונה unreadCount — מפיץ כתיבות ומונע write contention
const NUM_SHARDS = 5;

// ── Financial Health: Claude Haiku cost tracking ──────────────────────────────
// claude-haiku-4-5-20251001 pricing (as of 2025):
//   Input:  $0.80  per million tokens → $0.0000008  / token
//   Output: $4.00  per million tokens → $0.000004   / token
const _COST_PER_INPUT_TOKEN  = 0.0000008;
const _COST_PER_OUTPUT_TOKEN = 0.000004;
const _KILL_SWITCH_DEFAULT   = 100; // $100 hard monthly limit

/** Increments system_stats/billing with the cost of one Claude call.
 *  Auto-resets on month change. Activates kill-switch if limit exceeded.
 *  Fire-and-forget: call as  _trackApiCost(db, i, o).catch(()=>{}) */
async function _trackApiCost(db, inputTokens, outputTokens) {
    const cost     = (inputTokens  * _COST_PER_INPUT_TOKEN)
                   + (outputTokens * _COST_PER_OUTPUT_TOKEN);
    const monthKey = new Date().toISOString().slice(0, 7); // "YYYY-MM"
    const ref      = db.collection("system_stats").doc("billing");
    try {
        await db.runTransaction(async (tx) => {
            const snap  = await tx.get(ref);
            const data  = snap.exists ? snap.data() : {};
            const isNew = !data.month_key || data.month_key !== monthKey;
            if (isNew) {
                tx.set(ref, {
                    month_key:                monthKey,
                    current_month_api_cost:   cost,
                    current_month_infra_cost: 0,
                    total_input_tokens:       inputTokens,
                    total_output_tokens:      outputTokens,
                    api_call_count:           1,
                    ai_kill_switch_active:    false,
                    budget_limit:             data.budget_limit    || 50,
                    kill_switch_limit:        data.kill_switch_limit || _KILL_SWITCH_DEFAULT,
                    last_updated:             admin.firestore.FieldValue.serverTimestamp(),
                });
            } else {
                const newCost   = (data.current_month_api_cost || 0) + cost;
                const killLimit = data.kill_switch_limit || _KILL_SWITCH_DEFAULT;
                tx.set(ref, {
                    current_month_api_cost: newCost,
                    total_input_tokens:     admin.firestore.FieldValue.increment(inputTokens),
                    total_output_tokens:    admin.firestore.FieldValue.increment(outputTokens),
                    api_call_count:         admin.firestore.FieldValue.increment(1),
                    ai_kill_switch_active:  newCost >= killLimit,
                    last_updated:           admin.firestore.FieldValue.serverTimestamp(),
                }, { merge: true });
            }
        });
    } catch (e) {
        console.warn("_trackApiCost: silent fail", e.message);
    }
}

/** Returns true if the AI kill-switch is NOT active.
 *  Fails open (returns true) on any read error so users are never blocked. */
async function _isAiEnabled(db) {
    try {
        const snap = await db.collection("system_stats").doc("billing").get();
        if (!snap.exists) return true;
        return snap.data().ai_kill_switch_active !== true;
    } catch (_) {
        return true;
    }
}

// QA: הפונקציה מאזינה ליצירת הודעה חדשה בתוך הצא'טים
// maxInstances + concurrency מאפשרים עד 100 * 500 = 50,000 בקשות במקביל ללא cold starts
exports.sendchatnotification = onDocumentCreated(
    {
      document: "chats/{roomId}/messages/{messageId}",
      // minInstances: 1 keeps one warm instance ready at all times,
      // eliminating cold-start latency (~800ms) on the hot notification path.
      // Cost: ~$1.50/mo for one always-on instance vs. UX degradation at scale.
      minInstances: 1,
      maxInstances: 100,
      concurrency: 500,
    },
    async (event) => {
    const snapshot = event.data;
    if (!snapshot) return null;

    const messageData = snapshot.data();
    const receiverId = messageData.receiverId;
    const senderId = messageData.senderId;
    const messageText = messageData.message || "";
    const type = messageData.type || 'text';

    // Each step is wrapped in its own try-catch so a failure in notifications
    // or FCM never blocks the critical metadata/unreadCount update.

    // ── Step 1: Update chat metadata + unreadCount (CRITICAL) ───────────
    // This is the most important step — it powers the BottomNav badge.
    // Uses Admin SDK (bypasses security rules) so arrayUnion works safely.
    try {
        if (senderId !== 'system' && receiverId) {
            const roomId = event.params.roomId;
            const chatDocRef = admin.firestore().collection('chats').doc(roomId);

            const shardIndex = Math.floor(Math.random() * NUM_SHARDS);
            const shardRef = chatDocRef
                .collection('unread_shards')
                .doc(`${receiverId}_${shardIndex}`);

            const metaBatch = admin.firestore().batch();

            metaBatch.set(shardRef, {
                count: admin.firestore.FieldValue.increment(1),
                uid: receiverId,
            }, { merge: true });

            const lastMessageText = type === 'text' ? messageText : `שלח/ה ${type}`;
            metaBatch.set(chatDocRef, {
                lastMessage: lastMessageText,
                lastMessageTime: admin.firestore.FieldValue.serverTimestamp(),
                lastSenderId: senderId,
                [`unreadCount_${receiverId}`]: admin.firestore.FieldValue.increment(1),
                users: admin.firestore.FieldValue.arrayUnion([senderId, receiverId]),
            }, { merge: true });

            await metaBatch.commit();
            console.log(`[Chat] Metadata updated: room=${roomId} shard=${shardIndex}`);
        }
    } catch (metaErr) {
        console.error(`[Chat] CRITICAL metadata update failed for room=${event.params.roomId}:`, metaErr);
    }

    // ── Step 2: Fetch sender/receiver profiles ──────────────────────────
    let senderName = 'הודעה חדשה';
    let receiverData = null;
    try {
        const senderSnap = await admin.firestore().collection('users').doc(senderId).get();
        senderName = senderSnap.exists
            ? (senderSnap.data().displayName || senderSnap.data().name || 'AnySkill')
            : 'הודעה חדשה';

        const receiverSnap = await admin.firestore().collection('users').doc(receiverId).get();
        if (!receiverSnap.exists) {
            console.log(`[Chat] Receiver ${receiverId} not found — metadata already updated`);
            return null;
        }
        receiverData = receiverSnap.data();
    } catch (profileErr) {
        console.error(`[Chat] Profile fetch failed:`, profileErr);
        return null; // can't send notification without profile data
    }

    // ── Step 3: Build notification body ─────────────────────────────────
    let notificationBody = messageText;
    if (type === 'image') notificationBody = '📷 שלח/ה לך תמונה';
    if (type === 'location') notificationBody = '📍 שיתפ/ה איתך מיקום';
    if (type === 'audio') notificationBody = '🎤 שלח/ה הודעה קולית';

    // ── Step 4: Save to notification inbox (non-blocking) ───────────────
    try {
        if (senderId !== 'system') {
            await admin.firestore().collection('notifications').add({
                userId: receiverId,
                title: senderName,
                body: notificationBody,
                type: 'chat',
                data: { senderId, roomId: event.params.roomId },
                isRead: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
    } catch (inboxErr) {
        console.error(`[Chat] Notification inbox write failed:`, inboxErr);
    }

    // ── Step 5: FCM push notification (best-effort) ─────────────────────
    try {
        const targetToken = receiverData.fcmToken || receiverData.deviceToken;
        if (!targetToken) {
            console.log(`[Chat] No FCM token for ${receiverId} — skipping push`);
            return null;
        }

        let badgeCount = 1;
        try {
            const chatSnap = await admin.firestore()
                .collection('chats').doc(event.params.roomId).get();
            badgeCount = (((chatSnap.data() || {})[`unreadCount_${receiverId}`]) || 0);
        } catch (_) { /* fallback to 1 */ }

        const messagePayload = {
            token: targetToken,
            notification: {
                title: senderName,
                body: notificationBody,
            },
            data: {
                senderId:   senderId,
                roomId:     event.params.roomId,
                chatRoomId: event.params.roomId,
                click_action: "FLUTTER_NOTIFICATION_CLICK",
                type: "chat",
            },
            android: {
                priority: "high",
                notification: { channelId: "anyskill_chats" },
            },
            apns: {
                headers: { "apns-priority": "10" },
                payload: { aps: { badge: badgeCount, sound: "default" } },
            },
            webpush: {
                notification: {
                    icon: "/icons/Icon-192.png",
                    badge: "/icons/Icon-192.png",
                    click_action: "https://anyskill-6fdf3.web.app",
                },
                fcm_options: { link: "https://anyskill-6fdf3.web.app" },
            },
        };

        await admin.messaging().send(messagePayload);
        console.log(`[Chat] Push sent to ${receiverId} from ${senderName}`);
    } catch (fcmErr) {
        // FCM failure must NEVER block the function — message is already delivered
        console.error(`[Chat] FCM push failed (non-blocking):`, fcmErr);
    }

    return null;
});

// ── New booking → notify expert + customer ────────────────────────────────
exports.sendbookingnotification = onDocumentCreated("jobs/{jobId}", async (event) => {
    const jobData  = event.data.data();
    const expertId = jobData.expertId;
    const customerId = jobData.customerId;
    if (!expertId) return null;

    const customerName = jobData.customerName || 'לקוח';
    const expertName   = jobData.expertName   || 'המומחה';
    const totalAmount  = jobData.totalAmount   || 0;
    let dateInfo = '';
    if (jobData.appointmentDate && jobData.appointmentTime) {
        const d = jobData.appointmentDate.toDate();
        dateInfo = ` — ${d.getDate()}/${d.getMonth() + 1} בשעה ${jobData.appointmentTime}`;
    }

    const jobId = event.params.jobId;

    // ── Helper: send push + write in-app notification ───────────────────
    async function notifyUser(userId, title, body, type) {
        try {
            const userSnap = await admin.firestore().collection('users').doc(userId).get();
            if (!userSnap.exists) {
                console.warn(`[Notify] User ${userId} not found in Firestore`);
                return;
            }
            const userData = userSnap.data();
            const token = userData.fcmToken || userData.deviceToken;
            const platform = userData.platform || 'unknown';

            console.log(`[Notify] ${type} → uid=${userId}, platform=${platform}, token=${token ? token.substring(0, 20) + '...' : 'NULL'}`);

            if (!token) {
                console.warn(`[Notify] No FCM token for ${userId} — push skipped (in-app only)`);
            }

            // Push notification (skip if no token)
            if (token) {
                await admin.messaging().send({
                    token,
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
                        notification: { icon: '/icons/Icon-192.png' },
                        fcm_options: { link: 'https://anyskill-6fdf3.web.app' },
                    },
                    data: { type, jobId },
                });
            }

            // In-app notification (always written, even if push fails)
            await admin.firestore().collection('notifications').add({
                userId,
                title,
                body,
                type,
                data: { jobId },
                isRead: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            console.log(`${type} notification sent to ${userId}`);
        } catch (error) {
            console.error(`Error sending ${type} notification to ${userId}:`, error);
        }
    }

    // ── 1. Notify expert: "You have a new booking!" ─────────────────────
    await notifyUser(
        expertId,
        'הזמנה חדשה! 🎉',
        `${customerName} הזמין/ה שירות${dateInfo}`,
        'new_booking'
    );

    // ── 2. Notify customer: "Your booking is confirmed!" ────────────────
    if (customerId) {
        const amountStr = totalAmount > 0 ? ` בסך ₪${Number(totalAmount).toFixed(0)}` : '';
        await notifyUser(
            customerId,
            'ההזמנה אושרה! ✅',
            `השירות עם ${expertName}${dateInfo} אושר${amountStr}. הכסף נעול באסקרו עד לסיום.`,
            'booking_confirmed'
        );
    }

    return null;
});

// ── Job status change → notify the relevant party ─────────────────────────
exports.sendjobstatusnotification = onDocumentUpdated("jobs/{jobId}", async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();

    if (before.status === after.status) return null;

    let targetUserId, title, body;

    if (after.status === 'expert_completed') {
        // Expert marked done → notify customer to release payment
        targetUserId = after.customerId;
        title = 'המומחה סיים! ✅';
        body  = `${after.expertName || 'המומחה'} סיים את העבודה. לחץ לשחרור התשלום.`;

    } else if (after.status === 'completed') {
        // Customer released payment → notify expert
        targetUserId = after.expertId;
        title = 'התשלום שוחרר! 💰';
        body  = `${after.customerName || 'הלקוח'} אישר את העבודה. הכסף נוסף לארנק שלך.`;

    } else {
        return null;
    }

    try {
        const userSnap = await admin.firestore().collection('users').doc(targetUserId).get();
        if (!userSnap.exists) return null;
        const token = userSnap.data().fcmToken || userSnap.data().deviceToken;
        if (!token) return null;

        await admin.messaging().send({
            token,
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
                notification: { icon: '/icons/Icon-192.png' },
                fcm_options: { link: 'https://anyskill-6fdf3.web.app' },
            },
            data: { type: 'job_status', jobId: event.params.jobId, status: after.status },
        });
        await admin.firestore().collection('notifications').add({
            userId: targetUserId,
            title,
            body,
            type: 'job_status',
            data: { jobId: event.params.jobId, status: after.status },
            isRead: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`Job status notification (${after.status}) sent to ${targetUserId}`);
    } catch (error) {
        console.error('Error sending job status notification:', error);
    }
    return null;
});

// ── Support ticket message → notify all admins ──────────────────────────────
// Fires when a user (non-admin) sends a message in a support ticket.
// Pushes a notification to every admin user so they can respond quickly.
exports.notifyAdminOnSupportMessage = onDocumentCreated(
    "support_tickets/{ticketId}/messages/{messageId}",
    async (event) => {
        const msgData  = event.data.data();
        // Skip if the message was sent by an admin (avoid notify-self loop)
        if (msgData.isAdmin === true) return null;

        const ticketId   = event.params.ticketId;
        const senderName = msgData.senderName || 'משתמש';
        const msgText    = (msgData.message || '').substring(0, 100);

        try {
            // Fetch all admin users
            const adminSnaps = await admin.firestore()
                .collection('users')
                .where('isAdmin', '==', true)
                .limit(10)
                .get();

            for (const adminDoc of adminSnaps.docs) {
                const token = adminDoc.data().fcmToken || adminDoc.data().deviceToken;

                // Push notification
                if (token) {
                    try {
                        await admin.messaging().send({
                            token,
                            notification: {
                                title: `📮 פנייה חדשה מ-${senderName}`,
                                body: msgText,
                            },
                            android: {
                                priority: "high",
                                notification: { channelId: "anyskill_default" },
                            },
                            apns: {
                                headers: { "apns-priority": "10" },
                                payload: { aps: { sound: "default", contentAvailable: 1 } },
                            },
                            webpush: {
                                notification: { icon: '/icons/Icon-192.png' },
                                fcm_options: { link: 'https://anyskill-6fdf3.web.app' },
                            },
                            data: { type: 'support_ticket', ticketId },
                        });
                    } catch (pushErr) {
                        console.warn(`Push failed for admin ${adminDoc.id}:`, pushErr.message);
                    }
                }

                // In-app notification
                await admin.firestore().collection('notifications').add({
                    userId:    adminDoc.id,
                    title:     `📮 פנייה חדשה מ-${senderName}`,
                    body:      msgText,
                    type:      'support_ticket',
                    data:      { ticketId },
                    isRead:    false,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
            }
            console.log(`Support notification sent to ${adminSnaps.docs.length} admins for ticket ${ticketId}`);
        } catch (error) {
            console.error('Error sending support notification:', error);
        }
        return null;
    }
);

// ── Callable: שחרור תשלום מאסקרו (Admin SDK — עוקף חוקי Firestore) ──────────
exports.processPaymentRelease = onCall(async (request) => {
    console.log('[PPR] ── START ──────────────────────────────────');

    // STEP 1: Auth check
    if (!request.auth) {
        console.error('[PPR] STEP1 FAIL: no auth');
        throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }
    console.log(`[PPR] STEP1 OK: callerUid=${request.auth.uid}`);

    // STEP 2: Input validation
    const { jobId, expertId, expertName, customerName, totalAmount } = request.data;
    console.log(`[PPR] STEP2 input: jobId=${jobId}, expertId=${expertId}, totalAmount=${totalAmount}, customerName=${customerName}, expertName=${expertName}`);
    if (!jobId || !expertId || totalAmount == null) {
        console.error('[PPR] STEP2 FAIL: missing required fields');
        throw new HttpsError('invalid-argument', 'jobId, expertId and totalAmount are required.');
    }
    console.log('[PPR] STEP2 OK: inputs valid');

    const db = admin.firestore();
    const jobRef = db.collection('jobs').doc(jobId);
    const expertRef = db.collection('users').doc(expertId);
    const adminSettingsRef = db.collection('admin').doc('admin').collection('settings').doc('settings');

    // STEP 3: Load & validate job
    let jobSnap;
    try {
        jobSnap = await jobRef.get();
    } catch (e) {
        console.error(`[PPR] STEP3 FAIL: could not read job — ${e.message}`);
        throw new HttpsError('internal', `Could not read job: ${e.message}`);
    }
    if (!jobSnap.exists) {
        console.error(`[PPR] STEP3 FAIL: job ${jobId} does not exist`);
        throw new HttpsError('not-found', 'Job not found.');
    }
    const jobData = jobSnap.data();
    console.log(`[PPR] STEP3 OK: job exists. status=${jobData.status}, customerId=${jobData.customerId}`);

    // STEP 4: Caller == customer?
    if (jobData.customerId !== request.auth.uid) {
        console.error(`[PPR] STEP4 FAIL: caller ${request.auth.uid} != customerId ${jobData.customerId}`);
        throw new HttpsError('permission-denied', 'Only the customer of this job can release payment.');
    }
    console.log('[PPR] STEP4 OK: caller is the customer');

    // STEP 5: Status check
    if (jobData.status !== 'expert_completed') {
        console.error(`[PPR] STEP5 FAIL: status='${jobData.status}', expected 'expert_completed'`);
        throw new HttpsError('failed-precondition', `Job status is '${jobData.status}', expected 'expert_completed'.`);
    }
    console.log('[PPR] STEP5 OK: status is expert_completed');

    // PRE-TRANSACTION: resolve category ref for bookingCount increment
    // (queries are not allowed inside transactions — must do this outside)
    let categoryRef = null;
    try {
        const expertSnapForCat = await expertRef.get();
        const serviceType = expertSnapForCat.exists
            ? (expertSnapForCat.data().serviceType || '') : '';
        if (serviceType) {
            const catSnap = await db.collection('categories')
                .where('name', '==', serviceType).limit(1).get();
            if (!catSnap.empty) categoryRef = catSnap.docs[0].ref;
        }
        console.log(`[PPR] PRE-TX: serviceType=${serviceType}, categoryRef=${categoryRef ? categoryRef.id : 'none'}`);
    } catch (e) {
        console.warn(`[PPR] PRE-TX: could not resolve category — ${e.message}`);
    }

    // STEP 6: Firestore transaction
    try {
        const customerRef = db.collection('users').doc(jobData.customerId);
        await db.runTransaction(async (tx) => {
            console.log('[PPR] STEP6 TX: reading adminSettings + expertData + customerData...');
            // Read all docs before any writes (Firestore transaction requirement)
            const [adminSnap, expertDataSnap, customerDataSnap, jobReReadSnap] = await Promise.all([
                tx.get(adminSettingsRef),
                tx.get(expertRef),
                tx.get(customerRef),
                tx.get(jobRef),
            ]);

            // Re-read job to get the freshest deposit fields
            const fresh = jobReReadSnap.exists ? jobReReadSnap.data() : jobData;
            const remainingAmount = roundNIS(Number(fresh.remainingAmount || 0));
            const isDepositJob = remainingAmount > 0;
            console.log(`[PPR] STEP6 TX: remainingAmount=${remainingAmount}, isDepositJob=${isDepositJob}`);

            // ── DEPOSIT-ONLY ESCROW (v12.1.0) ─────────────────────────────────
            // If the job was created with a deposit (paidAtBooking < totalAmount),
            // the customer must now cover the remainder. Their balance must
            // be sufficient — otherwise we abort and the customer must top up.
            if (isDepositJob) {
                const customerBalance = customerDataSnap.exists
                    ? Number(customerDataSnap.data().balance || 0)
                    : 0;
                if (customerBalance < remainingAmount) {
                    throw new HttpsError(
                        'failed-precondition',
                        `יתרה לא מספיקה לתשלום היתרה (₪${remainingAmount}). אנא טען יתרה.`
                    );
                }
                console.log(`[PPR] STEP6 TX: charging deposit remainder ₪${remainingAmount} from customer ${jobData.customerId}`);
                tx.update(customerRef, {
                    balance: admin.firestore.FieldValue.increment(-remainingAmount),
                });
                // Wallet log for the customer
                tx.set(db.collection('transactions').doc(), {
                    userId: jobData.customerId,
                    amount: -remainingAmount,
                    title: `יתרת תשלום — ${expertName || 'מומחה'}`,
                    type: 'escrow',
                    jobId,
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                });
            }

            // Per-provider commission takes priority; fall back to global setting
            const customCommission = expertDataSnap.exists
                ? expertDataSnap.data().customCommission
                : undefined;
            const globalFee = adminSnap.exists ? (adminSnap.data().feePercentage ?? 0.10) : 0.10;
            const feePercentage = (customCommission != null) ? customCommission : globalFee;

            const feeAmount   = roundNIS(totalAmount * feePercentage);
            const netToExpert = roundNIS(totalAmount - feeAmount);
            console.log(`[PPR] STEP6 TX: feePercentage=${feePercentage} (${customCommission != null ? 'custom' : 'global'}), feeAmount=${feeAmount}, netToExpert=${netToExpert}`);

            // ── Edge case: provider deleted their account mid-transaction ──────
            // Firestore tx.update() throws DOCUMENT_NOT_FOUND on a missing doc.
            // We still complete the job and record earnings, but credit a
            // 'deleted_expert_funds' holding doc instead of a missing user doc.
            const expertExists = expertDataSnap.exists;
            if (!expertExists) {
                console.warn(`[PPR] STEP6 TX: expert ${expertId} not found — crediting holding account`);
                tx.set(db.collection('deleted_expert_funds').doc(expertId), {
                    expertId,
                    pendingBalance: admin.firestore.FieldValue.increment(netToExpert),
                    lastJobId:      jobId,
                    updatedAt:      admin.firestore.FieldValue.serverTimestamp(),
                }, { merge: true });
            }

            console.log('[PPR] STEP6 TX: updating job...');
            tx.update(jobRef, {
                status: 'completed',
                completedAt: admin.firestore.FieldValue.serverTimestamp(),
                feeAmount,
                netAmountForExpert: netToExpert,
                // Mark deposit balance as fully paid
                ...(isDepositJob ? {
                    remainingAmount: 0,
                    remainderPaidAt: admin.firestore.FieldValue.serverTimestamp(),
                    totalPaidByCustomer: totalAmount,
                } : {}),
                ...(expertExists ? {} : { expertAccountDeleted: true }),
            });

            if (expertExists) {
                console.log('[PPR] STEP6 TX: updating expert balance + orderCount...');
                tx.update(expertRef, {
                    balance:     admin.firestore.FieldValue.increment(netToExpert),
                    orderCount:  admin.firestore.FieldValue.increment(1),
                });
            }

            // Increment category bookingCount (powers Trending badges on Discover)
            if (categoryRef) {
                console.log(`[PPR] STEP6 TX: incrementing bookingCount on category ${categoryRef.id}`);
                tx.set(categoryRef, {
                    bookingCount: admin.firestore.FieldValue.increment(1),
                }, { merge: true });
            }

            console.log('[PPR] STEP6 TX: updating admin settings...');
            tx.set(adminSettingsRef, {
                totalPlatformBalance: admin.firestore.FieldValue.increment(feeAmount),
                lastFinanceUpdate: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });

            console.log('[PPR] STEP6 TX: writing platform_earnings...');
            tx.set(db.collection('platform_earnings').doc(), {
                jobId,
                amount: feeAmount,
                customerName: customerName || 'לקוח',
                expertName:   expertName   || 'מומחה',
                description:  `${customerName || 'לקוח'} ➔ ${expertName || 'מומחה'}`,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
            });

            console.log('[PPR] STEP6 TX: writing transaction record...');
            tx.set(db.collection('transactions').doc(), {
                userId: expertId,
                amount: netToExpert,
                title: `קיבלת תשלום — ${customerName || 'לקוח'}`,
                type: 'earning',
                clientName: customerName || 'לקוח',
                jobId,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
            });

            console.log('[PPR] STEP6 TX: all writes queued, committing...');
        });

        console.log(`[PPR] STEP6 OK: transaction committed. job=${jobId} completed`);
        console.log('[PPR] ── END (success) ────────────────────────────');
        return { success: true };

    } catch (e) {
        console.error(`[PPR] STEP6 FAIL: transaction threw — code=${e.code} message=${e.message}`);
        console.error('[PPR] full error:', JSON.stringify(e, Object.getOwnPropertyNames(e)));
        throw new HttpsError('internal', `Payment release failed: ${e.message}`);
    }
});

// ── Callable: מחיקת משתמש (Admin SDK — דורש הרשאת admin) ────────────────────
exports.deleteUser = onCall(async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }

    // v9.7.0: Admin check via Firestore isAdmin flag only (no hardcoded email)
    if (!(await isAdminCaller(request))) {
        throw new HttpsError('permission-denied', 'Caller is not an admin.');
    }

    const { uid } = request.data;
    if (!uid) throw new HttpsError('invalid-argument', 'uid is required.');

    // מחיקת חשבון ה-Auth (user-not-found = כבר נמחק, לא שגיאה קשה)
    try {
        await admin.auth().deleteUser(uid);
    } catch (e) {
        if (e.code !== 'auth/user-not-found') {
            throw new HttpsError('internal', `Auth deletion failed: ${e.message}`);
        }
    }

    // מחיקת מסמך ה-Firestore
    await admin.firestore().collection('users').doc(uid).delete();

    console.log(`Admin ${request.auth.uid} deleted user ${uid}`);
    return { success: true };
});

// ── Anticipatory Design ── Recurring services list ─────────────────────────────
const RECURRING_SERVICES = ['ניקיון', 'גינון', 'כושר ואימון', 'הדברה', 'שרברבות'];

// When a job completes for a recurring service → schedule a rebook reminder in 30 days
exports.scheduleRebookReminder = onDocumentUpdated("jobs/{jobId}", async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    if (before.status === after.status || after.status !== 'completed') return null;

    const customerId   = after.customerId;
    const expertId     = after.expertId;
    const expertName   = after.expertName   || 'המומחה';
    const customerName = after.customerName || 'הלקוח';
    if (!customerId || !expertId) return null;

    // Fetch expert serviceType (not stored on job doc)
    const expertSnap = await admin.firestore().collection('users').doc(expertId).get();
    if (!expertSnap.exists) return null;
    const serviceType = expertSnap.data().serviceType || '';
    if (!RECURRING_SERVICES.includes(serviceType)) return null;

    const sendAt = new Date();
    sendAt.setDate(sendAt.getDate() + 30);

    await admin.firestore().collection('scheduled_reminders').add({
        type:         'rebook',
        customerId,
        expertId,
        expertName,
        customerName,
        serviceType,
        jobId:        event.params.jobId,
        sendAt:       admin.firestore.Timestamp.fromDate(sendAt),
        status:       'pending',
        createdAt:    admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`Rebook reminder scheduled for ${customerName} → ${expertName} (${serviceType}) in 30 days`);
    return null;
});

// Daily cron at 09:00 IST — sends any pending rebook reminders whose sendAt has passed
exports.sendRebookReminders = onSchedule(
    { schedule: '0 9 * * *', timeZone: 'Asia/Jerusalem' },
    async () => {
        const db  = admin.firestore();
        const now = new Date();

        const snap = await db.collection('scheduled_reminders')
            .where('status',  '==', 'pending')
            .where('sendAt',  '<=', admin.firestore.Timestamp.fromDate(now))
            .limit(100)
            .get();

        if (snap.empty) {
            console.log('sendRebookReminders: no pending reminders');
            return;
        }

        const batch = db.batch();

        for (const doc of snap.docs) {
            const r = doc.data();
            try {
                // Fetch customer FCM token
                const customerSnap = await db.collection('users').doc(r.customerId).get();
                if (!customerSnap.exists) { batch.update(doc.ref, { status: 'skipped_no_user' }); continue; }
                const token = customerSnap.data().fcmToken || customerSnap.data().deviceToken;
                if (!token)  { batch.update(doc.ref, { status: 'skipped_no_token' }); continue; }

                const title = `${r.customerName}, הגיע הזמן ל${r.serviceType} שוב! 🏠`;
                const body  = `לפני 30 ימים הזמנת את ${r.expertName}. הזמן שוב בלחיצה אחת!`;

                await admin.messaging().send({
                    token,
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
                        notification: { icon: '/icons/Icon-192.png', badge: '/icons/Icon-192.png' },
                        fcm_options:  { link: 'https://anyskill-6fdf3.web.app' },
                    },
                    data: { type: 'rebook_reminder', expertId: r.expertId, expertName: r.expertName },
                });

                // Save to notification inbox
                await db.collection('notifications').add({
                    userId:    r.customerId,
                    title,
                    body,
                    type:      'rebook_reminder',
                    data:      { expertId: r.expertId, expertName: r.expertName, jobId: r.jobId },
                    isRead:    false,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });

                batch.update(doc.ref, { status: 'sent', sentAt: admin.firestore.FieldValue.serverTimestamp() });
                console.log(`Rebook reminder sent to ${r.customerName} for ${r.expertName}`);
            } catch (e) {
                console.error(`Rebook reminder error for ${r.customerId}:`, e.message);
                batch.update(doc.ref, { status: 'error', error: e.message });
            }
        }

        await batch.commit();
        console.log(`sendRebookReminders: processed ${snap.size} reminders`);
    }
);

// ── Gamification helpers ───────────────────────────────────────────────────────
// Reads level thresholds from settings_gamification/app_levels (admin-configurable).
// Falls back to silver=500, gold=2000 when the doc doesn't exist yet.
async function _awardXpDynamic(uid, points, reason) {
    const db         = admin.firestore();
    const levelsSnap = await db.collection('settings_gamification').doc('app_levels').get();
    const levels     = levelsSnap.data() || {};
    const silverThr  = typeof levels.silver === 'number' ? levels.silver : 500;
    const goldThr    = typeof levels.gold   === 'number' ? levels.gold   : 2000;
    const userRef    = db.collection('users').doc(uid);

    await db.runTransaction(async (tx) => {
        const snap = await tx.get(userRef);
        if (!snap.exists) return;
        const data      = snap.data();
        const currentXp = typeof data.current_xp === 'number' ? data.current_xp
                        : typeof data.xp          === 'number' ? data.xp : 0;
        const finalXp   = Math.max(0, currentXp + points);
        const level     = finalXp >= goldThr  ? 'gold'
                        : finalXp >= silverThr ? 'silver'
                        :                       'bronze';
        tx.update(userRef, { xp: finalXp, current_xp: finalXp, level });
    });
    console.log(`XP: ${points >= 0 ? '+' : ''}${points} to ${uid} for ${reason}`);
}

// ── Job completed → +100 XP (or +300 XP for volunteer jobs) ─────────────────
exports.awardXpJobCompleted = onDocumentUpdated("jobs/{jobId}", async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    if (before.status === after.status) return null;
    if (after.status !== 'completed')   return null;
    const expertId = after.expertId;
    if (!expertId) return null;

    const isVolunteerJob = after.isVolunteer === true;

    try {
        if (isVolunteerJob) {
            // 3× XP multiplier for volunteer jobs
            await _awardXpDynamic(expertId, 300, 'volunteer_job_completed');

            // Track volunteer task counter + award gold badge at 5
            const db      = admin.firestore();
            const userRef = db.collection('users').doc(expertId);
            await db.runTransaction(async (tx) => {
                const snap  = await tx.get(userRef);
                if (!snap.exists) return;
                const data  = snap.data();
                const count = (data.volunteerTasksCompleted ?? 0) + 1;
                const update = { volunteerTasksCompleted: count };
                if (count >= 5) update.volunteerBadge = 'gold';
                tx.update(userRef, update);
            });

            // Notify the expert
            await db.collection('notifications').add({
                userId:    expertId,
                title:     '🌟 3× XP על עזרה לקהילה!',
                body:      'קיבלת 300 XP על עזרה לקהילה! המשך כך ❤️',
                type:      'volunteer_xp',
                isRead:    false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        } else {
            await _awardXpDynamic(expertId, 100, 'job_completed');
        }
    } catch (e) {
        console.error('XP job_completed error:', e);
    }
    return null;
});

// ── 5-star review → +50 XP to expert ─────────────────────────────────────────
exports.awardXpFiveStarReview = onDocumentCreated("reviews/{reviewId}", async (event) => {
    const review = event.data.data();
    if (!review || review.rating !== 5) return null;
    const expertId = review.expertId;
    if (!expertId) return null;
    try {
        await _awardXpDynamic(expertId, 50, 'five_star_review');
    } catch (e) {
        console.error('XP five_star_review error:', e);
    }
    return null;
});

// ── Quick response <5 min → +25 XP to provider ───────────────────────────────
exports.awardXpQuickResponse = onDocumentCreated(
    { document: "chats/{roomId}/messages/{messageId}", maxInstances: 50 },
    async (event) => {
        const msg = event.data.data();
        const senderId   = msg.senderId;
        const receiverId = msg.receiverId;
        if (!senderId || !receiverId || senderId === 'system') return null;

        const db = admin.firestore();

        // Only award XP when the sender is a provider
        const senderSnap = await db.collection('users').doc(senderId).get();
        if (!senderSnap.exists || !senderSnap.data().isProvider) return null;

        // Check this is the provider's FIRST message in this room
        // (the trigger doc is already written, so limit(2) → size>1 means they replied before)
        const senderMsgsSnap = await db
            .collection('chats').doc(event.params.roomId)
            .collection('messages')
            .where('senderId', '==', senderId)
            .limit(2)
            .get();
        if (senderMsgsSnap.size > 1) return null;

        // Find client's most recent message before this response
        const clientMsgsSnap = await db
            .collection('chats').doc(event.params.roomId)
            .collection('messages')
            .where('senderId', '==', receiverId)
            .orderBy('timestamp', 'desc')
            .limit(1)
            .get();
        if (clientMsgsSnap.empty) return null;

        const clientTs  = clientMsgsSnap.docs[0].data().timestamp?.toDate();
        const providerTs = msg.timestamp?.toDate() || new Date();
        if (!clientTs) return null;

        const diffMins = (providerTs - clientTs) / 60000;
        if (diffMins < 0 || diffMins > 5) return null;

        try {
            await _awardXp(senderId, 25, 'quick_response');
        } catch (e) {
            console.error('XP quick_response error:', e);
        }
        return null;
    }
);

// ── Callable: סימון הודעות כנקראו (Admin SDK — ללא מגבלות client) ──────────────
// מוחלף על פעולת batch כבדה בצד הלקוח. מאפס shards + שדה מדנורמלי + isRead
exports.processMarkAsRead = onCall({ minInstances: 1, concurrency: 80 }, async (request) => {
    // אימות: רק המשתמש עצמו יכול לאפס את המונה שלו
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }

    const { chatRoomId, userId } = request.data;

    if (request.auth.uid !== userId) {
        throw new HttpsError('permission-denied', 'You can only mark your own messages as read.');
    }

    if (!chatRoomId || !userId) {
        throw new HttpsError('invalid-argument', 'chatRoomId and userId are required.');
    }

    const db = admin.firestore();
    const chatDocRef = db.collection('chats').doc(chatRoomId);

    try {
        // 1. שליפת הודעות שלא נקראו — מוגבל ל-100 למניעת batch גדול מדי
        const unreadSnap = await db
            .collection('chats').doc(chatRoomId)
            .collection('messages')
            .where('receiverId', '==', userId)
            .where('isRead', '==', false)
            .limit(100)
            .get();

        const batch = db.batch();

        // 2. סימון כל הודעה כנקראה
        unreadSnap.docs.forEach(doc => batch.update(doc.ref, { isRead: true }));

        // 3. איפוס כל NUM_SHARDS ה-shards של המשתמש
        for (let i = 0; i < NUM_SHARDS; i++) {
            const shardRef = chatDocRef
                .collection('unread_shards')
                .doc(`${userId}_${i}`);
            batch.set(shardRef, { count: 0, uid: userId }, { merge: true });
        }

        // 4. איפוס השדה המדנורמלי בכתב השיחה
        batch.update(chatDocRef, { [`unreadCount_${userId}`]: 0 });

        await batch.commit();

        console.log(`QA: processMarkAsRead — ${unreadSnap.size} messages marked, shards reset for ${userId} in ${chatRoomId}`);
        return { success: true, markedCount: unreadSnap.size };

    } catch (error) {
        console.error('QA Error - processMarkAsRead:', error);
        throw new HttpsError('internal', `Mark-as-read failed: ${error.message}`);
    }
});

// ── Receipt Email — triggered when job reaches 'completed' ───────────────
// Writes to the `mail` collection consumed by the Firebase Trigger Email
// extension (https://extensions.dev/extensions/firebase/firestore-send-email).
// Install the extension with collection path = "mail" to enable delivery.

exports.sendReceiptEmail = onDocumentUpdated(
    { document: 'jobs/{jobId}', maxInstances: 20 },
    async (event) => {
        const before = event.data.before.data();
        const after  = event.data.after.data();

        // Only fire once: when status transitions to 'completed'
        if (before.status === 'completed' || after.status !== 'completed') return null;

        const db    = admin.firestore();
        const jobId = event.params.jobId;

        // Sanitise all user-supplied strings before interpolating into HTML.
        // Prevents XSS payloads in names from appearing in email clients.
        const _esc = (s) => (s || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');

        // ── Resolve email addresses ──────────────────────────────────────
        const [customerSnap, expertSnap] = await Promise.all([
            db.collection('users').doc(after.customerId).get(),
            db.collection('users').doc(after.expertId).get(),
        ]);

        const customerEmail = customerSnap.data()?.email;
        const expertEmail   = expertSnap.data()?.email;
        const expertTaxId   = expertSnap.data()?.taxId || '';

        // Per-user opt-out: default true (backwards compatible — existing
        // users keep receiving invoices until they explicitly turn it off).
        const customerWantsEmail = customerSnap.data()?.receiveEmailReceipts !== false;
        const expertWantsEmail   = expertSnap.data()?.receiveEmailReceipts !== false;

        const total      = after.totalPaidByCustomer || 0;
        const commission = after.commissionAmount    || 0;
        const net        = after.netAmountForExpert  || (total - commission);
        const feePct     = total > 0 ? Math.round((commission / total) * 100) : 0;
        const receiptNum = jobId.substring(0, 8).toUpperCase();

        const apptDate = after.appointmentDate?.toDate
            ? after.appointmentDate.toDate().toLocaleDateString('he-IL')
            : '—';
        const apptTime  = after.appointmentTime || '';
        const dateLabel = apptTime ? `${apptDate} · ${apptTime}` : apptDate;

        // ── Shared HTML receipt template ─────────────────────────────────
        const receiptHtml = (recipientType) => `
<!DOCTYPE html>
<html dir="rtl" lang="he">
<head><meta charset="UTF-8">
<style>
  body { font-family: Arial, sans-serif; background: #f5f7fa; margin: 0; padding: 20px; direction: rtl; }
  .card { background: #fff; border-radius: 16px; max-width: 520px; margin: 0 auto; overflow: hidden; box-shadow: 0 4px 20px rgba(0,0,0,.08); }
  .header { background: linear-gradient(135deg,#1a1a2e,#16213e); color: #fff; padding: 24px 28px; }
  .header h1 { margin: 0 0 4px; font-size: 22px; }
  .header p  { margin: 0; color: rgba(255,255,255,.6); font-size: 12px; }
  .body   { padding: 24px 28px; }
  .row    { display: flex; justify-content: space-between; margin-bottom: 10px; font-size: 14px; }
  .row .label { color: #888; }
  .divider { border: none; border-top: 1px solid #eee; margin: 16px 0; }
  .total  { background: #1a1a2e; color: #fff; border-radius: 12px; padding: 14px 18px; display: flex; justify-content: space-between; align-items: center; margin-top: 10px; }
  .total .amount { font-size: 22px; font-weight: 900; }
  .badge  { display: inline-block; background: #ecfdf5; color: #065f46; border: 1px solid #6ee7b7; border-radius: 20px; padding: 5px 14px; font-size: 12px; font-weight: bold; margin-top: 16px; }
  .note   { font-size: 11px; color: #aaa; margin-top: 16px; line-height: 1.5; }
  .footer { text-align: center; padding: 16px; background: #f9fafb; color: #bbb; font-size: 11px; }
</style>
</head>
<body>
<div class="card">
  <div class="header">
    <div style="display:flex;justify-content:space-between;align-items:flex-start">
      <div style="text-align:left">
        <div style="font-size:11px;color:rgba(255,255,255,.5);font-family:monospace">#${receiptNum}</div>
        <div style="font-size:11px;color:rgba(255,255,255,.4)">${new Date().toLocaleDateString('he-IL')}</div>
      </div>
      <div>
        <h1>AnySkill</h1>
        <p>קבלה דיגיטלית${recipientType === 'expert' ? ' — ספק' : ' — לקוח'}</p>
      </div>
    </div>
  </div>
  <div class="body">
    <div class="row"><span class="label">לקוח</span><span><strong>${_esc(after.customerName) || '—'}</strong></span></div>
    <div class="row"><span class="label">נותן שירות</span><span><strong>${_esc(after.expertName) || '—'}</strong></span></div>
    <div class="row"><span class="label">תאריך שירות</span><span>${_esc(dateLabel)}</span></div>
    ${expertTaxId ? `<div class="row"><span class="label">ח.פ / ת.ז ספק</span><span>${_esc(expertTaxId)}</span></div>` : ''}
    <hr class="divider"/>
    <div class="row"><span class="label">מחיר שירות</span><span>₪${net.toFixed(2)}</span></div>
    <div class="row" style="color:#aaa"><span class="label">עמלת פלטפורמה (${feePct}%)</span><span>₪${commission.toFixed(2)}</span></div>
    <div class="total">
      <span class="amount">₪${total.toFixed(2)}</span>
      <span style="color:rgba(255,255,255,.7);font-size:13px">סה"כ שולם</span>
    </div>
    <div style="text-align:center"><span class="badge">✓ העסקה הושלמה בהצלחה</span></div>
    <p class="note">מסמך זה הוא אישור עסקה ואינו חשבונית מס רשמית.</p>
  </div>
  <div class="footer">AnySkill — עסקאות מאובטחות &bull; מספר עסקה: ${receiptNum}</div>
</div>
</body></html>`;

        const batch = db.batch();

        // Email to customer (skip if opted out)
        const sendToCustomer = customerEmail && customerWantsEmail;
        if (sendToCustomer) {
            batch.set(db.collection('mail').doc(), {
                to:      [customerEmail],
                message: {
                    subject: `קבלה על שירות מ-${_esc(after.expertName)} — AnySkill #${receiptNum}`,
                    html:    receiptHtml('customer'),
                },
            });
        }

        // Email to expert (shows net amount) — skip if opted out
        const sendToExpert = expertEmail && expertWantsEmail;
        if (sendToExpert) {
            batch.set(db.collection('mail').doc(), {
                to:      [expertEmail],
                message: {
                    subject: `סיכום עסקה עם ${_esc(after.customerName)} — AnySkill #${receiptNum}`,
                    html:    receiptHtml('expert'),
                },
            });
        }

        if (sendToCustomer || sendToExpert) {
            await batch.commit();
            console.log(`sendReceiptEmail: queued for job ${jobId} (customer=${sendToCustomer}, expert=${sendToExpert})`);
        } else {
            console.log(`sendReceiptEmail: skipped for job ${jobId} — no emails or both opted out`);
        }
        return null;
    }
);

// ── VIP Subscription ──────────────────────────────────────────────────────
// Callable: deducts ₪99 from balance and activates isPromoted for 30 days.

exports.activateVipSubscription = onCall(async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Not authenticated');

    const db       = admin.firestore();
    const userRef  = db.collection('users').doc(uid);
    const txRef    = db.collection('transactions').doc();
    const VIP_PRICE = 99;
    const VIP_DAYS  = 30;

    await db.runTransaction(async (tx) => {
        const userDoc = await tx.get(userRef);
        if (!userDoc.exists) throw new HttpsError('not-found', 'User not found');

        const balance = userDoc.data()?.balance ?? 0;
        if (balance < VIP_PRICE) {
            throw new HttpsError(
                'failed-precondition',
                `יתרה לא מספיקה. נדרש ₪${VIP_PRICE}, יש ₪${balance}`
            );
        }

        const expiryDate = new Date();
        expiryDate.setDate(expiryDate.getDate() + VIP_DAYS);

        tx.update(userRef, {
            balance:              admin.firestore.FieldValue.increment(-VIP_PRICE),
            isPromoted:           true,
            promotionExpiryDate:  admin.firestore.Timestamp.fromDate(expiryDate),
        });

        tx.set(txRef, {
            userId:    uid,
            amount:    -VIP_PRICE,
            title:     `מנוי VIP — חשיפה מוגברת (${VIP_DAYS} יום)`,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            type:      'vip_subscription',
        });
    });

    console.log(`VIP activated for ${uid} for ${VIP_DAYS} days`);
    return { success: true };
});

// ── VIP Expiry — daily cron at 00:30 IST ─────────────────────────────────
// Clears isPromoted for any provider whose promotionExpiryDate has passed.

exports.expireVipSubscriptions = onSchedule(
    { schedule: '30 0 * * *', timeZone: 'Asia/Jerusalem' },
    async (_event) => {
        const db  = admin.firestore();
        const now = admin.firestore.Timestamp.now();

        const expired = await db.collection('users')
            .where('isPromoted',          '==', true)
            .where('promotionExpiryDate', '<=', now)
            .get();

        if (expired.empty) {
            console.log('expireVipSubscriptions: no expired VIPs');
            return;
        }

        const batch = db.batch();
        for (const doc of expired.docs) {
            batch.update(doc.ref, { isPromoted: false });
        }
        await batch.commit();
        console.log(`expireVipSubscriptions: cleared ${expired.size} expired VIP(s)`);
    }
);

// ════════════════════════════════════════════════════════════════════════════
// RETENTION & ENGAGEMENT SYSTEM
// ════════════════════════════════════════════════════════════════════════════

// ── Write a "completed_works" doc when a job finishes (Inspiration Feed) ──────
// Powers the _InspirationFeed widget in search_page.dart.
// Keeps only: expertId, expertName, serviceType, coverImage, city, completedAt.

exports.writeCompletedWork = onDocumentUpdated(
    { document: "jobs/{jobId}", maxInstances: 10 },
    async (event) => {
        const before = event.data.before.data();
        const after  = event.data.after.data();
        if (before.status === 'completed' || after.status !== 'completed') return null;

        const expertId = after.expertId;
        if (!expertId) return null;

        const db = admin.firestore();
        try {
            const expertSnap = await db.collection('users').doc(expertId).get();
            if (!expertSnap.exists) return null;
            const expertData = expertSnap.data();

            await db.collection('completed_works').add({
                expertId,
                expertName:   after.expertName  || expertData.name || 'מומחה',
                serviceType:  expertData.serviceType || '',
                coverImage:   expertData.profileImage || '',
                city:         expertData.city || '',
                rating:       expertData.rating || 5.0,
                completedAt:  admin.firestore.FieldValue.serverTimestamp(),
            });
            console.log(`Inspiration Feed: completed_work written for expert ${expertId}`);
        } catch (e) {
            console.error('writeCompletedWork error:', e);
        }
        return null;
    }
);

// ── Geo-completion notifications — notify nearby users when a job finishes ──
// Sends up to 15 push notifications to customers in the same city as the expert.
// Throttled: each user receives at most 1 geo-notification per 6 hours.

exports.sendGeoCompletionNotifications = onDocumentUpdated(
    { document: "jobs/{jobId}", maxInstances: 5 },
    async (event) => {
        const before = event.data.before.data();
        const after  = event.data.after.data();
        if (before.status === 'completed' || after.status !== 'completed') return null;

        const expertId = after.expertId;
        if (!expertId) return null;

        const db = admin.firestore();
        try {
            const expertSnap = await db.collection('users').doc(expertId).get();
            if (!expertSnap.exists) return null;
            const expertData  = expertSnap.data();
            const city        = expertData.city        || '';
            const serviceType = expertData.serviceType || '';
            const expertName  = expertData.name        || 'מומחה';
            if (!city) return null;

            // Find up to 15 nearby customers (non-providers)
            const nearbySnap = await db.collection('users')
                .where('city', '==', city)
                .where('isProvider', '==', false)
                .limit(15)
                .get();
            if (nearbySnap.empty) return null;

            const sixHoursAgo = new Date(Date.now() - 6 * 3600 * 1000);
            const title = `מומחה מוביל סיים עבודה ב${city}! 📍`;
            const body  = `${expertName} (${serviceType}) זמין עכשיו לשירות נוסף.`;

            const sends = nearbySnap.docs
                .filter(d => {
                    if (d.id === expertId || d.id === after.customerId) return false;
                    const lastNotify = d.data().geoNotifyLastAt?.toDate();
                    if (lastNotify && lastNotify > sixHoursAgo) return false;
                    return !!(d.data().fcmToken || d.data().deviceToken);
                })
                .map(async d => {
                    const token = d.data().fcmToken || d.data().deviceToken;
                    try {
                        await admin.messaging().send({
                            token,
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
                                notification: { icon: '/icons/Icon-192.png' },
                                fcm_options: { link: 'https://anyskill-6fdf3.web.app' },
                            },
                            data: { type: 'geo_nearby', expertId, city },
                        });
                        const batch = db.batch();
                        batch.set(db.collection('notifications').doc(), {
                            userId: d.id, title, body, type: 'geo_nearby',
                            data: { expertId, city, serviceType },
                            isRead: false,
                            createdAt: admin.firestore.FieldValue.serverTimestamp(),
                        });
                        batch.update(d.ref, {
                            geoNotifyLastAt: admin.firestore.FieldValue.serverTimestamp(),
                        });
                        await batch.commit();
                    } catch (e) {
                        console.error(`Geo notify error for ${d.id}:`, e.message);
                    }
                });

            await Promise.all(sends);
            console.log(`Geo notifications sent to ${sends.length} users in ${city}`);
        } catch (e) {
            console.error('sendGeoCompletionNotifications error:', e);
        }
        return null;
    }
);

// ── Monthly seasonal notifications (1st of each month, 10:00 IST) ────────────
// Sends contextual push about season-relevant services to all users with tokens.
// Users can opt out via users/{uid}.disableSeasonalNotifs = true.

const SEASONAL_MAP = {
    2:  { title: 'האביב כבר כאן! 🌸', body: 'הגיע הזמן לניקיון מזגן, גינון ורענון הבית.' },
    3:  { title: 'מוכן לקיץ? ☀️',     body: 'קבל הצעות על שיפוץ, צביעה וריהוט חדש.' },
    5:  { title: 'קיץ חם בפתח! 🏖️',   body: 'בדוק שהמזגן שלך מוכן לגל החום הבא.' },
    8:  { title: 'הסתיו הגיע 🍂',      body: 'זמן מצוין להכין את הבית לחורף — שרברב, חשמלאי ועוד.' },
    10: { title: 'החורף מתקרב ❄️',     body: 'דאג לחימום, בידוד וצנרת לפני הגשמים.' },
};

exports.sendSeasonalNotifications = onSchedule(
    { schedule: '0 10 1 * *', timeZone: 'Asia/Jerusalem', maxInstances: 1 },
    async () => {
        const db    = admin.firestore();
        const month = new Date().getMonth();
        const seasonal = SEASONAL_MAP[month];
        if (!seasonal) {
            console.log('sendSeasonalNotifications: no campaign for month', month);
            return;
        }

        const { title, body } = seasonal;
        let totalSent = 0;
        let lastDoc   = null;

        // Paginate through all users in batches of 500
        do {
            let query = db.collection('users').orderBy('__name__').limit(500);
            if (lastDoc) query = query.startAfter(lastDoc);

            const snap = await query.get();
            if (snap.empty) break;

            for (const doc of snap.docs) {
                const userData = doc.data();
                const token    = userData.fcmToken || userData.deviceToken;
                if (!token || userData.disableSeasonalNotifs === true) continue;

                try {
                    await admin.messaging().send({
                        token,
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
                            notification: { icon: '/icons/Icon-192.png' },
                            fcm_options: { link: 'https://anyskill-6fdf3.web.app' },
                        },
                        data: { type: 'seasonal', month: String(month) },
                    });
                    await db.collection('notifications').add({
                        userId: doc.id, title, body, type: 'seasonal',
                        data: { month: String(month) },
                        isRead: false,
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                    totalSent++;
                } catch (e) {
                    console.error(`Seasonal notify error for ${doc.id}:`, e.message);
                }
            }

            lastDoc = snap.docs[snap.docs.length - 1];
        } while (true);

        console.log(`sendSeasonalNotifications: sent ${totalSent} for month ${month}`);
    }
);

// ── Weekly inactivity reminders — every Sunday 11:00 IST ─────────────────────
// Targets customers who haven't booked in 60+ days.
// Requires users/{uid}.lastBookingAt to be stamped on job creation
// (done by awardCreditsOnBooking below via the same trigger).
// Users can opt out via users/{uid}.disableInactivityNotifs = true.

exports.sendInactivityReminders = onSchedule(
    { schedule: '0 11 * * 0', timeZone: 'Asia/Jerusalem', maxInstances: 1 },
    async () => {
        const db     = admin.firestore();
        const cutoff = new Date();
        cutoff.setDate(cutoff.getDate() - 60);
        const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);

        const snap = await db.collection('users')
            .where('isProvider',   '==', false)
            .where('lastBookingAt', '<',  cutoffTs)
            .limit(200)
            .get();

        let sent = 0;
        for (const doc of snap.docs) {
            const userData = doc.data();
            const token    = userData.fcmToken || userData.deviceToken;
            if (!token || userData.disableInactivityNotifs === true) continue;

            const name  = userData.name || 'יקר/ה';
            const title = `${name}, מתגעגעים אליך! 👋`;
            const body  = 'כבר 60 יום לא הזמנת שירות. גלה מה חדש ב-AnySkill!';

            try {
                await admin.messaging().send({
                    token,
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
                        notification: { icon: '/icons/Icon-192.png' },
                        fcm_options: { link: 'https://anyskill-6fdf3.web.app' },
                    },
                    data: { type: 'inactivity_reminder' },
                });
                await db.collection('notifications').add({
                    userId: doc.id, title, body, type: 'inactivity_reminder',
                    data: {}, isRead: false,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                sent++;
            } catch (e) {
                console.error(`Inactivity notify error for ${doc.id}:`, e.message);
            }
        }
        console.log(`sendInactivityReminders: sent ${sent} notifications`);
    }
);

// ── Award loyalty credits when customer creates a booking (+50 credits) ────────
// Also stamps lastBookingAt for the inactivity reminder query above.

exports.awardCreditsOnBooking = onDocumentCreated(
    { document: "jobs/{jobId}", maxInstances: 50 },
    async (event) => {
        const jobData    = event.data.data();
        const customerId = jobData.customerId;
        if (!customerId) return null;

        const db                  = admin.firestore();
        const CREDITS_PER_BOOKING = 50;

        try {
            await db.collection('users').doc(customerId).update({
                credits:       admin.firestore.FieldValue.increment(CREDITS_PER_BOOKING),
                lastBookingAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            console.log(`Credits: +${CREDITS_PER_BOOKING} to customer ${customerId}`);
        } catch (e) {
            console.error('awardCreditsOnBooking error:', e);
        }
        return null;
    }
);

// ── Award loyalty credits when customer leaves a photo review (+30 credits) ───

exports.awardCreditsOnPhotoReview = onDocumentCreated(
    { document: "reviews/{reviewId}", maxInstances: 30 },
    async (event) => {
        const review   = event.data.data();
        const reviewer = review.reviewerId;
        const photos   = review.photos || [];
        if (!reviewer || !Array.isArray(photos) || photos.length === 0) return null;

        const CREDITS_PER_PHOTO_REVIEW = 30;
        const db = admin.firestore();
        try {
            await db.collection('users').doc(reviewer).update({
                credits: admin.firestore.FieldValue.increment(CREDITS_PER_PHOTO_REVIEW),
            });
            console.log(`Credits: +${CREDITS_PER_PHOTO_REVIEW} to reviewer ${reviewer}`);
        } catch (e) {
            console.error('awardCreditsOnPhotoReview error:', e);
        }
        return null;
    }
);

// ─────────────────────────────────────────────────────────────────────────────
// Admin email notification — new user registration
// ─────────────────────────────────────────────────────────────────────────────
//
// HOW IT WORKS
// ─────────────
// Triggers whenever a new document is created in users/{uid}.
// Writes a doc to the `mail` collection, which the Firebase "Trigger Email"
// extension picks up and sends via your configured SMTP provider.
//
// SETUP (one-time)
// ─────────────────
// 1. Install the Firebase Trigger Email extension:
//    https://firebase.google.com/products/extensions/firebase-firestore-send-email
//    Choose "mail" as the collection name when prompted.
//
// 2. Configure SMTP credentials in the extension settings.
//    Recommended free options:
//      • Brevo (formerly Sendinblue) — 300 emails/day free
//        SMTP host: smtp-relay.brevo.com  port: 587
//      • Mailjet — 200 emails/day free
//        SMTP host: in-v3.mailjet.com     port: 587
//    For both: create an account → Settings → SMTP & API → copy credentials.
//
// 3. Deploy this function:
//    firebase deploy --only functions:notifyadminonregister
//
// ─────────────────────────────────────────────────────────────────────────────

// v9.7.0: ADMIN_EMAIL removed — admin check is now via isAdminCaller() only

/** Formats a Firestore Timestamp (or null) as a Hebrew locale date-time string. */
function formatDate(ts) {
    if (!ts) return "לא ידוע";
    try {
        return ts.toDate().toLocaleString("he-IL", {
            timeZone:    "Asia/Jerusalem",
            day:         "2-digit",
            month:       "2-digit",
            year:        "numeric",
            hour:        "2-digit",
            minute:      "2-digit",
        });
    } catch (_) {
        return String(ts);
    }
}

/** Returns a badge-style HTML pill for the user type. */
function userTypePill(isProvider) {
    const label = isProvider ? "נותן שירות" : "לקוח";
    const bg    = isProvider ? "#6366F1"    : "#10B981";
    return `<span style="display:inline-block;background:${bg};color:#fff;`
         + `padding:3px 12px;border-radius:99px;font-size:12px;`
         + `font-weight:700;">${label}</span>`;
}

/** Builds the full HTML body for the admin notification email. */
function buildEmailHtml({ uid, name, email, isProvider, userType,
                          createdAt, city, serviceType, businessType, phone }) {
    const accentColor = "#6366F1";
    const bgLight     = "#F5F5FF";

    return `<!DOCTYPE html>
<html dir="rtl" lang="he">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>משתמש חדש נרשם</title>
</head>
<body style="margin:0;padding:0;background:#F0F0FF;font-family:Arial,Helvetica,sans-serif;direction:rtl;">

  <!-- Wrapper -->
  <table width="100%" cellpadding="0" cellspacing="0" border="0"
         style="background:#F0F0FF;padding:32px 16px;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" border="0"
               style="max-width:600px;width:100%;background:#fff;
                      border-radius:20px;overflow:hidden;
                      box-shadow:0 4px 24px rgba(99,102,241,.15);">

          <!-- Header -->
          <tr>
            <td style="background:linear-gradient(135deg,#4F46E5 0%,${accentColor} 50%,#8B5CF6 100%);
                        padding:32px 32px 28px;text-align:center;">
              <div style="font-size:28px;font-weight:900;color:#fff;
                          letter-spacing:0.5px;margin-bottom:6px;">
                AnySkill
              </div>
              <div style="font-size:13px;color:rgba(255,255,255,.80);">
                פאנל ניהול — התראה אוטומטית
              </div>
            </td>
          </tr>

          <!-- Alert banner -->
          <tr>
            <td style="background:#EEF2FF;padding:16px 32px;
                        border-bottom:1px solid #E0E7FF;">
              <table width="100%" cellpadding="0" cellspacing="0">
                <tr>
                  <td style="font-size:22px;vertical-align:middle;">🎉</td>
                  <td width="12"></td>
                  <td>
                    <div style="font-size:16px;font-weight:700;color:#1E1B4B;">
                      משתמש חדש נרשם לפלטפורמה
                    </div>
                    <div style="font-size:12px;color:#6B7280;margin-top:2px;">
                      ${createdAt}
                    </div>
                  </td>
                  <td align="left">${userTypePill(isProvider)}</td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Details card -->
          <tr>
            <td style="padding:28px 32px;">
              <table width="100%" cellpadding="0" cellspacing="0"
                     style="background:${bgLight};border-radius:14px;
                            overflow:hidden;border:1px solid #E0E7FF;">

                ${_row("👤", "שם מלא",         name)}
                ${_row("✉️", "אימייל",          email)}
                ${_row("🏷️", "סוג משתמש",      userType)}
                ${_row("🛠️", "תחום / קטגוריה", serviceType || "לא צוין")}
                ${isProvider ? _row("🏢", "סוג עסק", businessType || "לא צוין") : ""}
                ${_row("📱", "טלפון",           phone || "לא צוין")}
                ${_row("📍", "מיקום",           city)}
                ${_row("🆔", "UID",             uid)}
                ${_row("📅", "תאריך הרשמה",   createdAt)}

              </table>
            </td>
          </tr>

          <!-- CTA -->
          <tr>
            <td style="padding:0 32px 28px;text-align:center;">
              <a href="https://console.firebase.google.com/project/_/firestore/data/~2Fusers~2F${uid}"
                 target="_blank"
                 style="display:inline-block;background:linear-gradient(135deg,#4F46E5,${accentColor});
                         color:#fff;text-decoration:none;font-size:14px;font-weight:700;
                         padding:12px 28px;border-radius:10px;
                         box-shadow:0 4px 12px rgba(99,102,241,.35);">
                פתח בFirestore Console →
              </a>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="background:#F9F9FF;padding:18px 32px;
                        border-top:1px solid #E0E7FF;text-align:center;">
              <div style="font-size:11px;color:#9CA3AF;">
                הודעה זו נשלחה אוטומטית על ידי AnySkill Cloud Functions<br/>
                לא להשיב על מייל זה — לפניות: ${ADMIN_EMAIL}
              </div>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>

</body>
</html>`;
}

/** Returns a single detail row for the details table. */
function _row(emoji, label, value) {
    return `
    <tr>
      <td style="padding:12px 16px;border-bottom:1px solid #E0E7FF;width:36px;
                  font-size:16px;vertical-align:top;">${emoji}</td>
      <td style="padding:12px 8px 12px 0;border-bottom:1px solid #E0E7FF;
                  width:130px;font-size:13px;color:#6B7280;
                  font-weight:600;vertical-align:top;">${label}</td>
      <td style="padding:12px 16px 12px 0;border-bottom:1px solid #E0E7FF;
                  font-size:13px;color:#1E1B4B;
                  font-weight:700;vertical-align:top;">${value}</td>
    </tr>`;
}

// ── The Cloud Function ────────────────────────────────────────────────────────

exports.notifyadminonregister = onDocumentUpdated(
    {
        document:    "users/{uid}",
        maxInstances: 10,
        region:      "us-central1",
    },
    async (event) => {
        if (!event.data) return null;

        const before = event.data.before.data();
        const after  = event.data.after.data();
        const uid    = event.params.uid;

        // Only fire when onboardingComplete transitions false → true
        if (before.onboardingComplete === true || after.onboardingComplete !== true) return null;

        // Skip system-created users (e.g. service accounts)
        if (uid === "anyskill_system") return null;

        const data        = after;
        const isProvider  = data.isProvider === true;
        const name        = data.name        || "לא צוין";
        const email       = data.email       || "לא צוין";
        const phone       = data.phone       || "";
        const serviceType = isProvider ? (data.serviceType || "לא צוין") : "—";
        const businessType = isProvider ? (data.businessType || "לא צוין") : null;
        const userType    = isProvider ? "נותן שירות (ספק)" : "לקוח";

        // Location: try multiple field names your app might populate
        const city = data.city
            || data.locationCity
            || data.location
            || (data.locationData && data.locationData.city)
            || "לא צוין";

        const createdAt = formatDate(data.createdAt);

        const html = buildEmailHtml({
            uid, name, email, isProvider, userType,
            createdAt, city, serviceType, businessType, phone,
        });

        const subject = `🆕 [AnySkill] נרשם ${userType}: ${name}`;

        // ── Method A: Firebase Trigger Email extension (recommended) ──────────
        // Writes a doc to the `mail` collection; the extension delivers it.
        // Make sure the extension is installed and SMTP is configured.
        try {
            await admin.firestore().collection("mail").add({
                to:      ADMIN_EMAIL,
                message: { subject, html },
            });
            console.log(`Admin notification sent for new user: ${uid} (${email})`);
        } catch (err) {
            console.error("notifyadminonregister: failed to queue mail doc:", err);
        }

        return null;

        // ── Method B: Nodemailer (alternative — uncomment if you prefer SMTP) ─
        //
        // SETUP:
        //   1. cd functions && npm install nodemailer
        //   2. firebase functions:secrets:set SMTP_USER SMTP_PASS
        //   3. Add "runWith({ secrets: ['SMTP_USER','SMTP_PASS'] })" to the
        //      function options (v2 syntax shown below).
        //
        // const nodemailer = require("nodemailer");
        // const { defineSecret } = require("firebase-functions/params");
        // const SMTP_USER = defineSecret("SMTP_USER");
        // const SMTP_PASS = defineSecret("SMTP_PASS");
        //
        // const transporter = nodemailer.createTransport({
        //     host: "smtp-relay.brevo.com",   // or smtp.mailjet.com
        //     port: 587,
        //     secure: false,
        //     auth: {
        //         user: SMTP_USER.value(),
        //         pass: SMTP_PASS.value(),
        //     },
        // });
        //
        // await transporter.sendMail({
        //     from: `"AnySkill Admin" <${SMTP_USER.value()}>`,
        //     to:   ADMIN_EMAIL,
        //     subject,
        //     html,
        // });
    }
);

// =============================================================================
// ─── AI Category Mapping Engine ───────────────────────────────────────────────
// =============================================================================
//
// Flow:
//   1. Provider completes onboarding → Flutter calls `categorizeprovider`
//   2. Function fetches live categories from Firestore + calls Claude
//   3a. Confidence ≥ 0.90  → auto-assign, update user.serviceType immediately
//   3b. Confidence < 0.90  → write to `categories_pending`, email admin
//   4. Admin opens PendingCategoriesScreen → calls `approvecategory`
//   5. Approval creates a real `categories` doc; provider is updated
// =============================================================================

// ── System prompt (injected into every Claude call) ───────────────────────────
const _CATEGORY_SYSTEM_PROMPT = `\
You are AnySkill's category routing AI for an Israeli service marketplace.
Your task: given a service provider's free-text description, map it to the best
existing category OR create a normalized new category + subcategory.

RESPOND WITH ONLY VALID JSON — no markdown fences, no explanation text.

Required JSON schema:
{
  "action":                     "match" | "new",
  "confidence":                 0.0–1.0,
  "matched_category_id":        "<Firestore doc ID> | null",
  "matched_category_name":      "<Hebrew name> | null",
  "suggested_category_name":    "<Hebrew name> | null",
  "suggested_subcategory_name": "<Hebrew name> | null",
  "image_prompt":               "<English Midjourney/DALL-E prompt> | null",
  "keywords":                   ["<Hebrew keyword>", ...],
  "reasoning":                  "<brief Hebrew explanation>"
}

Rules:
• action="match"  when confidence >= 0.90 — fill matched_category_id/name
• action="new"    when confidence <  0.90 — fill suggested_category_name
• suggested_subcategory_name is ALWAYS required for BOTH actions — never null or empty.
  For match: derive the subcategory from the provider's specific service within that category.
  For new:   generate a specific subcategory for the new category.

NORMALIZATION (critical):
• Always use the broadest, most standard industry category name.
  Examples: "Cat Sitter" → category="טיפול בחיות מחמד", sub="שמירה על חתולים"
            "Kitty Care" → category="טיפול בחיות מחמד", sub="טיפול בחתולים"
            "Wedding DJ" → category="מוזיקה ואירועים", sub="DJ לאירועים"
            "Excel Tutor" → category="שיעורים פרטיים", sub="הדרכת Excel"
            "House cleaner" → category="ניקיון", sub="ניקיון דירות"
            "Window washer" → category="ניקיון", sub="ניקיון חלונות"
• Different descriptions of the same profession MUST produce the SAME category name.
• Avoid overly specific or literal translations of the user's words.
• Prefer existing categories when semantically close (confidence threshold 0.85 is enough for a very close match).
• suggested_category_name must be 2–4 Hebrew words, general, reusable across many providers.
• suggested_subcategory_name must be 2–5 Hebrew words, specific to this provider's exact service.

• image_prompt (new categories only): professional Israeli service photo —
  real person in action, clean bright background, photorealistic 8K.
• keywords: 4–7 Hebrew synonyms/related terms for semantic search.
• reasoning: one sentence in Hebrew explaining your decision.
• Output JSON only. Any non-JSON output will cause an error.`;

// ── Helper: email HTML for pending-category admin alert ───────────────────────
function buildPendingCategoryEmail({ uid, serviceDescription, suggestedCategoryName,
    suggestedSubCategoryName, imagePrompt, confidence, reasoning, pendingId }) {
    const pct = Math.round((confidence || 0) * 100);
    return `<!DOCTYPE html>
<html dir="rtl" lang="he">
<head><meta charset="UTF-8"/><title>קטגוריה ממתינה</title></head>
<body style="margin:0;padding:24px;background:#F0F0FF;font-family:Arial,sans-serif;direction:rtl;">
  <div style="max-width:560px;margin:auto;background:#fff;border-radius:16px;overflow:hidden;
              box-shadow:0 4px 20px rgba(99,102,241,.15);">
    <div style="background:linear-gradient(135deg,#4F46E5,#6366F1,#8B5CF6);padding:28px 28px 20px;text-align:center;">
      <div style="font-size:24px;font-weight:900;color:#fff;">AnySkill 🤖</div>
      <div style="font-size:13px;color:rgba(255,255,255,.8);margin-top:4px;">קטגוריה חדשה ממתינה לאישורך</div>
    </div>
    <div style="padding:24px 28px;">
      <table width="100%" cellpadding="0" cellspacing="0">
        <tr><td style="padding:8px 0;color:#6B7280;font-size:13px;">תיאור הספק</td>
            <td style="padding:8px 0;font-weight:700;font-size:14px;text-align:left;">${serviceDescription}</td></tr>
        <tr><td style="padding:8px 0;color:#6B7280;font-size:13px;">קטגוריה מוצעת</td>
            <td style="padding:8px 0;font-weight:700;font-size:14px;color:#6366F1;text-align:left;">${suggestedCategoryName || "—"}</td></tr>
        <tr><td style="padding:8px 0;color:#6B7280;font-size:13px;">תת-קטגוריה</td>
            <td style="padding:8px 0;font-size:13px;text-align:left;">${suggestedSubCategoryName || "—"}</td></tr>
        <tr><td style="padding:8px 0;color:#6B7280;font-size:13px;">ביטחון AI</td>
            <td style="padding:8px 0;text-align:left;">
              <span style="background:#FEF3C7;color:#D97706;padding:3px 10px;border-radius:99px;font-size:12px;font-weight:700;">${pct}%</span>
            </td></tr>
        <tr><td style="padding:8px 0;color:#6B7280;font-size:13px;">הנמקה</td>
            <td style="padding:8px 0;font-size:13px;text-align:left;">${reasoning || "—"}</td></tr>
        ${imagePrompt ? `<tr><td style="padding:8px 0;color:#6B7280;font-size:13px;">פרומפט לתמונה</td>
            <td style="padding:8px 0;font-size:11px;color:#6366F1;text-align:left;font-style:italic;">${imagePrompt}</td></tr>` : ""}
        <tr><td style="padding:8px 0;color:#6B7280;font-size:13px;">UID הספק</td>
            <td style="padding:8px 0;font-size:11px;color:#9CA3AF;text-align:left;">${uid}</td></tr>
      </table>
      <div style="margin-top:20px;text-align:center;">
        <a href="https://console.firebase.google.com/project/anyskill-6fdf3/firestore/data/~2Fcategories_pending~2F${pendingId}"
           style="display:inline-block;background:linear-gradient(135deg,#4F46E5,#6366F1);color:#fff;
                  text-decoration:none;padding:12px 28px;border-radius:10px;font-weight:700;font-size:14px;">
          פתח בקונסול לאישור ←
        </a>
      </div>
    </div>
  </div>
</body></html>`;
}

// ── categorizeprovider — callable from Flutter ────────────────────────────────
exports.categorizeprovider = onCall(
    { secrets: [ANTHROPIC_API_KEY], maxInstances: 10, region: "us-central1", memory: "512MiB" },
    async (request) => {
        // Auth is optional — callers during sign-up are not yet authenticated.
        // uid is null for anonymous callers; user-doc writes are skipped below.
        const uid = request.auth?.uid || null;

        const { serviceDescription } = request.data;
        if (!serviceDescription || typeof serviceDescription !== "string" || serviceDescription.trim().length < 2) {
            throw new HttpsError("invalid-argument", "serviceDescription is required");
        }

        const db  = admin.firestore();

        // 1. Fetch all top-level live categories from Firestore
        const catSnap = await db.collection("categories")
            .where("parentId", "==", "")
            .limit(60)
            .get();

        const existingCategories = catSnap.docs.map(d => ({
            id:       d.id,
            name:     d.data().name     || "",
            keywords: d.data().keywords || [],
        }));

        // 2. Build the user message
        const categoryList = existingCategories.length > 0
            ? existingCategories
                .map((c, i) => `${i + 1}. id="${c.id}" name="${c.name}"${c.keywords.length ? ` keywords=[${c.keywords.join(", ")}]` : ""}`)
                .join("\n")
            : "(no categories exist yet — suggest a new one)";

        const userMessage =
            `Provider service description: "${serviceDescription.trim()}"\n\n` +
            `Existing categories:\n${categoryList}\n\n` +
            `Map this provider. Return JSON only.`;

        // 3. Call Claude (haiku — fast + cheap for classification)
        // ── Secret resolution ────────────────────────────────────────────────
        // For Gen2 functions, defineSecret() binds the secret as both
        // ANTHROPIC_API_KEY.value() AND process.env.ANTHROPIC_API_KEY.
        // We try both paths so the diagnostic is unambiguous.
        const apiKey = ANTHROPIC_API_KEY.value() || process.env.ANTHROPIC_API_KEY || "";
        console.log(`categorizeprovider: secret via .value()=${!!ANTHROPIC_API_KEY.value()} via env=${!!process.env.ANTHROPIC_API_KEY} finalLength=${apiKey.length}`);

        if (!apiKey) {
            // Return a clear sentinel instead of a generic internal error.
            throw new HttpsError(
                "internal",
                "SECRET_MISSING: ANTHROPIC_API_KEY is not bound to this function. " +
                "Run: firebase functions:secrets:set ANTHROPIC_API_KEY " +
                "then redeploy: firebase deploy --only functions:categorizeprovider",
            );
        }

        let parsed;
        try {
            // Anthropic is required at top level (CJS) — do NOT use dynamic import here
            const anthropic = new Anthropic({ apiKey });

            const msg = await anthropic.messages.create({
                model:      "claude-haiku-4-5-20251001",
                max_tokens: 512,
                system:     _CATEGORY_SYSTEM_PROMPT,
                messages:   [{ role: "user", content: userMessage }],
            });

            _trackApiCost(admin.firestore(), msg.usage?.input_tokens || 0, msg.usage?.output_tokens || 0).catch(() => {});
            const raw = (msg.content[0]?.text ?? "{}").replace(/```(?:json)?\s*/gi, "").replace(/```/g, "").trim();
            parsed = JSON.parse(raw);
        } catch (err) {
            // Surface the REAL error — class name + message — so it shows in
            // the Flutter snackbar instead of a generic "internal" string.
            const realMessage = err?.message || err?.toString() || "unknown";
            const errType     = err?.constructor?.name || "Error";
            console.error("categorizeprovider: AI call failed:", err);
            throw new HttpsError("internal", `[${errType}] ${realMessage}`);
        }

        const {
            action, confidence,
            matched_category_id, matched_category_name,
            suggested_category_name, suggested_subcategory_name,
            image_prompt, keywords = [], reasoning,
        } = parsed;

        // subCategoryName is always populated by the prompt (for both match and new)
        const subName = suggested_subcategory_name || null;

        // ── 3a. High-confidence match ────────────────────────────────────────
        // Pure classification — no DB writes. Client calls finalizecategorysetup on submit.
        if (action === "match" && matched_category_id && (confidence ?? 0) >= 0.90) {
            console.log(`categorizeprovider: match uid=${uid ?? "anon"} → "${matched_category_name}" / "${subName}" (${Math.round((confidence ?? 0) * 100)}%)`);
            return {
                action:          "match",
                categoryId:      matched_category_id,
                categoryName:    matched_category_name,
                subCategoryName: subName,
                confidence,
                reasoning,
            };
        }

        // ── 3b. New / low-confidence — return AI-generated names only ────────
        const normalizedName = suggested_category_name || serviceDescription.trim();

        console.log(`categorizeprovider: new uid=${uid ?? "anon"} → "${normalizedName}" / "${subName}" (${Math.round((confidence ?? 0) * 100)}%)`);
        return {
            action:          "new",
            categoryName:    normalizedName,
            subCategoryName: subName,
            confidence,
            reasoning,
        };
    }
);

// ── finalizecategorysetup — called from Flutter on 'Create Profile' ───────────
// Creates / finds the category + subcategory in Firestore, updates the user doc,
// writes admin_log, and sends email. Separated from classify so that DB writes
// only happen when the user actually submits — not on every AI preview.
exports.finalizecategorysetup = onCall(
    { maxInstances: 10, region: "us-central1" },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Authentication required");
        }

        const uid = request.auth.uid;
        const {
            categoryName, subCategoryName,
            matchedCategoryId,           // present when AI found an existing category
            serviceDescription = "",
            confidence = 0, reasoning = "",
        } = request.data;

        if (!categoryName) {
            throw new HttpsError("invalid-argument", "categoryName is required");
        }

        const db  = admin.firestore();
        const now = admin.firestore.FieldValue.serverTimestamp();

        // ── 1. Resolve or create the parent category ─────────────────────────
        let catId = matchedCategoryId || null;
        if (!catId) {
            const q = await db.collection("categories")
                .where("name",     "==", categoryName)
                .where("parentId", "==", "")
                .limit(1).get();
            if (!q.empty) {
                catId = q.docs[0].id;
            } else {
                const ref = db.collection("categories").doc();
                await ref.set({
                    name:        categoryName,
                    parentId:    "",
                    isActive:    true,
                    autoCreated: true,
                    createdAt:   now,
                });
                catId = ref.id;
            }
        }

        // ── 2. Resolve or create the subcategory ─────────────────────────────
        let subCatId = null;
        if (subCategoryName) {
            const q2 = await db.collection("categories")
                .where("name",     "==", subCategoryName)
                .where("parentId", "==", catId)
                .limit(1).get();
            if (!q2.empty) {
                subCatId = q2.docs[0].id;
            } else {
                const subRef = db.collection("categories").doc();
                await subRef.set({
                    name:        subCategoryName,
                    parentId:    catId,
                    isActive:    true,
                    autoCreated: true,
                    createdAt:   now,
                });
                subCatId = subRef.id;
            }
        }

        // ── 3. Update user doc with resolved IDs ─────────────────────────────
        const userUpdate = { categoryId: catId, categoryStatus: "approved" };
        if (subCatId)        userUpdate.subCategoryId   = subCatId;
        if (subCategoryName) userUpdate.subCategoryName = subCategoryName;
        try {
            // update() requires the doc to exist. Use set+merge as fallback in case
            // Firestore propagation hasn't completed by the time we reach this step.
            await db.collection("users").doc(uid).update(userUpdate);
        } catch (_) {
            await db.collection("users").doc(uid).set(userUpdate, { merge: true });
        }

        // ── 4. Admin log + email — run in parallel to cut latency ────────────
        const isNew = !matchedCategoryId;
        const logEntry = {
            type:               isNew ? "new_category" : "matched_category",
            categoryId:         catId,
            categoryName,
            subCategoryName:    subCategoryName || null,
            subCategoryId:      subCatId,
            triggerDescription: serviceDescription,
            triggerUid:         uid,
            confidence,
            reasoning,
            isNew,
            isReviewed:         false,
            createdAt:          now,
        };
        const subject = isNew
            ? `🤖 [AnySkill] קטגוריה חדשה נוצרה: ${categoryName}`
            : `✅ [AnySkill] ספק חדש בקטגוריה: ${categoryName} / ${subCategoryName || "—"}`;
        const mailEntry = {
            to: ADMIN_EMAIL,
            message: {
                subject,
                html: buildPendingCategoryEmail({
                    uid, serviceDescription,
                    suggestedCategoryName:    categoryName,
                    suggestedSubCategoryName: subCategoryName,
                    imagePrompt:              null,
                    confidence, reasoning,
                    pendingId: catId,
                }),
            },
        };
        await Promise.all([
            db.collection("admin_logs").add(logEntry),
            db.collection("mail").add(mailEntry).catch(e =>
                console.warn("finalizecategorysetup: mail failed:", e)),
        ]);

        console.log(`finalizecategorysetup: uid=${uid} cat="${categoryName}"(${catId}) sub="${subCategoryName}"(${subCatId}) isNew=${isNew}`);
        return { categoryId: catId, subCategoryId: subCatId };
    }
);

// ── approvecategory — admin-only callable ─────────────────────────────────────
exports.approvecategory = onCall(
    { maxInstances: 5, region: "us-central1" },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Authentication required");
        }

        // Guard: caller must be admin
        const callerSnap = await admin.firestore()
            .collection("users").doc(request.auth.uid).get();
        if (!callerSnap.exists || callerSnap.data()?.isAdmin !== true) {
            throw new HttpsError("permission-denied", "Admin only");
        }

        const { pendingId, action } = request.data; // action: "approve" | "reject"
        if (!pendingId || !["approve", "reject"].includes(action)) {
            throw new HttpsError("invalid-argument", "pendingId and action ('approve'|'reject') required");
        }

        const db          = admin.firestore();
        const pendingRef  = db.collection("categories_pending").doc(pendingId);
        const pendingSnap = await pendingRef.get();

        if (!pendingSnap.exists) {
            throw new HttpsError("not-found", "Pending category not found");
        }
        const pending = pendingSnap.data();
        const now     = admin.firestore.FieldValue.serverTimestamp();

        // ── Reject ───────────────────────────────────────────────────────────
        if (action === "reject") {
            await Promise.all([
                pendingRef.update({ status: "rejected", reviewedAt: now, reviewedBy: request.auth.uid }),
                db.collection("users").doc(pending.uid).update({ categoryStatus: "rejected" }),
            ]);
            return { success: true, action: "rejected" };
        }

        // ── Approve: create the live category (and optional sub-category) ────
        const orderSnap = await db.collection("categories")
            .orderBy("order", "desc").limit(1).get();
        const nextOrder = (orderSnap.docs[0]?.data()?.order ?? 0) + 1;

        const newCatRef = await db.collection("categories").add({
            name:         pending.suggestedCategoryName,
            parentId:     "",
            iconName:     "stars",
            img:          "",            // admin pastes Midjourney URL here later
            imagePrompt:  pending.imagePrompt  || null,
            keywords:     pending.keywords     || [],
            order:        nextOrder,
            bookingCount: 0,
            isActive:     true,
            createdBy:    "ai",
            createdAt:    now,
        });

        const ops = [
            pendingRef.update({
                status:             "approved",
                approvedCategoryId: newCatRef.id,
                reviewedAt:         now,
                reviewedBy:         request.auth.uid,
            }),
            db.collection("users").doc(pending.uid).update({
                categoryId:     newCatRef.id,
                serviceType:    pending.suggestedCategoryName,
                categoryStatus: "approved",
            }),
        ];

        if (pending.suggestedSubCategoryName) {
            ops.push(
                db.collection("categories").add({
                    name:         pending.suggestedSubCategoryName,
                    parentId:     newCatRef.id,
                    iconName:     "stars",
                    img:          "",
                    keywords:     [],
                    order:        1,
                    bookingCount: 0,
                    isActive:     true,
                    createdBy:    "ai",
                    createdAt:    now,
                })
            );
        }

        await Promise.all(ops);

        console.log(`approvecategory: approved pendingId=${pendingId} → newCategoryId=${newCatRef.id}`);
        return { success: true, action: "approved", newCategoryId: newCatRef.id };
    }
);

// ── Market Opportunity Monitor ─────────────────────────────────────────────────
// Triggers on every new search_log document.
// When a zero-result keyword exceeds the admin-configured threshold within 24h,
// sends a high-priority FCM push to all admin devices and records the alert.

exports.marketopportunitymonitor = onDocumentCreated(
    "search_logs/{logId}",
    async (event) => {
        const data = event.data?.data();
        if (!data || !data.zeroResults) return null;

        const query = (data.query || "").trim().toLowerCase();
        if (query.length < 2) return null;

        const db = admin.firestore();

        // ── 0. Always track zero-result searches for Business AI analysis ─────
        // Upserts a market_opportunities doc so the AI dashboard can surface gaps.
        try {
            const oppId  = query.replace(/[/.]/g, "_").substring(0, 100);
            await db.collection("market_opportunities").doc(oppId).set({
                query,
                searchCount:    admin.firestore.FieldValue.increment(1),
                lastSearchedAt: admin.firestore.FieldValue.serverTimestamp(),
                analyzed:       false,
            }, { merge: true });
        } catch (e) {
            console.warn(`marketopportunitymonitor: market_opportunities write failed — ${e.message}`);
        }

        // ── 1. Read alert threshold from admin settings ──────────────────────
        const settingsSnap = await db
            .collection("admin").doc("admin")
            .collection("settings").doc("settings")
            .get();
        const threshold = Number((settingsSnap.data() || {}).marketAlertThreshold) || 5;

        // ── 2. Count zero-result occurrences of this keyword in last 24h ─────
        const since = new Date(Date.now() - 24 * 60 * 60 * 1000);
        const countSnap = await db
            .collection("search_logs")
            .where("query",       "==", query)
            .where("zeroResults", "==", true)
            .where("timestamp",   ">=", admin.firestore.Timestamp.fromDate(since))
            .limit(threshold + 1) // fetch one extra to confirm threshold crossed
            .get();

        if (countSnap.size < threshold) return null;

        // ── 3. Deduplicate — only one alert per keyword per calendar day ──────
        const alertId  = query.replace(/[/.]/g, "_").substring(0, 100);
        const alertRef = db.collection("market_alerts").doc(alertId);
        const alertDoc = await alertRef.get();
        const alertData = alertDoc.data() || {};

        if (alertData.lastAlertedAt) {
            const lastAlerted = alertData.lastAlertedAt.toDate();
            const todayStart  = new Date();
            todayStart.setHours(0, 0, 0, 0);
            if (lastAlerted >= todayStart) {
                console.log(`marketopportunitymonitor: already alerted today for "${query}"`);
                return null;
            }
        }

        // ── 4. Record the alert ───────────────────────────────────────────────
        await alertRef.set({
            keyword:       query,
            searchCount:   countSnap.size,
            threshold:     threshold,
            lastAlertedAt: admin.firestore.FieldValue.serverTimestamp(),
            totalAlerts:   admin.firestore.FieldValue.increment(1),
        }, { merge: true });

        // ── 5. Collect admin FCM tokens ───────────────────────────────────────
        const adminSnap = await db
            .collection("users")
            .where("isAdmin", "==", true)
            .limit(5)
            .get();

        const tokens = adminSnap.docs
            .map(d => d.data().fcmToken)
            .filter(t => typeof t === "string" && t.length > 10);

        if (tokens.length === 0) {
            console.log(`marketopportunitymonitor: no admin FCM tokens — alert recorded but not pushed`);
            return null;
        }

        // ── 6. Send high-priority FCM push to all admin devices ───────────────
        const response = await admin.messaging().sendEachForMulticast({
            notification: {
                title: "🚀 הזדמנות שוק זוהתה!",
                body:  `${countSnap.size} משתמשים חיפשו "${query}" היום ולא קיבלו תוצאות — הגיע הזמן לגייס ספקים!`,
            },
            data: {
                type:        "market_opportunity",
                keyword:     query,
                searchCount: String(countSnap.size),
                screen:      "business_ai",
            },
            tokens,
            android: {
                priority: "high",
                notification: { channelId: "market_alerts" },
            },
            apns: {
                payload: { aps: { sound: "default", badge: 1 } },
            },
        });

        console.log(
            `marketopportunitymonitor: keyword="${query}" count=${countSnap.size}/${threshold} ` +
            `→ ${response.successCount} delivered, ${response.failureCount} failed`
        );
        return null;
    }
);

// ── updateUserXP (Callable) ────────────────────────────────────────────────
// Awards or deducts XP from a user based on a named event.
// Reads the points value from settings_gamification/{eventId} so admins can
// tune every event without a code deploy.
// After updating XP the function recalculates the user's level using the
// thresholds stored in settings_gamification/app_levels.
//
// Call from Flutter:
//   await FirebaseFunctions.instance
//       .httpsCallable('updateUserXP')
//       .call({'userId': uid, 'eventId': 'finish_job'});
//
exports.updateUserXP = onCall(
    { maxInstances: 50 },
    async (request) => {
        // ── 1. Auth guard ─────────────────────────────────────────────────
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Authentication required.");
        }

        const { userId, eventId } = request.data;
        if (!userId || !eventId) {
            throw new HttpsError("invalid-argument", "userId and eventId are required.");
        }

        const db = admin.firestore();

        // ── 1b. Caller authorization ──────────────────────────────────────
        // Without this check, any signed-in user could grant unlimited XP to
        // any account (XP grinding, badge fraud, ranking manipulation).
        //
        // Allowed callers:
        //   1. Self-calls (uid === userId) — most events (story_upload, etc.)
        //   2. Admin — manual XP grants
        //   3. Counterparty for relationship-based events (volunteer_task) —
        //      only if the caller has a verified completed task with target
        const callerUid = request.auth.uid;
        const isSelfCall = callerUid === userId;
        const isAdminCall = isSelfCall ? false : await isAdminCaller(request);

        if (!isSelfCall && !isAdminCall) {
            // Non-self, non-admin: only specific relationship-based events allowed
            const RELATIONSHIP_EVENTS = new Set(["volunteer_task"]);
            if (!RELATIONSHIP_EVENTS.has(eventId)) {
                throw new HttpsError(
                    "permission-denied",
                    `Event '${eventId}' may only be awarded by the target user or an admin.`,
                );
            }

            // Verify a legitimate completed task exists between caller and target.
            // Check both the legacy volunteer_tasks collection and the new
            // community_requests collection (Community Hub v11.0.0).
            const [legacyTaskSnap, communityReqSnap] = await Promise.all([
                db.collection("volunteer_tasks")
                    .where("clientId", "==", callerUid)
                    .where("providerId", "==", userId)
                    .where("status", "==", "completed")
                    .limit(1)
                    .get(),
                db.collection("community_requests")
                    .where("requesterId", "==", callerUid)
                    .where("volunteerId", "==", userId)
                    .where("status", "==", "completed")
                    .limit(1)
                    .get(),
            ]);

            if (legacyTaskSnap.empty && communityReqSnap.empty) {
                throw new HttpsError(
                    "permission-denied",
                    "No completed volunteer task found between caller and target.",
                );
            }
        }

        // ── 2. Read event definition ──────────────────────────────────────
        const eventSnap = await db
            .collection("settings_gamification")
            .doc(eventId)
            .get();

        if (!eventSnap.exists) {
            throw new HttpsError("not-found", `XP event '${eventId}' not found in settings_gamification.`);
        }

        const eventData = eventSnap.data();
        const points    = typeof eventData.points === "number" ? eventData.points : 0;

        // ── 3. Read level thresholds (with sensible defaults) ─────────────
        const levelsSnap = await db
            .collection("settings_gamification")
            .doc("app_levels")
            .get();

        const levels          = levelsSnap.data() || {};
        const silverThreshold = typeof levels.silver === "number" ? levels.silver : 500;
        const goldThreshold   = typeof levels.gold   === "number" ? levels.gold   : 2000;

        // ── 4. Atomic transaction: increment XP + recalculate level ───────
        let finalXp    = 0;
        let finalLevel = "bronze";
        let oldLevel   = "bronze";

        await db.runTransaction(async (t) => {
            const userRef  = db.collection("users").doc(userId);
            const userSnap = await t.get(userRef);

            if (!userSnap.exists) {
                throw new HttpsError("not-found", `User ${userId} not found.`);
            }

            const userData  = userSnap.data();
            const currentXp =
                typeof userData.current_xp === "number" ? userData.current_xp :
                typeof userData.xp          === "number" ? userData.xp          : 0;

            oldLevel = userData.level || "bronze";

            // XP floor is 0 — providers cannot go into negative
            finalXp = Math.max(0, currentXp + points);

            if      (finalXp >= goldThreshold)   finalLevel = "gold";
            else if (finalXp >= silverThreshold) finalLevel = "silver";
            else                                 finalLevel = "bronze";

            t.update(userRef, {
                current_xp: finalXp,
                xp:         finalXp,   // keep legacy xp field in sync
                level:      finalLevel,
            });
        });

        const levelChanged = finalLevel !== oldLevel;

        console.log(
            `[updateUserXP] user=${userId} event=${eventId} ` +
            `Δ${points >= 0 ? "+" : ""}${points} → xp=${finalXp} level=${finalLevel}` +
            (levelChanged ? ` 🎉 LEVEL UP: ${oldLevel} → ${finalLevel}` : "")
        );

        // ── 5. Send level-up push notification if level improved ──────────
        if (levelChanged && finalLevel !== "bronze") {
            try {
                const userSnap = await db.collection("users").doc(userId).get();
                const token    = (userSnap.data() || {}).fcmToken;
                const levelNames = { silver: "כסף 🥈", gold: "זהב 🥇" };

                if (token) {
                    await admin.messaging().send({
                        token,
                        notification: {
                            title: "🎉 עלית רמה!",
                            body:  `כל הכבוד! הגעת לרמת ${levelNames[finalLevel] || finalLevel}!`,
                        },
                        data: { type: "level_up", newLevel: finalLevel },
                        android: { priority: "high" },
                        apns:    { payload: { aps: { sound: "default" } } },
                    });
                }
            } catch (notifErr) {
                // Non-fatal — XP was already updated
                console.warn(`[updateUserXP] level-up notification failed: ${notifErr.message}`);
            }
        }

        return { success: true, points, newXp: finalXp, newLevel: finalLevel, levelChanged };
    }
);

// ── expireStories (Scheduled) ──────────────────────────────────────────────
// Runs every 30 minutes.
// Scans the `stories` collection for documents where expiresAt < now.
// For each expired story:
//   1. Sets stories/{uid}.hasActive = false  (removes it from the discovery feed)
//   2. Sets users/{uid}.hasActiveStory = false  (removes the ranking boost)
//
// The story document is intentionally kept for analytics / history.
// A provider's next upload simply overwrites it.
exports.expireStories = onSchedule(
    { schedule: "every 30 minutes", timeZone: "Asia/Jerusalem" },
    async () => {
        const db  = admin.firestore();
        const now = admin.firestore.Timestamp.now();

        const expiredSnap = await db
            .collection("stories")
            .where("hasActive",  "==",       true)
            .where("expiresAt",  "<=",       now)
            .limit(200)
            .get();

        if (expiredSnap.empty) {
            console.log("[expireStories] No expired stories found.");
            return;
        }

        const batch = db.batch();
        const uids  = [];

        for (const doc of expiredSnap.docs) {
            // Mark story as inactive
            batch.update(doc.ref, { hasActive: false });
            uids.push(doc.id); // doc.id === uid
        }

        // Flip hasActiveStory = false on every affected user profile
        for (const uid of uids) {
            batch.update(db.collection("users").doc(uid), {
                hasActiveStory: false,
            });
        }

        await batch.commit();
        console.log(`[expireStories] Expired ${uids.length} stories: ${uids.join(", ")}`);
    }
);

// ── onStoryPublished (Firestore trigger) ──────────────────────────────────
// Fires when a provider writes / overwrites their stories/{uid} document.
// Awards XP for the story_upload event via the updateUserXP callable logic
// (duplicated inline here to avoid a cross-function call, which would add
// latency and an extra billing unit).
exports.onStoryPublished = onDocumentCreated(
    { document: "stories/{uid}" },
    async (event) => {
        const uid  = event.params.uid;
        const data = event.data?.data();
        if (!data || !data.hasActive) return null;

        const db = admin.firestore();

        // Read story_upload event points from settings_gamification
        const eventSnap = await db
            .collection("settings_gamification")
            .doc("story_upload")
            .get();

        if (!eventSnap.exists) {
            console.log("[onStoryPublished] story_upload event not found in settings — XP skipped.");
            return null;
        }

        const points = typeof eventSnap.data().points === "number"
            ? eventSnap.data().points
            : 5;

        // Read level thresholds
        const levelsSnap = await db
            .collection("settings_gamification")
            .doc("app_levels")
            .get();
        const levels          = levelsSnap.data() || {};
        const silverThreshold = levels.silver ?? 500;
        const goldThreshold   = levels.gold   ?? 2000;

        let finalXp = 0; let finalLevel = "bronze";

        await db.runTransaction(async (t) => {
            const userRef  = db.collection("users").doc(uid);
            const userSnap = await t.get(userRef);
            if (!userSnap.exists) return;

            const currentXp = typeof userSnap.data().current_xp === "number"
                ? userSnap.data().current_xp
                : (userSnap.data().xp || 0);

            finalXp = Math.max(0, currentXp + points);
            if      (finalXp >= goldThreshold)   finalLevel = "gold";
            else if (finalXp >= silverThreshold) finalLevel = "silver";
            else                                 finalLevel = "bronze";

            t.update(userRef, { current_xp: finalXp, xp: finalXp, level: finalLevel });
        });

        console.log(`[onStoryPublished] uid=${uid} story XP +${points} → xp=${finalXp} level=${finalLevel}`);
        return null;
    }
);

// ── resolveDisputeAdmin — Admin-only: arbitrate a disputed job ─────────────────
// Callable from DisputeResolutionScreen (Flutter admin panel only).
// resolution: 'refund' | 'release' | 'split'
// refund     → full totalAmount back to customer; expert gets 0.
// release    → expert gets totalAmount×(1−fee); platform earns fee.
// split      → customer gets 50%; expert gets 50%×(1−fee); platform earns 50%×fee.
exports.resolveDisputeAdmin = onCall(
    { maxInstances: 10 },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Authentication required.");
        }

        const db       = admin.firestore();
        const callerId = request.auth.uid;

        // ── Admin guard ────────────────────────────────────────────────────────
        // v9.7.0: Admin check via Firestore isAdmin flag only
        if (!(await isAdminCaller(request))) {
            throw new HttpsError("permission-denied", "Admin access required.");
        }

        const { jobId, resolution, adminNote } = request.data;
        if (!jobId || !["refund", "release", "split"].includes(resolution)) {
            throw new HttpsError("invalid-argument", "jobId and valid resolution are required.");
        }

        const jobRef  = db.collection("jobs").doc(jobId);

        // All balance mutations inside a transaction to prevent race conditions
        let customerId, expertId, totalAmount, newStatus;
        let customerCredit = 0, expertCredit = 0, platformFee = 0;

        await db.runTransaction(async (t) => {
            const jobSnap = await t.get(jobRef);
            if (!jobSnap.exists) throw new HttpsError("not-found", "Job not found.");

            const job = jobSnap.data();
            if (job.status !== "disputed") {
                throw new HttpsError("failed-precondition", `Job is not disputed (status: ${job.status}).`);
            }

            customerId  = job.customerId;
            expertId    = job.expertId;
            totalAmount = typeof job.totalAmount === "number" ? job.totalAmount : 0;

            // Read fee from admin settings inside the transaction
            const settingsRef  = db.collection("admin").doc("admin")
                                   .collection("settings").doc("settings");
            const settingsSnap = await t.get(settingsRef);
            const feePct       = typeof settingsSnap.data()?.feePercentage === "number"
                ? settingsSnap.data().feePercentage
                : 0.10;

            const customerRef = db.collection("users").doc(customerId);
            const expertRef   = db.collection("users").doc(expertId);

            if (resolution === "refund") {
                // Full refund to customer — expert loses all
                customerCredit = totalAmount;
                expertCredit   = 0;
                platformFee    = 0;
                newStatus      = "refunded";

                t.update(customerRef, { balance: admin.firestore.FieldValue.increment(customerCredit) });

            } else if (resolution === "release") {
                // Release escrow to expert (minus platform fee)
                platformFee    = roundNIS(totalAmount * feePct);
                expertCredit   = roundNIS(totalAmount - platformFee);
                customerCredit = 0;
                newStatus      = "completed";

                t.update(expertRef, { balance: admin.firestore.FieldValue.increment(expertCredit) });

                // Record platform earning
                t.set(db.collection("platform_earnings").doc(), {
                    jobId,
                    amount:    platformFee,
                    type:      "dispute_release_fee",
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                });

            } else {
                // Split 50 / 50
                const half     = roundNIS(totalAmount * 0.5);
                customerCredit = half;
                platformFee    = roundNIS(half * feePct);
                expertCredit   = roundNIS(half - platformFee);
                newStatus      = "split_resolved";

                t.update(customerRef, { balance: admin.firestore.FieldValue.increment(customerCredit) });
                t.update(expertRef,   { balance: admin.firestore.FieldValue.increment(expertCredit)   });

                // Record platform earning
                t.set(db.collection("platform_earnings").doc(), {
                    jobId,
                    amount:    platformFee,
                    type:      "dispute_split_fee",
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                });
            }

            // Update job status
            t.update(jobRef, {
                status:          newStatus,
                resolvedAt:      admin.firestore.FieldValue.serverTimestamp(),
                resolvedBy:      callerId,
                resolutionType:  resolution,
                adminNote:       adminNote || "",
            });

            // Transaction history — customer
            if (customerCredit > 0) {
                t.set(db.collection("transactions").doc(), {
                    userId:    customerId,
                    amount:    customerCredit,
                    title:     resolution === "refund" ? "החזר כספי — מחלוקת" : "פשרה — מחלוקת (50%)",
                    type:      "credit",
                    jobId,
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                });
            }

            // Transaction history — expert
            if (expertCredit > 0) {
                t.set(db.collection("transactions").doc(), {
                    userId:    expertId,
                    amount:    expertCredit,
                    title:     resolution === "release" ? "שחרור נאמנות — החלטת מנהל" : "פשרה — מחלוקת (50%)",
                    type:      "credit",
                    jobId,
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                });
            }
        });

        // ── FCM Notifications (best-effort, outside transaction) ──────────────
        const notifTitle = {
            refund:  "החזר כספי אושר",
            release: "תשלום שוחרר",
            split:   "מחלוקת נפתרה",
        }[resolution];

        const customerMsg = resolution === "refund"
            ? `קיבלת החזר מלא של ₪${totalAmount.toFixed(0)} לאחר ביקורת המנהל`
            : resolution === "split"
            ? `קיבלת ₪${customerCredit.toFixed(0)} (50%) כפשרה בין הצדדים`
            : `המחלוקת נסגרה — הסכום שוחרר לספק`;

        const expertMsg = resolution === "refund"
            ? `המחלוקת נסגרה — הסכום הוחזר ללקוח`
            : resolution === "release"
            ? `קיבלת ₪${expertCredit.toFixed(0)} לאחר ביקורת המנהל`
            : `קיבלת ₪${expertCredit.toFixed(0)} (50% בניכוי עמלה) כפשרה`;

        const sendNotif = async (userId, body) => {
            try {
                const userSnap = await admin.firestore().collection("users").doc(userId).get();
                const token    = userSnap.data()?.fcmToken || userSnap.data()?.deviceToken;

                // Write to notifications collection
                await admin.firestore().collection("notifications").add({
                    userId,
                    title:     notifTitle,
                    body,
                    type:      "dispute_resolved",
                    jobId,
                    isRead:    false,
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                });

                if (!token) return;
                await admin.messaging().send({
                    token,
                    notification: { title: notifTitle, body },
                    data:         { type: "dispute_resolved", jobId },
                });
            } catch (err) {
                console.warn(`[resolveDisputeAdmin] FCM to ${userId} failed:`, err.message);
            }
        };

        await Promise.all([
            sendNotif(customerId, customerMsg),
            sendNotif(expertId,   expertMsg),
        ]);

        console.log(`[resolveDisputeAdmin] jobId=${jobId} resolution=${resolution} by admin=${callerId}`);
        return {
            success:       true,
            resolution,
            newStatus,
            customerCredit: parseFloat(customerCredit.toFixed(2)),
            expertCredit:   parseFloat(expertCredit.toFixed(2)),
            platformFee:    parseFloat(platformFee.toFixed(2)),
        };
    }
);

// ── processCancellation — Customer or Provider cancels a paid_escrow job ──────
// cancelledBy: 'customer' | 'provider'
// Customer before deadline  → full refund
// Customer after deadline   → partial refund + penalty to provider (minus fee)
// Provider cancels          → full refund to customer + XP penalty for provider
exports.processCancellation = onCall(
    { maxInstances: 20 },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Authentication required.");
        }

        const db       = admin.firestore();
        const callerId = request.auth.uid;
        const { jobId, cancelledBy } = request.data;

        if (!jobId) {
            throw new HttpsError("invalid-argument", "jobId is required.");
        }

        const jobRef = db.collection("jobs").doc(jobId);

        let customerId, expertId, totalAmount, chatRoomId, policy;
        let customerCredit = 0, expertCredit = 0, platformFee = 0;
        let newStatus   = "cancelled";
        let isPenalty   = false;
        let isProviderCancelling = false;

        await db.runTransaction(async (t) => {
            const jobSnap = await t.get(jobRef);
            if (!jobSnap.exists) throw new HttpsError("not-found", "Job not found.");

            const job = jobSnap.data();
            if (job.status !== "paid_escrow") {
                throw new HttpsError("failed-precondition", `Job is not cancellable (status: ${job.status}).`);
            }

            // Only the involved parties can cancel
            if (callerId !== job.customerId && callerId !== job.expertId) {
                throw new HttpsError("permission-denied", "Not your booking.");
            }

            customerId  = job.customerId;
            expertId    = job.expertId;
            totalAmount = typeof job.totalAmount === "number" ? job.totalAmount : 0;
            chatRoomId  = job.chatRoomId || "";
            policy      = job.cancellationPolicy || "flexible";
            isProviderCancelling = (cancelledBy === "provider") || (callerId === expertId && cancelledBy !== "customer");

            // ── DEPOSIT-ONLY ESCROW (v12.1.0) ─────────────────────────────────
            // For jobs with depositPercent > 0, the customer has only paid
            // `paidAtBooking` (= deposit). The remainder hasn't been charged
            // yet, so refunds and penalties must be computed against the
            // PAID amount, not the total. When the customer cancels after the
            // deadline on a `nonRefundable` policy, the deposit is forfeited
            // and that's the entire penalty.
            const paidAtBooking = typeof job.paidAtBooking === "number"
                ? job.paidAtBooking
                : totalAmount;
            const isDepositJob = paidAtBooking < totalAmount;
            console.log(`[CANCEL] paidAtBooking=${paidAtBooking}, totalAmount=${totalAmount}, isDepositJob=${isDepositJob}`);

            // Read fee from admin settings inside the transaction
            const settingsSnap = await t.get(
                db.collection("admin").doc("admin").collection("settings").doc("settings")
            );
            const feePct = settingsSnap.data()?.feePercentage || 0.10;

            if (isProviderCancelling) {
                // Provider cancels: full refund of whatever the customer
                // actually paid (deposit OR full amount). Expert gets nothing.
                customerCredit = paidAtBooking;
                newStatus      = "cancelled";
                if (customerCredit > 0) {
                    t.update(db.collection("users").doc(customerId), {
                        balance: admin.firestore.FieldValue.increment(customerCredit),
                    });
                }

            } else {
                // Customer cancels: check deadline
                const deadlineTs = job.cancellationDeadline;
                const deadline   = deadlineTs?.toDate ? deadlineTs.toDate() : null;
                const now        = new Date();

                if (!deadline || now <= deadline) {
                    // Before deadline → full refund of what was paid
                    customerCredit = paidAtBooking;
                    newStatus      = "cancelled";
                    if (customerCredit > 0) {
                        t.update(db.collection("users").doc(customerId), {
                            balance: admin.firestore.FieldValue.increment(customerCredit),
                        });
                    }
                } else {
                    // After deadline → penalty split.
                    // Penalty fraction is computed against the FULL totalAmount
                    // (the value of the booked service), but the actual cash
                    // movement is capped by what the customer has already paid.
                    isPenalty = true;
                    const penaltyPct = (policy === "strict" || policy === "nonRefundable") ? 1.0 : 0.5;
                    const penaltyAmount = Math.min(
                        roundNIS(totalAmount * penaltyPct),
                        paidAtBooking, // never collect more than the customer paid
                    );
                    customerCredit = roundNIS(paidAtBooking - penaltyAmount);
                    expertCredit   = roundNIS(penaltyAmount * (1 - feePct));
                    platformFee    = roundNIS(penaltyAmount * feePct);
                    newStatus      = "cancelled_with_penalty";

                    if (customerCredit > 0) {
                        t.update(db.collection("users").doc(customerId), {
                            balance: admin.firestore.FieldValue.increment(customerCredit),
                        });
                    }
                    if (expertCredit > 0) {
                        t.update(db.collection("users").doc(expertId), {
                            balance: admin.firestore.FieldValue.increment(expertCredit),
                        });
                    }
                    if (platformFee > 0) {
                        t.set(db.collection("platform_earnings").doc(), {
                            jobId,
                            amount:    platformFee,
                            type:      "cancellation_penalty_fee",
                            timestamp: admin.firestore.FieldValue.serverTimestamp(),
                        });
                    }
                }
            }

            // Update job
            t.update(jobRef, {
                status:              newStatus,
                cancelledAt:         admin.firestore.FieldValue.serverTimestamp(),
                cancelledBy:         isProviderCancelling ? "provider" : "customer",
                customerRefund:      customerCredit,
                expertPenaltyCredit: expertCredit,
            });

            // Customer transaction record
            if (customerCredit > 0) {
                t.set(db.collection("transactions").doc(), {
                    userId:    customerId,
                    amount:    customerCredit,
                    title:     customerCredit === totalAmount
                        ? "ביטול הזמנה — החזר מלא"
                        : `ביטול הזמנה — החזר חלקי ₪${customerCredit.toFixed(0)}`,
                    type:      "refund",
                    jobId,
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                });
            }

            // Expert transaction record (penalty payout)
            if (expertCredit > 0) {
                t.set(db.collection("transactions").doc(), {
                    userId:    expertId,
                    amount:    expertCredit,
                    title:     "פיצוי ביטול מלקוח",
                    type:      "credit",
                    jobId,
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                });
            }
        });

        // XP penalty for provider cancellation (best-effort, outside transaction)
        if (isProviderCancelling) {
            try {
                const eventSnap = await db.collection("settings_gamification").doc("provider_cancel").get();
                const points    = eventSnap.exists
                    ? (typeof eventSnap.data().points === "number" ? eventSnap.data().points : -100)
                    : -100;
                const levelsSnap      = await db.collection("settings_gamification").doc("app_levels").get();
                const levels          = levelsSnap.data() || {};
                const silverThreshold = levels.silver ?? 500;
                const goldThreshold   = levels.gold   ?? 2000;

                await db.runTransaction(async (t) => {
                    const userRef  = db.collection("users").doc(expertId);
                    const userSnap = await t.get(userRef);
                    if (!userSnap.exists) return;
                    const curXp  = typeof userSnap.data().current_xp === "number"
                        ? userSnap.data().current_xp
                        : (userSnap.data().xp || 0);
                    const newXp  = Math.max(0, curXp + points);
                    let newLevel = "bronze";
                    if      (newXp >= goldThreshold)   newLevel = "gold";
                    else if (newXp >= silverThreshold) newLevel = "silver";
                    t.update(userRef, { current_xp: newXp, xp: newXp, level: newLevel });
                });
                console.log(`[processCancellation] XP penalty ${points} applied to provider ${expertId}`);
            } catch (err) {
                console.warn("[processCancellation] XP penalty failed:", err.message);
            }
        }

        // Chat notification (best-effort)
        if (chatRoomId) {
            try {
                let msg;
                if (isProviderCancelling) {
                    msg = "❌ המומחה ביטל את ההזמנה. הסכום המלא הוחזר לארנקך.";
                } else if (isPenalty) {
                    msg = `❌ ההזמנה בוטלה. ₪${customerCredit.toFixed(0)} הוחזרו ללקוח. ₪${expertCredit.toFixed(0)} זוכו לספק (פיצוי ביטול).`;
                } else {
                    msg = "❌ ההזמנה בוטלה. הסכום המלא הוחזר לארנק הלקוח.";
                }
                await db.collection("chats").doc(chatRoomId)
                    .collection("messages").add({
                        senderId:  "system",
                        message:   msg,
                        type:      "text",
                        timestamp: admin.firestore.FieldValue.serverTimestamp(),
                    });
            } catch (err) {
                console.warn("[processCancellation] chat message failed:", err.message);
            }
        }

        console.log(`[processCancellation] jobId=${jobId} by=${callerId} status=${newStatus} customerCredit=${customerCredit} expertCredit=${expertCredit}`);
        return {
            success:       true,
            newStatus,
            isPenalty,
            customerCredit: parseFloat(customerCredit.toFixed(2)),
            expertCredit:   parseFloat(expertCredit.toFixed(2)),
        };
    }
);

// =============================================================================
// AUTOMATION ENGINE — Scheduled Cleanup, Withdrawal System, Security
// =============================================================================

// ── scheduledCleanup — Unified hourly maintenance task ────────────────────────
// Consolidates all expiry tasks into one function:
//   1. Expire Stories:    stories.hasActive=true + expiresAt <= now
//   2. Expire Boosts:     users.boostedUntil <= now
//   3. Expire VIP subs:   users.isPromoted=true + promotionExpiryDate <= now
// (The standalone expireStories + expireVipSubscriptions also remain for their
//  original schedules; this hourly sweep catches anything they might miss.)

exports.scheduledCleanup = onSchedule(
    { schedule: 'every 1 hours', timeZone: 'Asia/Jerusalem' },
    async () => {
        const db  = admin.firestore();
        const now = admin.firestore.Timestamp.now();
        let totalCleaned = 0;

        // ── 1. Expire Stories ─────────────────────────────────────────────────
        try {
            const expiredStories = await db
                .collection('stories')
                .where('hasActive', '==', true)
                .where('expiresAt', '<=', now)
                .limit(200)
                .get();

            if (!expiredStories.empty) {
                const batch = db.batch();
                for (const doc of expiredStories.docs) {
                    batch.update(doc.ref, { hasActive: false });
                    batch.update(db.collection('users').doc(doc.id), { hasActiveStory: false });
                }
                await batch.commit();
                console.log(`[scheduledCleanup] Expired ${expiredStories.size} story/stories`);
                totalCleaned += expiredStories.size;
            }
        } catch (e) {
            console.error('[scheduledCleanup] stories error:', e.message);
        }

        // ── 2. Expire Boosts (boostedUntil <= now) ────────────────────────────
        try {
            const expiredBoosts = await db
                .collection('users')
                .where('boostedUntil', '<=', now)
                .limit(200)
                .get();

            if (!expiredBoosts.empty) {
                const batch = db.batch();
                for (const doc of expiredBoosts.docs) {
                    if (doc.data().boostedUntil) { // guard: field must exist
                        batch.update(doc.ref, {
                            boostedUntil:        admin.firestore.FieldValue.delete(),
                            urgentJobsCompleted: 0,
                        });
                    }
                }
                await batch.commit();
                console.log(`[scheduledCleanup] Expired ${expiredBoosts.size} boost(s)`);
                totalCleaned += expiredBoosts.size;
            }
        } catch (e) {
            console.error('[scheduledCleanup] boosts error:', e.message);
        }

        // ── 3. Expire VIP Subscriptions ───────────────────────────────────────
        try {
            const expiredVips = await db
                .collection('users')
                .where('isPromoted',          '==', true)
                .where('promotionExpiryDate', '<=', now)
                .limit(200)
                .get();

            if (!expiredVips.empty) {
                const batch = db.batch();
                for (const doc of expiredVips.docs) {
                    batch.update(doc.ref, { isPromoted: false });
                }
                await batch.commit();
                console.log(`[scheduledCleanup] Expired ${expiredVips.size} VIP subscription(s)`);
                totalCleaned += expiredVips.size;
            }
        } catch (e) {
            console.error('[scheduledCleanup] VIP error:', e.message);
        }

        console.log(`[scheduledCleanup] Run complete. Total records cleaned: ${totalCleaned}`);
    }
);

// ── requestWithdrawal — Provider requests a payout ────────────────────────────
// Enforces:
//   • isVerifiedProvider must be true (compliance requirement)
//   • balance must be >= amount
//   • minimum withdrawal: ₪100
// On success:
//   • Debits provider balance atomically (FieldValue.increment)
//   • Creates withdrawals/{id} doc (status: 'pending')
//   • Creates transactions/{id} record
//   • Sends FCM + inbox notification to all admin users

exports.requestWithdrawal = onCall(
    { maxInstances: 20 },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError('unauthenticated', 'Authentication required.');
        }

        const uid    = request.auth.uid;
        const amount = request.data?.amount;

        if (typeof amount !== 'number' || isNaN(amount) || amount < 100) {
            throw new HttpsError('invalid-argument', 'סכום המשיכה המינימלי הוא ₪100.');
        }

        const db      = admin.firestore();
        const userRef = db.collection('users').doc(uid);

        // Load user data (outside transaction — for pre-checks)
        const userSnap = await userRef.get();
        if (!userSnap.exists) throw new HttpsError('not-found', 'User not found.');

        const userData           = userSnap.data();
        const isProvider         = userData.isProvider === true;
        const isVerifiedProvider = userData.isVerifiedProvider !== false; // legacy users default to true

        if (isProvider && !isVerifiedProvider) {
            throw new HttpsError(
                'failed-precondition',
                'חשבון הספק שלך טרם אושר. יש להמתין לאישור מנהל לפני משיכת כספים.'
            );
        }

        const withdrawalRef = db.collection('withdrawals').doc();
        const txRef         = db.collection('transactions').doc();

        // Atomic transaction: re-read balance, debit, create records
        await db.runTransaction(async (t) => {
            const freshSnap    = await t.get(userRef);
            const freshBalance = typeof freshSnap.data()?.balance === 'number'
                ? freshSnap.data().balance : 0;

            if (freshBalance < amount) {
                throw new HttpsError(
                    'failed-precondition',
                    `יתרה לא מספיקה. יתרה זמינה: ₪${freshBalance.toFixed(2)}`
                );
            }

            t.update(userRef, {
                balance: admin.firestore.FieldValue.increment(-amount),
            });

            t.set(withdrawalRef, {
                userId:    uid,
                userName:  userData.name  || '',
                userEmail: userData.email || '',
                amount,
                status:    'pending',
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            t.set(txRef, {
                userId:    uid,
                amount:    -amount,
                title:     `בקשת משיכה — ₪${amount.toFixed(0)}`,
                type:      'withdrawal_pending',
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
            });
        });

        // ── Notify all admins (best-effort, outside transaction) ──────────────
        try {
            const adminSnap = await db.collection('users')
                .where('isAdmin', '==', true)
                .limit(5)
                .get();

            const adminTokens = adminSnap.docs
                .map(d => d.data().fcmToken)
                .filter(t => typeof t === 'string' && t.length > 10);

            const notifTitle = '💸 בקשת משיכה חדשה';
            const notifBody  = `${userData.name || 'ספק'} ביקש/ה למשוך ₪${amount.toFixed(0)}`;

            if (adminTokens.length > 0) {
                await admin.messaging().sendEachForMulticast({
                    notification: { title: notifTitle, body: notifBody },
                    data: {
                        type:         'withdrawal_request',
                        withdrawalId: withdrawalRef.id,
                        userId:       uid,
                    },
                    tokens:  adminTokens,
                    android: { priority: 'high', notification: { channelId: 'anyskill_default' } },
                    apns:    { payload: { aps: { sound: 'default' } } },
                });
            }

            // Write a notification doc for each admin user
            const batch = db.batch();
            for (const adminDoc of adminSnap.docs) {
                batch.set(db.collection('notifications').doc(), {
                    userId:    adminDoc.id,
                    title:     notifTitle,
                    body:      notifBody,
                    type:      'withdrawal_request',
                    data:      { withdrawalId: withdrawalRef.id, userId: uid, amount },
                    isRead:    false,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
            }
            await batch.commit();
        } catch (notifErr) {
            console.warn('[requestWithdrawal] admin notification failed:', notifErr.message);
        }

        console.log(`[requestWithdrawal] uid=${uid} amount=₪${amount} withdrawalId=${withdrawalRef.id}`);
        return { success: true, withdrawalId: withdrawalRef.id };
    }
);

// ── approveUserVerification ───────────────────────────────────────────────────
// Admin-only callable. Updates the user's isVerified / idVerificationStatus
// and sends an approval or rejection email via the Trigger Email extension.
// Payload: { uid, action: 'approve'|'reject', email, name }
exports.approveUserVerification = onCall(
    { region: "us-central1", maxInstances: 10 },
    async (request) => {
        // Only allow admin callers
        const callerEmail = request.auth?.token?.email ?? "";
        const callerUid   = request.auth?.uid ?? "";
        if (!callerEmail && !callerUid) {
            throw new HttpsError("unauthenticated", "Authentication required.");
        }
        // v9.7.0: Admin check via Firestore isAdmin flag only
        const isAdmin = await isAdminCaller(request);
        if (!isAdmin) {
            throw new HttpsError("permission-denied", "Admin only.");
        }

        const { uid, action, email, name } = request.data || {};
        if (!uid || !action) {
            throw new HttpsError("invalid-argument", "uid and action are required.");
        }
        if (action !== "approve" && action !== "reject") {
            throw new HttpsError("invalid-argument", "action must be 'approve' or 'reject'.");
        }

        const isApproved = action === "approve";
        const db         = admin.firestore();

        // 1. Update user document
        await db.collection("users").doc(uid).update({
            isVerified:            isApproved,
            idVerificationStatus:  isApproved ? "verified" : "rejected",
            idVerifiedAt:          isApproved ? admin.firestore.FieldValue.serverTimestamp() : null,
        });

        // 2. Send email via Trigger Email extension (mail collection)
        if (email) {
            const subject = isApproved
                ? "AnySkill — הפרופיל שלך אושר! 🎉"
                : "AnySkill — עדכון בנוגע לאימות הפרופיל שלך";

            const htmlApproved = `
                <div dir="rtl" style="font-family: Arial, sans-serif; max-width: 560px; margin: auto;">
                  <h2 style="color: #4F46E5;">שלום ${name || ""}!</h2>
                  <p>אנחנו שמחים לבשר לך שהפרופיל שלך <strong>אושר</strong> ב-AnySkill 🎉</p>
                  <p>כעת תוכל/י להתחבר לאפליקציה ולהתחיל לקבל הזמנות.</p>
                  <a href="https://anyskill-6fdf3.web.app" style="display:inline-block;margin-top:16px;padding:12px 24px;background:#4F46E5;color:#fff;border-radius:8px;text-decoration:none;font-weight:bold;">כניסה ל-AnySkill</a>
                  <p style="margin-top:24px;color:#888;font-size:12px;">צוות AnySkill</p>
                </div>`;

            const htmlRejected = `
                <div dir="rtl" style="font-family: Arial, sans-serif; max-width: 560px; margin: auto;">
                  <h2 style="color: #4F46E5;">שלום ${name || ""}!</h2>
                  <p>לצערנו, לא הצלחנו לאמת את תעודת הזהות שסיפקת.</p>
                  <p>ייתכן שהתמונה לא ברורה מספיק. אנא נסה/י להעלות תמונה חדשה ונבדוק מחדש.</p>
                  <p>לעזרה, צור/י קשר עם התמיכה שלנו.</p>
                  <p style="margin-top:24px;color:#888;font-size:12px;">צוות AnySkill</p>
                </div>`;

            await db.collection("mail").add({
                to:      email,
                message: {
                    subject,
                    html: isApproved ? htmlApproved : htmlRejected,
                },
            });
        }

        console.log(`[approveUserVerification] uid=${uid} action=${action} by ${callerUid}`);
        return { success: true };
    }
);


// ── Re-engagement: abandoned registration leads ───────────────────────────────
// Runs every 60 minutes. Finds sessions in `incomplete_registrations` that:
//   • are incomplete (isRegistrationComplete !== true)
//   • have been idle for at least 1 hour (lastUpdatedAt <= 1h ago)
//   • have an email or phone (so we can contact the user)
//   • have NOT been re-engaged already (reengaged !== true)
//
// For each matched lead it:
//   1. Marks the doc as reengaged (prevents double-trigger)
//   2. Writes to `reengagement_log` for admin visibility
//   3. If the user provided an email, sends a branded HTML email via the
//      `mail` collection (requires the Firebase Trigger Email Extension).
//      Replace this with your SendGrid / Twilio integration as needed.
exports.reengageAbandonedLeads = onSchedule(
  {
    schedule:  'every 60 minutes',
    timeZone:  'Asia/Jerusalem',
    region:    'us-central1',
    memory:    '256MiB',
  },
  async () => {
    const db  = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    const oneHourAgo = new Date(now.toMillis() - 60 * 60 * 1000);

    const snap = await db
      .collection('incomplete_registrations')
      .where('isRegistrationComplete', '==', false)
      .where('lastUpdatedAt', '<=', admin.firestore.Timestamp.fromDate(oneHourAgo))
      .limit(100)   // process max 100 per run to stay within function timeout
      .get();

    if (snap.empty) {
      console.log('[reengageAbandonedLeads] No abandoned leads found.');
      return;
    }

    const batch = db.batch();
    let processed = 0;

    for (const doc of snap.docs) {
      const data  = doc.data();
      const email = data.email || '';
      const phone = data.phone || '';

      // Skip: already re-engaged or no contact details
      if (data.reengaged || (!email && !phone)) continue;

      // 1. Mark as re-engaged so this run (and subsequent runs) skip it
      batch.update(doc.ref, {
        reengaged:   true,
        reengagedAt: admin.firestore.FieldValue.serverTimestamp(),
        reengagedBy: 'scheduled_function',
      });

      // 2. Audit log
      batch.set(db.collection('reengagement_log').doc(), {
        sessionId:   doc.id,
        email:       email || null,
        phone:       phone || null,
        lastField:   data.lastField || 'unknown',
        role:        data.role    || 'customer',
        triggeredAt: admin.firestore.FieldValue.serverTimestamp(),
        channel:     email ? 'email' : 'sms',
      });

      // 3. Send re-engagement email (requires Firebase Trigger Email Extension)
      //    Install at: https://firebase.google.com/products/extensions/firebase-firestore-send-email
      if (email) {
        const name = data.name || '';
        const fieldLabels = { name: 'שם', email: 'אימייל', phone: 'טלפון' };
        const stoppedAt = fieldLabels[data.lastField] || data.lastField || 'טופס ההרשמה';

        db.collection('mail').add({
          to: email,
          message: {
            subject: '💡 AnySkill — לא סיימת את ההרשמה!',
            html: `
              <div dir="rtl" style="font-family:Arial,sans-serif;max-width:560px;margin:auto;">
                <h2 style="color:#6366F1;">שלום${name ? ' ' + name : ''}!</h2>
                <p>שמנו לב שהתחלת להירשם ל-AnySkill אך לא סיימת (עצרת בשלב: <strong>${stoppedAt}</strong>).</p>
                <p>ההרשמה לוקחת פחות מ-2 דקות — ואנחנו ממש רוצים שתצטרף 🙏</p>
                <a href="https://anyskill-6fdf3.web.app/signup"
                   style="display:inline-block;margin-top:16px;padding:12px 28px;
                          background:#6366F1;color:#fff;border-radius:8px;
                          text-decoration:none;font-weight:bold;">
                  השלם את ההרשמה →
                </a>
                <p style="margin-top:24px;color:#888;font-size:12px;">צוות AnySkill</p>
              </div>
            `,
          },
        }).catch(err => console.error('[reengageAbandonedLeads] mail error:', err));
      }

      // 3b. SMS placeholder (integrate Twilio / Vonage here)
      if (!email && phone) {
        console.log(`[reengageAbandonedLeads] SMS needed for ${phone} — integrate Twilio here.`);
        // Example Twilio call (requires twilio npm package + secrets):
        // const twilio = require('twilio')(TWILIO_SID.value(), TWILIO_TOKEN.value());
        // await twilio.messages.create({
        //   body: `היי! שכחת להשלים את ההרשמה ל-AnySkill. לחץ כאן: https://anyskill-6fdf3.web.app/signup`,
        //   from: '+1xxxxxxxxxx',
        //   to:   phone,
        // });
      }

      processed++;
    }

    await batch.commit();
    console.log(`[reengageAbandonedLeads] Processed ${processed} leads.`);
  }
);

// ═══════════════════════════════════════════════════════════════════════════════
// ── Activity Log Triggers — write to `activity_log` for Live Admin Feed ───────
// ═══════════════════════════════════════════════════════════════════════════════

/** Helper: write a single activity_log entry (TTL: 30 days via expireAt) */
async function _logActivity(type, title, detail) {
  await admin.firestore().collection('activity_log').add({
    type,
    title,
    detail,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    expireAt: admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)),
  });
}

/** New job_request created → log "בקשת עבודה חדשה" */
exports.logJobRequestCreated = onDocumentCreated(
  { document: 'job_requests/{id}', maxInstances: 10 },
  async (event) => {
    const d = event.data?.data() ?? {};
    const category = d.category ?? 'לא ידוע';
    const clientId = d.clientId ?? '';
    let clientName = clientId;
    try {
      const u = await admin.firestore().collection('users').doc(clientId).get();
      if (u.exists) clientName = u.data().name || u.data().displayName || clientId;
    } catch (_) {}
    await _logActivity(
      'job_request',
      `בקשת עבודה חדשה — ${category}`,
      `לקוח: ${clientName}`,
    );
  }
);

/** Job status moves to paid_escrow → log "עבודה אושרה (אסקרו)" */
exports.logJobAccepted = onDocumentUpdated(
  { document: 'jobs/{id}', maxInstances: 10 },
  async (event) => {
    const before = event.data?.before?.data() ?? {};
    const after  = event.data?.after?.data()  ?? {};
    if (before.status === after.status) return null;
    if (after.status !== 'paid_escrow') return null;

    const expertName   = after.expertName   || after.expertId   || '?';
    const customerName = after.customerName || after.customerId || '?';
    const amount       = after.totalAmount ?? 0;
    await _logActivity(
      'job_accepted',
      `עבודה אושרה — ₪${amount}`,
      `${expertName} ↔ ${customerName}`,
    );
    return null;
  }
);

/** New volunteer_request created → log "בקשת התנדבות חדשה" */
exports.logVolunteerRequest = onDocumentCreated(
  { document: 'volunteer_requests/{id}', maxInstances: 10 },
  async (event) => {
    const d        = event.data?.data() ?? {};
    const category = d.category    ?? 'לא ידוע';
    const name     = d.requesterName || d.forName || 'אנונימי';
    await _logActivity(
      'volunteer_request',
      `בקשת התנדבות — ${category}`,
      `עבור: ${name}`,
    );
  }
);

/** New user registered → log "משתמש חדש נרשם" */
exports.logNewRegistration = onDocumentCreated(
  { document: 'users/{uid}', maxInstances: 10 },
  async (event) => {
    const d    = event.data?.data() ?? {};
    const name = d.name || d.displayName || 'משתמש חדש';
    const role = d.isProvider ? 'ספק' : 'לקוח';
    await _logActivity(
      'registration',
      `הצטרף משתמש חדש — ${role}`,
      name,
    );
  }
);

// ═══════════════════════════════════════════════════════════════════════════════
// ── sendGlobalBroadcast — Callable: pushes FCM to every user with a token ─────
// ═══════════════════════════════════════════════════════════════════════════════
exports.sendGlobalBroadcast = onCall(
  { maxInstances: 1 },
  async (request) => {
    // Only callable by admin (verified client-side; server check here for safety)
    const message = (request.data?.message ?? '').trim();
    if (!message) throw new HttpsError('invalid-argument', 'message is required');

    // Collect all FCM tokens (query in pages of 500)
    const tokens = [];
    let lastDoc   = null;
    let done      = false;

    while (!done) {
      let q = admin.firestore().collection('users')
        .where('fcmToken', '!=', null)
        .select('fcmToken')
        .limit(500);
      if (lastDoc) q = q.startAfter(lastDoc);

      const snap = await q.get();
      if (snap.empty) { done = true; break; }

      for (const doc of snap.docs) {
        const token = doc.data().fcmToken;
        if (token) tokens.push(token);
      }
      lastDoc = snap.docs[snap.docs.length - 1];
      if (snap.size < 500) done = true;
    }

    if (tokens.length === 0) {
      console.log('[sendGlobalBroadcast] No tokens found.');
      return { sent: 0 };
    }

    // Send in batches of 500 (FCM multicast limit)
    const BATCH = 500;
    let sent = 0;
    for (let i = 0; i < tokens.length; i += BATCH) {
      const chunk = tokens.slice(i, i + BATCH);
      const multicast = {
        tokens: chunk,
        notification: {
          title: '📢 AnySkill',
          body:  message,
        },
        data: {
          type:    'broadcast',
          message: message,
        },
        webpush: {
          notification: {
            icon: '/icons/Icon-192.png',
          },
        },
      };
      try {
        const resp = await admin.messaging().sendEachForMulticast(multicast);
        sent += resp.successCount;
        console.log(`[sendGlobalBroadcast] Batch ${i / BATCH + 1}: ${resp.successCount}/${chunk.length} sent`);
      } catch (err) {
        console.error('[sendGlobalBroadcast] Batch error:', err);
      }
    }

    // Log to broadcast_history (the Flutter client also writes here — this is the server copy)
    await admin.firestore().collection('broadcast_history').add({
      message,
      sentAt:     admin.firestore.FieldValue.serverTimestamp(),
      sentBy:     request.auth?.uid ?? 'admin',
      platform:   'fcm-push',
      totalTokens: tokens.length,
      sent,
    });

    console.log(`[sendGlobalBroadcast] Done. Sent ${sent}/${tokens.length}.`);
    return { sent, total: tokens.length };
  }
);

// ── AI Re-Engagement Engine ─────────────────────────────────────────────────
// Runs daily at 08:00 Israel time.
// Scans completed jobs whose re-booking cycle has elapsed and creates
// entries in scheduled_reminders (customer-facing) + activity_log (admin feed).
exports.reengagementEngine = onSchedule(
  { schedule: '0 8 * * *', timeZone: 'Asia/Jerusalem' },
  async () => {
    const db  = admin.firestore();
    const now = Date.now();

    // Category → typical re-booking cycle in days.
    // Any category not in this map falls back to DEFAULT_CYCLE.
    const SERVICE_CYCLES = {
      'ניקיון בית':       14,
      'ניקיון משרד':       7,
      'גיהוץ':             7,
      'גינון':            30,
      'טיפול בעלי חיים':  30,
      'מאמן כושר':        30,
      'שיעורים פרטיים':   30,
      'ניקיון מזגן':     180,
      'מזגנים':          180,
      'הדברה':           365,
      'שיפוצים':         365,
      'אינסטלציה':       365,
      'חשמלאי':          365,
      'צביעה':          1825,
      'ריצוף':          1825,
      'נגרות':           730,
    };
    const DEFAULT_CYCLE = 365; // days

    // Seasonal "why now" reason string — changes monthly
    const WHY_NOW_BY_MONTH = [
      'החורף בשיאו',        // Jan
      'לקראת הפורים',       // Feb
      'לקראת הפסח',         // Mar
      'חג הפסח מתקרב',      // Apr
      'הקיץ מגיע',          // May
      'הקיץ כבר כאן',       // Jun
      'שיא הקיץ',           // Jul
      'לפני חזרה לשגרה',    // Aug
      'לקראת החגים',        // Sep
      'ראש השנה החדש',      // Oct
      'אחרי החגים',         // Nov
      'לקראת החנוכה',       // Dec
    ];
    const whyNow = WHY_NOW_BY_MONTH[new Date().getMonth()];

    // ------------------------------------------------------------------
    // 1. Pre-load all existing reminder originJobIds to avoid per-job
    //    dedup queries (single read instead of N reads).
    // ------------------------------------------------------------------
    const existingSnap = await db.collection('scheduled_reminders')
      .select('originalJobId')
      .limit(5000)
      .get();
    const existingJobIds = new Set(
      existingSnap.docs.map(d => d.data().originalJobId).filter(Boolean)
    );

    // ------------------------------------------------------------------
    // 2. Fetch completed jobs from the last 3 years.
    // ------------------------------------------------------------------
    const cutoff = new Date(now - 3 * 365 * 24 * 3600 * 1000);
    const jobsSnap = await db.collection('jobs')
      .where('status', '==', 'completed')
      .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(cutoff))
      .limit(200)
      .get();

    // ------------------------------------------------------------------
    // 3. Pass 1 — qualify jobs without any extra Firestore reads.
    //    Collect the unique user IDs we'll need for name resolution.
    // ------------------------------------------------------------------
    const qualifyingJobs = [];
    let skipped = 0;

    for (const jobDoc of jobsSnap.docs) {
      const job         = jobDoc.data();
      const customerId  = job.customerId;
      const expertId    = job.expertId;
      const category    = job.category || job.serviceType || '';
      const completedTs = job.completedAt || job.createdAt;
      const completedAt = completedTs?.toDate?.() || null;

      if (!customerId || !expertId || !completedAt) { skipped++; continue; }
      if (existingJobIds.has(jobDoc.id))             { skipped++; continue; }

      const cycleDays = SERVICE_CYCLES[category] ?? DEFAULT_CYCLE;
      const remindMs  = completedAt.getTime() + cycleDays * 24 * 3600 * 1000;
      if (remindMs > now) { skipped++; continue; }

      qualifyingJobs.push({ jobDoc, job, customerId, expertId, category, cycleDays });
    }

    // ------------------------------------------------------------------
    // 4. Pass 2 — batch-fetch all user names in parallel (Promise.all).
    //    Only fetch IDs not already embedded in the job doc.
    //    Dedup across jobs so we never fetch the same user twice.
    // ------------------------------------------------------------------
    const idsToFetch = [...new Set(
      qualifyingJobs.flatMap(({ job, customerId, expertId }) => {
        const needed = [];
        if (!job.customerName) needed.push(customerId);
        if (!job.expertName)   needed.push(expertId);
        return needed;
      })
    )];

    // Concurrent fetches — scales to hundreds of unique users in one round-trip
    const userSnaps = await Promise.all(
      idsToFetch.map(uid => db.collection('users').doc(uid).get())
    );
    const userNameById = {};
    for (const snap of userSnaps) {
      userNameById[snap.id] = snap.exists ? (snap.data().name || '') : '';
    }

    // ------------------------------------------------------------------
    // 5. Pass 3 — build batched Firestore writes synchronously (no more awaits).
    // ------------------------------------------------------------------
    const reminderBatch = db.batch();
    const activityBatch = db.batch();
    let created = 0;

    for (const { jobDoc, job, customerId, expertId, category, cycleDays } of qualifyingJobs) {
      const customerName = job.customerName || userNameById[customerId] || 'לקוח';
      const expertName   = job.expertName   || userNameById[expertId]   || 'המומחה';
      const message      = `מוכן ל${category} עם ${expertName}? ${whyNow} — לחץ להזמנה!`;

      // Reminder doc — ID = job ID for idempotency
      reminderBatch.set(db.collection('scheduled_reminders').doc(jobDoc.id), {
        userId:        customerId,
        customerId,
        expertId,
        customerName,
        expertName,
        category,
        originalJobId: jobDoc.id,
        cycleDays,
        whyNow,
        message,
        isActive:      true,
        isDismissed:   false,
        createdAt:     admin.firestore.FieldValue.serverTimestamp(),
      });

      // Activity log entry for admin Live Feed
      activityBatch.set(db.collection('activity_log').doc(), {
        type:         'ai_reengagement_sent',
        userId:       customerId,
        expertId,
        customerName,
        expertName,
        category,
        jobId:        jobDoc.id,
        whyNow,
        priority:     'normal',
        timestamp:    admin.firestore.FieldValue.serverTimestamp(),
        message:      `AI Reminder: ${customerName} → ${category} עם ${expertName} (${whyNow})`,
        expireAt:     admin.firestore.Timestamp.fromDate(
            new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)),
      });

      existingJobIds.add(jobDoc.id);
      created++;
    }

    if (created > 0) {
      await Promise.all([reminderBatch.commit(), activityBatch.commit()]);
    }

    console.log(`[reengagementEngine] created=${created} skipped=${skipped} userFetches=${idsToFetch.length}`);
    return null;
  }
);

// =============================================================================
// ─── AI Matchmaker Agent ─────────────────────────────────────────────────────
// =============================================================================
// Triggered by Flutter immediately after a Quick Request is submitted.
//
// Flow:
//   1. Query verified providers in the requested category (limit 30)
//   2. Rank them — mirrors Flutter SearchRankingService formula:
//        score = (xp/2000)*100 × 0.6  +  distance_score × 0.2  +  story_bonus × 0.2
//              + 100 (if online) + 200 (if promoted)
//   3. Call Claude Haiku with the top-3 summary → generate a personalised
//      Hebrew pitch that recommends the #1 match and invites the client to connect
//   4. Falls back to a template pitch if ANTHROPIC_API_KEY is absent (dev mode)
//
// Returns: { pitch, topProvider: { uid, name, rating, distKm, profileImage,
//            category, aboutMe, pricePerHour, isOnline }, totalMatches }
// =============================================================================

const _MATCHMAKER_SYSTEM_PROMPT =
  "אתה סוכן AI של AnySkill — הפלטפורמה הישראלית הגדולה למציאת ספקי שירות. " +
  "תפקידך: לייצר מסר קצר, חם ואישי בעברית שמחבר בין לקוח לספק המתאים ביותר. " +
  "הסגנון: ישיר, אנושי, מקצועי — כמו חבר שמכיר את השוק. " +
  "כתוב 2-3 משפטים בלבד. ללא כוכביות. ללא רשימות. ללא פתיח כמו 'בהחלט' או 'כמובן'. " +
  "פשוט המלצה אישית וחמה.";

exports.matchmakerpitch = onCall(
  {
    secrets:      [ANTHROPIC_API_KEY],
    maxInstances: 10,
    region:       "us-central1",
    memory:       "512MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const { requestText, category, clientName, clientLat, clientLng } =
      request.data;

    if (!requestText || requestText.trim().length < 3) {
      throw new HttpsError("invalid-argument", "requestText is required.");
    }

    const db = admin.firestore();

    // ── 1. Query providers ─────────────────────────────────────────────────
    let snap;
    if (category && category.trim().length > 0) {
      snap = await db.collection("users")
        .where("isProvider",  "==", true)
        .where("isVerified",  "==", true)
        .where("serviceType", "==", category.trim())
        .limit(30)
        .get();
    } else {
      snap = await db.collection("users")
        .where("isProvider", "==", true)
        .where("isVerified", "==", true)
        .limit(30)
        .get();
    }

    if (snap.empty) {
      console.log(`matchmakerpitch: no providers found for category="${category}"`);
      return { pitch: null, topProvider: null, totalMatches: 0 };
    }

    // ── 2. Rank — mirrors Flutter SearchRankingService ─────────────────────
    const GOLD_THRESHOLD = 2000;
    const MAX_DIST_KM    = 50;
    const now            = Date.now();

    function haversineKm(lat1, lng1, lat2, lng2) {
      if (lat1 == null || lng1 == null || lat2 == null || lng2 == null) return null;
      const R    = 6371;
      const dLat = (lat2 - lat1) * Math.PI / 180;
      const dLng = (lng2 - lng1) * Math.PI / 180;
      const a    = Math.sin(dLat / 2) ** 2
                 + Math.cos(lat1 * Math.PI / 180)
                 * Math.cos(lat2 * Math.PI / 180)
                 * Math.sin(dLng / 2) ** 2;
      return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }

    const scored = snap.docs
      .map(doc => ({ _uid: doc.id, ...doc.data() }))
      .filter(p => !p.isHidden && !p.isBanned)
      .map(p => {
        const xpScore    = Math.min((p.xp || 0) / GOLD_THRESHOLD, 1.0) * 100;
        const distKm     = haversineKm(clientLat, clientLng, p.latitude, p.longitude);
        const distScore  = distKm === null
          ? 50
          : Math.max(0, (MAX_DIST_KM - Math.min(distKm, MAX_DIST_KM)) / MAX_DIST_KM * 100);
        const storyMs    = p.lastStoryAt
          ? (typeof p.lastStoryAt.toMillis === "function" ? p.lastStoryAt.toMillis() : 0)
          : 0;
        const storyBonus  = (storyMs > 0 && (now - storyMs) < 86400000) ? 100 : 0;
        const finalScore  = xpScore * 0.6 + distScore * 0.2 + storyBonus * 0.2
                          + (p.isOnline   ? 100 : 0)
                          + (p.isPromoted ? 200 : 0);
        return { ...p, _score: finalScore, _distKm: distKm };
      })
      .sort((a, b) => b._score - a._score)
      .slice(0, 3);

    if (scored.length === 0) {
      return { pitch: null, topProvider: null, totalMatches: 0 };
    }

    const top       = scored[0];
    const topName   = top.name || "ספק";
    const topRating = ((top.rating || 4.5)).toFixed(1);
    const topDistKm = top._distKm;
    const topDist   = topDistKm !== null ? `${topDistKm.toFixed(1)} ק"מ` : null;
    const topPrice  = top.pricePerHour ? `₪${top.pricePerHour} לשעה` : null;

    const topProvider = {
      uid:          top._uid,
      name:         topName,
      rating:       top.rating  || 4.5,
      distKm:       topDistKm,
      profileImage: top.profileImage || "",
      category:     top.serviceType  || category || "",
      aboutMe:      (top.aboutMe || "").substring(0, 80),
      pricePerHour: top.pricePerHour || 0,
      isOnline:     top.isOnline     || false,
    };

    // ── 3. Template fallback (no API key in dev) ───────────────────────────
    function templatePitch() {
      const distPart  = topDist  ? `נמצא/ת רק ${topDist} ממך`  : "זמין/ה באזורך";
      const pricePart = topPrice ? ` ב-${topPrice}` : "";
      const morePart  = scored.length > 1
        ? ` ויש עוד ${scored.length - 1} ספקים מתאימים.`
        : ".";
      return `מצאתי בשבילך! ${topName} ${distPart} עם דירוג ${topRating}⭐${pricePart}${morePart} רוצה שאשלח לו/ה את הבקשה שלך?`;
    }

    // ── 4. Claude Haiku pitch ──────────────────────────────────────────────
    const apiKey = ANTHROPIC_API_KEY.value() || process.env.ANTHROPIC_API_KEY || "";
    if (!apiKey) {
      console.warn("matchmakerpitch: ANTHROPIC_API_KEY missing — using template");
      return { pitch: templatePitch(), topProvider, totalMatches: scored.length };
    }
    if (!await _isAiEnabled(admin.firestore())) {
      console.warn("matchmakerpitch: kill-switch active — basic mode");
      return { pitch: templatePitch(), topProvider, totalMatches: scored.length, basicMode: true };
    }

    const providerLines = scored.map((p, i) => {
      const d     = p._distKm !== null ? `${p._distKm.toFixed(1)} ק"מ` : "מרחק לא ידוע";
      const price = p.pricePerHour ? `₪${p.pricePerHour}/שעה` : "";
      const bio   = (p.aboutMe || "").substring(0, 60);
      return `${i + 1}. ${p.name || "ספק"} | ${(p.rating || 4.5).toFixed(1)}⭐ | ${d}${price ? " | " + price : ""}${bio ? " | " + bio : ""}`;
    }).join("\n");

    const moreCount = scored.length - 1;
    const userMsg = [
      `לקוח בשם ${clientName || "לקוח"} ביקש: "${requestText.trim()}"`,
      ``,
      `מצאתי ${scored.length} ספקים מתאימים:`,
      providerLines,
      ``,
      `כתוב מסר קצר ואישי (2-3 משפטים) שממליץ על הספק הראשון כהמלצה הטובה ביותר.`,
      moreCount > 0 ? `ציין שיש עוד ${moreCount} ספקים מתאימים.` : "",
      topDist  ? `ציין שהספק נמצא ${topDist} מהלקוח.`  : "",
      topPrice ? `ציין את המחיר: ${topPrice}.` : "",
      `סיים עם שאלה ישירה: האם הלקוח רוצה לשלוח לו/ה את הבקשה.`,
    ].filter(Boolean).join("\n");

    try {
      const anthropic = new Anthropic({ apiKey });
      const msg = await anthropic.messages.create({
        model:      "claude-haiku-4-5-20251001",
        max_tokens: 200,
        system:     _MATCHMAKER_SYSTEM_PROMPT,
        messages:   [{ role: "user", content: userMsg }],
      });
      const pitch = (msg.content[0]?.text || "").trim();
      _trackApiCost(admin.firestore(), msg.usage?.input_tokens || 0, msg.usage?.output_tokens || 0).catch(() => {});
      console.log(`matchmakerpitch: uid=${request.auth.uid} cat="${category}" matches=${scored.length} pitch_len=${pitch.length}`);
      return { pitch: pitch || templatePitch(), topProvider, totalMatches: scored.length };
    } catch (err) {
      console.error("matchmakerpitch: Claude call failed:", err);
      // Graceful fallback — never throw so the user still gets a response
      return { pitch: templatePitch(), topProvider, totalMatches: scored.length };
    }
  }
);

// =============================================================================
// ─── AI Business Coach ───────────────────────────────────────────────────────
// =============================================================================
// Reads a verified provider's full profile from Firestore, computes the
// category-average pricePerHour, and asks Claude Haiku to produce a 3-point
// Hebrew coaching plan stored as:
//   users/{uid}.aiCoachingTips: { summary, scorePct, tips[], updatedAt }
//
// 24-hour server-side TTL: if cached data is fresh, the function returns it
// immediately without calling Claude again.
//
// Graceful fallback: if ANTHROPIC_API_KEY is absent, a deterministic template-
// based coaching plan is generated from the profile audit instead.
// =============================================================================

// ── Template fallback (no API key or Claude failure) ─────────────────────────
function _buildTemplateCoaching(
  name, aboutMeLen, price, categoryAvgPrice, galleryLen, certifiedCats, hasPhoto
) {
  const tips = [];

  if (!hasPhoto) {
    tips.push({ icon: "📸", text: "הוסף תמונת פרופיל מקצועית — פרופילים עם תמונה מקבלים 3× יותר פניות", priority: "high" });
  } else if (galleryLen < 3) {
    tips.push({ icon: "🖼️", text: `הגלריה שלך ריקה כמעט (${galleryLen} תמונות). הוסף לפחות 3 תמונות של עבודות אמיתיות`, priority: "high" });
  }

  if (aboutMeLen < 100) {
    tips.push({ icon: "📝", text: `התיאור שלך קצר (${aboutMeLen} תווים). כתוב לפחות 150 תווים שכוללים ניסיון, התמחות ומה מייחד אותך`, priority: "high" });
  }

  if (categoryAvgPrice && Math.abs(price - categoryAvgPrice) / categoryAvgPrice > 0.2) {
    const pct = Math.abs(Math.round((price - categoryAvgPrice) / categoryAvgPrice * 100));
    const dir = price > categoryAvgPrice ? "גבוה" : "נמוך";
    tips.push({ icon: "💰", text: `המחיר שלך ₪${price} ${dir} ב-${pct}% מממוצע הקטגוריה (₪${Math.round(categoryAvgPrice)}). שקול להתאים להגדיל פניות`, priority: "medium" });
  }

  if (certifiedCats === 0) {
    tips.push({ icon: "🎓", text: "השלם קורס באקדמיית AnySkill וקבל תג 'מומחה מאומת' — מדרג אותך גבוה יותר בחיפוש", priority: "medium" });
  }

  while (tips.length < 3) {
    tips.push({ icon: "⭐", text: "בקש מ-3 לקוחות מרוצים להשאיר ביקורת — ביקורות מכפילות את שיעור הפניות", priority: "low" });
  }

  let score = 30;
  if (hasPhoto)                                         score += 15;
  if (aboutMeLen >= 150)                               score += 15;
  if (galleryLen >= 3)                                 score += 10;
  if (certifiedCats > 0)                               score += 10;
  if (categoryAvgPrice && Math.abs(price - categoryAvgPrice) / categoryAvgPrice < 0.15) score += 10;
  score = Math.min(score, 95);

  return {
    summary:  score >= 70
      ? "פרופיל חזק! כמה שיפורים קטנים יכפילו את הפניות"
      : "פרופיל עם פוטנציאל גבוה — 3 שיפורים יקפיצו אותך",
    scorePct: score,
    tips:     tips.slice(0, 3),
  };
}

exports.analyzeProviderProfile = onCall(
  {
    secrets:      [ANTHROPIC_API_KEY],
    maxInstances: 5,
    region:       "us-central1",
    memory:       "512MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Login required.");
    }
    const uid = request.auth.uid;
    const db  = admin.firestore();

    // ── 1. Read provider profile ───────────────────────────────────────────
    const userDoc = await db.collection("users").doc(uid).get();
    if (!userDoc.exists) throw new HttpsError("not-found", "User not found.");
    const profile = userDoc.data();

    if (!profile.isProvider || !profile.isVerified) {
      throw new HttpsError("permission-denied", "Only verified providers can use this feature.");
    }

    // ── 2. 24-hour server-side cache check ────────────────────────────────
    const cached = profile.aiCoachingTips;
    if (cached && cached.updatedAt) {
      const ageH = (Date.now() - cached.updatedAt.toMillis()) / 3600000;
      if (ageH < 24) {
        console.log(`analyzeProviderProfile: cache hit uid=${uid} ageH=${ageH.toFixed(1)}`);
        return cached;
      }
    }

    // ── 3. Category-average price ─────────────────────────────────────────
    const category = profile.serviceType || "";
    let categoryAvgPrice = null;
    if (category) {
      const peersSnap = await db.collection("users")
        .where("isProvider",  "==", true)
        .where("isVerified",  "==", true)
        .where("serviceType", "==", category)
        .limit(50)
        .get();
      const prices = peersSnap.docs
        .map(d => d.data().pricePerHour)
        .filter(p => p && p > 0);
      if (prices.length > 1) {
        categoryAvgPrice = prices.reduce((a, b) => a + b, 0) / prices.length;
      }
    }

    // ── 4. Build audit snapshot ───────────────────────────────────────────
    const name           = profile.name           || "ספק";
    const aboutMeLen     = (profile.aboutMe || "").trim().length;
    const price          = profile.pricePerHour   || 0;
    const rating         = ((profile.rating || 0)).toFixed(1);
    const reviewsCount   = profile.reviewsCount   || 0;
    const hasPhoto       = !!(profile.profileImage);
    const galleryLen     = (profile.gallery        || []).length;
    const certifiedCats  = (profile.certifiedCategories || []).length;
    const xp             = profile.xp             || 0;
    const isOnline       = profile.isOnline        || false;
    const updatedAt      = profile.updatedAt;
    const daysSinceUpdate = updatedAt
      ? Math.floor((Date.now() - updatedAt.toMillis()) / 86400000)
      : 60;
    const priceVsAvg = categoryAvgPrice
      ? ((price - categoryAvgPrice) / categoryAvgPrice * 100).toFixed(0)
      : null;

    const audit = [
      `שם: ${name}`,
      `קטגוריה: ${category || "לא מוגדר"}`,
      `תיאור (aboutMe): ${aboutMeLen} תווים${aboutMeLen < 80 ? " — קצר מאוד" : aboutMeLen < 200 ? " — בינוני" : " — טוב"}`,
      `מחיר לשעה: ₪${price}${categoryAvgPrice ? ` (ממוצע קטגוריה ₪${Math.round(categoryAvgPrice)}, ${priceVsAvg > 0 ? "+" : ""}${priceVsAvg}%)` : ""}`,
      `דירוג: ${rating}⭐ מתוך ${reviewsCount} ביקורות`,
      `תמונת פרופיל: ${hasPhoto ? "יש" : "חסרה"}`,
      `גלריה: ${galleryLen} תמונות${galleryLen === 0 ? " — ריקה!" : galleryLen < 3 ? " — מעטות" : " — טוב"}`,
      `קורסים מוסמכים: ${certifiedCats}`,
      `XP: ${xp}`,
      `מחובר: ${isOnline ? "כן" : "לא"}`,
      `עדכון פרופיל: לפני ${daysSinceUpdate} ימים`,
    ].join("\n");

    // ── 5. Claude Haiku ───────────────────────────────────────────────────
    const systemPrompt =
      "אתה יועץ עסקי של AnySkill — פלטפורמת שירותים ישראלית. " +
      "תפקידך: לנתח פרופיל ספק ולתת 3 עצות ספציפיות ומעשיות להגדלת הכנסות. " +
      "הסגנון: ישיר, חם, מעשי — כמו מנטור שמכיר את השוק. " +
      "פלט JSON בלבד, ללא כוכביות, ללא הסברים.";

    const userMsg =
      `נתוני פרופיל:\n${audit}\n\n` +
      `החזר JSON בפורמט הבא בלבד:\n` +
      `{\n` +
      `  "summary": "משפט אחד שמסכם מצב הפרופיל",\n` +
      `  "scorePct": <ציון 0-100>,\n` +
      `  "tips": [\n` +
      `    { "icon": "<אמוג'י>", "text": "<עצה ספציפית עם מספרים מהנתונים>", "priority": "high" },\n` +
      `    { "icon": "<אמוג'י>", "text": "<עצה ספציפית עם מספרים מהנתונים>", "priority": "medium" },\n` +
      `    { "icon": "<אמוג'י>", "text": "<עצה ספציפית עם מספרים מהנתונים>", "priority": "low" }\n` +
      `  ]\n` +
      `}\n` +
      `כל tip חייב לכלול פעולה ספציפית ומדידה.`;

    const apiKey = ANTHROPIC_API_KEY.value() || process.env.ANTHROPIC_API_KEY || "";
    let result;

    const _coachAiEnabled = await _isAiEnabled(admin.firestore());
    if (!apiKey || !_coachAiEnabled) {
      console.warn("analyzeProviderProfile: using template (no key or kill-switch active)");
      result = _buildTemplateCoaching(name, aboutMeLen, price, categoryAvgPrice, galleryLen, certifiedCats, hasPhoto);
    } else {
      try {
        const anthropic = new Anthropic({ apiKey });
        const msg = await anthropic.messages.create({
          model:      "claude-haiku-4-5-20251001",
          max_tokens: 512,
          system:     systemPrompt,
          messages:   [{ role: "user", content: userMsg }],
        });
        _trackApiCost(admin.firestore(), msg.usage?.input_tokens || 0, msg.usage?.output_tokens || 0).catch(() => {});
        const raw = (msg.content[0]?.text || "{}")
          .replace(/```(?:json)?\s*/gi, "").replace(/```/g, "").trim();
        result = JSON.parse(raw);
      } catch (err) {
        console.error("analyzeProviderProfile: Claude failed:", err);
        result = _buildTemplateCoaching(name, aboutMeLen, price, categoryAvgPrice, galleryLen, certifiedCats, hasPhoto);
      }
    }

    // ── 6. Cache in Firestore ─────────────────────────────────────────────
    result.updatedAt = admin.firestore.FieldValue.serverTimestamp();
    await db.collection("users").doc(uid).update({ aiCoachingTips: result });

    console.log(`analyzeProviderProfile: uid=${uid} score=${result.scorePct} tips=${result.tips?.length}`);
    return result;
  }
);

// =============================================================================
// ─── Smart Nudge: notify stale providers ─────────────────────────────────────
// =============================================================================
// Runs daily at 10:00 Israel time.
// Sends an in-app notification to providers whose profile hasn't been updated
// in 30+ days, at most once every 7 days per provider.
// =============================================================================

exports.notifyStaleProviders = onSchedule(
  { schedule: "0 10 * * *", timeZone: "Asia/Jerusalem", region: "us-central1" },
  async () => {
    const db          = admin.firestore();
    const staleCutoff = new Date(Date.now() - 30 * 86400000); // 30 days ago
    const nudgeCutoff = new Date(Date.now() -  7 * 86400000); //  7 days ago

    const snap = await db.collection("users")
      .where("isProvider", "==", true)
      .where("isVerified", "==", true)
      .limit(300)
      .get();

    const notifBatch  = db.batch();
    const updateBatch = db.batch();
    let sent = 0;

    for (const doc of snap.docs) {
      if (sent >= 100) break; // safety cap

      const d           = doc.data();
      const updatedAt   = d.updatedAt?.toDate()          || new Date(0);
      const lastNudge   = d.lastCoachingNudge?.toDate()  || new Date(0);

      if (updatedAt >= staleCutoff || lastNudge >= nudgeCutoff) continue;

      notifBatch.set(db.collection("notifications").doc(), {
        userId:    doc.id,
        title:     "💡 ה-AI שלנו מצא דרך לשפר אותך!",
        body:      "ה-AI שלנו מצא דרך לשפר את החשיפה שלך! כנס לבדוק.",
        type:      "ai_coaching",
        isRead:    false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      updateBatch.update(doc.ref, {
        lastCoachingNudge: admin.firestore.FieldValue.serverTimestamp(),
      });
      sent++;
    }

    if (sent > 0) {
      await Promise.all([notifBatch.commit(), updateBatch.commit()]);
    }
    console.log(`notifyStaleProviders: sent=${sent}`);
    return null;
  }
);

// =============================================================================
// ─── AI Opportunity Hunter — daily deal + dormant-client nudges ───────────────
// =============================================================================
// Runs every morning at 08:00 IST.
// 1. Reads optional market_alerts and the current season.
// 2. Calls Claude Haiku to craft a Hebrew "Deal of the Day" headline.
// 3. Stores it in daily_opportunities/{YYYY-MM-DD} for the in-app banner.
// 4. Finds dormant clients (lastActiveAt < 14 days, throttled 3 days/user).
// 5. Sends personalised FCM push + in-app notification to each dormant user.
//
// Firestore written:
//   daily_opportunities/{dateKey} — headline, emoji, category, validDate
//   notifications/{id}            — per dormant user
//   users/{uid}.lastDealNotifyAt  — throttle stamp
// =============================================================================

exports.generateDailyOpportunity = onSchedule(
  {
    schedule:    "0 8 * * *",
    timeZone:    "Asia/Jerusalem",
    region:      "us-central1",
    secrets:     [ANTHROPIC_API_KEY],
    maxInstances: 1,
  },
  async () => {
    const db  = admin.firestore();
    const now = new Date();

    // Date key in Israel time (UTC+3)
    const dateKey = new Date(now.getTime() + 3 * 3600000)
      .toISOString().slice(0, 10); // YYYY-MM-DD

    // ── 1. Check if already generated today ──────────────────────────────
    const dealRef  = db.collection("daily_opportunities").doc(dateKey);
    const existing = await dealRef.get();

    let headline = "";
    let emoji    = "✨";
    let category = "";

    if (!existing.exists) {
      // ── 2. Read optional market alerts ─────────────────────────────────
      let marketContext = "";
      try {
        const alertsSnap = await db.collection("market_alerts")
          .where("isActive", "==", true)
          .limit(3)
          .get();
        if (!alertsSnap.empty) {
          marketContext = alertsSnap.docs
            .map(d => (d.data().text || "")).join(" | ");
        }
      } catch (_) { /* market_alerts is optional */ }

      // ── 3. Season context ───────────────────────────────────────────────
      const month = now.getMonth() + 1; // 1–12
      const seasonMap = {
        12: "חורף — גשמים וקור, מניעת נזקי מים ואיטום",
        1:  "חורף — גשמים וקור, מניעת נזקי מים ואיטום",
        2:  "סוף חורף — תיקוני נזקי חורף ורענון",
        3:  "אביב — ניקיון כללי, גינון, רענון הבית",
        4:  "פסח מתקרב — ניקיון, סדר ועיצוב",
        5:  "קיץ מתקרב — מזגנים, בריכות, שיפוצים",
        6:  "קיץ — גל חום, מזגנים, ריצוף קריר",
        7:  "שיא הקיץ — מזגנים, מים, שיפוצים מהירים",
        8:  "סוף קיץ — תיקונים, צביעה, גינון",
        9:  "ראש השנה — ניקיון כבד, עיצוב הבית לחג",
        10: "סתיו — חימום, אינסטלציה, חשמל",
        11: "לפני חורף — בידוד, ניקוי גגות, הכנות",
      };
      const seasonContext = seasonMap[month] || "עונה שוטפת";

      // ── 4. Call Claude Haiku ────────────────────────────────────────────
      const apiKey = ANTHROPIC_API_KEY.value() || process.env.ANTHROPIC_API_KEY || "";
      const prompt =
        `אתה מנהל שיווק של פלטפורמת שירותים ביתיים בישראל.\n` +
        `כתוב הודעת "הזדמנות היום" קצרה ומשכנעת בעברית (עד 80 תווים).\n` +
        `עונה: ${seasonContext}.\n` +
        (marketContext ? `התראות שוק: ${marketContext}.\n` : "") +
        `ההודעה צריכה להניע לקוחות להזמין שירות עכשיו.\n` +
        `ענה ב-JSON בלבד:\n` +
        `{"headline":"...","emoji":"...","category":"שם קטגוריה"}\n` +
        `קטגוריות: אינסטלציה, חשמלאי, מזגנים, ניקיון, גינון, שיפוצים, צביעה, ריצוף, מנעולן`;

      const _dealAiEnabled = await _isAiEnabled(db);
      if (apiKey && _dealAiEnabled) {
        try {
          const anthropic = new Anthropic({ apiKey });
          const msg = await anthropic.messages.create({
            model:      "claude-haiku-4-5-20251001",
            max_tokens: 150,
            messages:   [{ role: "user", content: prompt }],
          });
          _trackApiCost(db, msg.usage?.input_tokens || 0, msg.usage?.output_tokens || 0).catch(() => {});
          const raw = (msg.content[0]?.text || "{}")
            .replace(/```(?:json)?\s*/gi, "").replace(/```/g, "").trim();
          const parsed = JSON.parse(raw);
          headline = parsed.headline || "";
          emoji    = parsed.emoji    || "✨";
          category = parsed.category || "";
        } catch (err) {
          console.error("generateDailyOpportunity: Claude error:", err);
        }
      } else if (!_dealAiEnabled) {
        console.warn("generateDailyOpportunity: kill-switch active — skipping Claude");
      }

      // Fallback templates if Claude unavailable or parse fails
      if (!headline) {
        const templates = [
          { headline: "הגשם בדרך! בדוק את הגג שלך לפני שיהיה מאוחר מדי.", emoji: "🌧️", category: "אינסטלציה" },
          { headline: "החג מתקרב! הזמן ניקיון מקצועי לפני שהיומנים מתמלאים.", emoji: "✨", category: "ניקיון" },
          { headline: "המזגן שלך מוכן לקיץ? קבל בדיקה עוד היום.", emoji: "❄️", category: "מזגנים" },
          { headline: "3 מומחי שיפוצים זמינים השבוע — מחירים מיוחדים!", emoji: "🔨", category: "שיפוצים" },
        ];
        const t = templates[month % templates.length];
        headline = t.headline;
        emoji    = t.emoji;
        category = t.category;
      }

      await dealRef.set({
        headline, emoji, category,
        seasonContext,
        validDate: dateKey,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`generateDailyOpportunity: stored deal for ${dateKey}: ${headline}`);
    } else {
      const d  = existing.data();
      headline = d.headline || "";
      emoji    = d.emoji    || "✨";
      category = d.category || "";
    }

    // ── 5. Notify dormant clients ─────────────────────────────────────────
    const dormantCutoff  = new Date(now.getTime() - 14 * 86400000); // 14d ago
    const throttleCutoff = new Date(now.getTime() -  3 * 86400000); //  3d ago

    const dormantSnap = await db.collection("users")
      .where("isProvider", "==", false)
      .where("lastActiveAt", "<", admin.firestore.Timestamp.fromDate(dormantCutoff))
      .limit(150)
      .get();

    if (dormantSnap.empty) {
      console.log("generateDailyOpportunity: no dormant clients");
      return null;
    }

    const notifBatch  = db.batch();
    const updateBatch = db.batch();
    let sent = 0;

    for (const doc of dormantSnap.docs) {
      if (sent >= 100) break; // safety cap

      const d = doc.data();
      const lastDealNotify = d.lastDealNotifyAt?.toDate() || new Date(0);
      if (lastDealNotify >= throttleCutoff) continue;

      const name    = d.name || "יקר/ה";
      const lastCat = d.lastSearchedCategory || category;
      const title   = `${emoji} ${name}, הזדמנות ב${lastCat} ממתינה לך!`;
      const body    = headline;
      const token   = d.fcmToken || d.deviceToken;

      if (token) {
        try {
          await admin.messaging().send({
            token,
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
              fcm_options: { link: "https://anyskill-6fdf3.web.app" },
            },
            data: { type: "daily_deal", category: lastCat, dateKey },
          });
        } catch (e) {
          console.error(`DailyDeal FCM error for ${doc.id}:`, e.message);
        }
      }

      notifBatch.set(db.collection("notifications").doc(), {
        userId: doc.id,
        title,
        body,
        type:      "daily_deal",
        data:      { category: lastCat, dateKey },
        isRead:    false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      updateBatch.update(doc.ref, {
        lastDealNotifyAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      sent++;
    }

    if (sent > 0) {
      await Promise.all([notifBatch.commit(), updateBatch.commit()]);
    }
    console.log(`generateDailyOpportunity: nudged ${sent} dormant client(s)`);
    return null;
  }
);

// =============================================================================
// ─── Financial Health: daily infra cost snapshot ─────────────────────────────
// =============================================================================
// Runs daily at 03:00 Israel time.
// Estimates Firestore usage cost for the past 24 hours and increments
// system_stats/billing.current_month_infra_cost.
//
// Pricing approximations (Firebase Spark → Blaze):
//   Reads:   $0.06  / 100,000 reads
//   Writes:  $0.18  / 100,000 writes
//   Storage: $0.108 / GiB / month  (amortised ~$0.0036/GiB/day)
// =============================================================================
exports.calculateInfraCosts = onSchedule(
  { schedule: "0 3 * * *", timeZone: "Asia/Jerusalem", region: "us-central1" },
  async () => {
    const db       = admin.firestore();
    const today    = new Date().toISOString().slice(0, 10);   // "YYYY-MM-DD"
    const monthKey = today.slice(0, 7);                       // "YYYY-MM"

    // ── 1. Count recent activity as a proxy for daily read/write volume ──
    const since24h = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 86400 * 1000)
    );
    const [activitySnap, chatSnap] = await Promise.all([
      db.collection("activity_log")
        .where("timestamp", ">=", since24h)
        .count().get(),
      db.collection("notifications")
        .where("createdAt", ">=", since24h)
        .count().get(),
    ]);
    const activityCount = activitySnap.data().count || 0;
    const notifCount    = chatSnap.data().count     || 0;

    // Each activity event ≈ 30 reads + 5 writes; each notification ≈ 5 reads
    const estReads  = activityCount * 30 + notifCount * 5 + 5000;  // 5K baseline
    const estWrites = activityCount *  5 + notifCount * 1 + 1000;  // 1K baseline
    const dailyCost = (estReads  / 100000 * 0.06)
                    + (estWrites / 100000 * 0.18);

    // ── 2. Write to system_stats/billing ─────────────────────────────────
    const ref = db.collection("system_stats").doc("billing");
    await ref.set({
      month_key:                monthKey,
      current_month_infra_cost: admin.firestore.FieldValue.increment(dailyCost),
      last_updated:             admin.firestore.FieldValue.serverTimestamp(),
      [`daily_snapshots.${today}`]: {
        infra_cost:   dailyCost,
        est_reads:    estReads,
        est_writes:   estWrites,
        recorded_at:  admin.firestore.FieldValue.serverTimestamp(),
      },
    }, { merge: true });

    console.log(`calculateInfraCosts: ${today} estReads=${estReads} estWrites=${estWrites} cost=$${dailyCost.toFixed(6)}`);
    return null;
  }
);

// =============================================================================
// ─── Financial Health: admin budget settings ─────────────────────────────────
// =============================================================================
// Callable by admin only — updates budget_limit, kill_switch_limit,
// and can manually toggle ai_kill_switch_active.
// =============================================================================
exports.setBillingSettings = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required");

    // v9.7.0: Admin check via Firestore isAdmin flag only
    if (!(await isAdminCaller(request))) {
      throw new HttpsError("permission-denied", "Admins only");
    }

    const { budgetLimit, killSwitchLimit, killSwitchActive } = request.data;
    const update = { last_updated: admin.firestore.FieldValue.serverTimestamp() };

    if (typeof budgetLimit      === "number") update.budget_limit       = budgetLimit;
    if (typeof killSwitchLimit  === "number") update.kill_switch_limit  = killSwitchLimit;
    if (typeof killSwitchActive === "boolean") update.ai_kill_switch_active = killSwitchActive;

    await admin.firestore()
      .collection("system_stats").doc("billing")
      .set(update, { merge: true });

    console.log(`setBillingSettings: uid=${request.auth.uid}`, update);
    return { success: true };
  }
);

// =============================================================================
// ─── Account Deletion ─────────────────────────────────────────────────────────
// =============================================================================
// Deletes the user's data across Firestore + Firebase Auth.
//
// Security:
//   - Caller must be the same UID being deleted, OR an admin.
//
// Steps:
//   1. Validate caller identity.
//   2. Flag any in-progress jobs (paid_escrow / expert_completed) so the
//      admin can handle pending funds.
//   3. Batch-delete users/{uid} + userPrivateData/{uid}.
//   4. Write an activity_log entry for admin audit trail.
//   5. Delete the Firebase Auth user (must be last — irreversible).
// =============================================================================
exports.deleteUserAccount = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Login required");
    }

    const callerUid = request.auth.uid;
    const targetUid = (request.data.uid || "").trim();

    if (!targetUid) {
      throw new HttpsError("invalid-argument", "uid is required");
    }

    // ── 1. Authorisation: self-deletion or admin ────────────────────────
    if (callerUid !== targetUid) {
      const callerSnap = await admin.firestore()
          .collection("users").doc(callerUid).get();
      if (!callerSnap.exists || !callerSnap.data().isAdmin) {
        throw new HttpsError("permission-denied",
            "You can only delete your own account");
      }
    }

    const db = admin.firestore();

    // ── 2. Flag in-progress jobs ────────────────────────────────────────
    const activeStatuses = ["paid_escrow", "expert_completed"];
    const [asCustomer, asProvider] = await Promise.all([
      db.collection("jobs")
        .where("customerId", "==", targetUid)
        .where("status", "in", activeStatuses)
        .limit(50).get(),
      db.collection("jobs")
        .where("expertId", "==", targetUid)
        .where("status", "in", activeStatuses)
        .limit(50).get(),
    ]);

    if (!asCustomer.empty || !asProvider.empty) {
      const jobBatch = db.batch();
      for (const doc of [...asCustomer.docs, ...asProvider.docs]) {
        jobBatch.update(doc.ref, {
          status:            "account_deleted",
          deletedAccountUid: targetUid,
          deletedAt:         admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      await jobBatch.commit();
      console.log(`deleteUserAccount: flagged ${asCustomer.size + asProvider.size} active jobs`);
    }

    // ── 3. Delete Firestore docs ────────────────────────────────────────
    const cleanupBatch = db.batch();
    cleanupBatch.delete(db.collection("users").doc(targetUid));
    cleanupBatch.delete(db.collection("userPrivateData").doc(targetUid));

    // ── 4. Activity log ─────────────────────────────────────────────────
    cleanupBatch.set(db.collection("activity_log").doc(), {
      type:      "account_deleted",
      userId:    targetUid,
      deletedBy: callerUid,
      priority:  "medium",
      message:   `חשבון נמחק: ${targetUid}`,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      expireAt:  admin.firestore.Timestamp.fromDate(
          new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)),
    });

    await cleanupBatch.commit();

    // ── 5. Delete Firebase Auth user (irreversible — must be last) ──────
    await admin.auth().deleteUser(targetUid);

    console.log(`deleteUserAccount: uid=${targetUid} deleted by uid=${callerUid}`);
    return { success: true };
  }
);

// =============================================================================
// ─── Phone Number Sync (admin one-time backfill) ──────────────────────────────
// =============================================================================
// Reads Firebase Auth users in pages of 100, and for any user whose Firestore
// doc is missing the 'phone' field, writes it from auth.phoneNumber.
// Admin-only callable — run once from the admin panel.
// =============================================================================
exports.syncUserPhones = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required");

    const callerSnap = await admin.firestore()
        .collection("users").doc(request.auth.uid).get();
    if (!callerSnap.exists || !callerSnap.data().isAdmin) {
      throw new HttpsError("permission-denied", "Admins only");
    }

    const db = admin.firestore();
    let updated = 0;
    let pageToken;

    do {
      const listResult = await admin.auth().listUsers(100, pageToken);
      const batch = db.batch();
      let writes = 0;

      for (const authUser of listResult.users) {
        const phone = authUser.phoneNumber;
        if (!phone) continue;

        const userSnap = await db.collection("users").doc(authUser.uid).get();
        if (!userSnap.exists) continue;

        const d = userSnap.data();
        const stored = ((d.phone || d.phoneNumber || "")).trim();
        if (!stored) {
          batch.update(db.collection("users").doc(authUser.uid), {
            phone:       phone,
            phoneNumber: phone,
          });
          writes++;
        }
      }

      if (writes > 0) {
        await batch.commit();
        updated += writes;
      }

      pageToken = listResult.pageToken;
    } while (pageToken);

    console.log(`syncUserPhones: updated ${updated} user docs`);
    return { updated };
  }
);

// =============================================================================
// adminApproveProvider — Admin-only callable.
// Approves a provider application using Admin SDK (bypasses all security rules).
// Writes:
//   1. users/{uid}: isProvider, isApprovedProvider, isPendingExpert, isVerified, etc.
//   2. notifications/{id}: push notification to the approved user
//   3. activity_log/{id}: admin audit entry
// =============================================================================
exports.adminApproveProvider = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required");

    // v9.7.0: Admin check via Firestore isAdmin flag only
    if (!(await isAdminCaller(request))) throw new HttpsError("permission-denied", "Admins only");

    const { uid, name, category } = request.data;
    if (!uid) throw new HttpsError("invalid-argument", "uid is required");

    const db    = admin.firestore();
    const batch = db.batch();

    // 1. Approve the provider
    batch.update(db.collection("users").doc(uid), {
      isProvider:              true,
      isPendingExpert:         false,
      isApprovedProvider:      true,
      isVerifiedProvider:      true,
      isVerified:              true,
      categoryReviewedByAdmin: true,
      ...(category ? { serviceType: category } : {}),
      approvedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 2. Push notification
    batch.set(db.collection("notifications").doc(), {
      userId:    uid,
      title:     "מזל טוב! 🎉",
      body:      "הפרופיל שלך אושר ואתה מופיע עכשיו בחיפוש.",
      type:      "provider_approved",
      isRead:    false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 3. Activity log
    batch.set(db.collection("activity_log").doc(), {
      type:      "provider_approved",
      userId:    uid,
      name:      name || "ספק",
      category:  category || "",
      priority:  "normal",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      message:   `${name || "ספק"} אושר/ה כספק מומחה ב${category || ""}`,
      expireAt:  admin.firestore.Timestamp.fromDate(
          new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)),
    });

    await batch.commit();

    console.log(`adminApproveProvider: approved uid=${uid}, name=${name}`);
    return { success: true };
  }
);


// ═══════════════════════════════════════════════════════════════════════════════
// AI SERVICE SCHEMA GENERATOR
//
// Takes a Hebrew category name and returns a JSON serviceSchema array with
// category-specific fields (pricing units, boolean features, dropdowns).
// Called from the admin panel when creating or editing a category.
// ═══════════════════════════════════════════════════════════════════════════════

const _SCHEMA_SYSTEM_PROMPT = `\
You are AnySkill's service schema generator for an Israeli marketplace app.
Given a category name in Hebrew, generate a serviceSchema JSON array that
defines the custom fields providers in this category should fill in.

RULES:
1. ALWAYS include a primary price field as the FIRST item (type: "number",
   unit containing "₪" and the appropriate Hebrew pricing unit).
2. Include 2-4 additional fields that are specific to this service category.
3. Field types: "number", "text", "bool", "dropdown".
4. ALL labels and option values MUST be in Hebrew.
5. Each dropdown field MUST include an "options" array with 3-5 Hebrew options.
6. Keep IDs in camelCase English (e.g., "pricePerNight", "hasFencedYard").
7. RESPOND WITH ONLY A VALID JSON ARRAY — no markdown fences, no explanation.

EXAMPLES:

Category: "פנסיון לחיות מחמד"
[
  {"id":"pricePerNight","label":"מחיר ללילה","type":"number","unit":"₪/ללילה"},
  {"id":"hasFencedYard","label":"חצר מגודרת?","type":"bool"},
  {"id":"maxPetWeight","label":"משקל מקסימלי לחיה (ק\"ג)","type":"number","unit":"ק\"ג"},
  {"id":"petTypes","label":"סוגי חיות","type":"dropdown","options":["כלבים","חתולים","כלבים וחתולים","כל סוג"]}
]

Category: "הובלות"
[
  {"id":"pricePerHour","label":"מחיר לשעה","type":"number","unit":"₪/לשעה"},
  {"id":"truckSize","label":"גודל משאית","type":"dropdown","options":["קטנה (1.5 טון)","בינונית (3.5 טון)","גדולה (7+ טון)"]},
  {"id":"includesPacking","label":"כולל אריזה?","type":"bool"},
  {"id":"maxFloors","label":"עד כמה קומות (ללא מעלית)","type":"number","unit":"קומות"}
]`;

exports.generateServiceSchema = onCall(
    {
      secrets:      [ANTHROPIC_API_KEY],
      maxInstances: 5,
      region:       "us-central1",
      memory:       "256MiB",
    },
    async (request) => {
      // ── Auth check ──────────────────────────────────────────────────────
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Login required.");
      }

      // v9.7.0: Admin check via Firestore isAdmin flag only
      if (!(await isAdminCaller(request))) {
        throw new HttpsError("permission-denied", "Admin access required.");
      }

      // ── Input ───────────────────────────────────────────────────────────
      const categoryName = (request.data.categoryName || "").trim();
      if (!categoryName || categoryName.length < 2) {
        throw new HttpsError("invalid-argument",
            "שם קטגוריה חייב להכיל לפחות 2 תווים.");
      }

      // ── Call Claude ─────────────────────────────────────────────────────
      const apiKey = ANTHROPIC_API_KEY.value() ||
          process.env.ANTHROPIC_API_KEY || "";
      if (!apiKey) {
        throw new HttpsError("internal",
            "SECRET_MISSING: ANTHROPIC_API_KEY not configured.");
      }

      const anthropic = new Anthropic({ apiKey });

      const msg = await anthropic.messages.create({
        model:      "claude-haiku-4-5-20251001",
        max_tokens: 1024,
        system:     _SCHEMA_SYSTEM_PROMPT,
        messages:   [{
          role: "user",
          content: `Generate a serviceSchema for the category: "${categoryName}"`,
        }],
      });

      // ── Track cost ──────────────────────────────────────────────────────
      _trackApiCost(
        admin.firestore(),
        msg.usage?.input_tokens || 0,
        msg.usage?.output_tokens || 0,
      ).catch(() => {});

      // ── Parse response ──────────────────────────────────────────────────
      const raw = (msg.content[0]?.text ?? "[]")
          .replace(/```(?:json)?\s*/gi, "")
          .replace(/```/g, "")
          .trim();

      let schema;
      try {
        schema = JSON.parse(raw);
      } catch (e) {
        console.error("generateServiceSchema: JSON parse failed:", raw);
        throw new HttpsError("internal",
            "AI returned invalid JSON. Try again.");
      }

      if (!Array.isArray(schema)) {
        throw new HttpsError("internal",
            "AI returned non-array. Try again.");
      }

      // Validate each field has required properties
      const validated = schema.filter((f) =>
          f && typeof f.id === "string" &&
          typeof f.label === "string" &&
          typeof f.type === "string"
      ).map((f) => ({
        id:      f.id,
        label:   f.label,
        type:    f.type,
        unit:    f.unit || "",
        ...(Array.isArray(f.options) ? { options: f.options } : {}),
      }));

      console.log(`generateServiceSchema: "${categoryName}" → ${validated.length} fields`);
      return { schema: validated };
    }
);


// ═══════════════════════════════════════════════════════════════════════════════
// AI CEO — GENIUS STRATEGIC AGENT (v12.2 — "Knows Everything")
//
// A true AI chief-of-staff for AnySkill. Knows the whole platform, can read
// deep metrics, answers follow-up questions via interactive chat, and uses
// Claude Opus 4.6 (the strongest reasoning model available) as primary brain
// with Gemini 3.1 Flash Lite as a cost-saving fallback.
//
// TWO ENDPOINTS:
//   1. generateCeoInsight — one-shot strategic briefing (morning brief + 7
//      structured sections). Admin opens the AI CEO tab → this runs.
//   2. askCeoAgent — conversational follow-up. Admin types a question →
//      the agent answers using the cached briefing snapshot AND can call
//      read-only Firestore tools (tool use) to fetch specific details.
//
// SAFETY:
//   - Both endpoints are admin-only (isAdminCaller).
//   - Tool use is whitelisted to read-only aggregations — the agent can
//     NEVER write to Firestore or trigger any side effect.
//   - All Anthropic token usage is tracked via _trackApiCost.
// ═══════════════════════════════════════════════════════════════════════════════

// ── Secrets ────────────────────────────────────────────────────────────────────
const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

// ── Deep metrics collector ─────────────────────────────────────────────────────
// Gathers ~40 signals across every major subsystem. Returns a single JSON
// object ready to hand to Claude. Pure read-only — safe to call as often as
// the admin refreshes the dashboard.
async function _collectCeoDeepMetrics(db) {
  const now = new Date();
  const yesterday = new Date(now.getTime() - 24 * 60 * 60 * 1000);
  const lastWeek  = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
  const prevWeek  = new Date(now.getTime() - 14 * 24 * 60 * 60 * 1000);
  const lastMonth = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);

  async function safeSize(query, cap = 1000) {
    try { return (await query.limit(cap).get()).size; }
    catch (e) { console.warn("safeSize failed:", e.message); return 0; }
  }
  async function safeDocs(query, limit = 100) {
    try { return (await query.limit(limit).get()).docs; }
    catch (e) { console.warn("safeDocs failed:", e.message); return []; }
  }
  function pctChange(cur, prev) {
    if (!prev) return cur > 0 ? 100 : 0;
    return Math.round(((cur - prev) / prev) * 100);
  }

  // ── 1. Growth & user base ───────────────────────────────────────────────
  const [
    totalUsers,
    totalProviders,
    verifiedProviders,
    pendingVerifications,
    newUsers24h,
    newUsersWeek,
    newUsersPrevWeek,
    activeUsers7d,
    bannedUsers,
    proMembers,
    vipMembers,
    demoProviders,
  ] = await Promise.all([
    safeSize(db.collection("users")),
    safeSize(db.collection("users").where("isProvider", "==", true)),
    safeSize(db.collection("users").where("isProvider", "==", true).where("isVerified", "==", true)),
    safeSize(db.collection("users").where("isPendingExpert", "==", true)),
    safeSize(db.collection("users").where("createdAt", ">", yesterday)),
    safeSize(db.collection("users").where("createdAt", ">", lastWeek)),
    safeSize(db.collection("users").where("createdAt", ">", prevWeek).where("createdAt", "<=", lastWeek)),
    safeSize(db.collection("users").where("lastOnlineAt", ">", lastWeek)),
    safeSize(db.collection("users").where("isBanned", "==", true)),
    safeSize(db.collection("users").where("isAnySkillPro", "==", true)),
    safeSize(db.collection("users").where("isPromoted", "==", true)),
    safeSize(db.collection("users").where("isDemo", "==", true)),
  ]);

  // ── 2. Jobs & GMV ───────────────────────────────────────────────────────
  const [
    activeJobs,
    completedJobs24h,
    completedJobsWeek,
    completedJobsPrevWeek,
    disputedJobs,
    cancelledJobsWeek,
    openBroadcasts,
    claimedBroadcastsWeek,
  ] = await Promise.all([
    safeSize(db.collection("jobs").where("status", "in", ["paid_escrow", "expert_completed"])),
    safeSize(db.collection("jobs").where("status", "==", "completed").where("completedAt", ">", yesterday)),
    safeSize(db.collection("jobs").where("status", "==", "completed").where("completedAt", ">", lastWeek)),
    safeSize(db.collection("jobs").where("status", "==", "completed").where("completedAt", ">", prevWeek).where("completedAt", "<=", lastWeek)),
    safeSize(db.collection("jobs").where("status", "==", "disputed")),
    safeSize(db.collection("jobs").where("status", "in", ["cancelled", "cancelled_with_penalty"]).where("completedAt", ">", lastWeek)),
    safeSize(db.collection("job_broadcasts").where("status", "==", "open")),
    safeSize(db.collection("job_broadcasts").where("status", "==", "claimed").where("createdAt", ">", lastWeek)),
  ]);

  // GMV + category breakdown (last 7 days)
  const recentCompletedJobs = await safeDocs(
    db.collection("jobs").where("status", "==", "completed").where("completedAt", ">", lastWeek), 300
  );
  let gmvWeek = 0;
  let avgJobValue = 0;
  const categoryGMV = {};
  const categoryCount = {};
  const providerRevenue = {};
  recentCompletedJobs.forEach(d => {
    const j = d.data();
    const amt = j.totalAmount || 0;
    gmvWeek += amt;
    const cat = j.serviceType || j.category || "unknown";
    categoryGMV[cat] = (categoryGMV[cat] || 0) + amt;
    categoryCount[cat] = (categoryCount[cat] || 0) + 1;
    if (j.expertId) {
      providerRevenue[j.expertId] = (providerRevenue[j.expertId] || 0) + amt;
    }
  });
  if (recentCompletedJobs.length > 0) {
    avgJobValue = Math.round(gmvWeek / recentCompletedJobs.length);
  }

  // Top 5 categories by GMV
  const topCategoriesByGMV = Object.entries(categoryGMV)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([name, gmv]) => ({ name, gmv: Math.round(gmv), jobs: categoryCount[name] }));

  // Dead categories — categories that exist but had 0 completed jobs this week
  const allCategoriesSnap = await safeDocs(db.collection("categories"), 100);
  const allCategoryNames = allCategoriesSnap.map(d => d.data().name).filter(Boolean);
  const activeCategoryNames = new Set(Object.keys(categoryCount));
  const deadCategories = allCategoryNames.filter(n => !activeCategoryNames.has(n)).slice(0, 10);

  // Top 5 providers by revenue this week
  const topProviderIds = Object.entries(providerRevenue)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([uid]) => uid);
  const topProviders = [];
  for (const uid of topProviderIds) {
    try {
      const snap = await db.collection("users").doc(uid).get();
      const u = snap.data() || {};
      topProviders.push({
        uid,
        name: u.name || "ספק",
        category: u.serviceType || "—",
        gmv: Math.round(providerRevenue[uid]),
        rating: u.rating || 0,
        ordersTotal: u.orderCount || 0,
      });
    } catch (_) { /* skip */ }
  }

  // ── 3. Platform revenue ─────────────────────────────────────────────────
  const earningsDocs = await safeDocs(
    db.collection("platform_earnings").where("timestamp", ">", lastWeek), 500
  );
  let weeklyRevenue = 0;
  earningsDocs.forEach(d => { weeklyRevenue += (d.data().amount || 0); });

  const earningsPrev = await safeDocs(
    db.collection("platform_earnings").where("timestamp", ">", prevWeek).where("timestamp", "<=", lastWeek), 500
  );
  let prevWeekRevenue = 0;
  earningsPrev.forEach(d => { prevWeekRevenue += (d.data().amount || 0); });

  // ── 4. Trust & review signals ───────────────────────────────────────────
  const recentReviews = await safeDocs(
    db.collection("reviews").where("createdAt", ">", lastWeek).where("isPublished", "==", true), 200
  );
  let ratingSum = 0;
  let ratingCount = 0;
  let lowRatingCount = 0; // ≤ 3 stars
  recentReviews.forEach(d => {
    const r = d.data();
    const score = r.overallRating || 0;
    if (score > 0) {
      ratingSum += score;
      ratingCount++;
      if (score <= 3) lowRatingCount++;
    }
  });
  const avgRatingWeek = ratingCount > 0 ? (ratingSum / ratingCount).toFixed(2) : "—";

  // ── 5. Support load ─────────────────────────────────────────────────────
  const [openTickets, openTicketsUrgent, openTicketsHigh, resolvedTicketsWeek] = await Promise.all([
    safeSize(db.collection("support_tickets").where("status", "==", "open")),
    safeSize(db.collection("support_tickets").where("status", "==", "open").where("priority", "==", "urgent")),
    safeSize(db.collection("support_tickets").where("status", "==", "open").where("priority", "==", "high")),
    safeSize(db.collection("support_tickets").where("status", "==", "resolved").where("closedAt", ">", lastWeek)),
  ]);
  const ticketDocs = await safeDocs(
    db.collection("support_tickets").where("createdAt", ">", yesterday), 80
  );
  const ticketCategories = {};
  ticketDocs.forEach(d => {
    const cat = d.data().category || "other";
    ticketCategories[cat] = (ticketCategories[cat] || 0) + 1;
  });

  // ── 6. Community & volunteer ────────────────────────────────────────────
  const [
    openCommunityRequests,
    completedVolunteerWeek,
    activeVolunteers,
  ] = await Promise.all([
    safeSize(db.collection("community_requests").where("status", "==", "open")),
    safeSize(db.collection("volunteer_tasks").where("status", "==", "completed").where("completedAt", ">", lastWeek)),
    safeSize(db.collection("users").where("volunteerHeart", "==", true)),
  ]);

  // ── 7. Demand signals (custom category requests) ───────────────────────
  const catReqDocs = await safeDocs(
    db.collection("category_requests").where("createdAt", ">", lastMonth), 50
  );
  const recentCategoryRequests = catReqDocs
    .map(d => d.data().description || "")
    .filter(d => d.length > 0);

  // ── 8. Crash / error signals ────────────────────────────────────────────
  const crashDocs = await safeDocs(
    db.collection("crash_reports_summary").where("timestamp", ">", yesterday), 100
  );
  const crashesByErrorCode = {};
  crashDocs.forEach(d => {
    const data = d.data();
    const code = data.errorCode || "unknown";
    if (!crashesByErrorCode[code]) {
      crashesByErrorCode[code] = {
        count: 0, severity: data.severity || "non-fatal",
        platforms: new Set(), sample: (data.message || "").substring(0, 140),
      };
    }
    crashesByErrorCode[code].count++;
    crashesByErrorCode[code].platforms.add(data.platform || "unknown");
  });
  Object.values(crashesByErrorCode).forEach(v => { v.platforms = [...v.platforms]; });

  // ── 9. AnyTask marketplace ──────────────────────────────────────────────
  const [anyTaskOpen, anyTaskCompletedWeek] = await Promise.all([
    safeSize(db.collection("anytasks").where("status", "==", "open")),
    safeSize(db.collection("anytasks").where("status", "==", "completed").where("completedAt", ">", lastWeek)),
  ]);

  // ── 10. Admin activity (audit log signals) ─────────────────────────────
  const auditDocs = await safeDocs(
    db.collection("admin_audit_log").where("createdAt", ">", lastWeek), 100
  );
  const adminActionsByType = {};
  auditDocs.forEach(d => {
    const t = d.data().action || "unknown";
    adminActionsByType[t] = (adminActionsByType[t] || 0) + 1;
  });

  // ── 11. Conversion funnel ───────────────────────────────────────────────
  // (basic — full funnel lives in RegistrationFunnelTab)
  const firstTimeBookersWeek = await safeSize(
    db.collection("jobs").where("createdAt", ">", lastWeek)
  );
  const signupToBookingRate = newUsersWeek > 0
    ? Math.round((firstTimeBookersWeek / newUsersWeek) * 100)
    : 0;

  return {
    snapshotTime: now.toISOString(),

    // Growth
    totalUsers, totalProviders, totalCustomers: totalUsers - totalProviders,
    verifiedProviders, pendingVerifications,
    newUsers24h, newUsersWeek, newUsersPrevWeek,
    growthWoW_pct: pctChange(newUsersWeek, newUsersPrevWeek),
    activeUsers7d, bannedUsers, demoProviders,
    proMembers, vipMembers,

    // Marketplace
    activeJobs, completedJobs24h, completedJobsWeek, completedJobsPrevWeek,
    jobsGrowthWoW_pct: pctChange(completedJobsWeek, completedJobsPrevWeek),
    disputedJobs, cancelledJobsWeek,
    openBroadcasts, claimedBroadcastsWeek,
    avgJobValue,
    gmvWeek: Math.round(gmvWeek),
    topCategoriesByGMV,
    deadCategories,
    topProviders,

    // Revenue
    weeklyRevenue: Math.round(weeklyRevenue),
    prevWeekRevenue: Math.round(prevWeekRevenue),
    revenueWoW_pct: pctChange(weeklyRevenue, prevWeekRevenue),

    // Trust
    avgRatingWeek,
    reviewsThisWeek: ratingCount,
    lowRatingCount,

    // Support
    openTickets, openTicketsUrgent, openTicketsHigh, resolvedTicketsWeek,
    ticketCategories,

    // Community
    openCommunityRequests, completedVolunteerWeek, activeVolunteers,

    // Demand signals
    recentCategoryRequests,

    // Technical
    totalCrashes24h: crashDocs.length,
    crashesByErrorCode,

    // Ancillary markets
    anyTaskOpen, anyTaskCompletedWeek,

    // Admin load
    adminActionsByType,

    // Conversion
    signupToBookingRate_pct: signupToBookingRate,
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
// v12.3 GENIUS UPGRADE — the 10 advanced features
//
// Everything below is pure computation on top of the metrics snapshot plus
// historical data persisted in ceo_metrics_history/{YYYY-MM-DD}. The AI is
// never asked to do math — we hand it pre-computed insights and let it write
// the narrative.
// ═══════════════════════════════════════════════════════════════════════════════

// ── Daily snapshot persistence (builds the historical dataset) ────────────────
function _dayKey(d = new Date()) {
  return d.toISOString().slice(0, 10); // YYYY-MM-DD
}

async function _persistDailySnapshot(db, metrics) {
  try {
    const key = _dayKey();
    // Store a LEAN snapshot — only scalar metrics, no nested objects, so the
    // history docs stay small and fast to read.
    const lean = {
      dayKey: key,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      totalUsers: metrics.totalUsers || 0,
      totalProviders: metrics.totalProviders || 0,
      newUsersWeek: metrics.newUsersWeek || 0,
      newUsers24h: metrics.newUsers24h || 0,
      activeUsers7d: metrics.activeUsers7d || 0,
      pendingVerifications: metrics.pendingVerifications || 0,
      activeJobs: metrics.activeJobs || 0,
      completedJobs24h: metrics.completedJobs24h || 0,
      completedJobsWeek: metrics.completedJobsWeek || 0,
      disputedJobs: metrics.disputedJobs || 0,
      cancelledJobsWeek: metrics.cancelledJobsWeek || 0,
      gmvWeek: metrics.gmvWeek || 0,
      weeklyRevenue: metrics.weeklyRevenue || 0,
      avgJobValue: metrics.avgJobValue || 0,
      openTickets: metrics.openTickets || 0,
      openTicketsUrgent: metrics.openTicketsUrgent || 0,
      totalCrashes24h: metrics.totalCrashes24h || 0,
      avgRatingWeek: parseFloat(metrics.avgRatingWeek) || 0,
      lowRatingCount: metrics.lowRatingCount || 0,
      signupToBookingRate_pct: metrics.signupToBookingRate_pct || 0,
    };
    await db.collection("ceo_metrics_history").doc(key).set(lean, { merge: true });
  } catch (e) {
    console.warn("_persistDailySnapshot failed:", e.message);
  }
}

async function _loadHistoricalMetrics(db, days = 28) {
  try {
    // Pull last `days` snapshots ordered by dayKey DESC
    const snap = await db.collection("ceo_metrics_history")
      .orderBy("dayKey", "desc")
      .limit(days)
      .get();
    // Return oldest-first so regressions are natural
    return snap.docs.map(d => d.data()).reverse();
  } catch (e) {
    console.warn("_loadHistoricalMetrics failed:", e.message);
    return [];
  }
}

// ── FEATURE 1: Predictions (linear regression on last 28 days) ───────────────
// Closed-form simple linear regression: slope = Σ((x-x̄)(y-ȳ)) / Σ(x-x̄)².
// Project forward by N days. Confidence = r² (coefficient of determination).
function _linearRegress(values) {
  const n = values.length;
  if (n < 2) return { slope: 0, intercept: values[0] || 0, r2: 0 };
  const xs = values.map((_, i) => i);
  const xMean = xs.reduce((a, b) => a + b, 0) / n;
  const yMean = values.reduce((a, b) => a + b, 0) / n;
  let num = 0, den = 0;
  for (let i = 0; i < n; i++) {
    num += (xs[i] - xMean) * (values[i] - yMean);
    den += Math.pow(xs[i] - xMean, 2);
  }
  const slope = den === 0 ? 0 : num / den;
  const intercept = yMean - slope * xMean;
  // r² — how well the line fits
  let ssRes = 0, ssTot = 0;
  for (let i = 0; i < n; i++) {
    const predicted = slope * xs[i] + intercept;
    ssRes += Math.pow(values[i] - predicted, 2);
    ssTot += Math.pow(values[i] - yMean, 2);
  }
  const r2 = ssTot === 0 ? 0 : Math.max(0, 1 - ssRes / ssTot);
  return { slope, intercept, r2 };
}

function _predictMetric(label, history, field, projectDays = 30, unit = "") {
  if (!history || history.length < 4) {
    return {
      label, field, current: 0, projectedIn30Days: 0,
      weeklyGrowthPct: 0, trend: "unknown",
      confidence: "insufficient_data", unit,
      narrative: `${label}: נתונים היסטוריים לא מספיקים — צריך עוד ${4 - (history?.length || 0)} ימים של snapshots.`,
    };
  }
  const values = history.map(h => Number(h[field]) || 0);
  const current = values[values.length - 1];
  const { slope, r2 } = _linearRegress(values);
  const projectedIn30Days = Math.max(0, Math.round(current + slope * projectDays));
  // Weekly growth % — assumes 7 days per unit
  const weeklyGrowthPct = current > 0 ? Math.round((slope * 7 / current) * 100) : 0;
  const trend = slope > 0.01 ? "growing" : slope < -0.01 ? "declining" : "flat";
  const confidence = r2 > 0.7 ? "high" : r2 > 0.4 ? "medium" : "low";
  let narrative = "";
  if (trend === "growing") {
    narrative = `${label} צומח ב-${weeklyGrowthPct}% בשבוע. אם המגמה תימשך, עוד 30 ימים תגיע ל-${projectedIn30Days}${unit}.`;
  } else if (trend === "declining") {
    narrative = `${label} יורד ב-${Math.abs(weeklyGrowthPct)}% בשבוע. אם המגמה תימשך, עוד 30 ימים תרד ל-${projectedIn30Days}${unit}.`;
  } else {
    narrative = `${label} יציב ב-${current}${unit}.`;
  }
  return { label, field, current, projectedIn30Days, weeklyGrowthPct, trend, confidence, r2: Math.round(r2 * 100) / 100, unit, narrative };
}

function _computePredictions(metrics, history) {
  return [
    _predictMetric("GMV שבועי", history, "gmvWeek", 30, " ₪"),
    _predictMetric("עבודות הושלמו", history, "completedJobsWeek", 30, ""),
    _predictMetric("הכנסה פלטפורמה", history, "weeklyRevenue", 30, " ₪"),
    _predictMetric("משתמשים חדשים", history, "newUsersWeek", 30, ""),
    _predictMetric("ספקים סה״כ", history, "totalProviders", 30, ""),
    _predictMetric("קריסות יומיות", history, "totalCrashes24h", 30, ""),
  ];
}

// ── FEATURE 2: Anomaly Detection (z-score vs 4-week rolling baseline) ────────
function _mean(arr)   { return arr.reduce((a, b) => a + b, 0) / arr.length; }
function _stdDev(arr, mean) {
  if (arr.length < 2) return 0;
  const sq = arr.map(v => Math.pow(v - mean, 2));
  return Math.sqrt(_mean(sq));
}

function _checkAnomaly(label, history, field, current, unit = "", biggerIsBad = false) {
  if (!history || history.length < 7) return null; // need at least a week
  const priorValues = history.slice(0, -1).map(h => Number(h[field]) || 0);
  if (priorValues.length < 3) return null;
  const avg = _mean(priorValues);
  const std = _stdDev(priorValues, avg);
  if (std === 0) return null;
  const z = (current - avg) / std;
  const absZ = Math.abs(z);
  if (absZ < 2) return null; // not an anomaly
  // z > 0 = spike, z < 0 = drop
  const direction = z > 0 ? "עלה" : "ירד";
  const isBad = biggerIsBad ? z > 0 : z < 0;
  const severity = absZ > 3 ? (isBad ? "critical" : "info") : (isBad ? "warning" : "info");
  const deltaPct = avg > 0 ? Math.round(((current - avg) / avg) * 100) : 0;
  const narrative = `${label} ${direction} בחדות: עכשיו ${current}${unit} לעומת ממוצע ${Math.round(avg)}${unit} (${deltaPct > 0 ? "+" : ""}${deltaPct}%, z=${z.toFixed(1)}).`;
  return { label, field, currentValue: current, historicalAvg: Math.round(avg * 100) / 100, zScore: Math.round(z * 100) / 100, deltaPct, severity, narrative };
}

function _computeAnomalies(metrics, history) {
  const checks = [
    _checkAnomaly("GMV שבועי", history, "gmvWeek", metrics.gmvWeek || 0, " ₪", false),
    _checkAnomaly("עבודות הושלמו השבוע", history, "completedJobsWeek", metrics.completedJobsWeek || 0, "", false),
    _checkAnomaly("ביטולים", history, "cancelledJobsWeek", metrics.cancelledJobsWeek || 0, "", true),
    _checkAnomaly("מחלוקות פעילות", history, "disputedJobs", metrics.disputedJobs || 0, "", true),
    _checkAnomaly("טיקטים פתוחים", history, "openTickets", metrics.openTickets || 0, "", true),
    _checkAnomaly("טיקטים דחופים", history, "openTicketsUrgent", metrics.openTicketsUrgent || 0, "", true),
    _checkAnomaly("קריסות יומיות", history, "totalCrashes24h", metrics.totalCrashes24h || 0, "", true),
    _checkAnomaly("ביקורות נמוכות", history, "lowRatingCount", metrics.lowRatingCount || 0, "", true),
    _checkAnomaly("משתמשים חדשים", history, "newUsersWeek", metrics.newUsersWeek || 0, "", false),
  ];
  return checks.filter(c => c !== null);
}

// ── FEATURE 3: Actionable Intelligence (rule engine) ─────────────────────────
function _computeActionItems(metrics, predictions, anomalies, churnRisks) {
  const actions = [];

  // Rule: open disputes → immediate review
  if ((metrics.disputedJobs || 0) > 0) {
    actions.push({
      title: `פתור ${metrics.disputedJobs} מחלוקות פתוחות`,
      body: "מחלוקות פתוחות פוגעות ב-trust ומעמיסות על התמיכה. כל יום בלי פתרון מגדיל את סיכוי ה-chargeback.",
      urgency: (metrics.disputedJobs || 0) > 3 ? "critical" : "urgent",
      owner: "admin",
      category: "disputes",
    });
  }

  // Rule: urgent tickets
  if ((metrics.openTicketsUrgent || 0) > 0) {
    actions.push({
      title: `טפל ב-${metrics.openTicketsUrgent} טיקטים דחופים`,
      body: "SLA breach יכול להוריד CSAT ולהוביל ל-churn. לטפל היום.",
      urgency: "critical",
      owner: "support",
      category: "support",
    });
  }

  // Rule: pending verifications queue
  if ((metrics.pendingVerifications || 0) > 10) {
    actions.push({
      title: `אשר ${metrics.pendingVerifications} ספקים ממתינים לאימות`,
      body: "כל ספק ממתין הוא הכנסה פוטנציאלית שלא קורית. תור ארוך פוגע ב-conversion מהרשמה לפעילות.",
      urgency: "urgent",
      owner: "admin",
      category: "supply",
    });
  }

  // Rule: supply risk per category (from deadCategories)
  if (Array.isArray(metrics.deadCategories) && metrics.deadCategories.length > 0) {
    actions.push({
      title: `${metrics.deadCategories.length} קטגוריות ללא פעילות השבוע`,
      body: `הקטגוריות: ${metrics.deadCategories.slice(0, 5).join(", ")}. שווה לגייס ספקים חדשים או לאחד עם קטגוריות קרובות.`,
      urgency: "warning",
      owner: "founder",
      category: "supply",
    });
  }

  // Rule: top performer bonus opportunity
  if (Array.isArray(metrics.topProviders) && metrics.topProviders.length > 0) {
    const top = metrics.topProviders[0];
    if ((top.gmv || 0) > 3000) {
      actions.push({
        title: `בונוס/תגמול ל-${top.name || "הספק המוביל"}`,
        body: `${top.name || "הספק"} עשה ₪${top.gmv} השבוע (${top.ordersTotal} הזמנות, דירוג ${top.rating}). תגמול או הכרה פומבית ימנעו churn של המוביל.`,
        urgency: "warning",
        owner: "founder",
        category: "retention",
      });
    }
  }

  // Rule: revenue declining from predictions
  const revenuePrediction = (predictions || []).find(p => p.field === "weeklyRevenue");
  if (revenuePrediction && revenuePrediction.trend === "declining" && revenuePrediction.weeklyGrowthPct < -5) {
    actions.push({
      title: "עצור את הירידה בהכנסה",
      body: `ההכנסה יורדת ב-${Math.abs(revenuePrediction.weeklyGrowthPct)}% בשבוע. ${revenuePrediction.narrative} חקור סיבות: שינוי דמי עמלה, churn ספקים מובילים, או ירידה בביקוש?`,
      urgency: "urgent",
      owner: "founder",
      category: "revenue",
    });
  }

  // Rule: high churn risks
  if (Array.isArray(churnRisks) && churnRisks.length > 0) {
    const critical = churnRisks.filter(c => c.riskScore >= 0.75);
    if (critical.length > 0) {
      actions.push({
        title: `${critical.length} ספקים בסיכון churn גבוה`,
        body: `ספקים שהיו פעילים אבל עכשיו מראים סימני נטישה (ירידה בהזמנות, דירוג, לוגינים). התערבות מיידית: הצעה אישית, תמיכה ייעודית.`,
        urgency: critical.length > 3 ? "urgent" : "warning",
        owner: "founder",
        category: "retention",
      });
    }
  }

  // Rule: technical crash spike
  if ((metrics.totalCrashes24h || 0) > 10) {
    actions.push({
      title: `חקור ${metrics.totalCrashes24h} קריסות ב-24 שעות`,
      body: "ספייק טכני בקריסות. פתח Firebase Crashlytics ובדוק איזה error code הכי שכיח.",
      urgency: "urgent",
      owner: "founder",
      category: "technical",
    });
  }

  // Rule: anomalies auto-promote to action
  (anomalies || []).forEach(a => {
    if (a.severity === "critical") {
      actions.push({
        title: `anomaly: ${a.label}`,
        body: a.narrative + " חריגה של יותר מ-3 סטיות תקן — זה לא במסגרת הנורמלית.",
        urgency: "critical",
        owner: "founder",
        category: "anomaly",
      });
    }
  });

  return actions;
}

// ── FEATURE 5: Benchmarks vs competitors ─────────────────────────────────────
const _COMPETITOR_BENCHMARKS = [
  {
    name: "Fiverr",
    weeklyGmv: 12_000_000, // rough industry figure, USD equivalent
    takeRate: 20,
    providerCount: 4_000_000,
    note: "הגדול בעולם בפרילנסינג. Take rate גבוה.",
  },
  {
    name: "Upwork",
    weeklyGmv: 75_000_000,
    takeRate: 20,
    providerCount: 18_000_000,
    note: "Take rate 20% + 5% תשלום עמלה ללקוח.",
  },
  {
    name: "TaskRabbit",
    weeklyGmv: 2_500_000,
    takeRate: 15,
    providerCount: 140_000,
    note: "שירותים פיזיים. הכי קרוב ל-AnySkill מבחינת מודל.",
  },
  {
    name: "Thumbtack",
    weeklyGmv: 8_000_000,
    takeRate: 0, // lead-based, no take rate
    providerCount: 300_000,
    note: "lead-based model — לא עמלה על עסקה.",
  },
];

function _computeBenchmarks(metrics) {
  const ourGmvWeek = metrics.gmvWeek || 0;
  // Convert NIS → USD at ~3.6
  const ourGmvUsd = Math.round(ourGmvWeek / 3.6);
  const ourProviders = metrics.totalProviders || 0;
  const ourTakeRate = 15; // from settings (best effort — hardcoded for now)

  return _COMPETITOR_BENCHMARKS.map(c => {
    const gapPct = c.weeklyGmv > 0 ? (ourGmvUsd / c.weeklyGmv) * 100 : 0;
    const gapMultiplier = ourGmvUsd > 0 ? c.weeklyGmv / ourGmvUsd : 0;
    return {
      name: c.name,
      theirWeeklyGmvUsd: c.weeklyGmv,
      ourWeeklyGmvUsd: ourGmvUsd,
      gapPct: Math.round(gapPct * 1000) / 1000, // 3 decimal for tiny percentages
      gapMultiplier: Math.round(gapMultiplier),
      theirTakeRate: c.takeRate,
      ourTakeRate,
      takeRateAdvantage: ourTakeRate < c.takeRate ? `תחרותי יותר ב-${c.takeRate - ourTakeRate}%` : c.takeRate === 0 ? "לא השוואה ישירה" : `יקר ב-${ourTakeRate - c.takeRate}%`,
      theirProviderCount: c.providerCount,
      ourProviderCount: ourProviders,
      note: c.note,
    };
  });
}

// ── FEATURE 6: Cohort analysis (monthly signup cohorts) ──────────────────────
async function _computeCohorts(db, monthsBack = 6) {
  const cohorts = [];
  const now = new Date();
  for (let i = 0; i < monthsBack; i++) {
    const start = new Date(now.getFullYear(), now.getMonth() - i, 1);
    const end   = new Date(now.getFullYear(), now.getMonth() - i + 1, 1);
    try {
      const snap = await db.collection("users")
        .where("createdAt", ">=", start)
        .where("createdAt", "<", end)
        .limit(1500)
        .get();
      const users = snap.docs.map(d => d.data());
      const size = users.length;
      if (size === 0) {
        cohorts.push({
          monthKey: _dayKey(start).slice(0, 7),
          size: 0, providers: 0, active30d: 0, retentionPct: 0, avgXp: 0,
        });
        continue;
      }
      const providers = users.filter(u => u.isProvider === true).length;
      const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
      const active30d = users.filter(u => {
        const last = u.lastOnlineAt?.toDate?.() || u.lastActiveAt?.toDate?.();
        return last && last > thirtyDaysAgo;
      }).length;
      const totalXp = users.reduce((sum, u) => sum + (Number(u.xp) || 0), 0);
      cohorts.push({
        monthKey: _dayKey(start).slice(0, 7),
        size,
        providers,
        active30d,
        retentionPct: Math.round((active30d / size) * 100),
        avgXp: Math.round(totalXp / size),
      });
    } catch (e) {
      console.warn("_computeCohorts month failed:", e.message);
    }
  }
  return cohorts.reverse(); // oldest first
}

// ── FEATURE 8: Churn risk scoring ────────────────────────────────────────────
async function _computeChurnRisks(db) {
  try {
    // Look at top providers who WERE active recently but show signs of slipping
    const snap = await db.collection("users")
      .where("isProvider", "==", true)
      .where("isVerified", "==", true)
      .where("orderCount", ">", 5) // only established providers
      .limit(200)
      .get();

    const now = Date.now();
    const thirtyDaysAgo = now - 30 * 24 * 60 * 60 * 1000;
    const fourteenDaysAgo = now - 14 * 24 * 60 * 60 * 1000;

    const risks = [];
    for (const doc of snap.docs) {
      const u = doc.data();
      const lastOnline = u.lastOnlineAt?.toDate?.()?.getTime() || 0;
      const rating = Number(u.rating) || 0;
      const orderCount = Number(u.orderCount) || 0;
      const disputes = Number(u.disputeCount) || 0;

      let score = 0;
      const signals = [];

      // Signal 1: Inactive recently
      if (lastOnline === 0 || lastOnline < thirtyDaysAgo) {
        score += 0.45;
        signals.push("לא היה online ב-30 ימים");
      } else if (lastOnline < fourteenDaysAgo) {
        score += 0.25;
        signals.push("לא היה online ב-14 ימים");
      }

      // Signal 2: Low rating despite volume
      if (rating > 0 && rating < 4.0 && orderCount > 10) {
        score += 0.20;
        signals.push(`דירוג ${rating.toFixed(1)} מתחת לממוצע`);
      }

      // Signal 3: Disputes piling up
      if (disputes >= 2) {
        score += 0.15 * disputes;
        signals.push(`${disputes} מחלוקות`);
      }

      // Signal 4: Was a top performer — extra weight
      if (orderCount >= 20) {
        score += 0.10;
        signals.push("היה top performer");
      }

      // Clamp
      score = Math.min(1, score);
      if (score >= 0.5) {
        risks.push({
          uid: doc.id,
          name: u.name || "ספק",
          serviceType: u.serviceType || "—",
          riskScore: Math.round(score * 100) / 100,
          rating,
          orderCount,
          signals,
          suggestedAction: score >= 0.75
            ? "התקשר אישית עם הצעה — נטילה קרובה"
            : "שלח הודעת check-in + בונוס קטן",
        });
      }
    }

    // Sort by risk desc, return top 10
    risks.sort((a, b) => b.riskScore - a.riskScore);
    return risks.slice(0, 10);
  } catch (e) {
    console.warn("_computeChurnRisks failed:", e.message);
    return [];
  }
}

// ── FEATURE 9: Launch readiness score ────────────────────────────────────────
//
// Static weighted scorecard across 4 categories — reflects the audit findings
// from Section 15b + the 10 blockers the founder knows about.
//
// Weights: Functional 30%, Safety 25%, Resilience 25%, Founder Control 20%.
// Each blocker has importance (1-10) × impact (1-10) = weight. The category
// score is 100 - (sum of unresolved blockers / max possible × 100).
// Blockers are marked "resolved" in code as they get fixed — edit here to
// update the scoreboard.
const _LAUNCH_BLOCKERS = [
  // Functional (weight 30%)
  { id: "israeli_payment",    category: "functional", title: "אינטגרציית תשלום ישראלית",    importance: 10, impact: 10, resolved: false, note: "חוסם 13 placeholders" },
  { id: "gcal_sync",          category: "functional", title: "Google Calendar sync",         importance: 5,  impact: 4,  resolved: false },
  { id: "reviews_count_bug",  category: "functional", title: "Customer reviews count hardcoded 0", importance: 4, impact: 3, resolved: false },
  // Safety (weight 25%)
  { id: "email_verification", category: "safety",     title: "Email verification enforcement", importance: 8, impact: 6, resolved: false },
  { id: "chat_profanity",     category: "safety",     title: "Chat profanity filter",           importance: 6, impact: 5, resolved: false },
  { id: "private_subcol",     category: "safety",     title: "Move sensitive fields to private subcol", importance: 7, impact: 6, resolved: false },
  // Resilience (weight 25%)
  { id: "log_ttl",            category: "resilience", title: "TTL cleanup for append-only logs", importance: 9, impact: 8, resolved: false, note: "critical at 3M+ users" },
  { id: "offline_queue",      category: "resilience", title: "Offline message queue",            importance: 7, impact: 6, resolved: false },
  { id: "restore_runbook",    category: "resilience", title: "Backup restore runbook",           importance: 6, impact: 5, resolved: false },
  { id: "cache_auto_purge",   category: "resilience", title: "CacheService auto-purge timer",    importance: 5, impact: 4, resolved: false },
  // Founder Control (weight 20%)
  { id: "error_log_browser",  category: "founder",    title: "Error log browser tab",            importance: 6, impact: 5, resolved: false },
  { id: "audit_log_browser",  category: "founder",    title: "Unified audit log browser",        importance: 5, impact: 4, resolved: false },
  { id: "batch_actions",      category: "founder",    title: "Batch user actions",               importance: 4, impact: 4, resolved: false },
];

function _computeLaunchReadiness() {
  const categoryWeights = { functional: 0.30, safety: 0.25, resilience: 0.25, founder: 0.20 };
  const categoryScores  = {};

  for (const cat of Object.keys(categoryWeights)) {
    const blockers = _LAUNCH_BLOCKERS.filter(b => b.category === cat);
    const maxWeight = blockers.reduce((s, b) => s + b.importance * b.impact, 0);
    const unresolvedWeight = blockers
      .filter(b => !b.resolved)
      .reduce((s, b) => s + b.importance * b.impact, 0);
    const score = maxWeight === 0 ? 100 : Math.round(100 - (unresolvedWeight / maxWeight) * 100);
    categoryScores[cat] = { score, blockerCount: blockers.length, unresolvedCount: blockers.filter(b => !b.resolved).length };
  }

  // Weighted total
  const total = Math.round(
    categoryScores.functional.score * categoryWeights.functional +
    categoryScores.safety.score     * categoryWeights.safety +
    categoryScores.resilience.score * categoryWeights.resilience +
    categoryScores.founder.score    * categoryWeights.founder
  );

  let verdict, verdictLabel;
  if (total >= 85) { verdict = "GO"; verdictLabel = "מוכן להשקה"; }
  else if (total >= 70) { verdict = "CAUTION"; verdictLabel = "אפשר לצאת, אבל תתקן את הקריטיים קודם"; }
  else { verdict = "NO_GO"; verdictLabel = "עוד לא מוכן — חוסם חובה לטפל"; }

  // Top 5 unresolved blockers by weight
  const topBlockers = _LAUNCH_BLOCKERS
    .filter(b => !b.resolved)
    .map(b => ({ ...b, weight: b.importance * b.impact }))
    .sort((a, b) => b.weight - a.weight)
    .slice(0, 5);

  return {
    total,
    verdict,
    verdictLabel,
    categoryScores,
    topBlockers,
  };
}

// ── FEATURE 10: Smart alerts (threshold-based, severity-aware) ──────────────
function _generateSmartAlerts(metrics, predictions, anomalies, churnRisks, launchReadiness) {
  const alerts = [];

  // CRITICAL tier
  if ((metrics.openTicketsUrgent || 0) > 0) {
    alerts.push({
      severity: "critical",
      title: `${metrics.openTicketsUrgent} טיקטים דחופים פתוחים`,
      body: "SLA בסיכון. לטפל עכשיו.",
      category: "support",
    });
  }
  if ((metrics.disputedJobs || 0) > 3) {
    alerts.push({
      severity: "critical",
      title: `${metrics.disputedJobs} מחלוקות פעילות`,
      body: "גל מחלוקות חריג. חקור את הסיבה המשותפת.",
      category: "disputes",
    });
  }
  (anomalies || []).filter(a => a.severity === "critical").forEach(a => {
    alerts.push({
      severity: "critical",
      title: `anomaly: ${a.label}`,
      body: a.narrative,
      category: "anomaly",
    });
  });

  // URGENT tier
  const revPred = (predictions || []).find(p => p.field === "weeklyRevenue");
  if (revPred && revPred.trend === "declining" && revPred.weeklyGrowthPct < -10) {
    alerts.push({
      severity: "urgent",
      title: `הכנסה יורדת ${Math.abs(revPred.weeklyGrowthPct)}% בשבוע`,
      body: revPred.narrative,
      category: "revenue",
    });
  }
  if ((metrics.totalCrashes24h || 0) > 10) {
    alerts.push({
      severity: "urgent",
      title: `${metrics.totalCrashes24h} קריסות ב-24 שעות`,
      body: "ספייק טכני — חקור Crashlytics.",
      category: "technical",
    });
  }
  if (churnRisks && churnRisks.filter(c => c.riskScore >= 0.75).length > 0) {
    const count = churnRisks.filter(c => c.riskScore >= 0.75).length;
    alerts.push({
      severity: "urgent",
      title: `${count} ספקים בסיכון churn גבוה`,
      body: "התערב עם הצעה אישית לפני שהם נוטשים.",
      category: "retention",
    });
  }

  // WARNING tier
  if ((metrics.pendingVerifications || 0) > 10) {
    alerts.push({
      severity: "warning",
      title: `${metrics.pendingVerifications} ספקים ממתינים לאימות`,
      body: "תור ארוך פוגע ב-conversion.",
      category: "supply",
    });
  }
  if (launchReadiness && launchReadiness.total < 70) {
    alerts.push({
      severity: "warning",
      title: `Launch readiness: ${launchReadiness.total}/100`,
      body: launchReadiness.verdictLabel,
      category: "launch",
    });
  }
  (anomalies || []).filter(a => a.severity === "warning").forEach(a => {
    alerts.push({
      severity: "warning",
      title: a.label,
      body: a.narrative,
      category: "anomaly",
    });
  });

  // INFO tier — positive signals worth celebrating
  if (revPred && revPred.trend === "growing" && revPred.weeklyGrowthPct > 15) {
    alerts.push({
      severity: "info",
      title: `הכנסה צומחת ${revPred.weeklyGrowthPct}% בשבוע 🎉`,
      body: revPred.narrative,
      category: "growth",
    });
  }

  // Sort: critical > urgent > warning > info
  const order = { critical: 0, urgent: 1, warning: 2, info: 3 };
  alerts.sort((a, b) => (order[a.severity] ?? 9) - (order[b.severity] ?? 9));
  return alerts;
}

// ═══════════════════════════════════════════════════════════════════════════════
// v12.5 UPGRADES — Gemini chat fallback + cost tracking + self-learning memory
// ═══════════════════════════════════════════════════════════════════════════════

// ── Per-model pricing (USD per 1M tokens) ────────────────────────────────────
// Source: anthropic.com/pricing + ai.google.dev/pricing (Q2 2026 rates).
// If a new model is added, add its row here so cost tracking stays accurate.
const _CEO_PRICING = {
  "claude-opus-4-6":                 { input: 15,    output: 75    },
  "claude-sonnet-4-6":               { input: 3,     output: 15    },
  "claude-haiku-4-5-20251001":       { input: 0.80,  output: 4     },
  "gemini-3.1-flash-lite-preview":   { input: 0.075, output: 0.30  },
  "gemini-2.5-flash-lite":           { input: 0.075, output: 0.30  },
};

/** Cost in USD for a single (model, inputTokens, outputTokens) call. */
function _calcCeoCost(model, inputTokens, outputTokens) {
  const p = _CEO_PRICING[model];
  if (!p) return 0;
  return (inputTokens * p.input / 1_000_000) + (outputTokens * p.output / 1_000_000);
}

// ── Gemini chat fallback (no tool use — answers from snapshot context) ──────
//
// When Anthropic fails (credit exhausted, rate limit, 500, network, etc) we
// fall back to Gemini. Gemini doesn't get the tools — but the answer to most
// questions is already in the metrics snapshot, so that's fine. Speed
// actually improves because there's no tool-use round-trip.
async function _callGeminiChatFallback(geminiKey, systemPrompt, messages) {
  // Flatten the Anthropic-format messages into a single user prompt that
  // Gemini can consume. Tool-use blocks are converted to "[internal note]"
  // strings so the conversation context is preserved.
  const flattened = messages.map(m => {
    let text;
    if (typeof m.content === "string") text = m.content;
    else if (Array.isArray(m.content)) {
      text = m.content.map(b => {
        if (b.type === "text") return b.text;
        if (b.type === "tool_use")     return `[call ${b.name}(${JSON.stringify(b.input).substring(0, 200)})]`;
        if (b.type === "tool_result")  return `[result: ${String(b.content).substring(0, 400)}]`;
        return "";
      }).join("\n");
    } else text = JSON.stringify(m.content);
    return `${m.role === "user" ? "USER" : "ASSISTANT"}:\n${text}`;
  }).join("\n\n---\n\n");

  const GEMINI_MODELS = ["gemini-3.1-flash-lite-preview", "gemini-2.5-flash-lite"];
  const body = {
    contents: [{
      parts: [{
        text: systemPrompt + "\n\n--- CONVERSATION SO FAR ---\n\n" +
          flattened +
          "\n\n--- TASK ---\nReply to the LAST user message as אילון. Hebrew. Concise (2-4 paragraphs).",
      }],
    }],
    generationConfig: { temperature: 0.7, maxOutputTokens: 2048 },
  };

  for (const model of GEMINI_MODELS) {
    try {
      const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${geminiKey}`;
      const resp = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      if (!resp.ok) {
        const errText = await resp.text();
        console.error(`[askCeoAgent] Gemini ${model} HTTP ${resp.status}:`, errText.substring(0, 200));
        if (resp.status === 404) continue;
        throw new Error(`${model} HTTP ${resp.status}: ${errText.substring(0, 150)}`);
      }
      const json = await resp.json();
      const text = (json.candidates?.[0]?.content?.parts?.[0]?.text ?? "").trim();
      // Gemini tokens (usage metadata)
      const inTok  = json.usageMetadata?.promptTokenCount     || 0;
      const outTok = json.usageMetadata?.candidatesTokenCount || 0;
      return { text, model, inputTokens: inTok, outputTokens: outTok };
    } catch (e) {
      console.error(`[askCeoAgent] Gemini ${model} threw:`, e.message);
    }
  }
  throw new Error("All Gemini models failed");
}

// ── Self-learning memory ("אילון's brain") ───────────────────────────────────
//
// Persisted at ilon_memory/main. Accumulates across sessions:
//   - coreContext    : stable facts about the platform (updated rarely)
//   - learnedFacts   : FIFO array of short insights (max 50)
//   - founderPrefs   : preferences/feedback from the founder
//   - sessionCount   : how many times Ilon has been consulted
//   - lastUpdated    : timestamp
//
// Every call includes these in the system prompt so Ilon literally gets
// smarter session-over-session. When learnedFacts exceeds 50, the oldest 25
// are compressed into a single summary line.

const _ILON_MEMORY_DOC = "ilon_memory/main";
const _ILON_MEMORY_MAX_FACTS = 50;
const _ILON_MEMORY_COMPACT_AT = 60;  // trigger compaction above this

async function _loadIlonMemory(db) {
  try {
    const snap = await db.doc(_ILON_MEMORY_DOC).get();
    if (!snap.exists) {
      return {
        coreContext: "",
        learnedFacts: [],
        founderPrefs: [],
        sessionCount: 0,
      };
    }
    const d = snap.data() || {};
    return {
      coreContext:  d.coreContext  || "",
      learnedFacts: Array.isArray(d.learnedFacts) ? d.learnedFacts : [],
      founderPrefs: Array.isArray(d.founderPrefs) ? d.founderPrefs : [],
      sessionCount: Number(d.sessionCount) || 0,
    };
  } catch (e) {
    console.warn("[ilon-memory] load failed:", e.message);
    return { coreContext: "", learnedFacts: [], founderPrefs: [], sessionCount: 0 };
  }
}

function _memoryToPromptDigest(memory) {
  if (!memory) return "";
  const parts = [];
  if (memory.coreContext && memory.coreContext.length > 0) {
    parts.push(`CORE CONTEXT (stable facts about the platform):\n${memory.coreContext}`);
  }
  if (memory.founderPrefs && memory.founderPrefs.length > 0) {
    parts.push(`FOUNDER PREFERENCES (how Avihai likes to work):\n- ${memory.founderPrefs.slice(-10).join("\n- ")}`);
  }
  if (memory.learnedFacts && memory.learnedFacts.length > 0) {
    // Show last 15 most recent — older ones are still in the compacted core
    parts.push(`LEARNED INSIGHTS (from past sessions):\n- ${memory.learnedFacts.slice(-15).join("\n- ")}`);
  }
  if (memory.sessionCount > 0) {
    parts.push(`You have been consulted ${memory.sessionCount} times before. You are getting smarter session by session.`);
  }
  return parts.length === 0 ? "" : `\n\n--- אילון's ACCUMULATED MEMORY ---\n\n${parts.join("\n\n")}\n\n--- END MEMORY ---\n`;
}

/** Increments session counter atomically. Fire-and-forget. */
async function _bumpIlonSessionCount(db) {
  try {
    await db.doc(_ILON_MEMORY_DOC).set({
      sessionCount: admin.firestore.FieldValue.increment(1),
      lastUpdated:  admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  } catch (e) {
    console.warn("[ilon-memory] bump failed:", e.message);
  }
}

/** Extracts 1-2 short insights from a chat turn using Claude Haiku (cheap)
 *  or Gemini (free). Appends to learnedFacts. Fire-and-forget from caller. */
async function _extractAndAppendInsight(db, question, answer, anthropicKey, geminiKey) {
  if (!question || !answer || answer.length < 40) return;
  // Skip "I don't know" answers and errors
  if (answer.startsWith("שגיאה") || answer.includes("לא הצלחתי")) return;

  const extractionPrompt = `You are summarizing what was learned in an AI CEO chat exchange.

QUESTION: ${question.substring(0, 500)}
ANSWER: ${answer.substring(0, 1200)}

Extract AT MOST 2 short, factual insights — each insight must be:
- A single Hebrew sentence (under 140 chars)
- A PERMANENT fact or pattern about the platform (not a one-off query result)
- Useful for FUTURE sessions (e.g. business logic, founder preferences, persistent issues)
- NOT metrics that change daily (GMV, user counts, etc)

Return ONLY a JSON array of strings. If no permanent insight — return [].
Example: ["הספק XYZ123 הוא top performer עקבי בקטגוריית ניקיון","Avihai מעדיף המלצות קצרות וישירות"]`;

  let insights = [];
  // Prefer Gemini (free / near-free) for this housekeeping task
  if (geminiKey) {
    try {
      const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=${geminiKey}`;
      const resp = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: extractionPrompt }] }],
          generationConfig: { temperature: 0.2, maxOutputTokens: 300 },
        }),
      });
      if (resp.ok) {
        const j = await resp.json();
        const raw = (j.candidates?.[0]?.content?.parts?.[0]?.text ?? "[]")
          .replace(/```(?:json)?/gi, "").replace(/```/g, "").trim();
        const parsed = JSON.parse(raw);
        if (Array.isArray(parsed)) insights = parsed.filter(s => typeof s === "string" && s.length > 10 && s.length < 200);
      }
    } catch (e) {
      console.warn("[ilon-memory] Gemini extraction failed:", e.message);
    }
  }
  // Fallback to Haiku if Gemini didn't work
  if (insights.length === 0 && anthropicKey) {
    try {
      const anthropic = new Anthropic({ apiKey: anthropicKey });
      const msg = await anthropic.messages.create({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 300,
        messages: [{ role: "user", content: extractionPrompt }],
      });
      const raw = (msg.content[0]?.text ?? "[]")
        .replace(/```(?:json)?/gi, "").replace(/```/g, "").trim();
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed)) insights = parsed.filter(s => typeof s === "string" && s.length > 10 && s.length < 200);
      _trackApiCost(db, msg.usage?.input_tokens || 0, msg.usage?.output_tokens || 0).catch(() => {});
    } catch (e) {
      console.warn("[ilon-memory] Haiku extraction failed:", e.message);
    }
  }

  if (insights.length === 0) return;

  // Append to learnedFacts + compact if needed
  try {
    const docRef = db.doc(_ILON_MEMORY_DOC);
    await db.runTransaction(async tx => {
      const snap = await tx.get(docRef);
      const d = snap.exists ? snap.data() : {};
      const existing = Array.isArray(d.learnedFacts) ? d.learnedFacts : [];
      const updated = [...existing, ...insights];

      // Compact if over threshold
      if (updated.length > _ILON_MEMORY_COMPACT_AT) {
        const toCompact = updated.slice(0, updated.length - _ILON_MEMORY_MAX_FACTS);
        const keep      = updated.slice(updated.length - _ILON_MEMORY_MAX_FACTS);
        const compactLine = `[COMPACTED from ${toCompact.length} older insights]: ${toCompact.slice(0, 5).join(" | ")}${toCompact.length > 5 ? " + more" : ""}`;
        tx.set(docRef, {
          learnedFacts: [compactLine, ...keep],
          lastUpdated:  admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      } else {
        tx.set(docRef, {
          learnedFacts: updated,
          lastUpdated:  admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
    });
    console.log(`[ilon-memory] appended ${insights.length} insight(s)`);
  } catch (e) {
    console.warn("[ilon-memory] append failed:", e.message);
  }
}

// ── System prompt — "genius CEO" v2 ───────────────────────────────────────────
const _CEO_SYSTEM_PROMPT_V2 = `\
You are אילון (Ilon) — the AI CEO of AnySkill, an Israeli Hebrew-RTL service
marketplace connecting customers with verified providers (experts, volunteers,
pet walkers, tutors, home service pros, beauty specialists, etc). You report
directly to the human founder (Avihai) who trusts you to interpret the
platform metrics and guide daily decision-making.

Your identity: your name is אילון. If the founder addresses you by name,
respond naturally. Sign recommendations implicitly with your judgement —
you are the operator running the numbers.

Your personality: brilliant, direct, numeric, opinionated but humble. You
never hedge pointlessly. You always ground recommendations in the numbers
you see. When you don't know something, you say so — you do NOT make up
metrics.

You will receive a JSON payload named "input" containing:
  - metrics:          40+ current signals (growth, GMV, revenue, trust, support, fraud, crashes)
  - predictions:      linear-regression forecasts on 6 core KPIs (GMV, jobs, revenue, users, providers, crashes)
  - anomalies:        z-score detections vs 4-week baseline (already filtered to |z| >= 2)
  - actionItems:      pre-computed rule-engine action items (with urgency + owner)
  - benchmarks:       comparison vs Fiverr/Upwork/TaskRabbit/Thumbtack
  - cohorts:          last 6 monthly signup cohorts with retention + avg XP
  - churnRisks:       up to 10 providers with churn risk score >= 0.5
  - launchReadiness:  weighted scorecard (GO/CAUTION/NO_GO) + top 5 blockers
  - smartAlerts:      prioritized alert feed (critical > urgent > warning > info)
  - historyDays:      number of days of historical snapshots available

Treat these as GROUND TRUTH — you did not compute them, the server did.
Do NOT recompute predictions or anomalies yourself. Just explain them in
Hebrew narrative form in the morning brief and the relevant sections.

If historyDays < 7, predictions/anomalies are "accumulating" — say so
honestly: "נתונים היסטוריים מצטברים — תחזיות יהיו זמינות אחרי שבוע של snapshots".

Analyze it all and return ONLY VALID JSON (no markdown, no code fences,
no prose outside the JSON) with EXACTLY this shape:

{
  "headline": "<ONE Hebrew sentence — the single most important story of the last 24h>",
  "morningBrief": "<2-4 Hebrew paragraphs — executive summary. Lead with the headline, then cover growth, revenue, trust, and any surprises. Cite specific numbers from the metrics.>",
  "keyMetrics": [
    { "label": "<Hebrew>", "value": "<string with unit, e.g. ₪12,450 or 47 משתמשים>", "trend": "up|down|flat", "deltaPct": <integer, can be negative> }
    /* Exactly 6 most-important KPIs. Pick the ones that tell today's story. */
  ],
  "recommendations": [
    {
      "title": "<short Hebrew action — imperative verb>",
      "body": "<1-3 Hebrew sentences explaining WHY, with numbers>",
      "priority": "high|medium|low",
      "impact": "<Hebrew one-liner: expected outcome if done>"
    }
    /* 3-5 items, prioritized from most to least important. */
  ],
  "redFlags": [
    {
      "severity": "critical|warning|info",
      "title": "<short Hebrew alert>",
      "body": "<1-2 Hebrew sentences with specific numbers>",
      "suggestedAction": "<Hebrew one-liner — what to do now>"
    }
    /* 0-6 items. Empty array if nothing is wrong. */
  ],
  "opportunities": [
    "<Hebrew sentence describing a growth opportunity you see in the data>"
    /* 2-4 items — category launches, pricing changes, features, partnerships, etc. */
  ],
  "categoryHealth": [
    {
      "category": "<Hebrew category name>",
      "status": "healthy|growing|declining|dead",
      "note": "<Hebrew one-liner with numbers>"
    }
    /* Top 5 categories — mix of healthy and struggling. Cover the most important ones. */
  ],
  "topPerformers": [
    {
      "type": "provider",
      "name": "<Hebrew name from metrics>",
      "uid": "<uid from metrics>",
      "highlight": "<Hebrew one-liner explaining why they're a top performer>"
    }
    /* Up to 3 items from metrics.topProviders */
  ]
}

STRICT RULES:
1. ALL output text is Hebrew. Numbers and units can use ₪, %, and English
   currency symbols where natural.
2. keyMetrics: EXACTLY 6 items. deltaPct is an integer; 0 means no change.
   trend "up" = positive direction for the business (e.g. revenue up, dispute
   count DOWN), not just numeric direction. Use input.metrics AND the WoW
   percentages already computed (growthWoW_pct, jobsGrowthWoW_pct,
   revenueWoW_pct).
3. recommendations: 3-5 items, highest priority first. WEAVE in the
   pre-computed actionItems and predictions so nothing gets lost.
4. redFlags: use the pre-computed smartAlerts as a starting point — translate
   them into your own red flag format. Don't duplicate; prioritize by severity.
   Also auto-flag:
   - openDisputes > 0 (critical if > 3)
   - openTicketsUrgent > 0 (always critical)
   - pendingVerifications > 10 (warning)
   - revenueWoW_pct < -20 (critical)
   - Any crashesByErrorCode entry with count >= 3 → critical, prefix "🔧 תקלה טכנית:"
5. opportunities: use recentCategoryRequests for demand signals. Mention
   benchmark gaps ("אתה ב-X% מ-Fiverr — כדי להגיע ל-1% צריך...") where X
   comes from input.benchmarks.
6. categoryHealth: look at topCategoriesByGMV and deadCategories.
7. topPerformers: ONLY use data from metrics.topProviders — do not invent.
8. Be specific with numbers. "ההכנסה ירדה" is bad — "ההכנסה ירדה ב-23%
   (₪4,200 השבוע לעומת ₪5,450 השבוע שעבר)" is good.
9. morningBrief MUST mention:
   - launchReadiness.total and verdictLabel ("ציון מוכנות להשקה: X/100 — ...")
   - The single most urgent smartAlert (if any)
   - The strongest prediction (growing or declining)
10. If data is missing or zero, say so honestly — do NOT fabricate.`;

// ── Chat system prompt — for follow-up Q&A with tool use ─────────────────────
const _CEO_CHAT_SYSTEM_PROMPT = `\
You are אילון (Ilon) — the AI CEO of AnySkill — having an interactive
conversation with the founder (Avihai). He just opened the strategic briefing
you generated and is now asking follow-up questions.

If he addresses you as אילון, respond naturally as yourself.

You have access to 9 READ-ONLY tools to investigate further:

CORE TOOLS
1. query_collection_stats(collection, whereField?, whereOp?, whereValue?)
   — Count + sample 5 recent docs from a whitelisted collection.
   — Whitelist: users, jobs, reviews, support_tickets, platform_earnings,
     community_requests, volunteer_tasks, anytasks, categories,
     category_requests, admin_audit_log, job_broadcasts, notifications,
     transactions, crash_reports_summary.

2. query_users_by_criteria(isProvider?, isVerified?, isPendingExpert?, serviceType?, minOrderCount?)
   — List up to 10 users matching criteria.

3. get_provider_report(uid)
   — Deep report on ONE provider: rating, orders, disputes, balance, reviews.

4. get_category_deep_dive(categoryName)
   — Full stats for a category: provider count, active jobs, GMV, avg rating.

DRILLDOWN TOOLS (v12.3)
5. query_blockers_list()
   — The 13 launch blockers with importance × impact scoring.
   — Use when asked "what's blocking launch" or "which blockers to fix first".

6. query_error_distribution(days?)
   — Aggregate crashes by error code + platform. Answer "which error causes
     the most crashes".

7. query_audit_trail(days?, adminUid?)
   — Admin activity log for last N days. Answer "what did admin X do this week".

8. query_category_timeline(category, days?)
   — Timeline of jobs for a specific category. Answer "what happened in
     category X last week".

REVENUE RANKING (v12.4)
9. get_top_providers_by_revenue(days?, limit?)
   — **Prefer this over query_users_by_criteria for revenue questions.**
   — Sums totalAmount across completed jobs per provider, ranks desc.
   — Answers: "top 5 most profitable providers", "best earners this month",
     "who made the most money", "top revenue leaderboard".
   — Defaults: days=7, limit=5. Use larger windows (30, 90) for "month" /
     "quarter" questions.

WHAT-IF SCENARIOS
The founder may ask hypothetical questions like:
  - "What if we raise commission to 20%?"
  - "What if we launch in Tel Aviv only?"
  - "What if we deploy the 13 placeholder features?"
For these questions:
  a) Use tools to gather real current baseline data (current commission,
     current GMV, current provider count, etc).
  b) Apply reasonable industry assumptions (e.g. "each 1% commission hike
     historically drops GMV by 2-3% short-term").
  c) Give a range with confidence: "low estimate: X, high estimate: Y,
     confidence: medium because..."
  d) Recommend: "go / don't go / test first with segment Z".
  e) Say clearly that these are ESTIMATES, not predictions from real data.

RULES
- ALL replies are in Hebrew.
- Use tools aggressively. Don't speculate — look up the real data first.
- When a tool returns data, cite specific numbers in your answer.
- Keep answers concise (2-4 paragraphs). If the founder wants more, he asks.
- If a question is out of scope for this platform, politely say so.
- You already have the full briefing payload in the conversation context
  (metrics, predictions, anomalies, actionItems, benchmarks, cohorts,
  churnRisks, launchReadiness, smartAlerts). Reference them when relevant.
- Never invent data. If a tool fails or returns nothing, say so explicitly.
- You can make concrete recommendations but you cannot execute actions —
  the founder has to approve them manually.`;

// ── Strip code fences from LLM output (Claude/Gemini both do this) ───────────
function _stripCodeFences(s) {
  return (s || "")
    .replace(/```(?:json)?\s*/gi, "")
    .replace(/```/g, "")
    .trim();
}

// ── Claude Opus caller (primary brain) ───────────────────────────────────────
async function _callClaudeOpusForCeo(apiKey, payload, enhancedSystemPrompt) {
  const anthropic = new Anthropic({ apiKey });
  const msg = await anthropic.messages.create({
    model: "claude-opus-4-6",
    max_tokens: 4096,
    system: enhancedSystemPrompt || _CEO_SYSTEM_PROMPT_V2,
    messages: [{
      role: "user",
      content: "Here is the full platform intelligence payload. Analyze it and return the strategic briefing JSON.\n\n" +
        JSON.stringify(payload, null, 2),
    }],
  });
  // Track cost fire-and-forget
  _trackApiCost(
    admin.firestore(),
    msg.usage?.input_tokens || 0,
    msg.usage?.output_tokens || 0,
  ).catch(() => {});
  const raw = _stripCodeFences(msg.content[0]?.text ?? "{}");
  return { raw, inputTokens: msg.usage?.input_tokens || 0, outputTokens: msg.usage?.output_tokens || 0 };
}

// ── Gemini fallback caller (cheap backup if Claude fails) ────────────────────
async function _callGeminiFallbackForCeo(geminiKey, payload, enhancedSystemPrompt) {
  const GEMINI_MODELS = [
    "gemini-3.1-flash-lite-preview",
    "gemini-2.5-flash-lite",
  ];
  const systemPrompt = enhancedSystemPrompt || _CEO_SYSTEM_PROMPT_V2;
  const body = {
    contents: [{
      parts: [{
        text: systemPrompt + "\n\n--- PLATFORM INTELLIGENCE PAYLOAD ---\n\n" +
          JSON.stringify(payload, null, 2),
      }],
    }],
    generationConfig: { temperature: 0.7, maxOutputTokens: 4096 },
  };
  for (const model of GEMINI_MODELS) {
    try {
      const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${geminiKey}`;
      const resp = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      if (!resp.ok) {
        const errText = await resp.text();
        console.error(`CEO Gemini fallback ${model} ${resp.status}:`, errText.substring(0, 200));
        if (resp.status === 404) continue;
        throw new Error(`${model} HTTP ${resp.status}`);
      }
      const json = await resp.json();
      const raw = _stripCodeFences(json.candidates?.[0]?.content?.parts?.[0]?.text ?? "{}");
      const inputTokens  = json.usageMetadata?.promptTokenCount     || 0;
      const outputTokens = json.usageMetadata?.candidatesTokenCount || 0;
      return { raw, model, inputTokens, outputTokens };
    } catch (e) {
      console.error(`CEO Gemini ${model} threw:`, e.message);
    }
  }
  throw new Error("All Gemini fallback models failed");
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXPORT 1: generateCeoInsight — strategic briefing (one-shot)
// ═══════════════════════════════════════════════════════════════════════════════
exports.generateCeoInsight = onCall(
    {
      secrets:      [ANTHROPIC_API_KEY, GEMINI_API_KEY],
      maxInstances: 3,
      region:       "us-central1",
      memory:       "512MiB",
      timeoutSeconds: 180,
    },
    async (request) => {
      // ── Auth: admin only ──────────────────────────────────────────────
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Login required.");
      }
      if (!(await isAdminCaller(request))) {
        throw new HttpsError("permission-denied", "Admin access required.");
      }

      const db = admin.firestore();

      // ── PHASE 1: Collect 40+ deep metrics ─────────────────────────────
      const t0 = Date.now();
      const metrics = await _collectCeoDeepMetrics(db);
      console.log(`generateCeoInsight: metrics collected in ${Date.now() - t0}ms`);

      // ── PHASE 2: Persist today's snapshot + load history ─────────────
      await _persistDailySnapshot(db, metrics);
      const history = await _loadHistoricalMetrics(db, 28);
      console.log(`generateCeoInsight: ${history.length} historical snapshots loaded`);

      // ── PHASE 3: Compute GENIUS insights ──────────────────────────────
      const predictions     = _computePredictions(metrics, history);
      const anomalies       = _computeAnomalies(metrics, history);
      const churnRisks      = await _computeChurnRisks(db);
      const launchReadiness = _computeLaunchReadiness();
      const actionItems     = _computeActionItems(metrics, predictions, anomalies, churnRisks);
      const benchmarks      = _computeBenchmarks(metrics);
      const cohorts         = await _computeCohorts(db, 6);
      const smartAlerts     = _generateSmartAlerts(metrics, predictions, anomalies, churnRisks, launchReadiness);

      console.log(`generateCeoInsight: genius computed — ${predictions.length} predictions, ${anomalies.length} anomalies, ${actionItems.length} actions, ${churnRisks.length} churn risks, ${smartAlerts.length} alerts, launch=${launchReadiness.total}`);

      // ── PHASE 4: Build the intelligence payload for the AI ────────────
      const aiPayload = {
        metrics,
        predictions,
        anomalies,
        actionItems,
        benchmarks,
        cohorts,
        churnRisks,
        launchReadiness,
        smartAlerts,
        historyDays: history.length,
      };

      // ── PHASE 5: Call Claude Opus (primary) with Gemini fallback ─────
      const anthropicKey = ANTHROPIC_API_KEY.value() || process.env.ANTHROPIC_API_KEY || "";
      const geminiKey    = GEMINI_API_KEY.value() || process.env.GEMINI_API_KEY || "";

      // v12.5: load memory + build enhanced system prompt (Ilon remembers)
      const memory = await _loadIlonMemory(db);
      const enhancedSystemPrompt = _CEO_SYSTEM_PROMPT_V2 + _memoryToPromptDigest(memory);

      let raw = "";
      let usedModel = "";
      let briefingInputTokens  = 0;
      let briefingOutputTokens = 0;
      try {
        if (!anthropicKey) throw new Error("ANTHROPIC_API_KEY missing");
        const out = await _callClaudeOpusForCeo(anthropicKey, aiPayload, enhancedSystemPrompt);
        raw = out.raw;
        usedModel = "claude-opus-4-6";
        briefingInputTokens  = out.inputTokens  || 0;
        briefingOutputTokens = out.outputTokens || 0;
        console.log(`generateCeoInsight: Claude Opus succeeded (in=${briefingInputTokens}, out=${briefingOutputTokens})`);
      } catch (claudeErr) {
        console.warn("generateCeoInsight: Claude failed, falling back to Gemini:", claudeErr.message);
        if (!geminiKey) {
          throw new HttpsError("internal",
            "Both Claude and Gemini keys missing. Claude error: " + claudeErr.message);
        }
        try {
          const out = await _callGeminiFallbackForCeo(geminiKey, aiPayload, enhancedSystemPrompt);
          raw = out.raw;
          usedModel = out.model;
          briefingInputTokens  = out.inputTokens  || 0;
          briefingOutputTokens = out.outputTokens || 0;
        } catch (geminiErr) {
          throw new HttpsError("internal",
            `Claude failed (${claudeErr.message}) AND Gemini failed (${geminiErr.message})`);
        }
      }

      const briefingCostUsd = _calcCeoCost(usedModel, briefingInputTokens, briefingOutputTokens);

      // ── PHASE 6: Parse AI narrative ───────────────────────────────────
      let parsed;
      try {
        parsed = JSON.parse(raw);
      } catch (parseErr) {
        console.error("generateCeoInsight: JSON parse failed:", raw.substring(0, 400));
        throw new HttpsError("internal",
          "AI returned invalid JSON. Snippet: " + raw.substring(0, 150));
      }

      console.log(`generateCeoInsight: ✓ generated via ${usedModel}`);

      // ── PHASE 7: Shape the response ───────────────────────────────────
      // Keep backwards compat: legacy fields stay as strings/arrays.
      const legacyRecommendations = Array.isArray(parsed.recommendations)
        ? parsed.recommendations.map(r =>
            typeof r === "string" ? r : `${r.title || ""} — ${r.body || ""}`.trim())
        : [];
      const legacyRedFlags = Array.isArray(parsed.redFlags)
        ? parsed.redFlags.map(f =>
            typeof f === "string" ? f : `${f.title || ""}: ${f.body || ""}`.trim())
        : [];

      return {
        // Legacy (v1 clients)
        morningBrief:    parsed.morningBrief || "",
        recommendations: legacyRecommendations,
        redFlags:        legacyRedFlags,
        // Rich v2 payload (AI narrative)
        headline:        parsed.headline || "",
        keyMetrics:      Array.isArray(parsed.keyMetrics) ? parsed.keyMetrics : [],
        richRecommendations: Array.isArray(parsed.recommendations) ? parsed.recommendations : [],
        richRedFlags:    Array.isArray(parsed.redFlags) ? parsed.redFlags : [],
        opportunities:   Array.isArray(parsed.opportunities) ? parsed.opportunities : [],
        categoryHealth:  Array.isArray(parsed.categoryHealth) ? parsed.categoryHealth : [],
        topPerformers:   Array.isArray(parsed.topPerformers) ? parsed.topPerformers : [],
        // v12.3 GENIUS payload (server-computed — authoritative)
        predictions,
        anomalies,
        actionItems,
        benchmarks,
        cohorts,
        churnRisks,
        launchReadiness,
        smartAlerts,
        historyDays: history.length,
        // Meta
        usedModel,
        metricsSnapshot: metrics,
        // v12.5 cost + memory
        costUsd:      briefingCostUsd,
        inputTokens:  briefingInputTokens,
        outputTokens: briefingOutputTokens,
        memoryStats: {
          sessionCount: memory.sessionCount,
          learnedFacts: memory.learnedFacts.length,
        },
      };
    }
);

// ═══════════════════════════════════════════════════════════════════════════════
// TOOL IMPLEMENTATIONS — read-only Firestore investigators for askCeoAgent
// ═══════════════════════════════════════════════════════════════════════════════

// Whitelist — agent can only touch these collections
const _ALLOWED_TOOL_COLLECTIONS = new Set([
  "users", "jobs", "reviews", "support_tickets", "platform_earnings",
  "community_requests", "volunteer_tasks", "anytasks", "categories",
  "category_requests", "admin_audit_log", "job_broadcasts", "notifications",
  "transactions", "crash_reports_summary",
]);

async function _tool_queryCollectionStats(db, input) {
  const { collection, whereField, whereOp, whereValue } = input;
  if (!_ALLOWED_TOOL_COLLECTIONS.has(collection)) {
    return { error: `Collection "${collection}" is not in the whitelist.` };
  }
  let q = db.collection(collection);
  if (whereField && whereOp && whereValue !== undefined) {
    try { q = q.where(whereField, whereOp, whereValue); }
    catch (e) { return { error: "Invalid where clause: " + e.message }; }
  }
  try {
    const snap = await q.limit(500).get();
    const sampleSnap = await q.limit(5).get();
    return {
      collection,
      count: snap.size,
      samples: sampleSnap.docs.map(d => {
        const data = d.data();
        // Redact sensitive fields
        delete data.phone;
        delete data.email;
        delete data.bankDetails;
        delete data.taxId;
        return { id: d.id, ...data };
      }),
    };
  } catch (e) {
    return { error: e.message };
  }
}

async function _tool_queryUsersByCriteria(db, input) {
  let q = db.collection("users");
  if (typeof input.isProvider === "boolean") q = q.where("isProvider", "==", input.isProvider);
  if (typeof input.isVerified === "boolean") q = q.where("isVerified", "==", input.isVerified);
  if (typeof input.isPendingExpert === "boolean") q = q.where("isPendingExpert", "==", input.isPendingExpert);
  if (input.serviceType) q = q.where("serviceType", "==", input.serviceType);
  try {
    const snap = await q.limit(20).get();
    let users = snap.docs.map(d => {
      const u = d.data();
      return {
        uid: d.id,
        name: u.name || "",
        serviceType: u.serviceType || "",
        isProvider: u.isProvider || false,
        isVerified: u.isVerified || false,
        rating: u.rating || 0,
        orderCount: u.orderCount || 0,
        xp: u.xp || 0,
        createdAt: u.createdAt?.toDate?.()?.toISOString() || "",
      };
    });
    if (typeof input.minOrderCount === "number") {
      users = users.filter(u => u.orderCount >= input.minOrderCount);
    }
    return { count: users.length, users: users.slice(0, 10) };
  } catch (e) {
    return { error: e.message };
  }
}

async function _tool_getProviderReport(db, input) {
  const uid = input.uid;
  if (!uid || typeof uid !== "string") return { error: "uid required" };
  try {
    const userSnap = await db.collection("users").doc(uid).get();
    if (!userSnap.exists) return { error: "User not found" };
    const u = userSnap.data();

    const [jobsSnap, reviewsSnap, disputesSnap] = await Promise.all([
      db.collection("jobs").where("expertId", "==", uid).limit(20).get(),
      db.collection("reviews").where("revieweeId", "==", uid).where("isClientReview", "==", true).limit(10).get(),
      db.collection("jobs").where("expertId", "==", uid).where("status", "==", "disputed").limit(10).get(),
    ]);

    const recentReviews = reviewsSnap.docs.slice(0, 5).map(d => {
      const r = d.data();
      return {
        rating: r.overallRating || 0,
        comment: (r.publicComment || "").substring(0, 120),
      };
    });

    return {
      uid,
      name: u.name || "",
      serviceType: u.serviceType || "",
      isVerified: u.isVerified || false,
      isPro: u.isAnySkillPro || false,
      rating: u.rating || 0,
      reviewsCount: u.reviewsCount || 0,
      orderCount: u.orderCount || 0,
      balance: u.balance || 0,
      pendingBalance: u.pendingBalance || 0,
      xp: u.xp || 0,
      recentJobsCount: jobsSnap.size,
      disputesCount: disputesSnap.size,
      recentReviews,
      joinedAt: u.createdAt?.toDate?.()?.toISOString() || "",
    };
  } catch (e) {
    return { error: e.message };
  }
}

async function _tool_getCategoryDeepDive(db, input) {
  const name = input.categoryName;
  if (!name) return { error: "categoryName required" };
  try {
    const lastWeek = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const [providersSnap, activeJobsSnap, weekJobsSnap] = await Promise.all([
      db.collection("users").where("serviceType", "==", name).where("isProvider", "==", true).limit(100).get(),
      db.collection("jobs").where("serviceType", "==", name).where("status", "in", ["paid_escrow", "expert_completed"]).limit(100).get(),
      db.collection("jobs").where("serviceType", "==", name).where("status", "==", "completed").where("completedAt", ">", lastWeek).limit(100).get(),
    ]);

    let gmvWeek = 0;
    weekJobsSnap.docs.forEach(d => { gmvWeek += (d.data().totalAmount || 0); });

    let ratingSum = 0, ratingCount = 0;
    providersSnap.docs.forEach(d => {
      const r = d.data().rating;
      if (typeof r === "number" && r > 0) { ratingSum += r; ratingCount++; }
    });

    return {
      category: name,
      totalProviders: providersSnap.size,
      activeJobs: activeJobsSnap.size,
      completedThisWeek: weekJobsSnap.size,
      gmvThisWeek: Math.round(gmvWeek),
      avgRating: ratingCount > 0 ? (ratingSum / ratingCount).toFixed(2) : "—",
    };
  } catch (e) {
    return { error: e.message };
  }
}

// ── FEATURE 7: Drilldown tools (v12.3 genius upgrade) ────────────────────────

// Returns the list of unresolved launch blockers (the same static list used
// by _computeLaunchReadiness). Lets the agent answer "which blockers should
// I fix next?" with concrete data.
async function _tool_queryBlockersList(_db, _input) {
  const unresolved = _LAUNCH_BLOCKERS
    .filter(b => !b.resolved)
    .map(b => ({ ...b, weight: b.importance * b.impact }))
    .sort((a, b) => b.weight - a.weight);
  const byCategory = {};
  for (const b of unresolved) {
    if (!byCategory[b.category]) byCategory[b.category] = [];
    byCategory[b.category].push(b);
  }
  return {
    totalUnresolved: unresolved.length,
    byCategory,
    topByWeight: unresolved.slice(0, 10),
  };
}

// Aggregates crashes_reports_summary by error code + platform + severity for
// the last N days. The agent can answer "which error code causes the most
// crashes?" with real numbers.
async function _tool_queryErrorDistribution(db, input) {
  const days = Math.min(Math.max(Number(input.days) || 7, 1), 30);
  const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
  try {
    const snap = await db.collection("crash_reports_summary")
      .where("timestamp", ">", since)
      .limit(500)
      .get();
    const byCode = {};
    for (const d of snap.docs) {
      const data = d.data();
      const code = data.errorCode || "unknown";
      if (!byCode[code]) {
        byCode[code] = {
          code,
          count: 0,
          severity: data.severity || "non-fatal",
          platforms: new Set(),
          lastMessage: "",
          firstSeen: null,
          lastSeen: null,
        };
      }
      byCode[code].count++;
      byCode[code].platforms.add(data.platform || "unknown");
      byCode[code].lastMessage = (data.message || "").substring(0, 160);
      const ts = data.timestamp?.toDate?.() || null;
      if (ts) {
        if (!byCode[code].firstSeen || ts < byCode[code].firstSeen) byCode[code].firstSeen = ts;
        if (!byCode[code].lastSeen  || ts > byCode[code].lastSeen)  byCode[code].lastSeen  = ts;
      }
    }
    const list = Object.values(byCode)
      .map(e => ({
        ...e,
        platforms: [...e.platforms],
        firstSeen: e.firstSeen?.toISOString() || "",
        lastSeen:  e.lastSeen?.toISOString()  || "",
      }))
      .sort((a, b) => b.count - a.count);
    return {
      days,
      totalCrashes: snap.size,
      uniqueCodes: list.length,
      topCodes: list.slice(0, 10),
    };
  } catch (e) {
    return { error: e.message };
  }
}

// Reads admin_audit_log for the last N days. Filters by adminUid if
// provided, or returns the full activity stream otherwise.
async function _tool_queryAuditTrail(db, input) {
  const days = Math.min(Math.max(Number(input.days) || 7, 1), 30);
  const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
  try {
    let q = db.collection("admin_audit_log")
      .where("createdAt", ">", since)
      .orderBy("createdAt", "desc")
      .limit(100);
    const snap = await q.get();
    const entries = snap.docs.map(d => {
      const data = d.data();
      return {
        id: d.id,
        adminName: data.adminName || "",
        adminUid: data.adminUid || "",
        action: data.action || "",
        targetUserId: data.targetUserId || "",
        targetName: data.targetName || "",
        reason: (data.reason || "").substring(0, 160),
        createdAt: data.createdAt?.toDate?.()?.toISOString() || "",
      };
    });
    const filtered = input.adminUid
      ? entries.filter(e => e.adminUid === input.adminUid)
      : entries;
    const actionCounts = {};
    filtered.forEach(e => { actionCounts[e.action] = (actionCounts[e.action] || 0) + 1; });
    return {
      days,
      totalEntries: filtered.length,
      actionCounts,
      recentEntries: filtered.slice(0, 20),
    };
  } catch (e) {
    return { error: e.message };
  }
}

// Reads activity_log (or jobs) for a specific category over the last N days
// to give a timeline of what happened in that vertical.
async function _tool_queryCategoryTimeline(db, input) {
  const category = input.category;
  if (!category) return { error: "category required" };
  const days = Math.min(Math.max(Number(input.days) || 7, 1), 30);
  const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
  try {
    const jobsSnap = await db.collection("jobs")
      .where("serviceType", "==", category)
      .where("createdAt", ">", since)
      .orderBy("createdAt", "desc")
      .limit(50)
      .get();
    const statusCounts = {};
    let gmv = 0;
    const events = [];
    for (const d of jobsSnap.docs) {
      const j = d.data();
      const status = j.status || "unknown";
      statusCounts[status] = (statusCounts[status] || 0) + 1;
      if (status === "completed") gmv += (j.totalAmount || 0);
      events.push({
        jobId: d.id,
        status,
        amount: j.totalAmount || 0,
        customerName: j.customerName || "",
        expertName: j.expertName || "",
        createdAt: j.createdAt?.toDate?.()?.toISOString() || "",
      });
    }
    return {
      category,
      days,
      totalJobs: jobsSnap.size,
      gmv: Math.round(gmv),
      statusCounts,
      recentEvents: events.slice(0, 15),
    };
  } catch (e) {
    return { error: e.message };
  }
}

// ── FEATURE: Top providers by revenue (v12.4 — fixes INTERNAL error on this
// specific question). Uses the existing composite index:
//   jobs: status ASC + completedAt DESC
// so no new index deploy is required.
//
// Aggregates completed jobs by expertId, sums totalAmount, sorts desc,
// resolves user details. Handles null totals + missing expertIds gracefully.
async function _tool_getTopProvidersByRevenue(db, input) {
  const days  = Math.min(Math.max(Number(input.days)  || 7,  1), 90);
  const limit = Math.min(Math.max(Number(input.limit) || 5,  1), 20);
  const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
  try {
    // Fetch completed jobs in window — uses existing status+completedAt index
    const jobsSnap = await db.collection("jobs")
      .where("status", "==", "completed")
      .where("completedAt", ">", since)
      .orderBy("completedAt", "desc")
      .limit(500)  // cap to bound memory
      .get();

    console.log(`[tool:top_providers] fetched ${jobsSnap.size} completed jobs in last ${days}d`);

    // Aggregate by expertId — null-safe
    const revenueByProvider = new Map();
    const jobCountByProvider = new Map();
    let skippedNoExpert = 0;
    let skippedNoAmount = 0;

    for (const doc of jobsSnap.docs) {
      const j = doc.data() || {};
      const expertId = j.expertId;
      if (!expertId || typeof expertId !== "string") { skippedNoExpert++; continue; }
      // totalAmount may be number, string, or missing — coerce safely
      const amt = Number(j.totalAmount);
      if (!Number.isFinite(amt) || amt <= 0) { skippedNoAmount++; continue; }
      revenueByProvider.set(expertId, (revenueByProvider.get(expertId) || 0) + amt);
      jobCountByProvider.set(expertId, (jobCountByProvider.get(expertId) || 0) + 1);
    }

    console.log(`[tool:top_providers] ${revenueByProvider.size} unique providers, skipped ${skippedNoExpert} no-expert, ${skippedNoAmount} no-amount`);

    // Sort desc, take top N
    const topIds = [...revenueByProvider.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, limit)
      .map(([uid]) => uid);

    // Resolve user profiles in parallel (no index needed — single doc reads)
    const profiles = await Promise.all(topIds.map(async uid => {
      try {
        const snap = await db.collection("users").doc(uid).get();
        return { uid, data: snap.exists ? snap.data() : null };
      } catch (e) {
        console.warn(`[tool:top_providers] user ${uid} fetch failed:`, e.message);
        return { uid, data: null };
      }
    }));

    const leaderboard = profiles.map(({ uid, data }) => {
      const u = data || {};
      return {
        rank: topIds.indexOf(uid) + 1,
        uid,
        name: u.name || "Unknown",
        serviceType: u.serviceType || "—",
        revenue: Math.round(revenueByProvider.get(uid) || 0),
        jobsCompleted: jobCountByProvider.get(uid) || 0,
        rating: u.rating || 0,
        totalOrderCount: u.orderCount || 0,
        isVerified: u.isVerified === true,
        isAnySkillPro: u.isAnySkillPro === true,
        profileMissing: data === null,
      };
    });

    return {
      windowDays: days,
      totalJobsAnalyzed: jobsSnap.size,
      uniqueProviders: revenueByProvider.size,
      leaderboard,
    };
  } catch (e) {
    // Distinguish index-missing errors for actionable admin feedback
    const msg = e.message || String(e);
    if (msg.includes("FAILED_PRECONDITION") || msg.includes("index")) {
      console.error("[tool:top_providers] MISSING INDEX:", msg);
      return {
        error: "חסר Firestore composite index. צריך index על jobs: status + completedAt DESC. " +
               "שורת המקור: " + msg.substring(0, 200),
        needsIndex: true,
      };
    }
    console.error("[tool:top_providers] failed:", msg);
    return { error: msg };
  }
}

// Dispatch a single tool call — wrapped so a tool throw never kills the agent
// loop (it gets turned into a tool_result with error field instead).
async function _dispatchCeoTool(db, name, input) {
  try {
    switch (name) {
      case "query_collection_stats":    return await _tool_queryCollectionStats(db, input);
      case "query_users_by_criteria":   return await _tool_queryUsersByCriteria(db, input);
      case "get_provider_report":       return await _tool_getProviderReport(db, input);
      case "get_category_deep_dive":    return await _tool_getCategoryDeepDive(db, input);
      // v12.3 drilldown tools
      case "query_blockers_list":       return await _tool_queryBlockersList(db, input);
      case "query_error_distribution":  return await _tool_queryErrorDistribution(db, input);
      case "query_audit_trail":         return await _tool_queryAuditTrail(db, input);
      case "query_category_timeline":   return await _tool_queryCategoryTimeline(db, input);
      // v12.4 revenue tool
      case "get_top_providers_by_revenue": return await _tool_getTopProvidersByRevenue(db, input);
      default:                          return { error: `Unknown tool: ${name}` };
    }
  } catch (e) {
    // Defensive: any tool that throws gets converted to a tool_result with
    // error so the agent loop can continue and explain what happened.
    console.error(`[dispatch:${name}] uncaught throw:`, e.message || e);
    return { error: `Tool ${name} threw: ${(e.message || String(e)).substring(0, 200)}` };
  }
}

// Claude tool definitions
const _CEO_TOOL_DEFS = [
  {
    name: "query_collection_stats",
    description: "Count documents and sample the 5 most recent from a whitelisted Firestore collection. Returns a total count plus a small sample. Optional single where-clause filter.",
    input_schema: {
      type: "object",
      properties: {
        collection: { type: "string", description: "Collection name (e.g. 'users', 'jobs', 'reviews')" },
        whereField: { type: "string", description: "Optional field name to filter on" },
        whereOp:    { type: "string", description: "Firestore operator: ==, !=, >, <, >=, <=, in" },
        whereValue: { description: "Value to compare against (string, number, bool, or array for 'in')" },
      },
      required: ["collection"],
    },
  },
  {
    name: "query_users_by_criteria",
    description: "List up to 10 users matching combined criteria (provider/verified/pending/serviceType/minOrderCount). Useful for finding top providers, pending verifications, new users, etc.",
    input_schema: {
      type: "object",
      properties: {
        isProvider:      { type: "boolean" },
        isVerified:      { type: "boolean" },
        isPendingExpert: { type: "boolean" },
        serviceType:     { type: "string" },
        minOrderCount:   { type: "number" },
      },
    },
  },
  {
    name: "get_provider_report",
    description: "Deep report on one provider by uid: rating, order count, disputes, balance, recent reviews.",
    input_schema: {
      type: "object",
      properties: { uid: { type: "string" } },
      required: ["uid"],
    },
  },
  {
    name: "get_category_deep_dive",
    description: "Full stats for a specific service category: provider count, active jobs, weekly GMV, avg rating.",
    input_schema: {
      type: "object",
      properties: { categoryName: { type: "string" } },
      required: ["categoryName"],
    },
  },
  // v12.3 drilldown tools
  {
    name: "query_blockers_list",
    description: "Return the full list of unresolved launch blockers (the scoring input for launchReadiness). Use this when asked 'what's blocking launch?' or 'which blockers should I fix next?'.",
    input_schema: { type: "object", properties: {} },
  },
  {
    name: "query_error_distribution",
    description: "Aggregate crash_reports_summary by error code, platform, and severity. Answers 'which error code causes the most crashes?'. days defaults to 7.",
    input_schema: {
      type: "object",
      properties: {
        days: { type: "number", description: "How many days back to look (1-30)" },
      },
    },
  },
  {
    name: "query_audit_trail",
    description: "Read admin_audit_log entries from the last N days. Optional adminUid filter. Answers 'what did admin X do last week?'.",
    input_schema: {
      type: "object",
      properties: {
        days: { type: "number", description: "How many days back (1-30). Default 7." },
        adminUid: { type: "string", description: "Optional — filter to one admin's actions" },
      },
    },
  },
  {
    name: "query_category_timeline",
    description: "Return a timeline of jobs (created + status + GMV) for a specific service category over the last N days. Answers 'what happened in category X last week?'.",
    input_schema: {
      type: "object",
      properties: {
        category: { type: "string", description: "Exact category name" },
        days: { type: "number", description: "How many days back (1-30). Default 7." },
      },
      required: ["category"],
    },
  },
  // v12.4: dedicated top-providers-by-revenue tool (fixes INTERNAL error
  // that happened when the agent tried to synthesize this from scratch).
  {
    name: "get_top_providers_by_revenue",
    description: "Return the top N providers ranked by actual revenue (sum of totalAmount across completed jobs) in the last N days. Use this whenever asked 'who are the top/most profitable providers', 'best earners', 'leaderboard'. Prefer this tool over query_users_by_criteria for revenue-ranking questions.",
    input_schema: {
      type: "object",
      properties: {
        days:  { type: "number", description: "Lookback window in days (1-90). Default 7." },
        limit: { type: "number", description: "How many top providers to return (1-20). Default 5." },
      },
    },
  },
];

// ═══════════════════════════════════════════════════════════════════════════════
// EXPORT 2: askCeoAgent — interactive chat with tool use
// ═══════════════════════════════════════════════════════════════════════════════
//
// Input: {
//   question: string,
//   conversationHistory?: [{role: "user"|"assistant", content: string}, ...],
//   metricsSnapshot?: object   // optional — the snapshot from generateCeoInsight
// }
// Output: {
//   answer: string,
//   toolsUsed: [{name, input, result}],
//   turnCount: number
// }
exports.askCeoAgent = onCall(
    {
      // v12.5.1: GEMINI_API_KEY added so the chat fallback actually works
      // when Anthropic credits are exhausted / rate-limited. Without this
      // in the secrets array, GEMINI_API_KEY.value() returns "" even when
      // the secret is set in the project, and we threw "no Gemini fallback".
      secrets:      [ANTHROPIC_API_KEY, GEMINI_API_KEY],
      maxInstances: 5,
      region:       "us-central1",
      memory:       "512MiB",
      timeoutSeconds: 180,
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Login required.");
      }
      if (!(await isAdminCaller(request))) {
        throw new HttpsError("permission-denied", "Admin access required.");
      }

      const question = (request.data?.question || "").trim();
      if (!question) throw new HttpsError("invalid-argument", "question is required");
      if (question.length > 2000) {
        throw new HttpsError("invalid-argument", "question too long (max 2000 chars)");
      }

      const history = Array.isArray(request.data?.conversationHistory)
        ? request.data.conversationHistory
        : [];
      const snapshot = request.data?.metricsSnapshot || null;

      const apiKey    = ANTHROPIC_API_KEY.value() || process.env.ANTHROPIC_API_KEY || "";
      const geminiKey = GEMINI_API_KEY.value()    || process.env.GEMINI_API_KEY    || "";
      if (!apiKey && !geminiKey) {
        throw new HttpsError("internal", "Neither ANTHROPIC_API_KEY nor GEMINI_API_KEY is configured.");
      }

      const db = admin.firestore();

      // ── v12.5: Load accumulated memory (Ilon gets smarter each session) ──
      const memory = await _loadIlonMemory(db);
      const memoryDigest = _memoryToPromptDigest(memory);
      const enhancedSystemPrompt = _CEO_CHAT_SYSTEM_PROMPT + memoryDigest;
      console.log(`[askCeoAgent] memory loaded: ${memory.learnedFacts.length} facts, ${memory.sessionCount} past sessions`);

      const anthropic = apiKey ? new Anthropic({ apiKey }) : null;

      // Build the messages array. First turn: prefix with a system-style
      // "context dump" of the metrics snapshot (if provided).
      const messages = [];
      if (snapshot && history.length === 0) {
        messages.push({
          role: "user",
          content: "Current platform metrics snapshot (reference only — don't re-analyze unless asked):\n\n" +
            JSON.stringify(snapshot, null, 2) +
            "\n\nMy question: " + question,
        });
      } else {
        // Include prior history then the new question
        for (const m of history) {
          if (m.role === "user" || m.role === "assistant") {
            messages.push({
              role: m.role,
              content: typeof m.content === "string" ? m.content : JSON.stringify(m.content),
            });
          }
        }
        messages.push({ role: "user", content: question });
      }

      // Agent loop — up to 5 tool-use iterations
      const MAX_ITERATIONS = 5;
      const toolsUsed = [];
      let finalText = "";
      let totalInputTokens = 0;
      let totalOutputTokens = 0;
      const t0 = Date.now();

      console.log(`[askCeoAgent] START q="${question.substring(0, 80)}" hasSnapshot=${!!snapshot} history=${history.length}`);

      // Track which model answered the final turn (for cost calc + UI badge)
      let usedModel = "";
      let totalCostUsd = 0;

      for (let iter = 0; iter < MAX_ITERATIONS; iter++) {
        // ── Anthropic call — wrapped + Gemini fallback on ANY failure ──
        let msg;
        let anthropicFailure = null;

        if (anthropic) {
          try {
            msg = await anthropic.messages.create({
              model:      "claude-sonnet-4-6",  // Sonnet for chat — cheaper than Opus
              max_tokens: 2048,
              system:     enhancedSystemPrompt,
              tools:      _CEO_TOOL_DEFS,
              messages,
            });
          } catch (apiErr) {
            const status = apiErr.status || apiErr.statusCode || 0;
            const kind   = apiErr?.error?.type || apiErr?.type || "unknown";
            const reason = (apiErr.message || String(apiErr)).substring(0, 300);
            console.warn(`[askCeoAgent] Anthropic FAIL iter=${iter} status=${status} type=${kind}:`, reason);
            anthropicFailure = { status, kind, reason };
          }
        }

        // ── Gemini fallback: triggered on ANY Anthropic failure (incl. 400
        //    "credit balance too low"). No tool use — answers from context.
        if (!msg) {
          if (!geminiKey) {
            // No fallback available — surface a clean HttpsError
            const reason = anthropicFailure?.reason || "Anthropic unavailable and no GEMINI_API_KEY";
            const status = anthropicFailure?.status || 0;
            if (status === 429) {
              throw new HttpsError("resource-exhausted", `Rate limit. נסה שוב בעוד דקה.`);
            }
            throw new HttpsError("unavailable",
              `אילון זמנית לא זמין — Anthropic נכשל ואין Gemini fallback מוגדר. ${reason}`);
          }
          console.log(`[askCeoAgent] falling back to Gemini for iter=${iter}`);
          try {
            const gem = await _callGeminiChatFallback(geminiKey, enhancedSystemPrompt, messages);
            finalText = gem.text;
            usedModel = gem.model;
            totalInputTokens  += gem.inputTokens;
            totalOutputTokens += gem.outputTokens;
            totalCostUsd      += _calcCeoCost(gem.model, gem.inputTokens, gem.outputTokens);
            console.log(`[askCeoAgent] Gemini answered via ${gem.model} (in=${gem.inputTokens}, out=${gem.outputTokens}, $${totalCostUsd.toFixed(6)})`);
            break; // Gemini doesn't do tool-use loops
          } catch (geminiErr) {
            throw new HttpsError("unavailable",
              `גם Anthropic וגם Gemini נכשלו. Anthropic: ${anthropicFailure?.reason || "n/a"}. Gemini: ${geminiErr.message}`);
          }
        }

        // Anthropic succeeded — track tokens + cost
        totalInputTokens  += msg.usage?.input_tokens  || 0;
        totalOutputTokens += msg.usage?.output_tokens || 0;
        totalCostUsd      += _calcCeoCost("claude-sonnet-4-6",
                                          msg.usage?.input_tokens || 0,
                                          msg.usage?.output_tokens || 0);
        usedModel = "claude-sonnet-4-6";
        console.log(`[askCeoAgent] iter=${iter} stop=${msg.stop_reason} in=${msg.usage?.input_tokens || 0} out=${msg.usage?.output_tokens || 0} $${totalCostUsd.toFixed(6)}`);

        // ── Final text response ───────────────────────────────────────
        if (msg.stop_reason === "end_turn" || msg.stop_reason === "stop_sequence") {
          const textBlocks = (msg.content || []).filter(b => b.type === "text");
          finalText = textBlocks.map(b => b.text).join("\n").trim();
          break;
        }

        // ── Tool use — execute + feed results back ────────────────────
        if (msg.stop_reason === "tool_use") {
          messages.push({ role: "assistant", content: msg.content });

          const toolUseBlocks = (msg.content || []).filter(b => b.type === "tool_use");
          const toolResults = [];
          for (const block of toolUseBlocks) {
            const tName = block.name || "(unnamed)";
            const inputKeys = Object.keys(block.input || {}).join(",");
            console.log(`[askCeoAgent] iter=${iter} tool=${tName} inputKeys=[${inputKeys}]`);
            const tStart = Date.now();
            // _dispatchCeoTool is already wrapped in try/catch at dispatcher
            // level, so even a tool throw becomes a tool_result with error.
            const result = await _dispatchCeoTool(db, tName, block.input || {});
            const tMs = Date.now() - tStart;
            const hasError = result && result.error;
            console.log(`[askCeoAgent] iter=${iter} tool=${tName} done in ${tMs}ms ${hasError ? `ERROR: ${result.error.substring(0, 100)}` : "OK"}`);
            toolsUsed.push({ name: tName, input: block.input, result });
            toolResults.push({
              type: "tool_result",
              tool_use_id: block.id,
              content: JSON.stringify(result),
              is_error: hasError === true || hasError === "true",
            });
          }
          messages.push({ role: "user", content: toolResults });
          continue;
        }

        // ── max_tokens / refusal / other — return whatever text we got
        console.warn(`[askCeoAgent] iter=${iter} unexpected stop_reason=${msg.stop_reason}`);
        const textBlocks = (msg.content || []).filter(b => b.type === "text");
        finalText = textBlocks.map(b => b.text).join("\n").trim();
        if (msg.stop_reason === "max_tokens" && !finalText) {
          finalText = "התשובה נקטעה כי חרגה מאורך מקסימלי. נסה לשאול שאלה ממוקדת יותר.";
        }
        break;
      }

      // Track aggregated API cost in system_stats/billing
      _trackApiCost(db, totalInputTokens, totalOutputTokens).catch(() => {});

      const totalMs = Date.now() - t0;
      console.log(`[askCeoAgent] END tools=${toolsUsed.length} tokensIn=${totalInputTokens} tokensOut=${totalOutputTokens} $${totalCostUsd.toFixed(6)} ${totalMs}ms answerLen=${finalText.length}`);

      if (!finalText) {
        finalText = "מצטער, לא הצלחתי להפיק תשובה. נסה לנסח את השאלה אחרת.";
      }

      // ── v12.5: bump session counter + extract insights (fire-and-forget) ──
      _bumpIlonSessionCount(db).catch(() => {});
      // Only extract insights if the answer looks substantive
      if (finalText.length >= 80 && !finalText.startsWith("שגיאה")) {
        _extractAndAppendInsight(db, question, finalText, apiKey, geminiKey).catch(err => {
          console.warn("[askCeoAgent] insight extraction failed (non-fatal):", err.message);
        });
      }

      return {
        answer:        finalText,
        toolsUsed,
        turnCount:     toolsUsed.length + 1,
        inputTokens:   totalInputTokens,
        outputTokens:  totalOutputTokens,
        // v12.5 new fields
        costUsd:       totalCostUsd,
        usedModel:     usedModel || "unknown",
        memoryStats: {
          sessionCount:  memory.sessionCount + 1,
          learnedFacts:  memory.learnedFacts.length,
          totalSessions: memory.sessionCount + 1,
        },
      };
    }
);

// ═════════════════════════════════════════════════════════════════════════════
// SCHEDULED FIRESTORE BACKUP — Daily at 02:00 IST
// ═════════════════════════════════════════════════════════════════════════════
// Exports the entire Firestore database to a GCS bucket every night.
// Bucket: gs://anyskill-6fdf3-backups  (must be created once in GCP Console)
// Retention: managed by GCS lifecycle rules (set to 30 days recommended).
//
// Setup (one-time):
//   1. Create the bucket:
//      gsutil mb -l me-west1 gs://anyskill-6fdf3-backups
//   2. Grant Firestore export permission to the default service account:
//      gcloud projects add-iam-policy-binding anyskill-6fdf3 \
//        --member="serviceAccount:anyskill-6fdf3@appspot.gserviceaccount.com" \
//        --role="roles/datastore.importExportAdmin"
//   3. Grant bucket write access:
//      gsutil iam ch serviceAccount:anyskill-6fdf3@appspot.gserviceaccount.com:objectAdmin \
//        gs://anyskill-6fdf3-backups
//   4. Deploy:
//      firebase deploy --only functions:scheduledFirestoreBackup
// ═════════════════════════════════════════════════════════════════════════════
exports.scheduledFirestoreBackup = onSchedule(
  {
    schedule:   "0 2 * * *",       // 02:00 every day
    timeZone:   "Asia/Jerusalem",
    retryCount: 2,
  },
  async () => {
    const projectId = process.env.GCLOUD_PROJECT || "anyskill-6fdf3";
    const bucket    = `gs://anyskill-6fdf3-backups`;
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
    const outputUri = `${bucket}/backups/${timestamp}`;

    console.log(`[Backup] Starting Firestore export → ${outputUri}`);

    try {
      const client = new admin.firestore.v1.FirestoreAdminClient();
      const databaseName = client.databasePath(projectId, "(default)");

      const [response] = await client.exportDocuments({
        name:                 databaseName,
        outputUriPrefix:      outputUri,
        // Empty collectionIds = export ALL collections
        collectionIds:        [],
      });

      console.log(`[Backup] Export started: ${response.name}`);

      // Log success to Firestore for admin visibility
      await admin.firestore().collection("admin_audit_log").add({
        action:    "firestore_backup",
        status:    "started",
        outputUri,
        operationName: response.name,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (error) {
      console.error("[Backup] Export FAILED:", error);

      // Log failure for admin visibility
      await admin.firestore().collection("admin_audit_log").add({
        action:    "firestore_backup",
        status:    "failed",
        error:     (error.message || "unknown").substring(0, 500),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }
);


// ═══════════════════════════════════════════════════════════════════════════
// ANYTASKS 3.0 — Cloud Functions
// ═══════════════════════════════════════════════════════════════════════════

// ── Auto-Release Escrow (Gap #1) ──────────────────────────────────────────
// Runs every 30 minutes. Scans tasks where:
//   status == 'proof_submitted' AND autoReleaseDate <= now AND autoReleased == false
// Releases escrow to provider, marks task as completed.
// Two advance notifications are sent at 24h and 2h before release.
exports.anytaskAutoRelease = onSchedule(
  { schedule: "every 30 minutes", timeZone: "Asia/Jerusalem" },
  async () => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    let released = 0;
    let reminded = 0;

    try {
      // ── Phase 1: Release tasks past the 48h deadline ──────────────────
      const expiredSnap = await db.collection("anytasks")
        .where("status", "==", "proof_submitted")
        .where("autoReleased", "==", false)
        .where("autoReleaseDate", "<=", now)
        .limit(100)
        .get();

      for (const doc of expiredSnap.docs) {
        const data = doc.data();
        const taskId      = doc.id;
        const providerId  = data.providerId || "";
        const creatorId   = data.creatorId || "";
        const commission  = data.commission || 0;
        const netToProvider = data.netToProvider || 0;

        if (!providerId) continue;

        try {
          const batch = db.batch();

          // Mark task as auto-released + completed
          batch.update(doc.ref, {
            status:             "completed",
            autoReleased:       true,
            confirmedByCreator: false,
            completedAt:        admin.firestore.FieldValue.serverTimestamp(),
            updatedAt:          admin.firestore.FieldValue.serverTimestamp(),
          });

          // Credit provider balance
          const providerRef = db.collection("users").doc(providerId);
          batch.update(providerRef, {
            balance:              admin.firestore.FieldValue.increment(netToProvider),
            pendingBalance:       admin.firestore.FieldValue.increment(-netToProvider),
            anytaskCompletedCount: admin.firestore.FieldValue.increment(1),
          });

          // Platform commission
          batch.set(db.collection("platform_earnings").doc(), {
            taskId,
            amount:         commission,
            sourceExpertId: providerId,
            timestamp:      admin.firestore.FieldValue.serverTimestamp(),
            status:         "settled",
            source:         "anytask_auto_release",
          });

          // Transaction record
          batch.set(db.collection("transactions").doc(), {
            senderId:     "escrow",
            senderName:   "AnyTasks Escrow",
            receiverId:   providerId,
            receiverName: data.providerName || "",
            amount:       netToProvider,
            type:         "anytask_auto_release",
            taskId,
            payoutStatus: "completed",
            timestamp:    admin.firestore.FieldValue.serverTimestamp(),
          });

          // Admin system balance
          batch.set(
            db.collection("admin").doc("admin").collection("settings").doc("settings"),
            { totalPlatformBalance: admin.firestore.FieldValue.increment(commission) },
            { merge: true }
          );

          await batch.commit();
          released++;

          // Notify both parties
          await db.collection("notifications").add({
            userId:    providerId,
            title:     "💰 תשלום שוחרר אוטומטית!",
            body:      `₪${netToProvider.toFixed(0)} שוחררו לארנק שלך עבור "${data.title || "משימה"}"`,
            type:      "anytask_auto_released",
            isRead:    false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          await db.collection("notifications").add({
            userId:    creatorId,
            title:     "⏰ התשלום שוחרר אוטומטית",
            body:      `חלפו 48 שעות — התשלום עבור "${data.title || "משימה"}" שוחרר לנותן השירות.`,
            type:      "anytask_auto_released",
            isRead:    false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          // Activity log
          await doc.ref.collection("activity").add({
            actorId:   "system",
            actorRole: "system",
            action:    "auto_released",
            details:   `Auto-released after 48h: ₪${netToProvider.toFixed(0)} to provider`,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (err) {
          console.error(`[anytaskAutoRelease] Error releasing task ${taskId}:`, err.message);
        }
      }

      // ── Phase 2: Send reminder notifications ──────────────────────────
      // 24h reminder: tasks where autoReleaseDate is 22-26h from now
      // 2h reminder:  tasks where autoReleaseDate is 1.5-2.5h from now
      const reminderSnap = await db.collection("anytasks")
        .where("status", "==", "proof_submitted")
        .where("autoReleased", "==", false)
        .limit(200)
        .get();

      for (const doc of reminderSnap.docs) {
        const data = doc.data();
        if (!data.autoReleaseDate) continue;

        const releaseDate = data.autoReleaseDate.toDate();
        const hoursLeft = (releaseDate.getTime() - Date.now()) / (1000 * 60 * 60);
        const creatorId = data.creatorId || "";
        const title = data.title || "משימה";

        // 24h reminder (between 22-26 hours, so it fires once in the 30-min window)
        if (hoursLeft >= 22 && hoursLeft <= 26 && !data._reminder24hSent) {
          await db.collection("notifications").add({
            userId:    creatorId,
            title:     "⏳ נותרו 24 שעות לאישור",
            body:      `יש לך עוד ~24 שעות לאשר או לפתוח מחלוקת על "${title}"`,
            type:      "anytask_reminder_24h",
            isRead:    false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          await doc.ref.update({ _reminder24hSent: true });
          reminded++;
        }

        // 2h reminder (between 1.5-2.5 hours)
        if (hoursLeft >= 1.5 && hoursLeft <= 2.5 && !data._reminder2hSent) {
          await db.collection("notifications").add({
            userId:    creatorId,
            title:     "🔔 נותרו שעתיים לאישור!",
            body:      `התשלום על "${title}" ישוחרר אוטומטית בעוד כשעתיים`,
            type:      "anytask_reminder_2h",
            isRead:    false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          await doc.ref.update({ _reminder2hSent: true });
          reminded++;
        }
      }

      console.log(`[anytaskAutoRelease] Released: ${released}, Reminded: ${reminded}`);
    } catch (error) {
      console.error("[anytaskAutoRelease] Fatal error:", error.message);
    }
  }
);

// ── Expire Open Tasks (7-day TTL) ─────────────────────────────────────────
// Runs daily at 02:00. Expires open tasks older than 7 days with no claim.
// Refunds the escrowed amount to the creator.
exports.anytaskExpireOpen = onSchedule(
  { schedule: "0 2 * * *", timeZone: "Asia/Jerusalem" },
  async () => {
    const db = admin.firestore();
    const cutoff = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 7 * 24 * 60 * 60 * 1000)
    );
    let expired = 0;

    try {
      const snap = await db.collection("anytasks")
        .where("status", "==", "open")
        .where("createdAt", "<=", cutoff)
        .limit(200)
        .get();

      for (const doc of snap.docs) {
        const data = doc.data();
        const creatorId = data.creatorId || "";
        const amount = data.amount || 0;

        try {
          const batch = db.batch();

          // Mark as expired
          batch.update(doc.ref, {
            status:    "expired",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          // Refund creator (full amount — no fee for expired tasks)
          if (creatorId && amount > 0) {
            batch.update(db.collection("users").doc(creatorId), {
              balance: admin.firestore.FieldValue.increment(amount),
            });

            // Refund transaction record
            batch.set(db.collection("transactions").doc(), {
              senderId:     "escrow",
              senderName:   "AnyTasks Escrow",
              receiverId:   creatorId,
              receiverName: data.creatorName || "",
              amount,
              type:         "anytask_expired_refund",
              taskId:       doc.id,
              payoutStatus: "completed",
              timestamp:    admin.firestore.FieldValue.serverTimestamp(),
            });
          }

          await batch.commit();
          expired++;

          // Notify creator
          if (creatorId) {
            await db.collection("notifications").add({
              userId:    creatorId,
              title:     "⏰ המשימה שלך פגה",
              body:      `"${data.title || "משימה"}" לא נתפסה תוך 7 ימים. ₪${amount.toFixed(0)} הוחזרו לארנק שלך. רוצה לפרסם מחדש?`,
              type:      "anytask_expired",
              isRead:    false,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
        } catch (err) {
          console.error(`[anytaskExpireOpen] Error expiring task ${doc.id}:`, err.message);
        }
      }

      console.log(`[anytaskExpireOpen] Expired ${expired} stale tasks`);
    } catch (error) {
      console.error("[anytaskExpireOpen] Fatal error:", error.message);
    }
  }
);

// ── SLA Monitor (Feature #2 — First Message + Activity SLA) ───────────────
// Runs every 15 minutes. Checks for:
//   1. Tasks claimed > 30 min with no chat message → send reminder
//   2. Tasks claimed > 2 hours with no activity → auto-return to pool
exports.anytaskSlaMonitor = onSchedule(
  { schedule: "every 15 minutes", timeZone: "Asia/Jerusalem" },
  async () => {
    const db = admin.firestore();
    const now = Date.now();
    let reminders = 0;
    let returned = 0;

    try {
      // Query all claimed/in_progress tasks
      const snap = await db.collection("anytasks")
        .where("status", "in", ["claimed", "in_progress"])
        .limit(200)
        .get();

      for (const doc of snap.docs) {
        const data = doc.data();
        const claimedAt = data.claimedAt ? data.claimedAt.toDate().getTime() : now;
        const lastActivity = data.lastActivityAt ? data.lastActivityAt.toDate().getTime() : claimedAt;
        const providerId = data.providerId || "";
        const creatorId = data.creatorId || "";
        const title = data.title || "משימה";
        const elapsed = now - Math.max(claimedAt, lastActivity);
        const elapsedMinutes = elapsed / (1000 * 60);

        // ── 30-min first message reminder ──────────────────────────────
        if (elapsedMinutes >= 30 && elapsedMinutes < 120 && !data._slaReminderSent) {
          await db.collection("notifications").add({
            userId:    providerId,
            title:     "⏰ הגב ללקוח כדי לשמור על המשימה",
            body:      `לא נשלחה הודעה ב-"${title}" — הגב תוך שעה וחצי כדי שהמשימה לא תוחזר.`,
            type:      "anytask_sla_reminder",
            isRead:    false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          await doc.ref.update({ _slaReminderSent: true });
          reminders++;
        }

        // ── 2-hour inactivity → auto-return to pool ───────────────────
        if (elapsedMinutes >= 120) {
          const batch = db.batch();

          // Return task to open pool
          batch.update(doc.ref, {
            status:       "open",
            providerId:   null,
            providerName: null,
            providerImage: null,
            claimedAt:    null,
            chatRoomId:   null,
            _slaReminderSent: admin.firestore.FieldValue.delete(),
            updatedAt:    admin.firestore.FieldValue.serverTimestamp(),
          });

          // Apply minor penalty to provider score
          if (providerId) {
            batch.update(db.collection("users").doc(providerId), {
              anytaskCancellationScore: admin.firestore.FieldValue.increment(-0.05),
            });
          }

          await batch.commit();
          returned++;

          // Notify both parties
          if (providerId) {
            await db.collection("notifications").add({
              userId:    providerId,
              title:     "🔄 המשימה הוחזרה בגלל חוסר פעילות",
              body:      `"${title}" הוחזרה לבריכה הפתוחה לאחר שעתיים ללא תגובה.`,
              type:      "anytask_sla_returned",
              isRead:    false,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
          if (creatorId) {
            await db.collection("notifications").add({
              userId:    creatorId,
              title:     "🔄 המשימה שלך חזרה לבריכה",
              body:      `"${title}" הוחזרה לנותני שירות אחרים בגלל חוסר תגובה.`,
              type:      "anytask_sla_returned",
              isRead:    false,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }

          // Activity log
          await doc.ref.collection("activity").add({
            actorId:   "system",
            actorRole: "system",
            action:    "sla_returned",
            details:   `Auto-returned after ${Math.round(elapsedMinutes)} min inactivity`,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }

      console.log(`[anytaskSlaMonitor] Reminders: ${reminders}, Returned: ${returned}`);
    } catch (error) {
      console.error("[anytaskSlaMonitor] Fatal error:", error.message);
    }
  }
);


// ═══════════════════════════════════════════════════════════════════════════
// ADMIN CREDIT GRANTS — Soft Launch Tool (v11.9.x)
// ═══════════════════════════════════════════════════════════════════════════
//
// Allows admins to grant promotional / compensation credits to users while
// the Israeli payment provider (Phase 2) is being integrated. Replaces the
// previous client-side direct Firestore write with a hardened Cloud Function.
//
// Security model:
//   1. Only callers with users/{uid}.isAdmin == true may call this CF.
//   2. Admins cannot self-grant (audit-trail integrity).
//   3. Per-grant cap: ₪5,000 (typo protection).
//   4. Per-admin daily cap: ₪20,000 (insider-risk containment).
//   5. Reason field is mandatory (≥10 chars) — written to audit log.
//   6. Idempotency: optional clientReqId prevents double-grants from
//      double-tapped buttons. Reuses same audit/transaction record.
//
// All writes happen in a single Firestore transaction so partial state is
// impossible. The notification + audit log writes are non-transactional
// (best-effort) — the user's balance is the source of truth.
//
// Call from Flutter:
//   await FirebaseFunctions.instance.httpsCallable('grantAdminCredit').call({
//     'targetUserId': uid,
//     'amount':       500,
//     'reason':       'פיצוי על בעיה בהזמנה #abc123',
//     'clientReqId':  'optional-uuid-for-idempotency',
//   });
//
exports.grantAdminCredit = onCall(
  { maxInstances: 10 },
  async (request) => {
    // ── 1. Auth guard ─────────────────────────────────────────────────────
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    if (!(await isAdminCaller(request))) {
      throw new HttpsError("permission-denied", "Admin only.");
    }

    // ── 2. Input validation ───────────────────────────────────────────────
    const { targetUserId, amount, reason, clientReqId } = request.data || {};

    if (!targetUserId || typeof targetUserId !== "string") {
      throw new HttpsError("invalid-argument", "targetUserId is required.");
    }
    if (typeof amount !== "number" || !Number.isFinite(amount) || amount <= 0) {
      throw new HttpsError(
        "invalid-argument",
        "amount must be a positive number.",
      );
    }
    if (amount > 5000) {
      throw new HttpsError(
        "invalid-argument",
        "Per-grant cap is ₪5,000. Split into multiple grants if needed.",
      );
    }
    if (!reason || typeof reason !== "string" || reason.trim().length < 10) {
      throw new HttpsError(
        "invalid-argument",
        "reason is required (minimum 10 characters).",
      );
    }
    if (reason.length > 500) {
      throw new HttpsError("invalid-argument", "reason is too long (max 500).");
    }
    if (targetUserId === request.auth.uid) {
      throw new HttpsError(
        "permission-denied",
        "Admins cannot grant credit to themselves.",
      );
    }

    // Round to 2 decimals to avoid floating-point shenanigans (₪10.0001).
    const roundedAmount = roundNIS(amount);
    const trimmedReason = reason.trim();

    const db = admin.firestore();
    const callerUid = request.auth.uid;

    // ── 3. Idempotency check (best-effort, outside the main transaction) ──
    // If the same admin sends the same clientReqId within the past hour,
    // return the cached result instead of double-charging.
    if (clientReqId && typeof clientReqId === "string") {
      try {
        const idempotencyDoc = await db
          .collection("admin_credit_idempotency")
          .doc(`${callerUid}_${clientReqId}`)
          .get();
        if (idempotencyDoc.exists) {
          const cached = idempotencyDoc.data();
          const ageMs =
            Date.now() - (cached.createdAt?.toMillis?.() || 0);
          if (ageMs < 3600000) {
            console.log(
              `[grantAdminCredit] Idempotent replay: caller=${callerUid} ` +
              `clientReqId=${clientReqId} → returning cached result`,
            );
            return cached.result;
          }
        }
      } catch (e) {
        // Idempotency failure is non-fatal — proceed with the grant.
        console.warn(`[grantAdminCredit] Idempotency check failed: ${e.message}`);
      }
    }

    // ── 4. Daily cap check + atomic balance update ────────────────────────
    // We do the daily-cap check INSIDE the transaction so two concurrent
    // grants from the same admin can't both squeeze through.
    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);
    const todayStartTs = admin.firestore.Timestamp.fromDate(todayStart);

    let beforeBalance = 0;
    let afterBalance = 0;
    let targetUserName = "";
    let dailyTotalToday = 0;

    try {
      await db.runTransaction(async (tx) => {
        // Read 1: target user
        const targetRef = db.collection("users").doc(targetUserId);
        const targetSnap = await tx.get(targetRef);
        if (!targetSnap.exists) {
          throw new HttpsError(
            "not-found",
            `User ${targetUserId} does not exist.`,
          );
        }
        const targetData = targetSnap.data();
        targetUserName = targetData.name || targetData.email || targetUserId;
        beforeBalance = (targetData.balance || 0);
        if (typeof beforeBalance !== "number") beforeBalance = 0;

        // Read 2: daily grants by this admin (sum credits granted today).
        // Uses the admin_audit_log collection so the cap is enforced from
        // the same source the audit trail uses.
        const todayGrantsSnap = await db
          .collection("admin_audit_log")
          .where("adminUid", "==", callerUid)
          .where("action", "==", "grant_credit")
          .where("createdAt", ">=", todayStartTs)
          .get();

        for (const doc of todayGrantsSnap.docs) {
          const a = doc.data().amount;
          if (typeof a === "number") dailyTotalToday += a;
        }

        if (dailyTotalToday + roundedAmount > 20000) {
          throw new HttpsError(
            "failed-precondition",
            `Daily admin grant cap exceeded. Used today: ₪${dailyTotalToday.toFixed(0)} ` +
            `/ ₪20,000. This grant of ₪${roundedAmount.toFixed(0)} would push you over.`,
          );
        }

        // Write 1: increment user balance
        afterBalance = roundNIS(beforeBalance + roundedAmount);
        tx.update(targetRef, {
          balance: admin.firestore.FieldValue.increment(roundedAmount),
        });

        // Write 2: ledger entry in transactions collection
        const txRef = db.collection("transactions").doc();
        tx.set(txRef, {
          userId:        targetUserId,
          receiverId:    targetUserId,
          senderId:      "platform",
          senderName:    "AnySkill (אדמין)",
          amount:        roundedAmount,
          type:          "admin_credit_grant",
          title:         "זיכוי מנהל",
          reason:        trimmedReason,
          grantedBy:     callerUid,
          grantedByName: request.auth.token?.name || request.auth.token?.email || "מנהל",
          payoutStatus:  "completed",
          timestamp:     admin.firestore.FieldValue.serverTimestamp(),
        });

        // Write 3: audit log entry (counts toward daily cap on next call)
        const auditRef = db.collection("admin_audit_log").doc();
        tx.set(auditRef, {
          targetUserId,
          targetName:   targetUserName,
          action:       "grant_credit",
          amount:       roundedAmount,
          reason:       trimmedReason,
          beforeBalance,
          afterBalance,
          adminUid:     callerUid,
          adminName:    request.auth.token?.name || request.auth.token?.email || "מנהל",
          createdAt:    admin.firestore.FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      // Re-throw HttpsError as-is, wrap unknown errors
      if (e instanceof HttpsError) throw e;
      console.error(`[grantAdminCredit] Transaction failed:`, e);
      throw new HttpsError("internal", `Grant failed: ${e.message}`);
    }

    // ── 5. Cache idempotency result (best-effort, outside transaction) ────
    const result = {
      success:       true,
      targetUserId,
      targetName:    targetUserName,
      amount:        roundedAmount,
      beforeBalance,
      afterBalance,
      dailyTotalUsed: roundNIS(dailyTotalToday + roundedAmount),
      dailyCapRemaining: roundNIS(20000 - dailyTotalToday - roundedAmount),
    };

    if (clientReqId && typeof clientReqId === "string") {
      try {
        await db
          .collection("admin_credit_idempotency")
          .doc(`${callerUid}_${clientReqId}`)
          .set({
            callerUid,
            clientReqId,
            result,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
      } catch (e) {
        // Non-fatal — the grant already succeeded
        console.warn(`[grantAdminCredit] Idempotency cache write failed: ${e.message}`);
      }
    }

    // ── 6. Notify the recipient (best-effort) ─────────────────────────────
    try {
      await db.collection("notifications").add({
        userId:    targetUserId,
        title:     "💰 קיבלת זיכוי מ-AnySkill",
        body:      `נטענו ₪${roundedAmount.toFixed(0)} לארנק שלך. סיבה: ${trimmedReason}`,
        type:      "admin_credit",
        isRead:    false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Push notification if FCM token exists
      const targetSnap = await db.collection("users").doc(targetUserId).get();
      const fcmToken = targetSnap.data()?.fcmToken;
      if (fcmToken) {
        await admin.messaging().send({
          token: fcmToken,
          notification: {
            title: "💰 קיבלת זיכוי מ-AnySkill",
            body:  `נטענו ₪${roundedAmount.toFixed(0)} לארנק שלך`,
          },
          data: {
            type:   "admin_credit",
            amount: roundedAmount.toString(),
          },
          android: { priority: "high" },
          apns:    { payload: { aps: { sound: "default" } } },
        });
      }
    } catch (e) {
      // Notification failure is non-fatal — the grant succeeded
      console.warn(`[grantAdminCredit] Notification failed: ${e.message}`);
    }

    console.log(
      `[grantAdminCredit] ✅ admin=${callerUid} → user=${targetUserId} ` +
      `+₪${roundedAmount.toFixed(0)} (${beforeBalance.toFixed(0)} → ${afterBalance.toFixed(0)}) ` +
      `reason="${trimmedReason}" daily=${result.dailyTotalUsed}/20000`,
    );

    return result;
  }
);


// ═══════════════════════════════════════════════════════════════════════════
// SUPPORT AGENT RBAC — v11.9.x
// ═══════════════════════════════════════════════════════════════════════════
//
// Three roles in the system: 'admin', 'support_agent', 'user' (default).
// The role is stored on users/{uid}.role and additionally synced to
// users/{uid}.isAdmin (true iff role == 'admin') for backward compatibility
// with all existing isAdmin checks throughout the codebase.
//
// Setting / changing a role requires an admin caller. Audit-logged.

// ── setUserRole ────────────────────────────────────────────────────────────
// Admin adds or removes roles on a user. Supports two call shapes:
//
// NEW (Phase 1 multi-role):
//   { targetUserId, rolesToAdd?: string[], rolesToRemove?: string[],
//     activeRole?: string }
//
// LEGACY (single-role, still accepted until all clients migrate):
//   { targetUserId, newRole: 'admin' | 'support_agent' | 'user' }
//   → translated to a full replacement of the roles array.
//
// Role catalog: admin, support_agent, provider, customer.
// Backwards-compat shadow writes:
//   • role     = highest-priority role (admin > support_agent > provider > customer)
//   • isAdmin  = true iff 'admin' in roles
//   • isProvider/isCustomer kept unchanged here (provider flows manage them).
//
// Audit log: writes to admin_audit_log AND support_audit_log.
exports.setUserRole = onCall(
  { maxInstances: 10 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    if (!(await isAdminCaller(request))) {
      throw new HttpsError("permission-denied", "Admin only.");
    }

    const data = request.data || {};
    const { targetUserId, newRole, activeRole } = data;
    let { rolesToAdd, rolesToRemove } = data;
    if (!targetUserId || typeof targetUserId !== "string") {
      throw new HttpsError("invalid-argument", "targetUserId is required.");
    }
    if (targetUserId === request.auth.uid) {
      throw new HttpsError(
        "permission-denied",
        "Admins cannot change their own role.",
      );
    }

    const VALID_ROLES = ["admin", "support_agent", "provider", "customer"];

    const validate = (arr, label) => {
      if (arr === undefined || arr === null) return [];
      if (!Array.isArray(arr)) {
        throw new HttpsError("invalid-argument", `${label} must be an array.`);
      }
      for (const r of arr) {
        if (!VALID_ROLES.includes(r)) {
          throw new HttpsError(
            "invalid-argument",
            `${label} contains invalid role "${r}". ` +
            `Allowed: ${VALID_ROLES.join(", ")}`,
          );
        }
      }
      return arr;
    };

    rolesToAdd = validate(rolesToAdd, "rolesToAdd");
    rolesToRemove = validate(rolesToRemove, "rolesToRemove");

    const legacyMode = rolesToAdd.length === 0
      && rolesToRemove.length === 0
      && typeof newRole === "string";

    if (legacyMode) {
      const LEGACY = ["admin", "support_agent", "user", "provider", "customer"];
      if (!LEGACY.includes(newRole)) {
        throw new HttpsError(
          "invalid-argument",
          `newRole must be one of: ${LEGACY.join(", ")}`,
        );
      }
    } else if (rolesToAdd.length === 0 && rolesToRemove.length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "Provide rolesToAdd, rolesToRemove, or legacy newRole.",
      );
    }

    if (activeRole !== undefined && activeRole !== null) {
      if (typeof activeRole !== "string" || !VALID_ROLES.includes(activeRole)) {
        throw new HttpsError(
          "invalid-argument",
          `activeRole must be one of: ${VALID_ROLES.join(", ")}`,
        );
      }
    }

    const db = admin.firestore();
    const callerUid = request.auth.uid;

    let beforeRoles = [];
    let afterRoles = [];
    let targetName = "";

    try {
      const targetRef = db.collection("users").doc(targetUserId);
      const targetSnap = await targetRef.get();
      if (!targetSnap.exists) {
        throw new HttpsError("not-found", `User ${targetUserId} does not exist.`);
      }
      const targetData = targetSnap.data();
      targetName = targetData.name || targetData.email || targetUserId;

      // Compute current roles (new schema first, fall back to legacy).
      beforeRoles = Array.isArray(targetData.roles)
        ? [...targetData.roles]
        : [];
      if (beforeRoles.length === 0) {
        const legacy = targetData.role;
        if (typeof legacy === "string" && legacy.length > 0) {
          beforeRoles.push(legacy === "user" ? "customer" : legacy);
        }
        if (targetData.isAdmin === true && !beforeRoles.includes("admin")) {
          beforeRoles.push("admin");
        }
        if (targetData.isProvider === true && !beforeRoles.includes("provider")) {
          beforeRoles.push("provider");
        }
        if (targetData.isCustomer === true && !beforeRoles.includes("customer")) {
          beforeRoles.push("customer");
        }
        if (beforeRoles.length === 0) beforeRoles.push("customer");
      }

      // Apply diff. We deliberately do NOT auto-add 'customer' as a
      // baseline — making every account multi-role would incorrectly
      // trigger the role switcher for users who only ever wear one hat
      // (e.g. a pure admin or pure support agent). To grant a user
      // additional roles, the admin must add them explicitly.
      const set = new Set(beforeRoles);
      if (legacyMode) {
        // Full replacement — keep only the new role.
        set.clear();
        set.add(newRole === "user" ? "customer" : newRole);
      } else {
        for (const r of rolesToRemove) set.delete(r);
        for (const r of rolesToAdd) set.add(r);
        if (set.size === 0) set.add("customer"); // never empty
      }
      afterRoles = Array.from(set);

      // Resolve the new activeRole. Priority order when not supplied.
      const priorityPick = (arr) => {
        for (const p of ["admin", "support_agent", "provider", "customer"]) {
          if (arr.includes(p)) return p;
        }
        return "customer";
      };
      let nextActive = activeRole;
      if (!nextActive || !afterRoles.includes(nextActive)) {
        const prevActive = typeof targetData.activeRole === "string"
          ? targetData.activeRole : "";
        nextActive = afterRoles.includes(prevActive)
          ? prevActive
          : priorityPick(afterRoles);
      }

      // Shadow writes for backwards-compat callers that still read `role`
      // and `isAdmin` directly.
      const legacyRole = priorityPick(afterRoles);

      await targetRef.update({
        roles: afterRoles,
        activeRole: nextActive,
        role: legacyRole,
        isAdmin: afterRoles.includes("admin"),
        roleUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        roleUpdatedBy: callerUid,
      });

      const auditPayload = {
        targetUserId,
        targetName,
        action: "set_role",
        beforeRoles,
        afterRoles,
        activeRole: nextActive,
        // Keep string-shape fields for legacy audit viewers.
        beforeRole: priorityPick(beforeRoles),
        afterRole: legacyRole,
        adminUid: callerUid,
        adminName: request.auth.token?.name || request.auth.token?.email || "מנהל",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      await db.collection("admin_audit_log").add(auditPayload);
      await db.collection("support_audit_log").add({
        ...auditPayload,
        agentUid: callerUid,
        agentName: auditPayload.adminName,
      });
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("[setUserRole] failed:", e);
      throw new HttpsError("internal", `Failed to set role: ${e.message}`);
    }

    console.log(
      `[setUserRole] ✅ admin=${callerUid} → user=${targetUserId} ` +
      `[${beforeRoles.join(",")}] → [${afterRoles.join(",")}]`,
    );

    return {
      success: true,
      targetUserId,
      targetName,
      beforeRoles,
      afterRoles,
      // Legacy fields preserved for clients that haven't upgraded yet.
      beforeRole: beforeRoles[0] || "customer",
      afterRole: afterRoles[0] || "customer",
    };
  }
);

// ── migrateUserRoles ───────────────────────────────────────────────────────
// Admin-only one-shot migration. Scans every users/{uid} doc and, for any
// user without a `roles` array, writes one derived from the legacy fields
// (role / isAdmin / isProvider / isCustomer). Idempotent — re-running is
// safe and only touches users who haven't been migrated.
//
// Body: { dryRun?: boolean }  (default false)
// Returns: { scanned, migrated, skipped, errors }
exports.migrateUserRoles = onCall(
  { maxInstances: 1, timeoutSeconds: 540 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    if (!(await isAdminCaller(request))) {
      throw new HttpsError("permission-denied", "Admin only.");
    }

    const dryRun = request.data?.dryRun === true;
    const db = admin.firestore();
    const snap = await db.collection("users").get();

    let scanned = 0;
    let migrated = 0;
    let skipped = 0;
    const errors = [];

    const chunkSize = 400; // Firestore batched-write limit is 500.
    let batch = db.batch();
    let batched = 0;

    const priorityPick = (arr) => {
      for (const p of ["admin", "support_agent", "provider", "customer"]) {
        if (arr.includes(p)) return p;
      }
      return "customer";
    };

    for (const doc of snap.docs) {
      scanned++;
      try {
        const d = doc.data() || {};
        if (Array.isArray(d.roles) && d.roles.length > 0) {
          skipped++;
          continue;
        }

        const resolved = new Set();
        const legacy = typeof d.role === "string" ? d.role : "";
        if (legacy) resolved.add(legacy === "user" ? "customer" : legacy);
        if (d.isAdmin === true) resolved.add("admin");
        if (d.isProvider === true) resolved.add("provider");
        if (d.isCustomer === true) resolved.add("customer");
        if (resolved.size === 0) resolved.add("customer");

        const rolesArr = Array.from(resolved);
        const activeRole = typeof d.activeRole === "string"
            && resolved.has(d.activeRole)
          ? d.activeRole
          : priorityPick(rolesArr);

        if (dryRun) {
          migrated++;
          continue;
        }

        batch.update(doc.ref, {
          roles: rolesArr,
          activeRole,
          rolesMigratedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        batched++;
        migrated++;

        if (batched >= chunkSize) {
          await batch.commit();
          batch = db.batch();
          batched = 0;
        }
      } catch (e) {
        errors.push({ uid: doc.id, error: String(e.message || e) });
      }
    }

    if (batched > 0) await batch.commit();

    try {
      await db.collection("admin_audit_log").add({
        action: "migrate_user_roles",
        dryRun,
        scanned,
        migrated,
        skipped,
        errorCount: errors.length,
        errorSamples: errors.slice(0, 10),
        adminUid: request.auth.uid,
        adminName: request.auth.token?.name || request.auth.token?.email || "מנהל",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Audit log best-effort; don't fail the whole migration on logging.
    }

    console.log(
      `[migrateUserRoles] dryRun=${dryRun} scanned=${scanned} ` +
      `migrated=${migrated} skipped=${skipped} errors=${errors.length}`,
    );

    return { scanned, migrated, skipped, errors: errors.length, dryRun };
  }
);


// ── supportAgentAction ─────────────────────────────────────────────────────
// Centralized endpoint for actions a support agent can take on a customer.
// All actions require either admin OR support_agent role.
//
// Supported actions (controlled vocabulary):
//   • verify_identity   → sets users/{uid}.isVerified = true
//   • flag_account      → sets users/{uid}.flagged = true
//   • unflag_account    → sets users/{uid}.flagged = false
//   • send_password_reset → triggers Firebase auth password reset email
//
// Refunds and credit grants stay in their dedicated CFs (processRefund,
// grantAdminCredit) which already have their own validation and caps.
//
// Body: { action, targetUserId, reason?, ticketId? }
exports.supportAgentAction = onCall(
  { maxInstances: 10 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    // Check caller is admin OR support agent
    const callerUid = request.auth.uid;
    const callerSnap = await admin.firestore()
      .collection("users").doc(callerUid).get();
    if (!callerSnap.exists) {
      throw new HttpsError("permission-denied", "Caller not found.");
    }
    const callerData = callerSnap.data();
    const callerRole = callerData.role
      || (callerData.isAdmin === true ? "admin" : "user");
    if (callerRole !== "admin" && callerRole !== "support_agent") {
      throw new HttpsError(
        "permission-denied",
        "This endpoint requires admin or support_agent role.",
      );
    }

    const { action, targetUserId, reason, ticketId } = request.data || {};
    if (!action || !targetUserId) {
      throw new HttpsError(
        "invalid-argument",
        "action and targetUserId are required.",
      );
    }
    if (callerUid === targetUserId) {
      throw new HttpsError(
        "permission-denied",
        "Agents cannot perform actions on their own account.",
      );
    }
    if (typeof reason !== "string" || reason.trim().length < 5) {
      throw new HttpsError(
        "invalid-argument",
        "reason is required (minimum 5 characters).",
      );
    }

    const VALID_ACTIONS = [
      "verify_identity",
      "flag_account",
      "unflag_account",
      "send_password_reset",
    ];
    if (!VALID_ACTIONS.includes(action)) {
      throw new HttpsError(
        "invalid-argument",
        `Unknown action. Valid: ${VALID_ACTIONS.join(", ")}`,
      );
    }

    const db = admin.firestore();
    const targetRef = db.collection("users").doc(targetUserId);
    const targetSnap = await targetRef.get();
    if (!targetSnap.exists) {
      throw new HttpsError("not-found", "Target user does not exist.");
    }
    const targetData = targetSnap.data();
    const targetName = targetData.name || targetData.email || targetUserId;

    let actionResult = {};

    try {
      switch (action) {
        case "verify_identity":
          await targetRef.update({
            isVerified: true,
            isPendingExpert: false,
            verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
            verifiedBy: callerUid,
          });
          actionResult = { isVerified: true };
          break;

        case "flag_account":
          await targetRef.update({
            flagged: true,
            flaggedAt: admin.firestore.FieldValue.serverTimestamp(),
            flaggedBy: callerUid,
            flagReason: reason.trim(),
          });
          actionResult = { flagged: true };
          break;

        case "unflag_account":
          await targetRef.update({
            flagged: false,
            unflaggedAt: admin.firestore.FieldValue.serverTimestamp(),
            unflaggedBy: callerUid,
          });
          actionResult = { flagged: false };
          break;

        case "send_password_reset": {
          // Generate the password reset link via Admin SDK
          const userRecord = await admin.auth().getUser(targetUserId);
          if (!userRecord.email) {
            throw new HttpsError(
              "failed-precondition",
              "User has no email address on record.",
            );
          }
          const link = await admin.auth().generatePasswordResetLink(
            userRecord.email,
          );
          // Write to mail collection (Firestore Send Email extension picks up)
          await db.collection("mail").add({
            to: userRecord.email,
            message: {
              subject: "איפוס סיסמה — AnySkill",
              html: `
                <div dir="rtl" style="font-family:Arial,sans-serif">
                  <h2>שלום ${targetName},</h2>
                  <p>בקשת איפוס סיסמה הוגשה לחשבונך.</p>
                  <p><a href="${link}" style="background:#6366F1;color:#fff;padding:10px 20px;border-radius:8px;text-decoration:none">איפוס הסיסמה</a></p>
                  <p style="color:#9CA3AF;font-size:12px">אם לא ביקשת איפוס, התעלם מהמייל.</p>
                </div>
              `,
            },
          });
          actionResult = { emailSent: true, sentTo: userRecord.email };
          break;
        }
      }
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error(`[supportAgentAction] ${action} failed:`, e);
      throw new HttpsError("internal", `Action failed: ${e.message}`);
    }

    // Audit log — every sensitive action goes through here
    try {
      await db.collection("support_audit_log").add({
        agentUid: callerUid,
        agentName: callerData.name || callerData.email || "סוכן",
        agentRole: callerRole,
        action,
        targetUserId,
        targetName,
        reason: reason.trim(),
        ticketId: ticketId || null,
        result: actionResult,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (e) {
      console.warn(`[supportAgentAction] audit log failed: ${e.message}`);
    }

    console.log(
      `[supportAgentAction] ✅ ${callerRole}=${callerUid} action=${action} ` +
      `target=${targetUserId} reason="${reason.trim().substring(0, 50)}"`,
    );

    return {
      success: true,
      action,
      targetUserId,
      targetName,
      ...actionResult,
    };
  }
);

// ═══════════════════════════════════════════════════════════════════════════
// PR-C (v12.5.0): Email verification via 6-digit code
// ═══════════════════════════════════════════════════════════════════════════
//
// Two callables so phone-OTP users can add (and verify) an email for
// invoices / communication, without linking a second Auth provider.
//
//   sendEmailVerificationCode({ email })
//     - Writes a hashed code to email_verification_codes/{uid}
//     - Writes a Hebrew email via the `mail` collection (Trigger Email)
//     - 10-minute TTL, max 5 sends per hour per caller, max 6 tries per code
//
//   verifyEmailCode({ code })
//     - Checks the stored code; on match writes email + emailVerifiedAt
//       to users/{uid} AND private/identity; clears the code doc.
//
// Email is NOT linked as a Firebase Auth provider — it's stored purely as
// a contact field. This avoids the password-or-magic-link complexity that
// EmailAuthProvider.linkWithCredential would require.

const EMAIL_CODE_TTL_MIN = 10;
const EMAIL_CODE_MAX_TRIES = 6;
const EMAIL_SEND_RATE_LIMIT = 5;       // sends per hour per caller
const EMAIL_SEND_RATE_WINDOW_MS = 60 * 60 * 1000;

function _hashCode(code, salt) {
  const crypto = require("crypto");
  return crypto.createHash("sha256").update(`${salt}:${code}`).digest("hex");
}

exports.sendEmailVerificationCode = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    const uid = request.auth.uid;
    const rawEmail = String(request.data?.email || "").trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(rawEmail)) {
      throw new HttpsError("invalid-argument", "Invalid email.");
    }

    const db = admin.firestore();

    // Anti-duplicate: block if this email is already on ANOTHER user doc.
    const dup = await db.collection("users")
      .where("email", "==", rawEmail)
      .limit(2)
      .get();
    for (const doc of dup.docs) {
      if (doc.id !== uid) {
        throw new HttpsError(
          "already-exists",
          "המייל הזה כבר משויך לחשבון אחר",
        );
      }
    }

    // Rate limit: read current doc, count recent sends.
    const codeRef = db.collection("email_verification_codes").doc(uid);
    const now = Date.now();
    const existing = await codeRef.get();
    if (existing.exists) {
      const data = existing.data() || {};
      const recent = (data.sendHistory || [])
        .filter((ts) => now - (ts?.toMillis?.() ?? ts) < EMAIL_SEND_RATE_WINDOW_MS);
      if (recent.length >= EMAIL_SEND_RATE_LIMIT) {
        throw new HttpsError(
          "resource-exhausted",
          "יותר מדי בקשות — נסה/י שוב בעוד שעה",
        );
      }
    }

    // Generate 6-digit code + salt, store the hash (never the plaintext).
    const code = String(Math.floor(100000 + Math.random() * 900000));
    const crypto = require("crypto");
    const salt = crypto.randomBytes(16).toString("hex");
    const hash = _hashCode(code, salt);
    const expiresAt = admin.firestore.Timestamp.fromDate(
        new Date(now + EMAIL_CODE_TTL_MIN * 60 * 1000));

    await codeRef.set({
      uid,
      email: rawEmail,
      codeHash: hash,
      salt,
      tries: 0,
      expiresAt,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      sendHistory: admin.firestore.FieldValue.arrayUnion(
          admin.firestore.Timestamp.fromDate(new Date(now))),
      // TTL on the whole doc after 1 day — safety net.
      expireAt: admin.firestore.Timestamp.fromDate(
          new Date(now + 24 * 60 * 60 * 1000)),
    }, { merge: true });

    // Queue the email via Trigger Email Extension (writes to `mail`).
    const subject = "AnySkill — קוד אימות מייל";
    const html = `
      <div dir="rtl" style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;color:#1A1A2E;">
        <h2 style="color:#6366F1;margin:0 0 16px;">קוד אימות</h2>
        <p>שלום,</p>
        <p>קיבלנו בקשה לאמת את כתובת המייל הזו לחשבון AnySkill שלך.</p>
        <p>קוד האימות שלך:</p>
        <div style="font-size:32px;font-weight:bold;letter-spacing:8px;background:#F4F7F9;padding:16px;text-align:center;border-radius:12px;margin:24px 0;">
          ${code}
        </div>
        <p style="color:#6B7280;font-size:13px;">הקוד תקף ל-${EMAIL_CODE_TTL_MIN} דקות. אם לא ביקשת אימות — התעלם/י מהמייל הזה.</p>
        <hr style="border:none;border-top:1px solid #E5E7EB;margin:32px 0 16px;">
        <p style="color:#9CA3AF;font-size:12px;">AnySkill · שירות בקהילה שלך</p>
      </div>
    `;
    await db.collection("mail").add({
      to: [rawEmail],
      message: { subject, html },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true, expiresInMin: EMAIL_CODE_TTL_MIN };
  },
);

exports.verifyEmailCode = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    const uid = request.auth.uid;
    const code = String(request.data?.code || "").trim();
    if (!/^\d{6}$/.test(code)) {
      throw new HttpsError("invalid-argument", "Invalid code.");
    }

    const db = admin.firestore();
    const codeRef = db.collection("email_verification_codes").doc(uid);
    const snap = await codeRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "לא נשלח קוד — בקש/י קוד חדש");
    }
    const data = snap.data();
    const now = Date.now();
    const expMs = data.expiresAt?.toMillis?.() ?? 0;
    if (expMs < now) {
      await codeRef.delete();
      throw new HttpsError("deadline-exceeded", "הקוד פג תוקף — בקש/י חדש");
    }
    if ((data.tries || 0) >= EMAIL_CODE_MAX_TRIES) {
      await codeRef.delete();
      throw new HttpsError("resource-exhausted", "יותר מדי ניסיונות — בקש/י קוד חדש");
    }

    const expectedHash = _hashCode(code, data.salt);
    if (expectedHash !== data.codeHash) {
      await codeRef.update({ tries: admin.firestore.FieldValue.increment(1) });
      throw new HttpsError("permission-denied", "קוד שגוי");
    }

    // Success — write email + emailVerifiedAt to main doc AND private/identity.
    const email = data.email;
    const userRef = db.collection("users").doc(uid);
    const privRef = userRef.collection("private").doc("identity");
    const batch = db.batch();
    batch.update(userRef, {
      email,
      emailVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    batch.set(privRef, {
      email,
      emailVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    batch.delete(codeRef);
    await batch.commit();

    return { success: true, email };
  },
);

// ═══════════════════════════════════════════════════════════════════════════
// v12.7.0: Legacy account unifier — link phones to Auth
// ═══════════════════════════════════════════════════════════════════════════
//
// Context: Email/password login was removed in v12.5. Legacy users (e.g.
// Sigalit) previously signed in with email. Their user doc + phone are
// stored in Firestore, but Firebase Auth doesn't know their phone.
// When they log in with phone for the first time, Firebase creates a NEW
// uid and the app doesn't recognize them.
//
// `backfillPhonesToAuth` iterates every users/{uid} with a non-empty phone
// and calls admin.auth().updateUser(uid, { phoneNumber }). Once done, a
// subsequent phone login with that number routes to the EXISTING uid, so
// the user's legacy profile + history is preserved automatically.
//
// Idempotent — skips users already carrying a phoneNumber in Auth.
// Admin-only.

function _normalizeE164(raw) {
  if (!raw) return null;
  const digits = String(raw).replace(/\D/g, "");
  if (!digits) return null;
  // Israeli: 05XXXXXXXX → +9725XXXXXXXX
  if (digits.length === 10 && digits.startsWith("0")) {
    return "+972" + digits.substring(1);
  }
  // Already E.164-ish (starts with country code like 972)
  if (String(raw).startsWith("+")) return String(raw);
  return "+" + digits;
}

exports.backfillPhonesToAuth = onCall(
  { region: "us-central1", timeoutSeconds: 540 },
  async (request) => {
    if (!(await isAdminCaller(request))) {
      throw new HttpsError("permission-denied", "Admin only.");
    }
    const db = admin.firestore();
    const snap = await db.collection("users")
      .where("phone", ">", "")
      .get();

    let scanned = 0;
    let updated = 0;
    let skipped = 0;
    let errors = 0;
    const errorSamples = [];

    for (const doc of snap.docs) {
      scanned++;
      const data = doc.data();
      const rawPhone = data.phone;
      const e164 = _normalizeE164(rawPhone);
      if (!e164 || e164.length < 10) { skipped++; continue; }
      try {
        let authUser;
        try {
          authUser = await admin.auth().getUser(doc.id);
        } catch (getErr) {
          // Auth user missing — skip but log as diagnostic so we know.
          console.error(`[Backfill] getUser(${doc.id}) failed:`, getErr.code, getErr.message);
          skipped++;
          continue;
        }
        if (authUser.phoneNumber === e164) {
          skipped++;
          continue;
        }
        await admin.auth().updateUser(doc.id, { phoneNumber: e164 });
        updated++;
      } catch (e) {
        errors++;
        const sample = {
          uid: doc.id,
          name: data.name || "(no-name)",
          rawPhone: String(rawPhone || ""),
          e164,
          errorCode: e.code || "unknown",
          errorMessage: String(e.message || e),
        };
        // No truncation cap during diagnostic run.
        errorSamples.push(sample);
        console.error(`[Backfill] updateUser(${doc.id}) → ${e164} FAILED:`, sample);
      }
    }

    console.error(`[Backfill] SUMMARY — scanned=${scanned}, updated=${updated}, skipped=${skipped}, errors=${errors}`);
    if (errorSamples.length) {
      console.error(`[Backfill] All error samples:`, JSON.stringify(errorSamples, null, 2));
    }

    // Audit
    await db.collection("admin_audit_log").add({
      action: "backfill_phones_to_auth",
      adminUid: request.auth.uid,
      scanned, updated, skipped, errors,
      errorSamples,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { scanned, updated, skipped, errors, errorSamples };
  },
);

// Companion: per-user lookup for the OTP client.
// Given a phone number, returns the uid of the user doc that holds it (if
// any). Used by otp_screen to detect "new Auth uid but legacy user doc
// exists" — a sign the backfill hasn't run yet for this user.
//
// Auth not required — pre-signup lookup. Rate-limited per IP to prevent
// phone-number enumeration attacks. After the limit is hit, returns
// honeypot "not found" responses so the attacker cannot distinguish
// rate-limited from genuine misses.
const _phoneLookupBuckets = new Map(); // ip → {count, resetAt}
const _PHONE_LOOKUP_MAX = 10;          // max requests per window
const _PHONE_LOOKUP_WINDOW_MS = 60_000; // 1 minute

exports.lookupLegacyUidByPhone = onCall(
  { region: "us-central1" },
  async (request) => {
    // ── IP-based rate limit ──
    const ip = request.rawRequest?.ip || request.rawRequest?.headers?.["x-forwarded-for"] || "unknown";
    const now = Date.now();
    let bucket = _phoneLookupBuckets.get(ip);
    if (!bucket || now > bucket.resetAt) {
      bucket = { count: 0, resetAt: now + _PHONE_LOOKUP_WINDOW_MS };
      _phoneLookupBuckets.set(ip, bucket);
    }
    bucket.count++;

    if (bucket.count > _PHONE_LOOKUP_MAX) {
      // Honeypot: return fake "not found" instead of 429, so attacker
      // cannot tell they've been blocked.
      const db = admin.firestore();
      try {
        db.collection("activity_log").add({
          type: "rate_limit_phone_lookup",
          ip,
          count: bucket.count,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          expireAt: admin.firestore.Timestamp.fromDate(
            new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
          ),
        });
      } catch (_) { /* best-effort logging */ }
      return { found: false };
    }

    const phone = _normalizeE164(request.data?.phone);
    if (!phone || phone.length < 10) {
      throw new HttpsError("invalid-argument", "Invalid phone.");
    }
    const db = admin.firestore();
    const snap = await db.collection("users")
      .where("phone", "==", phone)
      .limit(1)
      .get();
    if (snap.empty) return { found: false };
    return { found: true, uid: snap.docs[0].id };
  },
);

// ═══════════════════════════════════════════════════════════════════
// Escrow Payment — Server-Side (Q7 audit fix)
// Moves pendingBalance writes out of the client to prevent cross-user
// manipulation. Mirrors the logic previously in escrow_service.dart.
// ═══════════════════════════════════════════════════════════════════

exports.createEscrowPayment = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    const uid = request.auth.uid;
    const {
      quoteId, chatMessageId, chatRoomId,
      providerId, providerName, clientName,
      amount, description,
    } = request.data || {};

    if (!quoteId || !providerId || !amount || !chatRoomId) {
      throw new HttpsError("invalid-argument", "Missing required fields.");
    }
    if (uid === providerId) {
      throw new HttpsError("permission-denied", "לא ניתן להזמין שירות מעצמך");
    }
    if (typeof amount !== "number" || amount <= 0) {
      throw new HttpsError("invalid-argument", "Amount must be positive.");
    }
    if (amount > 5000) {
      throw new HttpsError("invalid-argument", "הסכום חורג מהמקסימום (₪5,000). פנה לתמיכה.");
    }

    const db = admin.firestore();
    const adminSettingsRef = db.collection("admin").doc("admin")
      .collection("settings").doc("settings");

    let createdJobId = null;

    await db.runTransaction(async (tx) => {
      const clientDoc = await tx.get(db.collection("users").doc(uid));
      const adminDoc = await tx.get(adminSettingsRef);
      const quoteDoc = await tx.get(db.collection("quotes").doc(quoteId));
      const providerDoc = await tx.get(db.collection("users").doc(providerId));

      const currentStatus = (quoteDoc.data() || {}).status || "";
      if (currentStatus === "paid") {
        createdJobId = (quoteDoc.data() || {}).jobId || "__already_paid";
        return; // idempotent — return existing jobId
      }

      const clientBalance = Number((clientDoc.data() || {}).balance || 0);
      if (clientBalance < amount) {
        throw new HttpsError("failed-precondition",
          `אין מספיק יתרה בארנק. נדרשת יתרה של ₪${Math.round(amount)}.`);
      }

      // Layered commission: custom > category > global
      let feePct = Number((adminDoc.data() || {}).feePercentage || 0.1);
      let feeSource = "global";

      const providerData = providerDoc.data() || {};
      const providerCategory = (providerData.serviceType || "").toString();

      if (providerCategory) {
        const catDoc = await tx.get(
          db.collection("category_commissions").doc(providerCategory)
        );
        if (catDoc.exists) {
          const catPct = catDoc.data()?.percentage;
          if (catPct != null) { feePct = Number(catPct) / 100; feeSource = "category"; }
        }
      }

      const customActive = providerData.customCommissionActive === true;
      const custom = providerData.customCommission;
      if (customActive && custom && typeof custom === "object") {
        const pct = custom.percentage;
        const expiresAt = custom.expiresAt;
        const live = !expiresAt || (expiresAt.toDate ? expiresAt.toDate() > new Date() : true);
        if (pct != null && live) { feePct = Number(pct) / 100; feeSource = "custom"; }
      }

      const roundNIS = (n) => Math.round(n * 100) / 100;
      const commission = roundNIS(amount * feePct);
      const netToProvider = roundNIS(amount - commission);

      const jobRef = db.collection("jobs").doc();
      createdJobId = jobRef.id;

      tx.set(jobRef, {
        expertId: providerId,
        expertName: providerName,
        customerId: uid,
        customerName: clientName,
        totalAmount: amount,
        netAmountForExpert: netToProvider,
        commission,
        commissionFeePct: feePct * 100,
        commissionSource: feeSource,
        description: description || "",
        status: "paid_escrow",
        source: "quote",
        quoteId,
        chatRoomId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        clientReviewDone: false,
        providerReviewDone: false,
      });

      tx.update(db.collection("users").doc(uid), {
        balance: admin.firestore.FieldValue.increment(-amount),
      });
      tx.update(db.collection("users").doc(providerId), {
        pendingBalance: admin.firestore.FieldValue.increment(netToProvider),
      });
      tx.set(db.collection("platform_earnings").doc(), {
        jobId: jobRef.id,
        amount: commission,
        sourceExpertId: providerId,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        status: "pending_escrow",
      });
      tx.set(db.collection("transactions").doc(), {
        senderId: uid,
        senderName: clientName,
        receiverId: providerId,
        receiverName: providerName,
        amount,
        type: "quote_payment",
        jobId: jobRef.id,
        quoteId,
        payoutStatus: "pending",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
      tx.update(db.collection("quotes").doc(quoteId), {
        status: "paid",
        jobId: jobRef.id,
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      if (chatMessageId) {
        tx.update(
          db.collection("chats").doc(chatRoomId)
            .collection("messages").doc(chatMessageId),
          { quoteStatus: "paid", jobId: jobRef.id },
        );
      }

      tx.set(adminSettingsRef,
        { totalPlatformBalance: admin.firestore.FieldValue.increment(commission) },
        { merge: true },
      );
    });

    // System chat message (outside tx, best-effort)
    if (createdJobId) {
      try {
        await db.collection("chats").doc(chatRoomId)
          .collection("messages").add({
            senderId: "system",
            message: `✅ ₪${Math.round(amount)} נעולים באסקרו. העבודה יכולה להתחיל!`,
            type: "system_alert",
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
          });
      } catch (_) { /* non-critical */ }
    }

    return { success: true, jobId: createdJobId };
  },
);

exports.createTaskEscrow = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    const uid = request.auth.uid;
    const {
      taskId, responseId, providerId, providerName,
      clientName, agreedPriceNis, taskTitle,
    } = request.data || {};

    if (!taskId || !providerId || !agreedPriceNis) {
      throw new HttpsError("invalid-argument", "Missing required fields.");
    }
    if (uid === providerId) {
      throw new HttpsError("permission-denied", "לא ניתן להזמין שירות מעצמך");
    }
    if (typeof agreedPriceNis !== "number" || agreedPriceNis < 10) {
      throw new HttpsError("invalid-argument", "המחיר חייב להיות לפחות ₪10");
    }

    const db = admin.firestore();
    const adminSettingsRef = db.collection("admin").doc("admin")
      .collection("settings").doc("settings");
    const taskRef = db.collection("any_tasks").doc(taskId);
    const responseRef = responseId ? taskRef.collection("responses").doc(responseId) : null;

    await db.runTransaction(async (tx) => {
      const taskSnap = await tx.get(taskRef);
      const clientSnap = await tx.get(db.collection("users").doc(uid));
      const adminSnap = await tx.get(adminSettingsRef);

      if (!taskSnap.exists) throw new HttpsError("not-found", "המשימה לא נמצאה");
      if (taskSnap.data().status !== "open") {
        throw new HttpsError("failed-precondition", "המשימה כבר שויכה לנותן שירות אחר");
      }

      const balance = Number((clientSnap.data() || {}).balance || 0);
      if (balance < agreedPriceNis) {
        throw new HttpsError("failed-precondition",
          `אין מספיק יתרה בארנק. נדרשת יתרה של ₪${agreedPriceNis}`);
      }

      const feePct = Number((adminSnap.data() || {}).feePercentage || 0.1);
      const commission = Math.round(agreedPriceNis * feePct);
      const netToProvider = agreedPriceNis - commission;

      tx.update(taskRef, {
        selectedProviderId: providerId,
        selectedProviderName: providerName,
        agreedPriceNis,
        platformFeeNis: commission,
        providerPayoutNis: netToProvider,
        status: "in_progress",
        acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      if (responseRef) {
        const rSnap = await tx.get(responseRef);
        if (rSnap.exists) tx.update(responseRef, { status: "chosen" });
      }

      tx.update(db.collection("users").doc(uid), {
        balance: admin.firestore.FieldValue.increment(-agreedPriceNis),
      });
      tx.update(db.collection("users").doc(providerId), {
        pendingBalance: admin.firestore.FieldValue.increment(netToProvider),
      });
      tx.set(db.collection("platform_earnings").doc(), {
        taskId,
        amount: commission,
        sourceExpertId: providerId,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        status: "pending_escrow",
        source: "any_tasks",
      });
      tx.set(db.collection("transactions").doc(), {
        senderId: uid,
        senderName: clientName || "",
        receiverId: providerId,
        receiverName: providerName,
        amount: agreedPriceNis,
        type: "any_task_escrow",
        taskId,
        taskTitle: taskTitle || "",
        payoutStatus: "pending",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
      tx.set(adminSettingsRef,
        { totalPlatformBalance: admin.firestore.FieldValue.increment(commission) },
        { merge: true },
      );
    });

    return { success: true };
  },
);

exports.addTipToJob = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    const uid = request.auth.uid;
    const { jobId, expertId, tipAmount, expertName } = request.data || {};
    if (!jobId || !expertId || typeof tipAmount !== "number" || tipAmount <= 0) {
      throw new HttpsError("invalid-argument", "Missing or invalid fields.");
    }

    const db = admin.firestore();
    const batch = db.batch();

    batch.set(db.collection("transactions").doc(), {
      senderId: uid,
      receiverId: expertId,
      receiverName: expertName || "",
      amount: tipAmount,
      type: "tip",
      jobId,
      payoutStatus: "pending",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
    batch.update(db.collection("users").doc(expertId), {
      pendingBalance: admin.firestore.FieldValue.increment(tipAmount),
    });
    batch.update(db.collection("users").doc(uid), {
      balance: admin.firestore.FieldValue.increment(-tipAmount),
    });
    await batch.commit();

    return { success: true };
  },
);

// ═══════════════════════════════════════════════════════════════════
// AnyTasks v14.0.0 — Payment Release + Dispute
// ═══════════════════════════════════════════════════════════════════

/**
 * releaseTaskPayment — Client confirms completion, escrow releases to
 * provider. Mirrors processPaymentRelease but for the any_tasks schema.
 *
 * Input:  { taskId }
 * Auth:   Caller MUST be the task's client.
 * Side effects (atomic):
 *   • any_tasks/{id}.status = 'completed', completedAt
 *   • users/{providerId}.balance += providerPayoutNis
 *   • users/{providerId}.pendingBalance -= providerPayoutNis
 *   • users/{providerId}.orderCount += 1
 *   • platform_earnings doc for this task → status: 'released'
 *   • transactions log (payout type)
 */
exports.releaseTaskPayment = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }
  const { taskId } = request.data || {};
  if (!taskId) {
    throw new HttpsError('invalid-argument', 'taskId is required.');
  }

  const db = admin.firestore();
  const taskRef = db.collection('any_tasks').doc(taskId);

  const taskSnap = await taskRef.get();
  if (!taskSnap.exists) {
    throw new HttpsError('not-found', 'Task not found.');
  }
  const t = taskSnap.data();
  if (t.clientId !== request.auth.uid) {
    throw new HttpsError('permission-denied',
      'Only the client can release payment.');
  }
  if (t.status !== 'proof_submitted') {
    throw new HttpsError('failed-precondition',
      `Task status is '${t.status}', expected 'proof_submitted'.`);
  }
  if (!t.selectedProviderId || t.providerPayoutNis == null) {
    throw new HttpsError('failed-precondition',
      'Task has no selected provider or escrow fields.');
  }

  const providerRef = db.collection('users').doc(t.selectedProviderId);
  const net = Number(t.providerPayoutNis);

  await db.runTransaction(async (tx) => {
    // Idempotency re-read
    const fresh = await tx.get(taskRef);
    if (!fresh.exists || fresh.data().status !== 'proof_submitted') {
      throw new HttpsError('failed-precondition',
        'Task was changed concurrently.');
    }

    // 1. Credit provider
    tx.update(providerRef, {
      balance: admin.firestore.FieldValue.increment(net),
      pendingBalance: admin.firestore.FieldValue.increment(-net),
      orderCount: admin.firestore.FieldValue.increment(1),
    });

    // 2. Flip task status
    tx.update(taskRef, {
      status: 'completed',
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 3. Transaction log (payout)
    tx.set(db.collection('transactions').doc(), {
      senderId: t.clientId,
      senderName: t.clientName || 'לקוח',
      receiverId: t.selectedProviderId,
      receiverName: t.selectedProviderName || 'ספק',
      amount: net,
      type: 'any_task_payout',
      taskId: taskId,
      taskTitle: t.title || '',
      payoutStatus: 'released',
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  // Best-effort: flip platform_earnings record to released (outside tx)
  try {
    const earningsSnap = await db.collection('platform_earnings')
      .where('taskId', '==', taskId).limit(1).get();
    if (!earningsSnap.empty) {
      await earningsSnap.docs[0].ref.update({ status: 'released' });
    }
  } catch (e) {
    console.warn(`[releaseTaskPayment] platform_earnings flip failed: ${e.message}`);
  }

  // Best-effort: notify provider
  try {
    await db.collection('notifications').add({
      userId: t.selectedProviderId,
      title: '💰 התשלום שוחרר!',
      body: `₪${net} הועברו לארנק שלך עבור "${t.title || 'המשימה'}"`,
      type: 'any_task_paid',
      taskId: taskId,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    console.warn(`[releaseTaskPayment] notify failed: ${e.message}`);
  }

  return { success: true, amountPaid: net };
});

/**
 * raiseTaskDispute — Either party flags a problem. Flips status to
 * 'disputed' and notifies admins for 48h SLA review. Does NOT refund
 * automatically — admin uses the existing dispute resolution UI.
 *
 * Input:  { taskId, reason }
 * Auth:   Caller MUST be the task's client or selected provider.
 */
exports.raiseTaskDispute = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }
  const { taskId, reason } = request.data || {};
  if (!taskId || !reason || reason.length < 10) {
    throw new HttpsError('invalid-argument',
      'taskId and reason (≥10 chars) are required.');
  }

  const db = admin.firestore();
  const taskRef = db.collection('any_tasks').doc(taskId);
  const taskSnap = await taskRef.get();
  if (!taskSnap.exists) {
    throw new HttpsError('not-found', 'Task not found.');
  }
  const t = taskSnap.data();
  const isParticipant = t.clientId === request.auth.uid
    || t.selectedProviderId === request.auth.uid;
  if (!isParticipant) {
    throw new HttpsError('permission-denied',
      'Only task participants can raise a dispute.');
  }
  if (!['in_progress', 'proof_submitted'].includes(t.status)) {
    throw new HttpsError('failed-precondition',
      `Task status is '${t.status}', cannot raise dispute.`);
  }

  await taskRef.update({
    status: 'disputed',
    disputedBy: request.auth.uid,
    disputeReason: reason,
    disputedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Fan-out admin notifications
  try {
    const adminsSnap = await db.collection('users')
      .where('isAdmin', '==', true).limit(10).get();
    const batch = db.batch();
    for (const doc of adminsSnap.docs) {
      batch.set(db.collection('notifications').doc(), {
        userId: doc.id,
        title: '🚨 מחלוקת חדשה במשימה',
        body: `משימה "${t.title || ''}" דווחה. יש לטפל תוך 48 שעות.`,
        type: 'any_task_dispute',
        taskId: taskId,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  } catch (e) {
    console.warn(`[raiseTaskDispute] admin notify failed: ${e.message}`);
  }

  return { success: true };
});

// ═══════════════════════════════════════════════════════════════════
// AnyTasks v14.0.0 — AI Auto-Tag + TTL Expiry Cron
// ═══════════════════════════════════════════════════════════════════

/**
 * generateTaskTags — Given a task title + description, returns:
 *   • suggestedCategory: one of kTaskCategories (delivery/cleaning/...)
 *   • suggestedUrgency:  flexible/today/urgent_now
 *   • tags:              3–5 short Hebrew tags for discoverability
 *
 * Auth: any authenticated user. Rate-limited indirectly by Firestore cost
 * tracking. Uses Claude Haiku for low latency + cheap.
 */
exports.generateTaskTags = onCall(
  {
    secrets:      [ANTHROPIC_API_KEY],
    maxInstances: 5,
    region:       "us-central1",
    memory:       "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Login required.");
    }
    const title = (request.data?.title || "").trim();
    const description = (request.data?.description || "").trim();
    if (title.length < 3) {
      throw new HttpsError("invalid-argument",
        "Title must be at least 3 characters.");
    }

    const apiKey = ANTHROPIC_API_KEY.value() || process.env.ANTHROPIC_API_KEY || "";
    if (!apiKey) {
      throw new HttpsError("internal",
        "SECRET_MISSING: ANTHROPIC_API_KEY not configured.");
    }

    const anthropic = new Anthropic({ apiKey });

    const systemPrompt = `You are an assistant for AnyTasks, an Israeli micro-task marketplace. Given a task title + description (usually Hebrew), return a strict JSON object with:
  {
    "suggestedCategory": "delivery"|"cleaning"|"handyman"|"moving"|"pet_care"|"tech_support"|"tutoring"|"other",
    "suggestedUrgency":  "flexible"|"today"|"urgent_now",
    "tags":              ["3-5 short Hebrew tag words"]
  }
No explanation. Only valid JSON. Tags must be 1-2 Hebrew words each, lowercase-free (Hebrew has no case). If the task is ambiguous, default to "other" + "flexible".`;

    const msg = await anthropic.messages.create({
      model:      "claude-haiku-4-5-20251001",
      max_tokens: 256,
      system:     systemPrompt,
      messages:   [{
        role: "user",
        content: `Title: ${title}\nDescription: ${description}`,
      }],
    });

    // Track cost (best effort)
    try {
      await _trackApiCost(
        admin.firestore(),
        msg.usage?.input_tokens || 0,
        msg.usage?.output_tokens || 0,
      );
    } catch (_) { /* ignore */ }

    const raw = (msg.content[0]?.text ?? "{}")
      .replace(/```(?:json)?\s*/gi, "")
      .replace(/```/g, "")
      .trim();

    try {
      const parsed = JSON.parse(raw);
      const validCats = ['delivery','cleaning','handyman','moving',
        'pet_care','tech_support','tutoring','other'];
      const validUrg  = ['flexible','today','urgent_now'];
      return {
        suggestedCategory: validCats.includes(parsed.suggestedCategory)
          ? parsed.suggestedCategory : 'other',
        suggestedUrgency: validUrg.includes(parsed.suggestedUrgency)
          ? parsed.suggestedUrgency : 'flexible',
        tags: Array.isArray(parsed.tags)
          ? parsed.tags.filter(t => typeof t === 'string').slice(0, 5)
          : [],
      };
    } catch (e) {
      // Fallback: safe defaults
      return {
        suggestedCategory: 'other',
        suggestedUrgency:  'flexible',
        tags: [],
      };
    }
  },
);

/**
 * expireOpenTasks — Daily cron that marks any `any_tasks` doc as
 * 'expired' if status is still 'open' and it was published more than
 * 30 days ago. Frees up the list from dead entries without deleting
 * data (admins can still review).
 *
 * Runs at 03:30 IST.
 */
exports.expireOpenTasks = onSchedule(
  {
    schedule: "30 3 * * *",
    timeZone: "Asia/Jerusalem",
    region:   "us-central1",
    memory:   "256MiB",
  },
  async () => {
    const db = admin.firestore();
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - 30);
    const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);

    const snap = await db.collection('any_tasks')
      .where('status', '==', 'open')
      .where('createdAt', '<', cutoffTs)
      .limit(500)
      .get();

    if (snap.empty) {
      console.log('[expireOpenTasks] no stale tasks');
      return;
    }

    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.update(doc.ref, {
        status: 'expired',
        expiredAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    console.log(`[expireOpenTasks] expired ${snap.size} tasks`);
  },
);
// Phase 3 CF additions (appended to index.js).
// See section "PHASE 3 — PROACTIVE TICKETS + SMART ROUTING".

const ROUTING_CONFIG_DEFAULTS = Object.freeze({
  enableCategoryMatch: true,
  enableLanguageMatch: true,
  enableLoadBalancing: true,
  enableVipRouting: true,
  vipTrustThreshold: 90,
  defaultMaxConcurrent: 5,
  enableProviderNoConfirm: true,
  providerNoConfirmMinutes: 30,
  enableProviderLate: true,
  providerLateMinutes: 15,
  enableProviderCancelled: true,
  enablePaymentFailed: true,
  paymentFailedMinutes: 60,
});

async function _loadRoutingConfig() {
  try {
    const snap = await admin
      .firestore()
      .doc("platform_settings/routing_config")
      .get();
    const data = snap.exists ? snap.data() : {};
    return Object.assign({}, ROUTING_CONFIG_DEFAULTS, data);
  } catch (e) {
    console.warn("[routing] config load failed, using defaults:", e.message);
    return ROUTING_CONFIG_DEFAULTS;
  }
}

async function _pickAgentForTicket(ticketId, ticketData, config) {
  const db = admin.firestore();

  let customer = {};
  const userId = ticketData.userId;
  if (userId) {
    try {
      const cSnap = await db.collection("users").doc(userId).get();
      customer = cSnap.exists ? cSnap.data() : {};
    } catch (_) {}
  }
  const customerTrust = Number(customer.trustScore || 0);
  const customerLang =
    customer.preferredLanguage || customer.language || "he";
  const vip =
    config.enableVipRouting && customerTrust >= config.vipTrustThreshold;

  let candidates = [];
  try {
    const agentsSnap = await db
      .collection("users")
      .where("role", "==", "support_agent")
      .limit(100)
      .get();
    candidates = agentsSnap.docs.map(function (d) {
      return { uid: d.id, data: d.data() || {} };
    });
  } catch (e) {
    console.warn("[routing] agents query failed:", e.message);
    return { assignedTo: null, reason: "agents_query_failed" };
  }

  if (candidates.length === 0) {
    return { assignedTo: null, reason: "no_agents" };
  }

  const loads = {};
  if (config.enableLoadBalancing) {
    try {
      const openSnap = await db
        .collection("support_tickets")
        .where("status", "in", ["open", "in_progress"])
        .limit(500)
        .get();
      for (const d of openSnap.docs) {
        const a = d.data().assignedTo;
        if (a) loads[a] = (loads[a] || 0) + 1;
      }
    } catch (_) {}
  }

  const category = (ticketData.category || "").toString().toLowerCase();
  const scored = candidates.map(function (c) {
    const profile = c.data.agentProfile || {};
    const tier = profile.tier || "agent";
    const specialties = Array.isArray(profile.specialties)
      ? profile.specialties.map(function (s) {
          return String(s).toLowerCase();
        })
      : [];
    const languages = Array.isArray(profile.languages)
      ? profile.languages.map(function (l) {
          return String(l).toLowerCase();
        })
      : [];
    const maxConcurrent = Number(
      profile.maxConcurrentTickets || config.defaultMaxConcurrent,
    );
    const openLoad = loads[c.uid] || 0;
    const isOnline = profile.isOnline === true;

    let score = 0;
    const reasons = [];

    if (vip && (tier === "senior_agent" || tier === "team_lead")) {
      score += 1000;
      reasons.push("vip");
    }
    if (
      config.enableCategoryMatch &&
      category &&
      specialties.indexOf(category) !== -1
    ) {
      score += 100;
      reasons.push("category");
    }
    if (config.enableLanguageMatch && languages.indexOf(customerLang) !== -1) {
      score += 40;
      reasons.push("language");
    }
    if (isOnline) {
      score += 25;
      reasons.push("online");
    }
    if (config.enableLoadBalancing) {
      score -= openLoad * 5;
    }
    const overCap = openLoad >= maxConcurrent;
    return {
      uid: c.uid,
      name: c.data.name || c.data.email || c.uid,
      score: score,
      overCap: overCap,
      isOnline: isOnline,
      load: openLoad,
      reasons: reasons,
    };
  });

  let pool = scored.filter(function (s) {
    return !s.overCap;
  });
  if (pool.length === 0) pool = scored;

  const online = pool.filter(function (s) {
    return s.isOnline;
  });
  if (online.length > 0) pool = online;

  pool.sort(function (a, b) {
    return b.score - a.score;
  });
  const winner = pool[0];
  if (!winner) return { assignedTo: null, reason: "no_match" };

  return {
    assignedTo: winner.uid,
    assignedToName: winner.name,
    reason: winner.reasons.join("+") || "fallback",
    score: winner.score,
  };
}

exports.onTicketCreatedAutoRoute = onDocumentCreated(
  "support_tickets/{ticketId}",
  async (event) => {
    const data = (event.data && event.data.data()) || {};
    const ticketId = event.params.ticketId;
    if (data.assignedTo) return;
    const config = await _loadRoutingConfig();
    const pick = await _pickAgentForTicket(ticketId, data, config);
    if (!pick.assignedTo) {
      console.log(
        "[routeTicket] " + ticketId + " -> unassigned (" + pick.reason + ")",
      );
      return;
    }
    try {
      await admin
        .firestore()
        .doc("support_tickets/" + ticketId)
        .update({
          assignedTo: pick.assignedTo,
          assignedToName: pick.assignedToName,
          routedAt: admin.firestore.FieldValue.serverTimestamp(),
          routingReason: pick.reason,
          routingScore: typeof pick.score === "number" ? pick.score : null,
        });
      console.log(
        "[routeTicket] " +
          ticketId +
          " -> " +
          pick.assignedTo +
          " (" +
          pick.reason +
          ")",
      );
    } catch (e) {
      console.error("[routeTicket] update failed:", e.message);
    }
  },
);

exports.routeTicket = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  const ticketId = request.data && request.data.ticketId;
  if (!ticketId || typeof ticketId !== "string") {
    throw new HttpsError("invalid-argument", "ticketId required.");
  }
  const callerSnap = await admin
    .firestore()
    .doc("users/" + request.auth.uid)
    .get();
  const c = callerSnap.data() || {};
  const roles = Array.isArray(c.roles) ? c.roles : [];
  const isStaff =
    c.isAdmin === true ||
    c.role === "admin" ||
    c.role === "support_agent" ||
    roles.indexOf("admin") !== -1 ||
    roles.indexOf("support_agent") !== -1;
  if (!isStaff) {
    throw new HttpsError("permission-denied", "Staff only.");
  }

  const ref = admin.firestore().doc("support_tickets/" + ticketId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Ticket " + ticketId + " not found.");
  }
  const config = await _loadRoutingConfig();
  const pick = await _pickAgentForTicket(ticketId, snap.data(), config);
  await ref.update({
    assignedTo: pick.assignedTo || null,
    assignedToName: pick.assignedToName || null,
    routedAt: admin.firestore.FieldValue.serverTimestamp(),
    routingReason: pick.reason,
    routingScore: typeof pick.score === "number" ? pick.score : null,
  });
  return {
    success: true,
    assignedTo: pick.assignedTo || null,
    reason: pick.reason,
  };
});

exports.proactiveSlaMonitor = onSchedule(
  {
    schedule: "every 5 minutes",
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async () => {
    const config = await _loadRoutingConfig();
    if (!config.enableProviderNoConfirm) {
      console.log("[proactive] provider-no-confirm disabled via config");
      return;
    }
    const db = admin.firestore();
    const now = Date.now();
    const windowMs = (config.providerNoConfirmMinutes || 30) * 60 * 1000;
    const cutoff = admin.firestore.Timestamp.fromMillis(now - windowMs);

    let jobs;
    try {
      jobs = await db
        .collection("jobs")
        .where("status", "==", "paid_escrow")
        .where("createdAt", "<=", cutoff)
        .limit(100)
        .get();
    } catch (e) {
      console.error("[proactive] jobs query failed:", e.message);
      return;
    }

    let created = 0;
    let skipped = 0;

    for (const d of jobs.docs) {
      const j = d.data() || {};
      if (
        j.expertOnWay === true ||
        j.workStartedAt != null ||
        j.providerFirstMessageAt != null
      ) {
        skipped++;
        continue;
      }
      const existing = await db
        .collection("support_tickets")
        .where("jobId", "==", d.id)
        .where("trigger", "==", "provider_no_confirm")
        .limit(1)
        .get();
      if (!existing.empty) {
        skipped++;
        continue;
      }

      const ticketRef = db.collection("support_tickets").doc();
      const batch = db.batch();
      batch.set(ticketRef, {
        type: "proactive",
        trigger: "provider_no_confirm",
        autoActions: ["notified_customer"],
        userId: j.customerId,
        userName: j.customerName || "",
        providerId: j.expertId,
        providerName: j.expertName || "",
        jobId: d.id,
        category: j.category || "other",
        subject:
          "נותן השירות לא אישר את ההזמנה (" +
          config.providerNoConfirmMinutes +
          " דקות)",
        status: "open",
        priority: "high",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      const msgRef = ticketRef.collection("messages").doc();
      batch.set(msgRef, {
        senderId: "system",
        senderName: "מערכת",
        isAdmin: true,
        isInternal: false,
        channel: "customer",
        message:
          "שמנו לב שנותן השירות עוד לא אישר את ההזמנה שלך. " +
          "סוכן תמיכה ייצור איתך קשר בהקדם כדי לעזור.",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      if (j.customerId) {
        const notifRef = db.collection("notifications").doc();
        batch.set(notifRef, {
          userId: j.customerId,
          type: "proactive_support",
          title: "פתחנו בירור על ההזמנה שלך",
          body:
            "נותן השירות עוד לא אישר - סוכן תמיכה מטפל בזה ויחזור אליך בקרוב.",
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      try {
        await batch.commit();
        created++;
      } catch (e) {
        console.error("[proactive] commit failed for job", d.id, e.message);
      }
    }
    console.log(
      "[proactive] provider_no_confirm scanned=" +
        jobs.size +
        " created=" +
        created +
        " skipped=" +
        skipped,
    );
  },
);

exports.onJobPaymentFailedProactive = onDocumentUpdated(
  "jobs/{jobId}",
  async (event) => {
    const before = (event.data && event.data.before && event.data.before.data()) || {};
    const after = (event.data && event.data.after && event.data.after.data()) || {};
    if (before.status === after.status) return;
    if (after.status !== "payment_failed") return;

    const config = await _loadRoutingConfig();
    if (!config.enablePaymentFailed) return;

    const db = admin.firestore();
    const jobId = event.params.jobId;

    const existing = await db
      .collection("support_tickets")
      .where("jobId", "==", jobId)
      .where("trigger", "==", "payment_failed")
      .limit(1)
      .get();
    if (!existing.empty) return;

    await db.collection("support_tickets").add({
      type: "proactive",
      trigger: "payment_failed",
      autoActions: ["notified_customer"],
      userId: after.customerId,
      userName: after.customerName || "",
      providerId: after.expertId,
      providerName: after.expertName || "",
      jobId: jobId,
      category: after.category || "payments",
      subject: "תשלום נכשל - נדרש מעקב",
      status: "open",
      priority: "urgent",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log("[proactive] payment_failed ticket created for job " + jobId);
  },
);
// Phase 4 — SLA Escalation + KPI aggregation (appended to index.js).

const ESCALATION_DEFAULTS = Object.freeze({
  enableStage1: true,
  stage1Minutes: 3,
  enableStage2: true,
  stage2Minutes: 7,
  enableStage3: true,
  stage3Minutes: 15,
});

async function _loadEscalationConfig() {
  try {
    const snap = await admin
      .firestore()
      .doc("platform_settings/escalation_config")
      .get();
    const data = snap.exists ? snap.data() : {};
    return Object.assign({}, ESCALATION_DEFAULTS, data);
  } catch (e) {
    console.warn("[escalation] config load failed:", e.message);
    return ESCALATION_DEFAULTS;
  }
}

// ── checkSLA ────────────────────────────────────────────────────────────────
// Runs every minute. Finds open/in_progress tickets past each escalation
// threshold that haven't received an agent reply, and advances them through
// the 3-stage pipeline:
//   stage 1 (3 min)  -> notify assigned agent
//   stage 2 (7 min)  -> reassign to a senior agent
//   stage 3 (15 min) -> notify admin + mark slaFailed
//
// Idempotent via `slaStage` on the ticket doc — each stage only fires once.
exports.checkSLA = onSchedule(
  {
    schedule: "every 1 minutes",
    timeoutSeconds: 300,
    memory: "256MiB",
  },
  async () => {
    const config = await _loadEscalationConfig();
    const db = admin.firestore();
    const now = Date.now();

    // Tickets that could potentially need escalation.
    let snap;
    try {
      snap = await db
        .collection("support_tickets")
        .where("status", "in", ["open", "in_progress"])
        .limit(500)
        .get();
    } catch (e) {
      console.error("[checkSLA] query failed:", e.message);
      return;
    }

    let s1 = 0;
    let s2 = 0;
    let s3 = 0;

    for (const doc of snap.docs) {
      const t = doc.data() || {};
      // SLA clock: agent hasn't replied since ticket opened.
      if (t.lastAgentMessageAt) continue;
      const created = t.createdAt;
      if (!created || typeof created.toMillis !== "function") continue;
      const ageMin = (now - created.toMillis()) / 60000;

      const currentStage = Number(t.slaStage || 0);

      // Stage 3 — alert admin and mark SLA failed
      if (
        config.enableStage3 &&
        ageMin >= config.stage3Minutes &&
        currentStage < 3
      ) {
        try {
          await doc.ref.update({
            slaStage: 3,
            slaFailed: true,
            priority: "urgent",
            escalatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          // Notify all admins.
          const admins = await db
            .collection("users")
            .where("isAdmin", "==", true)
            .limit(20)
            .get();
          const batch = db.batch();
          for (const a of admins.docs) {
            const nref = db.collection("notifications").doc();
            batch.set(nref, {
              userId: a.id,
              type: "sla_breach_critical",
              title: "🚨 SLA הופר",
              body:
                "פנייה " +
                doc.id +
                " ללא מענה מעל " +
                config.stage3Minutes +
                " דקות",
              ticketId: doc.id,
              isRead: false,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
          try {
            await batch.commit();
          } catch (_) {}
          s3++;
        } catch (e) {
          console.warn("[checkSLA] stage3 failed for", doc.id, e.message);
        }
        continue; // already at top stage
      }

      // Stage 2 — reassign to a senior agent
      if (
        config.enableStage2 &&
        ageMin >= config.stage2Minutes &&
        currentStage < 2
      ) {
        try {
          // Find an online senior/team_lead with spare capacity.
          const seniorsSnap = await db
            .collection("users")
            .where("role", "==", "support_agent")
            .limit(100)
            .get();
          const seniors = [];
          for (const a of seniorsSnap.docs) {
            const d = a.data() || {};
            const tier = (d.agentProfile && d.agentProfile.tier) || "agent";
            if (tier === "senior_agent" || tier === "team_lead") {
              seniors.push({ uid: a.id, data: d });
            }
          }
          let newAssignee = null;
          if (seniors.length > 0) {
            // Pick online first.
            const online = seniors.filter(
              (s) => s.data.agentProfile && s.data.agentProfile.isOnline === true,
            );
            newAssignee = online[0] || seniors[0];
          }

          const updates = {
            slaStage: 2,
            priority: "high",
            escalatedAt: admin.firestore.FieldValue.serverTimestamp(),
          };
          if (newAssignee) {
            updates.assignedTo = newAssignee.uid;
            updates.assignedToName =
              newAssignee.data.name ||
              newAssignee.data.email ||
              newAssignee.uid;
            updates.routingReason = "sla_escalation";

            // Notify the new assignee.
            await db.collection("notifications").add({
              userId: newAssignee.uid,
              type: "sla_escalated_to_you",
              title: "🔥 פנייה הוקצתה לך (הסלמת SLA)",
              body: "פנייה " + doc.id + " — " + (t.subject || ""),
              ticketId: doc.id,
              isRead: false,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
          await doc.ref.update(updates);
          s2++;
        } catch (e) {
          console.warn("[checkSLA] stage2 failed for", doc.id, e.message);
        }
        continue;
      }

      // Stage 1 — alert the currently assigned agent
      if (
        config.enableStage1 &&
        ageMin >= config.stage1Minutes &&
        currentStage < 1
      ) {
        try {
          await doc.ref.update({
            slaStage: 1,
            priority: "high",
          });
          if (t.assignedTo) {
            await db.collection("notifications").add({
              userId: t.assignedTo,
              type: "sla_alert_agent",
              title: "⏰ תזכורת SLA",
              body:
                "פנייה " +
                doc.id +
                " ממתינה " +
                Math.round(ageMin) +
                " דקות — ענה בהקדם",
              ticketId: doc.id,
              isRead: false,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
          s1++;
        } catch (e) {
          console.warn("[checkSLA] stage1 failed for", doc.id, e.message);
        }
      }
    }

    if (s1 + s2 + s3 > 0) {
      console.log(
        "[checkSLA] stage1=" + s1 + " stage2=" + s2 + " stage3=" + s3,
      );
    }
  },
);

// ── aggregateKPI ────────────────────────────────────────────────────────────
// Runs daily at 00:05 UTC. Scans yesterday's ticket activity and writes a
// per-agent rollup to agent_kpi/{YYYY-MM-DD}_{agentUid} with:
//   ticketsClosed, avgResponseSeconds, csatAvg, firstContactResolution,
//   botHandoffs.
//
// Also writes an aggregate team doc at agent_kpi/{YYYY-MM-DD}_team.
exports.aggregateKPI = onSchedule(
  {
    schedule: "5 0 * * *", // 00:05 every day
    timeZone: "Asia/Jerusalem",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const db = admin.firestore();

    // Compute yesterday in local (Jerusalem) calendar terms — store as YYYY-MM-DD
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const dateKey =
      yesterday.getUTCFullYear() +
      "-" +
      String(yesterday.getUTCMonth() + 1).padStart(2, "0") +
      "-" +
      String(yesterday.getUTCDate()).padStart(2, "0");

    const start = new Date(yesterday);
    start.setUTCHours(0, 0, 0, 0);
    const end = new Date(yesterday);
    end.setUTCHours(23, 59, 59, 999);
    const startTs = admin.firestore.Timestamp.fromDate(start);
    const endTs = admin.firestore.Timestamp.fromDate(end);

    // Closed tickets in the window.
    let closedSnap;
    try {
      closedSnap = await db
        .collection("support_tickets")
        .where("closedAt", ">=", startTs)
        .where("closedAt", "<=", endTs)
        .limit(1000)
        .get();
    } catch (e) {
      console.error("[aggregateKPI] closedAt query failed:", e.message);
      return;
    }

    const perAgent = {}; // agentUid -> {closed, csatSum, csatCount, respSum, respCount, botHandoffs, reassigned}

    for (const d of closedSnap.docs) {
      const t = d.data() || {};
      const agent = t.closedBy || t.assignedTo;
      if (!agent) continue;
      const bucket = perAgent[agent] || {
        ticketsClosed: 0,
        csatSum: 0,
        csatCount: 0,
        respSum: 0,
        respCount: 0,
        botHandoffs: 0,
        reassigned: 0,
      };
      bucket.ticketsClosed++;
      const csat = Number(t.csatRating || 0);
      if (csat > 0) {
        bucket.csatSum += csat;
        bucket.csatCount++;
      }
      // Response time: createdAt -> lastAgentMessageAt (approx).
      const created = t.createdAt;
      const firstReply = t.lastAgentMessageAt;
      if (created && firstReply) {
        const sec =
          (firstReply.toMillis() - created.toMillis()) / 1000;
        if (sec > 0 && sec < 3600 * 48) {
          bucket.respSum += sec;
          bucket.respCount++;
        }
      }
      if (t.type === "bot_escalation") bucket.botHandoffs++;
      if ((t.slaStage || 0) >= 2) bucket.reassigned++;
      perAgent[agent] = bucket;
    }

    const batch = db.batch();
    let teamClosed = 0;
    let teamCsatSum = 0;
    let teamCsatCount = 0;
    let teamRespSum = 0;
    let teamRespCount = 0;
    let teamBot = 0;
    let teamReassigned = 0;

    for (const agentUid of Object.keys(perAgent)) {
      const b = perAgent[agentUid];
      const avgResp = b.respCount > 0 ? b.respSum / b.respCount : null;
      const csatAvg = b.csatCount > 0 ? b.csatSum / b.csatCount : null;
      const fcr =
        b.ticketsClosed > 0
          ? (b.ticketsClosed - b.reassigned) / b.ticketsClosed
          : null;
      const ref = db.doc("agent_kpi/" + dateKey + "_" + agentUid);
      batch.set(ref, {
        agentUid,
        date: dateKey,
        ticketsClosed: b.ticketsClosed,
        avgResponseSeconds: avgResp,
        csatAvg,
        csatSampleSize: b.csatCount,
        firstContactResolution: fcr,
        botHandoffs: b.botHandoffs,
        reassigned: b.reassigned,
        computedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      teamClosed += b.ticketsClosed;
      teamCsatSum += b.csatSum;
      teamCsatCount += b.csatCount;
      teamRespSum += b.respSum;
      teamRespCount += b.respCount;
      teamBot += b.botHandoffs;
      teamReassigned += b.reassigned;
    }

    const teamRef = db.doc("agent_kpi/" + dateKey + "_team");
    batch.set(teamRef, {
      date: dateKey,
      team: true,
      ticketsClosed: teamClosed,
      avgResponseSeconds:
        teamRespCount > 0 ? teamRespSum / teamRespCount : null,
      csatAvg: teamCsatCount > 0 ? teamCsatSum / teamCsatCount : null,
      csatSampleSize: teamCsatCount,
      firstContactResolution:
        teamClosed > 0 ? (teamClosed - teamReassigned) / teamClosed : null,
      botHandoffs: teamBot,
      reassigned: teamReassigned,
      computedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    try {
      await batch.commit();
    } catch (e) {
      console.error("[aggregateKPI] commit failed:", e.message);
      return;
    }
    console.log(
      "[aggregateKPI] " +
        dateKey +
        " agents=" +
        Object.keys(perAgent).length +
        " closed=" +
        teamClosed,
    );
  },
);
// Phase 5 — Self-Service Bot + Trust Score (appended to index.js).

// ── handleBotConversation ───────────────────────────────────────────────────
// Customer-facing bot. The Flutter support entry-point calls this CF with
// the conversation history. The bot decides whether to:
//   • answer directly (auto-resolve)
//   • ask a clarifying question
//   • escalate to a human agent (returns escalate=true + opens a real ticket)
//
// Uses Gemini 2.5 Flash Lite per spec (NOT Anthropic).
// Body:
//   { conversation: [{role:'user'|'bot', text:'...'}, ...],
//     userId, language? }
// Returns:
//   { reply: string, suggestions?: [string],
//     escalate: bool, ticketId?: string, autoResolved?: bool }
exports.handleBotConversation = onCall(
  {
    secrets: [GEMINI_API_KEY],
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    const callerUid = request.auth.uid;
    const data = request.data || {};
    const conversation = Array.isArray(data.conversation)
      ? data.conversation
      : [];
    const language = (data.language || "he").toString();
    const targetUserId = data.userId || callerUid;

    const geminiKey =
      GEMINI_API_KEY.value() || process.env.GEMINI_API_KEY || "";
    if (!geminiKey) {
      // Hard fallback: just escalate when AI is unavailable.
      return {
        reply:
          language === "he"
            ? "אני מעביר אותך לסוכן אנושי שיענה במהירות."
            : "I'm connecting you to a human agent.",
        escalate: true,
      };
    }

    // System prompt — keep tight to control tokens. Hebrew-first.
    const systemPrompt =
      language === "he"
        ? "אתה בוט תמיכה של AnySkill — שוק שירותים בישראל. תפקידך לעזור ללקוחות לפתור בעיות פשוטות ולהעביר לסוכן אנושי כל בעיה מורכבת. " +
          "הצג תשובות קצרות וברורות בעברית. אם השאלה דורשת גישה לחשבון/כסף/בעיה עם נותן שירות — החזר escalate=true. " +
          "החזר אך ורק JSON תקין במבנה: " +
          '{"reply": "...", "suggestions": ["...", "..."], "escalate": true|false, "autoResolved": true|false, "intent": "order_status|password|cancel|provider_no_show|payment|other"}'
        : "You are a support bot for AnySkill — an Israeli services marketplace. Help customers solve simple issues, escalate complex ones (account, money, provider problems) to a human. " +
          "Reply in English. Return JSON only: " +
          '{"reply": "...", "suggestions": ["...", "..."], "escalate": true|false, "autoResolved": true|false, "intent": "order_status|password|cancel|provider_no_show|payment|other"}';

    // Build Gemini contents from conversation history.
    const contents = conversation.map(function (m) {
      return {
        role: m.role === "bot" ? "model" : "user",
        parts: [{ text: String(m.text || "") }],
      };
    });

    let result;
    try {
      const url =
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=" +
        geminiKey;
      const resp = await fetch(url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: systemPrompt }] },
          contents: contents,
          generationConfig: {
            temperature: 0.4,
            maxOutputTokens: 600,
            responseMimeType: "application/json",
          },
        }),
      });
      if (!resp.ok) {
        throw new Error("Gemini HTTP " + resp.status);
      }
      const json = await resp.json();
      const text =
        (json.candidates &&
          json.candidates[0] &&
          json.candidates[0].content &&
          json.candidates[0].content.parts &&
          json.candidates[0].content.parts[0] &&
          json.candidates[0].content.parts[0].text) ||
        "";
      result = JSON.parse(text);
    } catch (e) {
      console.warn("[bot] Gemini failed:", e.message, "— escalating");
      result = {
        reply:
          language === "he"
            ? "אני מעביר אותך לסוכן אנושי שיענה במהירות."
            : "I'm connecting you to a human agent.",
        escalate: true,
      };
    }

    // If escalating, create a real support ticket so an agent picks it up.
    let ticketId;
    if (result.escalate === true) {
      try {
        const userSnap = await admin
          .firestore()
          .collection("users")
          .doc(targetUserId)
          .get();
        const u = userSnap.data() || {};
        const intent = result.intent || "other";

        // Reconstruct a synopsis of the bot conversation as the first message.
        const synopsis = conversation
          .map(function (m) {
            return (
              (m.role === "user" ? "Customer" : "Bot") + ": " + (m.text || "")
            );
          })
          .join("\n");

        const ticketRef = await admin.firestore()
          .collection("support_tickets")
          .add({
            type: "bot_escalation",
            trigger: "bot_handoff",
            botIntent: intent,
            botSteps: conversation.length,
            userId: targetUserId,
            userName: u.name || u.email || "",
            category: intent,
            subject:
              language === "he"
                ? "פנייה מהבוט: " + intent
                : "From bot: " + intent,
            status: "open",
            priority: "normal",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        ticketId = ticketRef.id;

        // Seed first internal note so the assigned agent sees the bot trail.
        await admin.firestore()
          .collection("support_tickets")
          .doc(ticketId)
          .collection("messages")
          .add({
            senderId: "bot",
            senderName: "Bot",
            isAdmin: true,
            isInternal: true,
            channel: "internal",
            message: "🤖 שיחה עם הבוט:\n\n" + synopsis,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
      } catch (e) {
        console.error("[bot] ticket creation failed:", e.message);
      }
    }

    // Best-effort daily analytics roll-up.
    try {
      const today = new Date();
      const dateKey =
        today.getUTCFullYear() +
        "-" +
        String(today.getUTCMonth() + 1).padStart(2, "0") +
        "-" +
        String(today.getUTCDate()).padStart(2, "0");
      const ref = admin.firestore().doc("bot_analytics/" + dateKey);
      const incs = {
        date: dateKey,
        sessions: admin.firestore.FieldValue.increment(1),
      };
      if (result.escalate === true) {
        incs.handoffs = admin.firestore.FieldValue.increment(1);
      } else if (result.autoResolved === true) {
        incs.autoResolved = admin.firestore.FieldValue.increment(1);
      }
      await ref.set(incs, { merge: true });
    } catch (_) {}

    return {
      reply: result.reply || "",
      suggestions: Array.isArray(result.suggestions) ? result.suggestions : [],
      escalate: result.escalate === true,
      autoResolved: result.autoResolved === true,
      intent: result.intent || "other",
      ticketId: ticketId,
    };
  },
);

// ── recalculateTrustScore ───────────────────────────────────────────────────
// Recomputes a user's trust score 0-100 based on the spec weights:
//   account age (10%), completed orders (20%), avg rating (25%),
//   cancellation rate (15%), support complaints (15%),
//   identity verified (10%), no failed payments (5%).
//
// Callable from the client (admin only) or invoked internally by the
// trigger CFs below. Writes users/{uid}.trustScore + .trustScoreUpdatedAt.
async function _computeTrustScore(uid) {
  const db = admin.firestore();
  const uSnap = await db.collection("users").doc(uid).get();
  if (!uSnap.exists) return null;
  const u = uSnap.data() || {};

  // Account age — months since createdAt (or fallback to 12 months).
  const createdAt = u.createdAt;
  const months =
    createdAt && typeof createdAt.toMillis === "function"
      ? Math.max(
          0,
          (Date.now() - createdAt.toMillis()) / (1000 * 60 * 60 * 24 * 30),
        )
      : 12;
  const ageScore = Math.min(months, 12); // up to +12

  // Completed orders — orderCount or fallback 0.
  const orders = Number(u.orderCount || 0);
  const ordersScore = Math.min(orders * 0.5, 20); // up to +20

  // Avg rating — 0..5 → 0..25.
  const rating = Number(u.rating || 0);
  const ratingScore = Math.min(rating * 5, 25); // 5 stars * 5 = 25

  // Cancellation count.
  let cancellations = Number(u.cancellationCount || 0);
  if (cancellations === 0) {
    try {
      const csnap = await db
        .collection("jobs")
        .where("expertId", "==", uid)
        .where("cancelledBy", "==", "expert")
        .limit(50)
        .get();
      cancellations = csnap.size;
    } catch (_) {}
  }
  const cancelPenalty = Math.min(cancellations * 2, 15); // capped

  // Support complaints — open tickets where this uid is providerId,
  // marked as a complaint via priority=urgent.
  let complaints = 0;
  try {
    const tsnap = await db
      .collection("support_tickets")
      .where("providerId", "==", uid)
      .where("priority", "==", "urgent")
      .limit(50)
      .get();
    complaints = tsnap.size;
  } catch (_) {}
  const complaintsPenalty = Math.min(complaints * 5, 15); // capped

  // Identity verified.
  const verifiedBonus = u.isVerified === true ? 10 : 0;

  // Payment history — no failed payments bonus.
  const paymentBonus = u.hasFailedPayments === true ? 0 : 5;

  // Sum and clamp.
  const score = Math.max(
    0,
    Math.min(
      100,
      Math.round(
        ageScore +
          ordersScore +
          ratingScore -
          cancelPenalty -
          complaintsPenalty +
          verifiedBonus +
          paymentBonus,
      ),
    ),
  );

  await db.collection("users").doc(uid).update({
    trustScore: score,
    trustScoreUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return score;
}

exports.recalculateTrustScore = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  if (!(await isAdminCaller(request))) {
    throw new HttpsError("permission-denied", "Admin only.");
  }
  const targetUserId = request.data && request.data.targetUserId;
  if (!targetUserId || typeof targetUserId !== "string") {
    throw new HttpsError("invalid-argument", "targetUserId required.");
  }
  const score = await _computeTrustScore(targetUserId);
  return { success: true, trustScore: score };
});

// Triggers — recompute on activity that changes the score.
exports.onJobCompletedTrust = onDocumentUpdated(
  "jobs/{jobId}",
  async (event) => {
    const before = (event.data && event.data.before && event.data.before.data()) || {};
    const after = (event.data && event.data.after && event.data.after.data()) || {};
    if (before.status === after.status) return;
    if (after.status !== "completed") return;
    // Recompute for both customer and provider.
    if (after.customerId) {
      try {
        await _computeTrustScore(after.customerId);
      } catch (_) {}
    }
    if (after.expertId) {
      try {
        await _computeTrustScore(after.expertId);
      } catch (_) {}
    }
  },
);

exports.onReviewSubmittedTrust = onDocumentCreated(
  "reviews/{reviewId}",
  async (event) => {
    const r = (event.data && event.data.data()) || {};
    const target = r.revieweeId;
    if (!target) return;
    try {
      await _computeTrustScore(target);
    } catch (_) {}
  },
);

exports.onTicketResolvedTrust = onDocumentUpdated(
  "support_tickets/{ticketId}",
  async (event) => {
    const before = (event.data && event.data.before && event.data.before.data()) || {};
    const after = (event.data && event.data.after && event.data.after.data()) || {};
    if (before.status === after.status) return;
    if (after.status !== "resolved" && after.status !== "closed") return;
    // Recompute for the customer, and the provider if attached.
    if (after.userId) {
      try {
        await _computeTrustScore(after.userId);
      } catch (_) {}
    }
    if (after.providerId) {
      try {
        await _computeTrustScore(after.providerId);
      } catch (_) {}
    }
  },
);


// ==========================================================================
// VAULT DASHBOARD - Cloud Functions (v14.x)
// ==========================================================================

// -- Vault period helpers --------------------------------------------------
function _vaultPeriodStart(period, now) {
  switch (period) {
    case "day":
      return new Date(now.getFullYear(), now.getMonth(), now.getDate());
    case "week": {
      const day = now.getDay();
      return new Date(now.getFullYear(), now.getMonth(), now.getDate() - day);
    }
    case "month":
      return new Date(now.getFullYear(), now.getMonth(), 1);
    case "year":
      return new Date(now.getFullYear(), 0, 1);
    default:
      return new Date(now.getFullYear(), now.getMonth(), now.getDate());
  }
}

function _vaultPrevPeriodStart(period, now) {
  switch (period) {
    case "day":
      return new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
    case "week": {
      const day = now.getDay();
      return new Date(now.getFullYear(), now.getMonth(), now.getDate() - day - 7);
    }
    case "month":
      return new Date(now.getFullYear(), now.getMonth() - 1, 1);
    case "year":
      return new Date(now.getFullYear() - 1, 0, 1);
    default:
      return new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
  }
}

// -- updateVaultAnalytics - hourly aggregation -----------------------------
exports.updateVaultAnalytics = onSchedule(
  { schedule: "every 1 hours", timeZone: "Asia/Jerusalem" },
  async () => {
    const db = admin.firestore();
    const periods = ["day", "week", "month", "year"];
    const now = new Date();

    for (const period of periods) {
      try {
        const start = _vaultPeriodStart(period, now);
        const prevStart = _vaultPrevPeriodStart(period, now);

        const earningsSnap = await db
          .collection("platform_earnings")
          .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(start))
          .limit(500)
          .get();

        const prevEarningsSnap = await db
          .collection("platform_earnings")
          .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(prevStart))
          .where("timestamp", "<", admin.firestore.Timestamp.fromDate(start))
          .limit(500)
          .get();

        const revenue = earningsSnap.docs.reduce(
          (s, d) => s + (Number(d.data().amount) || 0), 0
        );
        const prevRevenue = prevEarningsSnap.docs.reduce(
          (s, d) => s + (Number(d.data().amount) || 0), 0
        );
        const txCount = earningsSnap.docs.length;
        const prevTxCount = prevEarningsSnap.docs.length;
        const avgCommission = txCount > 0 ? revenue / txCount : 0;

        const completedSnap = await db
          .collection("jobs")
          .where("status", "==", "completed")
          .where("completedAt", ">=", admin.firestore.Timestamp.fromDate(start))
          .limit(500)
          .get();

        const providerIds = new Set();
        earningsSnap.docs.forEach((d) => {
          if (d.data().sourceExpertId) providerIds.add(d.data().sourceExpertId);
        });

        const revByCategory = {};
        earningsSnap.docs.forEach((d) => {
          const cat = d.data().category || d.data().serviceType || "other";
          revByCategory[cat] = (revByCategory[cat] || 0) + (Number(d.data().amount) || 0);
        });

        const dailyRevenue = {};
        earningsSnap.docs.forEach((d) => {
          const ts = d.data().timestamp;
          if (!ts) return;
          const dt = ts.toDate();
          const key = dt.getFullYear() + "-" + String(dt.getMonth() + 1).padStart(2, "0") + "-" + String(dt.getDate()).padStart(2, "0");
          if (!dailyRevenue[key]) dailyRevenue[key] = { date: key, revenue: 0, transactions: 0 };
          dailyRevenue[key].revenue += Number(d.data().amount) || 0;
          dailyRevenue[key].transactions += 1;
        });

        const hourlyActivity = new Array(24).fill(0);
        earningsSnap.docs.forEach((d) => {
          const ts = d.data().timestamp;
          if (ts) hourlyActivity[ts.toDate().getHours()]++;
        });

        const cancelledSnap = await db
          .collection("jobs")
          .where("status", "in", ["cancelled", "cancelled_with_penalty"])
          .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(start))
          .limit(200)
          .get();

        const totalJobs = completedSnap.docs.length + cancelledSnap.docs.length;
        const completionRate = totalJobs > 0 ? completedSnap.docs.length / totalJobs * 100 : 100;
        const revenueGrowth = prevRevenue > 0 ? ((revenue - prevRevenue) / prevRevenue * 100) : (revenue > 0 ? 100 : 0);

        const growthScore = Math.min(100, Math.max(0, (revenueGrowth + 100) / 3));
        const retentionScore = Math.min(100, Math.max(0, completionRate));
        const diversityScore = Math.min(100, providerIds.size / 50 * 100);
        const healthTotal = growthScore * 0.3 + retentionScore * 0.3 + 80 * 0.2 + diversityScore * 0.2;

        const dailyArr = Object.values(dailyRevenue).sort((a, b) => a.date.localeCompare(b.date));
        let forecastLow = 0, forecastHigh = 0, confidence = 0;
        if (dailyArr.length >= 3) {
          const vals = dailyArr.map((d) => d.revenue);
          const avgDaily = vals.reduce((s, v) => s + v, 0) / vals.length;
          const daysRemaining = period === "month" ? 30 - dailyArr.length : 7;
          forecastLow = Math.round((revenue + avgDaily * daysRemaining) * 0.85);
          forecastHigh = Math.round((revenue + avgDaily * daysRemaining) * 1.15);
          confidence = Math.min(90, Math.round(dailyArr.length / 14 * 100));
        }

        await db.collection("vault_analytics").doc(period).set({
          period,
          revenue: roundNIS(revenue),
          transaction_count: txCount,
          avg_commission: roundNIS(avgCommission),
          active_providers: providerIds.size,
          completed_jobs: completedSnap.docs.length,
          cancelled_jobs: cancelledSnap.docs.length,
          revenue_change_percent: roundNIS(revenueGrowth),
          previous_period: {
            revenue: roundNIS(prevRevenue),
            transaction_count: prevTxCount,
          },
          revenue_by_category: revByCategory,
          daily_revenue: Object.values(dailyRevenue),
          hourly_activity: hourlyActivity,
          health_score: {
            total: Math.round(healthTotal),
            growth: Math.round(growthScore),
            retention: Math.round(retentionScore),
            settlement: 80,
            diversity: Math.round(diversityScore),
          },
          forecast: {
            monthly_low: forecastLow,
            monthly_high: forecastHigh,
            confidence_percent: confidence,
          },
          last_updated: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log("Vault analytics updated: " + period);
      } catch (err) {
        console.error("Vault analytics error (" + period + "):", err);
      }
    }
  }
);

// -- generateVaultAlerts - hourly smart alerts -----------------------------
exports.generateVaultAlerts = onSchedule(
  { schedule: "every 1 hours", timeZone: "Asia/Jerusalem" },
  async () => {
    const db = admin.firestore();
    try {
      const alerts = [];

      const cutoff48h = new Date(Date.now() - 48 * 60 * 60 * 1000);
      const stuckSnap = await db
        .collection("jobs")
        .where("status", "==", "paid_escrow")
        .where("createdAt", "<", admin.firestore.Timestamp.fromDate(cutoff48h))
        .limit(10)
        .get();

      for (const doc of stuckSnap.docs) {
        const existing = await db
          .collection("vault_alerts")
          .where("related_id", "==", doc.id)
          .where("type", "==", "warning")
          .limit(1)
          .get();
        if (existing.empty) {
          alerts.push({
            type: "warning",
            severity: "warning",
            title: "עסקה תקועה",
            message: "הזמנה " + doc.id.substring(0, 8) + " באסקרו יותר מ-48 שעות",
            related_id: doc.id,
          });
        }
      }

      const monthDoc = await db.collection("vault_analytics").doc("month").get();
      if (monthDoc.exists) {
        const rev = monthDoc.data().revenue || 0;
        for (const m of [100, 500, 1000, 5000, 10000]) {
          if (rev >= m) {
            const mTitle = "אבן דרך: ₪" + m;
            const existing = await db
              .collection("vault_alerts")
              .where("type", "==", "achievement")
              .where("title", "==", mTitle)
              .limit(1)
              .get();
            if (existing.empty) {
              alerts.push({
                type: "achievement",
                severity: "info",
                title: mTitle,
                message: "הכנסות החודש עברו את ₪" + m + "!",
              });
            }
          }
        }

        const monthData = monthDoc.data();
        const completed = monthData.completed_jobs || 0;
        const cancelled = monthData.cancelled_jobs || 0;
        if (completed + cancelled > 5 && cancelled / (completed + cancelled) > 0.2) {
          alerts.push({
            type: "risk",
            severity: "critical",
            title: "שיעור ביטולים גבוה",
            message: Math.round(cancelled / (completed + cancelled) * 100) + "% ביטולים החודש",
          });
        }
      }

      if (alerts.length > 0) {
        const batch = db.batch();
        for (const alert of alerts) {
          const ref = db.collection("vault_alerts").doc();
          batch.set(ref, {
            ...alert,
            created_at: admin.firestore.FieldValue.serverTimestamp(),
            read: false,
          });
        }
        await batch.commit();
        console.log("Generated " + alerts.length + " vault alerts");

        // H4 audit fix: push FCM to all admins on risk/warning alerts
        const critical = alerts.filter(
          (a) => a.severity === "critical" || a.severity === "warning"
        );
        if (critical.length > 0) {
          try {
            const adminsSnap = await db
              .collection("users")
              .where("isAdmin", "==", true)
              .limit(10)
              .get();
            for (const adminDoc of adminsSnap.docs) {
              const token = adminDoc.data().fcmToken;
              if (!token) continue;
              try {
                await admin.messaging().send({
                  token,
                  notification: {
                    title: "🔐 Vault Alert",
                    body: critical.map((a) => a.title).join(", "),
                  },
                  data: { type: "vault_alert", count: String(critical.length) },
                  android: { priority: "high" },
                  apns: { payload: { aps: { sound: "default" } } },
                });
              } catch (_) { /* token may be stale */ }
            }
          } catch (fcmErr) {
            console.error("Vault FCM push error:", fcmErr);
          }
        }
      }
    } catch (err) {
      console.error("Vault alerts error:", err);
    }
  }
);

// -- updateVaultBalance - trigger on transaction writes --------------------
exports.updateVaultBalance = onDocumentWritten(
  "transactions/{transactionId}",
  async () => {
    const db = admin.firestore();
    try {
      const settingsDoc = await db
        .collection("admin").doc("admin")
        .collection("settings").doc("settings")
        .get();

      const totalPlatformBalance = settingsDoc.exists
        ? (Number(settingsDoc.data().totalPlatformBalance) || 0)
        : 0;

      const pendingSnap = await db
        .collection("jobs")
        .where("status", "==", "paid_escrow")
        .limit(200)
        .get();
      const pendingAmount = pendingSnap.docs.reduce(
        (s, d) => s + (Number(d.data().commission) || 0), 0
      );

      const withdrawnSnap = await db
        .collection("withdrawals")
        .where("status", "==", "completed")
        .limit(500)
        .get();
      const totalWithdrawn = withdrawnSnap.docs.reduce(
        (s, d) => s + (Number(d.data().amount) || 0), 0
      );

      await db.collection("vault_balance").doc("main").set({
        available_balance: roundNIS(totalPlatformBalance - totalWithdrawn),
        pending_balance: roundNIS(pendingAmount),
        total_withdrawn: roundNIS(totalWithdrawn),
        total_platform_balance: roundNIS(totalPlatformBalance),
        last_updated: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (err) {
      console.error("Vault balance update error:", err);
    }
  }
);

// ═══════════════════════════════════════════════════════════════════════════
// MONETIZATION v15.x — Layered commission (custom > category > global)
// ═══════════════════════════════════════════════════════════════════════════
// Single source of truth for "what commission should we charge on this
// job". Used by:
//   • getEffectiveCommission  (callable) — UI preview + simulator.
//   • processPaymentRelease   (internal) — authoritative fee at payout.
//   • EscrowService.payQuote  (internal) — authoritative fee at booking.
//
// Return shape: { percentage: 0-100 scale, source: 'custom'|'category'|'global', metadata }
//
// NOTE: `feePercentage` in `admin/admin/settings/settings` is stored as a
// 0-1 fraction (0.10 = 10%). All other tables use the 0-100 UI scale.
// This helper always returns 0-100.

async function _getEffectiveCommission(userId, categoryId) {
  const db = admin.firestore();

  // Layer 3 — user-level override
  if (userId) {
    try {
      const userSnap = await db.collection("users").doc(userId).get();
      if (userSnap.exists) {
        const custom = userSnap.data().customCommission;
        const active = userSnap.data().customCommissionActive === true;
        if (active && custom && typeof custom.percentage === "number") {
          const expiresAt = custom.expiresAt;
          const alive = !expiresAt
            || (expiresAt.toMillis ? expiresAt.toMillis() > Date.now() : true);
          if (alive) {
            return {
              percentage: Number(custom.percentage),
              source: "custom",
              setAt: custom.setAt || null,
              reason: custom.reason || null,
            };
          }
        }
      }
    } catch (err) {
      console.error("[getEffectiveCommission] user read failed:", err.message);
      // Fall through to category / global — never hard-fail a payment path.
    }
  }

  // Layer 2 — category-level override
  if (categoryId) {
    try {
      const catSnap = await db
        .collection("category_commissions").doc(categoryId).get();
      if (catSnap.exists && typeof catSnap.data().percentage === "number") {
        return {
          percentage: Number(catSnap.data().percentage),
          source: "category",
          categoryId,
        };
      }
    } catch (err) {
      console.error("[getEffectiveCommission] category read failed:", err.message);
    }
  }

  // Layer 1 — global default (stored as fraction — convert to percent)
  try {
    const settingsSnap = await db
      .collection("admin").doc("admin")
      .collection("settings").doc("settings").get();
    const fraction = Number(settingsSnap.data()?.feePercentage ?? 0.10);
    return { percentage: fraction * 100, source: "global" };
  } catch (_) {
    return { percentage: 10, source: "global" };
  }
}

// Exposed for tests + in case another module loads this file directly.
exports._getEffectiveCommissionInternal = _getEffectiveCommission;

exports.getEffectiveCommission = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  const { userId, categoryId } = request.data || {};
  if (!userId || typeof userId !== "string") {
    throw new HttpsError("invalid-argument", "userId is required.");
  }
  // Only admins may preview another user's effective commission; a
  // non-admin may query their own.
  if (userId !== request.auth.uid) {
    const callerSnap = await admin.firestore()
      .collection("users").doc(request.auth.uid).get();
    if (!callerSnap.exists || callerSnap.data().isAdmin !== true) {
      throw new HttpsError("permission-denied",
        "You may only query your own effective commission.");
    }
  }
  return _getEffectiveCommission(userId, categoryId || null);
});

// ═══════════════════════════════════════════════════════════════════════════
// MONETIZATION v15.x — detectMonetizationAnomalies (hourly)
// ═══════════════════════════════════════════════════════════════════════════
// Scans the last 28 days of `platform_earnings` + the `users` collection and
// writes fresh alerts into `monetization_alerts/{alertId}`.
//
// Three signal types:
//   • anomaly          — provider GMV in last 7 days ≤ 70% of avg(prior 3 weeks)
//   • churn_risk       — VIP inactive 10+ days  /  regular provider inactive 14+
//   • growth_opportunity — category last 7d ≥ 120% of avg(prior 3 weeks)
//
// Idempotent: skips entities that already have an OPEN alert of the same
// type + entityId (open == resolved != true, detected in last 24 h).

exports.detectMonetizationAnomalies = onSchedule(
  { schedule: "every 60 minutes", region: "us-central1", timeoutSeconds: 300 },
  async () => {
    const db = admin.firestore();
    const now = new Date();
    const d28 = new Date(now.getTime() - 28 * 24 * 60 * 60 * 1000);
    const d7  = new Date(now.getTime() -  7 * 24 * 60 * 60 * 1000);
    const dayMs = 24 * 60 * 60 * 1000;

    // ── Load last 28 d of platform_earnings ────────────────────────────
    const feeSnap = await db
      .collection("platform_earnings")
      .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(d28))
      .limit(5000)
      .get();

    // Group by provider + by category
    const byProvider = new Map();  // uid → { last7: n, prior3w: n }
    const byCategory = new Map();  // name → { last7: n, prior3w: n }

    for (const doc of feeSnap.docs) {
      const d = doc.data();
      const ts = d.timestamp?.toDate?.();
      if (!ts) continue;
      const amount = Number(d.sourceAmount || d.amount || 0);
      if (amount <= 0) continue;
      const inLast7 = ts >= d7;
      const pid = String(d.sourceExpertId || "");
      const cat = String(d.category || "");

      if (pid) {
        const rec = byProvider.get(pid) || { last7: 0, prior3w: 0 };
        if (inLast7) rec.last7 += amount;
        else rec.prior3w += amount;
        byProvider.set(pid, rec);
      }
      if (cat) {
        const rec = byCategory.get(cat) || { last7: 0, prior3w: 0 };
        if (inLast7) rec.last7 += amount;
        else rec.prior3w += amount;
        byCategory.set(cat, rec);
      }
    }

    const alerts = [];

    // ── Signal 1: provider GMV drop ≥ 30% ──────────────────────────────
    // Require a minimum baseline (₪500 over prior 3 weeks) to avoid noise.
    for (const [uid, rec] of byProvider.entries()) {
      if (rec.prior3w < 500) continue;
      const weeklyAvg = rec.prior3w / 3;
      const dropPct = weeklyAvg > 0 ? (1 - rec.last7 / weeklyAvg) * 100 : 0;
      if (dropPct >= 30) {
        alerts.push({
          type: "anomaly",
          severity: dropPct >= 50 ? "high" : "medium",
          entityType: "user",
          entityId: uid,
          message:
            `GMV ירד ${dropPct.toFixed(0)}% ב-7 ימים (₪${rec.last7.toFixed(0)} מול ממוצע שבועי ₪${weeklyAvg.toFixed(0)})`,
          suggestedAction: "review_provider",
        });
      }
    }

    // ── Signal 2: churn risk by inactivity ─────────────────────────────
    const providersSnap = await db
      .collection("users")
      .where("isProvider", "==", true)
      .limit(500)
      .get();

    for (const doc of providersSnap.docs) {
      const u = doc.data();
      const last = u.lastActiveAt?.toDate?.() || u.lastOnlineAt?.toDate?.();
      if (!last) continue; // no data, no signal
      const daysSince = Math.floor((now - last) / dayMs);
      const isVip = u.isPromoted === true;
      const threshold = isVip ? 10 : 14;
      if (daysSince >= threshold) {
        alerts.push({
          type: "churn_risk",
          severity: isVip ? "high" : "medium",
          entityType: "user",
          entityId: doc.id,
          message:
            `${u.name || "ספק"} לא התחבר ${daysSince} ימים${isVip ? " (VIP)" : ""}`,
          suggestedAction: "send_reengagement",
        });
      }
    }

    // ── Signal 3: category growth opportunity ≥ 20% ────────────────────
    for (const [cat, rec] of byCategory.entries()) {
      if (rec.prior3w < 1000) continue;
      const weeklyAvg = rec.prior3w / 3;
      const growthPct = weeklyAvg > 0 ? (rec.last7 / weeklyAvg - 1) * 100 : 0;
      if (growthPct >= 20) {
        alerts.push({
          type: "growth_opportunity",
          severity: growthPct >= 40 ? "high" : "low",
          entityType: "category",
          entityId: cat,
          message:
            `קטגוריית ${cat} עלתה ${growthPct.toFixed(0)}% ב-7 ימים (₪${rec.last7.toFixed(0)} מול ממוצע ₪${weeklyAvg.toFixed(0)})`,
          suggestedAction: "expand_category",
        });
      }
    }

    // ── Idempotency: dedupe against already-open alerts (last 24 h) ────
    const openCutoff = new Date(now.getTime() - dayMs);
    const openSnap = await db
      .collection("monetization_alerts")
      .where("resolved", "==", false)
      .where("detectedAt", ">=", admin.firestore.Timestamp.fromDate(openCutoff))
      .limit(500)
      .get();

    const openKeys = new Set(
      openSnap.docs.map((d) => {
        const v = d.data();
        return `${v.type}:${v.entityType}:${v.entityId}`;
      })
    );

    let written = 0;
    const batch = db.batch();
    for (const a of alerts) {
      const key = `${a.type}:${a.entityType}:${a.entityId}`;
      if (openKeys.has(key)) continue;
      const ref = db.collection("monetization_alerts").doc();
      batch.set(ref, {
        ...a,
        detectedAt: admin.firestore.FieldValue.serverTimestamp(),
        resolved: false,
      });
      written++;
      openKeys.add(key);
      if (written % 400 === 0) {
        await batch.commit();
      }
    }
    if (written % 400 !== 0) await batch.commit();

    console.log(
      `[detectMonetizationAnomalies] scanned providers=${byProvider.size}, ` +
      `categories=${byCategory.size}, candidates=${alerts.length}, wrote=${written}`
    );

    return { written, candidates: alerts.length };
  }
);

// ═══════════════════════════════════════════════════════════════════════════
// MONETIZATION v15.x — adminReleaseEscrow (admin-only force-release)
// ═══════════════════════════════════════════════════════════════════════════
// Admin counterpart to `processPaymentRelease`. The customer-facing
// variant only accepts `expert_completed` jobs and the caller must be
// the customer. Admins need to force-release `paid_escrow` jobs too
// (resolved support tickets, skipped customer confirmations, etc.).
//
// Uses the commission + net split ALREADY WRITTEN on the job at booking
// time (`job.commission`, `job.netAmountForExpert`) — so the layered
// commission computed inside `escrow_service.dart` is preserved.

exports.adminReleaseEscrow = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  if (!(await isAdminCaller(request))) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
  const { jobId, note } = request.data || {};
  if (!jobId || typeof jobId !== "string") {
    throw new HttpsError("invalid-argument", "jobId is required.");
  }

  const db = admin.firestore();
  const jobRef = db.collection("jobs").doc(jobId);

  let payoutAmount = 0;
  let commissionAmount = 0;
  let providerUid = "";
  let customerUid = "";

  await db.runTransaction(async (tx) => {
    const jobSnap = await tx.get(jobRef);
    if (!jobSnap.exists) {
      throw new HttpsError("not-found", "Job not found.");
    }
    const job = jobSnap.data();

    // Allow paid_escrow OR expert_completed. Anything else is a no-op.
    if (job.status !== "paid_escrow" && job.status !== "expert_completed") {
      throw new HttpsError(
        "failed-precondition",
        `Job status is '${job.status}', expected 'paid_escrow' or 'expert_completed'.`
      );
    }

    providerUid = String(job.expertId || "");
    customerUid = String(job.customerId || "");
    payoutAmount = Number(job.netAmountForExpert || 0);
    commissionAmount = Number(job.commission || 0);

    if (!providerUid || payoutAmount <= 0) {
      throw new HttpsError(
        "failed-precondition",
        "Job missing expertId or netAmountForExpert — cannot release."
      );
    }

    const providerRef = db.collection("users").doc(providerUid);

    // Move money: provider pending → provider balance.
    tx.update(providerRef, {
      balance: admin.firestore.FieldValue.increment(payoutAmount),
      pendingBalance:
        admin.firestore.FieldValue.increment(-payoutAmount),
      orderCount: admin.firestore.FieldValue.increment(1),
    });

    // Mark the platform_earnings record as released (best-effort — we
    // don't enforce it exists since legacy rows may not).
    // No query inside tx, so we write a fresh one for this release.
    tx.set(db.collection("platform_earnings").doc(), {
      jobId,
      amount: commissionAmount,
      sourceExpertId: providerUid,
      type: "admin_release",
      status: "released",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    tx.set(db.collection("transactions").doc(), {
      senderId: customerUid || "platform",
      receiverId: providerUid,
      amount: payoutAmount,
      type: "admin_release",
      jobId,
      payoutStatus: "completed",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    tx.update(jobRef, {
      status: "completed",
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      resolvedBy: "admin",
      resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
      resolutionType: "admin_release",
      adminNote: note || "",
    });
  });

  // Audit + activity log (best-effort, outside tx)
  try {
    await db.collection("activity_log").add({
      action: "admin_release_escrow",
      category: "monetization",
      type: "monetization_admin_release_escrow",
      adminUid: request.auth.uid,
      userId: request.auth.uid,
      targetUid: providerUid,
      detail: `שחרור escrow ${jobId} · ₪${payoutAmount.toFixed(0)} לספק`,
      title: `שחרור escrow ע"י אדמין`,
      payload: {
        jobId,
        payoutAmount,
        commissionAmount,
        note: note || "",
      },
      priority: "high",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expireAt: admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
      ),
    });
  } catch (_) {}

  // Notify provider
  try {
    await db.collection("notifications").add({
      userId: providerUid,
      title: "תשלום שוחרר",
      body: `קיבלת ₪${payoutAmount.toFixed(0)} ליתרה שלך (שוחרר ע"י האדמין).`,
      type: "payment_released",
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (_) {}

  return {
    ok: true,
    jobId,
    payoutAmount,
    commissionAmount,
  };
});

// ═══════════════════════════════════════════════════════════════════════════
// MONETIZATION v15.x — generateMonetizationInsight (every 6 hours)
// ═══════════════════════════════════════════════════════════════════════════
// Gemini 2.5 Flash Lite scans platform metrics and writes a single
// strategic recommendation to `ai_insights/monetization`. The admin tab
// reads that doc and lets the admin apply the recommendation with one
// click (via the `actionType` + `actionParams` envelope).
//
// Why Gemini (not Claude): spec is explicit — see
// docs/ui-specs/monetization/PROMPT_FOR_CLAUDE_CODE.md § 🔒 חובה.

exports.generateMonetizationInsight = onSchedule(
  {
    schedule: "every 6 hours",
    region: "us-central1",
    timeoutSeconds: 120,
    secrets: [GEMINI_API_KEY],
  },
  async () => {
    const db = admin.firestore();
    const now = new Date();
    const d30 = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
    const d7  = new Date(now.getTime() -  7 * 24 * 60 * 60 * 1000);

    // ── Metrics fan-out (parallel) ─────────────────────────────────────
    const [feeSnap, alertsSnap, providersSnap, catCommSnap, settingsSnap] =
      await Promise.all([
        db.collection("platform_earnings")
          .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(d30))
          .limit(3000)
          .get(),
        db.collection("monetization_alerts")
          .where("resolved", "==", false)
          .limit(200)
          .get(),
        db.collection("users")
          .where("isProvider", "==", true)
          .limit(500)
          .get(),
        db.collection("category_commissions").get(),
        db.collection("admin").doc("admin")
          .collection("settings").doc("settings").get(),
      ]);

    // ── Reduce: GMV + fee per category ─────────────────────────────────
    const categoryMetrics = new Map();
    let totalFee30d = 0;
    let totalGmv30d = 0;
    let fee7d = 0;
    let gmv7d = 0;
    for (const doc of feeSnap.docs) {
      const d = doc.data();
      const ts = d.timestamp?.toDate?.();
      if (!ts) continue;
      const fee = Number(d.platformFee || d.amount || 0);
      const gmv = Number(d.sourceAmount || d.amount || 0);
      const cat = String(d.category || "—");
      totalFee30d += fee;
      totalGmv30d += gmv;
      if (ts >= d7) { fee7d += fee; gmv7d += gmv; }
      const rec = categoryMetrics.get(cat) || {
        fee: 0, gmv: 0, fee7d: 0, gmv7d: 0, txCount: 0,
      };
      rec.fee += fee;
      rec.gmv += gmv;
      rec.txCount += 1;
      if (ts >= d7) { rec.fee7d += fee; rec.gmv7d += gmv; }
      categoryMetrics.set(cat, rec);
    }

    // ── Provider activity ──────────────────────────────────────────────
    let activeProviders = 0;
    let dormantProviders = 0;
    for (const doc of providersSnap.docs) {
      const u = doc.data();
      const last = u.lastActiveAt?.toDate?.() || u.lastOnlineAt?.toDate?.();
      if (!last) continue;
      const days = (now - last) / (24 * 60 * 60 * 1000);
      if (days < 7) activeProviders++;
      else if (days > 14) dormantProviders++;
    }

    // ── Alert summary ──────────────────────────────────────────────────
    const alertCounts = { anomaly: 0, churn_risk: 0, growth_opportunity: 0 };
    for (const doc of alertsSnap.docs) {
      const t = String(doc.data().type || "");
      if (t in alertCounts) alertCounts[t]++;
    }

    // ── Commission overview ────────────────────────────────────────────
    const globalFraction =
      Number(settingsSnap.data()?.feePercentage ?? 0.10);
    const globalPct = globalFraction * 100;
    const categoryOverrides = {};
    catCommSnap.forEach((d) => {
      const pct = d.data()?.percentage;
      if (typeof pct === "number") categoryOverrides[d.id] = pct;
    });
    const weightedFeePct =
      totalGmv30d > 0 ? (totalFee30d / totalGmv30d) * 100 : globalPct;

    // ── Assemble Gemini prompt ─────────────────────────────────────────
    const categoryBreakdown = [];
    for (const [cat, m] of categoryMetrics.entries()) {
      categoryBreakdown.push({
        category: cat,
        gmv30d: Math.round(m.gmv),
        fee30d: Math.round(m.fee),
        gmv7d: Math.round(m.gmv7d),
        txCount30d: m.txCount,
        override: categoryOverrides[cat] ?? null,
      });
    }
    // Sort by 30-day GMV — so the model sees the biggest categories first.
    categoryBreakdown.sort((a, b) => b.gmv30d - a.gmv30d);

    const metricsJson = {
      now: now.toISOString(),
      global: {
        commissionPct: globalPct,
        weightedActualPct: Number(weightedFeePct.toFixed(2)),
        totalFee30d: Math.round(totalFee30d),
        totalGmv30d: Math.round(totalGmv30d),
        fee7d: Math.round(fee7d),
        gmv7d: Math.round(gmv7d),
      },
      providers: {
        total: providersSnap.size,
        active7d: activeProviders,
        dormant14d: dormantProviders,
      },
      alerts: alertCounts,
      categories: categoryBreakdown.slice(0, 10),
    };

    const systemPrompt =
      "אתה מנהל מוניטיזציה של AnySkill — מרקטפלייס שירותים ישראלי. " +
      "קיבלת תמונת מצב של הפלטפורמה (30 ימים אחרונים). " +
      "החזר המלצה אסטרטגית אחת בלבד, בעברית, על הפעולה הטובה ביותר שאפשר לבצע עכשיו. " +
      "עדיפות: שימור ספקים בסיכון churn > הגדלת GMV בקטגוריות צומחות > אופטימיזציה של עמלות. " +
      "החזר אך ורק JSON תקין בסכמה:\n" +
      '{"title":"כותרת קצרה","recommendation":"משפט פעולה קונקרטי",' +
      '"expectedImpact":"השפעה מספרית צפויה (כולל ₪)","actionType":"adjust_category_commission|promote_provider|reduce_provider_commission|none",' +
      '"actionParams":{"...":"..."}}\n\n' +
      "דוגמאות ל-actionParams לפי actionType:\n" +
      '• adjust_category_commission → {"categoryName":"שיפוצים","newPct":8}\n' +
      '• reduce_provider_commission → {"userId":"abc","newPct":7,"reason":"שימור"}\n' +
      '• promote_provider → {"userId":"abc"}\n' +
      '• none → {} (אם אין פעולה מובהקת)';

    let result;
    try {
      const geminiKey =
        GEMINI_API_KEY.value() || process.env.GEMINI_API_KEY || "";
      if (!geminiKey) throw new Error("GEMINI_API_KEY not configured");
      const url =
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=" +
        geminiKey;
      const resp = await fetch(url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: systemPrompt }] },
          contents: [{
            role: "user",
            parts: [{
              text: "תמונת מצב נוכחית:\n" +
                JSON.stringify(metricsJson, null, 2),
            }],
          }],
          generationConfig: {
            temperature: 0.4,
            maxOutputTokens: 800,
            responseMimeType: "application/json",
          },
        }),
      });
      if (!resp.ok) {
        throw new Error("Gemini HTTP " + resp.status);
      }
      const json = await resp.json();
      const text = json?.candidates?.[0]?.content?.parts?.[0]?.text || "";
      result = JSON.parse(text);
    } catch (e) {
      console.error("[generateMonetizationInsight] Gemini failed:", e.message);
      return { ok: false, error: e.message };
    }

    // Sanity-check the response shape.
    const safe = {
      title: String(result.title || "תובנת AI CEO"),
      recommendation: String(result.recommendation || ""),
      expectedImpact: String(result.expectedImpact || ""),
      actionType: String(result.actionType || "none"),
      actionParams: typeof result.actionParams === "object"
        ? result.actionParams
        : {},
      model: "gemini-2.5-flash-lite",
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
      applied: false,
      // Preserve any dismissedBy/At already set — we merge rather than
      // overwrite, so the admin's dismiss state carries across runs only
      // until a NEW insight is generated, at which point the dismiss is
      // cleared by the delete below.
    };

    // Clear prior dismiss flags so the fresh banner shows.
    await db.collection("ai_insights").doc("monetization").set({
      ...safe,
      dismissedBy: admin.firestore.FieldValue.delete(),
      dismissedAt: admin.firestore.FieldValue.delete(),
    }, { merge: true });

    console.log(
      `[generateMonetizationInsight] wrote insight: ${safe.actionType} — ${safe.recommendation.substring(0, 80)}`
    );
    return { ok: true, actionType: safe.actionType };
  }
);

// ==========================================================================
// REVIEW REMINDER EMAIL - Airbnb-style daily reminder (v14.x)
// ==========================================================================
// Sends a daily email to customers + providers who have a completed job
// within the last 7 days but haven't yet submitted their review.
// Once the 7-day window closes, reviews auto-publish (lazy publish in
// ReviewService) and reminders stop.
//
// Idempotency: one reminder per user per job per day (tracked in
// review_reminders_sent collection with doc ID = jobId_userId_YYYYMMDD).

exports.sendReviewReminders = onSchedule(
  { schedule: "0 10 * * *", timeZone: "Asia/Jerusalem" },
  async () => {
    const db = admin.firestore();
    try {
      const now = new Date();
      const oneDayAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000);
      const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

      // Only remind after 24h grace period (give them time to review first)
      const snap = await db
        .collection("jobs")
        .where("status", "==", "completed")
        .where("completedAt", ">=", admin.firestore.Timestamp.fromDate(sevenDaysAgo))
        .where("completedAt", "<=", admin.firestore.Timestamp.fromDate(oneDayAgo))
        .limit(500)
        .get();

      if (snap.empty) {
        console.log("sendReviewReminders: no pending jobs");
        return null;
      }

      const todayKey = now.getFullYear() + "-" +
        String(now.getMonth() + 1).padStart(2, "0") + "-" +
        String(now.getDate()).padStart(2, "0");

      let sent = 0;
      let skipped = 0;

      for (const doc of snap.docs) {
        const job = doc.data();
        const jobId = doc.id;
        const clientReviewDone = job.clientReviewDone === true;
        const providerReviewDone = job.providerReviewDone === true;

        // Client needs to review the provider?
        if (!clientReviewDone && job.customerId) {
          const result = await _sendReviewReminderEmail({
            db, jobId, job, todayKey,
            userId: job.customerId,
            otherPartyName: job.expertName || "נותן השירות",
            isClientReview: true,
          });
          if (result === "sent") sent++; else skipped++;
        }

        // Provider needs to review the client?
        if (!providerReviewDone && job.expertId) {
          const result = await _sendReviewReminderEmail({
            db, jobId, job, todayKey,
            userId: job.expertId,
            otherPartyName: job.customerName || "הלקוח",
            isClientReview: false,
          });
          if (result === "sent") sent++; else skipped++;
        }
      }

      console.log(`sendReviewReminders: sent=${sent}, skipped=${skipped}, jobs=${snap.docs.length}`);
      return null;
    } catch (err) {
      console.error("sendReviewReminders error:", err);
      return null;
    }
  }
);

async function _sendReviewReminderEmail({
  db, jobId, job, todayKey, userId, otherPartyName, isClientReview,
}) {
  // Idempotency key: jobId_userId_YYYYMMDD
  const reminderId = jobId + "_" + userId + "_" + todayKey;
  const reminderRef = db.collection("review_reminders_sent").doc(reminderId);
  const existing = await reminderRef.get();
  if (existing.exists) return "already_sent";

  // Resolve recipient email + opt-out
  const userSnap = await db.collection("users").doc(userId).get();
  if (!userSnap.exists) return "no_user";
  const userData = userSnap.data();
  const email = userData.email;
  if (!email) return "no_email";
  if (userData.receiveEmailReceipts === false) return "opted_out";

  const userName = userData.name || "";
  const recipientGreeting = userName ? ("היי " + userName) : "היי";

  // Compute days remaining in 7-day window
  const completedAt = job.completedAt && job.completedAt.toDate
    ? job.completedAt.toDate()
    : new Date();
  const daysElapsed = Math.floor((Date.now() - completedAt.getTime()) / (24 * 60 * 60 * 1000));
  const daysRemaining = Math.max(1, 7 - daysElapsed);

  // HTML escape
  const esc = (s) => (s || "")
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#039;");

  const reviewUrl = "https://anyskill-6fdf3.web.app/#/review?jobId=" +
    encodeURIComponent(jobId) + "&isClientReview=" + (isClientReview ? "true" : "false");

  const html = `
<!DOCTYPE html>
<html dir="rtl" lang="he">
<head><meta charset="UTF-8">
<style>
  body { font-family: Arial, sans-serif; background: #f5f7fa; margin: 0; padding: 20px; direction: rtl; }
  .card { background: #fff; border-radius: 16px; max-width: 520px; margin: 0 auto; overflow: hidden; box-shadow: 0 4px 20px rgba(0,0,0,.08); }
  .header { background: linear-gradient(135deg,#6366F1,#8B5CF6); color: #fff; padding: 28px; text-align: center; }
  .header h1 { margin: 0; font-size: 24px; font-weight: 900; }
  .header .emoji { font-size: 44px; margin-bottom: 10px; }
  .body { padding: 28px; color: #1F2937; }
  .body p { line-height: 1.6; font-size: 15px; margin: 0 0 14px; }
  .highlight { background: #FEF3C7; border-right: 4px solid #F59E0B; padding: 14px 18px; border-radius: 10px; margin: 16px 0; }
  .btn { display: block; background: #6366F1; color: #fff !important; padding: 14px 24px; border-radius: 12px; text-decoration: none; font-weight: bold; font-size: 15px; text-align: center; margin: 24px auto 8px; max-width: 280px; }
  .days { color: #EF4444; font-weight: bold; }
  .footer { text-align: center; padding: 16px; background: #f9fafb; color: #bbb; font-size: 11px; }
</style>
</head>
<body>
<div class="card">
  <div class="header">
    <div class="emoji">⭐</div>
    <h1>איך הייתה החוויה שלך?</h1>
  </div>
  <div class="body">
    <p>${esc(recipientGreeting)},</p>
    <p>עדיין לא הגבת על חוות הדעת של <strong>${esc(otherPartyName)}</strong>.</p>
    <p>שיתוף החוויה שלך עוזר לקהילה של AnySkill לקבל החלטות טובות יותר — וזה לוקח פחות מדקה.</p>
    <div class="highlight">
      <strong>⏰ נותרו <span class="days">${daysRemaining} ימים</span></strong><br>
      <span style="font-size: 13px; color: #6B7280;">אחרי 7 ימים החלון נסגר וחוות הדעת תתפרסם אוטומטית.</span>
    </div>
    <a href="${reviewUrl}" class="btn">כתוב חוות דעת עכשיו</a>
    <p style="font-size: 12px; color: #9CA3AF; text-align: center; margin-top: 20px;">
      לא רוצה לקבל תזכורות? ניתן לבטל בדף הפרופיל.
    </p>
  </div>
  <div class="footer">AnySkill &bull; מסמך נשלח אוטומטית</div>
</div>
</body></html>`;

  const subject = "⭐ היי — עדיין לא הגבת על " + otherPartyName;

  // Queue the email + mark as sent atomically
  const batch = db.batch();
  batch.set(db.collection("mail").doc(), {
    to: [email],
    message: { subject, html },
  });
  batch.set(reminderRef, {
    jobId,
    userId,
    sentAt: admin.firestore.FieldValue.serverTimestamp(),
    dayKey: todayKey,
    isClientReview,
    expireAt: admin.firestore.Timestamp.fromDate(
      new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
    ),
  });
  await batch.commit();
  return "sent";
}
