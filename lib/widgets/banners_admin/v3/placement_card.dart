import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// One of the 4 large cards in the "4 מיקומים פעילים" section of Screen A.
///
/// Spec ([banners-mockup-v3.html:155-204, 905-1025](docs/ui-specs/Baner/banners-mockup-v3.html)):
/// - Standard variant: white surface, 20px radius, 1px line, soft shadow
/// - Featured variant (VIP): vipGradient bg, gold halo overlay, gold-tinted
///   text + status pill
/// - Hover: -3px translate + sh3 shadow
/// - Layout: head (icon + tier + name + status) → preview area → 3 stats
/// - Bottom-leading floating arrow button that rotates -45° on hover
class StudioPlacementCard extends StatefulWidget {
  const StudioPlacementCard({
    super.key,
    required this.tier,
    required this.name,
    required this.where,
    required this.icon,
    required this.statusLabel,
    required this.preview,
    required this.stats,
    this.featured = false,
    this.onTap,
  });

  /// Small uppercase pre-name label — e.g. "⭐ Premium · VIP" or "Standard".
  final String tier;

  /// Display name — "קרוסלת ספקים", "באנרי קידום".
  final String name;

  /// One-line where-it-shows description.
  final String where;

  /// Icon shown in the 38px square avatar.
  final IconData icon;

  /// Right-side status pill, e.g. "פועל", "6 פעילים", "5 מתוזמנים".
  final String statusLabel;

  /// The 116px-tall preview surface — provided as a Widget so each card
  /// can render a custom mini-preview (rotating VIP cards, gradient promo,
  /// wallet card, blue subcategory).
  final Widget preview;

  /// Exactly 3 stat tiles. The card layouts in 3 columns regardless of
  /// list length (extra entries are dropped, missing show "—").
  final List<StudioPlacementStat> stats;

  /// VIP-tier visual variant.
  final bool featured;

  /// Tap → routes to the placement's dedicated screen (or filters the
  /// table on the dashboard, depending on the card).
  final VoidCallback? onTap;

  @override
  State<StudioPlacementCard> createState() => _StudioPlacementCardState();
}

