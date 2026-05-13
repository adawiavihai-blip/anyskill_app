/// Mockup 11 — 3-slide onboarding shown ONCE on the first time a v2
/// viewer enters [CommunityHubScreenV2].
///
/// **Slide 2 is critical:** it's the only place that explicitly tells
/// the user the gold heart is temporary (30 days, renews on each new
/// completion). Per Phase B kickoff, this is the user-education
/// surface for the new mechanic.
///
/// **Persistence:** the "seen" flag lives in [SharedPreferences] under
/// the key [_kSeenKey]. We deliberately do NOT write to Firestore —
/// keeps the cost at zero and lets each device decide independently
/// (a user reinstalling the app sees onboarding again, which is OK).
///
/// **Entry behavior:** [CommunityV2OnboardingGate.shouldShow] checks
/// the flag. Callers should `await` it once on screen mount and push
/// this screen if it returns `true`.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/community_theme.dart';
import '../../widgets/community/primary_button.dart';

const String _kSeenKey = 'community_v2_onboarding_seen';

/// Helper used by [CommunityHubScreenV2] to decide whether to push
/// the onboarding screen on mount. Idempotent — second call returns
/// `false` once the flag is set.
class CommunityV2OnboardingGate {
  CommunityV2OnboardingGate._();

  static Future<bool> shouldShow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return !(prefs.getBool(_kSeenKey) ?? false);
    } catch (_) {
      // SharedPreferences failure — degrade gracefully (don't block hub).
      return false;
    }
  }

  static Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSeenKey, true);
    } catch (_) {/* non-blocking */}
  }
}

class OnboardingIntroScreen extends StatefulWidget {
  const OnboardingIntroScreen({super.key});

  @override
  State<OnboardingIntroScreen> createState() => _OnboardingIntroScreenState();
}

class _OnboardingIntroScreenState extends State<OnboardingIntroScreen> {
  final _pageCtrl = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_index < 2) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    await CommunityV2OnboardingGate.markSeen();
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _skip() async {
    await CommunityV2OnboardingGate.markSeen();
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CommunityColors.primaryWhite,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _index = i),
                children: const [
                  _SlideOne(),
                  _SlideTwo(),
                  _SlideThree(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: CommunityPrimaryButton(
                label: _index < 2 ? 'המשך' : 'בוא נתחיל',
                onPressed: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 14, 18, 0),
      child: Row(
        children: [
          // "דלג" — skip on slides 1 + 2 only (slide 3's CTA is "בוא נתחיל").
          _index < 2
              ? TextButton(
                  onPressed: _skip,
                  style: TextButton.styleFrom(
                    foregroundColor: CommunityColors.textMuted,
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 4),
                  ),
                  child: const Text(
                    'דלג',
                    style: TextStyle(
                      fontFamily: CommunityType.fontFamily,
                      fontSize: 13,
                    ),
                  ),
                )
              : const SizedBox(width: 28),
          const Spacer(),
          // 3-pill progress indicator
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final active = i == _index;
              return Padding(
                padding: const EdgeInsetsDirectional.only(end: 4),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  width: 18,
                  height: 3,
                  decoration: BoxDecoration(
                    color: active
                        ? CommunityColors.primaryBlack
                        : const Color(0x1A000000), // 10% black
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const Spacer(),
          const SizedBox(width: 28),
        ],
      ),
    );
  }
}

