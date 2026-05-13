/**
 * Chat Guard AI - Frontend Logic
 * ==================================
 * מנהל את כל הדשבורד - מילים, בדיקות, תקריות והגדרות
 *
 * 🔗 חיבור ל-Backend:
 * לפי ברירת מחדל משתמש ב-localStorage (עובד מיד ללא שרת).
 * כדי לחבר לשרת אמיתי: החלף את הפונקציות ב-DataLayer בקריאות ל-API שלך
 * (ראה backend/api-routes.js לדוגמאות)
 */

// ============================================
// Data Layer - שכבת נתונים
// ============================================
// כאן מתבצע כל הסנכרון. אם יש לך DB (Firebase/Supabase/REST API),
// החלף את הפונקציות כדי לקרוא/לכתוב לשם במקום ל-localStorage

const DataLayer = {
  // ---- Read ----
  async getWords() {
    // TODO: החלף ב: return fetch('/api/words').then(r => r.json())
    const saved = localStorage.getItem('chatguard_words');
    return saved ? JSON.parse(saved) : getDefaultWords();
  },

  async getIncidents() {
    // TODO: החלף ב: return fetch('/api/incidents').then(r => r.json())
    const saved = localStorage.getItem('chatguard_incidents');
    return saved ? JSON.parse(saved) : getDefaultIncidents();
  },

  async getSettings() {
    // TODO: החלף ב: return fetch('/api/settings').then(r => r.json())
    const saved = localStorage.getItem('chatguard_settings');
    return saved ? JSON.parse(saved) : getDefaultSettings();
  },

  async getStats() {
    // TODO: החלף ב: return fetch('/api/stats').then(r => r.json())
    const incidents = await this.getIncidents();
    const words = await this.getWords();
    const todayIncidents = incidents.filter(i => isToday(i.timestamp));
    const suspicious = [...new Set(incidents.filter(i => i.severity === 'critical' || i.severity === 'high').map(i => i.userId))];

    return {
      totalWords: words.length,
      attemptsToday: todayIncidents.length,
      blockedToday: todayIncidents.filter(i => i.action === 'blocked').length,
      suspiciousUsers: suspicious.length
    };
  },

  // ---- Write ----
  async saveWords(words) {
    // TODO: החלף ב: return fetch('/api/words', {method:'PUT', body: JSON.stringify(words)})
    localStorage.setItem('chatguard_words', JSON.stringify(words));
    this.notifySync('words');
  },

  async saveIncidents(incidents) {
    localStorage.setItem('chatguard_incidents', JSON.stringify(incidents));
    this.notifySync('incidents');
  },

  async saveSettings(settings) {
    localStorage.setItem('chatguard_settings', JSON.stringify(settings));
    this.notifySync('settings');
  },

  // ---- Sync Notification ----
  // מודיע לאפליקציה שהיו שינויים (כדי לרענן ב-real-time)
  notifySync(type) {
    const event = new CustomEvent('chatguard-sync', { detail: { type, timestamp: Date.now() } });
    window.dispatchEvent(event);
  }
};

// ============================================
// State - מצב האפליקציה בזיכרון
// ============================================
let state = {
  words: [],
  incidents: [],
  settings: {},
  filter: 'all',
  incidentFilter: 'all',
  editingWordId: null
};

