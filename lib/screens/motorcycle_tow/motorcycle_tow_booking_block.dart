// Motorcycle Towing CSM — Client booking block ("שירות גרר אופנועים").
// Mounted in expert_profile_screen.dart between the About section and the
// Service menu when the provider has a non-empty motorcycleTowProfile.
//
// Combines two surfaces from the spec mockups into ONE scrollable block:
//   1. Read-only public profile (mockup §3) — hero, bike types, equipment,
//      service cases, transparent pricing, service area, trust strip.
//   2. Booking inputs (mockup §4 compressed) — 5 step "sections":
//      a. Bike type pick (single-select from the provider's supported list)
//      b. Issue pick (single-select from provider's serviceCases)
//      c. Pickup + dropoff addresses + optional photos
//      d. Urgency + contact details
//      e. Live price breakdown (sticky summary)
//
// IMPORTANT: this block does NOT own the calendar, chat, or "Pay & Secure".
// It emits (preferences, total) to the parent (expert_profile_screen),
// which threads them through the existing escrow flow.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../constants/motorcycle_bike_types_catalog.dart';
import '../../constants/motorcycle_service_cases_catalog.dart';
import '../../constants/motorcycle_urgency_levels.dart';
import '../../widgets/address_input.dart';
import '../../widgets/wolt_tile_layer.dart';
import '../../models/motorcycle_tow_profile.dart';
import '../../services/geocoding_service.dart';
import '../../services/motorcycle_bike_types_service.dart';
import '../../services/motorcycle_tow_booking_service.dart';
import 'motorcycle_tow_palette.dart';

typedef _MTP = MotorcycleTowPalette;

typedef MotorcycleTowPreferencesChanged = void Function(
  MotorcycleTowBookingPreferences prefs,
  double total,
);

class MotorcycleTowBookingBlock extends StatefulWidget {
  final String expertId;
  final String expertName;
  final String? expertAvatarInitial;
  final MotorcycleTowProfile profile;
  /// Provider rating + reviews (for the read-only header in the live-pill
  /// area). When null, the rating row is omitted.
  final double? rating;
  final int? reviewsCount;
  /// Whether the provider is online. Drives the "זמין כעת" pulse.
  final bool isOnline;
  final MotorcycleTowPreferencesChanged onChanged;

  const MotorcycleTowBookingBlock({
    super.key,
    required this.expertId,
    required this.expertName,
    this.expertAvatarInitial,
    required this.profile,
    this.rating,
    this.reviewsCount,
    this.isOnline = true,
    required this.onChanged,
  });

  @override
  State<MotorcycleTowBookingBlock> createState() =>
      _MotorcycleTowBookingBlockState();
}

