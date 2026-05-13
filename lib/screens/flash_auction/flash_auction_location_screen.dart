// Flash Auction — Step 2 of 4: "מאיפה לאן?" (location + optional photos).
//
// Customer marks pickup + dropoff via Wolt-style flutter_map (centered pin
// that the map moves under). Free-text override + GPS auto-fill on first
// load. Photo upload is OPTIONAL — emphasized "מומלץ" but skippable.
//
// On "שדר את הקריאה לגרריסטים":
//   1. Validates pickup is set + dropoff has at least an address.
//   2. Uploads photos to Storage (`flash_auction_photos/{customerUid}/...`)
//      in parallel, capped at 4.
//   3. Computes distanceKm via Haversine.
//   4. Calls FlashAuctionService.createAuction(...).
//   5. On success — pushes FlashAuctionSearchingScreen with the new
//      auctionId. On failure — friendly Hebrew snackbar.
//
// Layout per mockup §2 (customer-flow.html lines 181-227): map at top
// (180px tall), tip banner, two address rows ("מאיפה" + "לאן"), photos
// strip, sticky CTA "שדר את הקריאה לגרריסטים".
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../models/flash_auction.dart';
import '../../services/flash_auction_service.dart';
import '../../services/geocoding_service.dart';
import '../../services/location_service.dart';
import '../../services/motorcycle_tow_booking_service.dart';
import '../../widgets/address_input.dart';
import '../../widgets/wolt_tile_layer.dart';
import '../../utils/error_mapper.dart';
import 'flash_auction_palette.dart';
import 'flash_auction_searching_screen.dart';

class FlashAuctionLocationScreen extends StatefulWidget {
  /// Issue id from the previous step. Forwarded into auction creation.
  final String issueType;

  const FlashAuctionLocationScreen({super.key, required this.issueType});

  @override
  State<FlashAuctionLocationScreen> createState() =>
      _FlashAuctionLocationScreenState();
}

