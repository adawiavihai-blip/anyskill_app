import 'package:flutter/material.dart';

/// Single source of truth for the app version.
/// Change this ONE constant and the new number appears everywhere
/// (login screen, admin panel, wherever it's referenced).
const String appVersion = '9.0.5';

// זו הרשימה המרכזית. כל האפליקציה תמשוך מכאן את השמות.
// אם תשנה כאן ל"כושר", זה ישתנה אוטומטית גם ב"גלה" וגם ב"עריכה".
// ignore: constant_identifier_names
const List<Map<String, dynamic>> APP_CATEGORIES = [
  {'name': 'שיפוצים',       'icon': Icons.build,              'iconName': 'build',              'img': 'https://images.unsplash.com/photo-1581094794329-c8112a89af12?w=500'},
  {'name': 'ניקיון',         'icon': Icons.cleaning_services,  'iconName': 'cleaning_services',  'img': 'https://images.unsplash.com/photo-1581578731548-c64695cc6958?w=500'},
  {'name': 'צילום',          'icon': Icons.camera_alt,         'iconName': 'camera_alt',         'img': 'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?w=500'},
  {'name': 'אימון כושר',    'icon': Icons.fitness_center,     'iconName': 'fitness_center',     'img': 'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?w=500'},
  {'name': 'שיעורים פרטיים','icon': Icons.school,             'iconName': 'school',             'img': 'https://images.unsplash.com/photo-1497633762265-9d179a990aa6?w=500'},
  {'name': 'עיצוב גרפי',   'icon': Icons.palette,            'iconName': 'palette',            'img': 'https://images.unsplash.com/photo-1558655146-d09347e92766?w=500'},
];

/// Resolves a raw serviceType string (which may be a variant, typo, or
/// plural/singular mismatch) to its canonical APP_CATEGORIES name.
///
/// Algorithm: word-level keyword overlap.
///   "מאמני כושר"  → {'מאמני','כושר'} ∩ {'אימון','כושר'} = {'כושר'} → 'אימון כושר' ✓
///   "כושר אישי"   → {'כושר','אישי'}  ∩ {'אימון','כושר'} = {'כושר'} → 'אימון כושר' ✓
///   "אימון כושר"  → exact match                                       → 'אימון כושר' ✓
///   "צלם"         → no overlap with any category                       → 'צלם' (unchanged)
///
/// Returns [rawType] unchanged when no category scores at least 1 keyword match,
/// preserving the existing behaviour for categories that are already canonical.
String resolveCanonicalCategory(String rawType) {
  if (rawType.isEmpty) return rawType;

  // Fast path — already an exact canonical name.
  final canonicalNames = APP_CATEGORIES
      .map((c) => c['name'] as String)
      .toList(growable: false);
  if (canonicalNames.contains(rawType)) return rawType;

  // Extract whole words (≥ 2 chars) from the raw string.
  final rawWords = rawType
      .split(RegExp(r'\s+'))
      .where((w) => w.length >= 2)
      .toSet();

  String bestMatch = rawType;
  int    bestScore = 0;

  for (final name in canonicalNames) {
    final nameWords = name.split(RegExp(r'\s+')).toSet();
    final overlap   = rawWords.where(nameWords.contains).length;
    if (overlap > bestScore) {
      bestScore = overlap;
      bestMatch = name;
    }
  }

  return bestMatch;
}

/// Sub-categories per category.
/// Key = category name (matches APP_CATEGORIES 'name').
/// Value = ordered list of sub-category strings.
// ignore: constant_identifier_names
const Map<String, List<String>> APP_SUB_CATEGORIES = {
  'שיפוצים': [
    'חשמל',
    'אינסטלציה',
    'צביעה',
    'ריצוף',
    'גבס ותקרות',
    'נגרות',
    'מיזוג אוויר',
    'שיפוץ כללי',
  ],
  'ניקיון': [
    'ניקיון בית',
    'ניקיון משרד',
    'שטיחים וריפודים',
    'חלונות',
    'ניקוי אחרי שיפוץ',
    'חיטוי והדברה',
  ],
  'צילום': [
    'חתונות ואירועים',
    'פורטרט',
    'מוצרים ומסחר',
    'אדריכלות ונדלן',
    'וידאו וסרטים',
    'תיעוד ספורט',
  ],
  'אימון כושר': [
    'כושר כללי',
    'יוגה',
    'פילאטיס',
    'ריצה וסיבולת',
    'אומנויות לחימה',
    'שחייה',
    'תזונה וספורט',
  ],
  'שיעורים פרטיים': [
    'מתמטיקה',
    'אנגלית',
    'פיזיקה וכימיה',
    'תכנות ומחשבים',
    'ספרות ועברית',
    'מוזיקה',
    'הכנה לבחינות',
  ],
  'עיצוב גרפי': [
    'לוגו ומיתוג',
    'סושיאל מדיה',
    'עיצוב אתרים (UI/UX)',
    'אינפוגרפיקה',
    'אריזה ומוצר',
    'הדפסה ודיגיטל',
  ],
};