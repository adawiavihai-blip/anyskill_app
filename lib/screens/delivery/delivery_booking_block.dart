import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/delivery_package_tags.dart';
import '../../constants/delivery_types_catalog.dart';
import '../../constants/delivery_vehicle_types.dart';
import '../../models/delivery_profile.dart';
import '../../services/delivery_booking_service.dart';
import '../../widgets/address_input.dart';

// Scoped dark premium palette — matches the settings block.
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
const _kStatusBlue = Color(0xFF3B82F6);
const _kStatusBlueDeep = Color(0xFF1E40AF);
const _kIndigoMedium = Color(0xFF6366F1);

/// Client-side "שלח עם דני" booking preferences block — rendered on the
/// courier's profile page between About and Service sections.
///
/// Emits a [DeliveryBookingPreferences] + `totalPrice` to the parent on every
/// change. The parent screen (ExpertProfileScreen) persists both to the job
/// document at booking time.
class DeliveryBookingBlock extends StatefulWidget {
  final String expertId;
  final String expertName;
  final DeliveryProfile deliveryProfile;
  final void Function(DeliveryBookingPreferences prefs, double totalPrice)
      onChanged;

  const DeliveryBookingBlock({
    super.key,
    required this.expertId,
    required this.expertName,
    required this.deliveryProfile,
    required this.onChanged,
  });

  @override
  State<DeliveryBookingBlock> createState() => _DeliveryBookingBlockState();
}

class _DeliveryBookingBlockState extends State<DeliveryBookingBlock> {
  // Package
  String _packageType = 'documents';
  final Set<String> _packageTags = {};
  final _descriptionCtrl = TextEditingController();

  // Vehicle
  String _selectedVehicle = 'scooter';
  _AiVehicleResult? _aiResult;
  bool _aiLoading = false;

  // Addresses
  final _pickupAddressCtrl = TextEditingController();
  final _pickupDetailsCtrl = TextEditingController();
  final _deliveryAddressCtrl = TextEditingController();
  final _deliveryDetailsCtrl = TextEditingController();

  // Timing
  String _timing = 'regular'; // immediate | regular | today | scheduled
  DateTime? _scheduledDate;

  // Method
  String _method = 'hand_to_recipient';
  final _instructionsCtrl = TextEditingController();

  // Add-ons
  final Set<String> _addOns = {'photo_gps', 'sms_tracking'};

  // Recipient
  final _recipientNameCtrl = TextEditingController();
  final _recipientPhoneCtrl = TextEditingController();

  // Distance — placeholder (real geocoding is out of scope)
  final double _distanceKm = 8.4;

