/**
 * Chat Guard — detection engine (server-side)
 *
 * Ported from `docs/ui-specs/chat-guard/backend/detection-engine.js` with
 * small adaptations for our Firestore schema + Cloud Functions runtime:
 *   • words come from `blocked_words` where `isActive == true`
 *   • settings come from `chat_guard_settings/main` (single doc)
 *   • emits a result object that `checkChatMessage` wraps into the
 *     callable response
 *
 * Pure function — no Firestore I/O here. The caller passes words + settings.
 */

const CATEGORIES = {
  PAYMENT: 'payment',
  CONTACT: 'contact',
  EXTERNAL: 'external',
  CUSTOM: 'custom',
};

const SEVERITY = {
  LOW: 'low',
  MEDIUM: 'medium',
  HIGH: 'high',
  CRITICAL: 'critical',
};

const ACTIONS = {
  ALLOW: 'allowed',
  WARN: 'warned',
  REWRITE: 'rewritten',
  BLOCK: 'blocked',
  SUSPEND: 'suspended',
};

const SEVERITY_SCORES = {
  [SEVERITY.LOW]: 15,
  [SEVERITY.MEDIUM]: 35,
  [SEVERITY.HIGH]: 60,
  [SEVERITY.CRITICAL]: 90,
};

const SEVERITY_ACTIONS = {
  [SEVERITY.LOW]: ACTIONS.WARN,
  [SEVERITY.MEDIUM]: ACTIONS.REWRITE,
  [SEVERITY.HIGH]: ACTIONS.BLOCK,
  [SEVERITY.CRITICAL]: ACTIONS.SUSPEND,
};

const SMART_REPLACEMENTS = {
  'מזומן': 'דרך האפליקציה',
  'cash': 'דרך האפליקציה',
  'ביט': 'דרך האפליקציה',
  'paybox': 'דרך האפליקציה',
  'העברה בנקאית': 'דרך האפליקציה',
  'וואטסאפ': "בצ'אט כאן",
  'whatsapp': "בצ'אט כאן",
  'טלגרם': "בצ'אט כאן",
  'telegram': "בצ'אט כאן",
};

const DEFAULT_SETTINGS = {
  enabled: false,
  sensitivity: 65,
  detectSpaces: true,
  detectLeetspeak: true,
  detectEmoji: true,
  detectPhoneNumbers: true,
  detectLinks: true,
};

// ── Main detection function ─────────────────────────────────────────────────

/**
 * Checks a message and returns a decision object.
 *
 * @param {string} message
 * @param {{
 *   words: Array<{id,text,category,severity,isActive}>,
 *   settings: Object,
 *   userRiskScore?: number
 * }} ctx
 * @returns {{
 *   detected: boolean, action: string, severity: string|null,
 *   score: number, matches: Array, rewrite: string|null, reason: string|null
 * }}
 */
