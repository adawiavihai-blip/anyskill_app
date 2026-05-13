// Cleaning CSM — provider-side "המקצועיות שלך" settings block.
// Dark premium with cyan/teal accents + 3 ambient orbs.
// Follows the same file pattern as delivery/pest control.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/cleaning_addons_catalog.dart';
import '../../constants/cleaning_customer_types.dart';
import '../../constants/cleaning_default_checklists.dart';
import '../../constants/cleaning_types_catalog.dart';
import '../../models/cleaning_profile.dart';
import '../../services/cleaning_booking_service.dart';
import '../../services/csm_text_override_service.dart';

// Dark premium palette — scoped to this widget only.
const _kDarkBase = Color(0xFF0A0E1A);
const _kDarkBaseMid = Color(0xFF0F1A2E);
const _kDarkBaseDeep = Color(0xFF0F1420);
const _kCyanDark = Color(0xFF0891B2);
const _kCyanMid = Color(0xFF06B6D4);
const _kCyanLight = Color(0xFF67E8F9);
const _kStatusGreen = Color(0xFF16A34A);
const _kStatusGreenLight = Color(0xFF4ADE80);
const _kStatusRed = Color(0xFFDC2626);
const _kStatusRedLight = Color(0xFFFCA5A5);
const _kPurpleMedium = Color(0xFFA855F7);
const _kAmberMedium = Color(0xFFF59E0B);

/// Provider-side settings block. Only rendered when sub-category == "נקיון".
class CleaningSettingsBlock extends StatefulWidget {
  final CleaningProfile initialProfile;
  final ValueChanged<CleaningProfile> onChanged;
  final String? providerId;

  const CleaningSettingsBlock({
    super.key,
    required this.initialProfile,
    required this.onChanged,
    this.providerId,
  });

  @override
  State<CleaningSettingsBlock> createState() => _CleaningSettingsBlockState();
}

class _CleaningSettingsBlockState extends State<CleaningSettingsBlock> {
  late CleaningVerifications _verifications;
  late List<String> _cleaningTypes;
  late List<String> _customerTypes;
  late CleaningEcoMode _ecoMode;
  late List<CleaningChecklistCategory> _checklist;
  late CleaningPricing _pricing;
  late CleaningRecurringDiscounts _discounts;
  late CleaningServiceArea _serviceArea;
  late List<CleaningBusinessPackage> _packages;

  final Map<String, TextEditingController> _taskCtrls = {};
  final TextEditingController _insuranceCtrl = TextEditingController();
  final Map<String, TextEditingController> _priceCtrls = {};
  final Map<String, TextEditingController> _addOnCtrls = {};

  // ── CSM text override wiring ──
  static const _csmId = 'cleaning';
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
    _verifications = p.verifications;
    _cleaningTypes = List.of(p.cleaningTypes);
    _customerTypes = List.of(p.customerTypes);
    _ecoMode = p.ecoMode;
    _checklist = p.baseChecklist.isEmpty
        ? defaultCleaningChecklist()
        : List.of(p.baseChecklist);
    _pricing = p.pricing;
    _discounts = p.recurringDiscounts;
    _serviceArea = p.serviceArea.cities.isEmpty
        ? p.serviceArea.copyWith(cities: const ['תל אביב', 'רמת גן', 'גבעתיים'])
        : p.serviceArea;
    _packages =
        p.businessPackages.isEmpty ? defaultBusinessPackages() : List.of(p.businessPackages);

