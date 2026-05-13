import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/massage_specialties.dart';
import '../../constants/massage_addons_catalog.dart';
import '../../models/massage_profile.dart';
import '../../services/csm_text_override_service.dart';
import '../../widgets/address_input.dart';

const _kCreamBorder = Color(0xFFEAE7DF);
const _kDark = Color(0xFF1A1A1A);
const _kDarkSecondary = Color(0xFF2D3142);
const _kSuccess = Color(0xFF10B981);
const _kAmber = Color(0xFFF59E0B);

class MassageSettingsBlock extends StatefulWidget {
  final MassageProfile initialProfile;
  final ValueChanged<MassageProfile> onChanged;

  const MassageSettingsBlock({
    super.key,
    required this.initialProfile,
    required this.onChanged,
  });

  @override
  State<MassageSettingsBlock> createState() => _MassageSettingsBlockState();
}

class _MassageSettingsBlockState extends State<MassageSettingsBlock> {
  late List<String> _specialties;
  late bool _homeEnabled;
  late int _homeRadius;
  late int _homeTravelFee;
  late bool _clinicEnabled;
  late String _clinicAddress;
  late String _clinicFloor;
  late List<MassageAddon> _addOns;
  late List<MassageDuration> _durations;
  late List<String> _pressureLevels;
  late List<String> _conversationStyles;
  late List<DiscountPackage> _packages;

  late final TextEditingController _clinicAddressCtrl;
  late final TextEditingController _clinicFloorCtrl;
  late final TextEditingController _travelFeeCtrl;

  // ── CSM text override wiring ──
  static const _csmId = 'massage';
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
    _specialties = List<String>.from(p.specialties);
    _homeEnabled = p.serviceLocations.home.enabled;
    _homeRadius = p.serviceLocations.home.radiusKm;
    _homeTravelFee = p.serviceLocations.home.travelFee;
    _clinicEnabled = p.serviceLocations.clinic.enabled;
    _clinicAddress = p.serviceLocations.clinic.address;
    _clinicFloor = p.serviceLocations.clinic.floor;
    _addOns = List<MassageAddon>.from(p.addOns);
    _durations = p.durations.isEmpty
        ? [
            const MassageDuration(minutes: 30, enabled: true, price: 100),
            const MassageDuration(minutes: 60, enabled: true, price: 150),
            const MassageDuration(minutes: 90, enabled: true, price: 210),
            const MassageDuration(minutes: 120, enabled: true, price: 270),
          ]
        : List<MassageDuration>.from(p.durations);
    _pressureLevels = List<String>.from(p.pressureLevels);
    _conversationStyles = List<String>.from(p.conversationStyles);
    _packages = List<DiscountPackage>.from(p.discountPackages);

