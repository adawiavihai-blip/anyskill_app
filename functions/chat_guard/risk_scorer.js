/**
 * Chat Guard — user risk scorer (server-side)
 *
 * Computes a 0-100 risk score for a user from:
 *   • incidents in the last 30 days (severity × count)
 *   • burst factor (many incidents in 24h)
 *   • escalation (recent worse than older)
 *   • user account age
 *
 * Ported + simplified from `docs/ui-specs/chat-guard/backend/risk-scorer.js`.
 * Requires the caller to pass in an initialized `admin.firestore()` handle.
 */

const SEVERITY_RANKS = { low: 1, medium: 2, high: 3, critical: 4 };

/**
 * @param {string} userId
 * @param {FirebaseFirestore.Firestore} db
 * @returns {Promise<number>} 0..100
 */
async function calculateUserRiskScore(userId, db) {
  if (!userId) return 0;

  const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000);

  let incidents = [];
  try {
    const snap = await db
      .collection('chat_guard_incidents')
      .where('userId', '==', userId)
      .where('timestamp', '>=', thirtyDaysAgo)
      .limit(200)
      .get();
    incidents = snap.docs.map((d) => d.data() || {});
  } catch (e) {
    // Missing composite index on first run is fine — score defaults to 0
    // and the CF falls through to allow. The admin can see the required
    // index link in the Firestore log; we also pre-declare it in
    // firestore.indexes.json so production builds don't hit this path.
    console.warn(`[chat-guard/risk] incidents query failed: ${e.message}`);
    return 0;
  }

  if (incidents.length === 0) return 0;

  let score = 0;

  // 1. Severity counts
  const counts = { low: 0, medium: 0, high: 0, critical: 0 };
  for (const inc of incidents) {
    const s = inc.severity;
    if (counts[s] !== undefined) counts[s] += 1;
  }
  score += counts.low * 3;
  score += counts.medium * 8;
  score += counts.high * 18;
  score += counts.critical * 35;

  // 2. Burst — many incidents in last 24h
  const now = Date.now();
  const last24h = incidents.filter((i) => {
    const ts = normalizeTimestamp(i.timestamp);
    return ts != null && now - ts < 86400000;
  });
  if (last24h.length >= 5) score += 15;
  else if (last24h.length >= 3) score += 8;

  // 3. Escalation — sort by timestamp desc, compare top 3 vs bottom 3
  if (incidents.length >= 6) {
    const sorted = [...incidents].sort((a, b) => {
      return (normalizeTimestamp(b.timestamp) || 0) -
             (normalizeTimestamp(a.timestamp) || 0);
    });
    const recent = sorted.slice(0, 3);
    const older = sorted.slice(-3);
    const recentAvg =
      recent.reduce((s, i) => s + (SEVERITY_RANKS[i.severity] || 0), 0) / 3;
    const olderAvg =
      older.reduce((s, i) => s + (SEVERITY_RANKS[i.severity] || 0), 0) / 3;
    if (olderAvg > 0 && recentAvg > olderAvg * 1.5) score += 12;
  }

  // 4. Account age — new account + many incidents = higher risk
  try {
    const userDoc = await db.collection('users').doc(userId).get();
    if (userDoc.exists) {
      const u = userDoc.data() || {};
      const created = normalizeTimestamp(u.createdAt) ||
                      normalizeTimestamp(u.registrationDate);
      if (created) {
        const ageDays = (now - created) / 86400000;
        if (ageDays < 7 && incidents.length >= 3) score += 20;
        else if (ageDays < 30 && incidents.length >= 5) score += 10;
      }
    }
  } catch (_) {/* not fatal */}

  return Math.min(100, Math.round(score));
}

/** Firestore Timestamp / JS Date / millis — normalized to millis. */
function normalizeTimestamp(v) {
  if (v == null) return null;
  if (typeof v === 'number') return v;
  if (v instanceof Date) return v.getTime();
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (typeof v.seconds === 'number') return v.seconds * 1000;
  return null;
}

module.exports = { calculateUserRiskScore };
