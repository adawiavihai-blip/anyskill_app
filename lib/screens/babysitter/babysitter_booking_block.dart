// Babysitter — client-side booking block (CLAUDE.md §53).
//
// Renders inside expert_profile_screen between the About section and the
// Service Menu. Two responsibilities:
//   1. Display the babysitter's profile (Trust Center + Experience + Services
//      + Certifications + Pricing + Live-billing notice for the parent).
//   2. Collect booking-time inputs (# children, agreed start/end, address +
//      map pin, special instructions) and emit them to the parent.
//
// Wolt-style address picker (per spec): the parent searches an address (free
// text — no Google Places key), then drags a map pin to the exact spot via
// `flutter_map`. The lat/lng + label go onto the job doc as
// `babysitterPreferences.verifiedAddress`. The existing escrow flow charges
// the deposit; the actual GPS check on "Start Job" happens in the
// job-lifecycle layer (NOT here).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/geocoding_service.dart';
import '../../widgets/address_input.dart';
import '../../models/babysitter_profile.dart';
import '../../constants/babysitter_age_groups.dart';
import '../../constants/babysitter_services_catalog.dart';
import '../../services/babysitter_booking_service.dart';
import '../../services/location_service.dart';
import '../../widgets/wolt_tile_layer.dart';

const _kBabyPink = Color(0xFFEC4899);
const _kBabyPinkBg = Color(0xFFFCE7F3);
const _kBabyIndigo = Color(0xFF6366F1);
const _kBabyIndigoBg = Color(0xFFEEF2FF);
const _kBabyGreen = Color(0xFF10B981);
const _kBabyGreenBg = Color(0xFFDCFCE7);
const _kBabyAmber = Color(0xFFF59E0B);
const _kBabyAmberBg = Color(0xFFFEF3C7);
const _kBabyPurple = Color(0xFF8B5CF6);
const _kCardBg = Colors.white;
const _kCreamBorder = Color(0xFFEAE7DF);
const _kBgCream = Color(0xFFFAF7F2);
const _kDarkText = Color(0xFF1A1A2E);
const _kMuted = Color(0xFF6B7280);

class BabysitterVerifiedAddress {
  final String formattedAddress;
  final String apartmentNumber;
  final String accessNotes;
  final double latitude;
  final double longitude;
  final bool pinAdjusted;

  const BabysitterVerifiedAddress({
    required this.formattedAddress,
    this.apartmentNumber = '',
    this.accessNotes = '',
    required this.latitude,
    required this.longitude,
    this.pinAdjusted = false,
  });

  Map<String, dynamic> toMap() => {
        'formattedAddress': formattedAddress,
        'apartmentNumber': apartmentNumber,
        'accessNotes': accessNotes,
        'latitude': latitude,
        'longitude': longitude,
        'pinAdjusted': pinAdjusted,
      };
}

class BabysitterBookingPreferences {
  final int numChildren;
  final List<int> childrenAges; // optional ages in years
  final DateTime agreedStart;
  final DateTime agreedEnd;
  final BabysitterVerifiedAddress? verifiedAddress;
  final String specialInstructions;
  final List<String> allergiesOrNotes;
  final bool isHoliday;
  final Map<String, dynamic> priceBreakdown;

  const BabysitterBookingPreferences({
    required this.numChildren,
    this.childrenAges = const [],
    required this.agreedStart,
    required this.agreedEnd,
    this.verifiedAddress,
    this.specialInstructions = '',
    this.allergiesOrNotes = const [],
    this.isHoliday = false,
    this.priceBreakdown = const {},
  });

  Map<String, dynamic> toMap() => {
        'numChildren': numChildren,
        'childrenAges': childrenAges,
        'agreedStart': agreedStart.toIso8601String(),
        'agreedEnd': agreedEnd.toIso8601String(),
        if (verifiedAddress != null)
          'verifiedAddress': verifiedAddress!.toMap(),
        'specialInstructions': specialInstructions,
        'allergiesOrNotes': allergiesOrNotes,
        'isHoliday': isHoliday,
        'priceBreakdown': priceBreakdown,
      };
}

class BabysitterBookingBlock extends StatefulWidget {
  final BabysitterProfile profile;
  final String providerName;
  final String providerId;
  final ValueChanged<BabysitterBookingPreferences> onPreferencesChanged;
  final ValueChanged<double> onTotalChanged;

