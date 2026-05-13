// Motorcycle Towing CSM — Provider settings block ("הגדרות גרר אופנועים").
// Mounted in edit_profile_screen.dart AFTER the sub-category dropdown when
// the selected sub resolves to "גרר אופנועים" via isMotorcycleTowingCategory.
//
// 6 sections (spec §motorcycle PROMPT_FOR_CLAUDE_CODE.md):
//   1. Bike types — multi-select grid, images come from Firestore catalog
//   2. Pricing — base + perKm + night surcharge + emergency surcharge
//   3. Equipment — 5 toggles
//   4. Service cases — 9 multi-select pills
//   5. Service area — 2 tabs (radius / polygon)
//   6. Smart features — 3 toggles
//
// Hardcoded rules (CLAUDE.md §41-style):
//  - NO insurance, NO documents, NO calendar (already global).
//  - Provider CANNOT change bike-type images — admin owns them.
//  - Light cream background + soft purple/green/amber accents (NOT dark
//    glass like handyman/cleaning/fitness — the spec is explicit about
//    minimal-but-informative + no dramatic gradients).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../constants/motorcycle_bike_types_catalog.dart';
import '../../constants/motorcycle_service_cases_catalog.dart';
import '../../models/motorcycle_tow_profile.dart';
import '../../services/motorcycle_bike_types_service.dart';
import '../../widgets/wolt_tile_layer.dart';
import 'motorcycle_tow_palette.dart';

// Shorthand alias to keep the existing `_MTPalette.foo` references inside
// this file's UI code readable and minimise the diff.
typedef _MTPalette = MotorcycleTowPalette;

// ═══════════════════════════════════════════════════════════════════════════
// PUBLIC WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class MotorcycleTowSettingsBlock extends StatefulWidget {
  final MotorcycleTowProfile initialProfile;
  final ValueChanged<MotorcycleTowProfile> onChanged;

  const MotorcycleTowSettingsBlock({
    super.key,
    required this.initialProfile,
    required this.onChanged,
  });

  @override
  State<MotorcycleTowSettingsBlock> createState() =>
      _MotorcycleTowSettingsBlockState();
}

