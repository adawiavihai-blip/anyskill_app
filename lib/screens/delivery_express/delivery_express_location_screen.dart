// Delivery Express — Step 2 of 4: "מאיפה לאן?" (pickup + dropoff + photos
// + optional recipient details).
//
// Mirrors FlashAuctionLocationScreen — same Wolt-style centred pin, same
// AddressInput + GeocodingService integration, same OSM tile fallback,
// same photo upload pattern. The only delivery-specific additions:
//   • Optional recipient name + phone fields under the addresses
//     (visible to the matched courier only — anonymity preserved until
//     selectOffer succeeds, see CLAUDE.md §76 babysitter pattern).
//   • Apartment / access notes captured in each `_LocationRow` and
//     stored on the location doc's `details` field.
//
// On "שדר את הקריאה לשליחים":
//   1. Validates BOTH pins have GPS coords (CF requires finite lat/lng to
//      find nearby providers — same constraint as Flash Auction).
//   2. Uploads photos to Storage at `delivery_express_photos/{uid}/`
//      (Storage rules clone from `flash_auction_photos/`).
//   3. Computes distanceKm via Haversine (lat/lng).
//   4. Calls DeliveryExpressService.createAuction(...).
//   5. On success — pushes DeliveryExpressSearchingScreen with the new id.
import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../models/delivery_express.dart';
import '../../services/delivery_express_service.dart';
import '../../services/geocoding_service.dart';
import '../../services/location_service.dart';
import '../../widgets/address_input.dart';
import '../../widgets/wolt_tile_layer.dart';
import '../../utils/error_mapper.dart';
import 'delivery_express_palette.dart';
import 'delivery_express_searching_screen.dart';

class DeliveryExpressLocationScreen extends StatefulWidget {
  final String packageType;
  final String urgencyReason;
  final String packageDescription;

  const DeliveryExpressLocationScreen({
    super.key,
    required this.packageType,
    required this.urgencyReason,
    this.packageDescription = '',
  });

  @override
  State<DeliveryExpressLocationScreen> createState() =>
      _DeliveryExpressLocationScreenState();
}

