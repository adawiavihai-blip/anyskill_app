import 'package:flutter/material.dart';

/// A pure-Flutter shimmer box — no extra packages required.
///
/// Renders a left-to-right sweep using a moving [LinearGradient].
/// The highlight band travels from off-screen-left to off-screen-right
/// in 1.4 s, then repeats seamlessly.
class SkeletonBox extends StatefulWidget {
  final double borderRadius;

  const SkeletonBox({super.key, this.borderRadius = 8});

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        // x sweeps from -1.5 (highlight left of widget) to +1.5 (right)
        final x = -1.5 + 3.0 * _ctrl.value;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(x - 1, 0),
              end:   Alignment(x + 1, 0),
              colors: const [
                Color(0xFFE4E4E4),
                Color(0xFFEEEEEE),
                Color(0xFFF8F8F8),
                Color(0xFFEEEEEE),
                Color(0xFFE4E4E4),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A [SliverPadding] + [SliverGrid] skeleton that exactly mirrors
/// the live category grid (4 columns, same padding & aspect ratio).
///
/// Drop this in anywhere [ConnectionState.waiting] is true to replace
/// the spinner with 8 shimmering placeholder cards.
class CategoryGridSkeleton extends StatelessWidget {
  const CategoryGridSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (_, __) => const SkeletonBox(borderRadius: 14),
          childCount: 8,
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount:   4,
          crossAxisSpacing: 6,
          mainAxisSpacing:  6,
          childAspectRatio: 0.82,
        ),
      ),
    );
  }
}
