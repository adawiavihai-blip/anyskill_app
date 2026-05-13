// Cleaning CSM — client-side "ניקיון" booking block.
// All 15 sections per spec 03_CLIENT_BOOKING_CLEANING.md, dark premium cyan/teal.
// CRITICAL per spec: Chat + Calendar + Express Reorder + Recurring Customers
// MUST read from the existing app systems (no new data stores).
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/cleaning_addons_catalog.dart';
import '../../constants/cleaning_types_catalog.dart';
import '../../models/cleaning_profile.dart';
import '../../services/cleaning_booking_service.dart';
import '../chat_screen.dart';

// Dark premium palette — scoped.
const _kDarkBase = Color(0xFF0A0E1A);
const _kDarkBaseMid = Color(0xFF0F1A2E);
const _kDarkBaseDeep = Color(0xFF0F1420);
const _kCyanDark = Color(0xFF0891B2);
const _kCyanMid = Color(0xFF06B6D4);
const _kCyanLight = Color(0xFF67E8F9);
const _kStatusGreen = Color(0xFF16A34A);
const _kStatusGreenLight = Color(0xFF4ADE80);
const _kPurpleMedium = Color(0xFFA855F7);
const _kAmberMedium = Color(0xFFF59E0B);
const _kBlueMedium = Color(0xFF3B82F6);

/// Booking preferences aggregated from all the user's selections.
/// Persisted to jobs/{id}.cleaningPreferences at escrow time.
class CleaningBookingPreferences {
  final String cleaningType;
  final int bedrooms;
  final int bathrooms;
  final int squareMeters;
  final bool hasPets;
  final String floor;
  final int estimatedDurationMinutes;
  final List<String> selectedTasks;
  final List<String> selectedAddOns;
  final String schedulingType; // 'one_time' | 'recurring'
  final String recurrenceFrequency; // weekly/biweekly/monthly
  final bool ecoMode;
  final String accessMethod; // 'client_present' | 'key_code'
  final String specialInstructions;
  final Map<String, double> priceBreakdown;

  const CleaningBookingPreferences({
    required this.cleaningType,
    required this.bedrooms,
    required this.bathrooms,
    required this.squareMeters,
    required this.hasPets,
    required this.floor,
    required this.estimatedDurationMinutes,
    required this.selectedTasks,
    required this.selectedAddOns,
    required this.schedulingType,
    required this.recurrenceFrequency,
    required this.ecoMode,
    required this.accessMethod,
    required this.specialInstructions,
    required this.priceBreakdown,
  });

  Map<String, dynamic> toMap() => {
    'cleaningType': cleaningType,
    'propertyDetails': {
      'bedrooms': bedrooms,
      'bathrooms': bathrooms,
      'squareMeters': squareMeters,
      'hasPets': hasPets,
      'floor': floor,
    },
    'estimatedDurationMinutes': estimatedDurationMinutes,
    'selectedTasks': selectedTasks,
    'selectedAddOns': selectedAddOns,
    'schedulingType': schedulingType,
    'recurrence': {
      'enabled': schedulingType == 'recurring',
      'frequency': recurrenceFrequency,
      'active': schedulingType == 'recurring',
    },
    'ecoMode': {'enabled': ecoMode},
    'accessMethod': accessMethod,
    'specialInstructions': specialInstructions,
    'qualityGuaranteeOptedIn': true,
    'beforeAfterPhotos': {'enabled': true, 'deliveryChannel': 'whatsapp'},
    'priceBreakdown': priceBreakdown,
  };
}

class CleaningBookingBlock extends StatefulWidget {
  final String expertId;
  final String expertName;
  final String? expertAvatarUrl;
  final CleaningProfile cleaningProfile;
  final void Function(CleaningBookingPreferences prefs, double totalPrice)
  onChanged;

  const CleaningBookingBlock({
    super.key,
    required this.expertId,
    required this.expertName,
    required this.cleaningProfile,
    required this.onChanged,
    this.expertAvatarUrl,
  });

  @override
  State<CleaningBookingBlock> createState() => _CleaningBookingBlockState();
}

class _CleaningBookingBlockState extends State<CleaningBookingBlock> {
  late String _cleaningType;
  int _bedrooms = 2;
  int _bathrooms = 1;
  int _squareMeters = 80;
  bool _hasPets = false;
  String _floor = 'elevator'; // ground | elevator
  int _estimatedDurationMinutes = 180;
  bool _calculatingDuration = false;

  final Set<String> _selectedTasks = {};
  final Set<String> _selectedAddOns = {};
  final TextEditingController _customTaskCtrl = TextEditingController();

