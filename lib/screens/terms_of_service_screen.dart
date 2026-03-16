import 'package:flutter/material.dart';

// Brand tokens (match sign_up_screen palette)
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
          title: const Text(
            'תנאי שימוש ופרטיות',
            style: TextStyle(
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
                    // ── Last updated ─────────────────────────────────────────
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: _kPurpleSoft,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'עדכון אחרון: מרץ 2026',
                          style: TextStyle(
                              fontSize: 12,
                              color: _kPurple,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    _section(
                      icon: Icons.info_outline_rounded,
                      color: _kPurple,
                      title: '1. מהי AnySkill?',
                      body:
                          'AnySkill היא פלטפורמת תיווך דיגיטלית המאפשרת קישור בין לקוחות לבין נותני שירות מקצועיים ("ספקים") בתחומים שונים. '
                          'AnySkill אינה מעסיקה את הספקים ואינה צד ישיר בהסכם השירות בין הלקוח לספק. '
                          'כל ספק הינו עצמאי ואחראי באופן מלא לאיכות, לבטיחות ולחוקיות השירות שהוא מספק.',
                    ),
                    const SizedBox(height: 16),

                    // ── ESCROW — highlighted ──────────────────────────────────
                    _highlightedSection(
                      icon: Icons.lock_rounded,
                      iconColor: const Color(0xFF10B981),
                      bgColor: const Color(0xFFF0FDF4),
                      borderColor: const Color(0xFF6EE7B7),
                      title: '2. מודל התשלום — נאמנות (Escrow)',
                      body:
                          'כל תשלום שמבצע לקוח מוחזק בחשבון נאמנות מאובטח של AnySkill '
                          'ואינו מועבר לספק עד שהלקוח מאשר השלמת השירות. '
                          'מנגנון זה מגן על הלקוח מפני תשלום עבור שירות שלא סופק.\n\n'
                          '• לאחר שהספק מסמן "סיימתי את העבודה", הלקוח יקבל הודעה.\n'
                          '• הלקוח יכול לאשר שחרור התשלום, לפתוח מחלוקת, או לבטל (בכפוף למדיניות הביטול).\n'
                          '• AnySkill גובה עמלת שירות מסכום כל עסקה מוצלחת. שיעור העמלה מוצג בהגדרות.',
                    ),
                    const SizedBox(height: 16),

                    // ── CANCELLATION — highlighted ────────────────────────────
                    _highlightedSection(
                      icon: Icons.cancel_outlined,
                      iconColor: const Color(0xFFF59E0B),
                      bgColor: const Color(0xFFFFFBEB),
                      borderColor: const Color(0xFFFDE68A),
                      title: '3. מדיניות ביטולים',
                      body:
                          'כל ספק קובע את מדיניות הביטול שלו. שלושה מסלולים אפשריים:\n\n'
                          '🟢 גמישה — ביטול חינם עד 4 שעות לפני המפגש. ביטול מאוחר יותר: קנס 50%.\n'
                          '🟡 בינונית — ביטול חינם עד 24 שעות לפני. ביטול מאוחר יותר: קנס 50%.\n'
                          '🔴 קפדנית — ביטול חינם עד 48 שעות לפני. ביטול מאוחר יותר: קנס 100%.\n\n'
                          'ביטול מצד הספק תמיד מזכה את הלקוח בהחזר מלא.\n'
                          'חלון הביטול המדויק מוצג בסיכום ההזמנה לפני האישור.',
                    ),
                    const SizedBox(height: 16),

                    _section(
                      icon: Icons.gavel_rounded,
                      color: const Color(0xFF6366F1),
                      title: '4. אחריות משתמשים',
                      body:
                          '• הלקוח מתחייב לספק מידע מדויק בעת ההזמנה ולנהוג בכבוד כלפי הספק.\n'
                          '• הספק מתחייב לספק את השירות שפורסם, במועד שנקבע, ברמה מקצועית.\n'
                          '• חל איסור מוחלט על ביצוע עסקאות מחוץ לפלטפורמה, הטרדה מינית, או שימוש אלים.',
                    ),
                    const SizedBox(height: 16),

                    _section(
                      icon: Icons.shield_outlined,
                      color: const Color(0xFF6366F1),
                      title: '5. יישוב מחלוקות',
                      body:
                          'במקרה של מחלוקת בין הלקוח לספק, ניתן לפתוח בקשת בוררות דרך האפליקציה. '
                          'צוות AnySkill יבחן את המקרה ויוציא החלטה תוך 48 שעות. '
                          'ניתן לקבל: החזר מלא ללקוח, שחרור לספק, או פשרה 50/50 — על פי שיקול דעת הצוות.',
                    ),
                    const SizedBox(height: 16),

                    _section(
                      icon: Icons.privacy_tip_outlined,
                      color: const Color(0xFF6366F1),
                      title: '6. מדיניות פרטיות',
                      body:
                          '• AnySkill אוספת: שם, אימייל, מספר טלפון, מיקום משוער, היסטוריית עסקאות.\n'
                          '• המידע משמש אך ורק לצורך הפעלת השירות, שיפור חווית המשתמש, ותמיכה.\n'
                          '• AnySkill לא תמכור מידע אישי לצדדים שלישיים.\n'
                          '• נתוני תשלום מוצפנים ומאוחסנים בתקן PCI DSS.\n'
                          '• משתמש רשאי לבקש מחיקת חשבון בפנייה לתמיכה.',
                    ),
                    const SizedBox(height: 16),

                    _section(
                      icon: Icons.update_rounded,
                      color: Colors.grey,
                      title: '7. שינויים בתנאים',
                      body:
                          'AnySkill שומרת לעצמה הזכות לעדכן תנאים אלה בכל עת. '
                          'שינויים מהותיים יימסרו בהודעה באפליקציה. '
                          'המשך השימוש לאחר פרסום השינויים מהווה הסכמה לתנאים החדשים.',
                    ),
                    const SizedBox(height: 32),
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

  // ── Section widgets ─────────────────────────────────────────────────────────

  Widget _section({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: const TextStyle(
              fontSize: 13.5, height: 1.65, color: Colors.black87),
        ),
      ],
    );
  }

  Widget _highlightedSection({
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
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
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
                fontSize: 13.5, height: 1.65, color: Colors.black87),
          ),
        ],
      ),
    );
  }
}

// ── Bottom "Accept" button ────────────────────────────────────────────────────
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
          child: const Text(
            'הבנתי ומסכים/ה — חזור לרישום',
            style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
