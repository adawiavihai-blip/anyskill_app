import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

// Brand tokens
const _kPurple     = Color(0xFF6366F1);
const _kPurpleSoft = Color(0xFFF0F0FF);

/// Full Terms of Service + Privacy Policy screen (Hebrew, RTL).
/// Opened from the sign-up checkbox or from Settings.
class TermsOfServiceScreen extends StatelessWidget {
  /// When [showAcceptButton] is true, a bottom "אישור" button is rendered
  /// and Navigator.pop(context, true) is called when tapped.
  final bool showAcceptButton;
  const TermsOfServiceScreen({super.key, this.showAcceptButton = false});

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
            onPressed: () => Navigator.pop(context, false),
          ),
          centerTitle: true,
          title: Text(
            AppLocalizations.of(context).tosFullTitle,
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.black87),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── Header metadata ────────────────────────────────────────
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: _kPurpleSoft,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          AppLocalizations.of(context).tosLastUpdated,
                          style: const TextStyle(
                              fontSize: 12,
                              color: _kPurple,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        AppLocalizations.of(context).tosBindingNotice,
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500]),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── TOC pill row ───────────────────────────────────────────
                    _TocBar(),
                    const SizedBox(height: 24),

                    // ── 1. AnySkill ────────────────────────────────────────────
                    _section(
                      number: '1',
                      icon: Icons.info_outline_rounded,
                      color: _kPurple,
                      title: 'מהי AnySkill?',
                      body:
                          'AnySkill היא פלטפורמת תיווך דיגיטלית ("הפלטפורמה") המאפשרת חיבור בין לקוחות '
                          'לבין נותני שירות מקצועיים ("ספקים") בתחומים שונים. '
                          'AnySkill מספקת תשתית טכנולוגית בלבד — לרבות מנגנון חיפוש, '
                          'מערכת תשלומי נאמנות (Escrow), מערכת הודעות, ומנגנון דירוג.\n\n'
                          'גישה לפלטפורמה ושימוש בה כפופים להסכמה מלאה לכל הסעיפים שלהלן. '
                          'שימוש ראשון מהווה הסכמה מחייבת. גיל מינימום לשימוש: 18.',
                    ),
                    const SizedBox(height: 16),

                    // ── 2. Independent Contractor (HIGHLIGHTED) ───────────────
                    _highlightedSection(
                      number: '2',
                      icon: Icons.person_pin_rounded,
                      iconColor: const Color(0xFF7C3AED),
                      bgColor: const Color(0xFFFAF5FF),
                      borderColor: const Color(0xFFD8B4FE),
                      title: 'סטטוס ספקים — קבלן עצמאי',
                      body:
                          'AnySkill אינה מעסיקה את הספקים בכל אופן שהוא. '
                          'הספקים הם קבלנים עצמאיים הפועלים על אחריותם הבלעדית.\n\n'
                          'בין AnySkill לספק לא מתקיימים יחסי עובד-מעביד, שליחות, שותפות, '
                          'או כל מסגרת אחרת המקימה אחריות של AnySkill כלפי צד שלישי בשל מעשי הספק.\n\n'
                          'הספק אחראי באופן בלעדי ל:\n'
                          '• כלים, ציוד, חומרים ורישיונות מקצועיים הנדרשים לביצוע השירות.\n'
                          '• ביטוח צד שלישי, ביטוח אחריות מקצועית, וביטוח בריאות.\n'
                          '• זכויות סוציאליות, פנסיה, דמי אבטלה — AnySkill אינה נושאת בכל אלה.\n'
                          '• עמידה בכל חוק, תקן, ורגולציה החלים על מקצועו.\n\n'
                          'AnySkill שומרת לעצמה את הזכות להשעות או לסיים חשבון ספק שנפגעה '
                          'אמינותו, ללא יצירת יחסי עבודה.',
                    ),
                    const SizedBox(height: 16),

                    // ── 3. Escrow (HIGHLIGHTED) ────────────────────────────────
                    _highlightedSection(
                      number: '3',
                      icon: Icons.lock_rounded,
                      iconColor: const Color(0xFF10B981),
                      bgColor: const Color(0xFFF0FDF4),
                      borderColor: const Color(0xFF6EE7B7),
                      title: 'מודל תשלום — נאמנות (Escrow)',
                      body:
                          'AnySkill פועלת כ"נאמן" (Trustee) על כספי העסקה בלבד. '
                          'היא אינה בעלים של הכסף ואינה מרוויחה ממנו ריבית.\n\n'
                          'זרימת הכספים:\n'
                          '• עם אישור ההזמנה, הלקוח מעביר את סכום העסקה המלא לחשבון הנאמנות של AnySkill.\n'
                          '• הכסף מוקפא ואינו מועבר לספק עד להשלמת אחד מהתנאים הבאים:\n'
                          '  (א) הלקוח אישר ידנית "שחרור תשלום" לאחר השלמת השירות.\n'
                          '  (ב) חלפו 72 שעות ממועד סימון "הושלם" על ידי הספק ללא פעולה מצד הלקוח — '
                          'השחרור יתבצע אוטומטית (אלא אם נפתחה מחלוקת).\n'
                          '  (ג) צוות AnySkill הוציא החלטת בוררות המורה על שחרור.\n\n'
                          'AnySkill תנכה את עמלת השירות מהסכום המועבר לספק. '
                          'הלקוח לא יחויב בסכום נוסף מעבר למה שאושר בהזמנה.',
                    ),
                    const SizedBox(height: 16),

                    // ── 4. Fees ────────────────────────────────────────────────
                    _section(
                      number: '4',
                      icon: Icons.percent_rounded,
                      color: _kPurple,
                      title: 'עמלות ודמי שירות',
                      body:
                          'AnySkill גובה עמלת שירות מסכום כל עסקה מוצלחת. '
                          'שיעור העמלה המעודכן מוצג בהגדרות האפליקציה ובדף האישור לפני כל תשלום.\n\n'
                          '• העמלה מנוכה אוטומטית מהסכום המועבר לספק — הלקוח לא מחויב בנפרד.\n'
                          '• AnySkill רשאית לשנות את שיעור העמלה בהתראה של 14 ימים מראש.\n'
                          '• עסקאות שבוטלו לפני תחילת השירות יזוכו במלואן ללקוח ללא ניכוי עמלה.',
                    ),
                    const SizedBox(height: 16),

                    // ── 5. Cancellation (HIGHLIGHTED) ─────────────────────────
                    _highlightedSection(
                      number: '5',
                      icon: Icons.cancel_outlined,
                      iconColor: const Color(0xFFF59E0B),
                      bgColor: const Color(0xFFFFFBEB),
                      borderColor: const Color(0xFFFDE68A),
                      title: 'מדיניות ביטולים',
                      body:
                          'כל ספק קובע את מדיניות הביטול שלו בעת פתיחת הפרופיל. '
                          'שלושה מסלולים אפשריים:\n\n'
                          '🟢 גמישה — ביטול חינם עד 4 שעות לפני המפגש. ביטול מאוחר: קנס 50% לספק.\n'
                          '🟡 בינונית — ביטול חינם עד 24 שעות לפני. ביטול מאוחר: קנס 50%.\n'
                          '🔴 קפדנית — ביטול חינם עד 48 שעות לפני. ביטול מאוחר: קנס 100%.\n\n'
                          'ביטול מצד הספק — ללא קשר למועד — מזכה את הלקוח בהחזר מלא של 100%.\n'
                          'קנס הביטול מועבר לספק בניכוי עמלת AnySkill הרגילה.\n'
                          'חלון הביטול המדויק מוצג בסיכום ההזמנה לפני האישור הסופי.',
                    ),
                    const SizedBox(height: 16),

                    // ── 6. Tax Compliance (HIGHLIGHTED) ───────────────────────
                    _highlightedSection(
                      number: '6',
                      icon: Icons.account_balance_outlined,
                      iconColor: const Color(0xFF0EA5E9),
                      bgColor: const Color(0xFFF0F9FF),
                      borderColor: const Color(0xFF7DD3FC),
                      title: 'ציות מס ואחריות פיסקלית',
                      body:
                          'הספק הוא האחראי הבלעדי לדיווח ולתשלום כל מס, היטל, '
                          'וכל חיוב חוקי אחר הנובע מהכנסותיו דרך הפלטפורמה. '
                          'AnySkill אינה גורמת מנכה-מס-במקור ואינה אחראית להגשת כל דיווח מס עבור הספק.\n\n'
                          'חובות הספק:\n'
                          '• בעל עסק מורשה / חברה בע"מ: להוציא חשבונית מס כדין ללקוח ו/או ל-AnySkill '
                          'בגין כל עסקה, בהתאם לחובות חוק מע"מ.\n'
                          '• עוסק פטור: להוציא קבלה כדין ולציין סטטוס עוסק פטור.\n'
                          '• פרילנסר ששכרו מגיע לסף חייב ברישום: מחובתו להירשם ברשויות המס.\n'
                          '• ספקים המשתמשים בשירותי הפקת חשבוניות דרך צד שלישי מורשה אחראים '
                          'לוודא כי השירות עומד בדרישות פקיד שומה.\n\n'
                          'AnySkill שומרת לעצמה הזכות להשעות משיכת כספים אם יש חשש '
                          'לאי-ציות לחובות הדיווח.',
                    ),
                    const SizedBox(height: 16),

                    // ── 7. User Conduct ────────────────────────────────────────
                    _section(
                      number: '7',
                      icon: Icons.gavel_rounded,
                      color: _kPurple,
                      title: 'אחריות משתמשים והתנהגות אסורה',
                      body:
                          'כל משתמש (לקוח וספק כאחד) מתחייב:\n'
                          '• לספק מידע אמיתי, מדויק ועדכני בעת הרישום ובמהלך השימוש.\n'
                          '• לנהוג בכבוד, ביושר ובהגינות כלפי כל משתמש אחר בפלטפורמה.\n'
                          '• שלא לבצע עסקאות מחוץ לפלטפורמה כדי לעקוף עמלת AnySkill.\n\n'
                          'שימושים אסורים:\n'
                          '• הטרדה, איומים, שפה פוגענית או גזענית, ציוד מינית.\n'
                          '• פרסום שירותים בלתי חוקיים, מזויפים, או מטעים.\n'
                          '• העלאת תוכן הפוגע בזכויות יוצרים של צד שלישי.\n'
                          '• ניסיון לפרוץ, לסרוק, לסרוק לפגיעויות, או לשבש את הפלטפורמה.\n'
                          '• יצירת חשבונות כפולים לצורך הטייה בדירוגים.\n\n'
                          'הפרה של כל אחד מהאמור לעיל עלולה לגרור השעיה מיידית ו/או '
                          'הפניה לרשויות אכיפת החוק.',
                    ),
                    const SizedBox(height: 16),

                    // ── 8. Account Security ────────────────────────────────────
                    _section(
                      number: '8',
                      icon: Icons.security_rounded,
                      color: _kPurple,
                      title: 'אבטחת חשבון ואחריות אישית',
                      body:
                          'המשתמש אחראי באופן מלא לשמירת סיסמתו ופרטי הגישה לחשבונו.\n\n'
                          '• חל איסור מוחלט להעביר גישה לחשבון לאדם אחר.\n'
                          '• כל פעולה שתתבצע מתוך חשבון המשתמש תיחשב כפעולה שבוצעה על ידיו, '
                          'אלא אם דיווח על גישה לא מורשית בתוך 24 שעות.\n'
                          '• AnySkill ממליצה להפעיל אימות דו-שלבי (2FA) ולהשתמש בסיסמה חזקה ייחודית.\n'
                          '• במקרה של חשד לפריצה לחשבון יש לפנות מיידית לתמיכה ב-support@anyskill.app.\n\n'
                          'AnySkill תחסום חשבון חשוד בפעילות בלתי מורשית ותחקור. '
                          'AnySkill לא תישא באחריות להפסדים שנגרמו כתוצאה מגישה לא מורשית '
                          'שנבעה מרשלנות המשתמש.',
                    ),
                    const SizedBox(height: 16),

                    // ── 9. Limitation of Liability (HIGHLIGHTED) ──────────────
                    _highlightedSection(
                      number: '9',
                      icon: Icons.shield_outlined,
                      iconColor: const Color(0xFFEF4444),
                      bgColor: const Color(0xFFFFF5F5),
                      borderColor: const Color(0xFFFECACA),
                      title: 'הגבלת אחריות',
                      body:
                          'AnySkill מספקת פלטפורמה טכנולוגית בלבד ואינה צד לחוזה השירות '
                          'בין הלקוח לבין הספק. בהתאם, AnySkill לא תישא בכל אחריות ל:\n\n'
                          '• איכות, בטיחות, חוקיות, או תוצאות של שירות שסיפק ספק.\n'
                          '• נזק גוף, נזק לרכוש, או כל נזק אחר שנגרם ללקוח על ידי ספק.\n'
                          '• אובדן הכנסה, אובדן נתונים, נזק עקיף או תוצאתי מכל סיבה שהיא.\n'
                          '• הפסקות שירות, תקלות טכניות, עיכובים, או שגיאות בפלטפורמה.\n'
                          '• מידע שגוי שסיפק משתמש בפרופיל, בהזמנה, או בצ׳אט.\n\n'
                          'בכל מקרה, האחריות הכוללת של AnySkill כלפי כל משתמש לא תעלה על '
                          'הסכום הכולל ששילם אותו משתמש ל-AnySkill בשלושת החודשים שקדמו '
                          'לאירוע הנזק.\n\n'
                          'הגבלה זו חלה במידה המרבית המותרת על פי הדין החל בישראל.',
                    ),
                    const SizedBox(height: 16),

                    // ── 10. Dispute Resolution ─────────────────────────────────
                    _section(
                      number: '10',
                      icon: Icons.balance_rounded,
                      color: _kPurple,
                      title: 'יישוב מחלוקות ובוררות',
                      body:
                          'מחלוקת בין משתמשים תטופל בשלבים הבאים:\n\n'
                          '(א) פנייה ישירה — הצדדים מעודדים לנסות ליישב את המחלוקת ביניהם '
                          'דרך מערכת הצ׳אט בתוך 24 שעות.\n'
                          '(ב) בקשת בוררות — אם לא הושגה הסכמה, כל צד רשאי לפתוח '
                          '"בקשת בוררות" דרך האפליקציה. הכספים ימשיכו להיות מוחזקים בנאמנות '
                          'עד לפתרון.\n'
                          '(ג) סקירת AnySkill — צוות ה-Trust & Safety יבחן ראיות (הודעות, '
                          'צילומי מסך, תיאורים) ויוציא החלטה תוך 48 שעות עסקים.\n'
                          '(ד) אפשרויות ההחלטה:\n'
                          '    • החזר מלא ללקוח.\n'
                          '    • שחרור מלא לספק.\n'
                          '    • פשרה יחסית לפי שיקול דעת הצוות.\n\n'
                          'החלטת הצוות סופית בתוך מסגרת הפלטפורמה. '
                          'הצדדים שומרים על זכותם לפנות לערכאות משפטיות חיצוניות.',
                    ),
                    const SizedBox(height: 16),

                    // ── 11. Intellectual Property ──────────────────────────────
                    _section(
                      number: '11',
                      icon: Icons.copyright_rounded,
                      color: _kPurple,
                      title: 'קניין רוחני',
                      body:
                          'כל הזכויות בפלטפורמה AnySkill — לרבות קוד, עיצוב, לוגו, שם המותג, '
                          'וחוויית המשתמש — שייכות ל-AnySkill בלבד.\n\n'
                          '• המשתמש מקבל רישיון שימוש אישי, מוגבל, ולא-ייחודי לגישה לפלטפורמה.\n'
                          '• אין להעתיק, לשכפל, לפרסם מחדש, לבצע הנדסה לאחור, '
                          'או ליצור יצירות נגזרות מהפלטפורמה.\n'
                          '• תוכן שהמשתמש מעלה לפלטפורמה (תמונות, ביקורות, פרופיל) '
                          'מעניק ל-AnySkill רישיון להציגו בתוך הפלטפורמה.',
                    ),
                    const SizedBox(height: 16),

                    // ── 12. Privacy ────────────────────────────────────────────
                    _section(
                      number: '12',
                      icon: Icons.privacy_tip_outlined,
                      color: _kPurple,
                      title: 'מדיניות פרטיות',
                      body:
                          'AnySkill אוספת ומעבדת מידע אישי הנדרש לתפעול השירות:\n'
                          '• מידע זיהוי: שם, אימייל, מספר טלפון, תמונה.\n'
                          '• מידע פיננסי: גרסה מוצפנת של פרטי תשלום בתקן PCI DSS. '
                          'AnySkill לא שומרת מספרי כרטיסי אשראי שלמים על שרתיה.\n'
                          '• מידע שימוש: היסטוריית הזמנות, עסקאות, שיחות תמיכה.\n'
                          '• מידע מיקום: משוער, לצורך תצוגת ספקים בקרבת מקום.\n\n'
                          'עקרונות שימוש:\n'
                          '• AnySkill לא תמכור, תשכיר, או תעביר מידע אישי לצדדים שלישיים '
                          'למטרות שיווק.\n'
                          '• שיתוף מוגבל עם שותפים טכנולוגיים (Firebase / Google) כחלק '
                          'מתפעול השירות, בכפוף לתנאי הפרטיות שלהם.\n'
                          '• המשתמש רשאי לבקש עיון, תיקון, או מחיקת מידע אישי '
                          'בפנייה ל-support@anyskill.app. '
                          'מחיקת חשבון תתבצע תוך 30 יום ממועד הבקשה.',
                    ),
                    const SizedBox(height: 16),

                    // ── 13. Changes ────────────────────────────────────────────
                    _section(
                      number: '13',
                      icon: Icons.update_rounded,
                      color: Colors.grey,
                      title: 'שינויים בתנאים',
                      body:
                          'AnySkill שומרת לעצמה הזכות לעדכן תנאים אלה בכל עת. '
                          'שינויים מהותיים יימסרו בהודעה דחיפה (Push) ו/או בבאנר באפליקציה '
                          'לפחות 14 ימים לפני כניסתם לתוקף.\n\n'
                          'המשך שימוש בפלטפורמה לאחר מועד כניסת השינויים לתוקף '
                          'מהווה הסכמה מלאה ובלתי חוזרת לתנאים המעודכנים. '
                          'גרסה ארכיונית של כל עדכון שמורה וזמינה לעיון לפי בקשה.',
                    ),
                    const SizedBox(height: 16),

                    // ── 14. Governing Law ──────────────────────────────────────
                    _section(
                      number: '14',
                      icon: Icons.location_city_rounded,
                      color: Colors.grey,
                      title: 'דין חל ושיפוט',
                      body:
                          'הסכם זה כפוף לדיני מדינת ישראל.\n\n'
                          'כל מחלוקת משפטית שלא הוכרעה דרך מנגנון הבוררות הפנימי '
                          'תובא בפני בתי המשפט המוסמכים במחוז תל אביב בלבד, '
                          'והצדדים מקבלים עליהם את סמכות השיפוט הייחודית של בתי משפט אלה.\n\n'
                          'ויתור של AnySkill על הפעלת זכות מסוימת לא ייחשב כויתור גורף. '
                          'אם ייקבע שסעיף כלשהו בהסכם זה אינו אכיף, יתר הסעיפים יישארו בתוקף מלא.',
                    ),
                    const SizedBox(height: 32),

                    // ── Footer ────────────────────────────────────────────────
                    Center(
                      child: Text(
                        '© AnySkill 2026. כל הזכויות שמורות.\nsupport@anyskill.app',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.grey[400], height: 1.6),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            if (showAcceptButton)
              _AcceptButton(onTap: () => Navigator.pop(context, true)),
          ],
        ),
      ),
    );
  }

  // ── Section widgets ──────────────────────────────────────────────────────────

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
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
                  color: iconColor.withValues(alpha: 0.15),
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
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: iconColor),
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

// ── Table of Contents pill bar ─────────────────────────────────────────────────

class _TocBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const topics = [
      'פלטפורמה',
      'קבלן עצמאי',
      'נאמנות',
      'מס',
      'אחריות',
      'פרטיות',
      'בוררות',
    ];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: topics.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _kPurpleSoft,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(topics[i],
              style: const TextStyle(
                  fontSize: 11.5,
                  color: _kPurple,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

// ── Bottom "Accept" button ─────────────────────────────────────────────────────

class _AcceptButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AcceptButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: _kPurple,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: Text(
            AppLocalizations.of(context).tosAcceptButton,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