  @override
  void initState() {
    super.initState();
    // Default to first available delivery type on the courier's profile.
    final available = widget.deliveryProfile.deliveryTypes;
    if (available.isNotEmpty) {
      _packageType = available.first;
    }
    // Default vehicle to the first enabled one on the courier's profile.
    final enabled = widget.deliveryProfile.vehicles.where((v) => v.enabled);
    if (enabled.isNotEmpty) {
      _selectedVehicle = enabled.first.type;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emit();
    });
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _pickupAddressCtrl.dispose();
    _pickupDetailsCtrl.dispose();
    _deliveryAddressCtrl.dispose();
    _deliveryDetailsCtrl.dispose();
    _instructionsCtrl.dispose();
    _recipientNameCtrl.dispose();
    _recipientPhoneCtrl.dispose();
    super.dispose();
  }

  double _addOnPriceTotal() {
    double total = 0;
    for (final id in _addOns) {
      if (id == 'photo_gps') total += 5;
      // sms_tracking is free
    }
    return total;
  }

  double get _totalPrice {
    return DeliveryBookingService.calculateTotal(
      profile: widget.deliveryProfile,
      packageType: _packageType,
      distanceKm: _distanceKm,
      timing: _timing,
      addOnsTotal: _addOnPriceTotal(),
    );
  }

  void _emit() {
    final prefs = DeliveryBookingPreferences(
      packageType: _packageType,
      packageTags: _packageTags.toList(),
      packageDescription: _descriptionCtrl.text,
      selectedVehicle: _selectedVehicle,
      aiRecommendedVehicle: _aiResult?.recommendedVehicle,
      aiSavingsAmount: _aiResult?.savingsAmount,
      aiSavingsMinutes: _aiResult?.savingsMinutes,
      pickupAddress: _pickupAddressCtrl.text,
      pickupDetails: _pickupDetailsCtrl.text,
      deliveryAddress: _deliveryAddressCtrl.text,
      deliveryDetails: _deliveryDetailsCtrl.text,
      distanceKm: _distanceKm,
      timing: _timing,
      scheduledFor: _scheduledDate,
      deliveryMethod: _method,
      specialInstructions: _instructionsCtrl.text,
      addOns: _addOns.toList(),
      recipientName: _recipientNameCtrl.text,
      recipientPhone: _recipientPhoneCtrl.text,
      priceBreakdown: DeliveryBookingService.buildPriceBreakdown(
        profile: widget.deliveryProfile,
        packageType: _packageType,
        distanceKm: _distanceKm,
        timing: _timing,
        addOnsTotal: _addOnPriceTotal(),
      ),
    );
    widget.onChanged(prefs, _totalPrice);
  }

  Future<void> _fetchAiRecommendation() async {
    if (_aiLoading) return;
    setState(() => _aiLoading = true);
    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('recommendVehicleForDelivery');
      final result = await callable.call({
        'packageType': _packageType,
        'distanceKm': _distanceKm,
        'urgency': _timing,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      if (!mounted) return;
      setState(() {
        _aiResult = _AiVehicleResult(
          recommendedVehicle:
              data['recommendedVehicle'] as String? ?? 'scooter',
          savingsAmount: (data['savingsAmount'] as num?)?.toInt() ?? 0,
          savingsMinutes: (data['savingsMinutes'] as num?)?.toInt() ?? 0,
          reason: data['reason'] as String? ?? '',
          confidence: (data['confidence'] as num?)?.toDouble() ?? 0.8,
        );
        if (_aiResult!.confidence > 0.7) {
          _selectedVehicle = _aiResult!.recommendedVehicle;
        }
      });
      _emit();
    } catch (_) {
      // Silently degrade — the card simply won't show.
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsetsDirectional.symmetric(vertical: 12),
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
          PositionedDirectional(
            top: 40,
            end: -40,
            child: _ambientOrb(_kGoldMid.withValues(alpha: 0.18), 220),
          ),
          PositionedDirectional(
            top: 320,
            start: -40,
            child: _ambientOrb(_kIndigoMedium.withValues(alpha: 0.12), 200),
          ),
          PositionedDirectional(
            bottom: 100,
            end: -40,
            child: _ambientOrb(_kStatusGreen.withValues(alpha: 0.08), 200),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _goldSeparator('↓ בלוק "שלח עם ${widget.expertName}" ↓'),
                const SizedBox(height: 18),
                _heroStoryMode(),
                const SizedBox(height: 18),
                _sectionRoute(),
                const SizedBox(height: 14),
                _sectionPackage(),
                const SizedBox(height: 14),
                _sectionTiming(),
                const SizedBox(height: 14),
                _sectionMethod(),
                const SizedBox(height: 14),
                _sectionAddOns(),
                const SizedBox(height: 14),
                _sectionRecipient(),
                const SizedBox(height: 14),
                _sectionRules(),
                const SizedBox(height: 14),
                _sectionSummary(),
                const SizedBox(height: 14),
                _goldSeparator('↑ סוף הבלוק ↑'),
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
            child: Text(text,
                style: const TextStyle(
                  color: _kGoldLight,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                )),
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

  // ── Hero Story ──
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
                color: _kGoldMid.withValues(alpha: 0.5),
                blurRadius: 30,
                spreadRadius: 3,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            widget.expertName.isNotEmpty
                ? widget.expertName.characters.first
                : 'ד',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          alignment: WrapAlignment.center,
          children: [
            _badge('● זמין · 8 דק׳ אליך', _kStatusGreenLight),
            _badge('🎯 94% דיוק', _kStatusBlue),
          ],
        ),
        const SizedBox(height: 10),
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            colors: [Colors.white, _kGoldPale],
          ).createShader(r),
          child: Text(
            'שלח עם ${widget.expertName}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text('הדרך החכמה לשלוח משהו חשוב',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12)),
      ],
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(text,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            )),
      );

  // ── Section 2: Route ──
  Widget _sectionRoute() {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stepHeader('1', 'המסלול שלך', 'איסוף → מסירה'),
          const SizedBox(height: 10),
          _liveMapPreview(),
          const SizedBox(height: 10),
          _labeledAddress(
            label: 'A · איסוף',
            addressCtrl: _pickupAddressCtrl,
            detailsCtrl: _pickupDetailsCtrl,
            color: _kStatusGreen,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 16),
            child: Container(
              height: 16,
              width: 1,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ),
          ),
          _labeledAddress(
            label: 'B · מסירה',
            addressCtrl: _deliveryAddressCtrl,
            detailsCtrl: _deliveryDetailsCtrl,
            color: _kStatusRed,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _kIndigoMedium.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _kIndigoMedium.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              '💡 ${widget.expertName} מכיר את האזור ומבצע שם רוב המשלוחים',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveMapPreview() {
    // Static dark map placeholder — real live map is handled in a future
    // PR via flutter_map once GPS hookup lands (CLAUDE.md Section 26).
    return Container(
      height: 140,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [_kStatusBlueDeep, _kDarkBaseMid],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            top: 8,
            end: 8,
            child: Container(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _kStatusGreen.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: _kStatusGreen.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: _kStatusGreenLight,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text('LIVE',
                      style: TextStyle(
                        color: _kStatusGreenLight,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      )),
                ],
              ),
            ),
          ),
          PositionedDirectional(
            top: 8,
            start: 8,
            child: Container(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_kGoldDark, _kGoldMid],
                ),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🛵',
                      style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                  Text('${widget.expertName} · 600 מ׳ ממך',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      )),
                ],
              ),
            ),
          ),
          Center(
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [_kGoldDark, _kGoldMid],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _kGoldMid.withValues(alpha: 0.5),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.two_wheeler_rounded,
                  color: Colors.white, size: 26),
            ),
          ),
          PositionedDirectional(
            bottom: 8,
            start: 8,
            end: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('📍 ${_distanceKm.toStringAsFixed(1)} ק"מ · ~22 דק׳',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      )),
                  const Text('מתקרב אליך →',
                      style: TextStyle(
                        color: _kGoldLight,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _labeledAddress({
    required String label,
    required TextEditingController addressCtrl,
    required TextEditingController detailsCtrl,
    required Color color,
  }) {
    // Smart two-field autocomplete (city + street+number) in dark theme,
    // matching the rest of this premium-glass card. Combined value
    // round-trips back into `addressCtrl` so submit at line 145 still
    // reads from `.text`.
    final initial = AddressValue.fromCombined(addressCtrl.text);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.25),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          alignment: Alignment.center,
          child: Text(
            label.substring(0, 1),
            style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              AddressInput(
                key: ValueKey('delivery-addr-${label.hashCode}'),
                darkTheme: true,
                dense: true,
                accentColor: color,
                initialCity: initial.city,
                initialStreet: initial.street,
                onChanged: (v) {
                  addressCtrl.text = v.combined;
                  _emit();
                },
              ),
              const SizedBox(height: 6),
              TextField(
                controller: detailsCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: _dark('דירה / קומה / קוד'),
                onChanged: (_) => _emit(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Section 3: Package + AI ──
  Widget _sectionPackage() {
    final types = widget.deliveryProfile.deliveryTypes.isEmpty
        ? kDeliveryTypes.map((e) => e.id).toList()
        : widget.deliveryProfile.deliveryTypes;
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stepHeader('2', 'מה שולחים?', 'AI בוחר את הרכב המתאים'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: types.map((id) {
              final def = findDeliveryType(id);
              if (def == null) return const SizedBox.shrink();
              final selected = _packageType == id;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _packageType = id);
                  _emit();
                  _fetchAiRecommendation();
                },
                child: Container(
                  width: (MediaQuery.of(context).size.width - 36 - 36) / 2 - 4,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                  decoration: BoxDecoration(
                    gradient: selected
                        ? const LinearGradient(
                            colors: [_kGoldDark, _kGoldMid])
                        : null,
                    color: selected
                        ? null
                        : Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? _kGoldLight
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: _kGoldMid.withValues(alpha: 0.3),
                              blurRadius: 16,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(def.icon, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(def.shortHe,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                )),
                            Text(def.weightSpec,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.65),
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
          const SizedBox(height: 12),
          _aiVehicleCard(),
          const SizedBox(height: 12),
          _vehicleSelector(),
          const SizedBox(height: 12),
          Text('✏️ תיאור החבילה',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _descriptionCtrl,
            maxLines: 2,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: _dark('לדוגמה: חוזה חתום לסקירה דחופה'),
            onChanged: (_) => _emit(),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: kPackageTags.map((t) {
              final selected = _packageTags.contains(t.id);
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    if (selected) {
                      _packageTags.remove(t.id);
                    } else {
                      _packageTags.add(t.id);
                    }
                  });
                  _emit();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected
                        ? t.color.withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected
                          ? t.color
                          : Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(t.icon, style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 4),
                      Text(t.titleHe,
                          style: TextStyle(
                            color: selected ? t.color : Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          )),
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

  Widget _aiVehicleCard() {
    if (_aiLoading) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _kGoldMid.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kGoldMid.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(_kGoldMid),
              ),
            ),
            const SizedBox(width: 10),
            const Text('AI בודק את האפשרות הטובה ביותר...',
                style: TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      );
    }
    if (_aiResult == null) return const SizedBox.shrink();
    final r = _aiResult!;
    final vehDef = findDeliveryVehicle(r.recommendedVehicle);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          _kGoldMid.withValues(alpha: 0.18),
          _kGoldDark.withValues(alpha: 0.08),
        ]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kGoldMid.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kGoldDark, _kGoldMid],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Text('🤖', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('AI ממליץ: ${vehDef?.nameHe ?? r.recommendedVehicle}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _kGoldLight.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        "חוסך ₪${r.savingsAmount} + ${r.savingsMinutes} דק'",
                        style: const TextStyle(
                            color: _kGoldLight,
                            fontSize: 9,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(r.reason,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _vehicleSelector() {
    final enabled = widget.deliveryProfile.vehicles.isEmpty
        ? kDeliveryVehicles
        : widget.deliveryProfile.vehicles
            .where((v) => v.enabled)
            .map((v) => findDeliveryVehicle(v.type))
            .whereType<DeliveryVehicleDef>()
            .toList();
    return Row(
      children: enabled.map((def) {
        final selected = _selectedVehicle == def.id;
        return Expanded(
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _selectedVehicle = def.id);
                _emit();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? _kGoldMid.withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? _kGoldMid
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(def.icon, color: Colors.white, size: 22),
                    const SizedBox(height: 4),
                    Text(def.nameHe,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        )),
                    Text('${def.avgMinutesFor5km} דק׳',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 10,
                        )),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Section 4: Timing ──
  Widget _sectionTiming() {
    final a = widget.deliveryProfile.availability;
    final options = <_TimingOption>[
      if (a.immediate.enabled)
        _TimingOption(
          id: 'immediate',
          titleHe: '⚡ עכשיו',
          descHe: "30 דק׳ · +₪${a.immediate.surcharge}",
          color: _kStatusRed,
        ),
      if (a.regularEnabled)
        _TimingOption(
          id: 'regular',
          titleHe: '⏰ תוך שעה',
          descHe: 'סטנדרטי',
          color: _kGoldMid,
        ),
      _TimingOption(
        id: 'today',
        titleHe: '📅 היום',
        descHe: 'בחלון',
        color: _kStatusGreen,
      ),
      if (a.scheduledEnabled)
        _TimingOption(
          id: 'scheduled',
          titleHe: '🗓️ מתוזמן',
          descHe: '⭐ ייחודי',
          color: _kIndigoMedium,
        ),
    ];
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stepHeader('3', 'מתי?', 'בחר תזמון'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((o) {
              final selected = _timing == o.id;
              return GestureDetector(
                onTap: () async {
                  HapticFeedback.lightImpact();
                  if (o.id == 'scheduled') {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate:
                          DateTime.now().add(const Duration(days: 30)),
                    );
                    if (!mounted) return;
                    if (date == null) return;
                    setState(() {
                      _timing = 'scheduled';
                      _scheduledDate = date;
                    });
                  } else {
                    setState(() {
                      _timing = o.id;
                      _scheduledDate = null;
                    });
                  }
                  _emit();
                },
                child: Container(
                  width: (MediaQuery.of(context).size.width - 36 - 36) / 2 - 4,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                  decoration: BoxDecoration(
                    gradient: selected
                        ? LinearGradient(
                            colors: [o.color, o.color.withValues(alpha: 0.7)])
                        : null,
                    color: selected
                        ? null
                        : Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? o.color
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(o.titleHe,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(o.descHe,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 11,
                          )),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          if (_timing == 'scheduled' && _scheduledDate != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kIndigoMedium.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '🗓️ מתוזמן ל-${_scheduledDate!.day}/${_scheduledDate!.month}/${_scheduledDate!.year}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Section 5: Method ──
  Widget _sectionMethod() {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stepHeader('4', 'איך למסור?', 'בחר את הסוג המועדף'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _methodCard(
                  id: 'hand_to_recipient',
                  icon: '🤝',
                  title: 'מסירה ליד',
                  desc: "השליח ימתין 5 דק'",
                  color: _kStatusGreen,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _methodCard(
                  id: 'leave_at_door',
                  icon: '🚪',
                  title: 'השאר בדלת',
                  desc: '+תמונה אוטומטית',
                  color: _kStatusBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('💬 הוראות מיוחדות',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _instructionsCtrl,
            maxLines: 2,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: _dark('קומה 5, משרד 12 - לחדר הקבלה'),
            onChanged: (_) => _emit(),
          ),
        ],
      ),
    );
  }

  Widget _methodCard({
    required String id,
    required String icon,
    required String title,
    required String desc,
    required Color color,
  }) {
    final selected = _method == id;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _method = id);
        _emit();
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(colors: [
                  color.withValues(alpha: 0.3),
                  color.withValues(alpha: 0.1),
                ])
              : null,
          color: selected ? null : Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? color
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 6),
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
            Text(desc,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 10)),
          ],
        ),
      ),
    );
  }

  // ── Section 6: Add-ons (NO insurance per spec) ──
  Widget _sectionAddOns() {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stepHeader('5', 'שדרוגים חכמים', 'לחבילות שחשובות לך'),
          const SizedBox(height: 10),
          _addOnRow(
            id: 'photo_gps',
            icon: '📸',
            title: 'תיעוד + GPS',
            desc: 'תמונה אוטומטית במסירה',
            trailing: '+₪5',
            popular: true,
          ),
          const SizedBox(height: 8),
          _addOnRow(
            id: 'sms_tracking',
            icon: '📞',
            title: 'SMS למקבל עם tracking',
            desc: 'לינק לא דורש אפליקציה',
            trailing: 'חינם',
            popular: false,
          ),
        ],
      ),
    );
  }

  Widget _addOnRow({
    required String id,
    required String icon,
    required String title,
    required String desc,
    required String trailing,
    required bool popular,
  }) {
    final on = _addOns.contains(id);
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          if (on) {
            _addOns.remove(id);
          } else {
            _addOns.add(id);
          }
        });
        _emit();
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: on && popular
              ? LinearGradient(colors: [
                  _kGoldMid.withValues(alpha: 0.2),
                  _kGoldDark.withValues(alpha: 0.08),
                ])
              : null,
          color: on && popular ? null : Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: on
                ? (popular ? _kGoldMid : _kStatusGreen)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      if (popular) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _kGoldMid.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text('✨ פופולרי',
                              style: TextStyle(
                                  color: _kGoldLight,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  Text(desc,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 10)),
                ],
              ),
            ),
            Text(trailing,
                style: TextStyle(
                    color: trailing == 'חינם'
                        ? _kStatusGreenLight
                        : _kGoldLight,
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Icon(
              on ? Icons.check_circle_rounded : Icons.add_circle_outline,
              color: on ? _kStatusGreenLight : Colors.white.withValues(alpha: 0.4),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ── Section 7: Recipient (+ phone masking notice) ──
  Widget _sectionRecipient() {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stepHeader('6', 'איש קשר במסירה', 'יקבל לינק לא דורש אפליקציה'),
          const SizedBox(height: 10),
          TextField(
            controller: _recipientNameCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: _dark('👤 שם מלא של המקבל'),
            onChanged: (_) => _emit(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _recipientPhoneCtrl,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: _dark('📱 מספר טלפון'),
            onChanged: (_) => _emit(),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _kStatusBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: _kStatusBlue.withValues(alpha: 0.3)),
            ),
            child: Text(
              '🔒 המספר שלך מוסתר מ-${widget.expertName} אוטומטית',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 8: Courier rules display ──
  Widget _sectionRules() {
    final rules = widget.deliveryProfile.rules.structuredRules
        .where((r) => r.enabled)
        .toList();
    if (rules.isEmpty &&
        widget.deliveryProfile.rules.customRules.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return _glassCard(
      borderColor: _kIndigoMedium.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stepHeader('📋', 'הכללים של ${widget.expertName}',
              'שקיפות לפני ההזמנה'),
          const SizedBox(height: 8),
          for (final r in rules)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 6),
              child: Row(
                children: [
                  Text(r.icon, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(r.titleHe,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                ],
              ),
            ),
          if (widget.deliveryProfile.rules.customRules.trim().isNotEmpty)
            Container(
              margin: const EdgeInsetsDirectional.only(top: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(widget.deliveryProfile.rules.customRules,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11)),
            ),
        ],
      ),
    );
  }

  // ── Section 9: Summary (sticky-style, but inline for Flutter scroll) ──
  Widget _sectionSummary() {
    final breakdown = DeliveryBookingService.buildPriceBreakdown(
      profile: widget.deliveryProfile,
      packageType: _packageType,
      distanceKm: _distanceKm,
      timing: _timing,
      addOnsTotal: _addOnPriceTotal(),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_kDarkBase, _kDarkBaseMid]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kGoldMid.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
              color: _kGoldMid.withValues(alpha: 0.1),
              blurRadius: 20,
              spreadRadius: 2),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('סך לתשלום',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 11)),
                    const SizedBox(height: 2),
                    ShaderMask(
                      shaderCallback: (r) => const LinearGradient(
                        colors: [Colors.white, _kGoldPale],
                      ).createShader(r),
                      child: Text('₪${_totalPrice.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                          )),
                    ),
                    Text('✓ סופי',
                        style: TextStyle(
                            color: _kStatusGreenLight.withValues(alpha: 0.9),
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('ETA',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 11)),
                  const SizedBox(height: 2),
                  const Text('~30 דק׳',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.08),
          ),
          const SizedBox(height: 10),
          _summaryRow('מחיר בסיס', '₪${breakdown['base']!.toStringAsFixed(0)}'),
          if ((breakdown['immediateSurcharge'] ?? 0) > 0)
            _summaryRow('תוספת חירום',
                '+₪${breakdown['immediateSurcharge']!.toStringAsFixed(0)}'),
          if ((breakdown['addOnsTotal'] ?? 0) > 0)
            _summaryRow('שדרוגים',
                '+₪${breakdown['addOnsTotal']!.toStringAsFixed(0)}'),
          if ((breakdown['kmAfter5'] ?? 0) > 0)
            _summaryRow('תוספת ק"מ אחרי 5',
                '+₪${breakdown['kmAfter5']!.toStringAsFixed(0)}'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _miniTag('📝 ${findDeliveryType(_packageType)?.shortHe ?? ""}'),
              _miniTag('⏰ $_timing'),
              _miniTag('🛵 ${findDeliveryVehicle(_selectedVehicle)?.nameHe ?? ""}'),
              _miniTag(_method == 'hand_to_recipient'
                  ? '🤝 מסירה ליד'
                  : '🚪 בדלת'),
              if (_addOns.contains('photo_gps')) _miniTag('📸 תיעוד'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _trustChip('🔒 תשלום מאובטח'),
              const SizedBox(width: 6),
              _trustChip('📍 מעקב חי'),
              const SizedBox(width: 6),
              _trustChip('↩️ ביטול חינם'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) => Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12)),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _miniTag(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      );

  Widget _trustChip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _kStatusGreen.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _kStatusGreen.withValues(alpha: 0.3)),
        ),
        child: Text(text,
            style: const TextStyle(
                color: _kStatusGreenLight,
                fontSize: 9,
                fontWeight: FontWeight.w700)),
      );

  // ── Shared helpers ──
  Widget _glassCard({required Widget child, Color? borderColor}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor ?? Colors.white.withValues(alpha: 0.08),
          width: borderColor != null ? 1.3 : 1,
        ),
      ),
      child: child,
    );
  }

  Widget _stepHeader(String step, String title, String subtitle) => Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient:
                  const LinearGradient(colors: [_kGoldDark, _kGoldMid]),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(step,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                )),
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
        ],
      );

  InputDecoration _dark(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.35),
          fontSize: 11,
        ),
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
          borderSide: BorderSide(color: _kGoldMid.withValues(alpha: 0.5)),
        ),
      );
}

