import 'package:flutter/material.dart';

// ── AnySkill Pro Badge ────────────────────────────────────────────────────────
//
// Displays a small logo + "AnySkill Pro" label.
// Tapping opens a BottomSheet explaining the Pro criteria to customers.
//
// Usage:
//   if (isPro) ProBadge()                          // card-size (default)
//   if (isPro) ProBadge(large: true)               // profile hero-size
// ─────────────────────────────────────────────────────────────────────────────

class ProBadge extends StatelessWidget {
  /// When true renders a slightly larger pill — for the expert profile hero.
  final bool large;
  const ProBadge({super.key, this.large = false});

  @override
  Widget build(BuildContext context) {
    final logoSize    = large ? 18.0 : 13.0;
    final fontSize    = large ? 12.0 : 9.5;
    final hPad        = large ? 9.0  : 6.0;
    final vPad        = large ? 4.0  : 3.0;
    final radius      = large ? 20.0 : 16.0;

    return GestureDetector(
      onTap: () => _showExplanation(context),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/NEW_LOGO1.png.png',
              width:  logoSize,
              height: logoSize,
              fit:    BoxFit.contain,
            ),
            const SizedBox(width: 4),
            Text(
              'AnySkill Pro',
              style: TextStyle(
                color:      Colors.white,
                fontSize:   fontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showExplanation(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _ProExplanationSheet(),
    );
  }
}

// ── Explanation bottom sheet ──────────────────────────────────────────────────

class _ProExplanationSheet extends StatelessWidget {
  const _ProExplanationSheet();

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight   = MediaQuery.of(context).size.height * 0.90;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      // ── Pinned header (handle + logo row) ──────────────────────────────────
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle — always visible at top
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // Logo + title — always visible
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Image.asset(
                    'assets/images/NEW_LOGO1.png.png',
                    width: 28, height: 28,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'מה זה AnySkill Pro?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ],
            ),
          ),

          // ── Scrollable body ────────────────────────────────────────────────
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 12, 24, 16 + bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
          Text(
            'תג הפרו מוענק אוטומטית לספקים שעמדו בכל הסטנדרטים הגבוהים ביותר.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),

          // Criteria list
          _CriterionRow(
            emoji: '⭐',
            title: 'דירוג גבוה',
            subtitle: 'ציון 4.8 ומעלה מלקוחות אמיתיים',
          ),
          _CriterionRow(
            emoji: '🏆',
            title: 'ניסיון מוכח',
            subtitle: '20 עסקאות שהושלמו בהצלחה',
          ),
          _CriterionRow(
            emoji: '⚡',
            title: 'תגובה מהירה',
            subtitle: 'זמן תגובה ממוצע של פחות מ-15 דקות',
          ),
          _CriterionRow(
            emoji: '🛡️',
            title: 'אמינות מושלמת',
            subtitle: 'אפס ביטולים מצד הספק ב-30 הימים האחרונים',
          ),
          const SizedBox(height: 20),

          // Close button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: const Text(
                'הבנתי',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 30), // breathing room at bottom
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CriterionRow extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  const _CriterionRow({
    required this.emoji,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Emoji icon circle
          Container(
            width: 36, height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
