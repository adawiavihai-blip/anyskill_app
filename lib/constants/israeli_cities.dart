/// Bundled list of Israeli cities, towns, and major localities (yishuvim).
///
/// Used by [AddressInput] for instant offline city autocomplete — no network
/// round-trip on the city field. Covers ~270 of Israel's largest and
/// best-known localities. Smaller moshavim/kibbutzim that aren't in this
/// list fall back to free-text entry.
///
/// Maintained as a const list so the bundle stays under ~10 KB and lookups
/// are O(n) over a small N (~270). If we ever need full coverage of all
/// ~1,200 yishuvim, swap to a generated asset under `assets/data/` and load
/// once at app start.
library;

/// Canonical alphabetical-by-Hebrew list of Israeli localities.
///
/// **Ordering rule:** Hebrew alphabetical (א → ת). Source list may contain
/// duplicates between the "main cities" batch and the "moshavim/kibbutzim"
/// batch — those are deduped at module load via the [kIsraeliCities] getter.
const List<String> _rawIsraeliCities = <String>[
  // א
  'אבו גוש',
  'אבו סנאן',
  'אבן יהודה',
  'אופקים',
  'אור יהודה',
  'אור עקיבא',
  'אזור',
  'אילת',
  'אכסאל',
  'אליכין',
  'אלעד',
  'אלפי מנשה',
  'אלקנה',
  'אריאל',
  'אשדוד',
  'אשקלון',
  // ב
  'באקה אל-גרבייה',
  'באר יעקב',
  'באר שבע',
  'בועיינה-נוג׳ידאת',
  'בוקעאתא',
  'ביר אל-מכסור',
  'בית אל',
  'בית דגן',
  'בית שאן',
  'בית שמש',
  'ביתר עילית',
  'בני ברק',
  'בני עי״ש',
  'בנימינה-גבעת עדה',
  'בסמ״ה',
  'בסמת טבעון',
  'בת חפר',
  'בת ים',
  // ג
  'גבעת זאב',
  'גבעת שמואל',
  'גבעתיים',
  'גדרה',
  'גן יבנה',
  'גני תקווה',
  'ג׳ולס',
  'ג׳סר א-זרקא',
  'ג׳ש (גוש חלב)',
  'ג׳ת',
  // ד
  'דאלית אל-כרמל',
  'דבוריה',
  'דייר אל-אסד',
  'דייר חנא',
  'דימונה',
  // ה
  'הוד השרון',
  'הר אדר',
  'הרצליה',
  // ז
  'זכרון יעקב',
  'זרזיר',
  // ח
  'חדרה',
  'חולון',
  'חורה',
  'חורפיש',
  'חיפה',
  'חצור הגלילית',
  'חריש',
  // ט
  'טבעון',
  'טבריה',
  'טובא-זנגרייה',
  'טייבה',
  'טירה',
  'טירת כרמל',
  'טמרה',
  // י
  'יבנאל',
  'יבנה',
  'יהוד-מונוסון',
  'יקנעם עילית',
  'ירוחם',
  'ירכא',
  'ירושלים',
  // כ
  'כאבול',
  'כאוכב אבו אל-היג׳א',
  'כוכב יאיר-צור יגאל',
  'כסיפה',
  'כסרא-סמיע',
  'כעביה-טבאש-חג׳אג׳רה',
  'כפר ברא',
  'כפר ורדים',
  'כפר יאסיף',
  'כפר יונה',
  'כפר כמא',
  'כפר כנא',
  'כפר מנדא',
  'כפר סבא',
  'כפר קאסם',
  'כפר קרע',
  'כפר שמריהו',
  'כפר תבור',
  'כרמיאל',
  // ל
  'לוד',
  'לקיה',
  // מ
  'מבשרת ציון',
  'מגאר',
  'מגדל',
  'מגדל העמק',
  'מודיעין עילית',
  'מודיעין-מכבים-רעות',
  'מזכרת בתיה',
  'מזרעה',
  'מטולה',
  'מיתר',
  'מסעדה',
  'מעיליא',
  'מעלה אדומים',
  'מעלות-תרשיחא',
  'מצפה רמון',
  'משהד',
  // נ
  'נהריה',
  'נוף הגליל',
  'נחף',
  'נצרת',
  'נשר',
  'נתיבות',
  'נתניה',
  // ס
  'סאג׳ור',
  'סולם',
  'סח׳נין',
  'סלע׳ה',
  // ע
  'עומר',
  'עיילבון',
  'עילוט',
  'עין מאהל',
  'עין קנייא',
  'עכו',
  'עפולה',
  'עראבה',
  'ערד',
  'ערערה',
  'ערערה-בנגב',
  'עתלית',
  // פ
  'פוריידיס',
  'פסוטה',
  'פקיעין',
  'פרדס חנה-כרכור',
  'פרדסיה',
  'פתח תקווה',
  // צ
  'צור הדסה',
  'צפת',
  // ק
  'קדומים',
  'קדימה-צורן',
  'קלנסווה',
  'קצרין',
  'קריית אונו',
  'קריית אתא',
  'קריית ביאליק',
  'קריית גת',
  'קריית טבעון',
  'קריית ים',
  'קריית מוצקין',
  'קריית מלאכי',
  'קריית עקרון',
  'קריית שמונה',
  'קרני שומרון',
  // ר
  'ראמה',
  'ראש העין',
  'ראש פינה',
  'ראשון לציון',
  'רהט',
  'רחובות',
  'ריינה',
  'רכסים',
  'רמלה',
  'רמת גן',
  'רמת השרון',
  'רמת ישי',
  'רעננה',
  // ש
  'שבלי-אום אל-גנם',
  'שגב-שלום',
  'שדרות',
  'שוהם',
  'שפרעם',
  // ת
  'תל אביב-יפו',
  'תל מונד',
  'תל שבע',
  'תמרה',
  // Major moshavim, kibbutzim, regional council seats with significant population
  'אבטליון',
  'אבירים',
  'אבן ספיר',
  'אבני חפץ',
  'אופקים',
  'אזור תעשייה',
  'אילון',
  'איתן',
  'אלון שבות',
  'אלוני אבא',
  'אלוני הבשן',
  'אלקוש',
  'אלקנה',
  'אמירים',
  'אפיק',
  'אפיקים',
  'ארגמן',
  'ארסוף',
  'אשבול',
  'בית גמליאל',
  'בית הלל',
  'בית זית',
  'בית חורון',
  'בית יהושע',
  'בית ינאי',
  'בית עזרא',
  'בית עריף',
  'בית רימון',
  'ביצרון',
  'בני דרור',
  'בני ראם',
  'בנימינה',
  'ברעם',
  'ברקת',
  'גאליה',
  'גבים',
  'גבעולים',
  'גבעת חיים',
  'גבעת ניל״י',
  'גבעת עדה',
  'גבעת ברנר',
  'גזית',
  'גן השומרון',
  'גן יבנה',
  'גן שלמה',
  'גן שמואל',
  'גני יוחנן',
  'גני עם',
  'גשר',
  'דברת',
  'דגניה א׳',
  'דגניה ב׳',
  'דליה',
  'דרגות',
  'הבונים',
  'הזורעים',
  'הסוללים',
  'העוגן',
  'הר עמשא',
  'הראל',
  'ורדון',
  'זיתן',
  'חוקוק',
  'חצב',
  'חצרים',
  'חרשים',
  'טירת יהודה',
  'טירת צבי',
  'יד בנימין',
  'יד חנה',
  'יד מרדכי',
  'יודפת',
  'יחיעם',
  'יסוד המעלה',
  'יעד',
  'יערה',
  'יפעת',
  'יקיר',
  'ירדנה',
  'ירקונה',
  'ישעי',
  'כברי',
  'כדורי',
  'כוכב יעקב',
  'כליל',
  'כסלון',
  'כפר אביב',
  'כפר אדומים',
  'כפר אוריה',
  'כפר אחים',
  'כפר ביאליק',
  'כפר ברוך',
  'כפר גליקסון',
  'כפר גליל ים',
  'כפר ויתקין',
  'כפר חב״ד',
  'כפר חרוב',
  'כפר טרומן',
  'כפר יהושע',
  'כפר יחזקאל',
  'כפר יעבץ',
  'כפר מל״ל',
  'כפר מנחם',
  'כפר מסריק',
  'כפר נטר',
  'כפר ניר',
  'כפר עזה',
  'כפר פינס',
  'כפר רופין',
  'כפר רוזנואלד',
  'כפר רות',
  'כפר שמואל',
  'כפר תפוח',
  'להבים',
  'מבוא חמה',
  'מבואות ים',
  'מגדל אור',
  'מגן',
  'מולדת',
  'מי עמי',
  'מיצר',
  'מירב',
  'מירון',
  'מנחמיה',
  'מסילת ציון',
  'מעגלים',
  'מעגן מיכאל',
  'מעוז חיים',
  'מעיין צבי',
  'מעלה החמישה',
  'מצפה אבי״ב',
  'מצפה נטופה',
  'מרגליות',
  'משאבי שדה',
  'משגב דב',
  'משואות יצחק',
  'נאות גולן',
  'נאות מרדכי',
  'נחל עוז',
  'נחלים',
  'ניצנים',
  'נירים',
  'נצר סרני',
  'נריה',
  'סאסא',
  'סביון',
  'סדה אליעזר',
  'סנסנה',
  'סעד',
  'עברון',
  'עין גב',
  'עין השופט',
  'עין חרוד איחוד',
  'עין חרוד מאוחד',
  'עין יעקב',
  'עין כרמל',
  'עין שמר',
  'עינת',
  'עלי',
  'עלמה',
  'עמיעד',
  'עמיקם',
  'ערבה',
  'פלך',
  'פרזון',
  'צופית',
  'צופים',
  'צוקי ים',
  'צור משה',
  'צרופה',
  'קדמת צבי',
  'קלע',
  'קרית ענבים',
  'ראש צורים',
  'רגבים',
  'רוויה',
  'רחוב',
  'רמות',
  'רמות השבים',
  'רמות מאיר',
  'רמת השופט',
  'רמת מגשימים',
  'רמת רחל',
  'רמת רזיאל',
  'רנן',
  'רעים',
  'שדה אילן',
  'שדה אליהו',
  'שדה בוקר',
  'שדה דוד',
  'שדה משה',
  'שדה נחום',
  'שדה ניצן',
  'שדה עוזיהו',
  'שדה צבי',
  'שדה ורבורג',
  'שדה יואב',
  'שדה יעקב',
  'שדמות דבורה',
  'שדמות מחולה',
  'שוקדה',
  'שילה',
  'שלוחות',
  'שלומי',
  'שלומית',
  'שמיר',
  'שמשית',
  'שעלבים',
  'שער הגולן',
  'שער העמקים',
  'שערים',
  'תדהר',
  'תל יוסף',
  'תל מונד',
  'תפרח',
  'תקומה',
];