function checkMessage(message, ctx = {}) {
  const words = ctx.words || [];
  const settings = { ...DEFAULT_SETTINGS, ...(ctx.settings || {}) };
  const userRiskScore = ctx.userRiskScore || 0;

  if (!message || !String(message).trim()) {
    return emptyResult();
  }

  const normalized = normalizeText(message, settings);
  const matches = [];
  let totalScore = 0;
  let maxSeverity = null;

  // Layer 1 — keyword matching against the active word list
  for (const word of words) {
    if (word.isActive === false) continue;
    const wordNorm = normalizeText(word.text, settings);
    if (wordNorm && normalized.includes(wordNorm)) {
      matches.push({
        word: word.text,
        category: word.category,
        severity: word.severity,
        matchType: 'keyword',
        wordId: word.id,
      });
      totalScore += SEVERITY_SCORES[word.severity] || 0;
      if (rankSeverity(word.severity) > rankSeverity(maxSeverity)) {
        maxSeverity = word.severity;
      }
    }
  }

  // Layer 2 — phone number detection
  if (settings.detectPhoneNumbers) {
    const phoneMatch = detectPhoneNumber(message);
    if (phoneMatch) {
      matches.push({
        word: phoneMatch,
        category: CATEGORIES.CONTACT,
        severity: SEVERITY.HIGH,
        matchType: 'phone',
      });
      totalScore += SEVERITY_SCORES[SEVERITY.HIGH];
      if (rankSeverity(SEVERITY.HIGH) > rankSeverity(maxSeverity)) {
        maxSeverity = SEVERITY.HIGH;
      }
    }
  }

  // Layer 3 — external links
  if (settings.detectLinks) {
    const linkMatch = detectExternalLink(message);
    if (linkMatch) {
      matches.push({
        word: linkMatch,
        category: CATEGORIES.EXTERNAL,
        severity: SEVERITY.CRITICAL,
        matchType: 'link',
      });
      totalScore += SEVERITY_SCORES[SEVERITY.CRITICAL];
      maxSeverity = SEVERITY.CRITICAL;
    }
  }

  // Layer 4 — semantic patterns
  const semanticMatch = detectSemanticPatterns(message);
  if (semanticMatch) {
    matches.push({
      word: semanticMatch.phrase,
      category: CATEGORIES.CUSTOM,
      severity: semanticMatch.severity,
      matchType: 'semantic',
    });
    totalScore += SEVERITY_SCORES[semanticMatch.severity];
    if (rankSeverity(semanticMatch.severity) > rankSeverity(maxSeverity)) {
      maxSeverity = semanticMatch.severity;
    }
  }

  // Layer 5 — user risk adjustment (bad history → harder threshold)
  if (userRiskScore > 70) {
    totalScore *= 1.3;
    if (maxSeverity === SEVERITY.MEDIUM) maxSeverity = SEVERITY.HIGH;
  } else if (userRiskScore > 50) {
    totalScore *= 1.15;
  }

  if (matches.length === 0) return emptyResult();

  // Sensitivity threshold — below threshold, soften to LOW (tip only)
  const threshold = 100 - (settings.sensitivity || 65);
  if (totalScore < threshold) {
    maxSeverity = SEVERITY.LOW;
  }

  const action = SEVERITY_ACTIONS[maxSeverity];
  const rewrite =
    action === ACTIONS.REWRITE ? generateSmartRewrite(message, matches) : null;

  return {
    detected: true,
    action,
    severity: maxSeverity,
    score: Math.min(100, Math.round(totalScore)),
    matches,
    rewrite,
    reason: generateReason(matches),
  };
}

// ── Helpers ─────────────────────────────────────────────────────────────────

function emptyResult() {
  return {
    detected: false,
    action: ACTIONS.ALLOW,
    severity: null,
    score: 0,
    matches: [],
    rewrite: null,
    reason: null,
  };
}

function normalizeText(text, settings = {}) {
  let t = String(text || '').toLowerCase();

  if (settings.detectSpaces !== false) {
    t = removeSpacedLetters(t);
  }

  if (settings.detectLeetspeak !== false) {
    t = t
      .replace(/0/g, 'o')
      .replace(/1/g, 'i')
      .replace(/3/g, 'e')
      .replace(/4/g, 'a')
      .replace(/5/g, 's')
      .replace(/7/g, 't');
  }

  if (settings.detectEmoji !== false) {
    t = t
      .replace(/💵|💰|💸|🤑/g, 'מזומן')
      .replace(/📞|☎️|📱/g, 'טלפון')
      .replace(/💬|✉️|📩/g, 'הודעה');
  }

  t = t.replace(/[.·_\-*•]/g, '');
  t = t.replace(/\s+/g, ' ').trim();
  return t;
}

function removeSpacedLetters(text) {
  return text.replace(/(\S)(?:\s(\S))+/g, (match) => {
    const parts = match.split(/\s+/);
    if (parts.every((p) => p.length === 1)) return parts.join('');
    return match;
  });
}

function detectPhoneNumber(text) {
  const cleaned = String(text || '').replace(/[\s\-.\*·_]/g, '');

  const mobileMatch = cleaned.match(/05\d{8}/);
  if (mobileMatch) return mobileMatch[0];

  const landlineMatch = cleaned.match(/0[2-4,8-9]\d{7}/);
  if (landlineMatch) return landlineMatch[0];

  const intlMatch = cleaned.match(/\+972\d{9}/);
  if (intlMatch) return intlMatch[0];

  const wordsNumbers = ['אפס', 'אחת', 'שתיים', 'שלוש', 'ארבע', 'חמש', 'שש', 'שבע', 'שמונה', 'תשע'];
  let wordCount = 0;
  wordsNumbers.forEach((w) => {
    const m = String(text || '').match(new RegExp(w, 'g'));
    if (m) wordCount += m.length;
  });
  if (wordCount >= 7) return 'מספר במילים';

  return null;
}

