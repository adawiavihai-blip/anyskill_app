-- =============================================================
-- Chat Guard AI - Database Schema
-- =============================================================
-- מבנה טבלאות לבסיס הנתונים.
-- תואם: PostgreSQL, MySQL, Supabase. (לFirebase - ראה הערות בסוף)
-- =============================================================

-- Table 1: מילות חסימה
-- כאן נשמרות כל המילים שהאדמין מגדיר
CREATE TABLE blocked_words (
  id VARCHAR(50) PRIMARY KEY,
  text VARCHAR(255) NOT NULL UNIQUE,
  category VARCHAR(20) NOT NULL DEFAULT 'custom',
  -- categories: payment, contact, external, custom
  severity VARCHAR(20) NOT NULL DEFAULT 'medium',
  -- severities: low, medium, high, critical
  notes TEXT,
  hits INT DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  created_by VARCHAR(50),
  updated_at TIMESTAMP,
  is_active BOOLEAN DEFAULT TRUE
);

CREATE INDEX idx_blocked_words_category ON blocked_words(category);
CREATE INDEX idx_blocked_words_severity ON blocked_words(severity);
CREATE INDEX idx_blocked_words_active ON blocked_words(is_active);

-- Table 2: תקריות (כל ניסיון זיהוי)
CREATE TABLE incidents (
  id VARCHAR(50) PRIMARY KEY,
  user_id VARCHAR(50) NOT NULL,
  user_name VARCHAR(255),
  chat_id VARCHAR(50),
  chat_partner_id VARCHAR(50),
  chat_partner_name VARCHAR(255),
  message TEXT NOT NULL,
  matched_words JSON NOT NULL,
  -- array: ["מזומן", "ביט"]
  severity VARCHAR(20) NOT NULL,
  action VARCHAR(20) NOT NULL,
  -- actions: allowed, warned, rewritten, blocked, suspended
  detection_methods JSON,
  -- array: ["keyword", "semantic", "phone"]
  risk_score INT DEFAULT 0,
  timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  reviewed BOOLEAN DEFAULT FALSE,
  reviewer_id VARCHAR(50),
  review_note TEXT
);

CREATE INDEX idx_incidents_user ON incidents(user_id);
CREATE INDEX idx_incidents_timestamp ON incidents(timestamp DESC);
CREATE INDEX idx_incidents_severity ON incidents(severity);
CREATE INDEX idx_incidents_chat ON incidents(chat_id);

-- Table 3: הגדרות מערכת
CREATE TABLE settings (
  id VARCHAR(50) PRIMARY KEY,
  sensitivity INT DEFAULT 65,
  detect_spaces BOOLEAN DEFAULT TRUE,
  detect_leetspeak BOOLEAN DEFAULT TRUE,
  detect_emoji BOOLEAN DEFAULT TRUE,
  detect_phone_numbers BOOLEAN DEFAULT TRUE,
  detect_links BOOLEAN DEFAULT TRUE,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_by VARCHAR(50)
);

-- הכנס שורה ראשונית להגדרות
INSERT INTO settings (id) VALUES ('main');

-- Table 4: ציון סיכון למשתמש (cache לביצועים)
CREATE TABLE user_risk_scores (
  user_id VARCHAR(50) PRIMARY KEY,
  score INT NOT NULL DEFAULT 0,
  incidents_count INT DEFAULT 0,
  last_incident_at TIMESTAMP,
  linked_users JSON,
  -- array of user IDs that are part of same fraud ring
  calculated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_risk_scores_score ON user_risk_scores(score DESC);

-- Table 5: דיווחים על משתמשים
CREATE TABLE user_reports (
  id VARCHAR(50) PRIMARY KEY,
  reported_user_id VARCHAR(50) NOT NULL,
  reporter_user_id VARCHAR(50) NOT NULL,
  reason TEXT,
  chat_id VARCHAR(50),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  resolved BOOLEAN DEFAULT FALSE
);

CREATE INDEX idx_user_reports_reported ON user_reports(reported_user_id);

-- Table 6: ערעורים של משתמשים שנחסמו
CREATE TABLE appeals (
  id VARCHAR(50) PRIMARY KEY,
  user_id VARCHAR(50) NOT NULL,
  incident_id VARCHAR(50),
  reason TEXT NOT NULL,
  status VARCHAR(20) DEFAULT 'pending',
  -- statuses: pending, approved, rejected
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  resolved_at TIMESTAMP,
  resolver_id VARCHAR(50),
  resolution_note TEXT
);

-- =============================================================
-- נתונים התחלתיים - מילים בסיסיות
-- =============================================================

INSERT INTO blocked_words (id, text, category, severity, notes) VALUES
  ('w_init_1', 'מזומן', 'payment', 'high', 'ברירת מחדל'),
  ('w_init_2', 'ביט', 'payment', 'high', 'ברירת מחדל'),
  ('w_init_3', 'paybox', 'payment', 'high', 'ברירת מחדל'),
  ('w_init_4', 'cash', 'payment', 'medium', 'ברירת מחדל'),
  ('w_init_5', 'כסף', 'payment', 'medium', 'ברירת מחדל'),
  ('w_init_6', 'העברה בנקאית', 'payment', 'medium', 'ברירת מחדל'),
  ('w_init_7', 'וואטסאפ', 'contact', 'high', 'ברירת מחדל'),
  ('w_init_8', 'whatsapp', 'contact', 'high', 'ברירת מחדל'),
  ('w_init_9', 'טלגרם', 'contact', 'high', 'ברירת מחדל'),
  ('w_init_10', 'טלפון', 'contact', 'medium', 'ברירת מחדל'),
  ('w_init_11', 'wa.me', 'external', 'critical', 'לינק ישיר'),
  ('w_init_12', 't.me', 'external', 'critical', 'לינק ישיר');


-- =============================================================
-- הוראות עבור Firebase Firestore
-- =============================================================
-- Firebase לא משתמש ב-SQL. במקום זה, צור את ה-Collections הבאות:
--
-- Collection: blocked_words
--   Document structure:
--   { id, text, category, severity, notes, hits, createdAt, isActive }
--
-- Collection: incidents
--   { id, userId, userName, message, matchedWords, severity, action,
--     detectionMethods, riskScore, timestamp, reviewed }
--
-- Collection: settings
--   Document ID: "main"
--   { sensitivity, detectSpaces, detectLeetspeak, detectEmoji,
--     detectPhoneNumbers, detectLinks }
--
-- Collection: user_risk_scores
--   Document ID = userId
--   { score, incidentsCount, lastIncidentAt, linkedUsers }
--
-- =============================================================
-- הוראות עבור Supabase
-- =============================================================
-- הרץ את ה-SQL הזה ישירות ב-SQL Editor של Supabase.
-- לאחר מכן הפעל Row Level Security (RLS) בהתאם לצרכי האבטחה שלך.
-- =============================================================
