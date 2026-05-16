/// AnySkill — Live Travel Map
///
/// Inline OpenStreetMap shown on the customer's booking card while the
/// provider is on the way (`expertOnWay == true && workStartedAt == null`).
/// Streams `provider_live_location/{providerUid}` via [LiveLocationService]
/// and renders a pulsing indigo dot at the provider's current position.
///
/// Renders the real map UNCONDITIONALLY when at least one anchor coordinate
/// is available — pickup, dropoff, or live provider GPS. The previous
/// "waiting for location" loading rect (a pale-blue box) made the card look
/// like a grey placeholder when the provider hadn't started broadcasting
/// yet. Now the customer sees their pickup + destination pins immediately,
/// and the pulsing provider dot fades in on top once GPS arrives.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/live_location_service.dart';
import 'wolt_tile_layer.dart';

class LiveTravelMap extends StatefulWidget {
  final String providerUid;
  final double height;

  /// Pickup coordinates from the job doc (motorcycle tow / flash auction:
  /// `motorcycleTowPreferences.pickupLat/Lng`; legacy bookings:
  /// top-level `clientLat/Lng`). Renders a green pin when non-null.
  final double? pickupLat;
  final double? pickupLng;

  /// Destination coordinates from the job doc. Renders a purple pin when
  /// non-null. For non-tow bookings this can be left null.
  final double? dropoffLat;
  final double? dropoffLng;

  const LiveTravelMap({
    super.key,
    required this.providerUid,
    this.height = 180,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
  });

  @override
  State<LiveTravelMap> createState() => _LiveTravelMapState();
}

class _LiveTravelMapState extends State<LiveTravelMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  /// Drives auto-follow — recentering the camera on the provider as their
  /// GPS updates so the customer never has to pan to find the moving pin.
  final MapController _mapController = MapController();

  /// Last provider position the camera was recentered on. Null until the
  /// first GPS fix.
  LatLng? _followed;

  /// Zoom used on the first provider fix — close enough to see them clearly.
  static const double _kFollowZoom = 15.0;

  static const _kFallbackCenter = LatLng(32.0853, 34.7818); // Tel Aviv

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  LatLng? get _pickup => (widget.pickupLat != null && widget.pickupLng != null)
      ? LatLng(widget.pickupLat!, widget.pickupLng!)
      : null;

  LatLng? get _dropoff =>
      (widget.dropoffLat != null && widget.dropoffLng != null)
          ? LatLng(widget.dropoffLat!, widget.dropoffLng!)
          : null;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LiveLocation?>(
      stream: LiveLocationService.streamLocation(widget.providerUid),
      builder: (context, snap) {
        final loc = snap.data;
        final provider =
            loc != null ? LatLng(loc.lat, loc.lng) : null;
        // Auto-follow: the moment the provider's GPS arrives (or moves),
        // recenter the map on them so the customer sees the provider right
        // away without panning. The first fix snaps to a close zoom; later
        // updates keep whatever zoom the customer chose.
        // (קובי נגר, 2026-05-17.)
        if (provider != null && provider != _followed) {
          final isFirstFix = _followed == null;
          _followed = provider;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            try {
              final z = isFirstFix
                  ? _kFollowZoom
                  : _mapController.camera.zoom;
              _mapController.move(provider, z);
            } catch (_) {
              // Map not attached on the very first frame — the
              // initialCenter already handles that case.
            }
          });
        }
        return _buildMap(provider);
      },
    );
  }

  Widget _buildMap(LatLng? provider) {
    // Pick an initial centre — prefer the live provider, then pickup, then
    // dropoff, then a sensible national fallback (Tel Aviv).
    final centre = provider ?? _pickup ?? _dropoff ?? _kFallbackCenter;

    // Tighter zoom when we only have a single anchor; wider when we have
    // both pickup + dropoff so the customer sees the whole trip context.
    final hasPickup = _pickup != null;
    final hasDropoff = _dropoff != null;
    final zoom = (hasPickup && hasDropoff) ? 13.5 : 15.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: centre,
                initialZoom: zoom,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                ),
              ),
              children: [
                WoltTileLayer.forContext(context, maxZoom: 19),
                MarkerLayer(
                  markers: [
                    if (_pickup != null) _pickupMarker(_pickup!),
                    if (_dropoff != null) _dropoffMarker(_dropoff!),
                    if (provider != null) _providerMarker(provider),
                  ],
                ),
              ],
            ),
            if (provider == null) _waitingBanner(),
          ],
        ),
      ),
    );
  }

  /// Small floating banner shown across the top of the map while we're
  /// waiting for the provider's first GPS write. The map (pickup +
  /// destination) is still visible underneath — the banner just tells the
  /// customer that the moving pin hasn't arrived yet.
  Widget _waitingBanner() {
    return Positioned(
      top: 8,
      left: 8,
      right: 8,
      child: IgnorePointer(
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF3B82F6)),
              ),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'ממתין למיקום של נותן השירות…',
                  style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1E40AF),
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Marker _pickupMarker(LatLng point) {
    return Marker(
      point: point,
      width: 28,
      height: 28,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF10B981),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 4,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.my_location_rounded,
            size: 13, color: Colors.white),
      ),
    );
  }

  Marker _dropoffMarker(LatLng point) {
    return Marker(
      point: point,
      width: 28,
      height: 32,
      alignment: Alignment.topCenter,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF8B5CF6),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 4,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.place_rounded, size: 13, color: Colors.white),
      ),
    );
  }

  Marker _providerMarker(LatLng point) {
    return Marker(
      point: point,
      width: 60,
      height: 60,
      child: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (_, __) {
          final v = _pulseCtrl.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 50 + 14 * v,
                height: 50 + 14 * v,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF6366F1)
                      .withValues(alpha: 0.20 * (1 - v)),
                ),
              ),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF6366F1),
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
