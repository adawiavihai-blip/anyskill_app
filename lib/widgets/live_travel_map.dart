/// AnySkill — Live Travel Map
///
/// Inline OpenStreetMap shown on the customer's booking card while the
/// provider is on the way (`expertOnWay == true && workStartedAt == null`).
/// Streams `provider_live_location/{providerUid}` via [LiveLocationService]
/// and renders a pulsing indigo dot at the provider's current position.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/live_location_service.dart';

class LiveTravelMap extends StatefulWidget {
  final String providerUid;
  final double height;

  const LiveTravelMap({
    super.key,
    required this.providerUid,
    this.height = 180,
  });

  @override
  State<LiveTravelMap> createState() => _LiveTravelMapState();
}

class _LiveTravelMapState extends State<LiveTravelMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LiveLocation?>(
      stream: LiveLocationService.streamLocation(widget.providerUid),
      builder: (context, snap) {
        final loc = snap.data;
        if (loc == null) {
          return Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.2)),
            ),
            alignment: Alignment.center,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF3B82F6)),
                ),
                SizedBox(width: 10),
                Text('ממתין למיקום של נותן השירות…',
                    style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF1E40AF),
                        fontWeight: FontWeight.w600)),
              ],
            ),
          );
        }
        final center = LatLng(loc.lat, loc.lng);
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: widget.height,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 15,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.anyskill.app',
                  maxZoom: 19,
                ),
                MarkerLayer(markers: [
                  Marker(
                    point: center,
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
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF6366F1),
                                border: Border.all(
                                    color: Colors.white, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF6366F1)
                                        .withValues(alpha: 0.5),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }
}
