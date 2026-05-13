// Step 2 of the babysitter emergency flow — Wolt-style address picker.
//
// Critical inputs collected:
//   • formattedAddress  — text (auto-filled from reverse geocode if GPS)
//   • apartmentNumber   — REQUIRED for any apartment building
//   • accessNotes       — REQUIRED — gate code, parking, which floor
//   • lat / lng         — from GPS or pin drag
//
// Bound to the existing app conventions:
//   • flutter_map + WoltTileLayer (matches §53 babysitter address picker)
//   • Centered pin / map moves underneath (Wolt pattern)
//   • LocationService.requestAndGet (NOT raw Geolocator) per Law 47
//
// On "שדר את הקריאה לבייביסיטרים":
//   1. Validate (address + apartment + access notes mandatory)
//   2. BabysitterEmergencyService.createEmergency()
//   3. Push BabysitterEmergencySearchingScreen
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/babysitter_emergency.dart';
import '../../services/babysitter_emergency_service.dart';
import '../../services/geocoding_service.dart';
import '../../services/location_service.dart';
import '../../utils/error_mapper.dart';
import '../../widgets/address_input.dart';
import '../../widgets/wolt_tile_layer.dart';
import 'babysitter_emergency_palette.dart';
import 'babysitter_emergency_safety_dialog.dart';
import 'babysitter_emergency_searching_screen.dart';

class BabysitterEmergencyLocationScreen extends StatefulWidget {
  final String reason;
  final int numChildren;
  final List<String> childrenAgeGroups;
  final DateTime agreedStartTime;
  final DateTime agreedEndTime;
  final String specialNotes;

  const BabysitterEmergencyLocationScreen({
    super.key,
    required this.reason,
    required this.numChildren,
    required this.childrenAgeGroups,
    required this.agreedStartTime,
    required this.agreedEndTime,
    required this.specialNotes,
  });

  @override
  State<BabysitterEmergencyLocationScreen> createState() =>
      _BabysitterEmergencyLocationScreenState();
}

