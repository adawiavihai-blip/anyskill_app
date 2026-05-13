import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/courier_rules_catalog.dart';
import '../../constants/delivery_types_catalog.dart';
import '../../constants/delivery_vehicle_types.dart';
import '../../models/delivery_profile.dart';
import '../../services/csm_text_override_service.dart';

// Dark premium palette — scoped to this widget only.
const _kDarkBase = Color(0xFF0A0E1A);
const _kDarkBaseMid = Color(0xFF151B2E);
const _kDarkBaseDeep = Color(0xFF0F1420);
const _kGoldDark = Color(0xFFD97706);
const _kGoldMid = Color(0xFFF59E0B);
const _kGoldLight = Color(0xFFFBBF24);
const _kGoldPale = Color(0xFFFCD34D);
const _kStatusGreen = Color(0xFF16A34A);
const _kStatusGreenLight = Color(0xFF4ADE80);
const _kStatusRed = Color(0xFFDC2626);
const _kStatusRedLight = Color(0xFFFCA5A5);
const _kStatusBlue = Color(0xFF3B82F6);
const _kIndigoMedium = Color(0xFF6366F1);
const _kIndigoDark = Color(0xFF4F46E5);
const _kPurpleBorder = Color(0x66636CF1);

/// Provider-side "הקריירה שלך" (Your Career) settings block.
///
/// Rendered ONLY when the provider's sub-category is "משלוחים".
/// Writes the [DeliveryProfile] back via [onChanged] — the parent screen
/// persists it to `users/{uid}.deliveryProfile` + `provider_listings/*`.
class DeliverySettingsBlock extends StatefulWidget {
  final DeliveryProfile initialProfile;
  final ValueChanged<DeliveryProfile> onChanged;

  const DeliverySettingsBlock({
    super.key,
    required this.initialProfile,
    required this.onChanged,
  });

  @override
  State<DeliverySettingsBlock> createState() => _DeliverySettingsBlockState();
}

class _DeliverySettingsBlockState extends State<DeliverySettingsBlock> {
  late List<DeliveryDocument> _documents;
  late List<DeliveryVehicle> _vehicles;
  late List<String> _selectedTypes;
  late List<String> _selectedCustomers;
  late bool _immediateEnabled;
  late int _immediateSurcharge;
  late bool _regularEnabled;
  late bool _scheduledEnabled;
  late String _baseLocation;
  late List<String> _coverageCities;
  late DeliveryPricing _pricing;
  late List<StructuredCourierRule> _rules;
  late String _customRules;
  late List<BusinessPackage> _packages;

  final _customRulesCtrl = TextEditingController();
  final _baseLocationCtrl = TextEditingController();

  static const int _kMaxCustomRulesChars = 500;

  // ── CSM text override wiring ──
  static const _csmId = 'delivery';
  final _textOverrides = CsmTextOverrideService.instance;
  String _t(String key, String fallback) =>
      _textOverrides.t(_csmId, key, fallback);
  void _onTextOverridesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _textOverrides.ensureLoaded(_csmId);
    _textOverrides.addListener(_onTextOverridesChanged);
    final p = widget.initialProfile;

    // Documents — seed the 3 required if missing.
    final seedDocs = {
      'id_card': 'תעודת זהות',
      'driver_license': 'רישיון נהיגה',
      'vehicle_insurance': "ביטוח רכב + צד ג'",
    };
    final existing = {for (final d in p.documents) d.type: d};
    _documents = seedDocs.entries
        .map((e) =>
            existing[e.key] ??
            DeliveryDocument(id: e.key, type: e.key, nameHe: e.value))
        .toList();

