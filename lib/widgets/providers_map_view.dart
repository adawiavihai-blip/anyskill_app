import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import '../utils/safe_image_provider.dart';
import '../services/navigation_launcher_service.dart';
import '../theme/app_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AnySkill Provider Map View — v9.9.0
//
// flutter_map (OSM) based map that displays provider markers with:
//   • Custom indigo markers with profile images
//   • Green glow ring for online providers
//   • Tappable markers → info card with photo, rating, "Request Now" button
//   • Dynamic radius circle overlay
//   • Debounced map-move callbacks for re-querying
// ═══════════════════════════════════════════════════════════════════════════════

// v12.9.0: legacy MapPalette.primary/_kGreen retired — use MapPalette instead.
// Gold is still needed only for the star rating glyph in the info card.
const _kGold       = Color(0xFFFBBF24);

/// Data model for a provider pin on the map.
class MapProvider {
  final String uid;
  final String name;
  final String? profileImage;
  final String? serviceType;
  final double? rating;
  final int? reviewsCount;
  final double lat;
  final double lng;
  final bool isOnline;
  final double? pricePerHour;

  const MapProvider({
    required this.uid,
    required this.name,
    this.profileImage,
    this.serviceType,
    this.rating,
    this.reviewsCount,
    required this.lat,
    required this.lng,
    required this.isOnline,
    this.pricePerHour,
  });

  LatLng get latLng => LatLng(lat, lng);
}

/// Callback when user taps "Request Now" on a marker info card.
typedef OnProviderTap = void Function(String uid);

class ProvidersMapView extends StatefulWidget {
  final List<MapProvider> providers;
  final LatLng? userLocation;
  final double radiusKm;
  final OnProviderTap onProviderTap;
  final OnProviderTap? onQuickChat;
  final ValueChanged<LatLng>? onMapMoved;
  /// v12.9.0: fired when user taps "Search this area" after panning.
  final VoidCallback? onSearchThisArea;
  /// v12.9.0 (PR-5): parent-driven selection — the map highlights this uid
  /// as the active marker AND skips rendering the legacy info card
  /// (the parent's carousel replaces it).
  final String? externalSelectedUid;
  /// v12.9.0 (PR-5): invoked when a marker is tapped. When provided, the
  /// widget delegates selection to the parent and does NOT render its own
  /// info card.
  final ValueChanged<String>? onMarkerTap;
  /// v12.9.0 (PR-5): parent-driven camera focus. Whenever this changes the
  /// map animates to the new LatLng.
  final LatLng? focusedLatLng;
  /// v12.9.0 (PR-5): bottom padding so side controls sit above the sheet.
  final double bottomSafeArea;

  const ProvidersMapView({
    super.key,
    required this.providers,
    this.userLocation,
    this.radiusKm = 20,
    required this.onProviderTap,
    this.onQuickChat,
    this.onMapMoved,
    this.onSearchThisArea,
    this.externalSelectedUid,
    this.onMarkerTap,
    this.focusedLatLng,
    this.bottomSafeArea = 20,
  });

  @override
  State<ProvidersMapView> createState() => _ProvidersMapViewState();
}

