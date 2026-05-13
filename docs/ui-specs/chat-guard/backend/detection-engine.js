/**
 * Chat Guard AI - Detection Engine (Backend)
 * =============================================
 * מנוע הזיהוי הראשי - גרסה מלאה עבור צד שרת.
 * עובד עם כל backend (Node.js, Serverless, Firebase Functions)
 *
 * שימוש:
 *   const { checkMessage } = require('./detection-engine');
 *   const result = await checkMessage(messageText, userId);
 */

// ============================================
// Configuration
// ============================================

const CATEGORIES = {
  PAYMENT: 'payment',
  CONTACT: 'contact',
  EXTERNAL: 'external',
  CUSTOM: 'custom'
};

const SEVERITY = {
  LOW: 'low',
  MEDIUM: 'medium',
  HIGH: 'high',
  CRITICAL: 'critical'
};

const ACTIONS = {
  ALLOW: 'allowed',
  WARN: 'warned',
  REWRITE: 'rewritten',
  BLOCK: 'blocked',
  SUSPEND: 'suspended'
};

// Severity → score mapping
const SEVERITY_SCORES = {
  [SEVERITY.LOW]: 15,
  [SEVERITY.MEDIUM]: 35,
  [SEVERITY.HIGH]: 60,
  [SEVERITY.CRITICAL]: 90
};

// Severity → action mapping
const SEVERITY_ACTIONS = {
  [SEVERITY.LOW]: ACTIONS.WARN,
  [SEVERITY.MEDIUM]: ACTIONS.REWRITE,
  [SEVERITY.HIGH]: ACTIONS.BLOCK,
  [SEVERITY.CRITICAL]: ACTIONS.SUSPEND
};

// Smart replacements - החלפה חכמה
const SMART_REPLACEMENTS = {
  'מזומן': 'דרך האפליקציה',
  'cash': 'דרך האפליקציה',
  'ביט': 'דרך האפליקציה',
  'paybox': 'דרך האפליקציה',
  'העברה בנקאית': 'דרך האפליקציה',
  'וואטסאפ': 'בצ\'אט כאן',
  'whatsapp': 'בצ\'אט כאן',
  'טלגרם': 'בצ\'אט כאן',
  'telegram': 'בצ\'אט כאן'
};

// ============================================
// Main Detection Function
// ============================================

/**
 * בודק הודעה ומחזיר אם יש ניסיון עקיפה
 *
 * @param {string} message - תוכן ההודעה
 * @param {Object} context - הקשר: userId, chatId, wordsList, settings, userRiskScore
 * @returns {Object} תוצאה: { detected, action, severity, score, matches, rewrite, reason }
 */
async function checkMessage(message, context = {}) {
  const {
    words = [],
    settings = getDefaultSettings(),
    userId = null,
    userRiskScore = 0,
    chatId = null
  } = context;

  // אם ההודעה ריקה
  if (!message || !message.trim()) {
    return {
      detected: false,
      action: ACTIONS.ALLOW,
      severity: null,
      score: 0,
      matches: [],
      rewrite: null,
      reason: null
    };
  }

  const normalized = normalizeText(message, settings);
  const matches = [];
  let totalScore = 0;
  let maxSeverity = null;

  // ---- Layer 1: Keyword matching ----
  for (const word of words) {
    const wordNorm = normalizeText(word.text, settings);
    if (normalized.includes(wordNorm)) {
      matches.push({
        word: word.text,
        category: word.category,
        severity: word.severity,
        matchType: 'keyword',
        wordId: word.id
      });
      totalScore += SEVERITY_SCORES[word.severity];
      if (rankSeverity(word.severity) > rankSeverity(maxSeverity)) {
        maxSeverity = word.severity;
      }
    }
  }

  // ---- Layer 2: Phone number detection ----
  if (settings.detectPhoneNumbers) {
    const phoneMatch = detectPhoneNumber(message);
    if (phoneMatch) {
      matches.push({
        word: phoneMatch,
        category: CATEGORIES.CONTACT,
        severity: SEVERITY.HIGH,
        matchType: 'phone'
      });
      totalScore += SEVERITY_SCORES[SEVERITY.HIGH];
      if (rankSeverity(SEVERITY.HIGH) > rankSeverity(maxSeverity)) {
        maxSeverity = SEVERITY.HIGH;
      }
    }
  }

  // ---- Layer 3: External links ----
  if (settings.detectLinks) {
    const linkMatch = detectExternalLink(message);
    if (linkMatch) {
      matches.push({
        word: linkMatch,
        category: CATEGORIES.EXTERNAL,
        severity: SEVERITY.CRITICAL,
        matchType: 'link'
      });
      totalScore += SEVERITY_SCORES[SEVERITY.CRITICAL];
      maxSeverity = SEVERITY.CRITICAL;
    }
  }

  // ---- Layer 4: Semantic patterns ----
  const semanticMatch = detectSemanticPatterns(message);
  if (semanticMatch) {
    matches.push({
      word: semanticMatch.phrase,
      category: CATEGORIES.CUSTOM,
      severity: semanticMatch.severity,
      matchType: 'semantic'
    });
    totalScore += SEVERITY_SCORES[semanticMatch.severity];
    if (rankSeverity(semanticMatch.severity) > rankSeverity(maxSeverity)) {
      maxSeverity = semanticMatch.severity;
    }
  }

  // ---- Layer 5: User risk adjustment ----
  // משתמש עם היסטוריה גרועה = סף נמוך יותר
  if (userRiskScore > 70) {
    totalScore *= 1.3;
    if (maxSeverity === SEVERITY.MEDIUM) maxSeverity = SEVERITY.HIGH;
  } else if (userRiskScore > 50) {
    totalScore *= 1.15;
  }

  // ---- No matches = allow ----
  if (matches.length === 0) {
    return {
      detected: false,
      action: ACTIONS.ALLOW,
      severity: null,
      score: 0,
      matches: [],
      rewrite: null,
      reason: null
    };
  }

  // ---- Apply sensitivity threshold ----
  const threshold = 100 - (settings.sensitivity || 65);
  if (totalScore < threshold) {
    // סף לא נחצה - טיפ רך
    maxSeverity = SEVERITY.LOW;
  }

  const action = SEVERITY_ACTIONS[maxSeverity];
  const rewrite = action === ACTIONS.REWRITE ? generateSmartRewrite(message, matches) : null;

  return {
    detected: true,
    action,
    severity: maxSeverity,
    score: Math.min(100, Math.round(totalScore)),
    matches,
    rewrite,
    reason: generateReason(matches, maxSeverity)
  };
}

