import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'data_export_screen.dart';

// Brand tokens — match terms_of_service_screen.dart
const _kPurple     = Color(0xFF6366F1);
const _kPurpleSoft = Color(0xFFF0F0FF);

/// Standalone Privacy Policy screen (Hebrew, RTL).
///
/// Compliant with:
///  - חוק הגנת הפרטיות, תשמ"א-1981 (Sections 11, 13, 14, 17)
///  - תקנות הגנת הפרטיות (אבטחת מידע), תשע"ז-2017
///  - GDPR (Articles 13, 14, 15, 17, 20, 22) — for any EU users
///  - Apple App Store / Google Play data safety requirements
///
/// Linked from: profile screen, sign-up, OTP, login.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _supportEmail = 'support@anyskill.app';
  static const _dpoEmail     = 'privacy@anyskill.app';
  static const _registrarUrl = 'https://www.gov.il/he/departments/the_privacy_protection_authority';
  static const _lastUpdated  = '10 במאי 2026';
  static const _version      = 'v1.0';

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FF),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.black87),
            onPressed: () => Navigator.pop(context),
          ),
          centerTitle: true,
          title: const Text(
            'מדיניות פרטיות',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────────────────────────────
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: _kPurpleSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'עודכן: $_lastUpdated · $_version',
                    style: TextStyle(
                        fontSize: 12, color: _kPurple, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'מסמך משפטי מחייב — כפוף לחוק הגנת הפרטיות, תשמ"א-1981',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),

              // ── Quick rights pill row ──────────────────────────────────────
              _RightsBar(),
              const SizedBox(height: 24),

              // ── Sections ───────────────────────────────────────────────────
              _section(
                number: '1',
                icon: Icons.shield_moon_rounded,
                color: _kPurple,
                title: 'מי אנחנו ומי אחראי',
                body:
                    'AnySkill ("אנחנו", "הפלטפורמה") מפעילה אפליקציית תיווך דיגיטלית '
                    'המחברת בין לקוחות לבין נותני שירות מקצועיים בישראל. '
                    'לצורך חוק הגנת הפרטיות, AnySkill היא בעלת מאגר המידע הרשום '
                    'ומשמשת כ"בעל מאגר" וכ"מחזיק במאגר" כהגדרתם בסעיף 7 לחוק.\n\n'
                    'פרטי קשר רשמיים:\n'
                    '• דוא"ל לפניות פרטיות (DPO): $_dpoEmail\n'
                    '• דוא"ל תמיכה כללית: $_supportEmail\n'
                    '• רשם מאגרי המידע: ניתן להגיש תלונה לרשות הגנת הפרטיות '
                    'במשרד המשפטים.',
              ),
              const SizedBox(height: 16),

              _highlightedSection(
                number: '2',
                icon: Icons.fingerprint_rounded,
                iconColor: const Color(0xFF7C3AED),
                bgColor: const Color(0xFFFAF5FF),
                borderColor: const Color(0xFFD8B4FE),
                title: 'איזה מידע אנחנו אוספים',
                body:
                    'נאסף ונעובד המידע הבא, בהתאם לסוג השימוש:\n\n'
                    '🔹 מידע מזהה — שם, מספר טלפון, כתובת אימייל, תמונת פרופיל.\n'
                    '🔹 מידע אימות (KYC) — לנותני שירות בלבד: מספר ת"ז / ח.פ, '
                    'צילום ת"ז, סלפי אימות חי, רישיונות מקצועיים. נשמרים '
                    'בתת-קולקציה מאובטחת בנפרד מהפרופיל הציבורי.\n'
                    '🔹 מידע פיננסי — יתרת ארנק פנימית, היסטוריית עסקאות, '
                    'מספר חשבון בנק לצורך משיכות. אין שמירת מספרי כרטיסי אשראי '
                    'מלאים על שרתינו (PCI DSS-compliant tokenization בלבד).\n'
                    '🔹 מידע מיקום — מיקום משוער (~עיר) לצורך התאמת ספקים; '
                    'מיקום מדויק רק בעת שירותים פעילים (גרר, הליכון כלב, '
                    'אימות הגעה לעבודה) ובהסכמה מפורשת.\n'
                    '🔹 מידע התנהגותי — היסטוריית הזמנות, חיפושים, דירוגים, '
                    'תוכן הודעות (לצורכי בטיחות בלבד — ראה סעיף 7).\n'
                    '🔹 מידע ביומטרי-מתון — סלפי אימות בלבד; משמש להשוואה '
                    'מול תמונת ת"ז ואינו מומר לוקטור ביומטרי.\n'
                    '🔹 מידע טכני — IP, סוג מכשיר, גרסת אפליקציה, מזהה התקן '
                    'לצורכי אבטחה ומניעת הונאה.',
              ),
              const SizedBox(height: 16),

              _section(
                number: '3',
                icon: Icons.task_alt_rounded,
                color: _kPurple,
                title: 'למה אנחנו אוספים את המידע (מטרות ובסיס חוקי)',
                body:
                    'כל איסוף מידע נשען על אחד מהבסיסים הבאים (Article 6 GDPR / '
                    'סעיפים 1, 11 לחוק הישראלי):\n\n'
                    '✅ ביצוע חוזה — הצגת ספקים, ביצוע הזמנות, נאמנות תשלומים, '
                    'דירוגים, יישוב מחלוקות.\n'
                    '✅ הסכמה מפורשת — מיקום מדויק, התראות Push, שיתוף תמונות '
                    'במהלך עבודה (תיעוד תיקון/הליכון/פנסיון).\n'
                    '✅ אינטרס לגיטימי — מניעת הונאה (anti-fraud), '
                    'אבטחת חשבון, שיפור איכות השירות, אנליטיקה אגרגטיבית.\n'
                    '✅ חובה חוקית — שמירת מסמכי עסקה לצורכי מס (7 שנים '
                    'לפי חוק רשויות המס), שיתוף עם רשויות לפי צו שיפוטי.\n\n'
                    'אנחנו לא משתמשים במידע למטרות שלא צוינו כאן ללא הסכמה '
                    'מחודשת ומפורשת.',
              ),
              const SizedBox(height: 16),

              _highlightedSection(
                number: '4',
                icon: Icons.share_rounded,
                iconColor: const Color(0xFF10B981),
                bgColor: const Color(0xFFF0FDF4),
                borderColor: const Color(0xFF6EE7B7),
                title: 'עם מי אנחנו משתפים את המידע',
                body:
                    'AnySkill לא מוכרת ולא משכירה מידע אישי לצדדים שלישיים — '
                    'נקודה. השיתוף היחיד הוא:\n\n'
                    '• ספקי תשתית מורשים — Google Firebase '
                    '(Auth, Firestore, Storage, Cloud Functions, Hosting), '
                    'Sentry (ניטור שגיאות), שירותי AI של Google '
                    '(Gemini) ושל Anthropic (Claude). כל אחד מהם כפוף לתנאי '
                    'הפרטיות שלו ולחוזה DPA (Data Processing Agreement) חתום.\n'
                    '• מתווך תשלומים — בעת שילוב ספק תשלומים ישראלי '
                    '(אישור עתידי), המידע הפיננסי הרלוונטי יועבר אליו '
                    'לצורך עיבוד התשלום בלבד.\n'
                    '• בין משתמשים — שם, תמונת פרופיל, דירוג, וקטגוריית '
                    'שירות מוצגים פומבית בתוך הפלטפורמה (טלפון ואימייל '
                    'נחשפים רק לאחר התאמה והזמנה).\n'
                    '• רשויות אכיפת חוק — אך ורק על פי צו שיפוטי תקף או '
                    'דרישה חוקית מחייבת. כל בקשה כזו מתועדת ב-audit log פנימי.\n'
                    '• רוכש עתידי — במקרה של מיזוג / מכירה / איחוד, '
                    'המידע יעבור לרוכש בכפוף להמשך עמידה במדיניות זו.',
              ),
              const SizedBox(height: 16),

              _section(
                number: '5',
                icon: Icons.public_rounded,
                color: _kPurple,
                title: 'העברת מידע מחוץ לישראל',
                body:
                    'חלק משירותי התשתית פועלים מחוץ לישראל:\n\n'
                    '• Google Firebase — שרתי us-central1 (ארה"ב) ו-europe-west '
                    '(האיחוד האירופי). מוגן ע"י Google Cloud DPA + Standard '
                    'Contractual Clauses (SCCs).\n'
                    '• Sentry — שרתי us.sentry.io (ארה"ב). DPA חתום.\n'
                    '• Anthropic / Google AI — עיבוד טקסט בלבד (לא מאוחסן יותר '
                    'מ-30 יום אצל הספק); אין שיתוף מזהים אישיים בפרומפטים.\n\n'
                    'בכל מקרה של העברה לעיבוד מחוץ לישראל / מחוץ לאיחוד האירופי, '
                    'אנו דואגים שהיעד עומד באחד מ:\n'
                    '(א) רמת הגנה נאותה לפי החלטת הנציבות האירופית, או\n'
                    '(ב) חוזה SCCs תקף בין AnySkill לבין ספק התשתית.',
              ),
              const SizedBox(height: 16),

              _highlightedSection(
                number: '6',
                icon: Icons.schedule_rounded,
                iconColor: const Color(0xFFF59E0B),
                bgColor: const Color(0xFFFFFBEB),
                borderColor: const Color(0xFFFDE68A),
                title: 'תקופות שמירת מידע',
                body:
                    'לכל סוג מידע יש משך שמירה מוגדר:\n\n'
                    '⏱ פרופיל פעיל — כל עוד החשבון פעיל.\n'
                    '⏱ מסמכי עסקה (חשבוניות, transactions) — 7 שנים '
                    'לפי חוק מס הכנסה ופקודת מס הכנסה.\n'
                    '⏱ הודעות צ\'אט — שנתיים מתאריך השליחה (אלא אם נדרש לצורכי '
                    'מחלוקת פעילה).\n'
                    '⏱ מסמכי KYC (ת"ז, סלפי) — 5 שנים מסיום ההתקשרות עם הספק '
                    'לפי תקנות איסור הלבנת הון.\n'
                    '⏱ Logs טכניים (error_logs, activity_log) — 30 יום, '
                    'נמחקים אוטומטית ע"י Firestore TTL.\n'
                    '⏱ מידע מיקום מדויק — נמחק תוך 90 יום מסיום השירות.\n'
                    '⏱ חשבון מחוק — תוך 30 יום ממועד הבקשה למחיקה. '
                    'מסמכי עסקה היסטוריים נשמרים מטעמי חוק רשויות המס '
                    'תוך הסרת מזהים ישירים.',
              ),
              const SizedBox(height: 16),

              _section(
                number: '7',
                icon: Icons.lock_rounded,
                color: _kPurple,
                title: 'אבטחת מידע',
                body:
                    'AnySkill עומדת בתקנות הגנת הפרטיות (אבטחת מידע) תשע"ז-2017, '
                    'ברמת אבטחה "בינונית" (סעיף 4 לתקנות):\n\n'
                    '🔐 הצפנה — כל המידע מוצפן at-rest (Firestore + Storage) '
                    'ובמעבר (TLS 1.3).\n'
                    '🔐 בקרת גישה — Firebase Custom Claims + Security Rules + '
                    'audit log שלא ניתן למחוק.\n'
                    '🔐 הגנה מפני הונאה — App Check, validation מולטי-שכבתי, '
                    'idempotency keys בכל פעולת כסף.\n'
                    '🔐 ניטור — Sentry + Firebase Crashlytics + Watchtower; '
                    'התראות אוטומטיות על אירועי אבטחה.\n'
                    '🔐 גיבויים — גיבוי יומי אוטומטי של כל המאגר ל-bucket '
                    'מוגן עם 30 יום שמירה.\n'
                    '🔐 בדיקות אבטחה תקופתיות — Firestore rules tests ב-CI; '
                    'audit חיצוני מתוכנן אחת לשנה.\n\n'
                    'במקרה של אירוע אבטחה חמור הכרוך בחשיפת מידע אישי, '
                    'נדווח לרשם מאגרי המידע ולמשתמשים שנפגעו '
                    'תוך 72 שעות (Article 33-34 GDPR / סעיף 11ב לתקנות).',
              ),
              const SizedBox(height: 16),

              _highlightedSection(
                number: '8',
                icon: Icons.account_circle_rounded,
                iconColor: const Color(0xFF0EA5E9),
                bgColor: const Color(0xFFF0F9FF),
                borderColor: const Color(0xFF7DD3FC),
                title: 'הזכויות שלך',
                body:
                    'כל משתמש זכאי לפנות אלינו ב-$_dpoEmail ולממש את הזכויות '
                    'הבאות (סעיפים 13-14 לחוק / Articles 15-22 GDPR):\n\n'
                    '👁 זכות עיון — לקבל עותק של כל המידע השמור עליך, '
                    'בפורמט קריא לאדם ולמכונה (JSON/CSV).\n'
                    '✏ זכות תיקון — לתקן מידע לא מדויק או לא מעודכן.\n'
                    '🗑 זכות מחיקה ("הזכות להישכח") — מחיקה מלאה של חשבונך '
                    'תוך 30 יום (למעט מסמכים שחובה חוקית לשמור).\n'
                    '⏸ זכות הגבלת עיבוד — לבקש הקפאת עיבוד מידע בעת מחלוקת.\n'
                    '📦 זכות ניידות — לקבל את המידע בפורמט מובנה כדי '
                    'להעביר לפלטפורמה אחרת.\n'
                    '🚫 זכות התנגדות — להתנגד לעיבוד המבוסס על אינטרס לגיטימי '
                    '(שיווק, אנליטיקה).\n'
                    '🤖 זכות לבל יחול עליך החלטה אוטומטית — ראה סעיף 9.\n'
                    '🔁 זכות לבטל הסכמה — בכל עת, בלי לפגוע בעיבוד שכבר נעשה.\n\n'
                    'מימוש זכויות אלה הוא חינם, ויענה תוך 30 יום. '
                    'אם לא תקבל מענה — ניתן להגיש תלונה לרשם מאגרי המידע '
                    'ברשות הגנת הפרטיות (משרד המשפטים).',
              ),
              const SizedBox(height: 16),

              _section(
                number: '9',
                icon: Icons.smart_toy_rounded,
                color: _kPurple,
                title: 'בינה מלאכותית והחלטות אוטומטיות',
                body:
                    'AnySkill משתמשת ב-AI (Google Gemini, Anthropic Claude) '
                    'במספר אזורים, באופן שקוף:\n\n'
                    '• דירוג חיפוש — אלגוריתם שמשקלל XP, מרחק, סטוריז, ודירוגים. '
                    'ניתן לאתר ב-CLAUDE.md §6.\n'
                    '• המלצות התאמה — Quiz למאמני כושר, המלצת רכב במשלוחים, '
                    'אבחון תקלה בהדברה ובהנדימן (מבוסס תמונה). שקוף ומסומן '
                    'באופן ברור.\n'
                    '• זיהוי הונאה — סריקה של דפוסי שימוש חשודים. '
                    'אדם תמיד סוקר לפני סגירת חשבון.\n'
                    '• Insights ניהוליים — סיכומים אגרגטיביים לאדמין; '
                    'אינם פוגעים בלקוחות באופן אישי.\n\n'
                    'אף החלטה אוטומטית בלעדית לא מתקבלת בעניינך מבלי '
                    'לאפשר בקשת התערבות אנושית. אם החלטה אוטומטית השפיעה '
                    'באופן משמעותי על השימוש שלך באפליקציה, אתה זכאי לבקש '
                    'בדיקה אנושית ב-$_dpoEmail.',
              ),
              const SizedBox(height: 16),

              _section(
                number: '10',
                icon: Icons.cookie_outlined,
                color: _kPurple,
                title: 'עוגיות וטכנולוגיות מעקב',
                body:
                    'בגרסת ה-Web אנו משתמשים ב:\n\n'
                    '🍪 עוגיות הכרחיות — לזיהוי הפעלה ושמירת התחברות. '
                    'אינן ניתנות לחסימה ללא פגיעה בשירות.\n'
                    '🍪 LocalStorage / SessionStorage — לשמירת העדפות שפה, '
                    'מצב תצוגה, ותור הודעות במצב offline.\n'
                    '🍪 Firebase Performance — מדידת זמני טעינה אגרגטיבית.\n\n'
                    'איננו משתמשים ב-cookies של צד שלישי לצורכי שיווק '
                    'או ריטרגטינג. אין Pixel של פייסבוק / גוגל אנליטיקס.',
              ),
              const SizedBox(height: 16),

              _section(
                number: '11',
                icon: Icons.child_care_rounded,
                color: _kPurple,
                title: 'קטינים',
                body:
                    'השירות מיועד למשתמשים מגיל 18 ומעלה בלבד. '
                    'איננו אוספים מידע מקטינים ביודעין.\n\n'
                    'אם נודע לנו שמידע נאסף מקטין מתחת לגיל 18, '
                    'נמחק אותו ב-72 שעות. כל הורה / אפוטרופוס שמזהה שימוש '
                    'של קטין שבחזקתו — נא לפנות מיידית ל-$_dpoEmail.',
              ),
              const SizedBox(height: 16),

              _highlightedSection(
                number: '12',
                icon: Icons.update_rounded,
                iconColor: const Color(0xFFEF4444),
                bgColor: const Color(0xFFFFF5F5),
                borderColor: const Color(0xFFFECACA),
                title: 'שינויים במדיניות',
                body:
                    'AnySkill תעדכן מדיניות זו מעת לעת. שינויים מהותיים '
                    '(הוספת קטגוריה חדשה של מידע, ספק תשתית חדש, או '
                    'שינוי בזכויות הנושא) יימסרו בהודעה Push ובאנר באפליקציה '
                    'לפחות 14 ימים לפני כניסתם לתוקף.\n\n'
                    'גרסה ארכיונית של כל עדכון נשמרת וזמינה לעיון ב-$_dpoEmail. '
                    'המשך שימוש בפלטפורמה לאחר מועד כניסת השינויים לתוקף '
                    'מהווה הסכמה לתנאים המעודכנים.',
              ),
              const SizedBox(height: 16),

              _section(
                number: '13',
                icon: Icons.contact_support_rounded,
                color: _kPurple,
                title: 'פנייה אלינו ולרשות',
                body:
                    'לכל שאלה, בקשה למימוש זכות, או תלונה:\n\n'
                    '📧 פניות פרטיות (DPO): $_dpoEmail\n'
                    '📧 תמיכה כללית: $_supportEmail\n'
                    '⏱ זמן מענה: עד 30 יום (לרוב תוך 7 ימי עסקים).\n\n'
                    'אם אינך מרוצה מהמענה שקיבלת, אתה זכאי להגיש תלונה '
                    'לרשות הגנת הפרטיות במשרד המשפטים.',
              ),
              const SizedBox(height: 24),

              // ── Action: open Data Export ───────────────────────────────
              _ActionCard(
                icon: Icons.download_rounded,
                color: _kPurple,
                title: 'ייצוא הנתונים שלי',
                subtitle: 'קבל עותק של כל המידע השמור עליך',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const DataExportScreen()),
                  );
                },
              ),
              const SizedBox(height: 12),
              _ActionCard(
                icon: Icons.gavel_rounded,
                color: const Color(0xFF6B7280),
                title: 'הגשת תלונה לרשות הגנת הפרטיות',
                subtitle: 'משרד המשפטים — באתר gov.il',
                onTap: () => _launch(_registrarUrl),
              ),
              const SizedBox(height: 32),

              // ── Footer ────────────────────────────────────────────────────
              Center(
                child: Text(
                  '© AnySkill 2026. כל הזכויות שמורות.\n$_dpoEmail',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11.5, color: Colors.grey[400], height: 1.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── Reusable section widgets ──────────────────────────────────────────────

  Widget _section({
    required String number,
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(number,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ),
            ),
            const SizedBox(width: 8),
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          body,
          style: const TextStyle(
              fontSize: 13.5, height: 1.70, color: Colors.black87),
        ),
      ],
    );
  }

  Widget _highlightedSection({
    required String number,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required Color borderColor,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(number,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: iconColor)),
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: const TextStyle(
                fontSize: 13.5, height: 1.70, color: Colors.black87),
          ),
        ],
      ),
    );
  }
}

// ── Quick rights pill row at top ──────────────────────────────────────────────

class _RightsBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final rights = [
      ('זכות עיון', Icons.visibility_outlined),
      ('זכות תיקון', Icons.edit_outlined),
      ('זכות מחיקה', Icons.delete_outline_rounded),
      ('זכות ניידות', Icons.swap_horiz_rounded),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: rights.map((r) {
          return Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(r.$2, size: 14, color: _kPurple),
                  const SizedBox(width: 6),
                  Text(r.$1,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Action card (Export / File complaint) ────────────────────────────────────

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