class _TimingOption {
  final String id;
  final String titleHe;
  final String descHe;
  final Color color;
  const _TimingOption({
    required this.id,
    required this.titleHe,
    required this.descHe,
    required this.color,
  });
}

class _AiVehicleResult {
  final String recommendedVehicle;
  final int savingsAmount;
  final int savingsMinutes;
  final String reason;
  final double confidence;
  const _AiVehicleResult({
    required this.recommendedVehicle,
    required this.savingsAmount,
    required this.savingsMinutes,
    required this.reason,
    required this.confidence,
  });
}

/// Booking preferences captured in the delivery block — saved on the job
/// doc as `jobs/{id}.deliveryPreferences`.
class DeliveryBookingPreferences {
  final String packageType;
  final List<String> packageTags;
  final String packageDescription;
  final String selectedVehicle;
  final String? aiRecommendedVehicle;
  final int? aiSavingsAmount;
  final int? aiSavingsMinutes;
  final String pickupAddress;
  final String pickupDetails;
  final String deliveryAddress;
  final String deliveryDetails;
  final double distanceKm;
  final String timing;
  final DateTime? scheduledFor;
  final String deliveryMethod;
  final String specialInstructions;
  final List<String> addOns;
  final String recipientName;
  final String recipientPhone;
  final Map<String, double> priceBreakdown;