// ============================================
// Text Normalization - נירמול טקסט
// ============================================

/**
 * מנרמל טקסט כדי לזהות הסוואות
 */
function normalizeText(text, settings = {}) {
  let t = text.toLowerCase();

  // 1. הסר רווחים בין אותיות בודדות
  //    "מ ז ו מ ן" → "מזומן"
  if (settings.detectSpaces !== false) {
    t = removeSpacedLetters(t);
  }

  // 2. Leetspeak: 0→o, 1→i, 3→e, 4→a, 5→s, 7→t
  if (settings.detectLeetspeak !== false) {
    t = t.replace(/0/g, 'o')
         .replace(/1/g, 'i')
         .replace(/3/g, 'e')
         .replace(/4/g, 'a')
         .replace(/5/g, 's')
         .replace(/7/g, 't');
  }

  // 3. Emojis → מילים
  if (settings.detectEmoji !== false) {
    t = t.replace(/💵|💰|💸|🤑/g, 'מזומן')
         .replace(/📞|☎️|📱/g, 'טלפון')
         .replace(/💬|✉️|📩/g, 'הודעה');
  }

  // 4. הסר סימני פיסוק נפוצים
  t = t.replace(/[.·_\-\*•]/g, '');

  // 5. הסר רווחים מרובים
  t = t.replace(/\s+/g, ' ').trim();

  return t;
}

function removeSpacedLetters(text) {
  // זיהוי סדרה של אותיות בודדות מופרדות ברווחים
  // "מ ז ו מ ן" → "מזומן"
  return text.replace(/(\S)(?:\s(\S))+/g, (match) => {
    const parts = match.split(/\s+/);
    // אם כל החלקים הם אות אחת → זו הסוואה
    if (parts.every(p => p.length === 1)) {
      return parts.join('');
    }
    return match;
  });
}

// ============================================
// Phone Number Detection
// ============================================
function detectPhoneNumber(text) {
  // הסר רווחים וסימני הפרדה
  const cleaned = text.replace(/[\s\-\.·_\*]/g, '');

  // מספר ישראלי נייד
  const mobileMatch = cleaned.match(/05\d{8}/);
  if (mobileMatch) return mobileMatch[0];

  // מספר קווי ישראלי
  const landlineMatch = cleaned.match(/0[2-4,8-9]\d{7}/);
  if (landlineMatch) return landlineMatch[0];

  // פורמט בינלאומי
  const intlMatch = cleaned.match(/\+972\d{9}/);
  if (intlMatch) return intlMatch[0];

  // מילים שמייצגות ספרות: "חמש אפס שבע"
  const wordsNumbers = ['אפס', 'אחת', 'שתיים', 'שלוש', 'ארבע', 'חמש', 'שש', 'שבע', 'שמונה', 'תשע'];
  let wordCount = 0;
  wordsNumbers.forEach(w => {
    const matches = text.match(new RegExp(w, 'g'));
    if (matches) wordCount += matches.length;
  });
  if (wordCount >= 7) return 'מספר במילים';

  return null;
}

