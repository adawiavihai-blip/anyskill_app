// Fitness Trainer CSM — Client booking block ("להתאמת האימון שלך").
// Appears in expert_profile_screen.dart BETWEEN the "אודות" section and the
// "השירות" section AND ONLY when the provider's sub-category resolves to
// "מאמני כושר" via isFitnessTrainerCategory().
//
// 10 sections (spec 01_MAIN_PROMPT.md):
//   1. AI Match Quiz CTA (purple gradient button → PersonalityQuizScreen)
//   2. Personality Match Result (94% in GREEN GLOW + 4 reason cards)
//   3. Specialties display (read-only colorful chips)
//   4. Packages carousel (horizontal, popular elevated)
//   5. Locations grid (3 cards: home / park / gym — NO online)
//   6. Certifications list (read-only with ✓ verified badges)
//   7. Monthly Journey Preview — Apple-style 3 rings + 4 stats + "Top 15%"
//   8. Success Story card (before/after + testimonial + rating)
//   9. Trust Badges Grid (4 guarantees in 2×2)
//  10. Active Offer Banner (urgency — dashed border + countdown)
//
// Design palette: LIGHT (client-facing) — cream/white with orange/gold/green/purple accents.
// Same design tokens as provider block but on a light canvas.
// Hebrew RTL throughout.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/fitness_trainer_profile.dart';
import 'personality_quiz_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SCOPED PALETTE (light — client-facing)
// ═══════════════════════════════════════════════════════════════════════════

class _FCPalette {
  static const orange = Color(0xFFFF6B35);
  static const gold = Color(0xFFF59E0B);
  static const green = Color(0xFF10B981);
  static const red = Color(0xFFEF4444);
  static const purple = Color(0xFF8B5CF6);
  static const blue = Color(0xFF3B82F6);

  static const textDark = Color(0xFF1F2937);
  static const textMedium = Color(0xFF6B7280);
  static const textLight = Color(0xFF9CA3AF);
  static const bgWhite = Color(0xFFFFFFFF);
  static const bgCream = Color(0xFFFFF8F3);
  static const bgGray = Color(0xFFFAFBFC);
  static const borderOrange = Color(0xFFFED7AA);
  static const borderGray = Color(0xFFE5E7EB);

  // Apple Activity ring colors
  static const ringMove = Color(0xFFFF455A); // red
  static const ringExercise = Color(0xFF32D74B); // green
  static const ringStand = Color(0xFF00C7BE); // turquoise
}

// ═══════════════════════════════════════════════════════════════════════════
// PUBLIC WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class FitnessTrainerBookingBlock extends StatefulWidget {
  /// The provider's fitness profile (loaded from
  /// `users/{uid}.fitnessTrainerProfile`).
  final FitnessTrainerProfile profile;

  /// Display name of the trainer — used in the match-result header
  /// and in the quiz screen.
  final String trainerName;

  /// Trainer id — forwarded to the match quiz CF.
  final String trainerId;

  /// Optional: called when the client taps a package card. The parent
  /// expert_profile_screen can use this to pre-fill the existing
  /// "Pay & Secure" flow. If null, tap is a no-op.
  final ValueChanged<PricingPackage>? onPackageSelected;

  const FitnessTrainerBookingBlock({
    super.key,
    required this.profile,
    required this.trainerName,
    required this.trainerId,
    this.onPackageSelected,
  });

  @override
  State<FitnessTrainerBookingBlock> createState() =>
      _FitnessTrainerBookingBlockState();
}