    // Vehicles — seed scooter + car if empty.
    if (p.vehicles.isEmpty) {
      _vehicles = kDeliveryVehicles
          .map((def) => DeliveryVehicle(
                id: def.id,
                type: def.id,
                nameHe: def.nameHe,
                maxWeightKg: def.defaultMaxWeightKg,
                enabled: false,
              ))
          .toList();
    } else {
      _vehicles = List.of(p.vehicles);
      for (final def in kDeliveryVehicles) {
        if (!_vehicles.any((v) => v.type == def.id)) {
          _vehicles.add(DeliveryVehicle(
            id: def.id,
            type: def.id,
            nameHe: def.nameHe,
            maxWeightKg: def.defaultMaxWeightKg,
            enabled: false,
          ));
        }
      }
    }

    _selectedTypes = List.of(p.deliveryTypes);
    _selectedCustomers = p.customerTypes.isEmpty
        ? const ['private', 'business']
        : List.of(p.customerTypes);
    _immediateEnabled = p.availability.immediate.enabled;
    _immediateSurcharge = p.availability.immediate.surcharge;
    _regularEnabled = p.availability.regularEnabled;
    _scheduledEnabled = p.availability.scheduledEnabled;
    _baseLocation = p.serviceArea.baseLocation;
    _baseLocationCtrl.text = _baseLocation;
    _coverageCities = List.of(p.serviceArea.coverageCities);
    _pricing = p.pricing;

    // Rules — seed all 5 built-in rules if missing.
    if (p.rules.structuredRules.isEmpty) {
      _rules = kCourierRules
          .map((def) => StructuredCourierRule(
                id: def.id,
                type: def.type,
                icon: def.icon,
                titleHe: def.titleHe,
                descHe: def.descHe,
                enabled: false,
                color: def.colorName,
              ))
          .toList();
    } else {
      _rules = List.of(p.rules.structuredRules);
      for (final def in kCourierRules) {
        if (!_rules.any((r) => r.id == def.id)) {
          _rules.add(StructuredCourierRule(
            id: def.id,
            type: def.type,
            icon: def.icon,
            titleHe: def.titleHe,
            descHe: def.descHe,
            enabled: false,
            color: def.colorName,
          ));
        }
      }
    }
    _customRules = p.rules.customRules;
    _customRulesCtrl.text = _customRules;

