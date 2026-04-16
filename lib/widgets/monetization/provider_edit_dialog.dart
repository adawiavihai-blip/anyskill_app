import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/monetization_service.dart';
import 'design_tokens.dart';

const _kReasonOptions = <String>[
  'שימור ספק',
  'ספק חדש',
  'Top performer',
  'פיצוי על תקלה',
  'אחר',
];

/// Dialog for editing one provider's custom commission.
/// Writes via [MonetizationService.setUserCommission] — which also
/// takes care of the `activity_log` entry.
class ProviderEditDialog extends StatefulWidget {
  const ProviderEditDialog({
    super.key,
    required this.userId,
    required this.userName,
    required this.currentPct,
    required this.globalPct,
    required this.categoryPct,
  });

  final String userId;
  final String userName;
  final double? currentPct; // null if no custom commission yet
  final double globalPct;
  final double? categoryPct;

  @override
  State<ProviderEditDialog> createState() => _ProviderEditDialogState();
}

class _ProviderEditDialogState extends State<ProviderEditDialog> {
  late double _pct;
  String _reason = _kReasonOptions.first;
  final _notesCtrl = TextEditingController();
  DateTime? _expiresAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _pct = widget.currentPct ?? widget.globalPct;
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save({required bool clear}) async {
    setState(() => _saving = true);
    try {
      await MonetizationService.setUserCommission(
        userId: widget.userId,
        userName: widget.userName,
        percentage: clear ? null : _pct,
        reason: _reason,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        expiresAt: _expiresAt,
        oldPercentage: widget.currentPct,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('שגיאה בשמירה: $e'),
            backgroundColor: MonetizationTokens.danger),
      );
      setState(() => _saving = false);
    }
  }

  Future<void> _pickExpiresAt() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _expiresAt = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MonetizationTokens.radiusXl)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('עריכת עמלה — ${widget.userName}',
                  style: MonetizationTokens.h2),
              const SizedBox(height: 4),
              Text(
                'שכבה 3 (פרטנית). דורסת את הקטגוריה וה-default.',
                style: MonetizationTokens.caption,
              ),
              const SizedBox(height: 18),

              // Presets
              Row(
                children: [
                  _PresetChip(
                    label: 'ברירת מחדל',
                    sub: '${widget.globalPct.toStringAsFixed(1)}%',
                    selected:
                        (_pct - widget.globalPct).abs() < 0.01,
                    onTap: () => setState(() => _pct = widget.globalPct),
                  ),
                  if (widget.categoryPct != null) ...[
                    const SizedBox(width: 8),
                    _PresetChip(
                      label: 'קטגוריה',
                      sub: '${widget.categoryPct!.toStringAsFixed(1)}%',
                      selected: (_pct - widget.categoryPct!).abs() < 0.01,
                      onTap: () => setState(() => _pct = widget.categoryPct!),
                    ),
                  ],
                  const SizedBox(width: 8),
                  _PresetChip(
                    label: 'מותאם',
                    sub: '${_pct.toStringAsFixed(1)}%',
                    selected: (_pct - widget.globalPct).abs() > 0.01 &&
                        (widget.categoryPct == null ||
                            (_pct - widget.categoryPct!).abs() > 0.01),
                    onTap: () {},
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Slider + numeric input
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _pct,
                      min: 0,
                      max: 30,
                      divisions: 300,
                      label: _pct.toStringAsFixed(1),
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _pct = v),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: TextFormField(
                      initialValue: _pct.toStringAsFixed(1),
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        suffixText: '%',
                      ),
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed != null && parsed >= 0 && parsed <= 30) {
                          setState(() => _pct = parsed);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Reason
              DropdownButtonFormField<String>(
                value: _reason,
                decoration: const InputDecoration(
                  labelText: 'סיבה',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: _kReasonOptions
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => setState(() => _reason = v ?? _reason),
              ),
              const SizedBox(height: 12),

              // Notes
              TextField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'הערות (אופציונלי)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),

              // Expiry
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _expiresAt == null
                          ? 'קבוע — ללא תאריך תפוגה'
                          : 'פג תוקף: ${_expiresAt!.day}/${_expiresAt!.month}/${_expiresAt!.year}',
                      style: MonetizationTokens.caption,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _saving ? null : _pickExpiresAt,
                    icon: const Icon(Icons.schedule, size: 16),
                    label: const Text('תאריך תפוגה'),
                  ),
                  if (_expiresAt != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() => _expiresAt = null),
                    ),
                ],
              ),
              const SizedBox(height: 20),

              // Actions
              Row(
                children: [
                  if (widget.currentPct != null)
                    TextButton(
                      onPressed: _saving ? null : () => _save(clear: true),
                      style: TextButton.styleFrom(
                          foregroundColor: MonetizationTokens.danger),
                      child: const Text('הסר override'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.pop(context, false),
                    child: const Text('ביטול'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saving ? null : () => _save(clear: false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MonetizationTokens.textPrimary,
                      foregroundColor: Colors.white,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('שמור'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.sub,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MonetizationTokens.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? MonetizationTokens.primaryLight : Colors.white,
            border: Border.all(
              color: selected
                  ? MonetizationTokens.primaryBorder
                  : MonetizationTokens.borderSoft,
              width: 0.5,
            ),
            borderRadius: BorderRadius.circular(MonetizationTokens.radiusMd),
          ),
          child: Column(
            children: [
              Text(label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: selected
                        ? MonetizationTokens.primaryDarker
                        : MonetizationTokens.textPrimary,
                  )),
              const SizedBox(height: 2),
              Text(sub,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// Exposed helper for use from the admin tab.
// Kept at file scope (not inside class) for easy import.
Future<bool?> showProviderEditDialog(
  BuildContext context, {
  required String userId,
  required String userName,
  required double? currentPct,
  required double globalPct,
  double? categoryPct,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => ProviderEditDialog(
      userId: userId,
      userName: userName,
      currentPct: currentPct,
      globalPct: globalPct,
      categoryPct: categoryPct,
    ),
  );
}

// Keep `Timestamp` import alive in case of future use.
// ignore: unused_element
Type _keep = Timestamp;
