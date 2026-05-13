/// Mockup 15 — Special "first gold heart" screen, shown ONCE in a
/// volunteer's lifetime, immediately after their first ever completed
/// community task.
///
/// **When this screen is shown:**
/// - Pushed by [CompletionCelebrationScreen] (mockup 06) when its data
///   loader observes `users/{uid}.volunteerTaskCount <= 1`. On every
///   subsequent completion, mockup 06's primary CTA pops back to the
///   feed without showing this screen.
///
/// **Critical message:** the screen MUST emphasize that the heart is
/// temporary (30 days) and renews on each new completion — that's the
/// only way the user understands the new mechanic. The "**30 יום**"
/// fragment is rendered in gold inside the body text per the mockup.
///
/// **Data source:** just `users/{currentUid}` for the first name.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../theme/community_theme.dart';

class FirstGoldHeartScreen extends StatefulWidget {
  const FirstGoldHeartScreen({super.key});

  @override
  State<FirstGoldHeartScreen> createState() => _FirstGoldHeartScreenState();
}

class _FirstGoldHeartScreenState extends State<FirstGoldHeartScreen> {
  late final Future<String> _firstNameFuture = _loadFirstName();

  Future<String> _loadFirstName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 'מתנדב/ת';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final raw = (snap.data()?['name'] as String? ?? '').trim();
      if (raw.isEmpty) return 'מתנדב/ת';
      final first = raw.split(RegExp(r'\s+')).first;
      return first.isEmpty ? 'מתנדב/ת' : first;
    } catch (_) {
      return 'מתנדב/ת';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Linear gradient #18181B → #1F1F23 per mockup 15.
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              CommunityColors.darkSurfaceTop,
              CommunityColors.darkSurfaceBot,
            ],
          ),
        ),
        child: Stack(
          children: [
            // ── Top radial gold highlight ─────────────────────────────
            Positioned(
              top: -100,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color(0x33A87F2A), // gold @ 20%
                        Color(0x00A87F2A), // transparent
                      ],
                      stops: [0.0, 0.65],
                    ),
                  ),
                ),
              ),
            ),

            // ── Foreground content ────────────────────────────────────
            SafeArea(
              child: FutureBuilder<String>(
                future: _firstNameFuture,
                builder: (context, snap) {
                  final firstName = snap.data ?? 'מתנדב/ת';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // X close button — pops to first route (feed).
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                            18, 14, 18, 0),
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: IconButton(
                            iconSize: 18,
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            color: CommunityColors.whiteSoft,
                            onPressed: () => Navigator.of(context)
                                .popUntil((r) => r.isFirst),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 32),
                              Center(child: _hero()),
                              const SizedBox(height: 24),
                              const Center(
                                child: Text(
                                  'לב זהב הוענק',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: CommunityType.fontFamily,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.5,
                                    color: Color(0xE6A87F2A), // gold @ 90%
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Center(
                                child: Text(
                                  '$firstName,\nקיבלת את הלב הראשון.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontFamily: CommunityType.fontFamily,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.6,
                                    height: 1.2,
                                    color: CommunityColors.whiteHigh,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Center(
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 280),
                                  child: const _BodyWithGoldEmphasis(),
                                ),
                              ),
                              const SizedBox(height: 28),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  'מה זה אומר עבורך',
                                  style: TextStyle(
                                    fontFamily: CommunityType.fontFamily,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.2,
                                    color: CommunityColors.whiteFaint,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              const _BenefitRow(
                                title: 'סימן אמון על הפרופיל',
                                subtitle:
                                    'לקוחות רואים שאתה תורם לקהילה',
                                isFirst: true,
                              ),
                              const _BenefitRow(
                                title: 'קידום בחיפוש למשך 30 יום',
                                subtitle:
                                    'תופיע גבוה יותר ללקוחות באזורך',
                              ),
                              const _BenefitRow(
                                title: 'פתקי תודה אמיתיים',
                                subtitle:
                                    'יוצגו בפרופיל הציבורי שלך',
                                isLast: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                        child: Column(
                          children: [
                            _whiteCta(
                              label: 'הצג את הפרופיל החדש שלי',
                              onPressed: () => Navigator.of(context)
                                  .popUntil((r) => r.isFirst),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => Navigator.of(context)
                                  .popUntil((r) => r.isFirst),
                              child: const Text(
                                'המשך לחפש בקשות',
                                style: TextStyle(
                                  fontFamily: CommunityType.fontFamily,
                                  fontSize: 12,
                                  color: CommunityColors.whiteSoft,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Hero medallion: 88×88 with concentric gold rings ──────────────────
  Widget _hero() {
    return SizedBox(
      width: 104,
      height: 104,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer faint ring (mockup `inset: -8`)
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0x26A87F2A), // gold @ 15%
                width: 0.5,
              ),
            ),
          ),
          // Inner ring + tinted bg
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0x1FA87F2A), // gold @ 12%
              border: Border.all(
                color: const Color(0x66A87F2A), // gold @ 40%
                width: 0.5,
              ),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.favorite,
              size: 44,
              color: CommunityColors.goldHeart,
            ),
          ),
        ],
      ),
    );
  }

  Widget _whiteCta({required String label, required VoidCallback onPressed}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: CommunityColors.primaryWhite,
          foregroundColor: CommunityColors.textPrimary,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(CommunityRadius.pill),
          ),
          minimumSize: const Size(double.infinity, 46),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: CommunityType.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }
}

/// Body paragraph with the "30 יום" fragment emphasized in gold.
class _BodyWithGoldEmphasis extends StatelessWidget {
  const _BodyWithGoldEmphasis();

  @override
  Widget build(BuildContext context) {
    const baseStyle = TextStyle(
      fontFamily: CommunityType.fontFamily,
      fontSize: 13,
      color: CommunityColors.whiteMid,
      height: 1.6,
    );
    const goldStyle = TextStyle(
      fontFamily: CommunityType.fontFamily,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Color(0xF2A87F2A), // gold @ 95%
      height: 1.6,
    );
    return RichText(
      textAlign: TextAlign.center,
      text: const TextSpan(
        style: baseStyle,
        children: [
          TextSpan(
            text: 'סיימת את ההתנדבות הראשונה שלך. הלב הזהב יוצג על '
                'הפרופיל למשך ',
          ),
          TextSpan(text: '30 יום', style: goldStyle),
          TextSpan(
            text: '. כל התנדבות חדשה תאריך את הזמן ל-30 יום נוספים.',
          ),
        ],
      ),
    );
  }
}

/// One benefit row with a gold checkmark + title + subtitle, separated
/// by 0.5px white@0.08 dividers per mockup 15.
class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.title,
    required this.subtitle,
    this.isFirst = false,
    this.isLast = false,
  });

  final String title;
  final String subtitle;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          top: isFirst
              ? BorderSide.none
              : const BorderSide(
                  color: Color(0x14FFFFFF), // 8% white
                  width: 0.5,
                ),
          bottom: isLast
              ? const BorderSide(
                  color: Color(0x14FFFFFF), // 8% white
                  width: 0.5,
                )
              : BorderSide.none,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.check_rounded,
              size: 16,
              color: Color(0xCCA87F2A), // gold @ 80%
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1,
                    color: CommunityColors.whiteHigh,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 11,
                    color: CommunityColors.whiteSoft,
                    height: 1.5,
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