  const DeliveryBookingPreferences({
    required this.packageType,
    required this.packageTags,
    required this.packageDescription,
    required this.selectedVehicle,
    this.aiRecommendedVehicle,
    this.aiSavingsAmount,
    this.aiSavingsMinutes,
    required this.pickupAddress,
    required this.pickupDetails,
    required this.deliveryAddress,
    required this.deliveryDetails,
    required this.distanceKm,
    required this.timing,
    this.scheduledFor,
    required this.deliveryMethod,
    required this.specialInstructions,
    required this.addOns,
    required this.recipientName,
    required this.recipientPhone,
    required this.priceBreakdown,
  });

  Map<String, dynamic> toMap() => {
        'packageType': packageType,
        'packageTags': packageTags,
        'packageDescription': packageDescription,
        'selectedVehicle': selectedVehicle,
        if (aiRecommendedVehicle != null)
          'aiRecommendedVehicle': aiRecommendedVehicle,
        if (aiSavingsAmount != null) 'aiSavingsAmount': aiSavingsAmount,
        if (aiSavingsMinutes != null) 'aiSavingsMinutes': aiSavingsMinutes,
        'pickupAddress': {
          'address': pickupAddress,
          'details': pickupDetails,
        },
        'deliveryAddress': {
          'address': deliveryAddress,
          'details': deliveryDetails,
        },
        'distanceKm': distanceKm,
        'timing': timing,
        if (scheduledFor != null) 'scheduledFor': scheduledFor,
        'deliveryMethod': deliveryMethod,
        'specialInstructions': specialInstructions,
        'addOns': addOns,
        'recipient': {
          'name': recipientName,
          'phone': recipientPhone,
          'phoneVerified': true,
        },
        'priceBreakdown': priceBreakdown,
      };
}