class _FitnessTrainerBookingBlockState
    extends State<FitnessTrainerBookingBlock> {
  QuizMatchResult? _quizResult;

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 14, horizontal: 0),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_FCPalette.bgCream, _FCPalette.bgWhite],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _FCPalette.borderOrange),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeroHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildAiQuizCta(),
                  if (_quizResult != null) ...[
                    const SizedBox(height: 14),
                    _buildMatchResult(_quizResult!),
                  ],
                  const SizedBox(height: 14),
                  if (p.selectedSpecialties.isNotEmpty) ...[
                    _buildSpecialties(),
                    const SizedBox(height: 14),
                  ],
                  if (p.packages.isNotEmpty) ...[
                    _buildPackagesCarousel(),
                    const SizedBox(height: 14),
                  ],
                  if (p.locations.isNotEmpty) ...[
                    _buildLocationsGrid(),
                    const SizedBox(height: 14),
                  ],
                  if (p.certifications.isNotEmpty) ...[
                    _buildCertificationsList(),
                    const SizedBox(height: 14),
                  ],
                  _buildMonthlyJourney(), // always visible (WOW factor)
                  if (p.successStories.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _buildSuccessStory(),
                  ],
                  const SizedBox(height: 14),
                  _buildTrustBadges(),
                  if (p.activeOffers.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _buildActiveOfferBanner(p.activeOffers.first),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HERO HEADER (thin strip at top of the block)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildHeroHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _FCPalette.orange.withValues(alpha: 0.12),
            _FCPalette.gold.withValues(alpha: 0.06),
          ],
        ),
        border: const Border(
          bottom: BorderSide(color: _FCPalette.borderOrange),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_FCPalette.orange, _FCPalette.gold],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'להתאמת האימון שלך',
                  style: TextStyle(
                    color: _FCPalette.textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '10 סקציות כדי לוודא התאמה מושלמת',
                  style: TextStyle(color: _FCPalette.textMedium, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _FCPalette.orange,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '🏋️ מאמני כושר',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 1. AI MATCH QUIZ CTA
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildAiQuizCta() {
    return InkWell(
      onTap: _openQuiz,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [_FCPalette.purple, Color(0xFF6366F1)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: _FCPalette.purple.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('🤖', style: TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'בדיקת התאמה אישית עם AI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '5 שאלות · 30 שניות · Gemini',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.24),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'חינם',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _quizResult == null
                        ? '✨ מצא את ההתאמה המושלמת'
                        : '✨ בדוק שוב את ההתאמה',
                    style: const TextStyle(
                      color: _FCPalette.purple,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.arrow_back_rounded,
                    color: _FCPalette.purple,
                    size: 18,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openQuiz() async {
    HapticFeedback.mediumImpact();
    final result = await Navigator.of(context).push<QuizMatchResult>(
      MaterialPageRoute(
        builder:
            (_) => PersonalityQuizScreen(
              trainerId: widget.trainerId,
              trainerName: widget.trainerName,
            ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _quizResult = result);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 2. PERSONALITY MATCH RESULT (green glow on the score)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildMatchResult(QuizMatchResult result) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _FCPalette.gold.withValues(alpha: 0.1),
            _FCPalette.orange.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _FCPalette.green.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _GlowingScoreCircle(score: result.matchScore),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🎯 התאמה מצוינת!',
                      style: TextStyle(
                        color: _FCPalette.textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'המאמנת ${widget.trainerName} מתאימה לפרופיל שלך לפי ה-AI',
                      style: const TextStyle(
                        color: _FCPalette.textMedium,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (ctx, cons) {
              final twoCol = cons.maxWidth >= 420;
              final itemW = twoCol ? (cons.maxWidth - 8) / 2 : cons.maxWidth;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    result.reasons.take(4).map((r) {
                      return SizedBox(
                        width: itemW,
                        child: _ReasonChip(reason: r),
                      );
                    }).toList(),
              );
            },
          ),
          if (result.isFallback) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _FCPalette.gold.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Text('ℹ️', style: TextStyle(fontSize: 12)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'ציון תקציר — הציון המלא יתעדכן לאחר חיבור ה-AI',
                      style: TextStyle(
                        color: Color(0xFF92400E),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 3. SPECIALTIES (read-only chips)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSpecialties() {
    final selected =
        widget.profile.selectedSpecialties
            .map((t) => TrainerSpecialty.byType(t))
            .whereType<TrainerSpecialty>()
            .toList();
    return _SectionCard(
      emoji: '🎯',
      title: 'תחומי התמחות',
      subtitle: '${selected.length} התמחויות שבהן המאמנת מתמחה',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children:
            selected.map((s) {
              final primary = Color(s.colors[0]);
              final secondary = Color(s.colors[1]);
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [primary, secondary]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(s.emoji, style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 6),
                    Text(
                      s.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 4. PACKAGES CAROUSEL (horizontal, popular elevated)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildPackagesCarousel() {
    final packages = widget.profile.packages;
    return _SectionCard(
      emoji: '💰',
      title: 'חבילות ומחירים',
      subtitle: 'גלול/י בצד ← לבחור',
      noPadding: true,
      child: SizedBox(
        height: 260,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          itemCount: packages.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (ctx, i) {
            final p = packages[i];
            return _PackageCard(
              package: p,
              onTap:
                  widget.onPackageSelected == null
                      ? null
                      : () {
                        HapticFeedback.selectionClick();
                        widget.onPackageSelected!(p);
                      },
            );
          },
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 5. LOCATIONS GRID (3 cards — NO online)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildLocationsGrid() {
    final locs = widget.profile.locations;
    return _SectionCard(
      emoji: '📍',
      title: 'איפה המאמנת מאמנת',
      subtitle: 'בחר/י את המיקום הנוח לך',
      child: LayoutBuilder(
        builder: (ctx, cons) {
          final threeUp = cons.maxWidth >= 520;
          final itemW =
              threeUp ? (cons.maxWidth - 16) / 3 : (cons.maxWidth - 8) / 2;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                locs.map((l) {
                  return SizedBox(
                    width: itemW,
                    child: _LocationCardRO(location: l),
                  );
                }).toList(),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 6. CERTIFICATIONS LIST (read-only + ✓ badges)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildCertificationsList() {
    final certs = widget.profile.certifications;
    return _SectionCard(
      emoji: '🎓',
      title: 'תעודות והסמכות',
      subtitle: 'הסמכות מקצועיות של המאמנת',
      child: Column(
        children:
            certs
                .map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _CertRowRO(cert: c),
                  ),
                )
                .toList(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 7. MONTHLY JOURNEY PREVIEW — THE WOW FACTOR (Apple 3 rings)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildMonthlyJourney() {
    return const _MonthlyJourneyCard();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 8. SUCCESS STORY CARD
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSuccessStory() {
    final story = widget.profile.successStories.first;
    return _SectionCard(
      emoji: '📸',
      title: 'סיפור הצלחה',
      subtitle: 'תוצאות אמיתיות של לקוחות',
      child: _StoryCardRO(story: story),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 9. TRUST BADGES GRID (4 in 2×2)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildTrustBadges() {
    return LayoutBuilder(
      builder: (ctx, cons) {
        final twoCol = cons.maxWidth >= 420;
        final itemW = twoCol ? (cons.maxWidth - 10) / 2 : cons.maxWidth;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: itemW,
              child: const _BadgeCard(
                emoji: '🛡️',
                title: 'הבטחת מרוצה',
                description: 'ביטול עד 4 שעות לפני',
                accent: _FCPalette.green,
              ),
            ),
            SizedBox(
              width: itemW,
              child: const _BadgeCard(
                emoji: '💯',
                title: 'החזר 100%',
                description: 'אם לא מרוצה מהאימון הראשון',
                accent: _FCPalette.blue,
              ),
            ),
            SizedBox(
              width: itemW,
              child: const _BadgeCard(
                emoji: '🔐',
                title: 'תשלום מאובטח',
                description: 'שירות נאמנות מוגן',
                accent: _FCPalette.purple,
              ),
            ),
            SizedBox(
              width: itemW,
              child: const _BadgeCard(
                emoji: '⭐',
                title: 'מאמן מאומת',
                description: 'תעודות ודירוגים נבדקו',
                accent: _FCPalette.gold,
              ),
            ),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 10. ACTIVE OFFER BANNER (dashed border + urgency)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildActiveOfferBanner(SpecialOffer offer) {
    return _ActiveOfferBanner(offer: offer);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PRIVATE WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _SectionCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final Widget child;
  final bool noPadding;
  const _SectionCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.child,
    this.noPadding = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _FCPalette.bgWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _FCPalette.borderGray),
      ),
      padding: EdgeInsets.all(noPadding ? 0 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding:
                noPadding
                    ? const EdgeInsets.fromLTRB(14, 14, 14, 4)
                    : EdgeInsets.zero,
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: _FCPalette.textDark,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: _FCPalette.textMedium,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _GlowingScoreCircle extends StatefulWidget {
  final int score;
  const _GlowingScoreCircle({required this.score});

  @override
  State<_GlowingScoreCircle> createState() => _GlowingScoreCircleState();
}

class _GlowingScoreCircleState extends State<_GlowingScoreCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) {
        final t = _ctrl.value;
        return Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_FCPalette.green, Color(0xFF059669)],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _FCPalette.green.withValues(alpha: 0.3 + t * 0.3),
                blurRadius: 16 + t * 14,
                spreadRadius: 1 + t * 4,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            '${widget.score}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
      },
    );
  }
}

class _ReasonChip extends StatelessWidget {
  final String reason;
  const _ReasonChip({required this.reason});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _FCPalette.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: _FCPalette.green,
            size: 18,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              reason,
              style: const TextStyle(
                color: _FCPalette.textDark,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  final PricingPackage package;
  final VoidCallback? onTap;
  const _PackageCard({required this.package, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isPopular = package.isPopular;
    final pricePer = package.pricePerSession.toStringAsFixed(0);
    return SizedBox(
      width: 200,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(14),
          transform:
              isPopular
                  ? Matrix4.translationValues(0.0, -6.0, 0.0)
                  : Matrix4.identity(),
          decoration: BoxDecoration(
            gradient:
                isPopular
                    ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_FCPalette.orange, _FCPalette.gold],
                    )
                    : null,
            color: isPopular ? null : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: isPopular ? null : Border.all(color: _FCPalette.borderGray),
            boxShadow:
                isPopular
                    ? [
                      BoxShadow(
                        color: _FCPalette.orange.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ]
                    : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isPopular)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '⭐ פופולרי',
                    style: TextStyle(
                      color: _FCPalette.orange,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              if (isPopular) const SizedBox(height: 10),
              Text(
                package.name,
                style: TextStyle(
                  color: isPopular ? Colors.white : _FCPalette.textDark,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                '${package.sessions} אימון · ${package.durationMinutes} דק׳',
                style: TextStyle(
                  color:
                      isPopular
                          ? Colors.white.withValues(alpha: 0.9)
                          : _FCPalette.textMedium,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₪${package.price}',
                    style: TextStyle(
                      color: isPopular ? Colors.white : _FCPalette.orange,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '₪$pricePer / אימון',
                      style: TextStyle(
                        color:
                            isPopular
                                ? Colors.white.withValues(alpha: 0.85)
                                : _FCPalette.textLight,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
              if (package.discount != null && package.discount! > 0) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isPopular
                            ? Colors.white.withValues(alpha: 0.25)
                            : _FCPalette.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'חיסכון ${package.discount}%',
                    style: TextStyle(
                      color: isPopular ? Colors.white : _FCPalette.green,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color:
                      isPopular
                          ? Colors.white
                          : _FCPalette.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  'בחר/י חבילה',
                  style: TextStyle(
                    color: isPopular ? _FCPalette.orange : _FCPalette.orange,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationCardRO extends StatelessWidget {
  final TrainingLocation location;
  const _LocationCardRO({required this.location});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _FCPalette.bgCream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _FCPalette.borderOrange),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(location.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  location.displayName,
                  style: const TextStyle(
                    color: _FCPalette.textDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'רדיוס ${location.radiusKm} ק״מ',
            style: const TextStyle(color: _FCPalette.textMedium, fontSize: 11),
          ),
          if (location.extraCost != null && location.extraCost! > 0) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _FCPalette.gold.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '+ ₪${location.extraCost}',
                style: const TextStyle(
                  color: _FCPalette.gold,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _FCPalette.green.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'ללא תוספת מחיר',
                style: TextStyle(
                  color: _FCPalette.green,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CertRowRO extends StatelessWidget {
  final Certification cert;
  const _CertRowRO({required this.cert});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _FCPalette.bgGray,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _FCPalette.borderGray),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _FCPalette.blue.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const Text('🎓', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        cert.name,
                        style: const TextStyle(
                          color: _FCPalette.textDark,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (cert.isVerified) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _FCPalette.blue.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          '✓ מאומת',
                          style: TextStyle(
                            color: _FCPalette.blue,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${cert.institution} · ${cert.year}',
                  style: const TextStyle(
                    color: _FCPalette.textMedium,
                    fontSize: 11,
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

// ═══════════════════════════════════════════════════════════════════════════
// MONTHLY JOURNEY PREVIEW — APPLE-STYLE 3 RINGS (the WOW factor)
// ═══════════════════════════════════════════════════════════════════════════

class _MonthlyJourneyCard extends StatefulWidget {
  const _MonthlyJourneyCard();

  @override
  State<_MonthlyJourneyCard> createState() => _MonthlyJourneyCardState();
}

class _MonthlyJourneyCardState extends State<_MonthlyJourneyCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ringCtrl;

  @override
  void initState() {
    super.initState();
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ringCtrl.forward();
    });
  }

  @override
  void dispose() {
    _ringCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('🎮', style: TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'המסע שלך אחרי חודש',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'הצצה לאן שתוכלי להגיע',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Apple-style 3 rings (2s animation on first mount)
          AnimatedBuilder(
            animation: _ringCtrl,
            builder: (ctx, _) {
              final t = _ringCtrl.value;
              return SizedBox(
                width: 150,
                height: 150,
                child: CustomPaint(
                  painter: _ThreeRingsPainter(
                    moveProgress: (t * 0.85).clamp(0.0, 1.0),
                    exerciseProgress: (t * 0.92).clamp(0.0, 1.0),
                    standProgress: t.clamp(0.0, 1.0),
                    centerEmoji: '🔥',
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // 4 stats grid
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  emoji: '🔥',
                  value: '28',
                  label: 'ימים רצופים',
                  color: _FCPalette.ringMove,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _StatTile(
                  emoji: '🏋️',
                  value: '16',
                  label: 'אימונים',
                  color: _FCPalette.ringExercise,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _StatTile(
                  emoji: '💪',
                  value: '+18%',
                  label: 'כוח',
                  color: _FCPalette.orange,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _StatTile(
                  emoji: '🏆',
                  value: '7',
                  label: 'תגים',
                  color: _FCPalette.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // "Top X%" banner
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _FCPalette.gold.withValues(alpha: 0.25),
                  _FCPalette.orange.withValues(alpha: 0.14),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _FCPalette.gold.withValues(alpha: 0.4)),
            ),
            child: const Row(
              children: [
                Text('✨', style: TextStyle(fontSize: 22)),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'תהיי ב-Top 15% בארץ',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'לפי ביצועים של לקוחות דומים',
                        style: TextStyle(color: Colors.white70, fontSize: 10.5),
                      ),
                    ],
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

class _ThreeRingsPainter extends CustomPainter {
  final double moveProgress;
  final double exerciseProgress;
  final double standProgress;
  final String centerEmoji;

  _ThreeRingsPainter({
    required this.moveProgress,
    required this.exerciseProgress,
    required this.standProgress,
    required this.centerEmoji,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    _drawRing(canvas, center, 64, 12, _FCPalette.ringMove, moveProgress);
    _drawRing(
      canvas,
      center,
      48,
      12,
      _FCPalette.ringExercise,
      exerciseProgress,
    );
    _drawRing(canvas, center, 32, 12, _FCPalette.ringStand, standProgress);

    final tp = TextPainter(
      text: TextSpan(text: centerEmoji, style: const TextStyle(fontSize: 22)),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }

  void _drawRing(
    Canvas canvas,
    Offset center,
    double radius,
    double width,
    Color color,
    double progress,
  ) {
    // Background ring (20% opacity)
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
    // Filled arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ThreeRingsPainter oldDelegate) =>
      oldDelegate.moveProgress != moveProgress ||
      oldDelegate.exerciseProgress != exerciseProgress ||
      oldDelegate.standProgress != standProgress ||
      oldDelegate.centerEmoji != centerEmoji;
}

class _StatTile extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  final Color color;
  const _StatTile({
    required this.emoji,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 9),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STORY CARD (read-only)
// ═══════════════════════════════════════════════════════════════════════════

class _StoryCardRO extends StatelessWidget {
  final SuccessStory story;
  const _StoryCardRO({required this.story});

  @override
  Widget build(BuildContext context) {
    final hasBefore = (story.beforeImageUrl ?? '').isNotEmpty;
    final hasAfter = (story.afterImageUrl ?? '').isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: _FCPalette.bgGray,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _FCPalette.borderGray),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (hasBefore || hasAfter)
            SizedBox(
              height: 180,
              child: Row(
                children: [
                  Expanded(
                    child: _BeforeAfterPanel(
                      label: 'לפני',
                      imageUrl: story.beforeImageUrl,
                      labelColor: _FCPalette.red,
                    ),
                  ),
                  Expanded(
                    child: _BeforeAfterPanel(
                      label: 'אחרי',
                      imageUrl: story.afterImageUrl,
                      labelColor: _FCPalette.green,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        story.clientName,
                        style: const TextStyle(
                          color: _FCPalette.textDark,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      List.filled(story.rating.clamp(0, 5), '⭐').join(),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  story.result,
                  style: const TextStyle(
                    color: _FCPalette.orange,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if ((story.testimonial ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '"${story.testimonial!}"',
                    style: const TextStyle(
                      color: _FCPalette.textMedium,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  DateFormat('dd/MM/yyyy').format(story.createdAt),
                  style: const TextStyle(
                    color: _FCPalette.textLight,
                    fontSize: 10.5,
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

class _BeforeAfterPanel extends StatelessWidget {
  final String label;
  final String? imageUrl;
  final Color labelColor;
  const _BeforeAfterPanel({
    required this.label,
    required this.imageUrl,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    final has = (imageUrl ?? '').isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black12,
        image:
            has
                ? DecorationImage(
                  image: NetworkImage(imageUrl!),
                  fit: BoxFit.cover,
                  onError: (_, __) {},
                )
                : null,
      ),
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: labelColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRUST BADGE (2x2 grid)
// ═══════════════════════════════════════════════════════════════════════════

class _BadgeCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String description;
  final Color accent;
  const _BadgeCard({
    required this.emoji,
    required this.title,
    required this.description,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    color: _FCPalette.textMedium,
                    fontSize: 10.5,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ACTIVE OFFER BANNER (dashed border + urgency)
// ═══════════════════════════════════════════════════════════════════════════

class _ActiveOfferBanner extends StatelessWidget {
  final SpecialOffer offer;
  const _ActiveOfferBanner({required this.offer});

  @override
  Widget build(BuildContext context) {
    final daysLeft = offer.expiresAt.difference(DateTime.now()).inDays;
    final spotsLeft = offer.availableSpots;
    final urgent = daysLeft <= 3 || (spotsLeft != null && spotsLeft <= 3);
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: urgent ? _FCPalette.red : _FCPalette.orange,
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              (urgent ? _FCPalette.red : _FCPalette.orange).withValues(
                alpha: 0.08,
              ),
              _FCPalette.gold.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        urgent ? _FCPalette.red : _FCPalette.orange,
                        _FCPalette.gold,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('🎁', style: TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offer.title,
                        style: const TextStyle(
                          color: _FCPalette.textDark,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        offer.description,
                        style: const TextStyle(
                          color: _FCPalette.textMedium,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (spotsLeft != null) ...[
                  _UrgencyPill(
                    label: 'נותרו $spotsLeft מקומות',
                    color: _FCPalette.orange,
                  ),
                  const SizedBox(width: 6),
                ],
                _UrgencyPill(
                  label:
                      daysLeft < 0
                          ? 'פג תוקף'
                          : daysLeft == 0
                          ? 'מסתיים היום!'
                          : 'עוד $daysLeft ימים',
                  color: urgent ? _FCPalette.red : _FCPalette.blue,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UrgencyPill extends StatelessWidget {
  final String label;
  final Color color;
  const _UrgencyPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );
    final path = Path()..addRRect(rrect);
    _drawDashedPath(canvas, path, paint, dashWidth: 6, dashSpace: 4);
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dashWidth,
    required double dashSpace,
  }) {
    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
