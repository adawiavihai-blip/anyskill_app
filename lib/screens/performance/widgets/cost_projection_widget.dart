import 'package:flutter/material.dart';

import '../models/performance_metric.dart';
import '_design.dart';

/// Projected monthly cost at growth landmarks. Helps the admin understand
/// when each Milestone upgrade pays for itself.
///
/// Numbers come from README.md `Cost Projection` + CURRENT_STATUS.md.
class CostProjectionWidget extends StatelessWidget {
  final PerformanceMetric metric;
  const CostProjectionWidget({super.key, required this.metric});

  @override
  Widget build(BuildContext context) {
    final rows = <_CostRow>[
      _CostRow(
        label: 'עכשיו',
        dau: _fmt(metric.dailyActiveUsers),
        cost: '\$${metric.firestoreMonthlyCostUsd.toStringAsFixed(0)} - \$25',
        milestone: 'Milestone 1',
        isCurrent: true,
      ),
      const _CostRow(
        label: '10K DAU',
        dau: '10,000',
        cost: '\$50 - \$100',
        milestone: 'Milestone 2',
        isCurrent: false,
      ),
      const _CostRow(
        label: '100K DAU',
        dau: '100,000',
        cost: '\$200 - \$500',
        milestone: 'Milestone 2-3',
        isCurrent: false,
      ),
      const _CostRow(
        label: '1M DAU',
        dau: '1,000,000',
        cost: '\$1K - \$3K',
        milestone: 'Milestone 3-4',
        isCurrent: false,
      ),
      const _CostRow(
        label: '10M DAU',
        dau: '10,000,000',
        cost: '\$5K - \$15K',
        milestone: 'Milestone 5',
        isCurrent: false,
      ),
    ];

    return PerfDesign.glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [PerfDesign.indigo, PerfDesign.purple],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.savings_outlined,
                    color: Colors.white, size: 18),
              ),
              const Spacer(),
              const Text(
                'תחזית עלויות',
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: PerfDesign.textHi,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...rows.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ProjRow(row: r),
              )),
          const SizedBox(height: 4),
          Text(
            'הטווחים משקפים הפעלה/אי-הפעלה של Redis + BigQuery + Sharding',
            textAlign: TextAlign.end,
            style: TextStyle(
              color: PerfDesign.textLo,
              fontSize: 11.5,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}

class _CostRow {
  final String label;
  final String dau;
  final String cost;
  final String milestone;
  final bool isCurrent;

  const _CostRow({
    required this.label,
    required this.dau,
    required this.cost,
    required this.milestone,
    required this.isCurrent,
  });
}

class _ProjRow extends StatelessWidget {
  final _CostRow row;
  const _ProjRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final highlight = row.isCurrent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: highlight
            ? PerfDesign.indigo.withValues(alpha: 0.12)
            : PerfDesign.glassFillStrong,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlight
              ? PerfDesign.indigo.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              row.milestone,
              style: TextStyle(
                color: PerfDesign.textMid,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            row.cost,
            style: TextStyle(
              color: highlight ? PerfDesign.indigo : PerfDesign.textHi,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                row.label,
                style: TextStyle(
                  color:
                      highlight ? PerfDesign.indigo : PerfDesign.textHi,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${row.dau} משתמשים',
                style: TextStyle(
                  color: PerfDesign.textLo,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          if (highlight) ...[
            const SizedBox(width: 8),
            const Icon(Icons.location_on_rounded,
                color: PerfDesign.indigo, size: 16),
          ],
        ],
      ),
    );
  }
}