class _MotorcycleTowSettingsBlockState
    extends State<MotorcycleTowSettingsBlock> {
  late MotorcycleTowProfile _profile;
  late TextEditingController _basePriceCtrl;
  late TextEditingController _pricePerKmCtrl;
  late TextEditingController _nightPercentCtrl;
  late TextEditingController _emergencyPercentCtrl;
  late TextEditingController _baseAddressCtrl;

  @override
  void initState() {
    super.initState();
    var p = widget.initialProfile;
    // Seed defaults for brand-new providers so they aren't shown an empty
    // form. Service cases default to the 6 hot ones; equipment is already
    // default-true on 4 of 5 in the model constructor.
    if (p.serviceCases.isEmpty) {
      p = p.copyWith(serviceCases: defaultMotorcycleServiceCaseIds());
    }
    _profile = p;
    _basePriceCtrl =
        TextEditingController(text: p.pricing.basePrice.toStringAsFixed(0));
    _pricePerKmCtrl =
        TextEditingController(text: p.pricing.pricePerKm.toStringAsFixed(1));
    _nightPercentCtrl = TextEditingController(
        text: p.pricing.nightSurchargePercent.toStringAsFixed(0));
    _emergencyPercentCtrl = TextEditingController(
        text: p.pricing.emergencySurchargePercent.toStringAsFixed(0));
    _baseAddressCtrl = TextEditingController(text: p.serviceArea.baseAddress);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onChanged(_profile);
    });
  }

  @override
  void dispose() {
    _basePriceCtrl.dispose();
    _pricePerKmCtrl.dispose();
    _nightPercentCtrl.dispose();
    _emergencyPercentCtrl.dispose();
    _baseAddressCtrl.dispose();
    super.dispose();
  }

  void _emit(MotorcycleTowProfile next) {
    setState(() => _profile = next);
    widget.onChanged(next);
  }

  // ── Sub-update helpers ───────────────────────────────────────────────────

  void _toggleBikeType(String id) {
    final ids = List<String>.from(_profile.bikeTypeIds);
    if (ids.contains(id)) {
      ids.remove(id);
    } else {
      ids.add(id);
    }
    _emit(_profile.copyWith(bikeTypeIds: ids));
  }

  void _toggleServiceCase(String id) {
    final ids = List<String>.from(_profile.serviceCases);
    if (ids.contains(id)) {
      ids.remove(id);
    } else {
      ids.add(id);
    }
    _emit(_profile.copyWith(serviceCases: ids));
  }

  void _setEquipmentField({
    bool? flatbed,
    bool? wheelCradle,
    bool? softStraps,
    bool? electricWinch,
    bool? towDolly,
  }) {
    _emit(_profile.copyWith(
      equipment: _profile.equipment.copyWith(
        flatbed: flatbed,
        wheelCradle: wheelCradle,
        softStraps: softStraps,
        electricWinch: electricWinch,
        towDolly: towDolly,
      ),
    ));
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: BoxDecoration(
          color: _MTPalette.bgPrimary,
          border: Border.all(color: _MTPalette.purple300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSection(
                    number: 1,
                    title: 'סוגי אופנועים שאתה גורר',
                    description:
                        'סמן את כל הסוגים שיש לך ציוד מתאים לטפל בהם. הלקוח יראה רק את אלו שתסמן.',
                    required: true,
                    done: _profile.hasBikeTypes,
                    child: _buildBikeTypesSection(),
                  ),
                  _buildDivider(),
                  _buildSection(
                    number: 2,
                    title: 'תמחור',
                    description:
                        'המחירים יוצגו ללקוח בשקיפות מלאה. תוכל לעדכן בכל עת.',
                    required: true,
                    done: _profile.hasPricing,
                    child: _buildPricingSection(),
                  ),
                  _buildDivider(),
                  _buildSection(
                    number: 3,
                    title: 'ציוד ושיטת גרירה',
                    description:
                        'בחר את הציוד והשיטות שברשותך. זה בונה אמון אצל לקוחות שמבינים באופנועים.',
                    done: _profile.hasEquipment,
                    child: _buildEquipmentSection(),
                  ),
                  _buildDivider(),
                  _buildSection(
                    number: 4,
                    title: 'סוגי קריאות שאתה מטפל בהן',
                    description: 'סמן את כל המקרים שאתה מוכן לקבל.',
                    done: _profile.hasServiceCases,
                    child: _buildServiceCasesSection(),
                  ),
                  _buildDivider(),
                  _buildSection(
                    number: 5,
                    title: 'אזור פעילות',
                    description:
                        'הגדר איפה אתה עובד — ברדיוס מהבסיס, או צייר אזור מדויק על המפה.',
                    required: true,
                    done: _profile.hasServiceArea,
                    child: _buildServiceAreaSection(),
                  ),
                  _buildDivider(),
                  _buildSection(
                    number: 6,
                    title: 'תכונות חכמות',
                    description: 'שירותים שמבדילים אותך — מומלץ להפעיל את כולם.',
                    done: true,
                    child: _buildSmartFeaturesSection(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────── HEADER ───────────────────────────────────────────

  Widget _buildHeader() {
    final completion = _profile.completionPercent;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: _MTPalette.purple50,
        border: Border(
          bottom: BorderSide(color: _MTPalette.purple200, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _MTPalette.purple500,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.two_wheeler_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'הגדרות גרר אופנועים',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _MTPalette.purple900,
                    height: 1.2,
                  ),
                ),
                Text(
                  'פרטי השירות שיוצגו ללקוחות',
                  style: TextStyle(
                    fontSize: 11,
                    color: _MTPalette.purple500,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          // Progress
          Container(
            width: 60,
            height: 4,
            decoration: BoxDecoration(
              color: _MTPalette.purple200,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: (completion / 100).clamp(0, 1),
              child: Container(
                decoration: BoxDecoration(
                  color: _MTPalette.purple500,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$completion%',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: _MTPalette.purple500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Divider(
          height: 1,
          thickness: 0.5,
          color: _MTPalette.borderTertiary,
        ),
      );

  // ───────────────────── SECTION SHELL ────────────────────────────────────

  Widget _buildSection({
    required int number,
    required String title,
    required String description,
    bool required = false,
    bool done = false,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color:
                      done ? _MTPalette.green500 : _MTPalette.bgSecondary,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: done
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 12)
                    : Text(
                        '$number',
                        style: const TextStyle(
                          fontSize: 11,
                          color: _MTPalette.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _MTPalette.textPrimary,
                  ),
                ),
              ),
              if (required)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _MTPalette.amber50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'חובה',
                    style: TextStyle(
                      fontSize: 10,
                      color: _MTPalette.amber600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              fontSize: 12,
              color: _MTPalette.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  // ═══════════════════════ 1. BIKE TYPES ════════════════════════════════════

  Widget _buildBikeTypesSection() {
    return StreamBuilder<List<MotorcycleBikeType>>(
      stream: MotorcycleBikeTypesService.streamBikeTypes(),
      initialData: kMotorcycleBikeTypesFallback,
      builder: (context, snap) {
        final types = (snap.data ?? kMotorcycleBikeTypesFallback)
            .where((t) => t.active)
            .toList();
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: types.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.78,
          ),
          itemBuilder: (_, i) {
            final t = types[i];
            final on = _profile.bikeTypeIds.contains(t.id);
            return _BikeTypeCard(
              type: t,
              selected: on,
              onTap: () => _toggleBikeType(t.id),
            );
          },
        );
      },
    );
  }

  // ═══════════════════════ 2. PRICING ═══════════════════════════════════════

  Widget _buildPricingSection() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _LabeledNumberField(
                label: 'מחיר בסיס',
                hint: 'מינימום קריאה (כולל 10 ק"מ ראשונים)',
                suffix: '₪',
                controller: _basePriceCtrl,
                onChanged: (v) => _emit(_profile.copyWith(
                  pricing: _profile.pricing.copyWith(basePrice: v),
                )),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _LabeledNumberField(
                label: 'מחיר לק"מ נוסף',
                hint: 'מעבר ל-10 ק"מ הראשונים',
                suffix: '₪',
                step: 0.5,
                controller: _pricePerKmCtrl,
                onChanged: (v) => _emit(_profile.copyWith(
                  pricing: _profile.pricing.copyWith(pricePerKm: v),
                )),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildNightSurchargeCard(),
        const SizedBox(height: 12),
        _LabeledNumberField(
          label: 'תוספת חירום מיידי',
          hint: 'לקריאות עם דרישת הגעה מתחת ל-30 דקות',
          suffix: '%',
          controller: _emergencyPercentCtrl,
          onChanged: (v) => _emit(_profile.copyWith(
            pricing: _profile.pricing.copyWith(emergencySurchargePercent: v),
          )),
        ),
      ],
    );
  }

  Widget _buildNightSurchargeCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _MTPalette.bgSecondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.nightlight_round,
                            size: 14, color: _MTPalette.purple500),
                        const SizedBox(width: 6),
                        const Text(
                          'תוספת לילה / שבת',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: _MTPalette.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'תופעל אוטומטית בשעות שתגדיר ובשבתות',
                      style: TextStyle(
                        fontSize: 11,
                        color: _MTPalette.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 90,
                child: _LabeledNumberField(
                  label: '',
                  suffix: '%',
                  controller: _nightPercentCtrl,
                  onChanged: (v) => _emit(_profile.copyWith(
                    pricing:
                        _profile.pricing.copyWith(nightSurchargePercent: v),
                  )),
                  dense: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(
              height: 1, thickness: 0.5, color: _MTPalette.borderTertiary),
          const SizedBox(height: 10),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              const Text(
                'שעות לילה:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: _MTPalette.textSecondary,
                ),
              ),
              const Text('מ-',
                  style: TextStyle(
                      fontSize: 11, color: _MTPalette.textTertiary)),
              _TimePicker(
                hour: _profile.pricing.nightStartHour,
                onChanged: (h) => _emit(_profile.copyWith(
                  pricing: _profile.pricing.copyWith(nightStartHour: h),
                )),
              ),
              const Text('עד',
                  style: TextStyle(
                      fontSize: 11, color: _MTPalette.textTertiary)),
              _TimePicker(
                hour: _profile.pricing.nightEndHour,
                onChanged: (h) => _emit(_profile.copyWith(
                  pricing: _profile.pricing.copyWith(nightEndHour: h),
                )),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════ 3. EQUIPMENT ═════════════════════════════════════

  Widget _buildEquipmentSection() {
    final eq = _profile.equipment;
    return Column(
      children: [
        _ToggleRow(
          label: 'משאית פלטה (Flatbed)',
          sub: 'השיטה הכי בטוחה — האופנוע מורם לחלוטין מהקרקע',
          value: eq.flatbed,
          onChanged: (v) => _setEquipmentField(flatbed: v),
        ),
        _ToggleRow(
          label: 'עריסת גלגל קדמי (Wheel Cradle)',
          sub: 'לאופנועי ספורט עם פיירינג נמוך',
          value: eq.wheelCradle,
          onChanged: (v) => _setEquipmentField(wheelCradle: v),
        ),
        _ToggleRow(
          label: 'רצועות בד רכות (Soft Straps)',
          sub: 'לא פוגעות בכרום, צבע ופיירינג',
          value: eq.softStraps,
          onChanged: (v) => _setEquipmentField(softStraps: v),
        ),
        _ToggleRow(
          label: 'כננת חשמלית',
          sub: 'לאופנועים עם מנוע תקוע או גיר נעול',
          value: eq.electricWinch,
          onChanged: (v) => _setEquipmentField(electricWinch: v),
        ),
        _ToggleRow(
          label: 'דולי עגלה (Tow Dolly)',
          sub: 'למרחקים קצרים — גלגל אחורי על הכביש',
          value: eq.towDolly,
          onChanged: (v) => _setEquipmentField(towDolly: v),
          last: true,
        ),
      ],
    );
  }

  // ═══════════════════════ 4. SERVICE CASES ═════════════════════════════════

  Widget _buildServiceCasesSection() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final c in kMotorcycleServiceCasesCatalog)
          _Pill(
            label: c.name,
            selected: _profile.serviceCases.contains(c.id),
            onTap: () => _toggleServiceCase(c.id),
          ),
      ],
    );
  }

  // ═══════════════════════ 5. SERVICE AREA ══════════════════════════════════

  Widget _buildServiceAreaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tabs
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _MTPalette.bgSecondary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AreaTab(
                label: 'רדיוס מהבסיס',
                icon: Icons.gps_fixed_rounded,
                active: _profile.serviceArea.mode == 'radius',
                onTap: () => _emit(_profile.copyWith(
                  serviceArea: _profile.serviceArea.copyWith(mode: 'radius'),
                )),
              ),
              _AreaTab(
                label: 'ציור אזור על המפה',
                icon: Icons.draw_rounded,
                active: _profile.serviceArea.mode == 'polygon',
                onTap: () => _emit(_profile.copyWith(
                  serviceArea:
                      _profile.serviceArea.copyWith(mode: 'polygon'),
                )),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_profile.serviceArea.mode == 'radius')
          _buildRadiusPane()
        else
          _buildPolygonPane(),
      ],
    );
  }

  Widget _buildRadiusPane() {
    final area = _profile.serviceArea;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'כתובת בסיס',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _MTPalette.textPrimary,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: _baseAddressCtrl,
          decoration: _inputDecoration(),
          style: const TextStyle(fontSize: 13),
          onChanged: (v) => _emit(_profile.copyWith(
            serviceArea: _profile.serviceArea.copyWith(baseAddress: v),
          )),
        ),
        const SizedBox(height: 12),
        const Text(
          'רדיוס שירות מהבסיס',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _MTPalette.textPrimary,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _MTPalette.purple500,
                  inactiveTrackColor: _MTPalette.purple200,
                  thumbColor: _MTPalette.purple500,
                  overlayColor:
                      _MTPalette.purple500.withValues(alpha: 0.15),
                ),
                child: Slider(
                  min: 5,
                  max: 200,
                  divisions: 39,
                  value: area.radiusKm.clamp(5, 200),
                  onChanged: (v) => _emit(_profile.copyWith(
                    serviceArea: _profile.serviceArea.copyWith(radiusKm: v),
                  )),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _MTPalette.purple50,
                borderRadius: BorderRadius.circular(6),
              ),
              constraints: const BoxConstraints(minWidth: 70),
              alignment: Alignment.center,
              child: Text(
                '${area.radiusKm.round()} ק"מ',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _MTPalette.purple700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildAreaMap(radius: true),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _MTPalette.bgSecondary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _MTPalette.purple500.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                  border: Border.all(color: _MTPalette.purple500, width: 1.5),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'אזור שירות · ~${_estimateAreaKm2(area.radiusKm).round()} קמ"ר',
                  style: const TextStyle(
                    fontSize: 12,
                    color: _MTPalette.textSecondary,
                  ),
                ),
              ),
              Text(
                '~${_estimateCitiesInRadius(area.radiusKm)} ערים בכיסוי',
                style: const TextStyle(
                  fontSize: 11,
                  color: _MTPalette.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPolygonPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _MTPalette.amber50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 14, color: _MTPalette.amber600),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'איך זה עובד: לחץ על המפה כדי להוסיף נקודות. כל נקודה תחבר את האזור שאתה רוצה לכסות. בסוף לחץ "סיים ציור".',
                  style: TextStyle(
                    fontSize: 12,
                    color: _MTPalette.amber800,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _buildAreaMap(radius: false),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _profile.serviceArea.polygonPoints.isEmpty
                  ? null
                  : () => _emit(_profile.copyWith(
                        serviceArea: _profile.serviceArea
                            .copyWith(polygonPoints: const []),
                      )),
              icon: const Icon(Icons.delete_outline_rounded, size: 14),
              label: const Text('נקה'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _MTPalette.textSecondary,
                side: const BorderSide(color: _MTPalette.borderSecondary),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                textStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
            const Spacer(),
            Text(
              'אזור מצויר · ${_profile.serviceArea.polygonPoints.length} נקודות',
              style: const TextStyle(
                fontSize: 11,
                color: _MTPalette.textTertiary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAreaMap({required bool radius}) {
    final area = _profile.serviceArea;
    // Guard against pre-load state where the doc hasn't hydrated yet.
    // (0,0) is the Gulf of Guinea and would render as empty ocean tiles
    // (perceived as a grey square). Fall back to Tel Aviv if either
    // coord is exactly zero.
    final lat = area.baseLat == 0 ? 32.0853 : area.baseLat;
    final lng = area.baseLng == 0 ? 34.7818 : area.baseLng;
    final center = LatLng(lat, lng);
    // ClipRRect (instead of Container+clipBehavior) is the reliable
    // pattern for rounding flutter_map's CanvasKit-rendered tiles —
    // some Flutter Web versions paint at 0×0 inside a Container that
    // has `clipBehavior: Clip.antiAlias` + a `BoxDecoration` border
    // without a fill color, which is what produced the grey square.
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 240,
        decoration: BoxDecoration(
          color: _MTPalette.bgSecondary,
          border:
              Border.all(color: _MTPalette.borderTertiary, width: 0.5),
        ),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: radius ? 9.5 : 10,
            minZoom: 6,
            maxZoom: 18,
            onTap: radius
                ? null
                : (_, p) {
                    final next = [
                      ..._profile.serviceArea.polygonPoints,
                      MotorcycleTowGeoPoint(
                          lat: p.latitude, lng: p.longitude),
                    ];
                    _emit(_profile.copyWith(
                      serviceArea:
                          _profile.serviceArea.copyWith(polygonPoints: next),
                    ));
                  },
          ),
          children: [
            // Unified Wolt-style tiles. WoltTileLayer now ships with an
            // OSM `fallbackUrl` + soft cream loading skeleton, so the
            // historical "Mapbox returns blank tiles" failure mode no
            // longer renders as a grey square — it auto-fails over to
            // OSM. See CLAUDE.md §78.
            WoltTileLayer.forContext(context, maxZoom: 19),
          if (radius)
            CircleLayer(
              circles: [
                CircleMarker(
                  point: center,
                  // flutter_map's `radius` is in pixels at the current zoom
                  // OR in metres when `useRadiusInMeter: true`. We want km
                  // → metres.
                  radius: area.radiusKm * 1000,
                  useRadiusInMeter: true,
                  color: _MTPalette.purple500.withValues(alpha: 0.18),
                  borderColor: _MTPalette.purple500,
                  borderStrokeWidth: 2,
                ),
              ],
            ),
          if (!radius && area.polygonPoints.length >= 2)
            PolygonLayer(
              polygons: [
                Polygon(
                  points: [
                    for (final p in area.polygonPoints) LatLng(p.lat, p.lng),
                  ],
                  color: _MTPalette.purple500.withValues(alpha: 0.18),
                  borderColor: _MTPalette.purple500,
                  borderStrokeWidth: 2,
                ),
              ],
            ),
          MarkerLayer(
            markers: [
              Marker(
                point: center,
                width: 20,
                height: 20,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _MTPalette.purple500,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
              if (!radius)
                for (final p in area.polygonPoints)
                  Marker(
                    point: LatLng(p.lat, p.lng),
                    width: 14,
                    height: 14,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border:
                            Border.all(color: _MTPalette.purple500, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════ 6. SMART FEATURES ═══════════════════════════════

  Widget _buildSmartFeaturesSection() {
    final f = _profile.smartFeatures;
    return Column(
      children: [
        _ToggleRow(
          label: 'תמונות "לפני/אחרי" אוטומטיות',
          sub: 'המערכת תזכיר לך לצלם בכל גרירה — מגן עליך מפני תלונות',
          value: f.beforeAfterPhotos,
          onChanged: (v) => _emit(_profile.copyWith(
            smartFeatures: f.copyWith(beforeAfterPhotos: v),
          )),
        ),
        _ToggleRow(
          label: 'הצעת מחיר מיידית',
          sub: 'מחושבת אוטומטית מהמחירים שמילאת למעלה',
          value: f.instantQuote,
          onChanged: (v) => _emit(_profile.copyWith(
            smartFeatures: f.copyWith(instantQuote: v),
          )),
        ),
        _ToggleRow(
          label: 'צ\'אט פנימי עם הלקוח',
          sub: 'תקשורת מאובטחת — בלי לחשוף מספר טלפון',
          value: f.internalChat,
          onChanged: (v) => _emit(_profile.copyWith(
            smartFeatures: f.copyWith(internalChat: v),
          )),
          last: true,
        ),
      ],
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  InputDecoration _inputDecoration() => InputDecoration(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: _MTPalette.borderSecondary, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: _MTPalette.borderSecondary, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: _MTPalette.purple500, width: 1),
        ),
        filled: true,
        fillColor: _MTPalette.bgPrimary,
      );

  /// Approximate πr².
  double _estimateAreaKm2(double radiusKm) =>
      3.14159265358979 * radiusKm * radiusKm;

  /// Rough cities-in-radius heuristic — Gush Dan density (≈1 city per 600 km²).
  int _estimateCitiesInRadius(double radiusKm) {
    final area = _estimateAreaKm2(radiusKm);
    return (area / 600).round().clamp(1, 200);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _BikeTypeCard extends StatelessWidget {
  final MotorcycleBikeType type;
  final bool selected;
  final VoidCallback onTap;
  const _BikeTypeCard({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: selected
                ? _MTPalette.purple300
                : _MTPalette.borderTertiary,
            width: selected ? 1 : 0.5,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _MTPalette.purple300.withValues(alpha: 0.3),
                    blurRadius: 0,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: _MTPalette.bgSecondary),
                  if (type.imageUrl.isNotEmpty)
                    Image.network(
                      type.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.two_wheeler_rounded,
                        color: _MTPalette.textTertiary,
                      ),
                    ),
                  if (selected)
                    Container(
                      color: _MTPalette.purple500.withValues(alpha: 0.08),
                    ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              color: selected ? _MTPalette.purple50 : _MTPalette.bgPrimary,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      type.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: selected
                            ? _MTPalette.purple700
                            : _MTPalette.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: selected
                          ? _MTPalette.purple500
                          : _MTPalette.bgPrimary,
                      border: Border.all(
                        color: selected
                            ? _MTPalette.purple500
                            : _MTPalette.borderSecondary,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.center,
                    child: selected
                        ? const Icon(Icons.check_rounded,
                            size: 11, color: Colors.white)
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledNumberField extends StatelessWidget {
  final String label;
  final String? hint;
  final String suffix;
  final TextEditingController controller;
  final ValueChanged<double> onChanged;
  final double? step;
  final bool dense;

  const _LabeledNumberField({
    required this.label,
    this.hint,
    required this.suffix,
    required this.controller,
    required this.onChanged,
    this.step,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _MTPalette.textPrimary,
              ),
            ),
          ),
        TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
          ],
          style: const TextStyle(fontSize: 13),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.start,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 11,
              vertical: dense ? 7 : 9,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: _MTPalette.borderSecondary, width: 0.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: _MTPalette.borderSecondary, width: 0.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: _MTPalette.purple500, width: 1),
            ),
            prefixText: '$suffix ',
            prefixStyle: const TextStyle(
              fontSize: 12,
              color: _MTPalette.textTertiary,
            ),
            filled: true,
            fillColor: _MTPalette.bgPrimary,
          ),
          onChanged: (v) {
            final parsed = double.tryParse(v.trim());
            if (parsed != null) onChanged(parsed);
          },
        ),
        if (hint != null && hint!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              hint!,
              style: const TextStyle(
                fontSize: 11,
                color: _MTPalette.textTertiary,
              ),
            ),
          ),
      ],
    );
  }
}

class _TimePicker extends StatelessWidget {
  final int hour;
  final ValueChanged<int> onChanged;
  const _TimePicker({required this.hour, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: hour, minute: 0),
        );
        if (picked != null) onChanged(picked.hour);
      },
      child: Container(
        width: 80,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: _MTPalette.bgPrimary,
          border: Border.all(color: _MTPalette.borderSecondary, width: 0.5),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          '${hour.toString().padLeft(2, '0')}:00',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: _MTPalette.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool last;

  const _ToggleRow({
    required this.label,
    required this.sub,
    required this.value,
    required this.onChanged,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(
                bottom: BorderSide(
                  color: _MTPalette.borderTertiary,
                  width: 0.5,
                ),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _MTPalette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 11,
                    color: _MTPalette.textTertiary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: _MTPalette.purple500,
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _MTPalette.purple50 : _MTPalette.bgPrimary,
          border: Border.all(
            color: selected
                ? _MTPalette.purple300
                : _MTPalette.borderTertiary,
            width: 0.5,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check_rounded,
                  size: 11, color: _MTPalette.purple700),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: selected
                    ? _MTPalette.purple700
                    : _MTPalette.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AreaTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _AreaTab({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? _MTPalette.bgPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: _MTPalette.borderTertiary.withValues(alpha: 0.6),
                    blurRadius: 0,
                    spreadRadius: 0.5,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 12,
                color: active
                    ? _MTPalette.textPrimary
                    : _MTPalette.textSecondary),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: active
                    ? _MTPalette.textPrimary
                    : _MTPalette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