// ============================================
// Default Data - נתונים התחלתיים
// ============================================
function getDefaultWords() {
  return [
    // Payment words
    { id: 'w1', text: 'מזומן', category: 'payment', severity: 'high', notes: '', createdAt: Date.now(), hits: 142 },
    { id: 'w2', text: 'ביט', category: 'payment', severity: 'high', notes: '', createdAt: Date.now(), hits: 98 },
    { id: 'w3', text: 'paybox', category: 'payment', severity: 'high', notes: '', createdAt: Date.now(), hits: 76 },
    { id: 'w4', text: 'cash', category: 'payment', severity: 'medium', notes: '', createdAt: Date.now(), hits: 34 },
    { id: 'w5', text: 'העברה בנקאית', category: 'payment', severity: 'medium', notes: '', createdAt: Date.now(), hits: 23 },
    { id: 'w6', text: 'כסף', category: 'payment', severity: 'medium', notes: 'הוסף על ידי המנהל', createdAt: Date.now(), hits: 45 },

    // Contact words
    { id: 'w7', text: 'וואטסאפ', category: 'contact', severity: 'high', notes: '', createdAt: Date.now(), hits: 87 },
    { id: 'w8', text: 'whatsapp', category: 'contact', severity: 'high', notes: '', createdAt: Date.now(), hits: 54 },
    { id: 'w9', text: 'טלגרם', category: 'contact', severity: 'high', notes: '', createdAt: Date.now(), hits: 29 },
    { id: 'w10', text: 'telegram', category: 'contact', severity: 'high', notes: '', createdAt: Date.now(), hits: 18 },
    { id: 'w11', text: 'אינסטגרם', category: 'contact', severity: 'medium', notes: '', createdAt: Date.now(), hits: 22 },
    { id: 'w12', text: 'טלפון', category: 'contact', severity: 'medium', notes: '', createdAt: Date.now(), hits: 67 },

    // External apps
    { id: 'w13', text: 'wa.me', category: 'external', severity: 'critical', notes: 'לינק ישיר לוואטסאפ', createdAt: Date.now(), hits: 43 },
    { id: 'w14', text: 't.me', category: 'external', severity: 'critical', notes: 'לינק לטלגרם', createdAt: Date.now(), hits: 12 },
    { id: 'w15', text: 'outside app', category: 'external', severity: 'high', notes: '', createdAt: Date.now(), hits: 8 }
  ];
}

function getDefaultIncidents() {
  const now = Date.now();
  return [
    {
      id: 'i1', userId: 'USR-48291', userName: 'דני כהן',
      message: 'אחי, תעביר לאשתי והיא תסדר איתך במזומן בצד',
      matchedWords: ['מזומן'],
      severity: 'critical', action: 'blocked',
      detectionMethod: 'LLM סמנטי + מילות מפתח',
      riskScore: 87,
      timestamp: now - 180000,
      chatPartner: 'עידית ש.'
    },
    {
      id: 'i2', userId: 'USR-38192', userName: 'שרה לוי',
      message: 'שלחה תמונה של QR PayBox',
      matchedWords: ['paybox (OCR)'],
      severity: 'high', action: 'blocked',
      detectionMethod: 'OCR',
      riskScore: 64,
      timestamp: now - 720000,
      chatPartner: 'דן ק.'
    },
    {
      id: 'i3', userId: 'USR-12495', userName: 'יוסי מזרחי',
      message: 'אפשר 0 5 0 · 1 2 3 4 · 5 6 7?',
      matchedWords: ['מספר טלפון מוסווה'],
      severity: 'medium', action: 'rewritten',
      detectionMethod: 'זיהוי הסוואות',
      riskScore: 42,
      timestamp: now - 1620000,
      chatPartner: 'מיכל א.'
    },
    {
      id: 'i4', userId: 'USR-22841', userName: 'רונית גולד',
      message: 'בוא תתקשר אליי בוואטסאפ',
      matchedWords: ['וואטסאפ'],
      severity: 'high', action: 'blocked',
      detectionMethod: 'מילת מפתח',
      riskScore: 71,
      timestamp: now - 3600000,
      chatPartner: 'אבי ל.'
    },
    {
      id: 'i5', userId: 'USR-48291', userName: 'דני כהן',
      message: 'נפגש ונסדר בקפה?',
      matchedWords: ['זיהוי סמנטי'],
      severity: 'medium', action: 'warned',
      detectionMethod: 'LLM סמנטי',
      riskScore: 38,
      timestamp: now - 7200000,
      chatPartner: 'נטע ב.'
    }
  ];
}

function getDefaultSettings() {
  return {
    sensitivity: 65,
    detectSpaces: true,
    detectLeetspeak: true,
    detectEmoji: true,
    detectPhoneNumbers: true,
    detectLinks: true
  };
}

// ============================================
// Detection Engine - מנוע הזיהוי
// ============================================
// הלוגיקה הבסיסית שמשמשת ב-Frontend לבדיקת הודעות
// (הגרסה המלאה והחזקה נמצאת ב-backend/detection-engine.js)

