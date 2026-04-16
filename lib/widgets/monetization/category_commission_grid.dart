import 'package:flutter/material.dart';
import '../../constants.dart';
import '../../services/monetization_service.dart';
import 'design_tokens.dart';

/// Grid of all APP_CATEGORIES with per-category commission override
/// controls (section 5 — inner tab "קטגוריות").
///
/// Each tile shows:
///   • category name + icon
///   • effective pct (override or global fallback, in small type)
///   • inline slider (0-30) bound to the local `_editing` map
///   • "Apply" button (only shown when the local value differs from
///     the persisted one)
///   • "×" button (only shown when an override is active — resets to global).
class CategoryCommissionGrid extends StatefulWidget {
  const CategoryCommissionGrid({
    super.key,
    required this.globalPct,
    required this.overrides,
  });

  /// Global default pct in 0-100 scale.
  final double globalPct;

  /// Map keyed by category name (doc id in `category_commissions`).
  /// Value is the full Firestore doc.
  final Map<String, Map<String, dynamic>> overrides;

  @override
  State<CategoryCommissionGrid> createState() =>
      _CategoryCommissionGridState();
}

class _CategoryCommissionGridState extends State<CategoryCommissionGrid> {
  /// Local pending edits. Key = category name. Value = pending pct (0-100).
  final Map<String, double> _editing = {};

  /// Category names currently saving — for spinner + button disable.
  final Set<String> _saving = <String>{};

  double _effectivePct(String name) {
    if (_editing.containsKey(name)) return _editing[name]!;
    final override = widget.overrides[name];
    final pct = (override?['percentage'] as num?)?.toDouble();
    return pct ?? widget.globalPct;
  }

  bool _hasOverride(String name) => widget.overrides.containsKey(name);

  bool _hasPendingChange(String name) {
    if (!_editing.containsKey(name)) return false;
    final pending = _editing[name]!;
    final persisted = (widget.overrides[name]?['percentage'] as num?)
            ?.toDouble() ??
        widget.globalPct;
    return (pending - persisted).abs() > 0.01;
  }

  Future<void> _apply(String name) async {
    setState(() => _saving.add(name));
    try {
      final old = (widget.overrides[name]?['percentage'] as num?)
          ?.toDouble();
      await MonetizationService.setCategoryCommission(
        categoryId: name,
        categoryName: name,
        percentage: _editing[name],
        oldPercentage: old,
      );
      if (!mounted) return;
      setState(() {
        _editing.remove(name);
        _saving.remove(name);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('עמלת $name נשמרה'),
          backgroundColor: MonetizationTokens.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving.remove(name));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה: $e'),
          backgroundColor: MonetizationTokens.danger,
        ),
      );
    }
  }

  Future<void> _removeOverride(String name) async {
    setState(() => _saving.add(name));
    try {
      final old = (widget.overrides[name]?['percentage'] as num?)
          ?.toDouble();
      await MonetizationService.setCategoryCommission(
        categoryId: name,
        categoryName: name,
        percentage: null,
        oldPercentage: old,
      );
      if (!mounted) return;
      setState(() {
        _editing.remove(name);
        _saving.remove(name);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving.remove(name));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה בהסרה: $e'),
          backgroundColor: MonetizationTokens.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'עמלת ברירת מחדל ${widget.globalPct.toStringAsFixed(0)}% — '
          'לשינוי פרטני לקטגוריה, גרור את הסליידר ולחץ "שמור".',
          style: MonetizationTokens.caption,
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.2,
          children: APP_CATEGORIES
              .map((c) => _buildTile(c['name'] as String, c['icon'] as IconData))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildTile(String name, IconData icon) {
    final pct = _effectivePct(name);
    final hasOverride = _hasOverride(name);
    final pending = _hasPendingChange(name);
    final saving = _saving.contains(name);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: hasOverride
              ? MonetizationTokens.primaryBorder
              : MonetizationTokens.borderSoft,
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(MonetizationTokens.radiusMd),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: hasOverride
                  ? MonetizationTokens.primaryLight
                  : MonetizationTokens.surfaceAlt,
              borderRadius:
                  BorderRadius.circular(MonetizationTokens.radiusSm),
            ),
            child: Icon(
              icon,
              size: 18,
              color: hasOverride
                  ? MonetizationTokens.primaryDark
                  : MonetizationTokens.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          // Name + pct + slider
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (hasOverride)
                      MonetizationPill(
                        label: 'מותאם',
                        background: MonetizationTokens.primaryLight,
                        foreground: MonetizationTokens.primaryDark,
                        fontSize: 9,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      pct.toStringAsFixed(1),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 2),
                    const Text('%',
                        style: TextStyle(
                            fontSize: 11,
                            color: MonetizationTokens.textTertiary)),
                    const SizedBox(width: 8),
                    Text(
                      hasOverride ? 'override' : 'default',
                      style: const TextStyle(
                          fontSize: 10,
                          color: MonetizationTokens.textTertiary),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7),
                    overlayShape: SliderComponentShape.noOverlay,
                    activeTrackColor: MonetizationTokens.primary,
                    inactiveTrackColor: MonetizationTokens.surfaceAlt,
                    thumbColor: MonetizationTokens.primary,
                  ),
                  child: Slider(
                    value: pct.clamp(0, 30).toDouble(),
                    min: 0,
                    max: 30,
                    divisions: 300,
                    onChanged: saving
                        ? null
                        : (v) {
                            setState(() => _editing[name] = v);
                          },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pending)
                SizedBox(
                  height: 28,
                  child: ElevatedButton(
                    onPressed: saving ? null : () => _apply(name),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MonetizationTokens.textPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(fontSize: 10),
                    ),
                    child: saving
                        ? const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: Colors.white),
                          )
                        : const Text('שמור'),
                  ),
                ),
              if (!pending && hasOverride)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 14),
                  tooltip: 'חזור ל-default',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                  color: MonetizationTokens.textTertiary,
                  onPressed:
                      saving ? null : () => _removeOverride(name),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