    _clinicAddressCtrl = TextEditingController(text: _clinicAddress);
    _clinicFloorCtrl = TextEditingController(text: _clinicFloor);
    _travelFeeCtrl = TextEditingController(
        text: _homeTravelFee > 0 ? '$_homeTravelFee' : '');
  }

  @override
  void dispose() {
    _textOverrides.removeListener(_onTextOverridesChanged);
    _clinicAddressCtrl.dispose();
    _clinicFloorCtrl.dispose();
    _travelFeeCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged(MassageProfile(
      specialties: _specialties,
      serviceLocations: MassageServiceLocations(
        home: HomeService(
          enabled: _homeEnabled,
          radiusKm: _homeRadius,
          travelFee: _homeTravelFee,
        ),
        clinic: ClinicService(
          enabled: _clinicEnabled,
          address: _clinicAddress,
          floor: _clinicFloor,
        ),
      ),
      addOns: _addOns,
      durations: _durations,
      pressureLevels: _pressureLevels,
      conversationStyles: _conversationStyles,
      discountPackages: _packages,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        _buildBanner(),
        const SizedBox(height: 16),
        _buildSpecialtiesSection(),
        const SizedBox(height: 16),
        _buildLocationsSection(),
        const SizedBox(height: 16),
        _buildAddOnsSection(),
        const SizedBox(height: 16),
        _buildDurationsSection(),
        const SizedBox(height: 16),
        _buildPackagesSection(),
        const SizedBox(height: 16),
        _buildPreferencesSection(),
      ],
    );
  }

  Widget _buildBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF8E7), Color(0xFFFEF3C7)],
        ),
        border: Border.all(color: const Color(0xFFFBBF24)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Text('💡', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_t('hero.title', 'הגדרות ייעודיות לעיסוי'),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF78350F))),
                const SizedBox(height: 2),
                Text(
                    _t('hero.subtitle',
                        'הלקוחות יראו רק את מה שתסמני כאן'),
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF92400E))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 1: Specialties ──────────────────────────────────

  Widget _buildSpecialtiesSection() {
    return _sectionCard(
      title: _t('specialties.title', 'סוגי טיפולים שאני מציעה'),
      subtitle: _t('specialties.subtitle',
          'סמני את כל הסוגים שאת יודעת לעשות. רק אלו יוצגו ללקוחות.'),
      badge: '${_specialties.length} / ${kMassageSpecialties.length}',
      child: Column(
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2.4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: kMassageSpecialties.length,
            itemBuilder: (_, i) {
              final s = kMassageSpecialties[i];
              final selected = _specialties.contains(s.id);
              return _specialtyChip(s, selected);
            },
          ),
          const SizedBox(height: 10),
          _addCustomButton('+ הוסף סוג טיפול אישי', _showAddCustomSpecialtyDialog),
        ],
      ),
    );
  }

  Widget _specialtyChip(MassageSpecialty s, bool selected) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          if (selected) {
            _specialties.remove(s.id);
          } else {
            _specialties.add(s.id);
          }
        });
        _notify();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_kDark, _kDarkSecondary],
                )
              : null,
          color: selected ? null : Colors.white,
          border: selected ? null : Border.all(color: _kCreamBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: selected ? Colors.white.withValues(alpha: 0.15) : s.bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(s.icon, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.nameHe,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: selected ? Colors.white : _kDark),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(s.taglineHe,
                      style: TextStyle(
                          fontSize: 10,
                          color: selected
                              ? Colors.white70
                              : const Color(0xFF999999)),
                      maxLines: 1),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, size: 18, color: Colors.white),
          ],
        ),
      ),
    );
  }

  void _showAddCustomSpecialtyDialog() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('סוג טיפול אישי', textAlign: TextAlign.right),
        content: TextField(
          controller: nameCtrl,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(
            hintText: 'שם הטיפול',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול')),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty) {
                final customId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
                setState(() => _specialties.add(customId));
                _notify();
                Navigator.pop(ctx);
              }
            },
            child: const Text('הוסף'),
          ),
        ],
      ),
    );
  }

  // ── Section 2: Locations ────────────────────────────────────

  Widget _buildLocationsSection() {
    return _sectionCard(
      title: _t('locations.title', 'איפה את נותנת טיפולים'),
      subtitle:
          _t('locations.subtitle', 'בחרי באילו אופציות הלקוחות יוכלו לבחור'),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _locationCard(
                icon: '🏠',
                title: 'בבית הלקוח',
                subtitle: 'אני מגיעה אליו',
                selected: _homeEnabled,
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _homeEnabled = !_homeEnabled);
                  _notify();
                },
              )),
              const SizedBox(width: 10),
              Expanded(child: _locationCard(
                icon: '🏢',
                title: 'בקליניקה שלי',
                subtitle: 'הלקוח מגיע אליי',
                selected: _clinicEnabled,
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _clinicEnabled = !_clinicEnabled);
                  _notify();
                },
              )),
            ],
          ),
          if (_homeEnabled) ...[
            const SizedBox(height: 12),
            _buildHomeDetails(),
          ],
          if (_clinicEnabled) ...[
            const SizedBox(height: 12),
            _buildClinicDetails(),
          ],
        ],
      ),
    );
  }

  Widget _locationCard({
    required String icon,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_kDark, _kDarkSecondary],
                )
              : null,
          color: selected ? null : Colors.white,
          border: selected ? null : Border.all(color: _kCreamBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 6),
            Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: selected ? Colors.white : _kDark)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(
                    fontSize: 11,
                    color: selected ? Colors.white70 : const Color(0xFF999999))),
            if (selected)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Icon(Icons.check_circle, size: 18, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeDetails() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7F3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('🏠 ', style: TextStyle(fontSize: 14)),
              Text('פרטים על שירות בבית',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 12),
          Text('רדיוס שירות (ק״מ ממיקומך)',
              style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _homeRadius.toDouble(),
                  min: 1,
                  max: 50,
                  divisions: 49,
                  activeColor: _kDark,
                  onChanged: (v) {
                    setState(() => _homeRadius = v.round());
                  },
                  onChangeEnd: (_) => _notify(),
                ),
              ),
              Text('$_homeRadius ק״מ',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 10),
          Text('מחיר נסיעה (אופציונלי)',
              style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('₪ ', style: TextStyle(fontSize: 14)),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _travelFeeCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (v) {
                    _homeTravelFee = int.tryParse(v) ?? 0;
                    _notify();
                  },
                ),
              ),
              const SizedBox(width: 8),
              const Text('לכיוון אחד',
                  style: TextStyle(fontSize: 11, color: Color(0xFF999999))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClinicDetails() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7F3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('🏢 ', style: TextStyle(fontSize: 14)),
              Text('פרטים על הקליניקה',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 12),
          Text('כתובת מלאה (תוצג ללקוחות)',
              style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          const SizedBox(height: 4),
          // Two-field smart autocomplete (city + street) bridged back to
          // the legacy single-string `clinic.address` field via combined.
          Builder(builder: (_) {
            final initial = AddressValue.fromCombined(_clinicAddress);
            return AddressInput(
              key: const ValueKey('massage-clinic-address'),
              initialCity: initial.city,
              initialStreet: initial.street,
              accentColor: _kSuccess,
              dense: true,
              streetHint: 'לדוגמה: בן יהודה 88',
              onChanged: (v) {
                _clinicAddress = v.combined;
                _clinicAddressCtrl.text = _clinicAddress;
                _notify();
              },
            );
          }),
          const SizedBox(height: 10),
          Text('קומה / דירה (אופציונלי)',
              style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          const SizedBox(height: 4),
          TextField(
            controller: _clinicFloorCtrl,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'קומה 3, דירה 12',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (v) {
              _clinicFloor = v;
              _notify();
            },
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Text('💡', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'הכתובת תוצג ללקוחות שיבחרו \'בקליניקה\'',
                    style: TextStyle(fontSize: 11, color: Colors.green[800]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 3: Add-Ons ──────────────────────────────────────

  Widget _buildAddOnsSection() {
    final enabledCount = _addOns.where((a) => a.enabled).length;
    return _sectionCard(
      title: _t('addOns.title', 'תוספות שאני מציעה'),
      subtitle: _t('addOns.subtitle',
          'סמני, שני מחיר אם רוצה, או הוסיפי משלך'),
      badge: '$enabledCount / ${kMassageAddonsCatalog.length}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final group in [kGroupRecommended, kGroupAroma, kGroupTherapeutic, kGroupEnriching]) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: Text(
                kAddonGroupLabels[group] ?? group,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: _kDark),
              ),
            ),
            ...addonsInGroup(group).map((def) {
              final existing = _addOns.where((a) => a.id == def.id).firstOrNull;
              final isEnabled = existing?.enabled ?? false;
              final price = existing?.customPrice ?? def.recommendedPrice;
              return _addonRow(def, isEnabled, price);
            }),
          ],
          const SizedBox(height: 10),
          _addCustomButton('הוסף תוספת אישית שלך', _showAddCustomAddonDialog),
        ],
      ),
    );
  }

  Widget _addonRow(MassageAddonDef def, bool enabled, int price) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          final idx = _addOns.indexWhere((a) => a.id == def.id);
          if (idx >= 0) {
            _addOns[idx] = _addOns[idx].copyWith(enabled: !enabled);
          } else {
            _addOns.add(MassageAddon(
                id: def.id, enabled: true, customPrice: def.recommendedPrice));
          }
        });
        _notify();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(
                  colors: [Color(0xFFFAFAF6), Color(0xFFF5F2EC)])
              : null,
          color: enabled ? null : Colors.white,
          border: Border.all(
            color: enabled ? _kDark : _kCreamBorder,
            width: enabled ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: enabled ? _kCreamBorder : const Color(0xFFF5F2EC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(def.icon, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(def.nameHe,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500)),
                  Text(def.descriptionHe,
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFF999999))),
                ],
              ),
            ),
            if (enabled)
              SizedBox(
                width: 60,
                child: TextField(
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  controller: TextEditingController(text: '$price'),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixText: '₪',
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 6),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (v) {
                    final idx = _addOns.indexWhere((a) => a.id == def.id);
                    if (idx >= 0) {
                      _addOns[idx] = _addOns[idx]
                          .copyWith(customPrice: int.tryParse(v) ?? price);
                      _notify();
                    }
                  },
                ),
              )
            else
              Text('מחיר מומלץ ₪$price',
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFF999999))),
            const SizedBox(width: 8),
            Icon(
              enabled ? Icons.check_box : Icons.check_box_outline_blank,
              color: enabled ? _kDark : _kCreamBorder,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCustomAddonDialog() {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('תוספת אישית', textAlign: TextAlign.right),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                  hintText: 'שם התוספת', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descCtrl,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                  hintText: 'תיאור קצר', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  hintText: 'מחיר (₪)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול')),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty) {
                final customId =
                    'custom_${DateTime.now().millisecondsSinceEpoch}';
                setState(() {
                  _addOns.add(MassageAddon(
                    id: customId,
                    enabled: true,
                    customPrice: int.tryParse(priceCtrl.text) ?? 0,
                    isCustom: true,
                    nameHe: nameCtrl.text.trim(),
                    icon: '✨',
                    descriptionHe: descCtrl.text.trim(),
                  ));
                });
                _notify();
                Navigator.pop(ctx);
              }
            },
            child: const Text('הוסף'),
          ),
        ],
      ),
    );
  }

  // ── Section 4: Durations ────────────────────────────────────

  Widget _buildDurationsSection() {
    return _sectionCard(
      title: _t('durations.title', 'משכי טיפול ומחירים'),
      subtitle: _t('durations.subtitle',
          'מחירי בסיס לטיפול שוודי · ניתן לעדכן לכל סוג בנפרד'),
      child: Column(
        children: [
          for (int i = 0; i < _durations.length; i++) _durationRow(i),
        ],
      ),
    );
  }

  Widget _durationRow(int i) {
    final d = _durations[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF8F2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text('${d.minutes} דק׳',
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const Spacer(),
          const Text('₪ ', style: TextStyle(fontSize: 13)),
          SizedBox(
            width: 70,
            child: TextField(
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              controller: TextEditingController(text: '${d.price}'),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                filled: true,
                fillColor: Colors.white,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kCreamBorder),
                ),
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (v) {
                _durations[i] =
                    d.copyWith(price: int.tryParse(v) ?? d.price);
                _notify();
              },
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _durations[i] = d.copyWith(enabled: !d.enabled));
              _notify();
            },
            child: Icon(
              d.enabled ? Icons.check_box : Icons.check_box_outline_blank,
              color: d.enabled ? _kDark : _kCreamBorder,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 5: Discount Packages ────────────────────────────

  Widget _buildPackagesSection() {
    return _sectionCard(
      title: _t('packages.title', 'חבילות הנחה'),
      subtitle: _t('packages.subtitle',
          'צרי חבילות שמקנות הנחה ללקוחות חוזרים'),
      badgeColor: _kAmber,
      badge: '💰 משפר נאמנות',
      child: Column(
        children: [
          if (_packages.isEmpty)
            _buildSuggestedPackages(),
          for (int i = 0; i < _packages.length; i++) _packageCard(i),
          const SizedBox(height: 10),
          _addCustomButton('+ הוסף חבילה חדשה', _showAddPackageDialog),
        ],
      ),
    );
  }

  Widget _buildSuggestedPackages() {
    final suggestions = [
      ('חבילת 3 טיפולים', 3, 10, 90),
      ('חבילת 5 טיפולים', 5, 15, 180),
      ('חבילת 10 טיפולים', 10, 25, 365),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text('חבילות מומלצות',
              style: TextStyle(fontSize: 11, color: Color(0xFF999999))),
        ),
        for (final (name, sessions, discount, days) in suggestions)
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                _packages.add(DiscountPackage(
                  id: 'pkg_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  sessionsCount: sessions,
                  discountPercent: discount,
                  validityDays: days,
                ));
              });
              _notify();
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: _kCreamBorder),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$name · $discount% הנחה · תוקף $days ימים',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const Icon(Icons.add_circle_outline, size: 20, color: _kSuccess),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _packageCard(int i) {
    final p = _packages[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
        ),
        border: Border.all(color: const Color(0xFFFBBF24), width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🎁 ', style: TextStyle(fontSize: 16)),
              Expanded(
                child: Text(p.name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
              ),
              Text(p.enabled ? 'פעיל ✓' : 'כבוי',
                  style: TextStyle(
                      fontSize: 11,
                      color: p.enabled ? _kSuccess : Colors.grey)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${p.sessionsCount} טיפולים  ·  הנחה ${p.discountPercent}%  ·  תוקף ${p.validityDays} ימים',
            style: const TextStyle(fontSize: 12, color: Color(0xFF78350F)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: () {
                  setState(() => _packages.removeAt(i));
                  _notify();
                },
                child: const Text('מחק',
                    style: TextStyle(fontSize: 12, color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAddPackageDialog() {
    final nameCtrl = TextEditingController();
    final sessionsCtrl = TextEditingController(text: '5');
    final discountCtrl = TextEditingController(text: '15');
    final daysCtrl = TextEditingController(text: '180');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('חבילה חדשה', textAlign: TextAlign.right),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                  hintText: 'שם החבילה', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: sessionsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        hintText: 'טיפולים', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: discountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        hintText: 'הנחה %', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: daysCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  hintText: 'תוקף (ימים)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול')),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty) {
                setState(() {
                  _packages.add(DiscountPackage(
                    id: 'pkg_${DateTime.now().millisecondsSinceEpoch}',
                    name: nameCtrl.text.trim(),
                    sessionsCount: int.tryParse(sessionsCtrl.text) ?? 5,
                    discountPercent: int.tryParse(discountCtrl.text) ?? 15,
                    validityDays: int.tryParse(daysCtrl.text) ?? 180,
                  ));
                });
                _notify();
                Navigator.pop(ctx);
              }
            },
            child: const Text('הוסף'),
          ),
        ],
      ),
    );
  }

  // ── Section 6: Preferences ──────────────────────────────────

  Widget _buildPreferencesSection() {
    return _sectionCard(
      title: _t('preferences.title', 'העדפות ושירות'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('עוצמות לחץ שאני יכולה לתת',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _pressureChip('light', '🪶 עדין'),
              _pressureChip('medium', '✋ בינוני'),
              _pressureChip('strong', '💪 חזק'),
            ],
          ),
          const SizedBox(height: 16),
          const Text('סגנון שיחה',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _conversationChip('chatty', '💬 בכיף לדבר'),
              _conversationChip('minimal', '🤫 מינימלי'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pressureChip(String id, String label) {
    final selected = _pressureLevels.contains(id);
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          if (selected) {
            _pressureLevels.remove(id);
          } else {
            _pressureLevels.add(id);
          }
        });
        _notify();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: [_kDark, _kDarkSecondary])
              : null,
          color: selected ? null : Colors.white,
          border: selected ? null : Border.all(color: _kCreamBorder),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: selected ? Colors.white : _kDark)),
      ),
    );
  }

  Widget _conversationChip(String id, String label) {
    final selected = _conversationStyles.contains(id);
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          if (selected) {
            _conversationStyles.remove(id);
          } else {
            _conversationStyles.add(id);
          }
        });
        _notify();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: [_kDark, _kDarkSecondary])
              : null,
          color: selected ? null : Colors.white,
          border: selected ? null : Border.all(color: _kCreamBorder),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: selected ? Colors.white : _kDark)),
      ),
    );
  }

  // ── Shared helpers ──────────────────────────────────────────

  Widget _sectionCard({
    required String title,
    String? subtitle,
    String? badge,
    Color? badgeColor,
    Widget? child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF999999))),
                    ],
                  ],
                ),
              ),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (badgeColor ?? _kSuccess).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(badge,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: badgeColor ?? _kSuccess)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (child != null) child,
        ],
      ),
    );
  }

  Widget _addCustomButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_kDark, _kDarkSecondary]),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white)),
      ),
    );
  }
}