/// Public, deduped, immutable view of [_rawIsraeliCities].
///
/// Source list intentionally allows duplicates between the "main cities" and
/// "moshavim/kibbutzim" batches; this view collapses them via `Set` while
/// preserving first-occurrence order (which is Hebrew-alphabetical).
final List<String> kIsraeliCities =
    List<String>.unmodifiable(<String>{..._rawIsraeliCities});

/// Normalize Hebrew text for matching: trim, collapse whitespace, and unify
/// common separator variants (hyphen variants, multiple spaces).
String _normalizeForMatch(String s) {
  return s
      .trim()
      .replaceAll(RegExp(r'[-–—−]'), '-') // various dashes → -
      .replaceAll(RegExp(r'\s+'), ' ');
}

/// Filter the bundled cities list against [query].
///
/// Matching strategy (priority order):
/// 1. Empty query → top [limit] alphabetically (= "popular cities" preview).
/// 2. Prefix match — cities that START with the normalized query.
/// 3. Substring match — cities that CONTAIN the query (fallback).
///
/// Returns at most [limit] entries. The widget renders these in a dropdown.
List<String> filterIsraeliCities(String query, {int limit = 8}) {
  final q = _normalizeForMatch(query);
  if (q.isEmpty) {
    return kIsraeliCities.take(limit).toList();
  }

  final prefix = <String>[];
  final contains = <String>[];

  for (final city in kIsraeliCities) {
    final normalized = _normalizeForMatch(city);
    if (normalized.startsWith(q)) {
      prefix.add(city);
    } else if (normalized.contains(q)) {
      contains.add(city);
    }
    if (prefix.length >= limit) break;
  }

  if (prefix.length >= limit) return prefix.take(limit).toList();
  final remaining = limit - prefix.length;
  return [...prefix, ...contains.take(remaining)];
}

/// Check whether the given city string is in the canonical bundled list.
/// Used by validation — accept unknown free-text city but flag it as
/// "not in our list" if the consumer wants strict validation.
bool isCanonicalIsraeliCity(String city) {
  final normalized = _normalizeForMatch(city);
  for (final c in kIsraeliCities) {
    if (_normalizeForMatch(c) == normalized) return true;
  }
  return false;
}
