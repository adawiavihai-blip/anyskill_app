import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/pest_control_profile.dart';
import '../../constants/pest_types_catalog.dart';
import '../../constants/pest_treatment_methods.dart';
import '../../constants/pest_structured_instructions.dart';
import '../../services/csm_text_override_service.dart';

const _kPestGreenDark = Color(0xFF14532D);
const _kPestGreenMedium = Color(0xFF166534);
const _kPestGreenLight = Color(0xFF15803D);
const _kPestGreenBg = Color(0xFFDCFCE7);
const _kAiBlueDark = Color(0xFF1E3A8A);
const _kAiBlueMedium = Color(0xFF1E40AF);
const _kEmergencyRed = Color(0xFFDC2626);
const _kEmergencyRedBg = Color(0xFFFEE2E2);
const _kAmberBg = Color(0xFFFEF3C7);
const _kAmberBorder = Color(0xFFFBBF24);
const _kIndigoMedium = Color(0xFF6366F1);
const _kCreamBorder = Color(0xFFEAE7DF);

class PestControlSettingsBlock extends StatefulWidget {
  final PestControlProfile initialProfile;
  final ValueChanged<PestControlProfile> onChanged;

  const PestControlSettingsBlock({
    super.key,
    required this.initialProfile,
    required this.onChanged,
  });

  @override
  State<PestControlSettingsBlock> createState() =>
      _PestControlSettingsBlockState();
}

class _PestControlSettingsBlockState extends State<PestControlSettingsBlock> {
  late List<PestLicense> _licenses;
  late List<String> _selectedPestTypes;
  late List<String> _selectedMethods;
  late List<String> _selectedCustomerTypes;
  late bool _emergencyEnabled;
  late int _emergencyFee;
  late bool _available247;
  late int _arrivalTime;
  late int _radiusKm;
  late int _travelFee;
  late int _freeRadiusKm;
  late Map<String, int> _basePricing;
  late int _warrantyMonths;
  late bool _digitalReport;
  late bool _beforeAfterPhotos;
  late List<MaintenancePackage> _packages;
  late List<StructuredInstruction> _instructions;
  late String _customInstructions;

  final _customInstructionsCtrl = TextEditingController();

  // ── CSM text override wiring ──
  static const _csmId = 'pest_control';
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
    _licenses = List.of(p.licenses);
    _selectedPestTypes = List.of(p.pestTypes);
    _selectedMethods = List.of(p.treatmentMethods);
    _selectedCustomerTypes = List.of(p.customerTypes);
    _emergencyEnabled = p.availability.emergencyService.enabled;
    _emergencyFee = p.availability.emergencyService.additionalFee;
    _available247 = p.availability.available247;
    _arrivalTime = p.availability.averageArrivalTime;
    _radiusKm = p.serviceArea.radiusKm;
    _travelFee = p.serviceArea.travelFee;
    _freeRadiusKm = p.serviceArea.freeRadiusKm;
    _basePricing = Map.of(p.basePricing);
    _warrantyMonths = p.warrantyAndService.warrantyMonths;
    _digitalReport = p.warrantyAndService.digitalReport;
    _beforeAfterPhotos = p.warrantyAndService.beforeAfterPhotos;
    _packages = List.of(p.maintenancePackages);
    _customInstructions = p.treatmentInstructions.customInstructions;
    _customInstructionsCtrl.text = _customInstructions;

