/// AnySkill — Walk Route Screen
///
/// Interactive map of a single dog walk. Shows the full GPS polyline,
/// start (green) + end (red) markers, distance, duration, and the static
/// OpenStreetMap thumbnail as a fallback. Streams the doc in real time so
/// in-progress walks animate as the provider moves.
///
/// Opened from:
///   * The customer's chat — tapping a `walk_summary` system message
///   * The customer's job card — "View Walk Route" link (future)
///
/// Uses the existing `flutter_map` + `latlong2` stack — no API key needed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/dog_walk_service.dart';

class WalkRouteScreen extends StatelessWidget {
  final String walkId;

  const WalkRouteScreen({super.key, required this.walkId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('מסלול ההליכון'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
      ),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: DogWalkService.watchWalk(walkId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data;
          if (data == null) {
            return const Center(
              child: Text('הליכון לא נמצא',
                  style: TextStyle(color: Colors.grey, fontSize: 16)),
            );
          }
          final pathRaw = (data['path'] as List? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(DogWalkPoint.fromMap)
              .toList();
          if (pathRaw.isEmpty) {
            return const Center(
              child: Text('אין עדיין נקודות במסלול',
                  style: TextStyle(color: Colors.grey, fontSize: 16)),
            );
          }
          final points = pathRaw.map((p) => LatLng(p.lat, p.lng)).toList();
          final status = data['status'] as String? ?? 'walking';
          final isLive = status == 'walking';
          final distanceM =
              (data['totalDistanceMeters'] as num? ?? 0).toDouble();
          final durationSec =
              (data['totalDurationSeconds'] as num? ?? 0).toInt();

          // Compute centroid for initial framing
          double sumLat = 0, sumLng = 0;
          for (final p in points) {
            sumLat += p.latitude;
            sumLng += p.longitude;
          }
          final center = LatLng(sumLat / points.length, sumLng / points.length);

          return Column(
            children: [
              // ── Stats banner ──────────────────────────────────────────
              Container(
                width: double.infinity,
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: Row(
                  children: [
                    if (isLive) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fiber_manual_record,
                                color: Colors.red, size: 10),
                            SizedBox(width: 4),
                            Text(
                              'בהליכון',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    _stat(
                      icon: Icons.straighten_rounded,
                      label: 'מרחק',
                      value: '${(distanceM / 1000).toStringAsFixed(2)} ק"מ',
                    ),
                    const SizedBox(width: 18),
                    _stat(
                      icon: Icons.timer_outlined,
                      label: 'משך',
                      value: _formatDuration(durationSec),
                    ),
                    const Spacer(),
                    Text(
                      '${points.length} נקודות',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              // ── Interactive map ───────────────────────────────────────
              Expanded(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 15,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.anyskill.app',
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: points,
                          color: const Color(0xFF6366F1),
                          strokeWidth: 5,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: points.first,
                          width: 32,
                          height: 32,
                          child: const Icon(
                            Icons.play_circle_filled_rounded,
                            color: Color(0xFF10B981),
                            size: 32,
                          ),
                        ),
                        Marker(
                          point: points.last,
                          width: 32,
                          height: 32,
                          child: Icon(
                            isLive
                                ? Icons.directions_walk_rounded
                                : Icons.stop_circle_rounded,
                            color: isLive
                                ? Colors.red
                                : const Color(0xFFEF4444),
                            size: 32,
                          ),
                        ),
                      ],
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

  Widget _stat({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF6366F1)),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: const TextStyle(
              fontSize: 11, color: Color(0xFF6B7280)),
        ),
        Text(
          value,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E)),
        ),
      ],
    );
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '$h ש׳ $m ד׳';
    return '$m ד׳';
  }
}