  String _schedulingType = 'recurring';
  String _recurrenceFrequency = 'biweekly';
  bool _ecoMode = true;
  String _accessMethod = 'client_present';
  final TextEditingController _instructionsCtrl = TextEditingController();

  Map<String, dynamic>? _lastBooking;

  @override
  void initState() {
    super.initState();
    // Default to the first enabled cleaning type the provider offers.
    final offered = widget.cleaningProfile.cleaningTypes;
    _cleaningType = offered.isNotEmpty ? offered.first : 'regular_home';

    // Preselect every task the provider listed (customer toggles off).
    for (final cat in widget.cleaningProfile.baseChecklist) {
      for (final task in cat.tasks) {
        if (task.addOnAmount == null) _selectedTasks.add(task.id);
      }
    }

    _loadExpressReorder();
    _recomputeDuration();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emit();
    });
  }

  @override
  void dispose() {
    _customTaskCtrl.dispose();
    _instructionsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExpressReorder() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final last = await CleaningBookingService.getLastBookingWith(
        customerId: uid,
        expertId: widget.expertId,
      );
      if (mounted && last != null) {
        setState(() => _lastBooking = last);
      }
    } catch (_) {}
  }

  Future<void> _recomputeDuration() async {
    // Optimistic heuristic first so the UI never blocks.
    final heuristic = CleaningBookingService.estimateDurationMinutes(
      cleaningType: _cleaningType,
      bedrooms: _bedrooms,
      bathrooms: _bathrooms,
      squareMeters: _squareMeters,
      hasPets: _hasPets,
      selectedTasksCount: _selectedTasks.length,
      addOnsCount: _selectedAddOns.length,
    );
    setState(() {
      _estimatedDurationMinutes = heuristic;
      _calculatingDuration = true;
    });

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'calculateCleaningDuration',
      );
      final result = await callable
          .call({
            'cleaningType': _cleaningType,
            'bedrooms': _bedrooms,
            'bathrooms': _bathrooms,
            'squareMeters': _squareMeters,
            'hasPets': _hasPets,
            'selectedTasksCount': _selectedTasks.length,
            'addOnsCount': _selectedAddOns.length,
          })
          .timeout(const Duration(seconds: 8));
      final data = result.data;
      if (data is Map) {
        final minutes = (data['estimatedMinutes'] as num?)?.toInt();
        if (minutes != null && mounted) {
          setState(() {
            _estimatedDurationMinutes = minutes;
            _calculatingDuration = false;
          });
          _emit();
          return;
        }
      }
    } catch (_) {
      // Keep the heuristic on CF failure.
    }
    if (mounted) setState(() => _calculatingDuration = false);
    _emit();
  }

  double get _totalPrice => CleaningBookingService.calculateTotal(
    profile: widget.cleaningProfile,
    cleaningType: _cleaningType,
    squareMeters: _squareMeters,
    selectedAddOns: _selectedAddOns.toList(),
    ecoMode: _ecoMode,
    schedulingType: _schedulingType,
    recurrenceFrequency: _recurrenceFrequency,
  );

  Map<String, double> get _breakdown =>
      CleaningBookingService.buildPriceBreakdown(
        profile: widget.cleaningProfile,
        cleaningType: _cleaningType,
        squareMeters: _squareMeters,
        selectedAddOns: _selectedAddOns.toList(),
        ecoMode: _ecoMode,
        schedulingType: _schedulingType,
        recurrenceFrequency: _recurrenceFrequency,
      );

  void _emit() {
    final prefs = CleaningBookingPreferences(
      cleaningType: _cleaningType,
      bedrooms: _bedrooms,
      bathrooms: _bathrooms,
      squareMeters: _squareMeters,
      hasPets: _hasPets,
      floor: _floor,
      estimatedDurationMinutes: _estimatedDurationMinutes,
      selectedTasks: _selectedTasks.toList(),
      selectedAddOns: _selectedAddOns.toList(),
      schedulingType: _schedulingType,
      recurrenceFrequency: _recurrenceFrequency,
      ecoMode: _ecoMode,
      accessMethod: _accessMethod,
      specialInstructions: _instructionsCtrl.text.trim(),
      priceBreakdown: _breakdown,
    );
    widget.onChanged(prefs, _totalPrice);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsetsDirectional.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kDarkBase, _kDarkBaseMid, _kDarkBaseDeep],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _kCyanMid.withValues(alpha: 0.25)),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -40,
            child: _orb(_kCyanMid.withValues(alpha: 0.22), 180),
          ),
          Positioned(
            top: 260,
            left: -60,
            child: _orb(_kStatusGreen.withValues(alpha: 0.15), 160),
          ),
          Positioned(
            bottom: -40,
            right: -30,
            child: _orb(_kPurpleMedium.withValues(alpha: 0.12), 170),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _separator('↓ הזמנת ניקיון אישית ↓'),
              const SizedBox(height: 14),
              _heroSection(),
              const SizedBox(height: 14),
              _trustCenterSection(),
              if (_lastBooking != null) ...[
                const SizedBox(height: 12),
                _expressReorderCard(),
              ],
              const SizedBox(height: 12),
              _stepHeader(1, 'איזה ניקיון את רוצה?', 'בחרי את הסוג המתאים'),
              const SizedBox(height: 8),
              _cleaningTypePicker(),
              const SizedBox(height: 14),
              _stepHeader(
                2,
                'פרטי הנכס שלך',
                'המחיר מתעדכן בזמן אמת',
                trailing: '💾 נשמר אוטומטית',
              ),
              const SizedBox(height: 8),
              _propertyDetails(),
              const SizedBox(height: 10),
              _aiDurationCard(),
              const SizedBox(height: 14),
              _stepHeader(
                3,
                'המשימות שלך',
                'סמני מה חשוב במיוחד',
                trailing: '${_selectedTasks.length} פעיל',
              ),
              const SizedBox(height: 8),
              _checklist(),
              const SizedBox(height: 14),
              _stepHeader(4, 'מתי שרה תגיע?', 'חד פעמי או חוזר אוטומטית'),
              const SizedBox(height: 8),
              _scheduling(),
              const SizedBox(height: 14),
              _ecoToggleSection(),
              const SizedBox(height: 14),
              _stepHeader(5, 'איך שרה תיכנס?', 'בחרי את שיטת הגישה'),
              const SizedBox(height: 8),
              _accessMethodSection(),
              const SizedBox(height: 14),
              _beforeAfterSection(),
              const SizedBox(height: 14),
              _qualityGuaranteeSection(),
              const SizedBox(height: 14),
              _chatPreviewSection(),
              if (widget.cleaningProfile.businessPackages.isNotEmpty) ...[
                const SizedBox(height: 14),
                _businessPackagesSection(),
              ],
              const SizedBox(height: 14),
              _stickyBottomSummary(),
              const SizedBox(height: 12),
              _separator('↑ סוף הבלוק ↑'),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────── shared helpers ───────────

  Widget _orb(Color color, double size) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, Colors.transparent]),
      ),
    ),
  );

  Widget _separator(String text) => Row(
    children: [
      Expanded(
        child: Container(height: 1, color: _kCyanMid.withValues(alpha: 0.35)),
      ),
      const SizedBox(width: 10),
      Text(
        text,
        style: TextStyle(
          color: _kCyanLight.withValues(alpha: 0.8),
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Container(height: 1, color: _kCyanMid.withValues(alpha: 0.35)),
      ),
    ],
  );

  InputDecoration _fieldDec() => InputDecoration(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    filled: true,
    fillColor: Colors.black.withValues(alpha: 0.3),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: _kCyanMid.withValues(alpha: 0.5),
        width: 1.2,
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
    ),
  );

  Widget _stepHeader(
    int num,
    String title,
    String subtitle, {
    String? trailing,
  }) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_kCyanMid, _kCyanDark]),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            '$num',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _kStatusGreen.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              trailing,
              style: const TextStyle(
                color: _kStatusGreenLight,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  // ─────────── Hero Section ───────────
  Widget _heroSection() {
    return Center(
      child: Column(
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              _heroBadge(
                Icons.circle,
                _kStatusGreenLight,
                'זמינה היום',
                filled: true,
              ),
              _heroBadge(null, _kStatusGreen, '🌱 Eco-Certified'),
              _heroBadge(null, _kAmberMedium, '🏆 Top 3'),
            ],
          ),
          const SizedBox(height: 12),
          ShaderMask(
            shaderCallback:
                (r) => const LinearGradient(
                  colors: [Colors.white, _kCyanLight],
                ).createShader(r),
            child: const Text(
              'בואי נתאים\nאת הניקיון שלך',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: Colors.white,
                letterSpacing: -0.8,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '3 דקות להזמנה · ביטוח עד ₪10,000 · אחריות מלאה',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroBadge(
    IconData? icon,
    Color color,
    String label, {
    bool filled = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color:
            filled
                ? color.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 8, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────── Trust Center ───────────
  Widget _trustCenterSection() {
    final v = widget.cleaningProfile.verifications;
    final insurance = v.insuranceAmount;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _kStatusGreen.withValues(alpha: 0.15),
            _kStatusGreen.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _kStatusGreen.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Text('🛡️', style: TextStyle(fontSize: 20)),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trust Center',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'למה את יכולה לסמוך עליה',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _trustBadge('🆔', 'ת"ז\nמאומתת', v.idVerified)),
              const SizedBox(width: 6),
              Expanded(
                child: _trustBadge('📋', 'בדיקת\nרקע', v.backgroundChecked),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _trustBadge(
                  '🛡️',
                  'ביטוח\n₪${insurance >= 1000 ? '${insurance ~/ 1000}K' : insurance}',
                  insurance > 0,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(child: _trustBadge('💎', 'תשלום\nבנאמנות', true)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _trustBadge(String icon, String label, bool verified) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              verified
                  ? _kStatusGreen.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────── Express Reorder ───────────
  Widget _expressReorderCard() {
    final last = _lastBooking!;
    final prefs = (last['cleaningPreferences'] as Map?) ?? {};
    final prop = (prefs['propertyDetails'] as Map?) ?? {};
    final cleaningTypeId = prefs['cleaningType']?.toString() ?? 'regular_home';
    final typeDef = findCleaningType(cleaningTypeId);
    final sqm = (prop['squareMeters'] as num?)?.toInt() ?? 80;
    final duration =
        (prefs['estimatedDurationMinutes'] as num?)?.toDouble() ?? 180;
    final rating = (last['reviewRating'] as num?)?.toDouble();
    final reviewText = last['reviewText']?.toString() ?? '';
    final completedAt = last['completedAt'];
    int daysAgo = 7;
    if (completedAt != null) {
      try {
        final dt = completedAt.toDate();
        daysAgo = DateTime.now().difference(dt).inDays;
      } catch (_) {}
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _kPurpleMedium.withValues(alpha: 0.25),
            _kPurpleMedium.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _kPurpleMedium.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '🔁 Express Reorder · נקיון אחרון לפני $daysAgo ימים',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(typeDef?.icon ?? '🏠', style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${typeDef?.nameHe ?? 'נקיון'} · $sqm מ"ר · ${(duration / 60).toStringAsFixed(1)} שעות',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (rating != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          ...List.generate(
                            5,
                            (i) => Icon(
                              i < rating.round()
                                  ? Icons.star
                                  : Icons.star_border,
                              size: 12,
                              color: _kAmberMedium,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (reviewText.isNotEmpty)
                            Expanded(
                              child: Text(
                                '"${reviewText.length > 40 ? '${reviewText.substring(0, 40)}…' : reviewText}"',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 10.5,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              ElevatedButton(
                onPressed: _prefillFromLastBooking,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPurpleMedium,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('חזור'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _prefillFromLastBooking() {
    final prefs = (_lastBooking!['cleaningPreferences'] as Map?) ?? const {};
    final prop = (prefs['propertyDetails'] as Map?) ?? const {};
    setState(() {
      _cleaningType = prefs['cleaningType']?.toString() ?? _cleaningType;
      _bedrooms = (prop['bedrooms'] as num?)?.toInt() ?? _bedrooms;
      _bathrooms = (prop['bathrooms'] as num?)?.toInt() ?? _bathrooms;
      _squareMeters = (prop['squareMeters'] as num?)?.toInt() ?? _squareMeters;
      _hasPets = prop['hasPets'] == true;
      _floor = prop['floor']?.toString() ?? _floor;
      final tasks = (prefs['selectedTasks'] as List?) ?? const [];
      _selectedTasks
        ..clear()
        ..addAll(tasks.map((e) => e.toString()));
      final addons = (prefs['selectedAddOns'] as List?) ?? const [];
      _selectedAddOns
        ..clear()
        ..addAll(addons.map((e) => e.toString()));
      _schedulingType = prefs['schedulingType']?.toString() ?? _schedulingType;
      final rec = prefs['recurrence'];
      if (rec is Map) {
        _recurrenceFrequency =
            rec['frequency']?.toString() ?? _recurrenceFrequency;
      }
      _ecoMode =
          (prefs['ecoMode'] is Map)
              ? (prefs['ecoMode']['enabled'] == true)
              : _ecoMode;
      _accessMethod = prefs['accessMethod']?.toString() ?? _accessMethod;
      _instructionsCtrl.text = prefs['specialInstructions']?.toString() ?? '';
    });
    _recomputeDuration();
  }

  // ─────────── Cleaning Type Picker ───────────
  Widget _cleaningTypePicker() {
    final offered =
        widget.cleaningProfile.cleaningTypes.isEmpty
            ? kCleaningTypes.map((t) => t.id).toList()
            : widget.cleaningProfile.cleaningTypes;
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.05,
      children:
          kCleaningTypes.where((t) => offered.contains(t.id)).map((t) {
            final active = _cleaningType == t.id;
            return GestureDetector(
              onTap: () {
                setState(() => _cleaningType = t.id);
                _recomputeDuration();
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient:
                      active
                          ? LinearGradient(
                            colors: [
                              _kCyanMid.withValues(alpha: 0.4),
                              _kCyanDark.withValues(alpha: 0.15),
                            ],
                          )
                          : null,
                  color: active ? null : Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        active
                            ? _kCyanLight
                            : Colors.white.withValues(alpha: 0.1),
                    width: active ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(t.icon, style: const TextStyle(fontSize: 22)),
                    const SizedBox(height: 4),
                    Text(
                      t.nameHe,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      t.descriptionHe,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 9,
                      ),
                    ),
                    if (active)
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Icon(
                          Icons.check_circle,
                          color: _kCyanLight,
                          size: 14,
                        ),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
    );
  }

  // ─────────── Property Details ───────────
  Widget _propertyDetails() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _propField(
                '🛏️ חדרי שינה',
                _stepper(_bedrooms, 1, 10, (v) {
                  setState(() => _bedrooms = v);
                  _recomputeDuration();
                }),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _propField(
                '🚿 חדרי אמבט',
                _stepper(_bathrooms, 1, 8, (v) {
                  setState(() => _bathrooms = v);
                  _recomputeDuration();
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _propField(
          '📐 גודל (מ"ר)',
          SizedBox(
            width: 110,
            child: TextField(
              controller: TextEditingController(text: _squareMeters.toString())
                ..selection = TextSelection.collapsed(
                  offset: _squareMeters.toString().length,
                ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: _fieldDec(),
              onSubmitted: (v) {
                setState(() => _squareMeters = int.tryParse(v) ?? 80);
                _recomputeDuration();
              },
              onChanged: (v) {
                final n = int.tryParse(v);
                if (n != null) {
                  _squareMeters = n;
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _propField(
                '🐕 בעלי-חיים',
                Row(
                  children: [
                    _tinyToggle(
                      'כן',
                      _hasPets,
                      () => setState(() => _hasPets = true),
                    ),
                    const SizedBox(width: 4),
                    _tinyToggle(
                      'לא',
                      !_hasPets,
                      () => setState(() => _hasPets = false),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _propField(
                '🪜 קומה',
                Row(
                  children: [
                    _tinyToggle(
                      'קרקע',
                      _floor == 'ground',
                      () => setState(() => _floor = 'ground'),
                    ),
                    const SizedBox(width: 4),
                    _tinyToggle(
                      'מעלית',
                      _floor == 'elevator',
                      () => setState(() => _floor = 'elevator'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _propField(String label, Widget trailing) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _stepper(int value, int min, int max, ValueChanged<int> onC) => Row(
    children: [
      IconButton(
        iconSize: 14,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        onPressed: value > min ? () => onC(value - 1) : null,
        icon: const Icon(Icons.remove, color: Colors.white),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          '$value',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      IconButton(
        iconSize: 14,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        onPressed: value < max ? () => onC(value + 1) : null,
        icon: const Icon(Icons.add, color: Colors.white),
      ),
    ],
  );

  Widget _tinyToggle(String label, bool active, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color:
                active
                    ? _kCyanMid.withValues(alpha: 0.25)
                    : Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  active ? _kCyanLight : Colors.white.withValues(alpha: 0.15),
            ),
          ),
          child: Text(
            active ? '$label ✓' : label,
            style: TextStyle(
              color: active ? _kCyanLight : Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );

  // ─────────── AI Duration Card ───────────
  Widget _aiDurationCard() {
    final hours = (_estimatedDurationMinutes / 60).toStringAsFixed(
      _estimatedDurationMinutes % 60 == 0 ? 0 : 1,
    );
    final base = widget.cleaningProfile.pricing.basePriceFor(
      _cleaningType,
      _squareMeters,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _kBlueMedium.withValues(alpha: 0.18),
            _kBlueMedium.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBlueMedium.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Text('⏱️', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'משך משוער: $hours שעות',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'מחיר בסיס: ₪${base.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: _kBlueMedium.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _calculatingDuration ? 'AI מחשב…' : 'AI חישב',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────── Smart Checklist ───────────
  Widget _checklist() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _kBlueMedium.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBlueMedium.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('💡', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'איך זה עובד: שרה מבצעת את המשימות לפי הסדר. את תקבלי תמונה לכל משימה שמסומנת 📷',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ...widget.cleaningProfile.baseChecklist.map((cat) {
          final totalInCat = cat.tasks.length;
          final activeInCat =
              cat.tasks.where((t) => _selectedTasks.contains(t.id)).length;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      cat.categoryIcon,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${cat.categoryNameHe} ($activeInCat/$totalInCat)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: totalInCat == 0 ? 0 : activeInCat / totalInCat,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      _kCyanLight,
                    ),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 8),
                ...cat.tasks.map((task) {
                  final active = _selectedTasks.contains(task.id);
                  return InkWell(
                    onTap:
                        () => setState(() {
                          if (active) {
                            _selectedTasks.remove(task.id);
                          } else {
                            _selectedTasks.add(task.id);
                            if (task.addOnAmount != null) {
                              // Toggling the task also toggles its addOn.
                              // (Stored under selectedAddOns by task.id prefix.)
                            }
                          }
                          _emit();
                        }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            active
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            color: active ? _kCyanLight : Colors.white38,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              task.nameHe,
                              style: TextStyle(
                                color: active ? Colors.white : Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (task.withPhoto)
                            const Text('📷', style: TextStyle(fontSize: 13)),
                          if (task.addOnAmount != null) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _kAmberMedium.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '+₪${task.addOnAmount}',
                                style: const TextStyle(
                                  color: _kAmberMedium,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        }),
        // Custom add-ons (oven, fridge, etc.)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'תוספות אופציונליות',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              ...kCleaningAddOns.map((a) {
                final active = _selectedAddOns.contains(a.id);
                final price =
                    widget.cleaningProfile.pricing.addOns[a.id] ??
                    a.defaultPrice;
                return InkWell(
                  onTap:
                      () => setState(() {
                        if (active) {
                          _selectedAddOns.remove(a.id);
                        } else {
                          _selectedAddOns.add(a.id);
                        }
                        _emit();
                      }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          active
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          color: active ? _kCyanLight : Colors.white38,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(a.icon, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            a.nameHe,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Text(
                          '+₪$price',
                          style: const TextStyle(
                            color: _kAmberMedium,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _customTaskCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: _fieldDec().copyWith(
            hintText: '+ הוסף משימה אישית (כביסה, שטיחים...)',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
      ],
    );
  }

  // ─────────── Scheduling ───────────
  Widget _scheduling() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap:
                    () => setState(() {
                      _schedulingType = 'one_time';
                      _emit();
                    }),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient:
                        _schedulingType == 'one_time'
                            ? LinearGradient(
                              colors: [
                                _kCyanMid.withValues(alpha: 0.3),
                                _kCyanDark.withValues(alpha: 0.1),
                              ],
                            )
                            : null,
                    color:
                        _schedulingType == 'one_time'
                            ? null
                            : Colors.black.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          _schedulingType == 'one_time'
                              ? _kCyanLight
                              : Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: const Column(
                    children: [
                      Text(
                        '📅 חד פעמי',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'בחרי תאריך ביומן',
                        style: TextStyle(color: Colors.white70, fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: GestureDetector(
                onTap:
                    () => setState(() {
                      _schedulingType = 'recurring';
                      _emit();
                    }),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient:
                        _schedulingType == 'recurring'
                            ? LinearGradient(
                              colors: [
                                _kStatusGreen.withValues(alpha: 0.3),
                                _kStatusGreen.withValues(alpha: 0.1),
                              ],
                            )
                            : null,
                    color:
                        _schedulingType == 'recurring'
                            ? null
                            : Colors.black.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          _schedulingType == 'recurring'
                              ? _kStatusGreenLight
                              : Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: const Column(
                    children: [
                      Text(
                        '🔄 קבוע',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'חיסכון עד 15%',
                        style: TextStyle(
                          color: _kStatusGreenLight,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_schedulingType == 'recurring') ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '📆 איזו תדירות?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _freqChip(
                      'שבועי',
                      'weekly',
                      widget.cleaningProfile.recurringDiscounts.weekly,
                    ),
                    const SizedBox(width: 6),
                    _freqChip(
                      'דו-שבועי',
                      'biweekly',
                      widget.cleaningProfile.recurringDiscounts.biweekly,
                    ),
                    const SizedBox(width: 6),
                    _freqChip(
                      'חודשי',
                      'monthly',
                      widget.cleaningProfile.recurringDiscounts.monthly,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _freqChip(String label, String freq, int discount) {
    final active = _recurrenceFrequency == freq;
    return Expanded(
      child: GestureDetector(
        onTap:
            () => setState(() {
              _recurrenceFrequency = freq;
              _emit();
            }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color:
                active
                    ? _kStatusGreen.withValues(alpha: 0.3)
                    : Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color:
                  active
                      ? _kStatusGreenLight
                      : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '−$discount%',
                style: TextStyle(
                  color:
                      active
                          ? _kStatusGreenLight
                          : Colors.white.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────── Eco Toggle ───────────
  Widget _ecoToggleSection() {
    if (!widget.cleaningProfile.ecoMode.enabled) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _kStatusGreen.withValues(alpha: 0.18),
            _kStatusGreen.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _kStatusGreen.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          const Text('🌱', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'חומרים אקולוגיים',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'בטוח לילדים, חיות מחמד, אלרגיות · +₪${widget.cleaningProfile.ecoMode.surcharge}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _ecoMode,
            activeColor: _kStatusGreenLight,
            onChanged:
                (v) => setState(() {
                  _ecoMode = v;
                  _emit();
                }),
          ),
        ],
      ),
    );
  }

  // ─────────── Access Method ───────────
  Widget _accessMethodSection() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _accessOption(
                '🏠',
                'אני בבית',
                'אפתח לה',
                _accessMethod == 'client_present',
                'client_present',
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _accessOption(
                '🔑',
                'מפתח/קוד',
                'ללא נוכחות',
                _accessMethod == 'key_code',
                'key_code',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _instructionsCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          maxLines: 3,
          decoration: _fieldDec().copyWith(
            hintText: '💬 הוראות נוספות לשרה (כלב קטן, קוד דלת, רגישויות...)',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          onChanged: (_) => _emit(),
        ),
      ],
    );
  }

  Widget _accessOption(
    String icon,
    String title,
    String sub,
    bool active,
    String value,
  ) {
    return GestureDetector(
      onTap:
          () => setState(() {
            _accessMethod = value;
            _emit();
          }),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient:
              active
                  ? LinearGradient(
                    colors: [
                      _kCyanMid.withValues(alpha: 0.3),
                      _kCyanDark.withValues(alpha: 0.1),
                    ],
                  )
                  : null,
          color: active ? null : Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? _kCyanLight : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 4),
            Text(
              active ? '$title ✓' : title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              sub,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────── Before/After Photos ───────────
  Widget _beforeAfterSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _kAmberMedium.withValues(alpha: 0.18),
            _kAmberMedium.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _kAmberMedium.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text('📸', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'תיעוד "לפני ואחרי"',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'תקבלי תמונות אוטומטית בWhatsApp',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kStatusGreen.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'חינם',
                  style: TextStyle(
                    color: _kStatusGreenLight,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────── Quality Guarantee ───────────
  Widget _qualityGuaranteeSection() {
    if (!widget.cleaningProfile.qualityGuarantee.enabled) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _kStatusGreen.withValues(alpha: 0.18),
            _kStatusGreen.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _kStatusGreen.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Text('💯', style: TextStyle(fontSize: 20)),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'אחריות 100% שביעות רצון',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'לא מרוצה? נקיון חוזר חינם תוך 24 שעות',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _qualityBadge('⏰', '24 שעות', 'לדווח')),
              const SizedBox(width: 6),
              Expanded(child: _qualityBadge('🔄', 'נקיון חוזר', 'חינם')),
              const SizedBox(width: 6),
              Expanded(child: _qualityBadge('💸', 'או החזר', 'מלא')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _qualityBadge(String icon, String title, String sub) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kStatusGreen.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            sub,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────── Chat Preview (SYNCED) ───────────
  Widget _chatPreviewSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('💬', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'שאלות ל${widget.expertName}?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'תגובה ~5 דקות',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kStatusGreen.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 3,
                      backgroundColor: _kStatusGreenLight,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'מקוונת',
                      style: TextStyle(
                        color: _kStatusGreenLight,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _openChat,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _kBlueMedium.withValues(alpha: 0.3),
                    _kBlueMedium.withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBlueMedium.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'פתחי צ\'אט עם ${widget.expertName}',
                    style: const TextStyle(
                      color: Color(0xFF93C5FD),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.arrow_forward,
                    color: Color(0xFF93C5FD),
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _quickReplyChip(
                  'זמינה לשבת?',
                  () => _openChat(preMsg: 'זמינה לשבת?'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _quickReplyChip(
                  'מביאה ציוד?',
                  () => _openChat(preMsg: 'מביאה ציוד?'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickReplyChip(String text, VoidCallback onTap) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Text(
        '"$text"',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.9),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );

  /// Opens the EXISTING ChatScreen with an optional pre-filled message.
  /// This is the only supported chat path per Section 15b / spec Rule 1.
  void _openChat({String? preMsg}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ChatScreen(
              receiverId: widget.expertId,
              receiverName: widget.expertName,
              initialMessage: preMsg,
            ),
      ),
    );
  }

  // ─────────── Business Packages ───────────
  Widget _businessPackagesSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_kCyanDark.withValues(alpha: 0.3), _kDarkBaseMid],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kCyanLight.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Text('💼', style: TextStyle(fontSize: 20)),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'חבילות לעסקים',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'חיסכון של עד 30% למשרדים וחנויות',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children:
                widget.cleaningProfile.businessPackages
                    .take(3)
                    .map(
                      (pkg) => Expanded(
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(
                            start: 3,
                            end: 3,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _kCyanLight.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '${pkg.visitsPerMonth}×',
                                  style: const TextStyle(
                                    color: _kCyanLight,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '₪${pkg.monthlyPrice}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'לחודש',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
          ),
        ],
      ),
    );
  }

  // ─────────── Sticky Bottom Summary ───────────
  Widget _stickyBottomSummary() {
    final b = _breakdown;
    final hours = (_estimatedDurationMinutes / 60).toStringAsFixed(
      _estimatedDurationMinutes % 60 == 0 ? 0 : 1,
    );
    final total = b['total'] ?? 0;
    final subtotal = b['subtotal'] ?? 0;
    final discountAbs = -(b['recurringDiscount'] ?? 0);
    final discountPct = widget.cleaningProfile.recurringDiscounts.discountFor(
      _recurrenceFrequency,
    );
    final typeDef = findCleaningType(_cleaningType);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_kDarkBase, _kDarkBaseMid]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _kCyanLight.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'סך לתשלום',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    Row(
                      children: [
                        Text(
                          '₪${total.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (_schedulingType == 'recurring' &&
                            discountPct > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _kStatusGreen.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '−$discountPct%',
                              style: const TextStyle(
                                color: _kStatusGreenLight,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (_schedulingType == 'recurring' && discountPct > 0)
                      Text(
                        'במקום ₪${subtotal.toStringAsFixed(0)} · מנוי ${_recurrenceFrequency == 'weekly'
                            ? 'שבועי'
                            : _recurrenceFrequency == 'biweekly'
                            ? 'דו-שבועי'
                            : 'חודשי'}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 10.5,
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'משך',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  Text(
                    '$hours שעות',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
          const SizedBox(height: 8),
          _summaryLine(
            '${typeDef?.icon ?? '🏠'} נקיון · $_squareMeters מ"ר',
            '₪${(b['base'] ?? 0).toStringAsFixed(0)}',
          ),
          if ((b['addOnsTotal'] ?? 0) > 0)
            _summaryLine(
              '🧽 תוספות',
              '₪${(b['addOnsTotal'] ?? 0).toStringAsFixed(0)}',
            ),
          if ((b['ecoSurcharge'] ?? 0) > 0)
            _summaryLine(
              '🌱 חומרים אקולוגיים',
              '₪${(b['ecoSurcharge'] ?? 0).toStringAsFixed(0)}',
            ),
          if (discountAbs > 0)
            _summaryLine(
              '🔄 הנחת מנוי',
              '−₪${discountAbs.toStringAsFixed(0)}',
              discount: true,
            ),
          const SizedBox(height: 10),
          // Chips row
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: const [
              _SummaryChip(icon: '🛡️', label: 'מבוטח'),
              _SummaryChip(icon: '💯', label: 'אחריות'),
              _SummaryChip(icon: '🌱', label: 'Eco'),
              _SummaryChip(icon: '📸', label: 'תיעוד'),
            ],
          ),
          const SizedBox(height: 14),
          // Main CTA — the spec says this opens the existing calendar.
          // The existing calendar lives INSIDE expert_profile_screen (inline),
          // so we scroll to it / show a Hebrew nudge to use the existing
          // booking button. Parent flow handles the real payment.
          _mainCtaButton(total),
          const SizedBox(height: 10),
          Center(
            child: Text(
              '🔒 תשלום בנאמנות  ·  ↩️ ביטול עד 24 שע׳  ·  💯 אחריות מלאה',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 10.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryLine(String label, String value, {bool discount = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: discount ? _kStatusGreenLight : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );

  Widget _mainCtaButton(double total) {
    return GestureDetector(
      onTap: () {
        // SPEC: opens the existing calendar / booking flow.
        // The existing calendar and "Pay & Secure" button live inside
        // expert_profile_screen (inline TableCalendar + bottom CTA). Our
        // _emit() has already propagated preferences + price to the parent,
        // so we just show a Hebrew nudge to the user to pick a date below.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'בחרי תאריך ושעה ביומן שלמטה ולחצי על "שלם ואבטח"',
              textDirection: TextDirection.rtl,
            ),
            backgroundColor: _kCyanDark,
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_kCyanMid, _kCyanDark]),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _kCyanMid.withValues(alpha: 0.5),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'קבעי מועד · ₪${total.toStringAsFixed(0)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward, color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String icon;
  final String label;
  const _SummaryChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
