import 'package:flutter/material.dart';
import 'category_results_screen.dart';

class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      body: CustomScrollView(
        slivers: [
          // ── Collapsing hero image AppBar ─────────────────────────────────
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: true,
              title: const Text(
                'AnySkill למען הקהילה',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black45)],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    'https://images.unsplash.com/photo-1593113598332-cd288d649433?w=800',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF10B981), Color(0xFF6366F1)],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        ),
                      ),
                      child: const Center(
                        child: Icon(Icons.volunteer_activism,
                            size: 80, color: Colors.white),
                      ),
                    ),
                  ),
                  // Gradient scrim so title stays readable
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Body content ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Mission statement ───────────────────────────────────
                  const Text(
                    'AnySkill למען הקהילה',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'יוזמה ייחודית שבה מומחים מוסמכים מתנדבים מרצונם '
                    'ומעניקים את שירותיהם המקצועיים ללא כל עלות לאנשים '
                    'שזקוקים לעזרה בקהילה. כאן תמצאו שיפוץ, ניקיון, '
                    'עיצוב, הוראה ועוד — הכל ממקום של נתינה אמיתית.',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 15,
                      color: Color(0xFF4B5563),
                      height: 1.65,
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Three highlight cards ───────────────────────────────
                  _HighlightCard(
                    icon: Icons.favorite,
                    color: const Color(0xFFEF4444),
                    title: 'ממקום של לב',
                    body: 'המומחים שלנו בוחרים להתנדב — ללא תשלום, ללא תמורה.',
                  ),
                  const SizedBox(height: 12),
                  _HighlightCard(
                    icon: Icons.verified_user_outlined,
                    color: const Color(0xFF6366F1),
                    title: 'מומחים מאומתים',
                    body: 'כל מתנדב עבר אימות זהות ואישור מקצועי על ידי AnySkill.',
                  ),
                  const SizedBox(height: 12),
                  _HighlightCard(
                    icon: Icons.groups_outlined,
                    color: const Color(0xFF10B981),
                    title: 'קהילה שמחזקת קהילה',
                    body: 'כל שירות שניתן מחזק את הקשר בין שכנים ובונה עתיד טוב יותר.',
                  ),

                  const SizedBox(height: 36),

                  // ── CTA buttons ─────────────────────────────────────────
                  ElevatedButton.icon(
                    onPressed: () {
                      // TODO: Navigate to volunteer registration / profile flag
                    },
                    icon: const Icon(Icons.volunteer_activism, size: 20),
                    label: const Text(
                      'אני רוצה להתנדב',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 54),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                  ),

                  const SizedBox(height: 12),

                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CategoryResultsScreen(
                          categoryName: 'volunteer',
                          volunteerOnly: true,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.search, size: 20),
                    label: const Text(
                      'חיפוש מומחים מתנדבים',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF10B981),
                      minimumSize: const Size(double.infinity, 54),
                      side: const BorderSide(
                          color: Color(0xFF10B981), width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Text(
                    'הצטרפו אלינו לשינוי',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[400],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Highlight info card ───────────────────────────────────────────────────────

class _HighlightCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  const _HighlightCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
        ],
      ),
    );
  }
}
