// Delivery Express — Step 1 of 4: "מה לשלוח?" (package type + urgency).
//
// Customer picks ONE of the 6 package buckets (documents / small / medium
// / large / flowers / cakes) AND ONE of the 6 urgency reasons. Optional
// free-text description for the courier. The picks are passed to
// DeliveryExpressLocationScreen which carries them forward to auction
// creation.
//
// Layout per spec / CLAUDE.md §57 pattern: urgency banner up top, 6-package
// grid, 6-urgency chip row, optional description text-field, safety strip
// near the bottom that opens DeliveryExpressSafetyDialog, "המשך" CTA at
// the bottom that's only enabled once package + urgency are picked.
import 'package:flutter/material.dart';

import '../../constants/delivery_express_constants.dart';
import 'delivery_express_location_screen.dart';
import 'delivery_express_palette.dart';
import 'delivery_express_safety_dialog.dart';

class DeliveryExpressPackageScreen extends StatefulWidget {
  const DeliveryExpressPackageScreen({super.key});

  @override
  State<DeliveryExpressPackageScreen> createState() =>
      _DeliveryExpressPackageScreenState();
}

class _DeliveryExpressPackageScreenState
    extends State<DeliveryExpressPackageScreen> {
  String? _selectedPackage;
  String? _selectedUrgency;
  final _descriptionCtrl = TextEditingController();

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    super.dispose();
  }

  bool get _canContinue =>
      _selectedPackage != null && _selectedUrgency != null;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: DeliveryExpressPalette.bgPrimary,
        appBar: AppBar(
          backgroundColor: DeliveryExpressPalette.bgPrimary,
          surfaceTintColor: DeliveryExpressPalette.bgPrimary,
          elevation: 0.5,
          centerTitle: false,
          iconTheme: const IconThemeData(
            color: DeliveryExpressPalette.textPrimary,
          ),
          title: const Text(
            'מצא שליח דחוף',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: DeliveryExpressPalette.textPrimary,
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _UrgencyBanner(),
                      const SizedBox(height: 18),
                      const Text(
                        'מה לשלוח?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: DeliveryExpressPalette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'בחר את סוג החבילה — זה יעזור לשליח להגיע עם הציוד המתאים',
                        style: TextStyle(
                          fontSize: 13,
                          color: DeliveryExpressPalette.textSecondary,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _PackageGrid(
                        selectedId: _selectedPackage,
                        onPick: (id) =>
                            setState(() => _selectedPackage = id),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'למה זה דחוף?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: DeliveryExpressPalette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'הקונטקסט מופיע אצל השליח — לא חובה לפרט יותר',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: DeliveryExpressPalette.textSecondary,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _UrgencyChips(
                        selectedId: _selectedUrgency,
                        onPick: (id) =>
                            setState(() => _selectedUrgency = id),
                      ),
                      const SizedBox(height: 20),
                      _buildDescription(),
                      const SizedBox(height: 18),
                      const _SafetyStrip(),
                    ],
                  ),
                ),
              ),
              _CtaBar(
                enabled: _canContinue,
                onContinue: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DeliveryExpressLocationScreen(
                        packageType: _selectedPackage!,
                        urgencyReason: _selectedUrgency!,
                        packageDescription: _descriptionCtrl.text.trim(),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDescription() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: DeliveryExpressPalette.bgSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: DeliveryExpressPalette.borderTertiary,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.notes_rounded,
                size: 15,
                color: DeliveryExpressPalette.textSecondary,
              ),
              const SizedBox(width: 6),
              const Text(
                'תיאור החבילה (לא חובה)',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: DeliveryExpressPalette.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '${_descriptionCtrl.text.length} / 200',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: DeliveryExpressPalette.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _descriptionCtrl,
            minLines: 2,
            maxLines: 3,
            maxLength: 200,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'לדוגמה: "תעודות מקור ללשכת עו"ד" / "זר ליום הולדת"',
              hintStyle: TextStyle(
                fontSize: 13,
                color: DeliveryExpressPalette.textTertiary,
              ),
              border: InputBorder.none,
              isDense: true,
              counterText: '',
            ),
            style: const TextStyle(
              fontSize: 13.5,
              color: DeliveryExpressPalette.textPrimary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════════

class _UrgencyBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DeliveryExpressPalette.red50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DeliveryExpressPalette.red500.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: DeliveryExpressPalette.red500,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.bolt_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'משלוח דחוף',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DeliveryExpressPalette.red700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'נשלח התראה לכל השליחים ברדיוס — מקבל הצעות תוך 60-90 שניות',
                  style: TextStyle(
                    fontSize: 12,
                    color: DeliveryExpressPalette.red700,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageGrid extends StatelessWidget {
  final String? selectedId;
  final ValueChanged<String> onPick;

  const _PackageGrid({required this.selectedId, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: DeliveryExpressPackageType.all.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemBuilder: (_, i) {
        final id = DeliveryExpressPackageType.all[i];
        final selected = selectedId == id;
        return _PackageTile(
          id: id,
          selected: selected,
          onTap: () => onPick(id),
        );
      },
    );
  }
}

class _PackageTile extends StatelessWidget {
  final String id;
  final bool selected;
  final VoidCallback onTap;
  const _PackageTile({
    required this.id,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = DeliveryExpressPackageType.labelOf(id);
    final weight = DeliveryExpressPackageType.weightSpecOf(id);
    final icon = DeliveryExpressPackageType.iconOf(id);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? DeliveryExpressPalette.gold50
              : DeliveryExpressPalette.bgPrimary,
          border: Border.all(
            color: selected
                ? DeliveryExpressPalette.gold500
                : DeliveryExpressPalette.borderTertiary,
            width: selected ? 1.5 : 0.5,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: DeliveryExpressPalette.gold500
                        .withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 26,
              color: selected
                  ? DeliveryExpressPalette.gold700
                  : DeliveryExpressPalette.gold500,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected
                    ? DeliveryExpressPalette.gold900
                    : DeliveryExpressPalette.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              weight,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                color: DeliveryExpressPalette.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UrgencyChips extends StatelessWidget {
  final String? selectedId;
  final ValueChanged<String> onPick;

  const _UrgencyChips({required this.selectedId, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: DeliveryExpressUrgencyReason.all.map((id) {
        final selected = selectedId == id;
        final label = DeliveryExpressUrgencyReason.labelOf(id);
        final icon = DeliveryExpressUrgencyReason.iconOf(id);
        return InkWell(
          onTap: () => onPick(id),
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? DeliveryExpressPalette.gold50
                  : DeliveryExpressPalette.bgPrimary,
              border: Border.all(
                color: selected
                    ? DeliveryExpressPalette.gold500
                    : DeliveryExpressPalette.borderTertiary,
                width: selected ? 1.2 : 0.5,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: selected
                      ? DeliveryExpressPalette.gold700
                      : DeliveryExpressPalette.textSecondary,
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? DeliveryExpressPalette.gold900
                        : DeliveryExpressPalette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SafetyStrip extends StatelessWidget {
  const _SafetyStrip();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DeliveryExpressPalette.amber50,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => showDeliveryExpressSafetyDialog(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.tips_and_updates_rounded,
                size: 20,
                color: DeliveryExpressPalette.amber600,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'טיפים לפני שליחה',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: DeliveryExpressPalette.amber800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'מה שכדאי לבדוק לפני שתשלח את החבילה',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: DeliveryExpressPalette.amber800,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_back_ios_rounded,
                size: 13,
                color: DeliveryExpressPalette.amber600,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CtaBar extends StatelessWidget {
  final bool enabled;
  final VoidCallback onContinue;

  const _CtaBar({required this.enabled, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: DeliveryExpressPalette.bgPrimary,
        border: Border(
          top: BorderSide(
            color: DeliveryExpressPalette.borderTertiary,
            width: 0.5,
          ),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: enabled ? onContinue : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: DeliveryExpressPalette.gold500,
            disabledBackgroundColor: DeliveryExpressPalette.borderSecondary
                .withValues(alpha: 0.55),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'המשך',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: 6),
              Icon(Icons.arrow_back_rounded, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
