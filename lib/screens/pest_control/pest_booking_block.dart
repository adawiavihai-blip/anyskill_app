import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/pest_control_profile.dart';
import '../../constants/pest_types_catalog.dart';
import '../../constants/pest_treatment_methods.dart';
import '../../constants/pest_structured_instructions.dart';
import '../../services/pest_control_booking_service.dart';

const _kPestGreenDark = Color(0xFF14532D);
const _kPestGreenLight = Color(0xFF15803D);
const _kPestGreenBg = Color(0xFFDCFCE7);
const _kAiBlueDark = Color(0xFF1E3A8A);
const _kAiBlueMedium = Color(0xFF1E40AF);
const _kAiBlueLight = Color(0xFF3B82F6);
const _kAiBlueBg = Color(0xFFEFF6FF);
const _kEmergencyRed = Color(0xFFDC2626);
const _kEmergencyRedDark = Color(0xFFB91C1C);
const _kIndigoMedium = Color(0xFF6366F1);
const _kCreamBorder = Color(0xFFEAE7DF);
const _kDarkPrimary = Color(0xFF1A1A1A);
const _kDarkSecondary = Color(0xFF2D3142);

class PestControlBookingPreferences {
  final String? pestTypeIdentified;
  final Map<String, dynamic>? aiIdentificationData;
  final String? selectedPestType;
  final String urgency;
  final String location;
  final String size;
  final String treatmentMethod;
  final List<String> specialHouseholdMembers;
  final List<Map<String, dynamic>> addOns;
  final String additionalNotes;
  final bool instructionsAcknowledged;
  final DateTime? instructionsAcknowledgedAt;

  const PestControlBookingPreferences({
    this.pestTypeIdentified,
    this.aiIdentificationData,
    this.selectedPestType,
    this.urgency = 'today',
    this.location = 'apartment',
    this.size = 'full_apartment',
    this.treatmentMethod = 'green',
    this.specialHouseholdMembers = const [],
    this.addOns = const [],
    this.additionalNotes = '',
    this.instructionsAcknowledged = false,
    this.instructionsAcknowledgedAt,
  });

  Map<String, dynamic> toMap() => {
        if (pestTypeIdentified != null)
          'pestTypeIdentified': pestTypeIdentified,
        if (aiIdentificationData != null)
          'aiIdentificationData': aiIdentificationData,
        'selectedPestType': selectedPestType,
        'urgency': urgency,
        'location': location,
        'size': size,
        'treatmentMethod': treatmentMethod,
        'specialHouseholdMembers': specialHouseholdMembers,
        'addOns': addOns,
        'additionalNotes': additionalNotes,
        'instructionsAcknowledged': instructionsAcknowledged,
        if (instructionsAcknowledgedAt != null)
          'instructionsAcknowledgedAt':
              instructionsAcknowledgedAt!.toIso8601String(),
      };
}

class PestBookingBlock extends StatefulWidget {
  final PestControlProfile pestProfile;
  final String providerName;
  final String providerId;
  final ValueChanged<PestControlBookingPreferences> onPreferencesChanged;
  final ValueChanged<double> onTotalChanged;

  const PestBookingBlock({
    super.key,
    required this.pestProfile,
    required this.providerName,
    required this.providerId,
    required this.onPreferencesChanged,
    required this.onTotalChanged,
  });

  @override
  State<PestBookingBlock> createState() => _PestBookingBlockState();
}

class _PestBookingBlockState extends State<PestBookingBlock> {
  String? _selectedPestType;
  String _urgency = 'today';
  String _locationKey = 'apartment_3_4_rooms';
  String _treatmentMethod = 'green';
  final List<String> _specialMembers = [];
  final List<Map<String, dynamic>> _selectedAddOns = [
    {'id': 'extended_warranty_6m', 'price': 80, 'nameHe': 'אחריות מורחבת 6 חודשים'},
  ];
  String _notes = '';
  bool _instructionsAcknowledged = false;
  bool _showMoreMethods = false;

  // AI state
  bool _isIdentifying = false;
  Map<String, dynamic>? _aiResult;
  final _notesCtrl = TextEditingController();

