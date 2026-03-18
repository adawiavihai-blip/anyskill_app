import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Full-bleed background for a category / sub-category card.
///
/// Layers (bottom → top):
///   1. CachedNetworkImage — scaled by [imageScale] for the hover-zoom effect.
///      Wrapped in AnimatedScale so the zoom is smooth (300 ms, easeOut).
///      The surrounding ClipRRect in the parent card clips the overflow so
///      the animation never leaks outside the card boundary.
///   2. LinearGradient overlay — 3-stop fade: transparent → hint of dark → rich
///      dark indigo at the bottom.  The overlay is NOT scaled, so it stays
///      pinned to the card edges regardless of the image scale.
///
/// Drop this as the first child inside a [Stack] with [StackFit.expand].
class CategoryImageBackground extends StatelessWidget {
  const CategoryImageBackground({
    super.key,
    required this.imageUrl,
    this.imageScale = 1.0,
  });

  final String imageUrl;

  /// Drives the smooth zoom-in effect. Caller (card widget) updates this
  /// on hover / press via AnimatedScale inside this widget.
  final double imageScale;

  // ── AnySkill branded gradient ──────────────────────────────────────────────
  // Used as the card background when imageUrl is empty or the network fails.
  static const List<List<Color>> _brandedGradients = [
    [Color(0xFF1E1B4B), Color(0xFF4338CA)], // deep indigo → indigo
    [Color(0xFF312E81), Color(0xFF6366F1)], // darker indigo → violet
    [Color(0xFF1E3A5F), Color(0xFF2563EB)], // navy → blue
    [Color(0xFF1A1A2E), Color(0xFF533483)], // dark navy → purple
    [Color(0xFF0F172A), Color(0xFF1E40AF)], // near-black → blue
  ];

  // Deterministic colour pick based on the URL string so the same card always
  // gets the same gradient (stable across rebuilds).
  LinearGradient _fallbackGradient() {
    final idx = imageUrl.isEmpty ? 0 : imageUrl.codeUnits.first % _brandedGradients.length;
    final colors = _brandedGradients[idx];
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── 1. Background image (or branded gradient fallback) ──────────────
        // AnimatedScale drives the hover/press zoom from the parent card.
        // Overflow is clipped by the ClipRRect that wraps the card Stack.
        AnimatedScale(
          scale:    imageScale,
          duration: const Duration(milliseconds: 320),
          curve:    Curves.easeOutCubic,
          child: imageUrl.isEmpty
              ? _GradientFill(gradient: _fallbackGradient())
              : CachedNetworkImage(
                  imageUrl:       imageUrl,
                  fit:            BoxFit.cover,
                  // Cap decoded size to 400 px — prevents 4K images from eating
                  // ~50 MB of RAM per card.  The card is never wider than 400 px
                  // even on large tablets, so there is no visual quality loss.
                  memCacheWidth:  400,
                  memCacheHeight: 400,
                  fadeInDuration: const Duration(milliseconds: 260),
                  fadeOutDuration: const Duration(milliseconds: 80),
                  placeholder:    (_, __) => const _ShimmerPlaceholder(),
                  errorWidget:    (_, __, ___) =>
                      _GradientFill(gradient: _fallbackGradient()),
                ),
        ),

        // ── 2. Readability gradient overlay ────────────────────────────────
        // 3-stop fade keeps text legible even on bright/washed-out photos.
        // NOT included in the AnimatedScale so it stays pinned to card edges.
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin:  Alignment.topCenter,
              end:    Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                const Color(0xFF0F172A).withValues(alpha: 0.28),
                const Color(0xFF0F172A).withValues(alpha: 0.88),
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Shimmer skeleton ──────────────────────────────────────────────────────────

class _ShimmerPlaceholder extends StatelessWidget {
  const _ShimmerPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFF2D2B55),
      highlightColor: const Color(0xFF4C4A82),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF2D2B55),
        ),
      ),
    );
  }
}

// ── Simple gradient fill ──────────────────────────────────────────────────────

class _GradientFill extends StatelessWidget {
  const _GradientFill({required this.gradient});
  final LinearGradient gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: gradient),
    );
  }
}