  const BabysitterBookingBlock({
    super.key,
    required this.profile,
    required this.providerName,
    required this.providerId,
    required this.onPreferencesChanged,
    required this.onTotalChanged,
  });

  @override
  State<BabysitterBookingBlock> createState() =>
      _BabysitterBookingBlockState();
}

class _BabysitterBookingBlockState extends State<BabysitterBookingBlock> {
  // ── Booking-time inputs ─────────────────────────────────────────────────
  int _numChildren = 1;
  DateTime? _agreedStart;
  DateTime? _agreedEnd;
  BabysitterVerifiedAddress? _verifiedAddress;
  final _instructionsCtrl = TextEditingController();
  bool _isHoliday = false;

  // ── Live preview ────────────────────────────────────────────────────────
  BabysitterBookingPriceBreakdown? _preview;

  @override
  void initState() {
    super.initState();
    _recalculate();
  }

  @override
  void dispose() {
    _instructionsCtrl.dispose();
    super.dispose();
  }

  void _recalculate() {
    if (_agreedStart == null || _agreedEnd == null) {
      setState(() => _preview = null);
      widget.onTotalChanged(0);
      return;
    }
    final bd = BabysitterBookingService.estimate(
      pricing: widget.profile.pricing,
      numChildren: _numChildren,
      agreedStart: _agreedStart!,
      agreedEnd: _agreedEnd!,
      isHoliday: _isHoliday,
      bookingCreatedAt: DateTime.now(),
    );
    setState(() => _preview = bd);
    widget.onTotalChanged(bd.total);
    widget.onPreferencesChanged(BabysitterBookingPreferences(
      numChildren: _numChildren,
      agreedStart: _agreedStart!,
      agreedEnd: _agreedEnd!,
      verifiedAddress: _verifiedAddress,
      specialInstructions: _instructionsCtrl.text.trim(),
      isHoliday: _isHoliday,
      priceBreakdown: bd.toMap(),
    ));
  }