// ─── Slide 1: "אנשים סביבך צריכים עזרה" ─────────────────────────────
class _SlideOne extends StatelessWidget {
  const _SlideOne();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          // Stacked overlapping cards illustration
          Expanded(
            child: Center(
              child: SizedBox(
                width: 280,
                height: 200,
                child: Stack(
                  children: [
                    PositionedDirectional(
                      top: 60, end: 8,
                      width: 196,
                      child: _miniCard(
                        title: 'עזרה בקניות',
                        meta: 'רחל ב. · קרוב אליך',
                        opacity: 1,
                      ),
                    ),
                    PositionedDirectional(
                      top: 24, end: 30,
                      width: 168,
                      child: _miniCard(
                        title: 'שיעור מתמטיקה',
                        meta: 'אונליין',
                        opacity: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'אנשים סביבך\nצריכים עזרה',
                  style: TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                    height: 1.2,
                    color: CommunityColors.textPrimary,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'בקשות אמיתיות מהשכונה שלך — קשישים, חיילים בודדים, '
                  'משפחות.',
                  style: TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 13,
                    color: CommunityColors.textTertiary,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _miniCard({
    required String title,
    required String meta,
    required double opacity,
  }) {
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: CommunityColors.primaryWhite,
          border:
              Border.all(color: CommunityColors.borderSubtle, width: 0.5),
          borderRadius: const BorderRadius.all(CommunityRadius.card),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: CommunityType.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CommunityColors.textPrimary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              meta,
              style: const TextStyle(
                fontFamily: CommunityType.fontFamily,
                fontSize: 10,
                color: CommunityColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Slide 2 (CRITICAL): "לב זהב על הפרופיל אחרי כל התנדבות" ────────
class _SlideTwo extends StatelessWidget {
  const _SlideTwo();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          Expanded(
            child: Center(
              child: SizedBox(
                width: 100, height: 100,
                child: Stack(
                  children: [
                    Container(
                      width: 88, height: 88,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF4F46E5),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'דנ',
                        style: TextStyle(
                          fontFamily: CommunityType.fontFamily,
                          fontSize: 28,
                          fontWeight: FontWeight.w500,
                          color: CommunityColors.primaryWhite,
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      bottom: -4, end: -4,
                      child: Container(
                        width: 32, height: 32,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: CommunityColors.primaryWhite,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x40A87F2A),
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.favorite,
                          size: 20,
                          color: CommunityColors.goldHeart,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'לב זהב על הפרופיל\nאחרי כל התנדבות',
                  style: TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                    height: 1.2,
                    color: CommunityColors.textPrimary,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'כל פעם שתתנדב/י — תקבל/י לב זהב למשך 30 יום שיוצג '
                  'ללקוחות בחיפוש. התנדבות חדשה מאריכה את הזמן.',
                  style: TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 13,
                    color: CommunityColors.textTertiary,
                    height: 1.55,
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

// ─── Slide 3: "כללים שמגנים על הקהילה" ─────────────────────────────
class _SlideThree extends StatelessWidget {
  const _SlideThree();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Facepile of 4 sample volunteers
                  SizedBox(
                    height: 42,
                    width: 42 + 3 * 32.0,
                    child: Stack(
                      children: [
                        for (int i = 0; i < 4; i++)
                          PositionedDirectional(
                            start: i * 32.0,
                            child: Container(
                              width: 42, height: 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const [
                                  Color(0xFF4F46E5),
                                  Color(0xFFDB2777),
                                  Color(0xFF059669),
                                  Color(0xFFF59E0B),
                                ][i],
                                border: Border.all(
                                    color: CommunityColors.primaryWhite,
                                    width: 2.5),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                const ['דנ', 'מי', 'יו', 'אב'][i],
                                style: const TextStyle(
                                  fontFamily: CommunityType.fontFamily,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: CommunityColors.primaryWhite,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '42 מתנדבים',
                    style: TextStyle(
                      fontFamily: CommunityType.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: CommunityColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'פעילים בשכונה שלך החודש',
                    style: TextStyle(
                      fontFamily: CommunityType.fontFamily,
                      fontSize: 12,
                      color: CommunityColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'כללים שמגנים\nעל הקהילה',
                  style: TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                    height: 1.2,
                    color: CommunityColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'אין תשלום, אין הונאות. כל התנדבות מאומתת.',
                  style: TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 13,
                    color: CommunityColors.textTertiary,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    _SafetyChip(label: 'תמונת הוכחה'),
                    _SafetyChip(label: 'דירוג דו-צדדי'),
                    _SafetyChip(label: '15 דק׳ מינימום'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetyChip extends StatelessWidget {
  const _SafetyChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: const BoxDecoration(
        color: CommunityColors.surface,
        borderRadius: BorderRadius.all(CommunityRadius.pill),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: CommunityType.fontFamily,
          fontSize: 11,
          color: CommunityColors.textSecondary,
        ),
      ),
    );
  }
}
