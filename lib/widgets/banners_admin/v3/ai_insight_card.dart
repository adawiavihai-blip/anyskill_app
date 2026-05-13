import 'package:flutter/material.dart';

import '../../../services/banners_service.dart';
import 'design_tokens.dart';

/// The gold "Gemini insight" card at the bottom of Screen A.
///
/// Mockup spec ([banners-mockup-v3.html:283-294, 1338-1352](docs/ui-specs/Baner/banners-mockup-v3.html)):
/// 3-column grid (icon · content · actions). Renders text from the
/// `ai_insights/banners` doc written by the existing `generateBannerInsights`
/// CF every 6 hours (CLAUDE.md §49).
///
/// **Empty state:** if the doc doesn't exist (CF hasn't fired yet OR
/// payload is malformed), shows a low-key "AI insight not available yet"
/// card with the manual-refresh CTA. Never fakes a recommendation.
class StudioAiInsightCard extends StatelessWidget {
  const StudioAiInsightCard({
    super.key,
    required this.insight,
    this.onAction,
    this.actionLabel,
  });

  final AiInsight? insight;

  /// Tapped when the user clicks the primary action button. The dashboard
  /// owns routing — usually pushes the VIP screen if the action references
  /// VIP capacity, otherwise it's a no-op.
  final VoidCallback? onAction;

  /// Custom label for the action button. Defaults to "פתח ניהול VIP" because
  /// the most common insight is about VIP capacity. Pass null to hide.
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final hasContent = insight != null && insight!.hasContent;

    if (!hasContent) {
      return _EmptyState();
    }

    return Container(
      padding: const EdgeInsets.all(StudioSpacing.s6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Color(0x0AB89855),
            Color(0xCCFFFFFF),
            Color(0x051A1A1A),
          ],
          stops: [0.0, 0.5, 1.0],
        ),
        color: StudioColors.bgElevated,
        borderRadius: BorderRadius.circular(StudioRadius.lg),
        border: Border.all(color: StudioColors.line),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          const Positioned.fill(child: _InsightHaloPaint()),
          Row(
            children: [
              // ── Icon (gold gradient circle) ──────────────────────
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: StudioColors.goldGradient,
                  borderRadius: BorderRadius.circular(StudioRadius.md),
                  boxShadow: StudioShadows.goldGlow,
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    size: 22, color: Colors.white),
              ),
              const SizedBox(width: StudioSpacing.s5),

              // ── Content ──────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tagText(insight!.model),
                      style: StudioText.overline(color: StudioColors.goldDeep)
                          .copyWith(
                              fontSize: 10.5,
                              letterSpacing: 1.26,
                              fontWeight: FontWeight.w700),
                      textDirection: TextDirection.rtl,
                    ),
                    const SizedBox(height: StudioSpacing.s1),
                    if (insight!.title.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          insight!.title,
                          style: StudioText.h3(),
                          textDirection: TextDirection.rtl,
                        ),
                      ),
                    Text(
                      insight!.recommendation,
                      style: StudioText.body(color: StudioColors.ink2)
                          .copyWith(fontSize: 14, height: 1.5),
                      textDirection: TextDirection.rtl,
                    ),
                    if (insight!.expectedImpact != null &&
                        insight!.expectedImpact!.isNotEmpty) ...[
                      const SizedBox(height: StudioSpacing.s2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: StudioSpacing.s3,
                            vertical: StudioSpacing.s1),
                        decoration: BoxDecoration(
                          color: StudioColors.gold.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          insight!.expectedImpact!,
                          style: StudioText.captionSm(
                                  color: StudioColors.goldDeep)
                              .copyWith(fontWeight: FontWeight.w600),
                          textDirection: TextDirection.rtl,
                        ),
                      ),
                    ],
                    const SizedBox(height: StudioSpacing.s2),
                    Text(
                      _metaText(insight!.generatedAt, insight!.model),
                      style: StudioText.captionSm(),
                      textDirection: TextDirection.rtl,
                    ),
                  ],
                ),
              ),

              // ── Actions ──────────────────────────────────────────
              if (onAction != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                      start: StudioSpacing.s5),
                  child: ElevatedButton(
                    onPressed: onAction,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: StudioColors.ink,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(StudioRadius.sm),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      elevation: 0,
                    ),
                    child: Text(
                      actionLabel ?? 'פתח ניהול VIP',
                      style: StudioText.bodyMedium(color: Colors.white),
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _tagText(String model) {
    final m = model.isEmpty ? 'Gemini' : model;
    return '⭐ תובנת AI · $m';
  }

  String _metaText(DateTime? generatedAt, String model) {
    if (generatedAt == null) return '🕒 ממתין לאיסוף נתונים ראשון';
    final diff = DateTime.now().difference(generatedAt);
    String when;
    if (diff.inMinutes < 1) {
      when = 'הרגע';
    } else if (diff.inHours < 1) {
      when = 'לפני ${diff.inMinutes} דקות';
    } else if (diff.inDays < 1) {
      when = 'לפני ${diff.inHours} שעות';
    } else {
      when = 'לפני ${diff.inDays} ימים';
    }
    return '🕒 עודכן $when · ${model.isEmpty ? "Gemini Flash" : model}';
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(StudioSpacing.s6),
      decoration: studioCard(radius: StudioRadius.lg),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: StudioColors.bgSubtle,
              borderRadius: BorderRadius.circular(StudioRadius.md),
            ),
            child: const Icon(Icons.hourglass_top_rounded,
                size: 22, color: StudioColors.ink3),
          ),
          const SizedBox(width: StudioSpacing.s5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '⭐ תובנת AI · Gemini',
                  style: StudioText.overline(color: StudioColors.ink3),
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: StudioSpacing.s1),
                Text(
                  'התובנה הראשונה תיווצר בריצה הבאה של ה-CF (כל 6 שעות).',
                  style: StudioText.body(color: StudioColors.ink3),
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 4),
                Text(
                  'עד אז — נתוני הבאנרים שלך נצברים.',
                  style: StudioText.captionSm(),
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightHaloPaint extends StatelessWidget {
  const _InsightHaloPaint();
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _InsightHaloPainter(), size: Size.infinite);
  }
}

class _InsightHaloPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final center = Offset(size.width * 1.05, -size.height * 0.4);
    final radius = size.width * 0.45;
    if (radius <= 0) return;
    final paint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x1AB89855), Color(0x00B89855)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _InsightHaloPainter oldDelegate) => false;
}
