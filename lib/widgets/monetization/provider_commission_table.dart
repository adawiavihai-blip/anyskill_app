import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'design_tokens.dart';

/// A row representing one provider in the commission table (section 7).
class ProviderTableRow {
  final String uid;
  final String name;
  final String? avatarUrl;
  final String category;
  final double gmv30d;
  final double effectivePct;
  final String commissionSource; // 'custom' | 'category' | 'global'
  final double healthScore; // 0-100
  final bool isVip;
  final bool isChurnRisk;
  final bool isTopPerformer;
  final int completedJobs;
  final Timestamp? joinedAt;
  final List<double> trendLast7Days;

  const ProviderTableRow({
    required this.uid,
    required this.name,
    required this.avatarUrl,
    required this.category,
    required this.gmv30d,
    required this.effectivePct,
    required this.commissionSource,
    required this.healthScore,
    required this.isVip,
    required this.isChurnRisk,
    required this.isTopPerformer,
    required this.completedJobs,
    required this.joinedAt,
    required this.trendLast7Days,
  });
}

enum ProviderFilter { all, customOnly, vipOnly, topEarners, churnRisk, inactive }

/// Stage 2 — placeholder table showing an empty state with filter chips.
/// Data wiring (`users` + `jobs` aggregation) lands in stage 4.
class ProviderCommissionTable extends StatefulWidget {
  const ProviderCommissionTable({
    super.key,
    this.rows = const [],
    this.filter = ProviderFilter.all,
    this.onFilterChanged,
    this.onEditProvider,
  });

  final List<ProviderTableRow> rows;
  final ProviderFilter filter;
  final ValueChanged<ProviderFilter>? onFilterChanged;
  final void Function(ProviderTableRow row)? onEditProvider;

  @override
  State<ProviderCommissionTable> createState() =>
      _ProviderCommissionTableState();
}

class _ProviderCommissionTableState extends State<ProviderCommissionTable> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter chips
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _buildChip(ProviderFilter.all, 'הכל · ${widget.rows.length}'),
            _buildChip(ProviderFilter.customOnly,
                'מותאמים · ${widget.rows.where((r) => r.commissionSource == 'custom').length}'),
            _buildChip(ProviderFilter.vipOnly,
                'VIP · ${widget.rows.where((r) => r.isVip).length}'),
            _buildChip(ProviderFilter.topEarners, 'Top 10% הכנסה'),
            _buildChip(
                ProviderFilter.churnRisk,
                'בסיכון churn · ${widget.rows.where((r) => r.isChurnRisk).length}',
                accent: MonetizationTokens.danger),
            _buildChip(ProviderFilter.inactive, 'ללא פעילות 7י׳'),
          ],
        ),
        const SizedBox(height: 14),
        if (widget.rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'אין ספקים להצגה עם המסנן הנוכחי',
                style: TextStyle(
                    fontSize: 12, color: MonetizationTokens.textTertiary),
              ),
            ),
          )
        else
          ...widget.rows.map(_buildRow),
      ],
    );
  }

  Widget _buildChip(ProviderFilter value, String label, {Color? accent}) {
    final selected = widget.filter == value;
    return GestureDetector(
      onTap: () => widget.onFilterChanged?.call(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? (accent ?? MonetizationTokens.textPrimary)
              : Colors.white,
          border: Border.all(
            color: selected
                ? (accent ?? MonetizationTokens.textPrimary)
                : MonetizationTokens.borderSoft,
            width: 0.5,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
            color: selected ? Colors.white : MonetizationTokens.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildRow(ProviderTableRow row) {
    final healthColor = row.healthScore >= 80
        ? MonetizationTokens.success
        : row.healthScore >= 50
            ? MonetizationTokens.warning
            : MonetizationTokens.danger;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
            color: MonetizationTokens.borderSoft, width: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Avatar + name + badges
          Expanded(
            flex: 4,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: MonetizationTokens.surfaceAlt,
                  backgroundImage: row.avatarUrl != null &&
                          row.avatarUrl!.isNotEmpty
                      ? NetworkImage(row.avatarUrl!)
                      : null,
                  child: row.avatarUrl == null || row.avatarUrl!.isEmpty
                      ? Text(row.name.isNotEmpty ? row.name[0] : '?',
                          style: const TextStyle(fontSize: 12))
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(row.name,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (row.isVip) ...[
                            const SizedBox(width: 4),
                            MonetizationPill(
                              label: 'VIP',
                              background: MonetizationTokens.warningLight,
                              foreground: MonetizationTokens.warningText,
                              fontSize: 9,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${row.completedJobs} עסקאות',
                        style: const TextStyle(
                          fontSize: 10,
                          color: MonetizationTokens.textTertiary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(row.category,
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: 2,
            child: Text('₪${row.gmv30d.toStringAsFixed(0)}',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${row.effectivePct.toStringAsFixed(1)}%',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500)),
                Text(
                  _sourceLabel(row.commissionSource),
                  style: const TextStyle(
                      fontSize: 9, color: MonetizationTokens.textTertiary),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Text(row.healthScore.toStringAsFixed(0),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500)),
                const SizedBox(width: 6),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: (row.healthScore / 100).clamp(0, 1),
                      minHeight: 4,
                      backgroundColor: MonetizationTokens.surfaceAlt,
                      valueColor: AlwaysStoppedAnimation(healthColor),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Action
          SizedBox(
            width: 70,
            child: TextButton(
              onPressed: () => widget.onEditProvider?.call(row),
              style: TextButton.styleFrom(
                foregroundColor: row.isChurnRisk
                    ? MonetizationTokens.danger
                    : MonetizationTokens.textPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                row.isChurnRisk ? 'פעל ↗' : 'ערוך',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _sourceLabel(String source) => switch (source) {
        'custom' => 'מותאם',
        'category' => 'מקטגוריה',
        _ => 'ברירת מחדל',
      };
}
