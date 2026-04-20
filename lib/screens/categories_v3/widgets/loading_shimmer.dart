import 'package:flutter/material.dart';

/// Lightweight static loading placeholder for the categories list and KPI strip.
///
/// **Important:** the previous Phase E version used `ShaderMask` + `LinearGradient`
/// + `AnimatedBuilder` to produce a true shimmer animation. On Flutter Web that
/// combination occasionally rendered as a single solid-grey block when the
/// initial `shaderCallback` rect was empty (post-frame timing). The visible
/// symptom: the entire categories list area showed as a "big empty grey box"
/// that never resolved even after data arrived. We swapped to a plain set of
/// rounded white containers — the layout is identical, no Shader involved.
/// If we ever want a real shimmer back, use the `shimmer` package instead of
/// hand-rolling ShaderMask on web.
class LoadingShimmer extends StatelessWidget {
  const LoadingShimmer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Shaped placeholder for the categories list — 5 white rounded rows that
/// match the height/spacing of `CategoryRowCard`. No animation; pure static
/// content so it never rendering-fails.
class CategoryListShimmer extends StatelessWidget {
  const CategoryListShimmer({super.key, this.rowCount = 5});
  final int rowCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(rowCount, (_) => const _ShimmerRow()),
    );
  }
}

class _ShimmerRow extends StatelessWidget {
  const _ShimmerRow();

  @override
  Widget build(BuildContext context) {
    final base = Colors.grey.shade300;
    return Container(
      height: 70,
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 130,
                  height: 12,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 200,
                  height: 10,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 60,
            height: 24,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 40,
            height: 12,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }
}

/// 5-card KPI shimmer — placeholder while the categories stream resolves.
/// Static layout (matches the real KpiMetricsRow grid).
class KpiRowShimmer extends StatelessWidget {
  const KpiRowShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final cols = w >= 1024 ? 5 : (w >= 720 ? 3 : 2);
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: cols == 5 ? 2.4 : (cols == 3 ? 2.2 : 2.0),
        ),
        itemCount: 5,
        itemBuilder: (_, __) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          ),
          child: Center(
            child: Container(
              width: 60,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
      );
    });
  }
}
