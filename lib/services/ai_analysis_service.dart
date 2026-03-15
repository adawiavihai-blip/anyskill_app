/// AnySkill — AI Request Analysis & Matchmaker Scoring
/// Pure Dart, no external API. Uses Hebrew keyword matching + weighted scoring.
library;

class RequestAnalysis {
  final String? suggestedCategory;
  final String urgency;   // 'urgent' | 'normal'
  final bool missingDate;
  final bool missingLocation;

  const RequestAnalysis({
    this.suggestedCategory,
    this.urgency = 'normal',
    this.missingDate = false,
    this.missingLocation = false,
  });

  bool get hasInsights =>
      suggestedCategory != null ||
      urgency == 'urgent' ||
      missingDate ||
      missingLocation;
}

class AiAnalysisService {
  AiAnalysisService._();

  // ── Category → Hebrew keyword map ────────────────────────────────────────
  static const Map<String, List<String>> _categoryKeywords = {
    'שרברבות': [
      'שרברב', 'ברז', 'צנרת', 'אינסטלציה', 'ניקוז', 'כיור', 'שירותים',
      'אמבטיה', 'דוד מים', 'נזילה', 'צינור', 'ביוב', 'מים', 'טיפטוף',
      'סתימה', 'ניסור',
    ],
    'חשמל': [
      'חשמלאי', 'חוט', 'שקע', 'מפסק', 'חשמל', 'תאורה', 'לוח חשמל',
      'מנורה', 'חיווט', 'פיוז', 'זרם', 'תקע', 'ממסר', 'גנרטור', 'מצבר',
    ],
    'ניקיון': [
      'ניקיון', 'ניקוי', 'שטיפה', 'עוזרת בית', 'טאטוא', 'שואב אבק',
      'חלונות', 'פרקט', 'שטיח', 'כביסה', 'בית נקי', 'דירה נקייה',
    ],
    'שיפוצים': [
      'שיפוץ', 'בנייה', 'צביעה', 'טיח', 'ריצוף', 'נגרות', 'גבס',
      'תקרה', 'קיר', 'אריחים', 'הרכבה', 'ריהוט', 'ארון', 'מדף', 'פרקט',
      'שפכטל', 'שפכטל', 'סיד', 'שינוי', 'חדר', 'מטבח',
    ],
    'גינון': [
      'גן', 'גינה', 'עשב', 'גיזום', 'עצים', 'שתילה', 'גינון', 'דשא',
      'פרחים', 'דישון', 'גדר', 'ענפים', 'עלים', 'מזרקה', 'ריסוס',
    ],
    'מחשבים וטכנולוגיה': [
      'מחשב', 'לפטופ', 'וירוס', 'תוכנה', 'IT', 'אינטרנט', 'wifi',
      'רשת', 'מדפסת', 'טלפון', 'סמארטפון', 'אייפד', 'טאבלט', 'Windows',
      'התקנה', 'הגדרה', 'שחזור', 'גיבוי', 'נתב',
    ],
    'הוראה פרטית': [
      'פרטי', 'שיעור', 'מתמטיקה', 'אנגלית', 'עברית', 'ביולוגיה',
      'פיזיקה', 'היסטוריה', 'לימוד', 'בגרות', 'מורה', 'תרגיל',
      'בחינה', 'מבחן', 'עזרה בלימודים', 'כתיבה',
    ],
    'עיצוב גרפי': [
      'עיצוב', 'לוגו', 'מיתוג', 'גרפי', 'אילוסטרציה', 'פוסטר', 'באנר',
      'אתר', 'UI', 'UX', 'brand', 'קריאייטיב', 'צבעים', 'פונט', 'canva',
    ],
    'צילום': [
      'צילום', 'צלם', 'מצלמה', 'תמונות', 'וידאו', 'קליפ', 'חתונה',
      'אירוע', 'פורטרט', 'סטודיו', 'רילס', 'תדמית', 'קריין',
    ],
    'כושר ואימון': [
      'כושר', 'אימון', 'מאמן', 'ספורט', 'דיאטה', 'תזונה', 'ריצה',
      'יוגה', 'פילאטיס', 'gym', 'הרזיה', 'שרירים', 'קרוספיט', 'שחייה',
    ],
    'מעבר דירה': [
      'מעבר', 'הובלה', 'ארגז', 'מובל', 'אריזה', 'פריקה', 'העברת ריהוט',
      'דירה חדשה', 'משרד חדש', 'שינוע', 'מנוף',
    ],
    'מנעולן': [
      'מנעולן', 'מפתח', 'דלת', 'נעול', 'מנעול', 'פריצת דלת', 'כספת',
      'גלגלת', 'ציר', 'אמבולנס', 'סגור',
    ],
    'הדברה': [
      'הדברה', 'מדביר', "ג'וקים", 'עכברים', 'נמלים', 'זבובים',
      'מזיקים', 'חרקים', 'פרעושים', 'קרציות', 'יתושים', 'עכביש',
    ],
    'רכב': [
      'רכב', 'מכונית', 'מוסך', 'מכאניק', 'גלגל', 'בלמים', 'שמן',
      'תקר', 'מנוע', 'פח', 'קוד שגיאה', 'מצבר', 'מזגן רכב',
    ],
    'בישול ואוכל': [
      'בישול', 'שף', 'קייטרינג', 'אוכל', 'ארוחה', 'עוגה', 'מסיבה',
      'אירוח', 'תפריט', 'חתונה', 'בר מצווה', 'שולחן',
    ],
    'מוסיקה': [
      'מוסיקה', 'גיטרה', 'פסנתר', 'שיר', 'הקלטה', 'DJ', 'כינור',
      'תוף', 'קלידים', 'לימוד נגינה', 'הופעה', 'להקה', 'סטודיו',
    ],
  };