function detectExternalLink(text) {
  const patterns = [
    { pattern: /wa\.me\/?\S*/i, name: 'wa.me' },
    { pattern: /t\.me\/?\S*/i, name: 't.me' },
    { pattern: /telegram\.me\/?\S*/i, name: 'telegram.me' },
    { pattern: /instagram\.com\/?\S*/i, name: 'instagram.com' },
    { pattern: /facebook\.com\/?\S*/i, name: 'facebook.com' },
    { pattern: /tiktok\.com\/?\S*/i, name: 'tiktok.com' },
    { pattern: /paypal\.me\/?\S*/i, name: 'paypal.me' },
  ];
  for (const { pattern, name } of patterns) {
    if (pattern.test(text)) return name;
  }
  return null;
}

function detectSemanticPatterns(text) {
  const lower = String(text || '').toLowerCase();
  const patterns = [
    { regex: /(נפגש|ניפגש|נסגור|נסדר).{0,15}(בצד|בחוץ|בקפה|פנים אל פנים)/, severity: SEVERITY.HIGH, phrase: 'הצעה לפגישה/סיכום בצד' },
    { regex: /(לסגור|לסדר|נסגור).{0,10}(בלעדיה|בלי|מחוץ)/, severity: SEVERITY.HIGH, phrase: 'הצעה לסגירה מחוץ לאפליקציה' },
    { regex: /(בלי|ללא|לחסוך).{0,10}(עמלה|אפליקציה|מערכת)/, severity: SEVERITY.CRITICAL, phrase: 'עקיפת עמלה' },
    { regex: /(זול יותר|הנחה|מוזל).{0,20}(ישיר|מחוץ)/, severity: SEVERITY.HIGH, phrase: 'הנחה מחוץ לאפליקציה' },
    { regex: /(תן|שלח|אשלח).{0,15}(טלפון|מספר|קשר|מייל)/, severity: SEVERITY.MEDIUM, phrase: 'בקשת פרטי קשר' },
    { regex: /(העבר|תעביר).{0,20}(לאשה|לאשתי|לבעלי|בצד)/, severity: SEVERITY.CRITICAL, phrase: 'העברה דרך אדם שלישי' },
  ];
  for (const p of patterns) {
    if (p.regex.test(lower)) return { phrase: p.phrase, severity: p.severity };
  }
  return null;
}

function generateSmartRewrite(original, matches) {
  let rewritten = original;
  for (const match of matches) {
    const word = String(match.word || '').toLowerCase();
    if (SMART_REPLACEMENTS[word]) {
      const regex = new RegExp(escapeRegex(match.word), 'gi');
      rewritten = rewritten.replace(regex, SMART_REPLACEMENTS[word]);
    }
  }
  if (rewritten === original) {
    rewritten = 'אשמח להמשיך את העסקה דרך האפליקציה';
  }
  return rewritten;
}

function generateReason(matches) {
  const categories = [...new Set(matches.map((m) => m.category))];
  const reasons = {
    [CATEGORIES.PAYMENT]: 'זוהה ניסיון להעברת תשלום מחוץ לאפליקציה',
    [CATEGORIES.CONTACT]: 'זוהה ניסיון לשיתוף פרטי קשר',
    [CATEGORIES.EXTERNAL]: 'זוהה קישור לאפליקציה חיצונית',
    [CATEGORIES.CUSTOM]: 'זוהה דפוס חשוד',
  };
  return reasons[categories[0]] || 'זוהה ניסיון עקיפת המערכת';
}

function rankSeverity(s) {
  return ({ low: 1, medium: 2, high: 3, critical: 4 }[s]) || 0;
}

function escapeRegex(str) {
  return String(str).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

module.exports = {
  checkMessage,
  normalizeText,
  detectPhoneNumber,
  detectExternalLink,
  detectSemanticPatterns,
  CATEGORIES,
  SEVERITY,
  ACTIONS,
  DEFAULT_SETTINGS,
};
