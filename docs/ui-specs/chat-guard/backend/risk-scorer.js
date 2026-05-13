/**
 * Chat Guard AI - Risk Scorer
 * ============================
 * מחשב את ציון הסיכון של משתמש על בסיס היסטוריה
 */

/**
 * מחשב ציון סיכון כולל למשתמש (0-100)
 *
 * @param {string} userId
 * @param {Object} db - חיבור ל-DB
 * @returns {number} 0-100
 */
async function calculateUserRiskScore(userId, db) {
  if (!userId) return 0;

  // טען את כל התקריות של המשתמש ב-30 ימים האחרונים
  const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000);
  const incidents = await db.collection('incidents').find({
    userId,
    timestamp: { $gte: thirtyDaysAgo }
  }).toArray();

  if (incidents.length === 0) return 0;

  let score = 0;

  // 1. ספירת תקריות לפי חומרה
  const severityCounts = {
    low: 0, medium: 0, high: 0, critical: 0
  };
  incidents.forEach(i => {
    severityCounts[i.severity] = (severityCounts[i.severity] || 0) + 1;
  });

  score += severityCounts.low * 3;
  score += severityCounts.medium * 8;
  score += severityCounts.high * 18;
  score += severityCounts.critical * 35;

  // 2. Frequency factor - הרבה תקריות בזמן קצר = יותר חשוד
  const last24h = incidents.filter(i => (Date.now() - new Date(i.timestamp).getTime()) < 86400000);
  if (last24h.length >= 5) score += 15;
  else if (last24h.length >= 3) score += 8;

  // 3. Escalation factor - עלייה ברצף = יותר חשוד
  if (incidents.length >= 3) {
    const recent = incidents.slice(0, 3);
    const older = incidents.slice(-3);
    const recentAvg = recent.reduce((s, i) => s + rankSeverity(i.severity), 0) / 3;
    const olderAvg = older.reduce((s, i) => s + rankSeverity(i.severity), 0) / 3;
    if (recentAvg > olderAvg * 1.5) score += 12;
  }

  // 4. Reports from others
  const reports = await db.collection('user_reports').countDocuments({
    reportedUserId: userId,
    createdAt: { $gte: thirtyDaysAgo }
  });
  score += reports * 10;

  // 5. Account age - חשבון חדש עם הרבה תקריות = חשוד יותר
  const user = await db.collection('users').findOne({ id: userId });
  if (user) {
    const accountAgeDays = (Date.now() - new Date(user.createdAt).getTime()) / 86400000;
    if (accountAgeDays < 7 && incidents.length >= 3) score += 20;
    else if (accountAgeDays < 30 && incidents.length >= 5) score += 10;
  }

  return Math.min(100, Math.round(score));
}

/**
 * מזהה רשתות הונאה - משתמשים מקושרים
 * זה פיצ'ר מתקדם - משמש Graph Analysis
 */
async function findLinkedUsers(userId, db) {
  const user = await db.collection('users').findOne({ id: userId });
  if (!user) return [];

  const linked = new Set();

  // לפי מכשיר משותף
  if (user.deviceId) {
    const sameDevice = await db.collection('users').find({
      deviceId: user.deviceId,
      id: { $ne: userId }
    }).toArray();
    sameDevice.forEach(u => linked.add(u.id));
  }

  // לפי IP משותף (ב-24 שעות האחרונות)
  if (user.lastIp) {
    const sameIp = await db.collection('sessions').find({
      ip: user.lastIp,
      userId: { $ne: userId },
      createdAt: { $gte: new Date(Date.now() - 86400000) }
    }).toArray();
    sameIp.forEach(s => linked.add(s.userId));
  }

  // לפי מספר טלפון דומה
  if (user.phone) {
    const similarPhone = await db.collection('users').find({
      phone: { $regex: user.phone.substring(0, 7) },
      id: { $ne: userId }
    }).toArray();
    similarPhone.forEach(u => linked.add(u.id));
  }

  return [...linked];
}

function rankSeverity(s) {
  return { low: 1, medium: 2, high: 3, critical: 4 }[s] || 0;
}

module.exports = {
  calculateUserRiskScore,
  findLinkedUsers
};