class _DeliveryExpressLocationScreenState
    extends State<DeliveryExpressLocationScreen> {
  static const _kDefaultCenter = LatLng(32.0853, 34.7818); // Tel Aviv

  final MapController _mapCtrl = MapController();
  final TextEditingController _pickupCtrl = TextEditingController();
  final TextEditingController _dropoffCtrl = TextEditingController();
  final TextEditingController _pickupDetailsCtrl = TextEditingController();
  final TextEditingController _dropoffDetailsCtrl = TextEditingController();
  final TextEditingController _recipientNameCtrl = TextEditingController();
  final TextEditingController _recipientPhoneCtrl = TextEditingController();

  String _activePin = 'pickup';

  LatLng? _pickupLatLng;
  LatLng? _dropoffLatLng;
  LatLng _mapCenter = _kDefaultCenter;

  final List<String> _photoUrls = [];
  bool _uploadingPhoto = false;
  bool _broadcasting = false;

  Timer? _pickupGeocodeTimer;
  Timer? _dropoffGeocodeTimer;
  bool _pickupGeocoding = false;
  bool _dropoffGeocoding = false;
  bool _suppressTextListeners = false;
  String? _lastPickupQuery;
  String? _lastDropoffQuery;

  static const _kGeocodeDebounce = Duration(milliseconds: 800);
  static const _kPlaceholderTexts = {
    'המיקום הנוכחי שלך',
    'מסומן על המפה',
  };

  int _pickupAddressVersion = 0;
  int _dropoffAddressVersion = 0;

  @override
  void initState() {
    super.initState();
    _pickupCtrl.addListener(_onPickupChanged);
    _dropoffCtrl.addListener(_onDropoffChanged);
    _bootstrapGps();
  }

  Future<void> _bootstrapGps() async {
    try {
      final cached = LocationService.cached;
      Position? pos = cached;
      pos ??= await LocationService.requestAndGet(context);
      if (pos == null || !mounted) return;
      final ll = LatLng(pos.latitude, pos.longitude);
      _suppressTextListeners = true;
      setState(() {
        _pickupLatLng = ll;
        _mapCenter = ll;
        _pickupCtrl.text = 'המיקום הנוכחי שלך';
      });
      _suppressTextListeners = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapCtrl.move(ll, 14);
      });
    } catch (_) {
      _suppressTextListeners = false;
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
    _pickupDetailsCtrl.dispose();
    _dropoffDetailsCtrl.dispose();
    _recipientNameCtrl.dispose();
    _recipientPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _commitActivePin() async {
    final pinned = _mapCenter;
    final forPickup = _activePin == 'pickup';
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

    _suppressTextListeners = true;
    setState(() {
      if (forPickup) {
        _pickupGeocoding = false;
        _pickupCtrl.text = combined;
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

  void _onPickupChanged() => _scheduleGeocode(forPickup: true);
  void _onDropoffChanged() => _scheduleGeocode(forPickup: false);

  void _scheduleGeocode({required bool forPickup}) {
    if (_suppressTextListeners) return;
    final ctrl = forPickup ? _pickupCtrl : _dropoffCtrl;
    final text = ctrl.text.trim();
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
    if (_kPlaceholderTexts.contains(text)) return;
    final last = forPickup ? _lastPickupQuery : _lastDropoffQuery;
    if (last == text) return;

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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapCtrl.move(result, 15);
      });
    }
  }

  /// Inline Haversine — same formula as MotorcycleTowBookingService.haversineKm.
  /// We can't import that service here (it's motorcycle-specific). Pure math,
  /// 12 lines.
  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0; // Earth radius (km).
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  double get _estimatedDistanceKm {
    if (_pickupLatLng == null || _dropoffLatLng == null) return 0;
    return _haversineKm(
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
    if (_pickupLatLng == null) return false;
    if (_dropoffLatLng == null) return false;
    return true;
  }

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
          .ref('delivery_express_photos/$uid/$ts.$ext');
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

    final pickup = DeliveryExpressLocation(
      address: _pickupCtrl.text.trim(),
      details: _pickupDetailsCtrl.text.trim(),
      lat: _pickupLatLng?.latitude,
      lng: _pickupLatLng?.longitude,
    );
    final dropoff = DeliveryExpressLocation(
      address: _dropoffCtrl.text.trim(),
      details: _dropoffDetailsCtrl.text.trim(),
      lat: _dropoffLatLng?.latitude,
      lng: _dropoffLatLng?.longitude,
    );
    final photoUrls = List<String>.unmodifiable(_photoUrls);
    final distanceKm = _estimatedDistanceKm;

    try {
      final auctionId = await DeliveryExpressService.createAuction(
        customerId: user.uid,
        customerName: user.displayName ?? '',
        packageType: widget.packageType,
        urgencyReason: widget.urgencyReason,
        packageDescription: widget.packageDescription,
        recipientName: _recipientNameCtrl.text.trim(),
        recipientPhone: _recipientPhoneCtrl.text.trim(),
        pickup: pickup,
        dropoff: dropoff,
        distanceKm: distanceKm,
        photoUrls: photoUrls,
      );
      if (!mounted) return;
      navigator.pushReplacement(
        MaterialPageRoute(
          builder: (_) => DeliveryExpressSearchingScreen(
            auctionId: auctionId,
            packageType: widget.packageType,
            urgencyReason: widget.urgencyReason,
            packageDescription: widget.packageDescription,
            recipientName: _recipientNameCtrl.text.trim(),
            recipientPhone: _recipientPhoneCtrl.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: DeliveryExpressPalette.bgPrimary,
        appBar: AppBar(
          backgroundColor: DeliveryExpressPalette.bgPrimary,
          surfaceTintColor: DeliveryExpressPalette.bgPrimary,
          elevation: 0.5,
          centerTitle: false,
          iconTheme: const IconThemeData(
            color: DeliveryExpressPalette.textPrimary,
          ),
          title: const Text(
            'מאיפה לאן?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: DeliveryExpressPalette.textPrimary,
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
                        addressCtrl: _pickupCtrl,
                        detailsCtrl: _pickupDetailsCtrl,
                        addressVersion: _pickupAddressVersion,
                        label: 'מאיפה לאסוף',
                        icon: Icons.my_location_rounded,
                        iconColor: DeliveryExpressPalette.green500,
                        detailsHint: 'דירה / קומה / קוד שער (לא חובה)',
                        onTapMap: () =>
                            setState(() => _activePin = 'pickup'),
                        showMapHint: _pickupLatLng == null,
                        geocoding: _pickupGeocoding,
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
                        addressCtrl: _dropoffCtrl,
                        detailsCtrl: _dropoffDetailsCtrl,
                        addressVersion: _dropoffAddressVersion,
                        label: 'לאן למסור',
                        icon: Icons.place_rounded,
                        iconColor: DeliveryExpressPalette.gold700,
                        detailsHint: 'דירה / קומה / הוראות גישה (לא חובה)',
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
                      _buildRecipientBox(),
                      const SizedBox(height: 18),
                      _buildPhotosHeader(),
                      const SizedBox(height: 6),
                      _buildPhotos(),
                      const SizedBox(height: 8),
                      const Text(
                        'תיעוד מקדים מגן עליך מטענות על נזקים. אפשר לדלג ולשלוח בלי תמונות.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: DeliveryExpressPalette.textTertiary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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

  Widget _buildPinModeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: DeliveryExpressPalette.bgSecondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _PinModeChip(
            label: 'איסוף',
            icon: Icons.my_location_rounded,
            iconColor: DeliveryExpressPalette.green500,
            active: _activePin == 'pickup',
            onTap: () => setState(() => _activePin = 'pickup'),
          ),
          _PinModeChip(
            label: 'מסירה',
            icon: Icons.place_rounded,
            iconColor: DeliveryExpressPalette.gold700,
            active: _activePin == 'dropoff',
            onTap: () => setState(() => _activePin = 'dropoff'),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DeliveryExpressPalette.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DeliveryExpressPalette.borderTertiary,
          width: 0.5,
        ),
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
                              color: DeliveryExpressPalette.green500,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 2),
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
                              color: DeliveryExpressPalette.gold700,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 2),
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
              IgnorePointer(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: Icon(
                      _activePin == 'pickup'
                          ? Icons.my_location_rounded
                          : Icons.place_rounded,
                      color: _activePin == 'pickup'
                          ? DeliveryExpressPalette.green500
                          : DeliveryExpressPalette.gold700,
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
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Material(
                  color: _activePin == 'pickup'
                      ? DeliveryExpressPalette.green500
                      : DeliveryExpressPalette.gold700,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: _commitActivePin,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.push_pin_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _activePin == 'pickup'
                                ? 'הצב כאן את נקודת האיסוף'
                                : 'הצב כאן את נקודת המסירה',
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
        color: DeliveryExpressPalette.gold50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: DeliveryExpressPalette.gold200,
          width: 0.5,
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: DeliveryExpressPalette.gold700,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 12,
                  color: DeliveryExpressPalette.gold900,
                  height: 1.5,
                ),
                children: [
                  TextSpan(
                    text: 'טיפ: ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text:
                        'גרור את המפה כדי שהסיכה הירוקה תפול על נקודת האיסוף — לחץ "הצב כאן" — ואז עבור ללשונית "מסירה" וחזור על הצעד.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecipientBox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: DeliveryExpressPalette.bgSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: DeliveryExpressPalette.borderTertiary,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.person_outline_rounded,
                size: 16,
                color: DeliveryExpressPalette.textSecondary,
              ),
              const SizedBox(width: 6),
              const Text(
                'פרטי הנמען (לא חובה)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: DeliveryExpressPalette.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: DeliveryExpressPalette.gold50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'מומלץ',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: DeliveryExpressPalette.gold900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'יישלח רק לשליח שנבחר — לא חשוף בהצעות',
            style: TextStyle(
              fontSize: 11.5,
              color: DeliveryExpressPalette.textTertiary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _PlainField(
                  controller: _recipientNameCtrl,
                  hint: 'שם הנמען',
                  icon: Icons.badge_outlined,
                  keyboardType: TextInputType.name,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PlainField(
                  controller: _recipientPhoneCtrl,
                  hint: 'טלפון נמען',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d\-\s]')),
                    LengthLimitingTextInputFormatter(14),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhotosHeader() {
    return Row(
      children: [
        const Text(
          'תמונת החבילה',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: DeliveryExpressPalette.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 7,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: DeliveryExpressPalette.amber50,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'מומלץ',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: DeliveryExpressPalette.amber800,
            ),
          ),
        ),
        const Spacer(),
        Text(
          '${_photoUrls.length} / 4',
          style: const TextStyle(
            fontSize: 11,
            color: DeliveryExpressPalette.textTertiary,
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
                      color: DeliveryExpressPalette.bgSecondary,
                      child: const Icon(
                        Icons.broken_image_outlined,
                        size: 18,
                        color: DeliveryExpressPalette.textTertiary,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => setState(() => _photoUrls.removeAt(i)),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.close_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          return InkWell(
            onTap: _uploadingPhoto ? null : _pickPhoto,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: DeliveryExpressPalette.bgSecondary,
                border: Border.all(
                  color: DeliveryExpressPalette.borderSecondary,
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
                          color: DeliveryExpressPalette.gold500,
                        ),
                      ),
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_rounded,
                          size: 22,
                          color: DeliveryExpressPalette.gold500,
                        ),
                        SizedBox(height: 2),
                        Text(
                          'הוסף',
                          style: TextStyle(
                            fontSize: 11,
                            color: DeliveryExpressPalette.gold500,
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
            color: active
                ? DeliveryExpressPalette.bgPrimary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: DeliveryExpressPalette.borderTertiary
                          .withValues(alpha: 0.5),
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
                      ? DeliveryExpressPalette.textPrimary
                      : DeliveryExpressPalette.textSecondary,
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
  final TextEditingController addressCtrl;
  final TextEditingController detailsCtrl;
  final String label;
  final IconData icon;
  final Color iconColor;
  final String detailsHint;
  final VoidCallback onTapMap;
  final bool showMapHint;
  final bool geocoding;
  final ValueChanged<LatLng>? onCoordinatesResolved;
  final int addressVersion;

  const _LocationRow({
    required this.addressCtrl,
    required this.detailsCtrl,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.detailsHint,
    required this.onTapMap,
    required this.showMapHint,
    this.geocoding = false,
    this.onCoordinatesResolved,
    this.addressVersion = 0,
  });

  @override
  Widget build(BuildContext context) {
    final initial = AddressValue.fromCombined(addressCtrl.text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: DeliveryExpressPalette.bgSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: DeliveryExpressPalette.borderTertiary,
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
                    color: DeliveryExpressPalette.textTertiary,
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
                      horizontal: 8,
                      vertical: 4,
                    ),
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
            key: ValueKey(
              'delivery-express-addr-${addressCtrl.hashCode}-$addressVersion',
            ),
            initialCity: initial.city,
            initialStreet: initial.street,
            accentColor: iconColor,
            dense: true,
            onChanged: (v) {
              if (addressCtrl.text != v.combined) {
                addressCtrl.text = v.combined;
              }
            },
            onCoordinatesResolved: (coords) {
              if (coords != null && onCoordinatesResolved != null) {
                onCoordinatesResolved!(coords);
              }
            },
          ),
          const SizedBox(height: 6),
          _PlainField(
            controller: detailsCtrl,
            hint: detailsHint,
            icon: Icons.notes_rounded,
            keyboardType: TextInputType.text,
          ),
        ],
      ),
    );
  }
}

class _PlainField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _PlainField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: DeliveryExpressPalette.bgPrimary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: DeliveryExpressPalette.borderSecondary,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 14,
            color: DeliveryExpressPalette.textTertiary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              style: const TextStyle(
                fontSize: 13,
                color: DeliveryExpressPalette.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  fontSize: 12.5,
                  color: DeliveryExpressPalette.textTertiary,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
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
          const Icon(
            Icons.straighten_rounded,
            size: 13,
            color: DeliveryExpressPalette.green500,
          ),
          const SizedBox(width: 4),
          Text(
            'מרחק משוער: ~${km.toStringAsFixed(1)} ק"מ',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DeliveryExpressPalette.green700,
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
        color: DeliveryExpressPalette.bgPrimary,
        border: Border(
          top: BorderSide(
            color: DeliveryExpressPalette.borderTertiary,
            width: 0.5,
          ),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: enabled ? onTap : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: DeliveryExpressPalette.gold500,
            disabledBackgroundColor: DeliveryExpressPalette.borderSecondary
                .withValues(alpha: 0.55),
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
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.send_rounded, size: 17),
                    SizedBox(width: 8),
                    Text(
                      'שדר את הקריאה לשליחים',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
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
    if (needsPickup) parts.add("איסוף");
    if (needsDropoff) parts.add("מסירה");
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
          const Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: Color(0xFFB45309),
          ),
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
                  TextSpan(text: which),
                  const TextSpan(
                    text:
                        " — בלי מיקום מדויק השליחים לא יקבלו את הקריאה.",
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