  // ── Urgency keywords ──────────────────────────────────────────────────────
  static const List<String> _urgentWords = [
    'דחוף', 'מיד', 'עכשיו', 'היום', 'בהקדם', 'urgent', 'asap',
    'מהר', 'חירום', 'מיידי', 'ברגע', 'כמה שיותר מהר', 'בהוקדם',
  ];

  // ── Date/time indicator patterns ──────────────────────────────────────────
  static const List<String> _dateWords = [
    'מחר', 'השבוע', 'הבא', 'בתאריך', 'בשעה', 'בבוקר', 'בצהריים',
    'בערב', 'בלילה', 'ביום שני', 'ביום שלישי', 'ביום רביעי',
    'ביום חמישי', 'ביום שישי', 'בשבת', 'ביום ראשון', 'ינואר', 'פברואר',
    'מרץ', 'אפריל', 'מאי', 'יוני', 'יולי', 'אוגוסט', 'ספטמבר',
    'אוקטובר', 'נובמבר', 'דצמבר', 'השנה', 'חודש הבא',
  ];

  // ── Location indicator patterns ───────────────────────────────────────────
  static const List<String> _locationWords = [
    'תל אביב', 'ירושלים', 'חיפה', 'ראשון לציון', 'פתח תקווה',
    'נתניה', 'באר שבע', 'בית שמש', 'אשדוד', 'אשקלון', 'רמת גן',
    'גבעתיים', 'הרצליה', 'כפר סבא', 'רעננה', 'מודיעין', 'ראש העין',
    'בבית', 'בדירה', 'במשרד', 'בחנות', 'בכתובת', 'באזור',
    'ברחוב', 'שכונת', 'בשכונה',
  ];

  // ── Public API ────────────────────────────────────────────────────────────
  /// Analyze a Hebrew request text. Returns detected category, urgency, and
  /// hints about missing information. Call this on every text change (debounced).
  static RequestAnalysis analyze(String text) {
    if (text.trim().length < 6) return const RequestAnalysis();

    final lower = text.toLowerCase();

    // 1. Category detection — most keyword hits wins
    String? bestCategory;
    int bestScore = 0;
    for (final entry in _categoryKeywords.entries) {
      int score = 0;
      for (final kw in entry.value) {
        if (lower.contains(kw.toLowerCase())) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        bestCategory = entry.key;
      }
    }

    // 2. Urgency
    final isUrgent =
        _urgentWords.any((w) => lower.contains(w.toLowerCase()));

    // 3. Missing date: no date keyword AND no time pattern AND text is substantial
    final hasDate = text.trim().length > 15 &&
        (_dateWords.any((w) => lower.contains(w.toLowerCase())) ||
            RegExp(r'\d{1,2}[/.]\d{1,2}').hasMatch(text) ||
            RegExp(r'\b\d{1,2}:\d{2}\b').hasMatch(text));

    // 4. Missing location: no city/location keyword AND text is substantial
    final hasLocation = text.trim().length > 15 &&
        (_locationWords.any((w) => lower.contains(w.toLowerCase())) ||
            RegExp(r'ב[א-ת]{3,}').hasMatch(text));

    return RequestAnalysis(
      suggestedCategory: bestScore > 0 ? bestCategory : null,
      urgency: isUrgent ? 'urgent' : 'normal',
      missingDate: !hasDate && text.trim().length > 20,
      missingLocation: !hasLocation && text.trim().length > 20,
    );
  }

  // ── Matchmaker scoring ────────────────────────────────────────────────────
  /// Scores a provider profile against a request description.
  /// Returns 0–100. Higher = better match.
  static double scoreProvider(
      Map<String, dynamic> provider, String requestText) {
    double score = 0;

    // Rating component — max 40 pts
    final rating = (provider['rating'] as num? ?? 4.5).toDouble();
    score += (rating / 5.0) * 40.0;

    // Keyword overlap — max 40 pts
    final bio =
        '${provider['aboutMe'] ?? ''} ${provider['serviceType'] ?? ''}'
            .toLowerCase();
    final words = requestText
        .toLowerCase()
        .split(RegExp(r'[\s,.!?]+'))
        .where((w) => w.length > 2)
        .toSet();
    final matchCount = words.where((w) => bio.contains(w)).length;
    score += (matchCount.clamp(0, 6) / 6.0) * 40.0;

    // Social proof — max 20 pts
    final orders = (provider['orderCount'] as num? ?? 0).toInt();
    score += (orders.clamp(0, 10) / 10.0) * 20.0;

    return score;
  }

  /// Returns the index of the best-matching provider in the list.
  /// Returns 0 if the list is empty.
  static int topMatchIndex(
      List<Map<String, dynamic>> providers, String requestText) {
    if (providers.isEmpty) return 0;
    int bestIdx = 0;
    double bestScore = -1;
    for (int i = 0; i < providers.length; i++) {
      final s = scoreProvider(providers[i], requestText);
      if (s > bestScore) {
        bestScore = s;
        bestIdx = i;
      }
    }
    return bestIdx;
  }
}
