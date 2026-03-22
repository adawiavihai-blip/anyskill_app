// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/pricing_model.dart';

/// Expert-facing screen for configuring the 3-tier Dynamic Pricing Engine.
///
/// Fields written to Firestore `users/{uid}`:
///   pricingType, basePrice, unitType, addOns, pricePerHour (compat mirror)
class PriceSettingsScreen extends StatefulWidget {
  /// Pre-populate from existing Firestore data so edits feel instant.
  final Map<String, dynamic> userData;
  const PriceSettingsScreen({super.key, required this.userData});

  @override
  State<PriceSettingsScreen> createState() => _PriceSettingsScreenState();
}

class _PriceSettingsScreenState extends State<PriceSettingsScreen> {
  // ── State ─────────────────────────────────────────────────────────────────
  late PricingType _type;
  late TextEditingController _priceCtrl;
  late List<AddOn> _addOns;
  bool _saving = false;

  // Add-on form controllers (one pair per existing row + the "new" row)
  final _newTitleCtrl = TextEditingController();
  final _newPriceCtrl = TextEditingController();

  static const _kPurple     = Color(0xFF6366F1);
  static const _kPurpleSoft = Color(0xFFF0F0FF);

  @override
  void initState() {
    super.initState();
    final existing = PricingModel.fromFirestore(widget.userData);
    _type    = existing.type;
    _priceCtrl = TextEditingController(
        text: existing.basePrice > 0
            ? existing.basePrice.toStringAsFixed(0)
            : '');
    _addOns  = List.from(existing.addOns);
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _newTitleCtrl.dispose();
    _newPriceCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _typeLabel(PricingType t) {
    switch (t) {
      case PricingType.hourly:   return 'שעתי';
      case PricingType.fixed:    return 'קבוע';
      case PricingType.flexible: return 'גמיש';
    }
  }

  IconData _typeIcon(PricingType t) {
    switch (t) {
      case PricingType.hourly:   return Icons.schedule_rounded;
      case PricingType.fixed:    return Icons.attach_money_rounded;
      case PricingType.flexible: return Icons.tune_rounded;
    }
  }

  String _priceFieldLabel() {
    switch (_type) {
      case PricingType.hourly:   return 'מחיר לשעה (₪)';
      case PricingType.fixed:    return 'מחיר לביקור (₪)';
      case PricingType.flexible: return 'מחיר מינימלי / החל מ (₪)';
    }
  }

  String _priceFieldHint() {
    switch (_type) {
      case PricingType.hourly:   return 'לדוג׳ 150';
      case PricingType.fixed:    return 'לדוג׳ 300';
      case PricingType.flexible: return 'לדוג׳ 80';
    }
  }

  void _addAddOn() {
    final title = _newTitleCtrl.text.trim();
    final price = double.tryParse(_newPriceCtrl.text.trim());
    if (title.isEmpty || price == null || price <= 0) return;
    setState(() {
      _addOns.add(AddOn(title: title, price: price));
      _newTitleCtrl.clear();
      _newPriceCtrl.clear();
    });
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final basePrice = double.tryParse(_priceCtrl.text.trim());
    if (basePrice == null || basePrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('נא להזין מחיר בסיס תקין'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final model = PricingModel(
        type:      _type,
        basePrice: basePrice,
        unitType:  PricingModel.defaultUnitType(_type),
        addOns:    _addOns,
      );
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update(model.toFirestore());
      navigator.pop();
      messenger.showSnackBar(const SnackBar(
        content: Text('✅ הגדרות התמחור נשמרו'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('שגיאה: $e'),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('הגדרות תמחור',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('שמור',
                    style: TextStyle(
                        color: _kPurple,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // ── Pricing type toggle ─────────────────────────────────────────
            const Text('סוג תמחור',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                'בחר את מבנה המחיר שמתאים לשירות שלך',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: PricingType.values.reversed.map((t) {
                final selected = _type == t;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _type = t;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 8),
                      decoration: BoxDecoration(
                        color: selected ? _kPurple : _kPurpleSoft,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? _kPurple
                              : const Color(0xFF6366F1).withValues(alpha: 0.2),
                          width: selected ? 2 : 1,
                        ),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: _kPurple.withValues(alpha: 0.25),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                )
                              ]
                            : [],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_typeIcon(t),
                              size: 22,
                              color: selected ? Colors.white : _kPurple),
                          const SizedBox(height: 6),
                          Text(
                            _typeLabel(t),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: selected ? Colors.white : _kPurple,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 8),
            // Explanation chip
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _buildTypeExplanation(_type),
            ),

            const SizedBox(height: 24),

            // ── Base price field ────────────────────────────────────────────
            Text(_priceFieldLabel(),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            TextField(
              controller: _priceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.start,
              decoration: InputDecoration(
                hintText: _priceFieldHint(),
                prefixText: '₪ ',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _kPurple, width: 2),
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── Add-ons section ─────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${_addOns.length} תוספות',
                    style: const TextStyle(
                        fontSize: 12,
                        color: _kPurple,
                        fontWeight: FontWeight.w600)),
                const Text('תוספות (Add-ons)',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 4),
            const Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                'אפשרויות רשות שהלקוח יכול לבחור בעת ההזמנה (לדוג׳ "השכרת גלשן +₪50")',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 12),

            // Existing add-ons list
            if (_addOns.isNotEmpty)
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _addOns.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final ao = _addOns[i];
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _kPurpleSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _kPurple.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline,
                              color: Colors.red, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () =>
                              setState(() => _addOns.removeAt(i)),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '₪${ao.price.toStringAsFixed(0)}',
                          style: const TextStyle(
                              color: _kPurple,
                              fontWeight: FontWeight.w900,
                              fontSize: 15),
                        ),
                        const Spacer(),
                        Text(
                          ao.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                  );
                },
              ),

            const SizedBox(height: 12),

            // New add-on input row
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('הוסף תוסף חדש',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: _newPriceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          textAlign: TextAlign.start,
                          decoration: InputDecoration(
                            hintText: '₪',
                            isDense: true,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: _kPurple, width: 2),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _newTitleCtrl,
                          textAlign: TextAlign.right,
                          decoration: InputDecoration(
                            hintText: 'שם התוסף (לדוג׳ השכרת גלשן)',
                            hintTextDirection: TextDirection.rtl,
                            isDense: true,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: _kPurple, width: 2),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: _addAddOn,
                      icon: const Icon(Icons.add_circle_outline_rounded,
                          size: 18, color: _kPurple),
                      label: const Text('הוסף תוסף',
                          style: TextStyle(
                              color: _kPurple, fontWeight: FontWeight.bold)),
                      style: TextButton.styleFrom(
                        backgroundColor: _kPurpleSoft,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 36),

            // ── Save button ─────────────────────────────────────────────────
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPurple,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _saving
                  ? const CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5)
                  : const Text('שמור הגדרות תמחור',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeExplanation(PricingType t) {
    String text;
    IconData icon;
    switch (t) {
      case PricingType.hourly:
        text = 'הלקוח רואה את המחיר לשעה. המחיר הכולל ייגזר מהחבילה שנבחרה.';
        icon = Icons.schedule_rounded;
        break;
      case PricingType.fixed:
        text = 'מחיר קבוע לביקור/שירות ללא קשר לזמן. מתאים לשיפוצניקים, צלמים.';
        icon = Icons.attach_money_rounded;
        break;
      case PricingType.flexible:
        text =
            'אתה מציג מחיר מינימלי. ההצעה הסופית נקבעת לאחר שיחה עם הלקוח.';
        icon = Icons.tune_rounded;
        break;
    }
    return Container(
      key: ValueKey(t),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                textAlign: TextAlign.right,
                style:
                    const TextStyle(fontSize: 12, color: Color(0xFF4B5563))),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 16, color: _kPurple),
        ],
      ),
    );
  }
}