class _BabysitterEmergencyLocationScreenState
    extends State<BabysitterEmergencyLocationScreen> {
  // Tel Aviv default — overridden by GPS or user pan.
  static const _kDefaultCenter = LatLng(32.0853, 34.7818);

  final _mapCtrl = MapController();
  // City + street are driven by the AddressInput widget — kept as plain
  // state strings here so the submit + validation paths can build the
  // legacy `formattedAddress` via `AddressValue.combined`.
  String _city = '';
  String _street = '';
  int _addressEpoch = 0;
  final _aptCtrl = TextEditingController();
  final _accessCtrl = TextEditingController();

  LatLng _pinLocation = _kDefaultCenter;
  bool _pinAdjusted = false;
  bool _loadingGps = false;
  bool _submitting = false;

  Timer? _reverseDebounce;
  bool _reverseLoading = false;

  @override
  void initState() {
    super.initState();
    _bootstrapGps();
  }

  @override
  void dispose() {
    _mapCtrl.dispose();
    _aptCtrl.dispose();
    _accessCtrl.dispose();
    _reverseDebounce?.cancel();
    super.dispose();
  }

  String get _combinedAddress =>
      AddressValue(city: _city, street: _street).combined;

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
          _addressEpoch++;
        }
      });
    });
  }

  Future<void> _bootstrapGps() async {
    setState(() => _loadingGps = true);
    try {
      // Use the project's resilient location service (web-safe, has
      // its own permission flow + fallback to JS-interop on web).
      final pos = await LocationService.requestAndGet(context);
      if (!mounted || pos == null) return;
      setState(() {
        _pinLocation = LatLng(pos.latitude, pos.longitude);
      });
      _mapCtrl.move(_pinLocation, 16.5);
    } catch (_) {
      // Silent — user can still pan + drop the pin.
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  void _moveTo(LatLng target, {bool adjusted = true}) {
    setState(() {
      _pinLocation = target;
      _pinAdjusted = adjusted;
    });
    if (adjusted) _scheduleReverseGeocode();
  }

  bool get _canSubmit =>
      _combinedAddress.trim().isNotEmpty &&
      _aptCtrl.text.trim().isNotEmpty &&
      _accessCtrl.text.trim().isNotEmpty &&
      !_submitting;

  Future<void> _onSubmit() async {
    if (!_canSubmit) {
      // Soft prompt — gentle nudge instead of hard error.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'יש למלא את הכתובת, מספר הדירה והוראות הגישה — חיוני למטפלת שמגיעה ראשונה אליכם'),
          backgroundColor: BabyEmergencyPalette.amber500,
        ),
      );
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _submitting = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw 'יש להתחבר כדי להמשיך';

      final location = BabysitterEmergencyLocation(
        formattedAddress: _combinedAddress.trim(),
        apartmentNumber: _aptCtrl.text.trim(),
        accessNotes: _accessCtrl.text.trim(),
        lat: _pinLocation.latitude,
        lng: _pinLocation.longitude,
        pinAdjusted: _pinAdjusted,
      );

      final emergencyId =
          await BabysitterEmergencyService.createEmergency(
        customerId: user.uid,
        customerName: user.displayName ?? '',
        reason: widget.reason,
        numChildren: widget.numChildren,
        childrenAgeGroups: widget.childrenAgeGroups,
        agreedStartTime: widget.agreedStartTime,
        agreedEndTime: widget.agreedEndTime,
        location: location,
        specialNotes: widget.specialNotes,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => BabysitterEmergencySearchingScreen(
            emergencyId: emergencyId,
            reason: widget.reason,
            numChildren: widget.numChildren,
            agreedStartTime: widget.agreedStartTime,
            agreedEndTime: widget.agreedEndTime,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ErrorMapper.show(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: BabyEmergencyPalette.bgPrimary,
        appBar: AppBar(
          backgroundColor: BabyEmergencyPalette.bgPrimary,
          elevation: 0,
          title: const Text(
            'איפה צריך את המטפלת?',
            style: TextStyle(
              color: BabyEmergencyPalette.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          iconTheme: const IconThemeData(
              color: BabyEmergencyPalette.textPrimary),
          actions: [
            IconButton(
              tooltip: 'מדריך בטיחות',
              icon: const Icon(Icons.health_and_safety_rounded,
                  color: BabyEmergencyPalette.purple500),
              onPressed: () =>
                  showBabysitterEmergencySafetyDialog(context),
            ),
            IconButton(
              tooltip: 'השתמש במיקום הנוכחי',
              onPressed: _loadingGps ? null : _bootstrapGps,
              icon: _loadingGps
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location_rounded,
                      color: BabyEmergencyPalette.purple500),
            ),
          ],
        ),
        body: Column(
          children: [
            // ── Address fields ─────────────────────────────────────────
            Container(
              color: BabyEmergencyPalette.bgPrimary,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Column(
                children: [
                  // Smart two-field autocomplete. `_addressEpoch` causes
                  // the widget to remount after a reverse-geocode pin drag
                  // so the new city/street propagate as initial values.
                  AddressInput(
                    key: ValueKey('babysitter-emergency-addr-$_addressEpoch'),
                    initialCity: _city,
                    initialStreet: _street,
                    accentColor: BabyEmergencyPalette.purple500,
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
                            child:
                                CircularProgressIndicator(strokeWidth: 1.5),
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
                        flex: 1,
                        child: _buildField(
                          controller: _aptCtrl,
                          label: 'דירה / קומה / כניסה *',
                          hint: '12 / 3',
                          icon: Icons.apartment_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildField(
                    controller: _accessCtrl,
                    label: 'הוראות גישה *',
                    hint: 'קוד שער · חניה · "פעמון תקול, נא להתקשר"',
                    icon: Icons.key_rounded,
                    maxLines: 2,
                    maxLength: 200,
                  ),
                ],
              ),
            ),

            // ── Map ─────────────────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapCtrl,
                    options: MapOptions(
                      initialCenter: _pinLocation,
                      initialZoom: 16,
                      onTap: (_, latLng) => _moveTo(latLng),
                      onPositionChanged: (pos, hasGesture) {
                        if (!hasGesture) return;
                        _moveTo(pos.center, adjusted: true);
                      },
                    ),
                    children: [
                      WoltTileLayer.forContext(context),
                    ],
                  ),
                  // Centred pin (Wolt-style — pin fixed, map moves)
                  IgnorePointer(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 36),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: BabyEmergencyPalette.pink400,
                            border:
                                Border.all(color: Colors.white, width: 3),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(11),
                          child: const Icon(
                            Icons.home_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Hint
                  if (!_pinAdjusted)
                    PositionedDirectional(
                      top: 12,
                      start: 12,
                      end: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '✋ הזיזי את המפה כדי לסמן את המיקום המדויק של הבית',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        // ── Sticky CTA ────────────────────────────────────────────────
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: const BoxDecoration(
              color: BabyEmergencyPalette.bgPrimary,
              border: Border(
                top: BorderSide(
                  color: BabyEmergencyPalette.borderTertiary,
                  width: 1,
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: const [
                    Icon(Icons.lock_rounded,
                        size: 14,
                        color: BabyEmergencyPalette.textTertiary),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'הכתובת המדויקת תיחשף רק למטפלת שתבחרי',
                        style: TextStyle(
                          color: BabyEmergencyPalette.textTertiary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _canSubmit ? _onSubmit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BabyEmergencyPalette.pink400,
                      disabledBackgroundColor:
                          BabyEmergencyPalette.borderSecondary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.bolt_rounded, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'שדר את הקריאה לבייביסיטרים',
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      onChanged: (_) => setState(() {}), // re-evaluate _canSubmit
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: BabyEmergencyPalette.purple500),
        labelStyle: const TextStyle(
          color: BabyEmergencyPalette.textSecondary,
          fontSize: 13.5,
        ),
        hintStyle: const TextStyle(
          color: BabyEmergencyPalette.textTertiary,
          fontSize: 13,
        ),
        filled: true,
        fillColor: BabyEmergencyPalette.bgSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
              color: BabyEmergencyPalette.borderTertiary),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
              color: BabyEmergencyPalette.borderTertiary),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
              color: BabyEmergencyPalette.purple500, width: 1.5),
        ),
        isDense: true,
        counterText: '',
      ),
    );
  }
}