    _insuranceCtrl.text = _verifications.insuranceAmount.toString();
    for (final cat in _checklist) {
      for (final t in cat.tasks) {
        _taskCtrls[t.id] = TextEditingController(text: t.nameHe);
      }
    }
    _pricing.regularHome.forEach((k, v) {
      _priceCtrls[k] = TextEditingController(text: v.toString());
    });
    _pricing.addOns.forEach((k, v) {
      _addOnCtrls[k] = TextEditingController(text: v.toString());
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emit();
    });
  }

  @override
  void dispose() {
    _textOverrides.removeListener(_onTextOverridesChanged);
    _insuranceCtrl.dispose();
    for (final c in _taskCtrls.values) {
      c.dispose();
    }
    for (final c in _priceCtrls.values) {
      c.dispose();
    }
    for (final c in _addOnCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit() {
    widget.onChanged(CleaningProfile(
      verifications: _verifications,
      cleaningTypes: _cleaningTypes,
      customerTypes: _customerTypes,
      ecoMode: _ecoMode,
      baseChecklist: _checklist,
      pricing: _pricing,
      recurringDiscounts: _discounts,
      qualityGuarantee: widget.initialProfile.qualityGuarantee,
      serviceArea: _serviceArea,
      businessPackages: _packages.where((p) => p.enabled).toList(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsetsDirectional.only(top: 6, bottom: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kDarkBase, _kDarkBaseMid, _kDarkBaseDeep],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _kCyanMid.withValues(alpha: 0.25), width: 1),
      ),
      child: Stack(
        children: [
          // Ambient orbs.
          Positioned(
              top: -60,
              right: -40,
              child: _orb(_kCyanMid.withValues(alpha: 0.22), 180)),
          Positioned(
              top: 300,
              left: -60,
              child:
                  _orb(_kStatusGreen.withValues(alpha: 0.15), 160)),
          Positioned(
              bottom: -40,
              right: -30,
              child:
                  _orb(_kPurpleMedium.withValues(alpha: 0.12), 170)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _separator(
                  '↓ הבלוק החדש · הגדרות נקיון ↓'),
              const SizedBox(height: 14),
              _heroSection(),
              const SizedBox(height: 16),
              _section(
                title: _t('verifications.title', 'אימותים'),
                subtitle: _t('verifications.subtitle',
                    'חובה - אימות נדרש לאישור הפרופיל'),
                borderColor: _kStatusRed.withValues(alpha: 0.4),
                icon: '🔴',
                child: _verificationsSection(),
              ),
              const SizedBox(height: 16),
              _section(
                title: _t('cleaningTypes.title', 'סוגי נקיון שאני מבצעת'),
                subtitle: _t('cleaningTypes.subtitle',
                    'בחרי את הסוגים - רק הם יוצגו ללקוחות'),
                icon: '🧼',
                child: _cleaningTypesGrid(),
              ),
              const SizedBox(height: 16),
              _section(
                title: _t('customerTypes.title', 'סוגי לקוחות'),
                subtitle: _t('customerTypes.subtitle', 'מי רלוונטי עבורך?'),
                icon: '👥',
                child: _customerTypesChips(),
              ),
              const SizedBox(height: 16),
              _section(
                title: _t('eco.title', 'Eco-Friendly Mode'),
                subtitle:
                    _t('eco.subtitle', '⭐ 78% מהלקוחות בוחרים בעדיפות'),
                borderColor: _kStatusGreen.withValues(alpha: 0.4),
                icon: '🌱',
                child: _ecoSection(),
              ),
              const SizedBox(height: 16),
              _section(
                title: _t('checklist.title', 'Checklist בסיסי שלך'),
                subtitle: _t('checklist.subtitle',
                    '⭐ הלקוחות יוכלו להוסיף/להוריד לעצמם לפי הצורך'),
                borderColor: _kPurpleMedium.withValues(alpha: 0.4),
                icon: '📋',
                child: _checklistBuilder(),
              ),
              const SizedBox(height: 16),
              _section(
                title: _t('pricing.title', 'מחירון לפי גודל הבית'),
                subtitle:
                    _t('pricing.subtitle', 'המערכת תחשב אוטומטית ללקוח'),
                icon: '💰',
                child: _pricingSection(),
              ),
              const SizedBox(height: 16),
              _section(
                title: _t('discounts.title', 'מנוי קבוע - הנחות'),
                subtitle:
                    _t('discounts.subtitle', '⭐ הכנסה צפויה לאורך זמן'),
                borderColor: _kPurpleMedium.withValues(alpha: 0.4),
                icon: '🔄',
                child: _discountsSection(),
              ),
              const SizedBox(height: 16),
              _section(
                title: _t('serviceArea.title', 'אזורי שירות וזמינות'),
                subtitle: _t('serviceArea.subtitle',
                    'היכן ובאילו שעות את עובדת'),
                icon: '📍',
                child: _serviceAreaSection(),
              ),
              const SizedBox(height: 16),
              _section(
                title: _t('businessPackages.title', 'חבילות לעסקים'),
                subtitle: _t('businessPackages.subtitle',
                    'מנוי חודשי · משרדים, חנויות · הכנסה קבועה'),
                icon: '💼',
                child: _businessPackagesSection(),
              ),
              const SizedBox(height: 18),
              _separator('↑ סוף הבלוק החדש ↑'),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────── helpers ───────────

  Widget _orb(Color color, double size) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, Colors.transparent],
            ),
          ),
        ),
      );

  Widget _separator(String text) => Row(
        children: [
          Expanded(
              child: Container(
                  height: 1, color: _kCyanMid.withValues(alpha: 0.35))),
          const SizedBox(width: 10),
          Text(text,
              style: TextStyle(
                  color: _kCyanLight.withValues(alpha: 0.8),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3)),
          const SizedBox(width: 10),
          Expanded(
              child: Container(
                  height: 1, color: _kCyanMid.withValues(alpha: 0.35))),
        ],
      );

  Widget _heroSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            children: [
              ShaderMask(
                shaderCallback: (r) => const LinearGradient(
                  colors: [Colors.white, _kCyanLight],
                ).createShader(r),
                child: Text(
                  _t('hero.title', 'המקצועיות שלך'),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _t('hero.subtitle', 'הגדרות שיביאו לך לקוחות בכל החודש'),
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500),
              ),
              if (widget.providerId != null) ...[
                const SizedBox(height: 14),
                StreamBuilder<int>(
                  stream: CleaningBookingService.streamRecurringCustomersCount(
                      widget.providerId!),
                  builder: (ctx, snap) {
                    final count = snap.data ?? 0;
                    final revenue = count * 230; // avg 4x/month × ~₪230
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          _kPurpleMedium.withValues(alpha: 0.25),
                          _kPurpleMedium.withValues(alpha: 0.08),
                        ]),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: _kPurpleMedium.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Text('💎', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$count לקוחות חוזרים פעילים',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text('הכנסה קבועה: ₪$revenue/חודש',
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.7),
                                        fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _section({
    required String title,
    required String subtitle,
    required String icon,
    Color? borderColor,
    required Widget child,
  }) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 11.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  // ─────────── Section: Verifications ───────────
  Widget _verificationsSection() {
    return Column(
      children: [
        _verifyRow(
            icon: '🆔',
            label: 'תעודת זהות',
            sub: 'מאומתת ב-OCR',
            value: _verifications.idVerified,
            onToggle: (v) {
              setState(() {
                _verifications = _verifications.copyWith(
                    idVerified: v,
                    idVerifiedAt: v ? DateTime.now() : null);
                _emit();
              });
            }),
        const SizedBox(height: 8),
        _verifyRow(
            icon: '📋',
            label: 'בדיקת רקע',
            sub: 'ללא רישום פלילי',
            value: _verifications.backgroundChecked,
            onToggle: (v) {
              setState(() {
                _verifications = _verifications.copyWith(
                    backgroundChecked: v,
                    backgroundCheckedAt: v ? DateTime.now() : null);
                _emit();
              });
            }),
        const SizedBox(height: 8),
        _verifyRow(
            icon: '📞',
            label: '${_verifications.referencesCount} ממליצים מאומתים',
            sub: 'דרושים לפחות 3',
            value: _verifications.referencesVerified,
            trailing: _stepperWidget(
              value: _verifications.referencesCount,
              min: 0,
              max: 20,
              onChanged: (v) => setState(() {
                _verifications = _verifications.copyWith(referencesCount: v);
                _emit();
              }),
            ),
            onToggle: (v) {
              setState(() {
                _verifications =
                    _verifications.copyWith(referencesVerified: v);
                _emit();
              });
            }),
        const SizedBox(height: 10),
        Row(
          children: [
            const Text('🛡️', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            const Expanded(
                child: Text('ביטוח אחריות (₪)',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600))),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _insuranceCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: _fieldDec(),
                onChanged: (v) {
                  final n = int.tryParse(v) ?? 10000;
                  _verifications = _verifications.copyWith(insuranceAmount: n);
                  _emit();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _verifyRow({
    required String icon,
    required String label,
    required String sub,
    required bool value,
    required ValueChanged<bool> onToggle,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value
              ? _kStatusGreen.withValues(alpha: 0.4)
              : _kStatusRed.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              Text(sub,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
            ],
          )),
          if (trailing != null) ...[trailing, const SizedBox(width: 8)],
          Switch(
            value: value,
            activeColor: _kStatusGreenLight,
            onChanged: onToggle,
          ),
        ],
      ),
    );
  }

  Widget _stepperWidget({
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            IconButton(
              iconSize: 14,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: value > min ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove, color: Colors.white),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('$value',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
            IconButton(
              iconSize: 14,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: value < max ? () => onChanged(value + 1) : null,
              icon: const Icon(Icons.add, color: Colors.white),
            ),
          ],
        ),
      );

  InputDecoration _fieldDec() => InputDecoration(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              BorderSide(color: _kCyanMid.withValues(alpha: 0.5), width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      );

  // ─────────── Section: Cleaning Types ───────────
  Widget _cleaningTypesGrid() {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.95,
      children: kCleaningTypes.map((t) {
        final active = _cleaningTypes.contains(t.id);
        return GestureDetector(
          onTap: () => setState(() {
            if (active) {
              _cleaningTypes.remove(t.id);
            } else {
              _cleaningTypes.add(t.id);
            }
            _emit();
          }),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: active
                  ? LinearGradient(colors: [
                      _kStatusGreen.withValues(alpha: 0.4),
                      _kStatusGreen.withValues(alpha: 0.15),
                    ])
                  : null,
              color: active ? null : Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active
                    ? _kStatusGreenLight
                    : _kCyanMid.withValues(alpha: 0.3),
                width: active ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(t.icon, style: const TextStyle(fontSize: 22)),
                const SizedBox(height: 4),
                Text(t.nameHe,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
                Text(t.descriptionHe,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 9)),
                if (active)
                  const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(Icons.check_circle,
                          color: _kStatusGreenLight, size: 14)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─────────── Section: Customer Types ───────────
  Widget _customerTypesChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kCleaningCustomerTypes.map((c) {
        final active = _customerTypes.contains(c.id);
        return GestureDetector(
          onTap: () => setState(() {
            if (active) {
              _customerTypes.remove(c.id);
            } else {
              _customerTypes.add(c.id);
            }
            _emit();
          }),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: active
                  ? _kCyanMid.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: active
                      ? _kCyanLight
                      : Colors.white.withValues(alpha: 0.15)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(c.icon, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(c.nameHe,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─────────── Section: Eco ───────────
  Widget _ecoSection() {
    return Column(
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('אני מציעה חומרים אקולוגיים',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  SizedBox(height: 2),
                  Text('מאושר EcoCert · בטוח לילדים ובעלי-חיים',
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
            Switch(
              value: _ecoMode.enabled,
              activeColor: _kStatusGreenLight,
              onChanged: (v) => setState(() {
                _ecoMode = CleaningEcoMode(
                    enabled: v,
                    surcharge: _ecoMode.surcharge,
                    certified: 'EcoCert');
                _emit();
              }),
            ),
          ],
        ),
        if (_ecoMode.enabled) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('תוספת לביקור:',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue: _ecoMode.surcharge.toString(),
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: _fieldDec().copyWith(suffixText: '₪'),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (v) {
                    _ecoMode = CleaningEcoMode(
                        enabled: _ecoMode.enabled,
                        surcharge: int.tryParse(v) ?? 25,
                        certified: 'EcoCert');
                    _emit();
                  },
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ─────────── Section: Checklist Builder ───────────
  Widget _checklistBuilder() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _kPurpleMedium.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: _kPurpleMedium.withValues(alpha: 0.3), width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('💡', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'איך זה עובד: את מגדירה רשימה בסיסית. הלקוח יוכל לסמן או לבטל לפי הצורך.',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ..._checklist.asMap().entries.map((entry) {
          final catIdx = entry.key;
          final cat = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(cat.categoryIcon,
                        style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          '${cat.categoryNameHe} · ${cat.tasks.length} משימות',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => _addTaskTo(catIdx),
                      icon: const Icon(Icons.add_circle_outline,
                          color: _kCyanLight),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ...cat.tasks.asMap().entries.map((te) {
                  final task = te.value;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.drag_handle,
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.3)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _taskCtrls[task.id],
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                            decoration: _fieldDec(),
                            onChanged: (v) {
                              final updatedTasks = List<CleaningTask>.of(
                                  cat.tasks);
                              updatedTasks[te.key] =
                                  task.copyWith(nameHe: v);
                              _checklist[catIdx] =
                                  cat.copyWith(tasks: updatedTasks);
                              _emit();
                            },
                          ),
                        ),
                        if (task.withPhoto)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Text('📷',
                                style: TextStyle(fontSize: 13)),
                          ),
                        if (task.addOnAmount != null)
                          Container(
                            margin: const EdgeInsetsDirectional.only(start: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _kAmberMedium.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('+₪${task.addOnAmount}',
                                style: const TextStyle(
                                    color: _kAmberMedium,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700)),
                          ),
                        IconButton(
                          iconSize: 14,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 24, minHeight: 24),
                          onPressed: () =>
                              _removeTask(catIdx, te.key, task.id),
                          icon: const Icon(Icons.close,
                              color: _kStatusRedLight),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        }),
        TextButton.icon(
          onPressed: _addCategory,
          icon: const Icon(Icons.add, color: _kCyanLight),
          label: const Text('+ הוסף קטגוריה',
              style: TextStyle(color: _kCyanLight, fontSize: 12)),
        ),
      ],
    );
  }

  void _addTaskTo(int catIdx) {
    final cat = _checklist[catIdx];
    final newId =
        '${cat.categoryId}_${DateTime.now().millisecondsSinceEpoch}';
    final newTask = CleaningTask(id: newId, nameHe: 'משימה חדשה');
    _taskCtrls[newId] = TextEditingController(text: newTask.nameHe);
    setState(() {
      _checklist[catIdx] =
          cat.copyWith(tasks: [...cat.tasks, newTask]);
      _emit();
    });
  }

  void _removeTask(int catIdx, int taskIdx, String taskId) {
    final cat = _checklist[catIdx];
    final updated = List<CleaningTask>.of(cat.tasks)..removeAt(taskIdx);
    _taskCtrls.remove(taskId)?.dispose();
    setState(() {
      _checklist[catIdx] = cat.copyWith(tasks: updated);
      _emit();
    });
  }

  void _addCategory() async {
    final ctrl = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kDarkBaseMid,
        title: const Text('קטגוריה חדשה',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
              hintText: 'למשל: מרפסת',
              hintStyle: TextStyle(color: Colors.white38)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('הוסף')),
        ],
      ),
    );
    if (added == true && ctrl.text.trim().isNotEmpty) {
      final id = 'cat_${DateTime.now().millisecondsSinceEpoch}';
      setState(() {
        _checklist.add(CleaningChecklistCategory(
          categoryId: id,
          categoryNameHe: ctrl.text.trim(),
          categoryIcon: '🧹',
          tasks: [],
        ));
        _emit();
      });
    }
    ctrl.dispose();
  }

  // ─────────── Section: Pricing ───────────
  Widget _pricingSection() {
    final tiers = const [
      ('upTo60sqm', '🏠 עד 60 מ"ר', 'דירת 2'),
      ('60to100sqm', '🏡 60-100 מ"ר', 'דירת 3-4 · הכי נפוץ'),
      ('100to150sqm', '🏘️ 100-150 מ"ר', '5/קוטג\''),
      ('over150sqm', '🏰 מעל 150 מ"ר', 'פנטהאוז'),
    ];
    return Column(
      children: [
        ...tiers.map((t) {
          final ctrl = _priceCtrls[t.$1] ??
              (_priceCtrls[t.$1] = TextEditingController(
                  text: (_pricing.regularHome[t.$1] ?? 240).toString()));
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.$2,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                      Text(t.$3,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 10.5)),
                    ],
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style:
                        const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: _fieldDec().copyWith(suffixText: '₪'),
                    onChanged: (v) {
                      final n = int.tryParse(v) ?? 0;
                      final newMap =
                          Map<String, int>.of(_pricing.regularHome);
                      newMap[t.$1] = n;
                      _pricing = _pricing.copyWith(regularHome: newMap);
                      _emit();
                    },
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 6),
        Text('תוספות אופציונליות (Add-Ons)',
            style: TextStyle(
                color: _kCyanLight.withValues(alpha: 0.9),
                fontSize: 11,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        ...kCleaningAddOns.map((a) {
          final ctrl = _addOnCtrls[a.id] ??
              (_addOnCtrls[a.id] = TextEditingController(
                  text: (_pricing.addOns[a.id] ?? a.defaultPrice).toString()));
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Text(a.icon, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(a.nameHe,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12))),
                SizedBox(
                  width: 85,
                  child: TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style:
                        const TextStyle(color: Colors.white, fontSize: 12.5),
                    decoration: _fieldDec().copyWith(suffixText: '₪'),
                    onChanged: (v) {
                      final n = int.tryParse(v) ?? 0;
                      final newMap = Map<String, int>.of(_pricing.addOns);
                      newMap[a.id] = n;
                      _pricing = _pricing.copyWith(addOns: newMap);
                      _emit();
                    },
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ─────────── Section: Discounts ───────────
  Widget _discountsSection() {
    Widget tier(String label, String sub, int value, ValueChanged<int> onC) {
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                  Text(sub,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 10.5)),
                ],
              ),
            ),
            SizedBox(
              width: 85,
              child: TextFormField(
                initialValue: value.toString(),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: _fieldDec().copyWith(suffixText: '%'),
                onChanged: (v) => onC(int.tryParse(v) ?? 0),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        tier('📅 שבועי', 'לקוח קבוע מובהק', _discounts.weekly, (v) {
          setState(() {
            _discounts = CleaningRecurringDiscounts(
                weekly: v,
                biweekly: _discounts.biweekly,
                monthly: _discounts.monthly);
            _emit();
          });
        }),
        tier('⭐ דו-שבועי', 'הכי משתלם · 70% מהלקוחות', _discounts.biweekly,
            (v) {
          setState(() {
            _discounts = CleaningRecurringDiscounts(
                weekly: _discounts.weekly,
                biweekly: v,
                monthly: _discounts.monthly);
            _emit();
          });
        }),
        tier('🗓️ חודשי', 'דיירי בית פרטי', _discounts.monthly, (v) {
          setState(() {
            _discounts = CleaningRecurringDiscounts(
                weekly: _discounts.weekly,
                biweekly: _discounts.biweekly,
                monthly: v);
            _emit();
          });
        }),
      ],
    );
  }

  // ─────────── Section: Service Area ───────────
  Widget _serviceAreaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('אזורי כיסוי',
            style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: kDefaultCleaningCities.map((city) {
            final active = _serviceArea.cities.contains(city);
            return GestureDetector(
              onTap: () => setState(() {
                final list = List<String>.of(_serviceArea.cities);
                if (active) {
                  list.remove(city);
                } else {
                  list.add(city);
                }
                _serviceArea = _serviceArea.copyWith(cities: list);
                _emit();
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: active
                      ? _kCyanMid.withValues(alpha: 0.25)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active
                        ? _kCyanLight
                        : _kCyanMid.withValues(alpha: 0.3),
                    style:
                        active ? BorderStyle.solid : BorderStyle.solid,
                  ),
                ),
                child: Text(
                  active ? '$city ✓' : '+ $city',
                  style: TextStyle(
                    color: active ? _kCyanLight : Colors.white70,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        const Text('שעות פעילות',
            style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        ...[
          ('morning_7_12', '🌅 בוקר 7-12'),
          ('afternoon_12_17', '☀️ צהריים 12-17'),
          ('evening_17_22', '🌆 ערב 17-22'),
          ('weekend', '📅 סוף שבוע'),
        ].map((h) {
          final v = _serviceArea.workHours[h.$1] ?? false;
          return Row(
            children: [
              Expanded(
                child: Text(h.$2,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12)),
              ),
              Switch(
                value: v,
                activeColor: _kStatusGreenLight,
                onChanged: (nv) => setState(() {
                  final map = Map<String, bool>.of(_serviceArea.workHours);
                  map[h.$1] = nv;
                  _serviceArea = _serviceArea.copyWith(workHours: map);
                  _emit();
                }),
              ),
            ],
          );
        }),
      ],
    );
  }

  // ─────────── Section: Business Packages ───────────
  Widget _businessPackagesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._packages.asMap().entries.map((e) {
          final pkg = e.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                _kCyanDark.withValues(alpha: 0.3),
                _kDarkBaseMid,
              ]),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: pkg.enabled
                    ? _kCyanLight.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pkg.nameHe,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('₪${pkg.monthlyPrice}/חודש',
                          style: const TextStyle(
                              color: _kCyanLight,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      if (pkg.activeCustomers > 0)
                        Text(
                            '${pkg.activeCustomers} לקוחות על החבילה',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 10)),
                    ],
                  ),
                ),
                Switch(
                  value: pkg.enabled,
                  activeColor: _kCyanLight,
                  onChanged: (v) => setState(() {
                    _packages[e.key] = pkg.copyWith(enabled: v);
                    _emit();
                  }),
                ),
              ],
            ),
          );
        }),
        TextButton.icon(
          onPressed: _addPackage,
          icon: const Icon(Icons.add, color: _kCyanLight, size: 16),
          label: const Text('+ הוסף חבילה',
              style: TextStyle(color: _kCyanLight, fontSize: 12)),
        ),
      ],
    );
  }

  void _addPackage() async {
    final nameCtrl = TextEditingController();
    final visitsCtrl = TextEditingController(text: '4');
    final priceCtrl = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kDarkBaseMid,
        title: const Text('חבילה חדשה',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                    hintText: 'שם החבילה',
                    hintStyle: TextStyle(color: Colors.white38))),
            TextField(
                controller: visitsCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                    hintText: 'ביקורים לחודש',
                    hintStyle: TextStyle(color: Colors.white38))),
            TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                    hintText: 'מחיר חודשי (₪)',
                    hintStyle: TextStyle(color: Colors.white38))),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('הוסף')),
        ],
      ),
    );
    if (added == true && nameCtrl.text.trim().isNotEmpty) {
      setState(() {
        _packages.add(CleaningBusinessPackage(
          id: 'pkg_${DateTime.now().millisecondsSinceEpoch}',
          nameHe: nameCtrl.text.trim(),
          visitsPerMonth: int.tryParse(visitsCtrl.text) ?? 4,
          monthlyPrice: int.tryParse(priceCtrl.text) ?? 0,
          enabled: true,
        ));
        _emit();
      });
    }
    nameCtrl.dispose();
    visitsCtrl.dispose();
    priceCtrl.dispose();
  }
}