class _FlashAuctionLocationScreenState
    extends State<FlashAuctionLocationScreen> {
  static const _kDefaultCenter = LatLng(32.0853, 34.7818); // Tel Aviv

  final MapController _mapCtrl = MapController();
  final TextEditingController _pickupCtrl = TextEditingController();
  final TextEditingController _dropoffCtrl = TextEditingController();

  /// Which pin is currently being placed via the centred-marker pattern.
  /// 'pickup' or 'dropoff'. Toggle via the segmented control above the map.
  String _activePin = 'pickup';

  LatLng? _pickupLatLng;
  LatLng? _dropoffLatLng;

  /// Current map centre — updated on every move event so the centred-pin
  /// stays in sync. Read at "שמור" tap to commit the active pin.
  LatLng _mapCenter = _kDefaultCenter;

  final List<String> _photoUrls = [];
  bool _uploadingPhoto = false;

  bool _broadcasting = false;

  // ── Forward-geocoding (typed address → pin on map) ──────────────────
  // Debounce timers ensure we hit Nominatim at most once per ~800ms even
  // if the user is mid-typing. Nominatim's usage policy is max 1 req/sec.
  Timer? _pickupGeocodeTimer;
  Timer? _dropoffGeocodeTimer;
  // Inline status — true while a geocoding request is in flight, used to
  // show a tiny spinner inside the text-field's trailing icon.
  bool _pickupGeocoding = false;
  bool _dropoffGeocoding = false;
  // Suppression flag: set true when the field text is being changed by
  // code (bootstrap GPS auto-fill, "מסומן על המפה" placeholder writes,
  // or the geocoder itself rewriting the field). We do NOT want any of
  // those to re-trigger the geocoder — only genuine user typing.
  bool _suppressTextListeners = false;
  // The last query a side already geocoded — prevents an immediate
  // re-geocode if the listener fires twice for the same text.
  String? _lastPickupQuery;
  String? _lastDropoffQuery;

  static const _kGeocodeDebounce = Duration(milliseconds: 800);

  /// Strings that we KNOW we wrote programmatically — never geocode these.
  /// "מסומן על המפה" stays here for legacy users; new pin commits resolve
  /// the real street via reverse-geocoding so this fallback rarely renders.
  static const _kPlaceholderTexts = {
    'המיקום הנוכחי שלך',
    'מסומן על המפה',
  };

  /// Bumped every time we commit a pin via the map so the wrapping
  /// AddressInput unmounts + remounts with the freshly-typed initial values.
  /// AddressInput is uncontrolled-style (parent never pushes values in
  /// after mount) so a key change is the cleanest way to force a reset.
  int _pickupAddressVersion = 0;
  int _dropoffAddressVersion = 0;

  @override
  void initState() {
    super.initState();
    _pickupCtrl.addListener(_onPickupChanged);
    _dropoffCtrl.addListener(_onDropoffChanged);
    _bootstrapGps();
  }

  /// Best-effort: drop the pickup pin on the customer's current GPS.
  /// If permission is denied / GPS unavailable, the map stays at the
  /// default centre and the user picks manually.
  Future<void> _bootstrapGps() async {
    try {
      final cached = LocationService.cached;
      Position? pos = cached;
      pos ??= await LocationService.requestAndGet(context);
      if (pos == null || !mounted) return;
      final ll = LatLng(pos.latitude, pos.longitude);
      // Suppress the text listener — we're writing a placeholder, not
      // user-typed input, so we don't want to re-geocode our own write.
      _suppressTextListeners = true;
      setState(() {
        _pickupLatLng = ll;
        _mapCenter = ll;
        _pickupCtrl.text = 'המיקום הנוכחי שלך';
      });
      _suppressTextListeners = false;
      // Defer move to next frame so MapController is ready.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapCtrl.move(ll, 14);
      });
    } catch (_) {
      _suppressTextListeners = false;
      // Silent — manual placement is the fallback.
    }
  }

  @override
  void dispose() {
    _pickupGeocodeTimer?.cancel();
    _dropoffGeocodeTimer?.cancel();
    _pickupCtrl.removeListener(_onPickupChanged);
    _dropoffCtrl.removeListener(_onDropoffChanged);
    _pickupCtrl.dispose();
    _dropoffCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  Future<void> _commitActivePin() async {
    final pinned = _mapCenter;
    final forPickup = _activePin == 'pickup';

    // Commit the pin immediately so the customer sees the marker land
    // even while the reverse-geocode round-trip is in flight.
    _suppressTextListeners = true;
    setState(() {
      if (forPickup) {
        _pickupLatLng = pinned;
        _pickupGeocoding = true;
        if (_pickupCtrl.text.isEmpty) _pickupCtrl.text = 'מסומן על המפה';
      } else {
        _dropoffLatLng = pinned;
        _dropoffGeocoding = true;
        if (_dropoffCtrl.text.isEmpty) _dropoffCtrl.text = 'מסומן על המפה';
      }
    });
    _suppressTextListeners = false;

    // Reverse-geocode so the address text field auto-syncs with the
    // map pin (Wolt-style). On any failure the placeholder above stays.
    final result = await GeocodingService.reverseGeocode(pinned);
    if (!mounted) return;

    if (result == null) {
      setState(() {
        if (forPickup) {
          _pickupGeocoding = false;
        } else {
          _dropoffGeocoding = false;
        }
      });
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
      // Nominatim returned a hit but no usable structured fields — fall
      // back to the display_name so the user sees SOMETHING real.
      combined = result.displayName.trim();
    } else if (streetPart.isEmpty) {
      combined = city;
    } else if (city.isEmpty) {
      combined = streetPart;
    } else {
      combined = '$streetPart, $city';
    }

    _suppressTextListeners = true;
    setState(() {
      if (forPickup) {
        _pickupGeocoding = false;
        _pickupCtrl.text = combined;
        // Cache the query so the typed-address geocoder doesn't re-fire
        // on this exact text in the next debounce window.
        _lastPickupQuery = combined;
        _pickupAddressVersion++;
      } else {
        _dropoffGeocoding = false;
        _dropoffCtrl.text = combined;
        _lastDropoffQuery = combined;
        _dropoffAddressVersion++;
      }
    });
    _suppressTextListeners = false;
  }

  // ── Forward geocoding — typed address triggers a debounced lookup ───
  // The pattern is the same for pickup + dropoff: cancel any in-flight
  // timer, skip placeholder/system writes, then after 800ms of typing
  // pause we hit Nominatim. On result we move the map + drop the pin.

  void _onPickupChanged() => _scheduleGeocode(forPickup: true);
  void _onDropoffChanged() => _scheduleGeocode(forPickup: false);

  void _scheduleGeocode({required bool forPickup}) {
    if (_suppressTextListeners) return;
    final ctrl = forPickup ? _pickupCtrl : _dropoffCtrl;
    final text = ctrl.text.trim();

    // Reset state if the user cleared the field — pin stays where it was,
    // but the lastQuery tracker is wiped so a later re-type re-geocodes.
    if (text.isEmpty) {
      if (forPickup) {
        _pickupGeocodeTimer?.cancel();
        _lastPickupQuery = null;
      } else {
        _dropoffGeocodeTimer?.cancel();
        _lastDropoffQuery = null;
      }
      return;
    }

    // Skip our own placeholder writes (bootstrap GPS + "מסומן על המפה").
    if (_kPlaceholderTexts.contains(text)) return;

    // Already geocoded this exact text? Skip — no need to spam Nominatim.
    final last = forPickup ? _lastPickupQuery : _lastDropoffQuery;
    if (last == text) return;

    // Debounce — only fire when the user stops typing for 800ms.
    if (forPickup) {
      _pickupGeocodeTimer?.cancel();
      _pickupGeocodeTimer = Timer(_kGeocodeDebounce, () {
        _runGeocode(forPickup: true, query: text);
      });
    } else {
      _dropoffGeocodeTimer?.cancel();
      _dropoffGeocodeTimer = Timer(_kGeocodeDebounce, () {
        _runGeocode(forPickup: false, query: text);
      });
    }
  }

  Future<void> _runGeocode({
    required bool forPickup,
    required String query,
  }) async {
    if (!mounted) return;
    // Re-check the field hasn't been cleared / placeholder-overwritten
    // since the timer started.
    final ctrl = forPickup ? _pickupCtrl : _dropoffCtrl;
    if (ctrl.text.trim() != query) return;
    if (_kPlaceholderTexts.contains(query)) return;

    setState(() {
      if (forPickup) {
        _pickupGeocoding = true;
      } else {
        _dropoffGeocoding = true;
      }
    });

    final result = await GeocodingService.forwardGeocode(query);

    if (!mounted) return;
    // The user might have typed more characters while the request was
    // in flight — only commit if the field still matches what we asked.
    if (ctrl.text.trim() != query) {
      setState(() {
        if (forPickup) {
          _pickupGeocoding = false;
        } else {
          _dropoffGeocoding = false;
        }
      });
      return;
    }

    setState(() {
      if (forPickup) {
        _pickupGeocoding = false;
        _lastPickupQuery = query;
        if (result != null) {
          _pickupLatLng = result;
          _mapCenter = result;
          _activePin = 'pickup';
        }
      } else {
        _dropoffGeocoding = false;
        _lastDropoffQuery = query;
        if (result != null) {
          _dropoffLatLng = result;
          _mapCenter = result;
          _activePin = 'dropoff';
        }
      }
    });

    if (result != null) {
      // Defer the map move to the next frame so MapController has been
      // attached if the screen just opened.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapCtrl.move(result, 15);
      });
    }
  }

  double get _estimatedDistanceKm {
    if (_pickupLatLng == null || _dropoffLatLng == null) return 0;
    return MotorcycleTowBookingService.haversineKm(
      _pickupLatLng!.latitude,
      _pickupLatLng!.longitude,
      _dropoffLatLng!.latitude,
      _dropoffLatLng!.longitude,
    );
  }

  bool get _canBroadcast {
    if (_broadcasting) return false;
    if (_pickupCtrl.text.trim().isEmpty) return false;
    if (_dropoffCtrl.text.trim().isEmpty) return false;
    // CLAUDE.md §57 — Flash Auction dispatch CF (_faFindNearbyProviders)
    // requires pickup lat/lng to be finite numbers. Without GPS coords
    // the CF silently returns 0 candidates and no provider gets notified.
    // Block the CTA until BOTH pins are pinned on the map.
    if (_pickupLatLng == null) return false;
    if (_dropoffLatLng == null) return false;
    return true;
  }

  /// True when the user typed an address but didn't pin its GPS yet.
  /// We surface a help text in this case rather than just greying out
  /// the CTA — otherwise the user has no idea why the button is locked.
  bool get _needsPickupPin =>
      _pickupCtrl.text.trim().isNotEmpty && _pickupLatLng == null;
  bool get _needsDropoffPin =>
      _dropoffCtrl.text.trim().isNotEmpty && _dropoffLatLng == null;

  Future<void> _pickPhoto() async {
    if (_uploadingPhoto || _photoUrls.length >= 4) return;
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 75,
    );
    if (file == null || !mounted) return;
    setState(() => _uploadingPhoto = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await file.readAsBytes();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = file.name.split('.').last.toLowerCase();
      final mime = ext == 'png'
          ? 'image/png'
          : ext == 'webp'
              ? 'image/webp'
              : 'image/jpeg';
      final ref = FirebaseStorage.instance
          .ref('flash_auction_photos/$uid/$ts.$ext');
      await ref.putData(bytes, SettableMetadata(contentType: mime));
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() {
        _photoUrls.add(url);
        _uploadingPhoto = false;
      });
    } catch (e) {
      if (mounted) setState(() => _uploadingPhoto = false);
      messenger.showSnackBar(SnackBar(content: Text('שגיאה בהעלאה: $e')));
    }
  }

  Future<void> _broadcast() async {
    if (!_canBroadcast) return;
    setState(() => _broadcasting = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _broadcasting = false);
      return;
    }
    final navigator = Navigator.of(context);
    // Build the two FlashAuctionLocation values ONCE — we forward them
    // to both `createAuction` AND the searching screen so the "נסה שנית"
    // CTA can re-broadcast without re-walking through the wizard.
    final pickup = FlashAuctionLocation(
      address: _pickupCtrl.text.trim(),
      lat: _pickupLatLng?.latitude,
      lng: _pickupLatLng?.longitude,
    );
    final dropoff = FlashAuctionLocation(
      address: _dropoffCtrl.text.trim(),
      lat: _dropoffLatLng?.latitude,
      lng: _dropoffLatLng?.longitude,
    );
    final photoUrls = List<String>.unmodifiable(_photoUrls);
    final distanceKm = _estimatedDistanceKm;
    try {
      final auctionId = await FlashAuctionService.createAuction(
        customerId: user.uid,
        customerName: user.displayName ?? '',
        issueType: widget.issueType,
        pickup: pickup,
        dropoff: dropoff,
        distanceKm: distanceKm,
        photoUrls: photoUrls,
      );
      if (!mounted) return;
      // Pop the location screen off the stack and replace with searching.
      navigator.pushReplacement(
        MaterialPageRoute(
          builder: (_) => FlashAuctionSearchingScreen(
            auctionId: auctionId,
            issueType: widget.issueType,
            pickup: pickup,
            dropoff: dropoff,
            distanceKm: distanceKm,
            photoUrls: photoUrls,
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _broadcasting = false);
      if (mounted) ErrorMapper.show(context, e);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: FlashPalette.bgPrimary,
        appBar: AppBar(
          backgroundColor: FlashPalette.bgPrimary,
          surfaceTintColor: FlashPalette.bgPrimary,
          elevation: 0.5,
          centerTitle: false,
          iconTheme: const IconThemeData(color: FlashPalette.textPrimary),
          title: const Text(
            'איפה אתה — ולאן?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: FlashPalette.textPrimary,
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildPinModeToggle(),
                      const SizedBox(height: 8),
                      _buildMap(),
                      const SizedBox(height: 10),
                      _buildMapTip(),
                      const SizedBox(height: 12),
                      _LocationRow(
                        controller: _pickupCtrl,
                        addressVersion: _pickupAddressVersion,
                        label: 'מיקום הגרירה',
                        icon: Icons.my_location_rounded,
                        iconColor: FlashPalette.green500,
                        onTapMap: () =>
                            setState(() => _activePin = 'pickup'),
                        showMapHint: _pickupLatLng == null,
                        geocoding: _pickupGeocoding,
                        // Fast path — when the user picks a street from the
                        // AddressInput dropdown, we already have lat/lng from
                        // Nominatim. Commit it directly + move the map, no
                        // second forward-geocode round-trip.
                        onCoordinatesResolved: (coords) {
                          setState(() {
                            _pickupLatLng = coords;
                            _mapCenter = coords;
                            _activePin = 'pickup';
                          });
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _mapCtrl.move(coords, 15);
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      _LocationRow(
                        controller: _dropoffCtrl,
                        addressVersion: _dropoffAddressVersion,
                        label: 'לאן (יעד)',
                        icon: Icons.place_rounded,
                        iconColor: FlashPalette.purple500,
                        onTapMap: () =>
                            setState(() => _activePin = 'dropoff'),
                        showMapHint: _dropoffLatLng == null,
                        geocoding: _dropoffGeocoding,
                        onCoordinatesResolved: (coords) {
                          setState(() {
                            _dropoffLatLng = coords;
                            _mapCenter = coords;
                            _activePin = 'dropoff';
                          });
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _mapCtrl.move(coords, 15);
                          });
                        },
                      ),
                      if (_estimatedDistanceKm > 0) ...[
                        const SizedBox(height: 8),
                        _DistanceLine(km: _estimatedDistanceKm),
                      ],
                      const SizedBox(height: 18),
                      _buildPhotosHeader(),
                      const SizedBox(height: 6),
                      _buildPhotos(),
                      const SizedBox(height: 8),
                      const Text(
                        'תיעוד מקדים מגן עליך מטענות על נזקים. אפשר לדלג ולשלוח בלי תמונות.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: FlashPalette.textTertiary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Inline warning — surface the exact reason the CTA is locked
              // when the user typed text but didn't pin GPS on the map.
              // Without coords, the CF returns 0 candidates silently and
              // no provider gets notified (CLAUDE.md §57).
              if (_needsPickupPin || _needsDropoffPin)
                _MissingPinWarning(
                  needsPickup: _needsPickupPin,
                  needsDropoff: _needsDropoffPin,
                ),
              _CtaBar(
                enabled: _canBroadcast,
                broadcasting: _broadcasting,
                onTap: _broadcast,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Pin mode toggle (pickup / dropoff) ───────────────────────────────

  Widget _buildPinModeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: FlashPalette.bgSecondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _PinModeChip(
            label: 'מאיפה',
            icon: Icons.my_location_rounded,
            iconColor: FlashPalette.green500,
            active: _activePin == 'pickup',
            onTap: () => setState(() => _activePin = 'pickup'),
          ),
          _PinModeChip(
            label: 'לאן',
            icon: Icons.place_rounded,
            iconColor: FlashPalette.purple500,
            active: _activePin == 'dropoff',
            onTap: () => setState(() => _activePin = 'dropoff'),
          ),
        ],
      ),
    );
  }

  // ── Map (Wolt-style centred pin) ─────────────────────────────────────

  Widget _buildMap() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FlashPalette.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FlashPalette.borderTertiary, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 220,
          width: double.infinity,
          child: Stack(
        children: [
          FlutterMap(
            mapController: _mapCtrl,
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
              // Unified Wolt-style tiles. WoltTileLayer ships with an OSM
              // fallbackUrl + loading skeleton, so it now gives us BOTH
              // visual consistency AND the OSM-level reliability the old
              // bare-OSM call site was after. See CLAUDE.md §78.
              WoltTileLayer.forContext(context, maxZoom: 19),
              MarkerLayer(
                markers: [
                  if (_pickupLatLng != null)
                    Marker(
                      point: _pickupLatLng!,
                      width: 26,
                      height: 26,
                      child: Container(
                        decoration: BoxDecoration(
                          color: FlashPalette.green500,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.my_location_rounded,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ),
                  if (_dropoffLatLng != null)
                    Marker(
                      point: _dropoffLatLng!,
                      width: 26,
                      height: 32,
                      alignment: Alignment.topCenter,
                      child: Container(
                        decoration: BoxDecoration(
                          color: FlashPalette.purple500,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.place_rounded,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          // Centred pin (always visible — that's the Wolt UX).
          IgnorePointer(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: Icon(
                  _activePin == 'pickup'
                      ? Icons.my_location_rounded
                      : Icons.place_rounded,
                  color: _activePin == 'pickup'
                      ? FlashPalette.green500
                      : FlashPalette.purple500,
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
          // Bottom-overlay "save this point" button.
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Material(
              color: _activePin == 'pickup'
                  ? FlashPalette.green500
                  : FlashPalette.purple500,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: _commitActivePin,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.push_pin_rounded,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        _activePin == 'pickup'
                            ? 'הצב כאן את נקודת המוצא'
                            : 'הצב כאן את נקודת היעד',
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

  Widget _buildMapTip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: FlashPalette.purple50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: FlashPalette.purple200, width: 0.5),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 16, color: FlashPalette.purple500),
          SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 12,
                  color: FlashPalette.purple700,
                  height: 1.5,
                ),
                children: [
                  TextSpan(
                    text: 'טיפ: ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text:
                        'גרור את המפה כדי שהסיכה הירוקה תפול על המיקום שלך — לחץ "הצב כאן" — ואז עבור ללשונית "לאן" וחזור על הצעד.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotosHeader() {
    return Row(
      children: [
        const Text(
          'תמונות של האופנוע',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: FlashPalette.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: FlashPalette.amber50,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'מומלץ',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: FlashPalette.amber800,
            ),
          ),
        ),
        const Spacer(),
        Text(
          '${_photoUrls.length} / 4',
          style: const TextStyle(
            fontSize: 11,
            color: FlashPalette.textTertiary,
          ),
        ),
      ],
    );
  }

  Widget _buildPhotos() {
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          if (i < _photoUrls.length) {
            final url = _photoUrls[i];
            return Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    url,
                    width: 78,
                    height: 78,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 78,
                      height: 78,
                      color: FlashPalette.bgSecondary,
                      child: const Icon(Icons.broken_image_outlined,
                          size: 18, color: FlashPalette.textTertiary),
                    ),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _photoUrls.removeAt(i)),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.close_rounded,
                          size: 13, color: Colors.white),
                    ),
                  ),
                ),
              ],
            );
          }
          // Empty slot — tappable add.
          return InkWell(
            onTap: _uploadingPhoto ? null : _pickPhoto,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: FlashPalette.bgSecondary,
                border: Border.all(
                  color: FlashPalette.borderSecondary,
                  width: 0.5,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _uploadingPhoto && i == _photoUrls.length
                  ? const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: FlashPalette.purple500,
                        ),
                      ),
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_rounded,
                            size: 22, color: FlashPalette.purple500),
                        SizedBox(height: 2),
                        Text(
                          'הוסף',
                          style: TextStyle(
                            fontSize: 11,
                            color: FlashPalette.purple500,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════════

class _PinModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color iconColor;
  final bool active;
  final VoidCallback onTap;

  const _PinModeChip({
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
            color: active ? FlashPalette.bgPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: active
                ? [
                    BoxShadow(
                      color:
                          FlashPalette.borderTertiary.withValues(alpha: 0.5),
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
                  color: active
                      ? FlashPalette.textPrimary
                      : FlashPalette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTapMap;
  final bool showMapHint;
  final bool geocoding;
  final ValueChanged<LatLng>? onCoordinatesResolved;

  /// Bumped by the parent every time a map-pin commit reverse-geocoded a
  /// fresh address into [controller]. Wired into the AddressInput key so
  /// the widget unmounts + remounts with the freshly-typed initial values
  /// (AddressInput is uncontrolled-style — see address_input.dart docs).
  final int addressVersion;

  const _LocationRow({
    required this.controller,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.onTapMap,
    required this.showMapHint,
    this.geocoding = false,
    this.onCoordinatesResolved,
    this.addressVersion = 0,
  });

  @override
  Widget build(BuildContext context) {
    // Parse the legacy single-string controller value into city + street
    // so AddressInput can hydrate. Re-parsed on every rebuild — cheap, and
    // it lets the bootstrap GPS placeholder "המיקום הנוכחי שלך" land in
    // street when the parent sets it.
    final initial = AddressValue.fromCombined(controller.text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: FlashPalette.bgSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: FlashPalette.borderTertiary,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: FlashPalette.textTertiary,
                  ),
                ),
              ),
              if (geocoding)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: iconColor,
                  ),
                )
              else if (showMapHint)
                TextButton(
                  onPressed: onTapMap,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'סמן על המפה',
                    style: TextStyle(
                      fontSize: 11,
                      color: iconColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          AddressInput(
            // Key includes the controller hashCode AND the address-version
            // counter so the widget re-seeds its internal city + street
            // text fields whenever the parent reverse-geocoded a fresh
            // address from a map-pin commit. User typing does NOT bump
            // the counter — so live typing keeps focus + cursor position.
            key: ValueKey('flash-addr-${controller.hashCode}-$addressVersion'),
            initialCity: initial.city,
            initialStreet: initial.street,
            accentColor: iconColor,
            dense: true,
            onChanged: (v) {
              // Pipe back into the legacy controller so the existing
              // _scheduleGeocode listener + _canBroadcast check keep firing.
              if (controller.text != v.combined) {
                controller.text = v.combined;
              }
            },
            onCoordinatesResolved: (coords) {
              if (coords != null && onCoordinatesResolved != null) {
                onCoordinatesResolved!(coords);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _DistanceLine extends StatelessWidget {
  final double km;
  const _DistanceLine({required this.km});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          const Icon(Icons.straighten_rounded,
              size: 13, color: FlashPalette.green500),
          const SizedBox(width: 4),
          Text(
            'מרחק משוער: ~${km.toStringAsFixed(1)} ק"מ',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: FlashPalette.green700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CtaBar extends StatelessWidget {
  final bool enabled;
  final bool broadcasting;
  final VoidCallback onTap;

  const _CtaBar({
    required this.enabled,
    required this.broadcasting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      decoration: const BoxDecoration(
        color: FlashPalette.bgPrimary,
        border: Border(
          top: BorderSide(color: FlashPalette.borderTertiary, width: 0.5),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: enabled ? onTap : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: FlashPalette.purple500,
            disabledBackgroundColor:
                FlashPalette.borderSecondary.withValues(alpha: 0.55),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: broadcasting
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'משדר...',
                      style: TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w700),
                    ),
                  ],
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.send_rounded, size: 17),
                    SizedBox(width: 8),
                    Text(
                      'שדר את הקריאה לגרריסטים',
                      style: TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}


class _MissingPinWarning extends StatelessWidget {
  final bool needsPickup;
  final bool needsDropoff;
  const _MissingPinWarning({
    required this.needsPickup,
    required this.needsDropoff,
  });

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (needsPickup) parts.add("מאיפה");
    if (needsDropoff) parts.add("לאן");
    final which = parts.join(" + ");
    return Container(
      margin: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDBA74), width: 0.6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 16, color: Color(0xFFB45309)),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF92400E),
                  height: 1.5,
                ),
                children: [
                  const TextSpan(
                    text: "סמן על המפה: ",
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: which,
                  ),
                  const TextSpan(
                    text:
                        " — בלי מיקום מדויק הגרריסטים לא יקבלו את הקריאה.",
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