const DetectionEngine = {
  /**
   * בדיקה אם הודעה מכילה ניסיון עקיפה
   * @returns { detected, severity, matches, score }
   */
  check(message, words, settings) {
    if (!message || !message.trim()) {
      return { detected: false, severity: null, matches: [], score: 0 };
    }

    const normalized = this.normalize(message, settings);
    const matches = [];
    let maxSeverity = null;
    let score = 0;

    // בדוק כל מילה ברשימה
    for (const word of words) {
      const wordNormalized = this.normalize(word.text, settings);
      if (normalized.includes(wordNormalized)) {
        matches.push({
          word: word.text,
          category: word.category,
          severity: word.severity,
          id: word.id
        });

        // עדכן את הרמה הכי גבוהה שנמצאה
        if (this.severityRank(word.severity) > this.severityRank(maxSeverity)) {
          maxSeverity = word.severity;
        }

        score += this.severityScore(word.severity);
      }
    }

    // בדיקות נוספות
    if (settings.detectPhoneNumbers && this.hasPhoneNumber(message)) {
      matches.push({ word: 'מספר טלפון', category: 'contact', severity: 'high', id: 'phone' });
      if (this.severityRank('high') > this.severityRank(maxSeverity)) maxSeverity = 'high';
      score += this.severityScore('high');
    }

    if (settings.detectLinks && this.hasExternalLink(message)) {
      matches.push({ word: 'קישור חיצוני', category: 'external', severity: 'critical', id: 'link' });
      maxSeverity = 'critical';
      score += this.severityScore('critical');
    }

    return {
      detected: matches.length > 0,
      severity: maxSeverity,
      matches,
      score: Math.min(100, score)
    };
  },

  // נירמול טקסט להתאמת הסוואות
  normalize(text, settings) {
    let t = text.toLowerCase();

    if (settings.detectSpaces) {
      // הסר רווחים מיותרים בין אותיות בודדות (מ ז ו מ ן → מזומן)
      t = t.replace(/(\S)\s+(?=\S\s|\S$)/g, (m, c) => {
        // תפוס רק אם זו סדרה של אותיות בודדות
        return c;
      });
      t = t.replace(/\s+/g, ' ').trim();
    }

    if (settings.detectLeetspeak) {
      // החלף ספרות נפוצות לאותיות (0→o, 1→i, 3→e, 4→a, 5→s)
      t = t.replace(/0/g, 'o').replace(/1/g, 'i').replace(/3/g, 'e').replace(/4/g, 'a').replace(/5/g, 's');
    }

    if (settings.detectEmoji) {
      // החלף אימוג'ים נפוצים במילים
      t = t.replace(/💵|💰|💸/g, 'מזומן').replace(/📞|☎️|📱/g, 'טלפון');
    }

    // הסר סימני פיסוק מהסוואה
    t = t.replace(/[.·_\-\*]/g, '');

    return t;
  },

  hasPhoneNumber(text) {
    // זיהוי מספר טלפון ישראלי גם עם רווחים והפרדות
    const cleaned = text.replace(/[\s\-\.·_]/g, '');
    return /05\d{8}/.test(cleaned) || /0\d{1,2}\d{7}/.test(cleaned);
  },

  hasExternalLink(text) {
    return /(?:wa\.me|t\.me|telegram\.me|instagram\.com|facebook\.com|tiktok\.com)/i.test(text);
  },

  severityRank(s) {
    return { null: 0, low: 1, medium: 2, high: 3, critical: 4 }[s] || 0;
  },

  severityScore(s) {
    return { low: 15, medium: 35, high: 60, critical: 90 }[s] || 0;
  },

  // קבע איזו פעולה לבצע לפי רמת חומרה
  decideAction(severity) {
    return {
      low: 'warned',       // טיפ רך
      medium: 'rewritten', // החלפה חכמה
      high: 'blocked',     // חסימה
      critical: 'suspended' // השעיה
    }[severity] || 'allowed';
  }
};

// ============================================
// Initialization - אתחול
// ============================================
document.addEventListener('DOMContentLoaded', async () => {
  await loadAll();
  setupTabs();
  setupFilters();
  setupSyncListener();
  updateLastSync();
  setInterval(updateLastSync, 30000);
});

async function loadAll() {
  state.words = await DataLayer.getWords();
  state.incidents = await DataLayer.getIncidents();
  state.settings = await DataLayer.getSettings();
  renderAll();
}

function renderAll() {
  renderWords();
  renderIncidents();
  renderSettings();
  renderKPIs();
}

// ============================================
// Tabs
// ============================================
function setupTabs() {
  document.querySelectorAll('.tab').forEach(tab => {
    tab.addEventListener('click', () => {
      document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
      document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
      tab.classList.add('active');
      document.getElementById(`tab-${tab.dataset.tab}`).classList.add('active');
    });
  });
}

