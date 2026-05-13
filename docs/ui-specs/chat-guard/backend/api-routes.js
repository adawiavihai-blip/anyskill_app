/**
 * Chat Guard AI - API Routes
 * ============================
 * נקודות קצה REST לשימוש האפליקציה שלך.
 * מוכן לשילוב ב-Express, Fastify, Next.js API Routes, Firebase Functions וכו'.
 *
 * כל הנקודות מחזירות JSON.
 */

const { checkMessage, SEVERITY, ACTIONS } = require('./detection-engine');
const { calculateUserRiskScore } = require('./risk-scorer');

// ============================================
// CRUD: Words Management
// ============================================

/**
 * GET /api/words
 * מחזיר את כל מילות החסימה
 */
async function getWords(req, db) {
  // החלף ב-DB אמיתי (Firebase/Supabase/SQL)
  const words = await db.collection('blocked_words').find().toArray();
  return { success: true, words };
}

/**
 * POST /api/words
 * הוספת מילה חדשה
 * Body: { text, category, severity, notes }
 */
async function addWord(req, db) {
  const { text, category, severity, notes = '' } = req.body;

  if (!text || !text.trim()) {
    return { success: false, error: 'טקסט המילה חובה' };
  }

  // בדוק כפילות
  const existing = await db.collection('blocked_words').findOne({
    text: { $regex: new RegExp(`^${text}$`, 'i') }
  });
  if (existing) {
    return { success: false, error: 'מילה זו כבר קיימת' };
  }

  const newWord = {
    id: 'w_' + Date.now(),
    text: text.trim(),
    category: category || 'custom',
    severity: severity || 'medium',
    notes,
    createdAt: new Date(),
    createdBy: req.user?.id || 'admin',
    hits: 0
  };

  await db.collection('blocked_words').insertOne(newWord);

  // Notify all connected clients (via WebSocket/Push) that words updated
  await broadcastUpdate('words');

  return { success: true, word: newWord };
}

/**
 * PUT /api/words/:id
 * עדכון מילה
 */
async function updateWord(req, db) {
  const { id } = req.params;
  const { text, category, severity, notes } = req.body;

  const result = await db.collection('blocked_words').updateOne(
    { id },
    { $set: { text, category, severity, notes, updatedAt: new Date() } }
  );

  if (result.matchedCount === 0) {
    return { success: false, error: 'מילה לא נמצאה' };
  }

  await broadcastUpdate('words');
  return { success: true };
}

/**
 * DELETE /api/words/:id
 */
async function deleteWord(req, db) {
  const { id } = req.params;
  await db.collection('blocked_words').deleteOne({ id });
  await broadcastUpdate('words');
  return { success: true };
}

// ============================================
// Main Detection Endpoint
// ============================================

/**
 * POST /api/check
 * הנקודה שהאפליקציה שלך קוראת לה לכל הודעה שנשלחת
 *
 * Body: { message, userId, chatId }
 * Returns: {
 *   action: 'allowed' | 'warned' | 'rewritten' | 'blocked' | 'suspended',
 *   severity: string | null,
 *   score: number,
 *   rewrite: string | null,
 *   reason: string | null
 * }
 */
async function checkMessageEndpoint(req, db) {
  const { message, userId, chatId } = req.body;

  if (!message) {
    return { success: false, error: 'ההודעה חובה' };
  }

  // טען נתונים נחוצים
  const words = (await db.collection('blocked_words').find().toArray());
  const settings = await db.collection('settings').findOne({ _id: 'main' }) || {};
  const userRiskScore = userId ? await calculateUserRiskScore(userId, db) : 0;

  // הרץ את מנוע הזיהוי
  const result = await checkMessage(message, {
    words,
    settings,
    userId,
    userRiskScore,
    chatId
  });

  // אם זוהה ניסיון - שמור תקרית ב-DB
  if (result.detected) {
    await saveIncident({
      userId,
      chatId,
      message,
      result
    }, db);

    // עדכן את מונה ה-hits של המילים שתפסו
    for (const match of result.matches) {
      if (match.wordId) {
        await db.collection('blocked_words').updateOne(
          { id: match.wordId },
          { $inc: { hits: 1 } }
        );
      }
    }
  }

  return {
    success: true,
    action: result.action,
    severity: result.severity,
    score: result.score,
    rewrite: result.rewrite,
    reason: result.reason,
    detected: result.detected
  };
}

// ============================================
// Incidents
// ============================================

/**
 * GET /api/incidents
 * Query: ?severity=critical&limit=50&offset=0
 */
async function getIncidents(req, db) {
  const { severity, limit = 50, offset = 0, userId } = req.query;

  const filter = {};
  if (severity) filter['result.severity'] = severity;
  if (userId) filter.userId = userId;

  const incidents = await db.collection('incidents')
    .find(filter)
    .sort({ timestamp: -1 })
    .skip(parseInt(offset))
    .limit(parseInt(limit))
    .toArray();

  const total = await db.collection('incidents').countDocuments(filter);

  return { success: true, incidents, total };
}