  // ── Date/time pickers ───────────────────────────────────────────────────
  Future<void> _pickStart() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _agreedStart ?? now,
      firstDate: now.subtract(const Duration(hours: 1)),
      lastDate: now.add(const Duration(days: 90)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_agreedStart ?? now),
    );
    if (time == null) return;
    setState(() {
      _agreedStart =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
      // Default end = start + 4h if end not yet set or invalid.
      if (_agreedEnd == null || !_agreedEnd!.isAfter(_agreedStart!)) {
        _agreedEnd = _agreedStart!.add(const Duration(hours: 4));
      }
    });
    _recalculate();
  }

  Future<void> _pickEnd() async {
    if (_agreedStart == null) {
      await _pickStart();
      return;
    }
    final base = _agreedEnd ?? _agreedStart!.add(const Duration(hours: 4));
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: _agreedStart!,
      lastDate: _agreedStart!.add(const Duration(days: 2)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null) return;
    final picked =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!picked.isAfter(_agreedStart!)) return;
    setState(() => _agreedEnd = picked);
    _recalculate();
  }

  Future<void> _openAddressPicker() async {
    final result = await Navigator.of(context).push<BabysitterVerifiedAddress>(
      MaterialPageRoute(
        builder: (_) => _AddressPickerScreen(initial: _verifiedAddress),
      ),
    );
    if (result == null) return;
    setState(() => _verifiedAddress = result);
    _recalculate();
  }

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kBgCream,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kCreamBorder),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _hero(),
          const SizedBox(height: 16),
          _trustCenter(),
          const SizedBox(height: 16),
          _experienceCard(),
          const SizedBox(height: 16),
          _servicesAndAgesCard(),
          const SizedBox(height: 16),
          _pricingDisplayCard(),
          const SizedBox(height: 16),
          _bookingInputsCard(),
          const SizedBox(height: 16),
          _addressCard(),
          const SizedBox(height: 16),
          _instructionsCard(),
          const SizedBox(height: 16),
          _smartBillingNotice(),
          const SizedBox(height: 16),
          _livePreviewCard(),
        ],
      ),
    );
  }

  Widget _hero() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_kBabyPink, _kBabyPurple],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Text('👶', style: TextStyle(fontSize: 32)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'הזמינו משמרת בייביסיטר',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'עם ${widget.providerName} — חיוב חכם, מיקום מאומת, ושקיפות מלאה',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  // ── Trust Center ────────────────────────────────────────────────────────
  Widget _trustCenter() {
    final trust = widget.profile.trust;
    final certs = widget.profile.certifications;
    final hasFirstAid = certs.any((c) => c.type == 'first_aid' || c.type == 'bls');
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('🛡️ מרכז אמון'),
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 2,
            childAspectRatio: 2.6,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _trustBadge(
                icon: Icons.verified_user_rounded,
                label: trust.idVerified ? 'זהות מאומתת' : 'זהות לא מאומתת',
                active: trust.idVerified,
              ),
              _trustBadge(
                icon: Icons.fact_check_rounded,
                label: trust.backgroundChecked
                    ? 'בדיקת רקע ✓'
                    : 'אין בדיקת רקע',
                active: trust.backgroundChecked,
              ),
              _trustBadge(
                icon: Icons.medical_services_rounded,
                label:
                    hasFirstAid ? 'מוסמכת בעזרה ראשונה' : 'אין הסמכת עזרה ראשונה',
                active: hasFirstAid,
              ),
              _trustBadge(
                icon: Icons.lock_rounded,
                label: 'תשלום מוגן בנאמנות',
                active: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _trustBadge(
      {required IconData icon, required String label, required bool active}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: active ? _kBabyGreenBg : Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: active ? _kBabyGreen : Colors.grey.shade300, width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: active ? _kBabyGreen : Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: active ? const Color(0xFF065F46) : Colors.grey[600],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ── Experience Card ─────────────────────────────────────────────────────
  Widget _experienceCard() {
    final exp = widget.profile.experience;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('🌟 הניסיון שלי'),
          Row(
            children: [
              _statTile('${exp.yearsExperience}', 'שנות ניסיון', _kBabyPink),
              const SizedBox(width: 10),
              _statTile(
                  '${exp.totalFamilies}', 'משפחות עבדה איתי', _kBabyIndigo),
              const SizedBox(width: 10),
              _statTile(
                  exp.hasOwnChildren ? '✓' : '—', 'אמא בעצמה', _kBabyPurple),
            ],
          ),
          if (widget.profile.introNote.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kBabyPinkBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                widget.profile.introNote,
                style: const TextStyle(
                    color: Color(0xFF831843), fontSize: 13, height: 1.45),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statTile(String value, String label, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.30)),
          ),
          child: Column(
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: color)),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: _kMuted)),
            ],
          ),
        ),
      );

  // ── Services + Ages Card ────────────────────────────────────────────────
  Widget _servicesAndAgesCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('👶 גילאים'),
            if (widget.profile.ageGroups.isEmpty)
              const Text('—', style: TextStyle(color: _kMuted, fontSize: 13))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final id in widget.profile.ageGroups)
                    () {
                      final g = babysitterAgeGroupById(id);
                      if (g == null) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: g.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('${g.emoji} ${g.labelHe}',
                            style: TextStyle(
                                color: g.color,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      );
                    }(),
                ],
              ),
            const SizedBox(height: 14),
            _sectionTitle('🤲 שירותים נוספים'),
            if (widget.profile.servicesOffered.isEmpty)
              const Text('—', style: TextStyle(color: _kMuted, fontSize: 13))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final id in widget.profile.servicesOffered)
                    () {
                      final s = babysitterServiceById(id);
                      if (s == null) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _kBabyIndigoBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('${s.emoji} ${s.labelHe}',
                            style: const TextStyle(
                                color: _kBabyIndigo,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      );
                    }(),
                ],
              ),
          ],
        ),
      );

  // ── Pricing Display ─────────────────────────────────────────────────────
  Widget _pricingDisplayCard() {
    final p = widget.profile.pricing;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('💰 תעריפי שעה'),
          Row(
            children: [
              _priceBox('1 ילד', '₪${p.rateOneChild.toStringAsFixed(0)}/שעה'),
              const SizedBox(width: 8),
              _priceBox(
                  '2 ילדים', '₪${p.rateTwoChildren.toStringAsFixed(0)}/שעה'),
              const SizedBox(width: 8),
              _priceBox('3+ ילדים',
                  '₪${p.rateThreePlusChildren.toStringAsFixed(0)}/שעה'),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chipTag(
                  '🌙 לילה (${p.nightStartsAtHour.toString().padLeft(2, '0')}:00) +${p.nightSurchargePercent}%',
                  _kBabyIndigo),
              if (p.holidaySurchargePercent > 0)
                _chipTag(
                    '🎉 חג +${p.holidaySurchargePercent}%', _kBabyAmber),
              if (p.lastMinuteSurchargePercent > 0)
                _chipTag(
                    '⚡ רגע אחרון +${p.lastMinuteSurchargePercent}%',
                    _kBabyPurple),
            ],
          ),
        ],
      ),
    );
  }

  Widget _priceBox(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: _kBabyPinkBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: _kMuted)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: _kBabyPink)),
            ],
          ),
        ),
      );

  Widget _chipTag(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  // ── Booking Inputs ──────────────────────────────────────────────────────
  Widget _bookingInputsCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('📋 פרטי המשמרת'),
            const Text('כמה ילדים?',
                style: TextStyle(fontSize: 13, color: _kMuted)),
            const SizedBox(height: 6),
            Row(
              children: [
                for (int i = 1; i <= 4; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(
                          end: i < 4 ? 6 : 0),
                      child: InkWell(
                        onTap: () {
                          setState(() => _numChildren = i);
                          _recalculate();
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _numChildren == i
                                ? _kBabyPink
                                : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _numChildren == i
                                  ? _kBabyPink
                                  : _kCreamBorder,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            i == 4 ? '4+' : '$i',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: _numChildren == i
                                  ? Colors.white
                                  : _kDarkText,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _dateTimeButton(
                    label: 'התחלה',
                    value: _agreedStart,
                    onTap: _pickStart,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _dateTimeButton(
                    label: 'סיום',
                    value: _agreedEnd,
                    onTap: _pickEnd,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            CheckboxListTile.adaptive(
              value: _isHoliday,
              onChanged: (v) {
                setState(() => _isHoliday = v ?? false);
                _recalculate();
              },
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: _kBabyAmber,
              title: const Text('המשמרת בערב חג / חג',
                  style: TextStyle(fontSize: 13)),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      );

  Widget _dateTimeButton({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    final formatted = value == null
        ? 'בחרי תאריך ושעה'
        : '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')} '
            '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kCreamBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: _kMuted)),
            const SizedBox(height: 2),
            Text(formatted,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  // ── Address Picker (Wolt-style) ─────────────────────────────────────────
  Widget _addressCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('📍 כתובת מאומתת',
                hint:
                    'נחשפת לבייביסיטר רק אחרי שאת מאשרת את ההזמנה. ההגעה תוודא דרך GPS.'),
            if (_verifiedAddress == null)
              InkWell(
                onTap: _openAddressPicker,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _kBabyIndigoBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kBabyIndigo, width: 1.4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.add_location_alt_rounded,
                          color: _kBabyIndigo, size: 26),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('סמן/י את המיקום על המפה',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: _kBabyIndigo)),
                            SizedBox(height: 2),
                            Text(
                                'חיפוש כתובת + גרירת סיכה למיקום המדויק (Wolt-style)',
                                style: TextStyle(fontSize: 11, color: _kMuted)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_left, color: _kBabyIndigo),
                    ],
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kBabyGreenBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBabyGreen),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: _kBabyGreen, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_verifiedAddress!.formattedAddress,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: Color(0xFF065F46))),
                          if (_verifiedAddress!.apartmentNumber.isNotEmpty)
                            Text(_verifiedAddress!.apartmentNumber,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF065F46))),
                          Text(
                              _verifiedAddress!.pinAdjusted
                                  ? 'מיקום מדויק (סיכה הוזזה)'
                                  : 'מיקום מהחיפוש',
                              style: const TextStyle(
                                  fontSize: 11, color: _kMuted)),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _openAddressPicker,
                      child: const Text('עריכה'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

  // ── Special Instructions ────────────────────────────────────────────────
  Widget _instructionsCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('📝 הערות והנחיות מיוחדות',
                hint: 'אלרגיות, הרגלי שינה, קודי שער…'),
            TextField(
              controller: _instructionsCtrl,
              maxLines: 3,
              maxLength: 400,
              decoration: const InputDecoration(
                hintText: 'דוגמה: לא לאכול בוטנים, השער מקודד 1234, רוני נרדמת ב-21:00...',
                border: OutlineInputBorder(),
                counterText: '',
              ),
              onChanged: (_) => _recalculate(),
            ),
          ],
        ),
      );

  // ── Smart Billing Notice ────────────────────────────────────────────────
  Widget _smartBillingNotice() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kBabyAmberBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBabyAmber, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.bolt_rounded, color: _kBabyAmber, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Smart Auto-Billing — שקיפות מלאה',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF92400E),
                          fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    'אם תאחרי לחזור — נחויב ₪${widget.profile.pricing.lateFeePerInterval.toStringAsFixed(0)} '
                    'לכל ${widget.profile.pricing.lateFeeIntervalMinutes} דק׳ '
                    '(תקרה ₪${widget.profile.pricing.lateFeeMaxAmount.toStringAsFixed(0)}). '
                    'החיוב הסופי יחושב לפי שעות בפועל.',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF92400E), height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  // ── Live Preview ────────────────────────────────────────────────────────
  Widget _livePreviewCard() {
    if (_preview == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: _kMuted, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text('בחרי שעות התחלה וסיום כדי לראות את הסכום הצפוי',
                  style: TextStyle(fontSize: 13, color: _kMuted)),
            ),
          ],
        ),
      );
    }
    final bd = _preview!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kBabyIndigo, _kBabyPurple],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('סכום משוער',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Text('₪${bd.total.toStringAsFixed(0)}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          if (bd.regularHours > 0)
            _previewRow(
                '${bd.regularHours.toStringAsFixed(1)} שעות רגילות',
                '₪${bd.regularAmount.toStringAsFixed(0)}'),
          if (bd.nightHours > 0)
            _previewRow(
                '${bd.nightHours.toStringAsFixed(1)} שעות לילה',
                '₪${bd.nightAmount.toStringAsFixed(0)}'),
          if (bd.holidaySurcharge > 0)
            _previewRow('תוספת חג',
                '₪${bd.holidaySurcharge.toStringAsFixed(0)}'),
          if (bd.lastMinuteSurcharge > 0)
            _previewRow('תוספת רגע אחרון',
                '₪${bd.lastMinuteSurcharge.toStringAsFixed(0)}'),
          const SizedBox(height: 8),
          const Text(
            '* לא כולל קנס איחור — נגבה רק אם תחזרי באיחור',
            style: TextStyle(color: Colors.white60, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _previewRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      );

  // ── Common helpers ──────────────────────────────────────────────────────
  Widget _card({required Widget child}) => Container(
        decoration: BoxDecoration(
          color: _kCardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kCreamBorder),
        ),
        padding: const EdgeInsets.all(14),
        child: child,
      );

  Widget _sectionTitle(String title, {String? hint}) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: _kDarkText)),
            if (hint != null && hint.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(hint,
                    style: const TextStyle(fontSize: 11, color: _kMuted)),
              ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────
// Address Picker Screen — Wolt-style flutter_map + draggable pin
// ─────────────────────────────────────────────────────────────────────────

class _AddressPickerScreen extends StatefulWidget {
  final BabysitterVerifiedAddress? initial;
  const _AddressPickerScreen({this.initial});

  @override
  State<_AddressPickerScreen> createState() => _AddressPickerScreenState();
}

class _AddressPickerScreenState extends State<_AddressPickerScreen> {
  // City + street are now driven by the AddressInput widget. We keep them
  // as local state strings (NOT controllers — AddressInput owns those) so
  // the confirm path can reconstruct the legacy `formattedAddress`.
  String _city = '';
  String _street = '';
  // Bump on every AddressInput-replace so initial state propagates after
  // reverse-geocode (Flutter widget identity-based state survival).
  int _addressEpoch = 0;
  final _aptCtrl = TextEditingController();
  final _accessCtrl = TextEditingController();
  final _mapController = MapController();

  // Israel default center (Tel Aviv) — gets overridden by GPS / user pan.
  LatLng _pinLocation = const LatLng(32.0853, 34.7818);
  bool _pinAdjusted = false;
  bool _loadingGps = false;

  // Debounce reverse-geocode so dragging the map doesn't spam Nominatim.
  Timer? _reverseDebounce;
  bool _reverseLoading = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      final parsed = AddressValue.fromCombined(init.formattedAddress);
      _city = parsed.city;
      _street = parsed.street;
      _aptCtrl.text = init.apartmentNumber;
      _accessCtrl.text = init.accessNotes;
      _pinLocation = LatLng(init.latitude, init.longitude);
      _pinAdjusted = init.pinAdjusted;
    } else {
      _tryUseCurrentGps();
    }
  }

  @override
  void dispose() {
    _aptCtrl.dispose();
    _accessCtrl.dispose();
    _mapController.dispose();
    _reverseDebounce?.cancel();
    super.dispose();
  }

  /// Round-trip the current pin coordinates back into the city + street
  /// fields. Fires on user pan/drop. Debounced 600ms so dragging is smooth.
  void _scheduleReverseGeocode() {
    _reverseDebounce?.cancel();
    _reverseDebounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      setState(() => _reverseLoading = true);
      final result = await GeocodingService.reverseGeocode(_pinLocation);
      if (!mounted) return;
      setState(() {
        _reverseLoading = false;
        if (result != null) {
          final road = result.road ?? '';
          final houseNumber = result.houseNumber ?? '';
          final newCity = result.city ?? '';
          final newStreet =
              houseNumber.isNotEmpty ? '$road $houseNumber'.trim() : road;
          if (newCity.isNotEmpty) _city = newCity;
          if (newStreet.isNotEmpty) _street = newStreet;
          _addressEpoch++; // re-seed AddressInput with reverse-geocoded text
        }
      });
    });
  }

  Future<void> _tryUseCurrentGps() async {
    setState(() => _loadingGps = true);
    try {
      // Route through LocationService per CLAUDE.md Law 47:
      // gives us the branded pre-prompt dialog + web JS-interop fallback +
      // stored-state reconciliation. Falls back to silent no-op if the
      // user declines or no fix is available.
      final pos = await LocationService.requestAndGet(context);
      if (!mounted || pos == null) return;
      setState(() {
        _pinLocation = LatLng(pos.latitude, pos.longitude);
      });
      _mapController.move(_pinLocation, 16);
    } catch (_) {
      // silent — user can pan/drop the pin manually
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  void _moveTo(LatLng target, {bool adjusted = true}) {
    setState(() {
      _pinLocation = target;
      _pinAdjusted = adjusted;
    });
    _mapController.move(target, _mapController.camera.zoom);
    // Sync the address fields with the new pin position. Debounced so the
    // user can drag without Nominatim being hammered.
    if (adjusted) _scheduleReverseGeocode();
  }

  String get _combinedAddress {
    final addr = AddressValue(city: _city, street: _street).combined;
    return addr;
  }

  void _confirm() {
    if (_combinedAddress.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('יש להזין כתובת')),
      );
      return;
    }
    Navigator.pop(
      context,
      BabysitterVerifiedAddress(
        formattedAddress: _combinedAddress,
        apartmentNumber: _aptCtrl.text.trim(),
        accessNotes: _accessCtrl.text.trim(),
        latitude: _pinLocation.latitude,
        longitude: _pinLocation.longitude,
        pinAdjusted: _pinAdjusted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgCream,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('כתובת מאומתת',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'השתמש במיקום הנוכחי',
            onPressed: _loadingGps ? null : _tryUseCurrentGps,
            icon: _loadingGps
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location, color: _kBabyIndigo),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Address fields ─────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // Smart two-field autocomplete. Re-seeded on pin drag via
                // `_addressEpoch` so reverse-geocoded text flows back in.
                AddressInput(
                  key: ValueKey('baby-addr-$_addressEpoch'),
                  initialCity: _city,
                  initialStreet: _street,
                  accentColor: _kBabyPink,
                  dense: true,
                  onChanged: (v) {
                    _city = v.city;
                    _street = v.street;
                  },
                  onCoordinatesResolved: (coords) {
                    if (coords != null) _moveTo(coords, adjusted: true);
                  },
                ),
                if (_reverseLoading)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'מסנכרן עם המפה…',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _aptCtrl,
                        decoration: const InputDecoration(
                          labelText: 'דירה / קומה / כניסה',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _accessCtrl,
                  maxLines: 2,
                  inputFormatters: [LengthLimitingTextInputFormatter(200)],
                  decoration: const InputDecoration(
                    labelText: 'הוראות גישה (קוד שער, חניה)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),

          // ── Map ────────────────────────────────────────────────────────
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _pinLocation,
                    initialZoom: 16,
                    onTap: (_, latLng) => _moveTo(latLng),
                    onPositionChanged: (pos, hasGesture) {
                      if (!hasGesture) return;
                      // While dragging the map, sync the centred pin.
                      _moveTo(pos.center, adjusted: true);
                    },
                  ),
                  children: [
                    WoltTileLayer.forContext(context),
                  ],
                ),
                // Centred pin (Wolt-style — pin fixed, map moves underneath).
                IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 36),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _kBabyPink,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 8,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(10),
                        child: const Icon(Icons.home_filled,
                            color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                ),
                // Hint banner
                if (!_pinAdjusted)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '✋ הזיזי את המפה כדי לסמן את המיקום המדויק של הבית',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Confirm button ─────────────────────────────────────────────
          SafeArea(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBabyPink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('✓ אישור מיקום מדויק',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