    if (p.businessPackages.isEmpty) {
      _packages = const [
        BusinessPackage(
          id: 'basic',
          nameHe: '📦 בייסיק',
          deliveriesPerMonth: 5,
          monthlyPrice: 249,
          enabled: false,
        ),
        BusinessPackage(
          id: 'pro',
          nameHe: '🚀 פרו',
          deliveriesPerMonth: 15,
          monthlyPrice: 599,
          enabled: false,
        ),
      ];
    } else {
      _packages = List.of(p.businessPackages);
    }
  }

  @override
  void dispose() {
    _textOverrides.removeListener(_onTextOverridesChanged);
    _customRulesCtrl.dispose();
    _baseLocationCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(DeliveryProfile(
      documents: _documents,
      vehicles: _vehicles.where((v) => v.enabled).toList(),
      deliveryTypes: _selectedTypes,
      customerTypes: _selectedCustomers,
      availability: DeliveryAvailability(
        immediate: DeliveryImmediateOption(
          enabled: _immediateEnabled,
          surcharge: _immediateSurcharge,
        ),
        regularEnabled: _regularEnabled,
        scheduledEnabled: _scheduledEnabled,
      ),
      serviceArea: DeliveryServiceArea(
        baseLocation: _baseLocation,
        coverageCities: _coverageCities,
      ),
      pricing: _pricing,
      rules: CourierRules(
        structuredRules: _rules.where((r) => r.enabled).toList(),
        customRules: _customRules,
      ),
      businessPackages: _packages.where((p) => p.enabled).toList(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsetsDirectional.symmetric(vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [_kDarkBase, _kDarkBaseMid, _kDarkBaseDeep],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Stack(
        children: [
          // Ambient orbs — positioned decorative gradients.
          PositionedDirectional(
            top: 40,
            end: -30,
            child: _ambientOrb(_kGoldMid.withValues(alpha: 0.15), 180),
          ),
          PositionedDirectional(
            top: 240,
            start: -40,
            child: _ambientOrb(_kIndigoMedium.withValues(alpha: 0.10), 200),
          ),
          PositionedDirectional(
            bottom: 120,
            end: -40,
            child: _ambientOrb(_kStatusGreen.withValues(alpha: 0.08), 180),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _goldSeparator('↓ הבלוק החדש — מתווסף רק אחרי "משלוחים" ↓'),
                const SizedBox(height: 18),
                _heroStoryMode(),
                const SizedBox(height: 22),
                _sectionDocuments(),
                const SizedBox(height: 18),
                _sectionVehicles(),
                const SizedBox(height: 18),
                _sectionDeliveryTypes(),
                const SizedBox(height: 18),
                _sectionCustomerTypes(),
                const SizedBox(height: 18),
                _sectionAvailability(),
                const SizedBox(height: 18),
                _sectionServiceArea(),
                const SizedBox(height: 18),
                _sectionPricing(),
                const SizedBox(height: 18),
                _sectionRules(),
                const SizedBox(height: 18),
                _sectionBusinessPackages(),
                const SizedBox(height: 16),
                _goldSeparator('↑ סוף הבלוק החדש ↑'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ambientOrb(Color color, double size) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
            ),
          ),
        ),
      );

  Widget _goldSeparator(String text) => Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [
                  Color(0x00F59E0B),
                  _kGoldMid,
                  Color(0x00F59E0B),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 10),
            child: Text(
              text,
              style: const TextStyle(
                color: _kGoldLight,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [
                  Color(0x00F59E0B),
                  _kGoldMid,
                  Color(0x00F59E0B),
                ]),
              ),
            ),
          ),
        ],
      );

  // ── Section 0: Hero Story Mode ──
  Widget _heroStoryMode() {
    return Column(
      children: [
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [_kGoldDark, _kGoldMid, _kGoldLight],
            ),
            boxShadow: [
              BoxShadow(
                color: _kGoldMid.withValues(alpha: 0.4),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.local_shipping_rounded,
              color: Colors.white, size: 38),
        ),
        const SizedBox(height: 14),
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, _kGoldPale],
          ).createShader(r),
          child: Text(
            _t('hero.title', 'הקריירה שלך'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _t('hero.subtitle', 'כל מה שצריך כדי להרוויח יותר'),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            _statusBadge('● פעיל · מקבל הזמנות', _kStatusGreenLight),
            _statusBadge('🎯 Top 5 · ת"א', _kStatusBlue),
          ],
        ),
      ],
    );
  }

  Widget _statusBadge(String text, Color color) => Container(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(text,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            )),
      );

  // ── Section 1: Documents (required!) ──
  Widget _sectionDocuments() {
    return _glassCard(
      borderColor: _kStatusRed.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(
            icon: '📄',
            title: _t('documents.title', 'מסמכים ורישיונות'),
            subtitle: _t('documents.subtitle',
                'חובה — אימות נדרש לאישור הפרופיל'),
            color: _kStatusRedLight,
          ),
          const SizedBox(height: 12),
          for (final d in _documents) _documentRow(d),
        ],
      ),
    );
  }

  Widget _documentRow(DeliveryDocument d) {
    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: d.verified
                    ? const [_kStatusGreen, Color(0xFF15803D)]
                    : [Colors.white.withValues(alpha: 0.1), Colors.white.withValues(alpha: 0.05)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              d.verified ? Icons.verified_rounded : Icons.description_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.nameHe,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    )),
                Text(
                  d.verified ? '✓ מאושר' : 'ממתין להעלאה',
                  style: TextStyle(
                    color: d.verified
                        ? _kStatusGreenLight
                        : Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: d.verified,
            activeColor: _kStatusGreen,
            onChanged: (v) {
              HapticFeedback.lightImpact();
              setState(() {
                final idx = _documents.indexWhere((x) => x.id == d.id);
                _documents[idx] = d.copyWith(
                  verified: v,
                  verifiedAt:
                      v ? DateTime.now().toIso8601String() : null,
                );
              });
              _emit();
            },
          ),
        ],
      ),
    );
  }

  // ── Section 2: Fleet ──
  Widget _sectionVehicles() {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(
            icon: '🛵',
            title: _t('fleet.title', 'הצי שלי'),
            subtitle: _t('fleet.subtitle', 'לקוחות יראו את האפשרויות'),
          ),
          const SizedBox(height: 12),
          for (final v in _vehicles) _vehicleRow(v),
        ],
      ),
    );
  }

  Widget _vehicleRow(DeliveryVehicle v) {
    final def = findDeliveryVehicle(v.type);
    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: v.enabled
            ? LinearGradient(colors: [
                _kGoldDark.withValues(alpha: 0.15),
                _kGoldMid.withValues(alpha: 0.05),
              ])
            : null,
        color: v.enabled ? null : Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: v.enabled
              ? _kGoldMid.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_kGoldDark, _kGoldMid]),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child:
                Icon(def?.icon ?? Icons.directions_car_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.nameHe,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    )),
                Text(
                  '📋 משקל מקס׳: ${v.maxWeightKg} ק"ג',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: v.enabled,
            activeColor: _kGoldMid,
            onChanged: (on) {
              HapticFeedback.lightImpact();
              setState(() {
                final idx = _vehicles.indexWhere((x) => x.id == v.id);
                _vehicles[idx] = v.copyWith(enabled: on);
              });
              _emit();
            },
          ),
        ],
      ),
    );
  }

  // ── Section 3: Delivery Types ──
  Widget _sectionDeliveryTypes() {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(
            icon: '📦',
            title: _t('deliveryTypes.title', 'סוגי משלוחים'),
            subtitle: _t('deliveryTypes.subtitle', 'סמן את מה שאתה מבצע'),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kDeliveryTypes.map((d) {
              final selected = _selectedTypes.contains(d.id);
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    if (selected) {
                      _selectedTypes.remove(d.id);
                    } else {
                      _selectedTypes.add(d.id);
                    }
                  });
                  _emit();
                },
                child: Container(
                  width: (MediaQuery.of(context).size.width - 36 - 36) / 2 - 4,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                  decoration: BoxDecoration(
                    gradient: selected
                        ? const LinearGradient(colors: [_kStatusGreen, Color(0xFF15803D)])
                        : null,
                    color: selected ? null : Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? _kStatusGreenLight
                          : d.isOptional
                              ? _kGoldMid.withValues(alpha: 0.35)
                              : Colors.white.withValues(alpha: 0.06),
                      width: d.isOptional && !selected ? 1.2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(d.icon, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.shortHe,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                )),
                            Text(d.weightSpec,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 10,
                                )),
                          ],
                        ),
                      ),
                      if (selected)
                        const Icon(Icons.check_circle_rounded,
                            color: Colors.white, size: 16),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Section 4: Customer Types ──
  Widget _sectionCustomerTypes() {
    const options = [
      {'id': 'private', 'nameHe': 'פרטיים', 'icon': '👤'},
      {'id': 'business', 'nameHe': 'עסקים', 'icon': '🏢'},
      {'id': 'stores', 'nameHe': 'חנויות', 'icon': '🛍'},
      {'id': 'restaurants', 'nameHe': 'מסעדות', 'icon': '🍽'},
    ];
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(
            icon: '👥',
            title: _t('customerTypes.title', 'סוגי לקוחות'),
            subtitle: _t('customerTypes.subtitle', 'עם מי אתה עובד'),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((o) {
              final id = o['id']!;
              final selected = _selectedCustomers.contains(id);
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    if (selected) {
                      _selectedCustomers.remove(id);
                    } else {
                      _selectedCustomers.add(id);
                    }
                  });
                  _emit();
                },
                child: Container(
                  width: (MediaQuery.of(context).size.width - 36 - 36) / 2 - 4,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: selected
                        ? const LinearGradient(colors: [Colors.white, Color(0xFFE5E7EB)])
                        : null,
                    color: selected ? null : Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(o['icon']!, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text(
                        o['nameHe']!,
                        style: TextStyle(
                          color: selected ? _kDarkBase : Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Section 5: Availability ──
  Widget _sectionAvailability() {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(
            icon: '⏰',
            title: _t('availability.title', 'זמינות'),
            subtitle: _t('availability.subtitle', '3 סוגי הזמנות'),
          ),
          const SizedBox(height: 12),
          _availabilityRow(
            titleHe: '⚡ משלוח מיידי',
            descHe: "תוך 30 דקות · תוספת מחיר",
            value: _immediateEnabled,
            onChanged: (v) {
              setState(() => _immediateEnabled = v);
              _emit();
            },
            tint: _kStatusRed,
            trailing: SizedBox(
              width: 90,
              child: TextFormField(
                initialValue: _immediateSurcharge.toString(),
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  prefixText: '₪ ',
                  prefixStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6), fontSize: 11),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.3),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08)),
                  ),
                ),
                onChanged: (s) {
                  final n = int.tryParse(s);
                  if (n != null) {
                    _immediateSurcharge = n;
                    _emit();
                  }
                },
              ),
            ),
          ),
          _availabilityRow(
            titleHe: '⏰ משלוח רגיל',
            descHe: 'תוך שעה · סטנדרטי',
            value: _regularEnabled,
            onChanged: (v) {
              setState(() => _regularEnabled = v);
              _emit();
            },
            tint: Colors.white.withValues(alpha: 0.3),
          ),
          _availabilityRow(
            titleHe: '🗓️ הזמנה מראש',
            descHe: 'פי 2.4 הזמנות מעסקים',
            value: _scheduledEnabled,
            onChanged: (v) {
              setState(() => _scheduledEnabled = v);
              _emit();
            },
            tint: _kIndigoMedium,
            badge: '⭐ ייחודי!',
          ),
        ],
      ),
    );
  }

  Widget _availabilityRow({
    required String titleHe,
    required String descHe,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color tint,
    Widget? trailing,
    String? badge,
  }) {
    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tint.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(titleHe,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          )),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [_kIndigoMedium, _kIndigoDark]),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(badge,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            )),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(descHe,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11,
                    )),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
          ],
          const SizedBox(width: 4),
          Switch(
              value: value, activeColor: _kGoldMid, onChanged: (v) {
            HapticFeedback.lightImpact();
            onChanged(v);
          }),
        ],
      ),
    );
  }

  // ── Section 6: Service Area ──
  Widget _sectionServiceArea() {
    const allCities = [
      'תל אביב', 'רמת גן', 'גבעתיים', 'הרצליה',
      'פתח תקווה', 'חולון', 'בת ים', 'ראשון לציון',
    ];
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(
              icon: '📍',
              title: _t('serviceArea.title', 'אזורי שירות'),
              subtitle: _t('serviceArea.subtitle', 'היכן אתה פעיל')),
          const SizedBox(height: 12),
          _labeledField(
            label: 'בסיס פעילות',
            child: TextFormField(
              controller: _baseLocationCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: _darkInputDecoration('לדוגמה: תל אביב מרכז'),
              onChanged: (s) {
                _baseLocation = s;
                _emit();
              },
            ),
          ),
          const SizedBox(height: 12),
          Text('אזורי כיסוי',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: allCities.map((city) {
              final selected = _coverageCities.contains(city);
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    if (selected) {
                      _coverageCities.remove(city);
                    } else {
                      _coverageCities.add(city);
                    }
                  });
                  _emit();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: selected
                        ? const LinearGradient(colors: [_kGoldDark, _kGoldMid])
                        : null,
                    color: selected ? null : Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: selected
                            ? _kGoldLight
                            : Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Text(city,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      )),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Section 7: Pricing ──
  Widget _sectionPricing() {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(
              icon: '💰',
              title: _t('pricing.title', 'מחירון לפי משקל'),
              subtitle: _t('pricing.subtitle', 'שקיפות מלאה ללקוח'),
              trailing: _miniBadge('שקיפות', _kStatusGreen)),
          const SizedBox(height: 12),
          _priceRow('מסמכים (עד 1ק"ג)', _pricing.documents, (v) {
            setState(() => _pricing = DeliveryPricing(
                  documents: v,
                  smallPackage: _pricing.smallPackage,
                  mediumPackage: _pricing.mediumPackage,
                  largePackage: _pricing.largePackage,
                  flowers: _pricing.flowers,
                  cakes: _pricing.cakes,
                  perKmAfter5: _pricing.perKmAfter5,
                ));
            _emit();
          }),
          _priceRow('חבילה קטנה (עד 5ק"ג)', _pricing.smallPackage, (v) {
            setState(() => _pricing = DeliveryPricing(
                  documents: _pricing.documents,
                  smallPackage: v,
                  mediumPackage: _pricing.mediumPackage,
                  largePackage: _pricing.largePackage,
                  flowers: _pricing.flowers,
                  cakes: _pricing.cakes,
                  perKmAfter5: _pricing.perKmAfter5,
                ));
            _emit();
          }),
          _priceRow('בינונית (5-15ק"ג)', _pricing.mediumPackage, (v) {
            setState(() => _pricing = DeliveryPricing(
                  documents: _pricing.documents,
                  smallPackage: _pricing.smallPackage,
                  mediumPackage: v,
                  largePackage: _pricing.largePackage,
                  flowers: _pricing.flowers,
                  cakes: _pricing.cakes,
                  perKmAfter5: _pricing.perKmAfter5,
                ));
            _emit();
          }),
          _priceRow('גדולה (15-30ק"ג)', _pricing.largePackage, (v) {
            setState(() => _pricing = DeliveryPricing(
                  documents: _pricing.documents,
                  smallPackage: _pricing.smallPackage,
                  mediumPackage: _pricing.mediumPackage,
                  largePackage: v,
                  flowers: _pricing.flowers,
                  cakes: _pricing.cakes,
                  perKmAfter5: _pricing.perKmAfter5,
                ));
            _emit();
          }),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Text('תוספת לכל ק"מ אחרי 5',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    )),
                const Spacer(),
                SizedBox(
                  width: 80,
                  child: TextFormField(
                    initialValue: _pricing.perKmAfter5.toString(),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: _darkInputDecoration('₪/ק"מ'),
                    onChanged: (s) {
                      final d = double.tryParse(s);
                      if (d != null) {
                        setState(() => _pricing = DeliveryPricing(
                              documents: _pricing.documents,
                              smallPackage: _pricing.smallPackage,
                              mediumPackage: _pricing.mediumPackage,
                              largePackage: _pricing.largePackage,
                              flowers: _pricing.flowers,
                              cakes: _pricing.cakes,
                              perKmAfter5: d,
                            ));
                        _emit();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceRow(String label, int value, ValueChanged<int> onChanged) {
    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                )),
          ),
          SizedBox(
            width: 80,
            child: TextFormField(
              initialValue: value.toString(),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              decoration: _darkInputDecoration('₪'),
              onChanged: (s) {
                final n = int.tryParse(s);
                if (n != null) onChanged(n);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 8: Rules (Purple!) ──
  Widget _sectionRules() {
    return _glassCard(
      borderColor: _kPurpleBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(
            icon: '📋',
            title: _t('rules.title', 'הכללים שלך'),
            subtitle: _t('rules.subtitle', 'הלקוחות יראו לפני ההזמנה'),
            color: _kIndigoMedium,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _kIndigoMedium.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: _kIndigoMedium.withValues(alpha: 0.25)),
            ),
            child: Text(
              '💡 פחות אי הבנות = יותר ★★★★★',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final r in _rules) _ruleRow(r),
          const SizedBox(height: 10),
          Text('הוראות אישיות נוספות',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(height: 6),
          TextField(
            controller: _customRulesCtrl,
            maxLength: _kMaxCustomRulesChars,
            maxLines: 3,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: _darkInputDecoration(
                'לדוגמה: חבילות שביר — חובה לסמן, אגיע עם בועות וניילון מגן...'),
            onChanged: (s) {
              _customRules = s;
              _emit();
            },
          ),
        ],
      ),
    );
  }

  Widget _ruleRow(StructuredCourierRule r) {
    final color = _ruleColor(r.color);
    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: r.enabled
            ? color.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: r.enabled
              ? color.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          Text(r.icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.titleHe,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    )),
                Text(r.descHe,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11,
                    )),
              ],
            ),
          ),
          Switch(
            value: r.enabled,
            activeColor: color,
            onChanged: (v) {
              HapticFeedback.lightImpact();
              setState(() {
                final idx = _rules.indexWhere((x) => x.id == r.id);
                _rules[idx] = StructuredCourierRule(
                  id: r.id,
                  type: r.type,
                  icon: r.icon,
                  titleHe: r.titleHe,
                  descHe: r.descHe,
                  enabled: v,
                  color: r.color,
                );
              });
              _emit();
            },
          ),
        ],
      ),
    );
  }

  Color _ruleColor(String name) {
    switch (name) {
      case 'red':
        return _kStatusRed;
      case 'amber':
        return _kGoldMid;
      case 'blue':
        return _kStatusBlue;
    }
    return Colors.white;
  }

  // ── Section 9: Business Packages ──
  Widget _sectionBusinessPackages() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          const Color(0xFF1E3A8A).withValues(alpha: 0.6),
          const Color(0xFF1E40AF).withValues(alpha: 0.3),
        ]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kStatusBlue.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(
              icon: '💼',
              title: _t('businessPackages.title', 'חבילות לעסקים'),
              subtitle: _t('businessPackages.subtitle',
                  '💰 שליחים עם חבילות = פי 2.5 הכנסה')),
          const SizedBox(height: 12),
          for (final p in _packages) _packageRow(p),
        ],
      ),
    );
  }

  Widget _packageRow(BusinessPackage p) {
    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.nameHe,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    )),
                Text('${p.deliveriesPerMonth} משלוחים · ₪${p.monthlyPrice}/חודש',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: p.enabled,
            activeColor: _kGoldMid,
            onChanged: (v) {
              HapticFeedback.lightImpact();
              setState(() {
                final idx = _packages.indexWhere((x) => x.id == p.id);
                _packages[idx] = BusinessPackage(
                  id: p.id,
                  nameHe: p.nameHe,
                  deliveriesPerMonth: p.deliveriesPerMonth,
                  monthlyPrice: p.monthlyPrice,
                  enabled: v,
                  activeCustomers: p.activeCustomers,
                );
              });
              _emit();
            },
          ),
        ],
      ),
    );
  }

  // ── Shared helpers ──
  Widget _glassCard({required Widget child, Color? borderColor}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor ?? Colors.white.withValues(alpha: 0.08),
          width: borderColor != null ? 1.5 : 1,
        ),
      ),
      child: child,
    );
  }

  Widget _sectionHeader({
    required String icon,
    required String title,
    required String subtitle,
    Color? color,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              (color ?? _kGoldMid).withValues(alpha: 0.4),
              (color ?? _kGoldDark).withValues(alpha: 0.15),
            ]),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(icon, style: const TextStyle(fontSize: 18)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  )),
              Text(subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 11,
                  )),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _miniBadge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(text,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            )),
      );

  Widget _labeledField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            )),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  InputDecoration _darkInputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.3),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              BorderSide(color: _kGoldMid.withValues(alpha: 0.5)),
        ),
        counterText: '',
      );
}