class _ProvidersMapViewState extends State<ProvidersMapView>
    with SingleTickerProviderStateMixin {
  final _mapCtrl = MapController();
  String? _selectedUid;

  // Default center: Tel Aviv
  static const _defaultCenter = LatLng(32.0853, 34.7818);

  LatLng get _center => widget.userLocation ?? _defaultCenter;

  // v12.9.0: pulsing My Location ring.
  late final AnimationController _pulseCtrl;

  // v12.9.0: track how far the user has panned from the original center so
  // we can show the "search this area" pill.
  LatLng? _lastQueriedCenter;
  LatLng? _currentMapCenter;
  bool _showSearchHere = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _lastQueriedCenter = widget.userLocation ?? _defaultCenter;
  }

  @override
  void didUpdateWidget(covariant ProvidersMapView old) {
    super.didUpdateWidget(old);
    // v12.9.0 (PR-5): parent moved focus (e.g. carousel swipe). Animate the
    // camera to the new location without changing zoom.
    if (widget.focusedLatLng != null &&
        widget.focusedLatLng != old.focusedLatLng) {
      try {
        _mapCtrl.move(widget.focusedLatLng!, _mapCtrl.camera.zoom);
      } catch (_) {
        // MapController may not yet be ready during first build.
      }
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  // v12.9.0 (PR-5): effective selection uses parent's value when provided.
  String? get _effectiveSelectedUid =>
      widget.externalSelectedUid ?? _selectedUid;

  // v12.9.0: build all provider markers once per rebuild, sharing the data
  // with MarkerClusterLayerWidget.
  List<Marker> _buildMarkers() =>
      widget.providers.map(_buildProviderMarker).toList();

  // v12.11.0: Pick the best initial camera.
  // - If we have user location → center on user at zoom 12.
  // - Else if we have providers → fit bounds around all markers.
  // - Else → center on Israel at zoom 8. Never zoom below 6.
  ({LatLng center, double zoom, LatLngBounds? bounds}) _initialCamera() {
    if (widget.userLocation != null) {
      return (center: widget.userLocation!, zoom: 12.0, bounds: null);
    }
    final pts = widget.providers
        .map((p) => p.latLng)
        .toList(growable: false);
    if (pts.isNotEmpty) {
      return (
        center: pts.first,
        zoom: _zoomForRadius(widget.radiusKm),
        bounds: LatLngBounds.fromPoints(pts),
      );
    }
    // Fallback: Israel center
    return (center: const LatLng(31.5, 34.8), zoom: 8.0, bounds: null);
  }

  @override
  Widget build(BuildContext context) {
    final markers = _buildMarkers();
    final cam = _initialCamera();
    return Stack(
      children: [
        // ── Map ─────────────────────────────────────────────────────────
        FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: cam.center,
            initialZoom: cam.zoom,
            minZoom: 6,
            maxZoom: 19,
            initialCameraFit: cam.bounds != null
                ? CameraFit.bounds(
                    bounds: cam.bounds!,
                    padding: const EdgeInsets.all(60),
                  )
                : null,
            // Don't clear selection on tap-outside when parent drives it
            // — the carousel is the source of truth in PR-5.
            onTap: widget.onMarkerTap == null
                ? (_, __) => setState(() => _selectedUid = null)
                : null,
            onPositionChanged: (pos, hasGesture) {
              _currentMapCenter = pos.center;
              if (hasGesture && widget.onMapMoved != null) {
                widget.onMapMoved!(pos.center);
              }
              // v12.9.0: show "search this area" after the user panned 400m+.
              if (hasGesture && _lastQueriedCenter != null) {
                const Distance dist = Distance();
                final moved = dist(_lastQueriedCenter!, pos.center);
                final shouldShow = moved > 400;
                if (shouldShow != _showSearchHere) {
                  setState(() => _showSearchHere = shouldShow);
                }
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              retinaMode: MediaQuery.of(context).devicePixelRatio > 1.5,
              userAgentPackageName: 'com.anyskill.app',
              maxZoom: 19,
            ),

            // Radius circle
            if (widget.userLocation != null)
              CircleLayer(circles: [
                CircleMarker(
                  point: widget.userLocation!,
                  radius: widget.radiusKm * 1000, // meters
                  useRadiusInMeter: true,
                  color: MapPalette.primary.withValues(alpha: 0.06),
                  borderColor: MapPalette.primary.withValues(alpha: 0.25),
                  borderStrokeWidth: 1.5,
                ),
              ]),

            // User location dot with pulsing ring
            if (widget.userLocation != null)
              MarkerLayer(markers: [
                Marker(
                  point: widget.userLocation!,
                  width: 60, height: 60,
                  child: _buildUserLocationPin(),
                ),
              ]),

            // Provider markers — grouped into clusters when dense.
            MarkerClusterLayerWidget(
              options: MarkerClusterLayerOptions(
                maxClusterRadius: 60,
                disableClusteringAtZoom: 16,
                size: const Size(48, 48),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(50),
                markers: markers,
                builder: (context, clusterMarkers) =>
                    _buildClusterBubble(clusterMarkers.length),
              ),
            ),
          ],
        ),

        // ── v12.9.0: "Search this area" pill (below the top bar/chips) ──
        if (_showSearchHere && widget.onSearchThisArea != null)
          Positioned(
            top: 172, left: 0, right: 0,
            child: Align(
              alignment: Alignment.topCenter,
              child: _buildSearchThisAreaButton(),
            ),
          ),

        // ── v12.9.0: Side controls (recenter · zoom in · zoom out) ───────
        PositionedDirectional(
          start: 12,
          bottom: widget.bottomSafeArea,
          child: _buildSideControls(),
        ),

        // ── Legacy info card (hidden when parent drives selection in PR-5) ──
        if (_selectedUid != null && widget.onMarkerTap == null)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: _buildInfoCard(),
          ),
      ],
    );
  }

  // v12.9.0: Pin = price tag + avatar + pointer + shadow.
  // Total size 90×104, anchored at bottomCenter so the pointer tip sits
  // exactly on the provider's coordinate.
  Marker _buildProviderMarker(MapProvider p) {
    final isSelected = p.uid == _effectiveSelectedUid;
    // v12.11.0: border reflects availability — green = online, red = offline,
    // gold = active/selected (overrides availability).
    final borderColor = isSelected
        ? MapPalette.goldActive
        : (p.isOnline ? MapPalette.online : MapPalette.red);
    final borderWidth = isSelected ? 3.5 : (p.isOnline ? 3.0 : 2.5);
    final priceText = (p.pricePerHour != null && p.pricePerHour! > 0)
        ? '₪${p.pricePerHour!.toStringAsFixed(0)}'
        : null;

    return Marker(
      point: p.latLng,
      width: 92,
      height: 104,
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
        onTap: () {
          // Parent-driven selection (PR-5). Fall back to internal state if
          // no callback was supplied so legacy callers still get the info
          // card behavior.
          if (widget.onMarkerTap != null) {
            widget.onMarkerTap!(p.uid);
          } else {
            setState(() => _selectedUid = p.uid);
          }
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Price tag
            if (priceText != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1D26),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  priceText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            if (priceText != null) const SizedBox(height: 2),
            // Avatar with border + glow + optional availability dot
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: isSelected ? 54 : 48,
                  height: isSelected ? 54 : 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: borderColor, width: borderWidth),
                    boxShadow: [
                      if (p.isOnline || isSelected)
                        BoxShadow(
                          color: (isSelected
                                  ? MapPalette.goldActive
                                  : MapPalette.online)
                              .withValues(alpha: 0.45),
                          blurRadius: isSelected ? 18 : 10,
                          spreadRadius: isSelected ? 2 : 0,
                        ),
                      const BoxShadow(
                        color: Color(0x26000000),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipOval(child: _buildMarkerImage(p)),
                ),
                if (p.isOnline)
                  Positioned(
                    bottom: -1,
                    right: -1,
                    child: Container(
                      width: 13, height: 13,
                      decoration: BoxDecoration(
                        color: MapPalette.online,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            // Pointer stalk
            Container(width: 2, height: 8, color: borderColor),
            // Tiny ground shadow
            Container(
              width: 18, height: 4,
              decoration: BoxDecoration(
                color: const Color(0x33000000),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarkerImage(MapProvider p) {
    final img = safeImageProvider(p.profileImage);
    if (img != null) {
      return Image(image: img, fit: BoxFit.cover);
    }
    // Initials fallback
    final initials = p.name.isNotEmpty ? p.name[0] : '?';
    return Container(
      color: MapPalette.primary.withValues(alpha: 0.1),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: MapPalette.primary,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  /// Haversine distance in km between two lat/lng points.
  double _distanceKm(LatLng a, LatLng b) {
    const R = 6371.0; // Earth radius in km
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLng = _deg2rad(b.longitude - a.longitude);
    final s = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(a.latitude)) *
            cos(_deg2rad(b.latitude)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return R * 2 * atan2(sqrt(s), sqrt(1 - s));
  }

  static double _deg2rad(double deg) => deg * (pi / 180);

  Widget _buildInfoCard() {
    final p = widget.providers.where((p) => p.uid == _selectedUid).firstOrNull;
    if (p == null) return const SizedBox.shrink();

    // Distance label
    String? distLabel;
    if (widget.userLocation != null) {
      final km = _distanceKm(widget.userLocation!, p.latLng);
      distLabel = km < 1
          ? 'בשכונתך'
          : '${km.toStringAsFixed(1)} ק"מ';
    }

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Top row: avatar + info ───────────────────────────────
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundImage: safeImageProvider(p.profileImage),
                  backgroundColor: MapPalette.primary.withValues(alpha: 0.1),
                  child: safeImageProvider(p.profileImage) == null
                      ? Text(p.name.isNotEmpty ? p.name[0] : '?',
                          style: const TextStyle(
                              color: MapPalette.primary, fontWeight: FontWeight.bold, fontSize: 18))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(p.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold)),
                          ),
                          if (p.isOnline) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('Online',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF16A34A),
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (p.rating != null && p.rating! > 0) ...[
                            const Icon(Icons.star_rounded, size: 14, color: _kGold),
                            const SizedBox(width: 2),
                            Text(p.rating!.toStringAsFixed(1),
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600)),
                            const SizedBox(width: 8),
                          ],
                          if (distLabel != null) ...[
                            Icon(Icons.near_me_rounded,
                                size: 13, color: Colors.grey[500]),
                            const SizedBox(width: 3),
                            Text(distLabel,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500)),
                          ],
                        ],
                      ),
                      if (p.pricePerHour != null && p.pricePerHour! > 0) ...[
                        const SizedBox(height: 2),
                        Text('₪${p.pricePerHour!.toStringAsFixed(0)}/שעה',
                            style: const TextStyle(
                                fontSize: 13,
                                color: MapPalette.primary,
                                fontWeight: FontWeight.w700)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // ── Bottom action row: Navigate / Chat / Profile ────────
            Row(
              children: [
                // Navigate button
                Expanded(
                  child: _infoCardAction(
                    icon: Icons.directions_car_rounded,
                    label: 'נווט',
                    color: const Color(0xFF10B981),
                    onTap: () => NavigationLauncherService.showPicker(
                      context,
                      lat: p.lat,
                      lng: p.lng,
                      destinationName: p.name,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Quick Chat button
                if (widget.onQuickChat != null)
                  Expanded(
                    child: _infoCardAction(
                      icon: Icons.chat_bubble_rounded,
                      label: 'הודעה',
                      color: const Color(0xFF6366F1),
                      onTap: () => widget.onQuickChat!(p.uid),
                    ),
                  ),
                if (widget.onQuickChat != null) const SizedBox(width: 8),
                // Profile button
                Expanded(
                  child: _infoCardAction(
                    icon: Icons.person_rounded,
                    label: 'פרופיל',
                    color: const Color(0xFF8B5CF6),
                    onTap: () => widget.onProviderTap(p.uid),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCardAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  /// Convert a radius in km to an appropriate map zoom level.
  double _zoomForRadius(double km) {
    if (km <= 2) return 15;
    if (km <= 5) return 13.5;
    if (km <= 10) return 12.5;
    if (km <= 20) return 11.5;
    if (km <= 50) return 10;
    return 9;
  }

  // ── v12.9.0: Pulsing My Location pin ──────────────────────────────────
  Widget _buildUserLocationPin() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, _) {
        // 0.0 → 1.0 loop. Ring scales 0.4→1.2 and fades 0.35→0.
        final t = _pulseCtrl.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            // Pulsing halo
            Opacity(
              opacity: (0.35 * (1.0 - t)).clamp(0.0, 0.35),
              child: Transform.scale(
                scale: 0.4 + (t * 0.8),
                child: Container(
                  width: 60, height: 60,
                  decoration: const BoxDecoration(
                    color: MapPalette.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            // Solid center dot
            Container(
              width: 18, height: 18,
              decoration: BoxDecoration(
                color: MapPalette.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: MapPalette.primary.withValues(alpha: 0.45),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ── v12.9.0: Cluster bubble ───────────────────────────────────────────
  Widget _buildClusterBubble(int count) {
    return Container(
      decoration: BoxDecoration(
        color: MapPalette.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ── v12.9.0: "Search this area" pill ───────────────────────────────────
  Widget _buildSearchThisAreaButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () {
          _lastQueriedCenter = _currentMapCenter ?? _lastQueriedCenter;
          setState(() => _showSearchHere = false);
          widget.onSearchThisArea?.call();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: MapPalette.primary, width: 1.5),
            boxShadow: MapShadows.floatingControl,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.refresh_rounded,
                  size: 16, color: MapPalette.primary),
              SizedBox(width: 6),
              Text(
                'חפש באזור הזה',
                style: TextStyle(
                  color: MapPalette.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── v12.9.0: Side controls (recenter · zoom in · zoom out) ─────────────
  Widget _buildSideControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.userLocation != null) ...[
          _SideBtn(
            icon: Icons.my_location_rounded,
            iconColor: MapPalette.primary,
            onTap: () {
              _mapCtrl.move(_center, _zoomForRadius(widget.radiusKm));
              _lastQueriedCenter = _center;
              setState(() => _showSearchHere = false);
            },
            tooltip: 'המיקום שלי',
          ),
          const SizedBox(height: 10),
        ],
        _SideBtn(
          icon: Icons.add_rounded,
          onTap: () {
            final z = _mapCtrl.camera.zoom;
            _mapCtrl.move(_mapCtrl.camera.center, (z + 1).clamp(1, 19));
          },
          tooltip: 'הגדל',
        ),
        const SizedBox(height: 8),
        _SideBtn(
          icon: Icons.remove_rounded,
          onTap: () {
            final z = _mapCtrl.camera.zoom;
            _mapCtrl.move(_mapCtrl.camera.center, (z - 1).clamp(1, 19));
          },
          tooltip: 'הקטן',
        ),
      ],
    );
  }
}

// ── Small circular side-control button ──────────────────────────────────
class _SideBtn extends StatelessWidget {
  final IconData icon;
  final Color?   iconColor;
  final VoidCallback onTap;
  final String? tooltip;
  const _SideBtn({
    required this.icon,
    this.iconColor,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42, height: 42,
          child: Icon(icon,
              size: 22,
              color: iconColor ?? MapPalette.textPrimary),
        ),
      ),
    );
    final decorated = DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: MapShadows.floatingControl,
      ),
      child: btn,
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: decorated) : decorated;
  }
}