function setupFilters() {
  document.querySelectorAll('.filter-btn[data-filter]').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.filter-btn[data-filter]').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      state.filter = btn.dataset.filter;
      renderWords();
    });
  });

  document.querySelectorAll('.filter-btn[data-incident-filter]').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.filter-btn[data-incident-filter]').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      state.incidentFilter = btn.dataset.incidentFilter;
      renderIncidents();
    });
  });
}

// ============================================
// Words Management - ניהול מילים
// ============================================
async function addWord() {
  const input = document.getElementById('newWordInput');
  const category = document.getElementById('newWordCategory').value;
  const severity = document.getElementById('newWordSeverity').value;
  const text = input.value.trim();

  if (!text) {
    showToast('יש להקליד מילה', 'error');
    return;
  }

  // בדוק כפילות
  if (state.words.some(w => w.text.toLowerCase() === text.toLowerCase())) {
    showToast('מילה זו כבר קיימת ברשימה', 'error');
    return;
  }

  const newWord = {
    id: 'w' + Date.now(),
    text,
    category,
    severity,
    notes: '',
    createdAt: Date.now(),
    hits: 0
  };

  state.words.unshift(newWord);
  await DataLayer.saveWords(state.words);

  input.value = '';
  renderWords();
  renderKPIs();
  showToast(`המילה "${text}" נוספה בהצלחה`);
}

async function deleteWord(id) {
  if (!confirm('למחוק את המילה הזו לצמיתות?')) return;

  const word = state.words.find(w => w.id === id);
  state.words = state.words.filter(w => w.id !== id);
  await DataLayer.saveWords(state.words);

  renderWords();
  renderKPIs();
  showToast(`המילה "${word.text}" נמחקה`);
}

function editWord(id) {
  const word = state.words.find(w => w.id === id);
  if (!word) return;

  state.editingWordId = id;
  document.getElementById('editWordText').value = word.text;
  document.getElementById('editWordCategory').value = word.category;
  document.getElementById('editWordSeverity').value = word.severity;
  document.getElementById('editWordNotes').value = word.notes || '';
  document.getElementById('editModal').classList.add('show');
}

function closeModal() {
  document.getElementById('editModal').classList.remove('show');
  state.editingWordId = null;
}

async function saveEdit() {
  if (!state.editingWordId) return;

  const word = state.words.find(w => w.id === state.editingWordId);
  if (!word) return;

  word.text = document.getElementById('editWordText').value.trim();
  word.category = document.getElementById('editWordCategory').value;
  word.severity = document.getElementById('editWordSeverity').value;
  word.notes = document.getElementById('editWordNotes').value;

  await DataLayer.saveWords(state.words);
  closeModal();
  renderWords();
  showToast('השינויים נשמרו');
}

function renderWords() {
  const grid = document.getElementById('wordsGrid');
  const search = document.getElementById('searchWords').value.toLowerCase();

  let filtered = state.words;

  if (state.filter !== 'all') {
    filtered = filtered.filter(w => w.category === state.filter);
  }

  if (search) {
    filtered = filtered.filter(w => w.text.toLowerCase().includes(search));
  }

  document.getElementById('wordCount').textContent = `${filtered.length} מילים`;

  if (filtered.length === 0) {
    grid.innerHTML = `
      <div class="empty-state" style="grid-column: 1 / -1;">
        <div class="empty-state-emoji">🔍</div>
        <p>לא נמצאו מילים</p>
      </div>
    `;
    return;
  }

  grid.innerHTML = filtered.map(w => `
    <div class="word-card severity-${w.severity}">
      <div class="word-info">
        <div class="word-text">${escapeHtml(w.text)}</div>
        <div class="word-meta">
          <span>${getCategoryLabel(w.category)}</span>
          <span>·</span>
          <span>${getSeverityLabel(w.severity)}</span>
          ${w.hits ? `<span>·</span><span>${w.hits} פעמים</span>` : ''}
        </div>
      </div>
      <div class="word-actions">
        <button class="icon-btn" onclick="editWord('${w.id}')" title="ערוך">✏️</button>
        <button class="icon-btn delete" onclick="deleteWord('${w.id}')" title="מחק">🗑️</button>
      </div>
    </div>
  `).join('');
}

// ============================================
// Test Messages - בדיקת הודעות
// ============================================
function setTestText(text) {
  document.getElementById('testMessageInput').value = text;
  testMessage();
}