class _MotorcycleTowBookingBlockState
    extends State<MotorcycleTowBookingBlock> {
  // ── Booking input state ─────────────────────────────────────────────────
  String? _bikeTypeId;
  final _bikeModelCtrl = TextEditingController();
  String? _issueId;
  final _issueDetailsCtrl = TextEditingController();
  final _pickupAddressCtrl = TextEditingController();
  final _dropoffAddressCtrl = TextEditingController();
  double? _pickupLat;
  double? _pickupLng;
  double? _dropoffLat;
  double? _dropoffLng;
  double _distanceKm = 0;

  // Wolt-style map picker state for step 3 ("מאיפה לאן?"). Ported from the
  // Flash Auction location screen so urgent dispatch + scheduled booking
  // share the same drag-the-map-pin → address auto-fill UX.
  final MapController _locMapCtrl = MapController();
  String _activePin = 'pickup'; // which pin the centred marker commits to
  LatLng _mapCenter = const LatLng(32.0853, 34.7818); // Tel Aviv default
  int _pickupAddrVersion = 0; // bumped to re-seed the pickup AddressInput
  int _dropoffAddrVersion = 0; // bumped to re-seed the dropoff AddressInput
  bool _geocodingPin = false; // reverse-geocode round-trip in flight
  String _urgencyId = 'within_hour';
  DateTime? _scheduledAt;
  final _contactNameCtrl = TextEditingController();
  final _contactPhoneCtrl = TextEditingController();
  final List<String> _beforePhotoUrls = [];
  bool _uploadingPhoto = false;

  List<MotorcycleBikeType> _bikeTypes = const [];
  StreamSubscription<List<MotorcycleBikeType>>? _bikeStreamSub;

  @override
  void initState() {
    super.initState();
    // Pre-load the live bike-types list (read once, then keep streaming for
    // live updates if the admin replaces an image while the customer is
    // viewing).
    _bikeStreamSub =
        MotorcycleBikeTypesService.streamBikeTypes().listen((list) {
      if (!mounted) return;
      setState(() => _bikeTypes = list);
    });
    // Default contact info from the signed-in user — they can edit if they
    // book on behalf of someone else.
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _contactNameCtrl.text = user.displayName ?? '';
      _contactPhoneCtrl.text = user.phoneNumber ?? '';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void dispose() {
    _bikeStreamSub?.cancel();
    _bikeModelCtrl.dispose();
    _issueDetailsCtrl.dispose();
    _pickupAddressCtrl.dispose();
    _dropoffAddressCtrl.dispose();
    _contactNameCtrl.dispose();
    _contactPhoneCtrl.dispose();
    _locMapCtrl.dispose();
    super.dispose();
  }

  // ── Pricing recompute + emit ────────────────────────────────────────────

  MotorcycleTowPriceBreakdown _computeBreakdown() {
    return MotorcycleTowBookingService.calculate(
      pricing: widget.profile.pricing,
      distanceKm: _distanceKm,
      urgencyId: _urgencyId,
      when: _scheduledAt,
    );
  }

  void _emit() {
    final breakdown = _computeBreakdown();
    final prefs = MotorcycleTowBookingPreferences(
      bikeTypeId: _bikeTypeId ?? '',
      bikeModel: _bikeModelCtrl.text.trim(),
      issueId: _issueId ?? '',
      issueDetails: _issueDetailsCtrl.text.trim(),
      pickupAddress: _pickupAddressCtrl.text.trim(),
      pickupLat: _pickupLat,
      pickupLng: _pickupLng,
      dropoffAddress: _dropoffAddressCtrl.text.trim(),
      dropoffLat: _dropoffLat,
      dropoffLng: _dropoffLng,
      distanceKm: _distanceKm,
      urgencyId: _urgencyId,
      scheduledAt: _scheduledAt,
      contactName: _contactNameCtrl.text.trim(),
      contactPhone: _contactPhoneCtrl.text.trim(),
      beforePhotoUrls: List.unmodifiable(_beforePhotoUrls),
      priceBreakdown: breakdown,
    );
    widget.onChanged(prefs, breakdown.total);
  }

  void _updateDistanceFromPins() {
    if (_pickupLat != null &&
        _pickupLng != null &&
        _dropoffLat != null &&
        _dropoffLng != null) {
      final km = MotorcycleTowBookingService.haversineKm(
        _pickupLat!,
        _pickupLng!,
        _dropoffLat!,
        _dropoffLng!,
      );
      setState(() => _distanceKm = km);
    }
  }

  Future<void> _pickPhoto() async {
    if (_uploadingPhoto) return;
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 75,
    );
    if (file == null) return;
    setState(() => _uploadingPhoto = true);
    try {
      final bytes = await file.readAsBytes();
      final user = FirebaseAuth.instance.currentUser;
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = file.name.split('.').last.toLowerCase();
      final ref = FirebaseStorage.instance.ref(
        'motorcycle_tow_pre_photos/${user?.uid ?? 'anon'}/$ts.$ext',
      );
      await ref.putData(
        bytes,
        SettableMetadata(contentType: _mimeFor(ext)),
      );
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() {
        _beforePhotoUrls.add(url);
        _uploadingPhoto = false;
      });
      _emit();
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה בהעלאת תמונה: $e'),
          backgroundColor: _MTP.red500,
        ),
      );
    }
  }

  String _mimeFor(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: BoxDecoration(
          color: _MTP.bgPrimary,
          border: Border.all(color: _MTP.borderTertiary, width: 0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHero(),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ReadOnlyHeading(
                      icon: Icons.two_wheeler_rounded,
                      title: 'סוגי אופנועים שאני גורר'),
                  const SizedBox(height: 8),
                  _buildBikeTypesScroll(),
                  const SizedBox(height: 16),
                  _ReadOnlyHeading(
                      icon: Icons.handyman_rounded,
                      title: 'שיטת הגרירה והציוד'),
                  const SizedBox(height: 8),
                  _buildEquipmentGrid(),
                  const SizedBox(height: 16),
                  _ReadOnlyHeading(
                      icon: Icons.error_outline_rounded,
                      title: 'סוגי קריאות'),
                  const SizedBox(height: 8),
                  _buildServiceCasesPills(),
                  const SizedBox(height: 16),
                  _ReadOnlyHeading(
                      icon: Icons.access_time_rounded,
                      title: 'תמחור שקוף'),
                  const SizedBox(height: 8),
                  _buildPricingCard(),
                  const SizedBox(height: 16),
                  _ReadOnlyHeading(
                      icon: Icons.place_outlined, title: 'אזור פעילות'),
                  const SizedBox(height: 8),
                  _buildAreaMap(),
                  const SizedBox(height: 18),
                  // ── BOOKING INPUTS ──────────────────────────────────
                  _buildBookingInputsHeader(),
                  const SizedBox(height: 12),
                  _BookingStep(
                    number: 1,
                    title: 'איזה סוג אופנוע?',
                    description: 'זה עוזר לנהג להביא את הציוד הנכון',
                    child: _buildBikeTypePicker(),
                  ),
                  const SizedBox(height: 14),
                  _BookingStep(
                    number: 2,
                    title: 'מה קרה?',
                    description: 'בחר את הסיבה לגרירה',
                    child: _buildIssuePicker(),
                  ),
                  const SizedBox(height: 14),
                  _BookingStep(
                    number: 3,
                    title: 'מאיפה לאן?',
                    description:
                        'סמן על המפה או הקלד — הכתובת תתמלא אוטומטית. ניתן להעלות תמונות של האופנוע — מומלץ מאוד.',
                    child: _buildLocationsAndPhotos(),
                  ),
                  const SizedBox(height: 14),
                  _BookingStep(
                    number: 4,
                    title: 'מתי?',
                    description: 'בחר את דחיפות הגרירה',
                    child: _buildUrgencyAndContact(),
                  ),
                  const SizedBox(height: 14),
                  _BookingStep(
                    number: 5,
                    title: 'סיכום ההזמנה',
                    description: 'בדוק שהכל נכון לפני "שלם ושמור"',
                    child: _buildSummary(),
                  ),
                  const SizedBox(height: 14),
                  _buildTrustStrip(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HERO
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildHero() {
    final etaMin = _profileEtaMin();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_MTP.purple700, _MTP.purple500],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.two_wheeler_rounded,
                  size: 22, color: Colors.white),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'שירות גרר אופנועים',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
              if (widget.isOnline) const _LivePill(),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  label: 'זמן הגעה',
                  value: etaMin,
                  sub: 'דקות',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroStat(
                  label: 'מחיר התחלתי',
                  value: '₪${widget.profile.pricing.basePrice.round()}',
                  sub:
                      '+ ₪${widget.profile.pricing.pricePerKm.toStringAsFixed(1)} לק"מ',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroStat(
                  label: widget.profile.serviceArea.mode == 'polygon'
                      ? 'אזור שירות'
                      : 'רדיוס שירות',
                  value: widget.profile.serviceArea.mode == 'polygon'
                      ? '${widget.profile.serviceArea.polygonPoints.length}'
                      : '${widget.profile.serviceArea.radiusKm.round()}',
                  sub: widget.profile.serviceArea.mode == 'polygon'
                      ? 'נקודות'
                      : 'ק"מ',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _profileEtaMin() {
    // Rough proxy — emergency: 22-35, within hour: 60-90, today/scheduled: '—'
    if (_urgencyId == 'immediate') return '22–35';
    if (_urgencyId == 'within_hour') return '60–90';
    return '—';
  }

  // ═══════════════════════════════════════════════════════════════════════
  // READ-ONLY PUBLIC PROFILE
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildBikeTypesScroll() {
    final selectedIds = widget.profile.bikeTypeIds.toSet();
    final shown = _bikeTypes.where((t) => selectedIds.contains(t.id)).toList();
    if (shown.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'לא הוגדרו סוגי אופנועים',
          style: TextStyle(
            fontSize: 12,
            color: _MTP.textTertiary,
          ),
        ),
      );
    }
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: shown.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final t = shown[i];
          return SizedBox(
            width: 88,
            child: Column(
              children: [
                Container(
                  width: 88,
                  height: 66,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: _MTP.bgSecondary,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: t.imageUrl.isEmpty
                      ? const Icon(Icons.two_wheeler_rounded,
                          color: _MTP.textTertiary)
                      : Image.network(
                          t.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.two_wheeler_rounded,
                            color: _MTP.textTertiary,
                          ),
                        ),
                ),
                const SizedBox(height: 4),
                Text(
                  t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _MTP.textPrimary,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEquipmentGrid() {
    final items = widget.profile.equipment.enabledList;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          'לא צוין ציוד',
          style: TextStyle(fontSize: 12, color: _MTP.textTertiary),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 6,
        mainAxisExtent: 36,
      ),
      itemBuilder: (_, i) {
        final it = items[i];
        return Row(
          children: [
            const Icon(Icons.check_rounded,
                size: 14, color: _MTP.green500),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                it['label']!,
                style: const TextStyle(
                  fontSize: 12,
                  color: _MTP.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildServiceCasesPills() {
    final ids = widget.profile.serviceCases;
    if (ids.isEmpty) {
      return Text(
        'לא צוינו סוגי קריאות',
        style: TextStyle(fontSize: 12, color: _MTP.textTertiary),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final id in ids)
          if (findServiceCase(id) != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: _MTP.purple50,
                border: Border.all(color: _MTP.purple200, width: 0.5),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                findServiceCase(id)!.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _MTP.purple700,
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildPricingCard() {
    final p = widget.profile.pricing;
    final nightWindow =
        '${p.nightStartHour.toString().padLeft(2, '0')}:00–${p.nightEndHour.toString().padLeft(2, '0')}:00';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _MTP.amber50.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _MTP.amber50, width: 0.5),
      ),
      child: Column(
        children: [
          _PriceRow(
            label: 'מחיר בסיס (כולל ${p.includedKm} ק"מ)',
            value: '₪${p.basePrice.round()}',
          ),
          _PriceRow(
            label: 'לכל ק"מ נוסף',
            value: '₪${p.pricePerKm.toStringAsFixed(1)}',
          ),
          const Divider(
              height: 16, thickness: 0.5, color: _MTP.borderTertiary),
          _PriceRow(
            label: 'תוספת לילה ($nightWindow)',
            value: '+${p.nightSurchargePercent.round()}%',
          ),
          _PriceRow(
            label: 'תוספת חירום מיידי',
            value: '+${p.emergencySurchargePercent.round()}%',
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 12, color: _MTP.amber600),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'הצעת מחיר מדויקת תופיע אחרי הזנת מיקום ויעד',
                  style: TextStyle(
                    fontSize: 11,
                    color: _MTP.amber800,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAreaMap() {
    final area = widget.profile.serviceArea;
    final center = LatLng(area.baseLat, area.baseLng);

    // Compute camera-fit bounds so the configured area is centred and
    // legible no matter where the provider's base is. Without this the
    // map shows a static zoom-9 view and a tiny purple dot — the user
    // perceives a "gray square".
    LatLngBounds? bounds;
    if (area.mode == 'polygon' && area.polygonPoints.length >= 2) {
      bounds = LatLngBounds.fromPoints(
        [for (final p in area.polygonPoints) LatLng(p.lat, p.lng)],
      );
    } else if (area.mode == 'radius' && area.radiusKm > 0) {
      // ~111 km per degree latitude; longitude scales by cos(lat).
      final latDelta = area.radiusKm / 111.0;
      final lngDelta = area.radiusKm /
          (111.0 *
              (area.baseLat.abs() < 89
                  ? (1 - 0.005 * (area.baseLat.abs())) // light approx
                  : 1));
      bounds = LatLngBounds(
        LatLng(area.baseLat - latDelta, area.baseLng - lngDelta),
        LatLng(area.baseLat + latDelta, area.baseLng + lngDelta),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: _MTP.borderTertiary, width: 0.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: 10,
              minZoom: 5,
              maxZoom: 18,
              initialCameraFit: bounds == null
                  ? null
                  : CameraFit.bounds(
                      bounds: bounds,
                      padding: const EdgeInsets.all(20),
                    ),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom |
                    InteractiveFlag.drag |
                    InteractiveFlag.doubleTapZoom,
              ),
            ),
            children: [
              WoltTileLayer.forContext(context, maxZoom: 19),
              if (area.mode == 'radius' && area.radiusKm > 0)
                CircleLayer(circles: [
                  CircleMarker(
                    point: center,
                    radius: area.radiusKm * 1000,
                    useRadiusInMeter: true,
                    color: _MTP.purple500.withValues(alpha: 0.22),
                    borderColor: _MTP.purple500,
                    borderStrokeWidth: 2,
                  ),
                ])
              else if (area.mode == 'polygon' &&
                  area.polygonPoints.length >= 2)
                PolygonLayer(polygons: [
                  Polygon(
                    points: [
                      for (final p in area.polygonPoints)
                        LatLng(p.lat, p.lng),
                    ],
                    color: _MTP.purple500.withValues(alpha: 0.22),
                    borderColor: _MTP.purple500,
                    borderStrokeWidth: 2,
                  ),
                ]),
              MarkerLayer(markers: [
                Marker(
                  point: center,
                  width: 28,
                  height: 28,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _MTP.purple500,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.place_rounded,
                        size: 16, color: Colors.white),
                  ),
                ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _MTP.bgSecondary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  area.baseAddress.isEmpty
                      ? 'בסיס לא צוין'
                      : 'בסיס: ${area.baseAddress}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: _MTP.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (area.mode == 'radius')
                Text(
                  '· רדיוס ${area.radiusKm.round()} ק"מ',
                  style: const TextStyle(
                    fontSize: 11,
                    color: _MTP.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else if (area.mode == 'polygon')
                Text(
                  '· ${area.polygonPoints.length} נקודות',
                  style: const TextStyle(
                    fontSize: 11,
                    color: _MTP.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTrustStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _MTP.green50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _MTP.green300, width: 0.5),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        children: const [
          _TrustItem(icon: Icons.verified_user_outlined, label: 'מאומת'),
          _TrustItem(
              icon: Icons.security_rounded, label: 'ביטוח מלא לאופנוע'),
          _TrustItem(
              icon: Icons.camera_alt_outlined, label: 'תמונות לפני/אחרי'),
          _TrustItem(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'צ\'אט מאובטח'),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BOOKING INPUTS
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildBookingInputsHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _MTP.purple50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _MTP.purple200, width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.shopping_cart_outlined,
              color: _MTP.purple700, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'מלא את הפרטים — וסיים בלחיצת "שלם ושמור" למטה',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _MTP.purple700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBikeTypePicker() {
    final allowedIds = widget.profile.bikeTypeIds.toSet();
    final shown =
        _bikeTypes.where((t) => allowedIds.contains(t.id)).toList();
    if (shown.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _MTP.bgSecondary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'הספק לא הגדיר סוגי אופנועים',
          style: TextStyle(fontSize: 12, color: _MTP.textTertiary),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: shown.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.55,
          ),
          itemBuilder: (_, i) {
            final t = shown[i];
            final on = _bikeTypeId == t.id;
            return InkWell(
              onTap: () {
                setState(() => _bikeTypeId = t.id);
                _emit();
              },
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: on ? _MTP.purple500 : _MTP.borderTertiary,
                    width: on ? 1 : 0.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  color: on ? _MTP.purple50 : _MTP.bgPrimary,
                ),
                clipBehavior: Clip.antiAlias,
                child: Row(
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: t.imageUrl.isEmpty
                          ? const Icon(Icons.two_wheeler_rounded,
                              color: _MTP.textTertiary)
                          : Image.network(
                              t.imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.two_wheeler_rounded,
                                color: _MTP.textTertiary,
                              ),
                            ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(start: 10),
                        child: Text(
                          t.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: on
                                ? _MTP.purple700
                                : _MTP.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _bikeModelCtrl,
          decoration: _input(
            hint: 'דגם (אופציונלי, למשל: Yamaha MT-07)',
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: (_) => _emit(),
        ),
      ],
    );
  }

  Widget _buildIssuePicker() {
    final allowed = widget.profile.serviceCases
        .map(findServiceCase)
        .whereType<MotorcycleServiceCase>()
        .toList();
    if (allowed.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _MTP.bgSecondary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'הספק לא הגדיר סוגי קריאות',
          style: TextStyle(fontSize: 12, color: _MTP.textTertiary),
        ),
      );
    }
    return Column(
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: allowed.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            mainAxisExtent: 56,
          ),
          itemBuilder: (_, i) {
            final c = allowed[i];
            final on = _issueId == c.id;
            return InkWell(
              onTap: () {
                setState(() => _issueId = c.id);
                _emit();
              },
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: on ? _MTP.purple50 : _MTP.bgPrimary,
                  border: Border.all(
                    color: on ? _MTP.purple500 : _MTP.borderTertiary,
                    width: on ? 1 : 0.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Text(c.emoji,
                        style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        c.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: on
                              ? _MTP.purple700
                              : _MTP.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _issueDetailsCtrl,
          maxLines: 2,
          decoration: _input(
            hint: 'פרטים נוספים (אופציונלי, למשל: האופנוע על המדרכה...)',
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: (_) => _emit(),
        ),
      ],
    );
  }

  Widget _buildLocationsAndPhotos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Wolt-style map picker — drag so the centred pin lands on the
        // location, tap "הצב כאן", and the address fields below auto-fill
        // via reverse-geocoding. Ported from the Flash Auction location
        // screen ("מצא גרר דחוף") so both towing flows share the same UX.
        _buildLocationPinToggle(),
        const SizedBox(height: 8),
        _buildLocationMap(),
        const SizedBox(height: 8),
        _buildLocationMapTip(),
        const SizedBox(height: 14),
        const _MiniLabel(text: 'מאיפה (מיקום הגרירה)'),
        const SizedBox(height: 4),
        // Smart two-field autocomplete bridged to legacy `_pickupAddressCtrl`
        // via combined; coords auto-set on dropdown selection and trigger
        // _updateDistanceFromPins so the live distance preview stays in
        // sync. The key carries `_pickupAddrVersion` so the widget re-seeds
        // whenever a map-pin commit reverse-geocoded a fresh address in.
        Builder(builder: (_) {
          final initial = AddressValue.fromCombined(_pickupAddressCtrl.text);
          return AddressInput(
            key: ValueKey('motorcycle-tow-pickup-$_pickupAddrVersion'),
            initialCity: initial.city,
            initialStreet: initial.street,
            accentColor: _MTP.green500,
            dense: true,
            streetHint: 'למשל: יגאל אלון 94',
            onChanged: (v) {
              _pickupAddressCtrl.text = v.combined;
              _emit();
            },
            onCoordinatesResolved: (coords) {
              if (coords != null) {
                _applyLocationCoords(coords, pickup: true);
              }
            },
          );
        }),
        const SizedBox(height: 10),
        const _MiniLabel(text: 'לאן (יעד)'),
        const SizedBox(height: 4),
        Builder(builder: (_) {
          final initial =
              AddressValue.fromCombined(_dropoffAddressCtrl.text);
          return AddressInput(
            key: ValueKey('motorcycle-tow-dropoff-$_dropoffAddrVersion'),
            initialCity: initial.city,
            initialStreet: initial.street,
            accentColor: _MTP.purple500,
            dense: true,
            streetHint: 'למשל: מוסך הצפון, האלון 12',
            onChanged: (v) {
              _dropoffAddressCtrl.text = v.combined;
              _emit();
            },
            onCoordinatesResolved: (coords) {
              if (coords != null) {
                _applyLocationCoords(coords, pickup: false);
              }
            },
          );
        }),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _MiniLabel(
                text: _distanceKm > 0
                    ? 'מרחק משוער: ${_distanceKm.toStringAsFixed(1)} ק"מ'
                    : 'מרחק משוער יחושב אחרי בחירת מיקומים',
              ),
            ),
            TextButton.icon(
              onPressed: () =>
                  _showDistanceManualEntryDialog(context),
              icon:
                  const Icon(Icons.edit_outlined, size: 14),
              label: const Text('הזן מרחק ידנית'),
              style: TextButton.styleFrom(
                foregroundColor: _MTP.purple500,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                textStyle: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const _MiniLabel(text: 'תמונות של האופנוע (מומלץ מאוד)'),
        const SizedBox(height: 6),
        _buildPhotoZone(),
      ],
    );
  }

  // ── Wolt-style map picker (step 3) ──────────────────────────────────────

  /// Segmented "מאיפה / לאן" toggle — picks which pin the centred map
  /// marker commits to.
  Widget _buildLocationPinToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _MTP.bgSecondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _PinToggleChip(
            label: 'מאיפה',
            icon: Icons.my_location_rounded,
            iconColor: _MTP.green500,
            active: _activePin == 'pickup',
            onTap: () => setState(() => _activePin = 'pickup'),
          ),
          _PinToggleChip(
            label: 'לאן',
            icon: Icons.place_rounded,
            iconColor: _MTP.purple500,
            active: _activePin == 'dropoff',
            onTap: () => setState(() => _activePin = 'dropoff'),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationMap() {
    final pickupLL = (_pickupLat != null && _pickupLng != null)
        ? LatLng(_pickupLat!, _pickupLng!)
        : null;
    final dropoffLL = (_dropoffLat != null && _dropoffLng != null)
        ? LatLng(_dropoffLat!, _dropoffLng!)
        : null;
    final pickupActive = _activePin == 'pickup';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _MTP.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _MTP.borderTertiary, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 220,
          width: double.infinity,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _locMapCtrl,
                options: MapOptions(
                  initialCenter: _mapCenter,
                  initialZoom: 13,
                  minZoom: 6,
                  maxZoom: 18,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.pinchZoom |
                        InteractiveFlag.drag |
                        InteractiveFlag.doubleTapZoom,
                  ),
                  onPositionChanged: (pos, _) {
                    _mapCenter = pos.center;
                  },
                ),
                children: [
                  WoltTileLayer.forContext(context, maxZoom: 19),
                  MarkerLayer(
                    markers: [
                      if (pickupLL != null)
                        Marker(
                          point: pickupLL,
                          width: 26,
                          height: 26,
                          child: _mapMarker(
                              Icons.my_location_rounded, _MTP.green500),
                        ),
                      if (dropoffLL != null)
                        Marker(
                          point: dropoffLL,
                          width: 26,
                          height: 26,
                          child: _mapMarker(
                              Icons.place_rounded, _MTP.purple500),
                        ),
                    ],
                  ),
                ],
              ),
              // Centred pin — always visible (Wolt UX). Colour follows the
              // active slot so the user knows which pin they're placing.
              IgnorePointer(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: Icon(
                      pickupActive
                          ? Icons.my_location_rounded
                          : Icons.place_rounded,
                      color: pickupActive ? _MTP.green500 : _MTP.purple500,
                      size: 36,
                      shadows: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 5,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Bottom-overlay "commit this point" button.
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Material(
                  color: pickupActive ? _MTP.green500 : _MTP.purple500,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: _geocodingPin ? null : _commitLocationPin,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_geocodingPin)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          else
                            const Icon(Icons.push_pin_rounded,
                                color: Colors.white, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            _geocodingPin
                                ? 'מאתר כתובת...'
                                : (pickupActive
                                    ? 'הצב כאן את נקודת המוצא'
                                    : 'הצב כאן את נקודת היעד'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mapMarker(IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 12),
    );
  }

  Widget _buildLocationMapTip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _MTP.purple50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _MTP.purple200, width: 0.5),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 16, color: _MTP.purple500),
          SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 12,
                  color: _MTP.purple700,
                  height: 1.5,
                ),
                children: [
                  TextSpan(
                    text: 'טיפ: ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text:
                        'גרור את המפה כדי שהסיכה תיפול על המיקום — לחץ "הצב כאן" — והכתובת תתמלא אוטומטית. עבור בין "מאיפה" ל-"לאן" בלשוניות שמעל.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Called when an AddressInput resolves a typed street to coordinates —
  /// drops the matching pin + recenters the map so the typed-address and
  /// map-pin paths stay in sync.
  void _applyLocationCoords(LatLng coords, {required bool pickup}) {
    setState(() {
      if (pickup) {
        _pickupLat = coords.latitude;
        _pickupLng = coords.longitude;
        _activePin = 'pickup';
      } else {
        _dropoffLat = coords.latitude;
        _dropoffLng = coords.longitude;
        _activePin = 'dropoff';
      }
      _mapCenter = coords;
    });
    _updateDistanceFromPins();
    _emit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _locMapCtrl.move(coords, 15);
      } catch (_) {}
    });
  }

  /// Commit the centred map pin to the active slot, then reverse-geocode
  /// the coordinates so the matching address field auto-fills (Wolt-style).
  /// On any geocoding failure the pin still stands — the customer can type
  /// the address manually instead. The pin's lat/lng are set immediately
  /// so the live distance preview updates without waiting for Nominatim.
  Future<void> _commitLocationPin() async {
    final pinned = _mapCenter;
    final forPickup = _activePin == 'pickup';
    setState(() {
      _geocodingPin = true;
      if (forPickup) {
        _pickupLat = pinned.latitude;
        _pickupLng = pinned.longitude;
      } else {
        _dropoffLat = pinned.latitude;
        _dropoffLng = pinned.longitude;
      }
    });
    _updateDistanceFromPins();

    StreetSuggestion? result;
    try {
      result = await GeocodingService.reverseGeocode(pinned);
    } catch (_) {
      result = null;
    }
    if (!mounted) return;

    if (result == null) {
      setState(() => _geocodingPin = false);
      _emit();
      return;
    }

    // Build a friendly "<street> <house>, <city>" string. AddressInput
    // splits this back into city + street via AddressValue.fromCombined.
    final road = (result.road ?? '').trim();
    final house = (result.houseNumber ?? '').trim();
    final city = (result.city ?? '').trim();
    final streetPart = [
      if (road.isNotEmpty) road,
      if (house.isNotEmpty) house,
    ].join(' ').trim();
    String combined;
    if (streetPart.isEmpty && city.isEmpty) {
      combined = result.displayName.trim();
    } else if (streetPart.isEmpty) {
      combined = city;
    } else if (city.isEmpty) {
      combined = streetPart;
    } else {
      combined = '$streetPart, $city';
    }

    setState(() {
      _geocodingPin = false;
      if (forPickup) {
        _pickupAddressCtrl.text = combined;
        _pickupAddrVersion++; // re-seed the pickup AddressInput
      } else {
        _dropoffAddressCtrl.text = combined;
        _dropoffAddrVersion++;
      }
    });
    _emit();
  }

  Future<void> _showDistanceManualEntryDialog(BuildContext context) async {
    final controller = TextEditingController(
        text: _distanceKm > 0 ? _distanceKm.toStringAsFixed(1) : '');
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מרחק משוער (ק"מ)'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
            ],
            decoration:
                _input(hint: 'למשל: 8.4'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ביטול')),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(controller.text.trim());
                Navigator.pop(ctx, v);
              },
              style: FilledButton.styleFrom(backgroundColor: _MTP.purple500),
              child: const Text('שמור'),
            ),
          ],
        ),
      ),
    );
    if (result != null && result > 0) {
      setState(() => _distanceKm = result);
      _emit();
    }
    _updateDistanceFromPins();
  }

  Widget _buildPhotoZone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _uploadingPhoto ? null : _pickPhoto,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: _MTP.bgSecondary,
              border: Border.all(
                color: _MTP.borderSecondary,
                width: 0.5,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _uploadingPhoto
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _MTP.purple500,
                        ),
                      )
                    : const Icon(Icons.camera_alt_outlined,
                        size: 18, color: _MTP.purple500),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'הוסף תמונות (לפני הגרירה)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _MTP.textPrimary,
                    ),
                  ),
                ),
                const Icon(Icons.add_rounded,
                    size: 18, color: _MTP.purple500),
              ],
            ),
          ),
        ),
        if (_beforePhotoUrls.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _beforePhotoUrls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final url = _beforePhotoUrls[i];
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        url,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 56,
                          height: 56,
                          color: _MTP.bgSecondary,
                          child: const Icon(Icons.broken_image_outlined,
                              size: 16, color: _MTP.textTertiary),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _beforePhotoUrls.removeAt(i));
                          _emit();
                        },
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.close_rounded,
                              size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 4),
        const Text(
          'תיעוד למניעת מחלוקות מאוחרות יותר',
          style: TextStyle(fontSize: 11, color: _MTP.textTertiary),
        ),
      ],
    );
  }

  Widget _buildUrgencyAndContact() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          children: [
            for (final u in kMotorcycleUrgencyLevels)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _UrgencyCard(
                  level: u,
                  selected: _urgencyId == u.id,
                  onTap: () async {
                    setState(() => _urgencyId = u.id);
                    if (u.id == 'scheduled') {
                      final picked = await _pickScheduledDateTime(context);
                      if (picked != null) {
                        setState(() => _scheduledAt = picked);
                      }
                    } else {
                      setState(() => _scheduledAt = null);
                    }
                    _emit();
                  },
                ),
              ),
          ],
        ),
        if (_urgencyId == 'scheduled' && _scheduledAt != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _MTP.purple50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 13, color: _MTP.purple700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _formatScheduled(_scheduledAt!),
                      style: const TextStyle(
                        fontSize: 12,
                        color: _MTP.purple700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<DateTime?> _pickScheduledDateTime(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
      initialDate: now.add(const Duration(days: 1)),
    );
    if (date == null || !context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (time == null) return null;
    return DateTime(
        date.year, date.month, date.day, time.hour, time.minute);
  }

  String _formatScheduled(DateTime t) {
    final d = '${t.day.toString().padLeft(2, '0')}/'
        '${t.month.toString().padLeft(2, '0')}/${t.year}';
    final h = '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
    return 'תזמון: $d ב-$h';
  }

  Widget _buildSummary() {
    final breakdown = _computeBreakdown();
    final pricing = widget.profile.pricing;
    final isNight = MotorcycleTowBookingService.isNightOrSaturday(
      pricing: pricing,
      when: _scheduledAt,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _MTP.bgSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _MTP.borderTertiary, width: 0.5),
      ),
      child: Column(
        children: [
          _SummaryRow(
            icon: Icons.two_wheeler_rounded,
            label: 'אופנוע',
            value: _bikeTypeLabel(),
          ),
          _SummaryRow(
            icon: Icons.error_outline_rounded,
            label: 'סיבת הגרירה',
            value: _issueId == null
                ? '—'
                : (findServiceCase(_issueId!)?.name ?? '—'),
          ),
          _SummaryRow(
            icon: Icons.place_outlined,
            label: 'מסלול',
            value: _routeLabel(),
          ),
          _SummaryRow(
            icon: Icons.schedule_rounded,
            label: 'זמן',
            value: _urgencyLabel(),
          ),
          const Divider(
              height: 16, thickness: 0.5, color: _MTP.borderTertiary),
          _PriceRow(
            label: 'מחיר בסיס',
            value: '₪${breakdown.basePrice.round()}',
          ),
          if (breakdown.extraKm > 0)
            _PriceRow(
              label:
                  'תוספת ק"מ (${breakdown.extraKm.toStringAsFixed(1)} ק"מ)',
              value: '₪${breakdown.kmFee.round()}',
            ),
          if (isNight)
            _PriceRow(
              label:
                  'תוספת לילה / שבת (${pricing.nightSurchargePercent.round()}%)',
              value: '₪${breakdown.nightSurcharge.round()}',
            ),
          if (_urgencyId == 'immediate')
            _PriceRow(
              label:
                  'תוספת חירום מיידי (${pricing.emergencySurchargePercent.round()}%)',
              value: '₪${breakdown.emergencySurcharge.round()}',
            ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: _MTP.borderTertiary,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'סה"כ משוער',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _MTP.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '₪${breakdown.total.round()}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: _MTP.purple700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '✓ ביטוח מלא בזמן הגרירה  ·  ✓ מעקב GPS חי  ·  ✓ תמונות לפני/אחרי',
            style: TextStyle(
              fontSize: 11,
              color: _MTP.textTertiary,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _bikeTypeLabel() {
    if (_bikeTypeId == null) return '—';
    final t = findMotorcycleBikeType(_bikeTypeId!, _bikeTypes);
    final name = t?.name ?? _bikeTypeId!;
    final model = _bikeModelCtrl.text.trim();
    return model.isEmpty ? name : '$name · $model';
  }

  String _routeLabel() {
    final from = _pickupAddressCtrl.text.trim();
    final to = _dropoffAddressCtrl.text.trim();
    if (from.isEmpty && to.isEmpty) return '—';
    if (from.isEmpty) return '— ← $to';
    if (to.isEmpty) return '$from ← —';
    return '$from ← $to';
  }

  String _urgencyLabel() {
    final lvl = findUrgencyLevel(_urgencyId);
    if (lvl == null) return '—';
    if (_urgencyId == 'scheduled' && _scheduledAt != null) {
      return _formatScheduled(_scheduledAt!);
    }
    if (_urgencyId == 'immediate') return '${lvl.name} · ETA 22–35 דקות';
    return '${lvl.name} · ${lvl.sub}';
  }

  // ── Decoration helpers ───────────────────────────────────────────────────

  InputDecoration _input({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(fontSize: 12, color: _MTP.textTertiary),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: _MTP.borderSecondary, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: _MTP.borderSecondary, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: _MTP.purple500, width: 1),
        ),
        filled: true,
        fillColor: _MTP.bgPrimary,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _LivePill extends StatefulWidget {
  const _LivePill();

  @override
  State<_LivePill> createState() => _LivePillState();
}

class _LivePillState extends State<_LivePill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: const Color(0xFF5DCAA5)
                    .withValues(alpha: 0.5 + 0.5 * _ctrl.value),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'זמין כעת',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  const _HeroStat({
    required this.label,
    required this.value,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFFCECBF6),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          Text(
            sub,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFFCECBF6),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyHeading extends StatelessWidget {
  final IconData icon;
  final String title;
  const _ReadOnlyHeading({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: _MTP.purple50,
            borderRadius: BorderRadius.circular(5),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 12, color: _MTP.purple500),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: _MTP.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final String value;
  const _PriceRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: _MTP.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _MTP.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _MTP.purple50,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 14, color: _MTP.purple500),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: _MTP.textTertiary,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _MTP.textPrimary,
                    height: 1.4,
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

class _TrustItem extends StatelessWidget {
  final IconData icon;
  final String label;
  const _TrustItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: _MTP.green500),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: _MTP.green700,
          ),
        ),
      ],
    );
  }
}

class _BookingStep extends StatelessWidget {
  final int number;
  final String title;
  final String description;
  final Widget child;
  const _BookingStep({
    required this.number,
    required this.title,
    required this.description,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: _MTP.purple500,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$number',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
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
                  color: _MTP.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 30),
          child: Text(
            description,
            style: const TextStyle(
              fontSize: 12,
              color: _MTP.textSecondary,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _MiniLabel extends StatelessWidget {
  final String text;
  const _MiniLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: _MTP.textPrimary,
      ),
    );
  }
}

/// Segmented chip for the Wolt-style map pin-mode toggle (מאיפה / לאן).
class _PinToggleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color iconColor;
  final bool active;
  final VoidCallback onTap;
  const _PinToggleChip({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? _MTP.bgPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: _MTP.borderTertiary.withValues(alpha: 0.5),
                      blurRadius: 0,
                      spreadRadius: 0.5,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: active ? _MTP.textPrimary : _MTP.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UrgencyCard extends StatelessWidget {
  final MotorcycleUrgencyLevel level;
  final bool selected;
  final VoidCallback onTap;
  const _UrgencyCard({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _MTP.purple50 : _MTP.bgPrimary,
          border: Border.all(
            color: selected ? _MTP.purple500 : _MTP.borderTertiary,
            width: selected ? 1 : 0.5,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        level.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: selected
                              ? _MTP.purple700
                              : _MTP.textPrimary,
                        ),
                      ),
                      if (level.surchargePercent > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: _MTP.amber50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '+${level.surchargePercent.round()}%',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: _MTP.amber800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    level.sub,
                    style: const TextStyle(
                      fontSize: 11,
                      color: _MTP.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              size: 16,
              color:
                  selected ? _MTP.purple500 : _MTP.borderSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