// ============================================
// External Link Detection
// ============================================
function detectExternalLink(text) {
  const patterns = [
    { pattern: /wa\.me\/?\S*/i, name: 'wa.me' },
    { pattern: /t\.me\/?\S*/i, name: 't.me' },
    { pattern: /telegram\.me\/?\S*/i, name: 'telegram.me' },
    { pattern: /instagram\.com\/?\S*/i, name: 'instagram.com' },
    { pattern: /facebook\.com\/?\S*/i, name: 'facebook.com' },
    { pattern: /tiktok\.com\/?\S*/i, name: 'tiktok.com' },
    { pattern: /paypal\.me\/?\S*/i, name: 'paypal.me' }
  ];

  for (const { pattern, name } of patterns) {
    if (pattern.test(text)) return name;
  }
  return null;
}

// ============================================
// Semantic Patterns - ביטויים סמנטיים
// ============================================
function detectSemanticPatterns(text) {
  const lower = text.toLowerCase();

  // ביטויים שמרמזים על עסקה מחוץ לפלטפורמה
  const patterns = [
    // סיכום בצד
    { regex: /(נפגש|ניפגש|נסגור|נסדר).{0,15}(בצד|בחוץ|בקפה|פנים אל פנים)/, severity: SEVERITY.HIGH, phrase: 'הצעה לפגישה/סיכום בצד' },
    { regex: /(לסגור|לסדר|נסגור).{0,10}(בלעדיה|בלי|מחוץ)/, severity: SEVERITY.HIGH, phrase: 'הצעה לסגירה מחוץ לאפליקציה' },

    // עקיפת עמלה
    { regex: /(בלי|ללא|לחסוך).{0,10}(עמלה|אפליקציה|מערכת)/, severity: SEVERITY.CRITICAL, phrase: 'עקיפת עמלה' },
    { regex: /(זול יותר|הנחה|מוזל).{0,20}(ישיר|מחוץ)/, severity: SEVERITY.HIGH, phrase: 'הנחה מחוץ לאפליקציה' },

    // שיתוף פרטי קשר
    { regex: /(תן|שלח|אשלח).{0,15}(טלפון|מספר|קשר|מייל)/, severity: SEVERITY.MEDIUM, phrase: 'בקשת פרטי קשר' },

    // העברה בצד
    { regex: /(העבר|תעביר).{0,20}(לאשה|לאשתי|לבעלי|בצד)/, severity: SEVERITY.CRITICAL, phrase: 'העברה דרך אדם שלישי' }
  ];

  for (const p of patterns) {
    if (p.regex.test(lower)) {
      return { phrase: p.phrase, severity: p.severity };
    }
  }

  return null;
}

// ============================================
// Smart Rewrite - החלפה חכמה
// ============================================
function generateSmartRewrite(original, matches) {
  let rewritten = original;

  for (const match of matches) {
    const word = match.word.toLowerCase();
    if (SMART_REPLACEMENTS[word]) {
      const regex = new RegExp(escapeRegex(match.word), 'gi');
      rewritten = rewritten.replace(regex, SMART_REPLACEMENTS[word]);
    }
  }

  // אם לא השתנה כלום, הצע ניסוח כללי
  if (rewritten === original) {
    rewritten = 'אשמח להמשיך את העסקה דרך האפליקציה';
  }

  return rewritten;
}

// ============================================
// Reason Generation
// ============================================
function generateReason(matches, severity) {
  const categories = [...new Set(matches.map(m => m.category))];

  const reasons = {
    [CATEGORIES.PAYMENT]: 'זוהה ניסיון להעברת תשלום מחוץ לאפליקציה',
    [CATEGORIES.CONTACT]: 'זוהה ניסיון לשיתוף פרטי קשר',
    [CATEGORIES.EXTERNAL]: 'זוהה קישור לאפליקציה חיצונית',
    [CATEGORIES.CUSTOM]: 'זוהה דפוס חשוד'
  };

  return reasons[categories[0]] || 'זוהה ניסיון עקיפת המערכת';
}

// ============================================
// Helpers
// ============================================
function rankSeverity(s) {
  return { null: 0, low: 1, medium: 2, high: 3, critical: 4 }[s] || 0;
}

function escapeRegex(str) {
  return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
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
// Exports
// ============================================

// CommonJS (Node.js)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    checkMessage,
    normalizeText,
    detectPhoneNumber,
    detectExternalLink,
    detectSemanticPatterns,
    generateSmartRewrite,
    CATEGORIES,
    SEVERITY,
    ACTIONS
  };
}

// Browser / ES Modules
if (typeof window !== 'undefined') {
  window.ChatGuardDetection = {
    checkMessage,
    normalizeText,
    CATEGORIES,
    SEVERITY,
    ACTIONS
  };
}