function testMessage() {
  const message = document.getElementById('testMessageInput').value;
  const result = DetectionEngine.check(message, state.words, state.settings);
  const resultEl = document.getElementById('testResult');

  if (!message.trim()) {
    resultEl.classList.remove('show');
    return;
  }

  resultEl.classList.add('show');
  resultEl.className = 'test-result show';

  if (!result.detected) {
    resultEl.classList.add('safe');
    resultEl.innerHTML = `
      <div style="display:flex; align-items:center; gap:8px; font-weight:500; margin-bottom:6px;">
        ✅ ההודעה נקייה
      </div>
      <p style="font-size:13px; line-height:1.6;">לא זוהה ניסיון עקיפה. המערכת תאפשר לשלוח את ההודעה.</p>
    `;
    return;
  }

  const action = DetectionEngine.decideAction(result.severity);
  const actionDetails = getActionDetails(action);

  resultEl.classList.add(actionDetails.class);

  resultEl.innerHTML = `
    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:10px;">
      <div style="font-weight:500; font-size:14px;">${actionDetails.emoji} ${actionDetails.title}</div>
      <div style="background:rgba(255,255,255,0.5); padding:4px 10px; border-radius:6px; font-size:12px;">
        ציון סיכון: <strong>${result.score}</strong>/100
      </div>
    </div>
    <p style="font-size:12px; line-height:1.6; margin-bottom:10px;">${actionDetails.description}</p>
    <div style="background:rgba(255,255,255,0.5); padding:10px; border-radius:6px; margin-bottom:8px;">
      <div style="font-size:11px; opacity:0.8; margin-bottom:4px;">זוהו המילים:</div>
      <div style="font-size:13px;">
        ${result.matches.map(m => `<span style="background:white; padding:2px 8px; border-radius:6px; margin-left:4px; display:inline-block; margin-bottom:4px;">${escapeHtml(m.word)}</span>`).join('')}
      </div>
    </div>
    <div style="font-size:11px; opacity:0.7;">רמה: ${getSeverityLabel(result.severity)}</div>
  `;
}

// ============================================
// Incidents - תקריות
// ============================================
function renderIncidents() {
  const list = document.getElementById('incidentsList');
  let filtered = state.incidents;

  if (state.incidentFilter !== 'all') {
    filtered = filtered.filter(i => i.severity === state.incidentFilter);
  }

  if (filtered.length === 0) {
    list.innerHTML = `
      <div class="empty-state">
        <div class="empty-state-emoji">✨</div>
        <p>אין תקריות בקטגוריה זו</p>
      </div>
    `;
    return;
  }

  list.innerHTML = filtered.map(i => `
    <div class="incident ${i.severity}">
      <div class="incident-header">
        <div class="badges">
          <span class="badge ${i.severity}">${getSeverityLabel(i.severity)} · ${i.riskScore}</span>
          <span class="badge neutral">${i.detectionMethod}</span>
          ${i.action === 'blocked' ? '<span class="badge high">נחסם</span>' : ''}
          ${i.action === 'rewritten' ? '<span class="badge medium">הוחלף</span>' : ''}
          ${i.action === 'warned' ? '<span class="badge low">אזהרה</span>' : ''}
        </div>
        <span style="font-size:11px; color:#666;">${timeAgo(i.timestamp)}</span>
      </div>
      <div class="incident-message">
        ${highlightMatches(i.message, i.matchedWords)}
      </div>
      <div class="incident-meta">
        <span>👤 ${escapeHtml(i.userName)}</span>
        <span>💬 ${escapeHtml(i.chatPartner || '—')}</span>
        <span>🆔 ${i.userId}</span>
      </div>
    </div>
  `).join('');
}

function loadIncidents() {
  renderIncidents();
  showToast('התקריות רועננו');
}

// ============================================
// Settings
// ============================================
function renderSettings() {
  document.getElementById('sensitivitySlider').value = state.settings.sensitivity;
  document.getElementById('sensitivityValue').textContent = state.settings.sensitivity;
  document.getElementById('detectSpaces').checked = state.settings.detectSpaces;
  document.getElementById('detectLeetspeak').checked = state.settings.detectLeetspeak;
  document.getElementById('detectEmoji').checked = state.settings.detectEmoji;
  document.getElementById('detectPhoneNumbers').checked = state.settings.detectPhoneNumbers;
  document.getElementById('detectLinks').checked = state.settings.detectLinks;
}

function updateSensitivity(value) {
  document.getElementById('sensitivityValue').textContent = value;
  state.settings.sensitivity = parseInt(value);
}