async function saveIncident(data, db) {
  const incident = {
    id: 'i_' + Date.now(),
    userId: data.userId,
    chatId: data.chatId,
    message: data.message,
    matchedWords: data.result.matches.map(m => m.word),
    severity: data.result.severity,
    action: data.result.action,
    detectionMethods: [...new Set(data.result.matches.map(m => m.matchType))],
    riskScore: data.result.score,
    timestamp: new Date(),
    reviewed: false
  };

  await db.collection('incidents').insertOne(incident);
  await broadcastUpdate('incidents');
  return incident;
}

// ============================================
// Stats & KPIs
// ============================================

/**
 * GET /api/stats
 * מחזיר KPIs לדשבורד
 */
async function getStats(req, db) {
  const now = new Date();
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const yesterdayStart = new Date(todayStart.getTime() - 86400000);

  const [
    totalWords,
    todayIncidents,
    yesterdayIncidents,
    todayBlocked,
    suspiciousUsers
  ] = await Promise.all([
    db.collection('blocked_words').countDocuments(),
    db.collection('incidents').countDocuments({ timestamp: { $gte: todayStart } }),
    db.collection('incidents').countDocuments({
      timestamp: { $gte: yesterdayStart, $lt: todayStart }
    }),
    db.collection('incidents').countDocuments({
      timestamp: { $gte: todayStart },
      action: { $in: ['blocked', 'suspended'] }
    }),
    db.collection('incidents').distinct('userId', {
      severity: { $in: ['high', 'critical'] },
      timestamp: { $gte: new Date(now.getTime() - 7 * 86400000) }
    })
  ]);

  const changePercent = yesterdayIncidents > 0
    ? Math.round(((todayIncidents - yesterdayIncidents) / yesterdayIncidents) * 100)
    : 0;

  return {
    success: true,
    stats: {
      totalWords,
      attemptsToday: todayIncidents,
      blockedToday: todayBlocked,
      suspiciousUsers: suspiciousUsers.length,
      changeFromYesterday: changePercent
    }
  };
}

// ============================================
// Settings
// ============================================

async function getSettings(req, db) {
  const settings = await db.collection('settings').findOne({ _id: 'main' }) || {
    sensitivity: 65,
    detectSpaces: true,
    detectLeetspeak: true,
    detectEmoji: true,
    detectPhoneNumbers: true,
    detectLinks: true
  };
  return { success: true, settings };
}

async function updateSettings(req, db) {
  const settings = req.body;
  await db.collection('settings').updateOne(
    { _id: 'main' },
    { $set: { ...settings, updatedAt: new Date() } },
    { upsert: true }
  );
  await broadcastUpdate('settings');
  return { success: true };
}

// ============================================
// Real-time Broadcasting
// ============================================

/**
 * מודיע לכל הלקוחות שמחוברים על שינוי
 * להטמעה: השתמש ב-WebSocket, Socket.io, Firebase Realtime, Supabase Realtime
 */
async function broadcastUpdate(type) {
  // Example for Socket.io:
  // io.emit('chatguard-update', { type, timestamp: Date.now() });

  // Example for Firebase Realtime:
  // await firebase.database().ref('sync').set({ type, timestamp: Date.now() });

  // Example for Supabase Realtime: (automatic on table changes)

  console.log(`[ChatGuard] Broadcast: ${type} updated`);
}

// ============================================
// Route Registration Example
// ============================================

/**
 * דוגמה לרישום הנקודות ב-Express:
 */
function registerRoutes(app, db) {
  // Words CRUD
  app.get('/api/words', (req, res) => getWords(req, db).then(r => res.json(r)));
  app.post('/api/words', (req, res) => addWord(req, db).then(r => res.json(r)));
  app.put('/api/words/:id', (req, res) => updateWord(req, db).then(r => res.json(r)));
  app.delete('/api/words/:id', (req, res) => deleteWord(req, db).then(r => res.json(r)));

  // Detection
  app.post('/api/check', (req, res) => checkMessageEndpoint(req, db).then(r => res.json(r)));

  // Incidents
  app.get('/api/incidents', (req, res) => getIncidents(req, db).then(r => res.json(r)));

  // Stats
  app.get('/api/stats', (req, res) => getStats(req, db).then(r => res.json(r)));

  // Settings
  app.get('/api/settings', (req, res) => getSettings(req, db).then(r => res.json(r)));
  app.put('/api/settings', (req, res) => updateSettings(req, db).then(r => res.json(r)));
}

module.exports = {
  getWords,
  addWord,
  updateWord,
  deleteWord,
  checkMessageEndpoint,
  getIncidents,
  getStats,
  getSettings,
  updateSettings,
  registerRoutes
};