    if (p.treatmentInstructions.structuredInstructions.isEmpty) {
      _instructions = kStructuredInstructions.map((def) {
        final defaultDuration = def.durationOptions?.isNotEmpty == true
            ? def.durationOptions![def.durationOptions!.length > 1 ? 1 : 0]
            : null;
        return StructuredInstruction(
          id: def.id,
          type: def.type,
          icon: def.icon,
          titleHe: def.titleHe,
          enabled: false,
          duration: defaultDuration,
          color: def.colorName,
        );
      }).toList();
    } else {
      _instructions = List.of(p.treatmentInstructions.structuredInstructions);
      for (final def in kStructuredInstructions) {
        if (!_instructions.any((i) => i.id == def.id)) {
          _instructions.add(StructuredInstruction(
            id: def.id,
            type: def.type,
            icon: def.icon,
            titleHe: def.titleHe,
            enabled: false,
            duration: def.durationOptions?.isNotEmpty == true
                ? def.durationOptions![1.clamp(0, def.durationOptions!.length - 1)]
                : null,
            color: def.colorName,
          ));
        }
      }
    }
  }

  @override
  void dispose() {
    _textOverrides.removeListener(_onTextOverridesChanged);
    _customInstructionsCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged(PestControlProfile(
      licenses: _licenses,
      pestTypes: _selectedPestTypes,
      treatmentMethods: _selectedMethods,
      customerTypes: _selectedCustomerTypes,
      availability: PestAvailability(
        emergencyService: PestEmergencyService(
          enabled: _emergencyEnabled,
          additionalFee: _emergencyFee,
        ),
        available247: _available247,
        averageArrivalTime: _arrivalTime,
      ),
      serviceArea: PestServiceArea(
        radiusKm: _radiusKm,
        travelFee: _travelFee,
        freeRadiusKm: _freeRadiusKm,
      ),
      basePricing: _basePricing,
      warrantyAndService: PestWarranty(
        warrantyMonths: _warrantyMonths,
        digitalReport: _digitalReport,
        beforeAfterPhotos: _beforeAfterPhotos,
      ),
      maintenancePackages: _packages,
      treatmentInstructions: TreatmentInstructions(
        structuredInstructions: _instructions.where((i) => i.enabled).toList(),
        customInstructions: _customInstructions,
      ),
    ));
  }

  bool get _hasSnakeLicense =>
      _licenses.any((l) => l.type == 'snake_catcher' && l.verified);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBanner(),
        const SizedBox(height: 14),
        _buildLicensesSection(),
        const SizedBox(height: 14),
        _buildPestTypesSection(),
        const SizedBox(height: 14),
        _buildTreatmentMethodsSection(),
        const SizedBox(height: 14),
        _buildAvailabilitySection(),
        const SizedBox(height: 14),
        _buildPricingSection(),
        const SizedBox(height: 14),
        _buildWarrantySection(),
        const SizedBox(height: 14),
        _buildPackagesSection(),
        const SizedBox(height: 14),
        _buildInstructionsSection(),
      ],
    );
  }

  Widget _buildBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [_kPestGreenDark, _kPestGreenLight],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 8, color: Color(0xFF4ADE80)),
                SizedBox(width: 6),
                Text('פעיל ומקבל הזמנות',
                    style: TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(_t('hero.title', 'הגדרות ייעודיות להדברה'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
              _t('hero.subtitle',
                  'הלקוחות יראו רק את מה שתסמן כאן · רישיון משרד הגנ"ס נדרש'),
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    String? subtitle,
    required Widget child,
    Color borderColor = _kCreamBorder,
    double borderWidth = 1,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  // ── Licenses ───────────────────────────────────────────────
  Widget _buildLicensesSection() {
    final verified = _licenses.where((l) => l.verified).length;
    return _sectionCard(
      title: _t('licenses.title', 'רישיונות חובה'),
      subtitle: _t('licenses.subtitle', 'חובה לפי חוק - אימות נדרש'),
      borderColor: _kEmergencyRed,
      borderWidth: 2,
      child: Column(
        children: [
          if (verified > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _kPestGreenBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified, size: 16, color: _kPestGreenLight),
                  const SizedBox(width: 6),
                  Text('$verified מאושרים',
                      style: const TextStyle(
                          fontSize: 13,
                          color: _kPestGreenDark,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ..._licenses.map(_buildLicenseRow),
          const SizedBox(height: 8),
          _buildAddLicenseButton(),
        ],
      ),
    );
  }

  Widget _buildLicenseRow(PestLicense lic) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: lic.verified
              ? [_kPestGreenBg, const Color(0xFFBBF7D0)]
              : [Colors.white, const Color(0xFFF9FAFB)],
        ),
        border: Border.all(
            color: lic.verified ? _kPestGreenLight : _kCreamBorder),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Icon(
            lic.verified ? Icons.check_circle : Icons.pending,
            size: 20,
            color: lic.verified ? _kPestGreenLight : const Color(0xFF9CA3AF),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lic.nameHe,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                if (lic.licenseNumber.isNotEmpty)
                  Text('#${lic.licenseNumber}',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF6B7280))),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: lic.verified ? _kPestGreenBg : const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              lic.verified ? 'מאושר' : 'ממתין',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: lic.verified
                    ? _kPestGreenDark
                    : const Color(0xFF92400E),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () {
              setState(() => _licenses.remove(lic));
              _notify();
            },
            child: const Icon(Icons.close, size: 18, color: Color(0xFF9CA3AF)),
          ),
        ],
      ),
    );
  }

  Widget _buildAddLicenseButton() {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _showAddLicenseDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: _kCreamBorder, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: Text('+ הוסף רישיון',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _kPestGreenDark)),
        ),
      ),
    );
  }

  void _showAddLicenseDialog() {
    final types = [
      {'type': 'ministry_environmental_protection', 'name': 'רישיון משרד הגנ"ס'},
      {'type': 'snake_catcher', 'name': 'לוכד נחשים מוסמך'},
      {'type': 'other', 'name': 'הסמכה נוספת'},
    ];
    final numCtrl = TextEditingController();
    String? selectedType;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('הוסף רישיון',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              ...types.map((t) => RadioListTile<String>(
                    title: Text(t['name']!),
                    value: t['type']!,
                    groupValue: selectedType,
                    onChanged: (v) => setSheetState(() => selectedType = v),
                    activeColor: _kPestGreenLight,
                    contentPadding: EdgeInsets.zero,
                  )),
              const SizedBox(height: 12),
              TextField(
                controller: numCtrl,
                decoration: InputDecoration(
                  labelText: 'מספר רישיון',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: selectedType == null
                      ? null
                      : () {
                          final name = types
                              .firstWhere(
                                  (t) => t['type'] == selectedType)['name']!;
                          setState(() {
                            _licenses.add(PestLicense(
                              id: '${selectedType}_${DateTime.now().millisecondsSinceEpoch}',
                              type: selectedType!,
                              nameHe: name,
                              licenseNumber: numCtrl.text.trim(),
                              verified: false,
                            ));
                          });
                          _notify();
                          Navigator.pop(ctx);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPestGreenDark,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('הוסף'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Pest Types ─────────────────────────────────────────────
  Widget _buildPestTypesSection() {
    return _sectionCard(
      title: _t('pestTypes.title', 'סוגי מזיקים שאני מטפל'),
      subtitle: 'הלקוחות יראו את הסל שלך · ${_selectedPestTypes.length}/14',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final group in [kGroupInsects, kGroupRodents, kGroupAnimalCapture]) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6, top: 4),
              child: Text(kPestGroupLabels[group]!,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280))),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: pestTypesInGroup(group).map((pest) {
                final isSelected = _selectedPestTypes.contains(pest.id);
                final isCapture = pest.group == kGroupAnimalCapture;
                final needsLicense =
                    pest.id == 'snakes' && !_hasSnakeLicense;

                return GestureDetector(
                  onTap: () {
                    if (needsLicense) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'לכידת נחשים דורשת רישיון לוכד נחשים מוסמך'),
                          backgroundColor: _kEmergencyRed,
                        ),
                      );
                      return;
                    }
                    HapticFeedback.lightImpact();
                    setState(() {
                      if (isSelected) {
                        _selectedPestTypes.remove(pest.id);
                      } else {
                        _selectedPestTypes.add(pest.id);
                      }
                    });
                    _notify();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? LinearGradient(
                              colors: isCapture
                                  ? [_kAiBlueMedium, _kAiBlueDark]
                                  : [_kPestGreenDark, _kPestGreenMedium],
                            )
                          : null,
                      color: isSelected ? null : Colors.white,
                      border: Border.all(
                          color: isSelected
                              ? Colors.transparent
                              : _kCreamBorder),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(pest.icon, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 6),
                        Text(pest.nameHe,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color:
                                  isSelected ? Colors.white : const Color(0xFF1A1A2E),
                            )),
                        if (isSelected) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.check, size: 14, color: Colors.white),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  // ── Treatment Methods ──────────────────────────────────────
  Widget _buildTreatmentMethodsSection() {
    return _sectionCard(
      title: _t('methods.title', 'שיטות הטיפול שלי'),
      subtitle: _t('methods.subtitle', 'בחר לפחות שיטה אחת'),
      child: Column(
        children: kTreatmentMethods.map((method) {
          final isSelected = _selectedMethods.contains(method.id);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  if (isSelected) {
                    _selectedMethods.remove(method.id);
                  } else {
                    _selectedMethods.add(method.id);
                  }
                });
                _notify();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? const LinearGradient(
                          colors: [_kPestGreenDark, _kPestGreenMedium])
                      : null,
                  color: isSelected ? null : Colors.white,
                  border: Border.all(
                      color: isSelected
                          ? Colors.transparent
                          : _kCreamBorder),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  children: [
                    Text(method.icon, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(method.nameHe,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFF1A1A2E),
                                  )),
                              if (method.isRecommended) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.white.withValues(alpha: 0.2)
                                        : _kPestGreenBg,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('מומלץ',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: isSelected
                                            ? Colors.white
                                            : _kPestGreenDark,
                                      )),
                                ),
                              ],
                            ],
                          ),
                          Text(method.descHe,
                              style: TextStyle(
                                fontSize: 12,
                                color: isSelected
                                    ? Colors.white70
                                    : const Color(0xFF6B7280),
                              )),
                        ],
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_circle,
                          size: 20, color: Colors.white),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Availability ───────────────────────────────────────────
  Widget _buildAvailabilitySection() {
    return _sectionCard(
      title: _t('availability.title', 'זמינות ותגובה'),
      subtitle: _t('availability.subtitle', 'חירום = +35% הזמנות'),
      child: Column(
        children: [
          _buildToggleRow(
            icon: '\u{1F6A8}',
            label: 'שירות חירום',
            sublabel: 'תוך שעה',
            value: _emergencyEnabled,
            onChanged: (v) {
              setState(() => _emergencyEnabled = v);
              _notify();
            },
            borderColor: _kEmergencyRed,
            bgColor: _kEmergencyRedBg,
          ),
          if (_emergencyEnabled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('תוספת: ',
                    style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                const Text('₪',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                SizedBox(
                  width: 80,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(
                        text: _emergencyFee.toString()),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (v) {
                      _emergencyFee = int.tryParse(v) ?? 150;
                      _notify();
                    },
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          _buildToggleRow(
            icon: '\u{1F319}',
            label: 'זמין 24/7',
            sublabel: 'לילות, סופ"ש וחגים',
            value: _available247,
            onChanged: (v) {
              setState(() => _available247 = v);
              _notify();
            },
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('זמן הגעה ממוצע',
                  style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
              const SizedBox(height: 6),
              Row(
                children: [15, 30, 45, 60].map((min) {
                  final isSelected = _arrivalTime == min;
                  return Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text("$min'"),
                      selected: isSelected,
                      onSelected: (_) {
                        HapticFeedback.lightImpact();
                        setState(() => _arrivalTime = min);
                        _notify();
                      },
                      selectedColor: _kPestGreenBg,
                      checkmarkColor: _kPestGreenDark,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToggleRow({
    required String icon,
    required String label,
    String? sublabel,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color borderColor = _kCreamBorder,
    Color bgColor = Colors.white,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: value ? bgColor : Colors.white,
        border: Border.all(color: value ? borderColor : _kCreamBorder),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                if (sublabel != null)
                  Text(sublabel,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF6B7280))),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: (v) {
              HapticFeedback.lightImpact();
              onChanged(v);
            },
            activeColor: _kPestGreenLight,
          ),
        ],
      ),
    );
  }

  // ── Pricing ────────────────────────────────────────────────
  Widget _buildPricingSection() {
    const pricingFields = [
      {'key': 'apartment_3_4_rooms', 'label': 'דירה 3-4 חדרים', 'icon': '\u{1F3E0}', 'default': 290},
      {'key': 'private_house', 'label': 'בית פרטי', 'icon': '\u{1F3E1}', 'default': 450},
      {'key': 'restaurant_small_business', 'label': 'מסעדה / עסק', 'icon': '\u{1F37D}', 'default': 350},
      {'key': 'animal_capture', 'label': 'לכידת בעל חיים', 'icon': '\u{1F40D}', 'default': 220},
    ];

    return _sectionCard(
      title: _t('pricing.title', 'מחירון שקוף'),
      subtitle: _t('pricing.subtitle', 'לקוחות סומכים על מחיר ברור'),
      child: Column(
        children: pricingFields.map((f) {
          final key = f['key'] as String;
          final label = f['label'] as String;
          final icon = f['icon'] as String;
          final defaultVal = f['default'] as int;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(label,
                        style: const TextStyle(fontSize: 14))),
                const Text('₪',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                SizedBox(
                  width: 80,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(
                        text: (_basePricing[key] ?? defaultVal).toString()),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (v) {
                      _basePricing[key] = int.tryParse(v) ?? defaultVal;
                      _notify();
                    },
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Warranty ───────────────────────────────────────────────
  Widget _buildWarrantySection() {
    return _sectionCard(
      title: _t('warranty.title', 'אחריות ושירות'),
      subtitle: _t('warranty.subtitle', 'מבדיל בינך לבין מתחרים'),
      child: Column(
        children: [
          Row(
            children: [
              const Text('\u{1F6E1}', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('אחריות בסיסית',
                      style: TextStyle(fontSize: 14))),
              ...[1, 3, 6].map((m) {
                final isSelected = _warrantyMonths == m;
                return Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ChoiceChip(
                    label: Text(m == 1
                        ? 'חודש'
                        : '$m חו\''),
                    selected: isSelected,
                    onSelected: (_) {
                      HapticFeedback.lightImpact();
                      setState(() => _warrantyMonths = m);
                      _notify();
                    },
                    selectedColor: _kPestGreenBg,
                    checkmarkColor: _kPestGreenDark,
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 10),
          _buildToggleRow(
            icon: '\u{1F4CB}',
            label: 'דוח דיגיטלי אוטומטי',
            sublabel: 'נוצר אחרי כל טיפול',
            value: _digitalReport,
            onChanged: (v) {
              setState(() => _digitalReport = v);
              _notify();
            },
          ),
          const SizedBox(height: 8),
          _buildToggleRow(
            icon: '\u{1F4F8}',
            label: 'תמונות לפני/אחרי',
            sublabel: "מתועד אוטו'",
            value: _beforeAfterPhotos,
            onChanged: (v) {
              setState(() => _beforeAfterPhotos = v);
              _notify();
            },
          ),
        ],
      ),
    );
  }

  // ── Packages ───────────────────────────────────────────────
  Widget _buildPackagesSection() {
    final active = _packages.where((p) => p.enabled).length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFFFFFBEB), _kAmberBg]),
        border: Border.all(color: _kAmberBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('\u{1F381}', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(_t('packages.title', 'חבילות תחזוקה'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700))),
              if (active > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('$active פעילות',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(_t('packages.subtitle', 'הכנסה קבועה · לקוחות חוזרים'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          const SizedBox(height: 12),
          ..._packages.asMap().entries.map((entry) {
            final pkg = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: _kCreamBorder),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                children: [
                  const Icon(Icons.autorenew, size: 18, color: Color(0xFF6B7280)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pkg.nameHe,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(
                            '${pkg.treatmentsCount} טיפולים · ${pkg.discountPercent}% הנחה',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF6B7280))),
                      ],
                    ),
                  ),
                  Text('₪${pkg.pricePerTreatment}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      setState(() => _packages.removeAt(entry.key));
                      _notify();
                    },
                    child: const Icon(Icons.close,
                        size: 18, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            );
          }),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _showAddPackageDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: _kAmberBorder),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text('+ הוסף חבילה חדשה',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFD97706))),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddPackageDialog() {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: '199');
    final countCtrl = TextEditingController(text: '4');
    final discountCtrl = TextEditingController(text: '30');
    String type = 'quarterly';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('חבילה חדשה',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'שם החבילה',
                  hintText: 'לדוגמה: רבעוני · ביתי',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: countCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'מספר טיפולים',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '₪ לטיפול',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: discountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '% הנחה',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _packages.add(MaintenancePackage(
                        id: 'pkg_${DateTime.now().millisecondsSinceEpoch}',
                        nameHe: nameCtrl.text.trim().isNotEmpty
                            ? nameCtrl.text.trim()
                            : 'חבילה חדשה',
                        type: type,
                        treatmentsCount:
                            int.tryParse(countCtrl.text) ?? 4,
                        discountPercent:
                            int.tryParse(discountCtrl.text) ?? 0,
                        pricePerTreatment:
                            int.tryParse(priceCtrl.text) ?? 199,
                      ));
                    });
                    _notify();
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('הוסף חבילה'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Treatment Instructions ─────────────────────────────────
  Widget _buildInstructionsSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _kIndigoMedium, width: 1.5),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _kIndigoMedium.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('\u{1F4CB}', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        _t('instructions.title', 'הוראות והתנהלות לאחר טיפול'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    Text(_t('instructions.subtitle', 'מתורגם אוטומטית ללקוחות'),
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF6B7280))),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('חדש',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _kIndigoMedium)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('\u{1F4A1}', style: TextStyle(fontSize: 16)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'למה זה חשוב?\nלקוחות שיודעים מראש מה צפוי מבטלים פחות, מתלוננים פחות, ומדרגים יותר טוב.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF4F46E5)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text('הוראות מהירות (סמן את הרלוונטיות)',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280))),
          const SizedBox(height: 8),
          ..._instructions.asMap().entries.map((entry) {
            final idx = entry.key;
            final inst = entry.value;
            final def = findInstruction(inst.id);
            if (def == null) return const SizedBox.shrink();
            return _buildInstructionRow(idx, inst, def);
          }),
          const SizedBox(height: 14),
          const Text('הוראות אישיות נוספות',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280))),
          const SizedBox(height: 6),
          TextField(
            controller: _customInstructionsCtrl,
            maxLines: 4,
            maxLength: 500,
            decoration: InputDecoration(
              hintText: 'כתוב הוראות נוספות ללקוח...',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onChanged: (v) {
              _customInstructions = v;
              _notify();
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              '+ במקרה של ריח',
              '+ ניקוי מטבח',
              '+ נשים בהריון',
              '+ אסטמטיים',
            ].map((chip) {
              return ActionChip(
                label: Text(chip, style: const TextStyle(fontSize: 12)),
                onPressed: () {
                  final text = chip.substring(2);
                  if (!_customInstructionsCtrl.text.contains(text)) {
                    final existing = _customInstructionsCtrl.text;
                    _customInstructionsCtrl.text =
                        existing.isEmpty ? text : '$existing\n$text';
                    _customInstructions = _customInstructionsCtrl.text;
                    _notify();
                  }
                },
                backgroundColor: const Color(0xFFF3F4F6),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionRow(
      int idx, StructuredInstruction inst, InstructionDef def) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: inst.enabled
            ? LinearGradient(colors: [def.bgStart, def.bgEnd])
            : null,
        color: inst.enabled ? null : const Color(0xFFF9FAFB),
        border: Border.all(
            color: inst.enabled ? def.border : _kCreamBorder),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(def.icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(def.titleHe,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: inst.enabled
                              ? def.textPrimary
                              : const Color(0xFF374151),
                        )),
                    Text(def.descHe,
                        style: TextStyle(
                          fontSize: 12,
                          color: inst.enabled
                              ? def.textSecondary
                              : const Color(0xFF9CA3AF),
                        )),
                  ],
                ),
              ),
              Switch(
                value: inst.enabled,
                onChanged: (v) {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _instructions[idx] = StructuredInstruction(
                      id: inst.id,
                      type: inst.type,
                      icon: inst.icon,
                      titleHe: inst.titleHe,
                      enabled: v,
                      duration: inst.duration,
                      color: inst.color,
                    );
                  });
                  _notify();
                },
                activeColor: _kPestGreenLight,
              ),
            ],
          ),
          if (inst.enabled && def.durationOptions != null) ...[
            const SizedBox(height: 8),
            Row(
              children: def.durationOptions!.map((d) {
                final isSelected = inst.duration == d;
                final label = durationLabel(inst.type, d);
                return Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ChoiceChip(
                    label: Text(label, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (_) {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _instructions[idx] = StructuredInstruction(
                          id: inst.id,
                          type: inst.type,
                          icon: inst.icon,
                          titleHe: inst.titleHe,
                          enabled: true,
                          duration: d,
                          color: inst.color,
                        );
                      });
                      _notify();
                    },
                    selectedColor: def.bgStart,
                    checkmarkColor: def.textPrimary,
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