async function saveSettings() {
  state.settings = {
    sensitivity: parseInt(document.getElementById('sensitivitySlider').value),
    detectSpaces: document.getElementById('detectSpaces').checked,
    detectLeetspeak: document.getElementById('detectLeetspeak').checked,
    detectEmoji: document.getElementById('detectEmoji').checked,
    detectPhoneNumbers: document.getElementById('detectPhoneNumbers').checked,
    detectLinks: document.getElementById('detectLinks').checked
  };
  await DataLayer.saveSettings(state.settings);
  showToast('ההגדרות נשמרו');
}

function exportData() {
  const data = {
    words: state.words,
    settings: state.settings,
    incidents: state.incidents,
    exportedAt: new Date().toISOString()
  };
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `chatguard-export-${Date.now()}.json`;
  a.click();
  URL.revokeObjectURL(url);
  showToast('הנתונים יוצאו בהצלחה');
}

// ============================================
// KPIs
// ============================================
async function renderKPIs() {
  const stats = await DataLayer.getStats();
  document.getElementById('kpiTotalWords').textContent = stats.totalWords;
  document.getElementById('kpiAttempts').textContent = stats.attemptsToday;
  document.getElementById('kpiBlocked').textContent = stats.blockedToday;
  document.getElementById('kpiSuspicious').textContent = stats.suspiciousUsers;
}

// ============================================
// Sync Listener - מאזין לשינויים
// ============================================
function setupSyncListener() {
  window.addEventListener('chatguard-sync', (e) => {
    console.log('Sync event:', e.detail);
    updateLastSync();
  });

  // Multi-tab sync: אם הדשבורד פתוח ב-2 טאבים, הם יסתנכרנו
  window.addEventListener('storage', async (e) => {
    if (e.key && e.key.startsWith('chatguard_')) {
      await loadAll();
      showToast('נתונים סונכרנו מטאב אחר');
    }
  });
}

function updateLastSync() {
  document.getElementById('lastSync').textContent = 'סונכרן ' + new Date().toLocaleTimeString('he-IL', { hour: '2-digit', minute: '2-digit' });
}

// ============================================
// Helpers
// ============================================
function getCategoryLabel(cat) {
  return { payment: 'תשלומים', contact: 'פרטי קשר', external: 'חיצוניות', custom: 'מותאם' }[cat] || cat;
}

function getSeverityLabel(sev) {
  return { low: 'נמוך', medium: 'בינוני', high: 'גבוה', critical: 'קריטי' }[sev] || sev;
}

function getActionDetails(action) {
  return {
    warned: { class: 'warning', emoji: '💡', title: 'טיפ רך ישלח', description: 'ההודעה תיעבור, אבל המשתמש יקבל טיפ בטיחות.' },
    rewritten: { class: 'warning', emoji: '✏️', title: 'החלפה חכמה', description: 'המערכת תציע למשתמש ניסוח חלופי בטוח.' },
    blocked: { class: 'blocked', emoji: '🚫', title: 'ההודעה תיחסם', description: 'ההודעה לא תשלח. המשתמש יקבל הסבר.' },
    suspended: { class: 'blocked', emoji: '🔒', title: 'החשבון יושהה', description: 'ההודעה נחסמת והחשבון יועבר לבדיקה ידנית.' }
  }[action];
}

function highlightMatches(message, matchedWords) {
  let result = escapeHtml(message);
  matchedWords.forEach(word => {
    if (typeof word === 'string' && !word.includes('(')) {
      const regex = new RegExp(escapeRegex(word), 'gi');
      result = result.replace(regex, m => `<span class="incident-highlight">${m}</span>`);
    }
  });
  return result;
}

function timeAgo(timestamp) {
  const seconds = Math.floor((Date.now() - timestamp) / 1000);
  if (seconds < 60) return 'לפני ' + seconds + ' שניות';
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return 'לפני ' + minutes + ' דקות';
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return 'לפני ' + hours + ' שעות';
  const days = Math.floor(hours / 24);
  return 'לפני ' + days + ' ימים';
}

function isToday(timestamp) {
  const d = new Date(timestamp);
  const today = new Date();
  return d.toDateString() === today.toDateString();
}

function escapeHtml(str) {
  const div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}

function escapeRegex(str) {
  return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function showToast(message, type = 'success') {
  const toast = document.getElementById('toast');
  toast.textContent = message;
  toast.className = 'toast show' + (type === 'error' ? ' error' : '');
  setTimeout(() => toast.classList.remove('show'), 3000);
}