class _StudioPlacementCardState extends State<StudioPlacementCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final featured = widget.featured;

    final headInk = featured ? Colors.white : StudioColors.ink;
    final mutedInk = featured
        ? Colors.white.withValues(alpha: 0.6)
        : StudioColors.ink3;
    final tierInk = featured ? StudioColors.gold : StudioColors.ink4;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          transform: _hover
              ? Matrix4.translationValues(0, -3, 0)
              : Matrix4.identity(),
          decoration: BoxDecoration(
            gradient: featured ? StudioColors.vipGradient : null,
            color: featured ? null : StudioColors.bgElevated,
            borderRadius: BorderRadius.circular(StudioRadius.lg),
            border: Border.all(
              color: featured
                  ? StudioColors.gold.withValues(alpha: 0.3)
                  : StudioColors.line,
            ),
            boxShadow: _hover ? StudioShadows.sh3 : StudioShadows.sh1,
          ),
          padding: const EdgeInsets.all(StudioSpacing.s5),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              if (featured)
                const Positioned.fill(child: _FeaturedHaloPaint()),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Head ────────────────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PlacementIcon(icon: widget.icon, featured: featured),
                      const SizedBox(width: StudioSpacing.s3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.tier.toUpperCase(),
                              style: StudioText.overline(color: tierInk),
                              textDirection: TextDirection.rtl,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.name,
                              style: StudioText.h3(color: headInk),
                              textDirection: TextDirection.rtl,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.where,
                              style: StudioText.caption(color: mutedInk),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textDirection: TextDirection.rtl,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: StudioSpacing.s2),
                      _StatusPill(
                        label: widget.statusLabel,
                        featured: featured,
                      ),
                    ],
                  ),

                  const SizedBox(height: StudioSpacing.s4),

                  // ── Preview ─────────────────────────────────────
                  ClipRRect(
                    borderRadius: BorderRadius.circular(StudioRadius.md),
                    child: Container(
                      height: 116,
                      decoration: BoxDecoration(
                        color: featured
                            ? Colors.white.withValues(alpha: 0.04)
                            : StudioColors.bgSubtle,
                        border: Border.all(
                          color: featured
                              ? Colors.white.withValues(alpha: 0.08)
                              : StudioColors.line,
                        ),
                        borderRadius: BorderRadius.circular(StudioRadius.md),
                      ),
                      child: widget.preview,
                    ),
                  ),

                  const SizedBox(height: StudioSpacing.s4),

                  // ── Stats ───────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.only(top: StudioSpacing.s3),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: featured
                              ? Colors.white.withValues(alpha: 0.08)
                              : StudioColors.line,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        for (int i = 0; i < 3; i++)
                          Expanded(
                            child: _StatTile(
                              tile: i < widget.stats.length
                                  ? widget.stats[i]
                                  : const StudioPlacementStat(
                                      label: '',
                                      value: '',
                                    ),
                              featured: featured,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              // ── Floating arrow ──────────────────────────────────
              PositionedDirectional(
                bottom: StudioSpacing.s4,
                start: StudioSpacing.s4,
                child: _ArrowButton(featured: featured, hover: _hover),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlacementIcon extends StatelessWidget {
  const _PlacementIcon({required this.icon, required this.featured});
  final IconData icon;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        gradient: featured ? StudioColors.goldGradient : null,
        color: featured ? null : StudioColors.bgSubtle,
        borderRadius: BorderRadius.circular(StudioRadius.sm),
      ),
      child: Icon(
        icon,
        size: 18,
        color: featured ? Colors.white : StudioColors.ink2,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.featured});
  final String label;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final bgColor = featured
        ? StudioColors.gold.withValues(alpha: 0.18)
        : StudioColors.successBg;
    final fgColor = featured ? StudioColors.gold : StudioColors.success;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fgColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: StudioText.chip(color: fgColor),
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.tile, required this.featured});
  final StudioPlacementStat tile;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final labelInk = featured
        ? Colors.white.withValues(alpha: 0.5)
        : StudioColors.ink4;
    final valueInk = featured ? Colors.white : StudioColors.ink;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tile.label.toUpperCase(),
          style: StudioText.overline(color: labelInk).copyWith(fontSize: 10),
          textDirection: TextDirection.rtl,
        ),
        const SizedBox(height: 2),
        Text(
          tile.value.isEmpty ? '—' : tile.value,
          style: StudioText.metricMd(color: valueInk),
          textDirection: TextDirection.rtl,
        ),
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.featured, required this.hover});
  final bool featured;
  final bool hover;

  @override
  Widget build(BuildContext context) {
    final bg = hover
        ? (featured ? StudioColors.gold : StudioColors.ink)
        : (featured
            ? Colors.white.withValues(alpha: 0.1)
            : StudioColors.bgSubtle);
    final fg = hover
        ? (featured ? const Color(0xFF1A1A1A) : Colors.white)
        : (featured ? Colors.white : StudioColors.ink2);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: AnimatedRotation(
        duration: const Duration(milliseconds: 150),
        turns: hover ? -0.125 : 0.0, // -45 degrees on hover (double, not int)
        child: Icon(
          Icons.arrow_back, // RTL: visual leading-arrow
          size: 14,
          color: fg,
        ),
      ),
    );
  }
}

class _FeaturedHaloPaint extends StatelessWidget {
  const _FeaturedHaloPaint();
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _FeaturedHaloPainter(), size: Size.infinite);
  }
}

class _FeaturedHaloPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final center = Offset(size.width * 1.1, -size.height * 0.5);
    final radius = size.width * 0.7;
    if (radius <= 0) return;
    final paint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x2DB89855), Color(0x00B89855)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _FeaturedHaloPainter oldDelegate) => false;
}

/// One of the 3 stats at the bottom of a Placement Card.
class StudioPlacementStat {
  final String label;
  final String value;

  const StudioPlacementStat({required this.label, required this.value});
}
