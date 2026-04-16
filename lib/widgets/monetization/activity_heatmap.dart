import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// Section 6 (right) — 4 hour-buckets × 7 day-of-week cells. Purple
/// saturation encodes transaction intensity. The cell with the peak value
/// is emphasized.
///
/// Expects a 4×7 matrix: `values[hourBucket][dayOfWeek]`.
///   hourBucket: 0=08:00-12:00, 1=12:00-16:00, 2=16:00-20:00, 3=20:00-08:00
///   dayOfWeek:  0=Sun..6=Sat (Hebrew calendar order — Sunday first).
class ActivityHeatmap extends StatelessWidget {
  const ActivityHeatmap({
    super.key,
    required this.values,
    this.insight,
  });

  final List<List<double>> values;
  final String? insight;

  static const _hourLabels = ['08', '12', '16', '20'];
  static const _dayLabels  = ['א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ש'];

  @override
  Widget build(BuildContext context) {
    double maxV = 0;
    for (final row in values) {
      for (final v in row) {
        if (v > maxV) maxV = v;
      }
    }
    if (maxV <= 0) maxV = 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Day labels row
        Row(
          children: [
            const SizedBox(width: 24),
            ..._dayLabels.map((d) => Expanded(
                  child: Center(
                    child: Text(d, style: MonetizationTokens.captionTertiary),
                  ),
                )),
          ],
        ),
        const SizedBox(height: 4),

        // 4 rows of 7 cells each
        ...List.generate(values.length, (r) {
          final row = values[r];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    r < _hourLabels.length ? _hourLabels[r] : '',
                    textAlign: TextAlign.start,
                    style: MonetizationTokens.captionTertiary,
                  ),
                ),
                ...List.generate(row.length, (c) {
                  final value = row[c];
                  final intensity = (value / maxV).clamp(0.0, 1.0);
                  final isPeak = value == maxV && value > 0;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: AspectRatio(
                        aspectRatio: 1.8,
                        child: Tooltip(
                          message: '${_dayLabels[c]} ${_hourLabels[r]}: ${value.toStringAsFixed(0)}',
                          child: Container(
                            decoration: BoxDecoration(
                              color: MonetizationTokens.primary
                                  .withValues(alpha: 0.08 + intensity * 0.72),
                              borderRadius: BorderRadius.circular(4),
                              border: isPeak
                                  ? Border.all(
                                      color: MonetizationTokens.primaryDarker,
                                      width: 1.5)
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        }),

        if (insight != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: MonetizationTokens.primaryLight,
              borderRadius: BorderRadius.circular(MonetizationTokens.radiusSm),
            ),
            child: Text(insight!,
                style: const TextStyle(
                  fontSize: 11,
                  color: MonetizationTokens.primaryDark,
                  height: 1.5,
                )),
          ),
        ],
      ],
    );
  }
}
