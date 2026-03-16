import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Full-bleed background for a category / sub-category card.
///
/// Layers (bottom → top):
///   1. CachedNetworkImage (with shimmer while loading, branded gradient on error)
///   2. LinearGradient overlay — transparent at top → dark indigo at bottom
///      so the Hebrew label is always legible.
///
/// Drop this as the first child inside a [Stack] with [StackFit.expand].
class CategoryImageBackground extends StatelessWidget {
  const CategoryImageBackground({
    super.key,
    required this.imageUrl,
  });

  final String imageUrl;

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
        if (imageUrl.isEmpty)
          _GradientFill(gradient: _fallbackGradient())
        else
          CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            // Shimmer skeleton while the image loads
            placeholder: (_, __) => const _ShimmerPlaceholder(),
            // Branded gradient if the URL is broken / offline
            errorWidget: (_, __, ___) =>
                _GradientFill(gradient: _fallbackGradient()),
          ),

        // ── 2. Readability gradient overlay ────────────────────────────────
        // Transparent at the top, darkens toward the bottom so the label
        // is always readable regardless of the photo's brightness.
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                const Color(0xFF1E1B4B).withValues(alpha: 0.78),
              ],
              stops: const [0.35, 1.0],
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