  PestControlProfile get _profile => widget.pestProfile;

  @override
  void initState() {
    super.initState();
    if (_profile.treatmentMethods.contains('green')) {
      _treatmentMethod = 'green';
    } else if (_profile.treatmentMethods.isNotEmpty) {
      _treatmentMethod = _profile.treatmentMethods.first;
    }
    _recalculate();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  void _recalculate() {
    final total = PestControlBookingService.calculateTotal(
      profile: _profile,
      locationKey: _locationKey,
      urgency: _urgency,
      addOns: _selectedAddOns,
    );
    widget.onTotalChanged(total);

    widget.onPreferencesChanged(PestControlBookingPreferences(
      pestTypeIdentified: _aiResult?['pestType'] as String?,
      aiIdentificationData: _aiResult,
      selectedPestType: _selectedPestType,
      urgency: _urgency,
      location: _locationKey,
      treatmentMethod: _treatmentMethod,
      specialHouseholdMembers: _specialMembers,
      addOns: _selectedAddOns,
      additionalNotes: _notes,
      instructionsAcknowledged: _instructionsAcknowledged,
      instructionsAcknowledgedAt:
          _instructionsAcknowledged ? DateTime.now() : null,
    ));
  }

  double get _totalPrice => PestControlBookingService.calculateTotal(
        profile: _profile,
        locationKey: _locationKey,
        urgency: _urgency,
        addOns: _selectedAddOns,
      );

  @override
  Widget build(BuildContext context) {
    final hasInstructions =
        _profile.treatmentInstructions.structuredInstructions.isNotEmpty ||
            _profile.treatmentInstructions.customInstructions.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFAF6),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeroCard(),
          const SizedBox(height: 14),
          _buildAiIdentificationCard(),
          if (_aiResult != null) ...[
            const SizedBox(height: 14),
            _buildAiResultCard(),
          ],
          if (hasInstructions) ...[
            const SizedBox(height: 14),
            _buildInstructionsDisplay(),
          ],
          const SizedBox(height: 14),
          _buildSection1LocationUrgency(),
          const SizedBox(height: 14),
          _buildSection2TreatmentType(),
          const SizedBox(height: 14),
          _buildSection3Details(),
          if (_profile.maintenancePackages.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildPackagesDisplay(),
          ],
          const SizedBox(height: 14),
          _buildSummaryBar(),
        ],
      ),
    );
  }

  // ── Hero Card ──────────────────────────────────────────────
  Widget _buildHeroCard() {
    final arrTime = _profile.availability.averageArrivalTime;
    final hasLicense =
        _profile.licenses.any((l) => l.type == 'ministry_environmental_protection' && l.verified);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [_kPestGreenDark, Color(0xFF16A34A)]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('● זמין · $arrTime דק\'',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              if (hasLicense)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _kAiBlueBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('⬢ רישיון משרד הגנ"ס',
                      style: TextStyle(
                          fontSize: 11,
                          color: _kAiBlueMedium,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Center(
            child: Text('בנה את הטיפול שלך',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800)),
          ),
          Center(
            child: Text(
                '3 שלבים פשוטים · ${widget.providerName} יקבל הכל מוכן',
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF6B7280))),
          ),
        ],
      ),
    );
  }

  // ── AI Identification ──────────────────────────────────────
  Widget _buildAiIdentificationCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [_kAiBlueDark, _kAiBlueMedium]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('\u{1F916}', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('לא יודע מה זה?',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    Text('צלם והAI יזהה תוך 2 שניות',
                        style: TextStyle(
                            color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('AI חכם',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isIdentifying)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(color: Colors.white),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _aiButton(
                    icon: Icons.camera_alt,
                    label: 'צלם עכשיו',
                    onTap: () => _identifyPest(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _aiButton(
                    icon: Icons.photo_library,
                    label: 'העלה תמונה',
                    onTap: () => _identifyPest(ImageSource.gallery),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _aiButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(11),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Future<void> _identifyPest(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1200,
        imageQuality: 80,
      );
      if (picked == null || !mounted) return;

      setState(() {
        _isIdentifying = true;
      });

      final bytes = await picked.readAsBytes();
      final base64Image = base64Encode(bytes);

      final callable =
          FirebaseFunctions.instance.httpsCallable('identifyPestFromImage');
      final result = await callable.call({'imageBase64': base64Image});

      if (!mounted) return;

      final data = Map<String, dynamic>.from(result.data as Map);
      setState(() {
        _aiResult = data;
        _isIdentifying = false;
        final pestType = data['pestType'] as String?;
        if (pestType != null && _profile.pestTypes.contains(pestType)) {
          _selectedPestType = pestType;
        }
      });
      HapticFeedback.mediumImpact();
      _recalculate();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isIdentifying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('לא הצלחנו לזהות, אנא בחר ידנית'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
    }
  }

  // ── AI Result Card ─────────────────────────────────────────
  Widget _buildAiResultCard() {
    final pestTypeHe = _aiResult?['pestTypeHe'] as String? ?? 'לא ידוע';
    final confidence =
        ((_aiResult?['confidence'] as num?)?.toDouble() ?? 0) * 100;
    final desc = _aiResult?['description'] as String? ?? '';
    final pestType = _aiResult?['pestType'] as String? ?? '';
    final handles = _profile.pestTypes.contains(pestType);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFFF0FDF4), _kPestGreenBg]),
        border: Border.all(color: const Color(0xFFBBF7D0)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _kPestGreenBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                    child: Text('\u{1F916}',
                        style: TextStyle(fontSize: 24))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pestTypeHe,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    Text('זוהה ע"י AI · ${confidence.toInt()}% התאמה',
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF6B7280))),
                  ],
                ),
              ),
            ],
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(desc,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF374151))),
          ],
          const SizedBox(height: 10),
          if (handles) ...[
            _infoRow(Icons.check_circle, _kPestGreenLight,
                '${widget.providerName} מטפל בסוג זה'),
            if (_profile.treatmentMethods.contains('green'))
              _infoRow(Icons.eco, _kPestGreenLight,
                  'הדברה ירוקה - בטוח לבית שלך'),
            _infoRow(Icons.schedule, _kAiBlueLight,
                'זמין היום · ${_profile.availability.averageArrivalTime} דק\' אליך'),
          ] else
            _infoRow(Icons.warning_amber, const Color(0xFFF59E0B),
                '${widget.providerName} לא מטפל בסוג זה, מומלץ לחפש מדביר אחר'),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF374151))),
          ),
        ],
      ),
    );
  }

  // ── Treatment Instructions Display ─────────────────────────
  Widget _buildInstructionsDisplay() {
    final instructions =
        _profile.treatmentInstructions.structuredInstructions;
    final custom = _profile.treatmentInstructions.customInstructions;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _kIndigoMedium, width: 1.5),
        borderRadius: BorderRadius.circular(20),
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
                    const Text('מה צריך לדעת לפני',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    Text('הוראות מ${widget.providerName} · קרא לפני ההזמנה',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF6B7280))),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('חשוב!',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _kEmergencyRed)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...instructions.map((inst) {
            final def = findInstruction(inst.id);
            if (def == null) return const SizedBox.shrink();
            final durText = durationLabel(inst.type, inst.duration);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [def.bgStart, def.bgEnd]),
                border: Border.all(color: def.border),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(def.icon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          durText.isNotEmpty
                              ? '${def.titleHe} · $durText'
                              : def.titleHe,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: def.textPrimary,
                          ),
                        ),
                        Text(def.descHe,
                            style: TextStyle(
                                fontSize: 12, color: def.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          if (custom.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFAFAFA), Color(0xFFF5F5F5)]),
                borderRadius: BorderRadius.circular(12),
                border: const BorderDirectional(
                  end: BorderSide(color: _kIndigoMedium, width: 3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('\u{1F4AC} הערה אישית מ${widget.providerName}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Divider(height: 1),
                  const SizedBox(height: 6),
                  Text(custom,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF374151))),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() =>
                  _instructionsAcknowledged = !_instructionsAcknowledged);
              _recalculate();
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _instructionsAcknowledged
                    ? _kPestGreenBg
                    : const Color(0xFFF9FAFB),
                border: Border.all(
                    color: _instructionsAcknowledged
                        ? _kPestGreenLight
                        : _kCreamBorder),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    _instructionsAcknowledged
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 22,
                    color: _instructionsAcknowledged
                        ? _kPestGreenDark
                        : const Color(0xFF9CA3AF),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'קראתי והבנתי - אני מאשר את ההוראות',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 1: Location & Urgency ──────────────────────────
  Widget _buildSection1LocationUrgency() {
    return _sectionCard(
      number: '1',
      title: 'איפה ומתי?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('סוג הנכס',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280))),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _locationChip('apartment_3_4_rooms', '\u{1F3E0}', 'דירה 3-4 חדרים'),
              _locationChip('private_house', '\u{1F3E1}', 'בית פרטי'),
              _locationChip('restaurant_small_business', '\u{1F37D}', 'מסעדה / עסק'),
              _locationChip('animal_capture', '\u{1F40D}', 'לכידת בע"ח'),
            ],
          ),
          const SizedBox(height: 14),
          const Text('דחיפות',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280))),
          const SizedBox(height: 6),
          Row(
            children: [
              if (_profile.availability.emergencyService.enabled)
                Expanded(child: _urgencyChip('emergency', '\u{1F6A8}', 'חירום',
                    '+₪${_profile.availability.emergencyService.additionalFee}',
                    _kEmergencyRed, _kEmergencyRedDark)),
              if (_profile.availability.emergencyService.enabled)
                const SizedBox(width: 8),
              Expanded(child: _urgencyChip('today', '\u{26A1}', 'היום', 'אחה"צ',
                  _kDarkPrimary, _kDarkSecondary)),
              const SizedBox(width: 8),
              Expanded(child: _urgencyChip('this_week', '\u{1F4C5}', 'השבוע', '',
                  const Color(0xFF6B7280), const Color(0xFF9CA3AF))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _locationChip(String key, String icon, String label) {
    final isSelected = _locationKey == key;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _locationKey = key);
        _recalculate();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [_kDarkPrimary, _kDarkSecondary])
              : null,
          color: isSelected ? null : Colors.white,
          border: Border.all(
              color: isSelected ? Colors.transparent : _kCreamBorder),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF1A1A2E),
                )),
          ],
        ),
      ),
    );
  }

  Widget _urgencyChip(String value, String icon, String label,
      String sublabel, Color c1, Color c2) {
    final isSelected = _urgency == value;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _urgency = value);
        _recalculate();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(colors: [c1, c2])
              : null,
          color: isSelected ? null : Colors.white,
          border: Border.all(
              color: isSelected ? Colors.transparent : _kCreamBorder),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF1A1A2E),
                )),
            if (sublabel.isNotEmpty)
              Text(sublabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected ? Colors.white70 : const Color(0xFF9CA3AF),
                  )),
          ],
        ),
      ),
    );
  }

  // ── Section 2: Treatment Type ──────────────────────────────
  Widget _buildSection2TreatmentType() {
    final recommended =
        _profile.treatmentMethods.contains('green') ? 'green' : null;
    final methods = _profile.treatmentMethods;
    final mainMethod = recommended ?? (methods.isNotEmpty ? methods.first : null);
    final otherMethods = methods.where((m) => m != mainMethod).toList();

    return _sectionCard(
      number: '2',
      title: 'סוג הטיפול',
      subtitle: recommended != null ? 'AI בחר את הכי מתאים לך' : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mainMethod != null) ...[
            if (recommended != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('\u{2728} הכי מתאים לך',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFD97706))),
                ),
              ),
            _treatmentMethodCard(mainMethod),
          ],
          if (otherMethods.isNotEmpty && !_showMoreMethods) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _showMoreMethods = true),
              child: Text(
                  '+ ראה ${otherMethods.length} שיטות נוספות',
                  style: const TextStyle(
                      fontSize: 13,
                      color: _kPestGreenDark,
                      fontWeight: FontWeight.w600)),
            ),
          ],
          if (_showMoreMethods)
            ...otherMethods.map((m) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _treatmentMethodCard(m),
                )),
        ],
      ),
    );
  }

  Widget _treatmentMethodCard(String methodId) {
    final def = findTreatmentMethod(methodId);
    if (def == null) return const SizedBox.shrink();
    final isSelected = _treatmentMethod == methodId;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _treatmentMethod = methodId);
        _recalculate();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(colors: [_kPestGreenBg, Color(0xFFBBF7D0)])
              : null,
          color: isSelected ? null : Colors.white,
          border: Border.all(
            color: isSelected ? _kPestGreenLight : _kCreamBorder,
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Text(def.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(def.nameHe,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  Text(def.descHe,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF6B7280))),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle,
                  size: 22, color: _kPestGreenLight),
          ],
        ),
      ),
    );
  }

  // ── Section 3: Details ─────────────────────────────────────
  Widget _buildSection3Details() {
    const members = [
      {'id': 'children', 'icon': '\u{1F476}', 'label': 'ילדים'},
      {'id': 'pets', 'icon': '\u{1F415}', 'label': 'חיות מחמד'},
      {'id': 'pregnant', 'icon': '\u{1F930}', 'label': 'בהריון'},
      {'id': 'asthma', 'icon': '\u{1F9F4}', 'label': 'אסתמה'},
      {'id': 'aquarium', 'icon': '\u{1F420}', 'label': 'אקווריום'},
      {'id': 'garden', 'icon': '\u{1F331}', 'label': 'גינה'},
    ];

    return _sectionCard(
      number: '3',
      title: 'פרטים נוספים',
      subtitle: 'אופציונלי · משפר את השירות',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('בני בית מיוחדים (${widget.providerName} יתאים)',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: members.map((m) {
              final id = m['id'] as String;
              final isSelected = _specialMembers.contains(id);
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    if (isSelected) {
                      _specialMembers.remove(id);
                    } else {
                      _specialMembers.add(id);
                    }
                  });
                  _recalculate();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? const LinearGradient(
                            colors: [_kPestGreenBg, Color(0xFFBBF7D0)])
                        : null,
                    color: isSelected ? null : Colors.white,
                    border: Border.all(
                        color: isSelected
                            ? _kPestGreenLight
                            : _kCreamBorder,
                        width: isSelected ? 1.5 : 1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(m['icon']!, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 4),
                      Text(m['label']!,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? _kPestGreenDark
                                : const Color(0xFF374151),
                          )),
                      if (isSelected) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.check,
                            size: 14, color: _kPestGreenDark),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          // Add-on: extended warranty
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFFFAFAF6), Color(0xFFF5F2EC)]),
              border: Border.all(color: _kDarkPrimary, width: 1.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Text('\u{1F6E1}', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('אחריות מורחבת 6 חודשים +₪80',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      Text('חזרה חינם אם המזיק חוזר',
                          style: TextStyle(
                              fontSize: 12, color: Color(0xFF6B7280))),
                    ],
                  ),
                ),
                Checkbox(
                  value: _selectedAddOns.any((a) => a['id'] == 'extended_warranty_6m'),
                  onChanged: (v) {
                    HapticFeedback.lightImpact();
                    setState(() {
                      if (v == true) {
                        _selectedAddOns.add({
                          'id': 'extended_warranty_6m',
                          'price': 80,
                          'nameHe': 'אחריות מורחבת 6 חודשים',
                        });
                      } else {
                        _selectedAddOns.removeWhere(
                            (a) => a['id'] == 'extended_warranty_6m');
                      }
                    });
                    _recalculate();
                  },
                  activeColor: _kPestGreenLight,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'הערות נוספות למדביר...',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onChanged: (v) {
              _notes = v;
              _recalculate();
            },
          ),
        ],
      ),
    );
  }

  // ── Packages Display ───────────────────────────────────────
  Widget _buildPackagesDisplay() {
    final packages = _profile.maintenancePackages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('\u{1F381}', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            const Text('חבילות תחזוקה',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                  'חוסך ${packages.isNotEmpty ? packages.first.discountPercent : 0}%',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _kPestGreenDark)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _packageCard(
                label: 'חד פעמי',
                price:
                    '₪${_profile.basePricing['apartment_3_4_rooms'] ?? 290}',
                sublabel:
                    '${_profile.warrantyAndService.warrantyMonths} חו\' אחריות',
                isPopular: false,
              ),
              ...packages.map((pkg) => _packageCard(
                    label: pkg.nameHe,
                    price: '₪${pkg.pricePerTreatment}',
                    sublabel:
                        'חיסכון ₪${((_profile.basePricing['apartment_3_4_rooms'] ?? 290) - pkg.pricePerTreatment) * pkg.treatmentsCount}',
                    isPopular: true,
                  )),
            ],
          ),
        ),
      ],
    );
  }

  Widget _packageCard({
    required String label,
    required String price,
    required String sublabel,
    required bool isPopular,
  }) {
    return Container(
      width: 140,
      margin: const EdgeInsetsDirectional.only(end: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: isPopular
            ? const LinearGradient(colors: [_kDarkPrimary, _kDarkSecondary])
            : null,
        color: isPopular ? null : Colors.white,
        border: Border.all(
            color: isPopular ? Colors.transparent : _kCreamBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          if (isPopular)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFBBF24),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('פופולרי',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E))),
            ),
          Text(label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isPopular ? Colors.white : const Color(0xFF1A1A2E),
              )),
          const SizedBox(height: 4),
          Text(price,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: isPopular ? Colors.white : const Color(0xFF1A1A2E),
              )),
          const SizedBox(height: 2),
          Text(sublabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: isPopular ? Colors.white70 : const Color(0xFF6B7280),
              )),
        ],
      ),
    );
  }

  // ── Summary Bar ────────────────────────────────────────────
  Widget _buildSummaryBar() {
    final total = _totalPrice;
    final hasInstructions =
        _profile.treatmentInstructions.structuredInstructions.isNotEmpty ||
            _profile.treatmentInstructions.customInstructions.isNotEmpty;
    final canBook = !hasInstructions || _instructionsAcknowledged;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [_kDarkPrimary, _kDarkSecondary]),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('מחיר סופי',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 13)),
                  const Spacer(),
                  const Text('\u{2713} ללא הפתעות',
                      style: TextStyle(
                          color: Colors.white54, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 4),
              Text('₪${total.toInt()}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (_selectedPestType != null)
                    _summaryTag(findPestType(_selectedPestType!)?.icon ?? '',
                        findPestType(_selectedPestType!)?.nameHe ?? ''),
                  _summaryTag(
                      _urgency == 'emergency'
                          ? '\u{1F6A8}'
                          : '\u{26A1}',
                      _urgency == 'emergency'
                          ? 'חירום'
                          : _urgency == 'today'
                              ? 'היום'
                              : 'השבוע'),
                  if (_treatmentMethod == 'green')
                    _summaryTag('\u{1F33F}', 'ירוק'),
                  if (_selectedAddOns.any(
                      (a) => a['id'] == 'extended_warranty_6m'))
                    _summaryTag('\u{1F6E1}', '+6 חו\' אחריות'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (!canBook)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'אנא אשר את ההוראות למעלה כדי להמשיך',
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w500),
            ),
          ),
        const SizedBox(height: 4),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('\u{1F512} תשלום אחרי',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            SizedBox(width: 12),
            Text('\u{1F4CB} דוח דיגיטלי',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            SizedBox(width: 12),
            Text('\u{21A9} ביטול חינם',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          ],
        ),
      ],
    );
  }

  Widget _summaryTag(String icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$icon $label',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500)),
    );
  }

  // ── Helpers ────────────────────────────────────────────────
  Widget _sectionCard({
    required String number,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kCreamBorder),
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
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(number,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    if (subtitle != null)
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF6B7280))),
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
}
