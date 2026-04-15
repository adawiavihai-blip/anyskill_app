/// AnySkill — Live Walk Map (Pet Stay Tracker v13.0.0, Step 8)
///
/// Inline map shown on the owner's Pet Mode ONLY while a walk for the
/// current job is in progress (`dog_walks/{walkId}.status == 'walking'`).
/// Streams the walk doc in real time — the polyline lengthens and the
/// end-marker moves as the provider moves.
///
/// Renders nothing if no active walk — the parent conditionally includes
/// this widget, but we keep a belt-and-suspenders empty state inside.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class LiveWalkMap extends StatelessWidget {
  final String jobId;

  const LiveWalkMap({super.key, required this.jobId});

  Stream<DocumentSnapshot<Map<String, dynamic>>?> _activeWalkStream() async* {
    // Find the most recent walk for this job. We avoid a composite index
    // by filtering status client-side.
    final snaps = FirebaseFirestore.instance
        .collection('dog_walks')
        .where('jobId', isEqualTo: jobId)
        .orderBy('startedAt', descending: true)
        .limit(1)
        .snapshots();
    await for (final q in snaps) {
      if (q.docs.isEmpty) {
        yield null;
        continue;
      }
      final d = q.docs.first;
      final status = d.data()['status'] as String? ?? '';
      if (status == 'walking') {
        yield d;
      } else {
        yield null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
      stream: _activeWalkStream(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        final doc = snap.data;
        if (doc == null || !doc.exists) return const SizedBox.shrink();
        return _LiveMapBody(data: doc.data()!);
      },
    );
  }
}

class _LiveMapBody extends StatelessWidget {
  final Map<String, dynamic> data;

  const _LiveMapBody({required this.data});

  @override
  Widget build(BuildContext context) {
    final pathRaw = (data['path'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();

    final markersRaw = (data['markers'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();

    final points = <LatLng>[];
    for (final p in pathRaw) {
      final lat = (p['lat'] as num?)?.toDouble();
      final lng = (p['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        points.add(LatLng(lat, lng));
      }
    }

    int pee = 0;
    int poop = 0;
    for (final m in markersRaw) {
      if (m['type'] == 'pee') pee++;
      if (m['type'] == 'poop') poop++;
    }

    final startedAt = (data['startedAt'] as Timestamp?)?.toDate();
    final distanceM = (data['totalDistanceMeters'] as num? ?? 0).toDouble();
    final providerName = (data['providerName'] ?? '') as String;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF10B981), width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Live badge + provider
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFFECFDF5),
            child: Row(
              children: [
                const _PulsingDot(),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    providerName.isEmpty
                        ? '🚶 הליכון פעיל'
                        : '🚶 $providerName יצא להליכון',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Color(0xFF065F46),
                    ),
                  ),
                ),
                if (startedAt != null)
                  _LiveTimer(startedAt: startedAt),
              ],
            ),
          ),

          // Map
          SizedBox(
            height: 240,
            child: points.isEmpty
                ? const _WaitingForGps()
                : _buildMap(points, markersRaw),
          ),

          // Footer stats
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            color: Colors.white,
            child: Row(
              children: [
                _stat('מרחק',
                    '${(distanceM / 1000).toStringAsFixed(2)} ק"מ',
                    const Color(0xFF059669)),
                const SizedBox(width: 14),
                _stat('💧 פיפי', '$pee', const Color(0xFFCA8A04)),
                const SizedBox(width: 14),
                _stat('💩 קקי', '$poop', const Color(0xFF92400E)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(List<LatLng> points, List<Map<String, dynamic>> markers) {
    final markerWidgets = <Marker>[];

    // Pee/poop markers on the map
    for (final m in markers) {
      final lat = (m['lat'] as num?)?.toDouble();
      final lng = (m['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final type = m['type'] as String? ?? '';
      if (type != 'pee' && type != 'poop') continue;
      markerWidgets.add(Marker(
        point: LatLng(lat, lng),
        width: 28,
        height: 28,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            type == 'pee' ? '💧' : '💩',
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ));
    }

    // Start marker
    if (points.length > 1) {
      markerWidgets.add(Marker(
        point: points.first,
        width: 28,
        height: 28,
        child: const Icon(
          Icons.play_circle_filled_rounded,
          color: Color(0xFF10B981),
          size: 28,
        ),
      ));
    }

    // Current position (end of path) — pulsing green dot
    markerWidgets.add(Marker(
      point: points.last,
      width: 48,
      height: 48,
      child: const _PulsingPin(),
    ));

    return FlutterMap(
      options: MapOptions(
        initialCenter: points.last,
        initialZoom: 16,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.anyskill.app',
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: points,
              color: const Color(0xFF10B981),
              strokeWidth: 5,
            ),
          ],
        ),
        MarkerLayer(markers: markerWidgets),
      ],
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Row(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color)),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: Color(0xFF6B7280))),
      ],
    );
  }
}

class _WaitingForGps extends StatelessWidget {
  const _WaitingForGps();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF9FAFB),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(height: 10),
          Text(
            'ממתין לאיתור GPS...',
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1.0).animate(_c),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Color(0xFF10B981),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _PulsingPin extends StatefulWidget {
  const _PulsingPin();
  @override
  State<_PulsingPin> createState() => _PulsingPinState();
}

class _PulsingPinState extends State<_PulsingPin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            // Expanding halo
            Container(
              width: 48 * t,
              height: 48 * t,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF10B981)
                    .withValues(alpha: 0.3 * (1 - t)),
              ),
            ),
            // Center solid dot
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF10B981),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.5),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LiveTimer extends StatefulWidget {
  final DateTime startedAt;
  const _LiveTimer({required this.startedAt});
  @override
  State<_LiveTimer> createState() => _LiveTimerState();
}

class _LiveTimerState extends State<_LiveTimer> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.startedAt);
    final h = elapsed.inHours;
    final m = elapsed.inMinutes % 60;
    final s = elapsed.inSeconds % 60;
    final text = h > 0
        ? '${h.toString().padLeft(2, "0")}:${m.toString().padLeft(2, "0")}:${s.toString().padLeft(2, "0")}'
        : '${m.toString().padLeft(2, "0")}:${s.toString().padLeft(2, "0")}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 11,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
