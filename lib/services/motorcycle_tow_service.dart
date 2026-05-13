/// AnySkill — Motorcycle Towing Service.
///
/// Live GPS tracking for motorcycle-tow jobs. Modeled on
/// [DogWalkService] (CLAUDE.md §3d Pet Stay Tracker).
///
/// Workflow:
///   1. Provider taps **"קיבלתי את הקריאה"** in their order card after the
///      job's escrow is paid.
///      → [MotorcycleTowService.startTow] creates a `motorcycle_tows/{towId}`
///        doc + opens `Geolocator.getPositionStream`.
///
///   2. Each position update (10 m delta) is appended to `path` and the
///      doc's `providerLocation.{lat, lng, t}` is overwritten so the
///      customer's tracking screen can render a live pin.
///
///   3. Provider advances through the stages (en_route_pickup →
///      arrived_pickup → loaded_in_transit → arrived_destination) via
///      [MotorcycleTowService.advanceStage].
///
///   4. On the final stage, [endTow] flushes the buffer + computes
///      total distance + duration + posts a chat system message + a
///      customer notification.
///
/// `towId` format: `{jobId}_{startTimestamp}` — multi-tow per booking is
/// supported (rare, but useful for re-routes).
///
/// **Privacy**: only the customer + provider can read the tow doc.
/// Firestore rules: `motorcycle_tows/{towId}` → participant-only read/write.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/motorcycle_tracking_stages.dart';

class MotorcycleTowPoint {
  final double lat;
  final double lng;
  final DateTime timestamp;

  const MotorcycleTowPoint({
    required this.lat,
    required this.lng,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'lat': lat,
        'lng': lng,
        't': Timestamp.fromDate(timestamp),
      };

  factory MotorcycleTowPoint.fromMap(Map<String, dynamic> m) =>
      MotorcycleTowPoint(
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        timestamp: (m['t'] as Timestamp).toDate(),
      );
}

class MotorcycleTowSummary {
  final String towId;
  final double distanceMeters;
  final int durationSeconds;
  final int pathPoints;

  const MotorcycleTowSummary({
    required this.towId,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.pathPoints,
  });
}

class PersistedMotorcycleTow {
  final String towId;
  final String jobId;
  final String customerId;
  final String customerName;
  final String providerId;
  final String providerName;

  const PersistedMotorcycleTow({
    required this.towId,
    required this.jobId,
    required this.customerId,
    required this.customerName,
    required this.providerId,
    required this.providerName,
  });
}

class MotorcycleTowService {
  static final _db = FirebaseFirestore.instance;
  static const _collection = 'motorcycle_tows';

  // ── Persistent state keys (SharedPreferences) ─────────────────────────
  static const _kPrefsActiveTowId = 'motorcycle_tow.activeTowId';
  static const _kPrefsActiveJobId = 'motorcycle_tow.activeJobId';
  static const _kPrefsActiveCustomerId = 'motorcycle_tow.activeCustomerId';
  static const _kPrefsActiveCustomerName = 'motorcycle_tow.activeCustomerName';
  static const _kPrefsActiveProviderId = 'motorcycle_tow.activeProviderId';
  static const _kPrefsActiveProviderName = 'motorcycle_tow.activeProviderName';

  static StreamSubscription<Position>? _activeSub;
  static String? _activeTowId;
  static String? _activeJobId;
  static final List<MotorcycleTowPoint> _buffer = [];
  static DateTime? _lastFlushAt;

  static bool get isTowing => _activeSub != null;
  static String? get activeTowId => _activeTowId;
  static String? get activeJobId => _activeJobId;

  // ──────────────────────────────────────────────────────────────────────
  // Persistent state helpers
  // ──────────────────────────────────────────────────────────────────────

  static Future<void> _saveActiveToPrefs({
    required String towId,
    required String jobId,
    required String customerId,
    required String customerName,
    required String providerId,
    required String providerName,
  }) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kPrefsActiveTowId, towId);
      await p.setString(_kPrefsActiveJobId, jobId);
      await p.setString(_kPrefsActiveCustomerId, customerId);
      await p.setString(_kPrefsActiveCustomerName, customerName);
      await p.setString(_kPrefsActiveProviderId, providerId);
      await p.setString(_kPrefsActiveProviderName, providerName);
    } catch (e) {
      debugPrint('[MotorcycleTow] prefs save failed: $e');
    }
  }

  static Future<void> _clearActiveFromPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kPrefsActiveTowId);
      await p.remove(_kPrefsActiveJobId);
      await p.remove(_kPrefsActiveCustomerId);
      await p.remove(_kPrefsActiveCustomerName);
      await p.remove(_kPrefsActiveProviderId);
      await p.remove(_kPrefsActiveProviderName);
    } catch (_) {}
  }

  static Future<PersistedMotorcycleTow?> readPersistedActiveTow() async {
    try {
      final p = await SharedPreferences.getInstance();
      final towId = p.getString(_kPrefsActiveTowId);
      final jobId = p.getString(_kPrefsActiveJobId);
      if (towId == null || jobId == null) return null;
      return PersistedMotorcycleTow(
        towId: towId,
        jobId: jobId,
        customerId: p.getString(_kPrefsActiveCustomerId) ?? '',
        customerName: p.getString(_kPrefsActiveCustomerName) ?? '',
        providerId: p.getString(_kPrefsActiveProviderId) ?? '',
        providerName: p.getString(_kPrefsActiveProviderName) ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// Resume an interrupted tow. Returns true on successful resume.
  static Future<bool> tryResumeActiveTow() async {
    if (_activeSub != null) return true;
    final info = await readPersistedActiveTow();
    if (info == null) return false;

    try {
      final doc = await _db.collection(_collection).doc(info.towId).get();
      if (!doc.exists) {
        await _clearActiveFromPrefs();
        return false;
      }
      final status = doc.data()?['status'] as String? ?? '';
      // Active states — anything between 'driver_assigned' and the final
      // stage means the tow is still running.
      if (status == 'arrived_destination' ||
          status == 'cancelled' ||
          status.isEmpty) {
        await _clearActiveFromPrefs();
        return false;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return false;
      }

      _activeTowId = info.towId;
      _activeJobId = info.jobId;
      _buffer.clear();
      _lastFlushAt = DateTime.now();
      _activeSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen(
        _onPositionUpdate,
        onError: (e) => debugPrint('[MotorcycleTow] resume stream error: $e'),
      );
      debugPrint('[MotorcycleTow] ✅ resumed tow ${info.towId}');
      return true;
    } catch (e) {
      debugPrint('[MotorcycleTow] resume failed: $e');
      return false;
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // START
  // ──────────────────────────────────────────────────────────────────────

  /// Begins tracking a new tow. Returns the deterministic `towId`. Throws
  /// if a tow is already active or if location services are unavailable.
  static Future<String> startTow({
    required String jobId,
    required String customerId,
    required String customerName,
    required String providerId,
    required String providerName,
    Map<String, dynamic>? bookingSnapshot,
    // Mirrors `MotorcycleTowSmartFeatures.beforeAfterPhotos` (§55).
    // Copied onto the tow doc at start time so the tracking screen can
    // gate the photo-prompt UI on a single read instead of re-fetching
    // the provider's profile every render. Same pattern as the Pet Stay
    // CSM's `flagWalkTracking` / `flagDailyProof` (§3d).
    bool beforeAfterPhotosEnabled = false,
  }) async {
    if (_activeSub != null) {
      throw StateError('גרירה כבר פעילה — סיים אותה לפני שתתחיל חדשה');
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw StateError('שירותי מיקום מושבתים בטלפון');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      throw StateError('אין הרשאה לשירותי מיקום');
    }
    // Best-effort upgrade to "always".
    if (perm == LocationPermission.whileInUse) {
      try {
        await Geolocator.requestPermission();
      } catch (_) {}
    }

    final startedAt = DateTime.now();
    final towId = '${jobId}_${startedAt.millisecondsSinceEpoch}';
    _activeTowId = towId;
    _activeJobId = jobId;
    _buffer.clear();
    _lastFlushAt = startedAt;

    await _db.collection(_collection).doc(towId).set({
      'towId': towId,
      'jobId': jobId,
      'customerId': customerId,
      'customerName': customerName,
      'providerId': providerId,
      'providerName': providerName,
      'status': 'driver_assigned',
      'startedAt': Timestamp.fromDate(startedAt),
      'endedAt': null,
      'path': <Map<String, dynamic>>[],
      'providerLocation': null,
      'totalDistanceMeters': 0,
      'totalDurationSeconds': 0,
      'flagBeforeAfterPhotos': beforeAfterPhotosEnabled,
      'beforePhotos': <Map<String, dynamic>>[],
      'afterPhotos': <Map<String, dynamic>>[],
      if (bookingSnapshot != null) 'bookingSnapshot': bookingSnapshot,
    });

    await _saveActiveToPrefs(
      towId: towId,
      jobId: jobId,
      customerId: customerId,
      customerName: customerName,
      providerId: providerId,
      providerName: providerName,
    );

    _activeSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(
      _onPositionUpdate,
      onError: (e) {
        debugPrint('[MotorcycleTow] position stream error: $e');
      },
    );

    debugPrint('[MotorcycleTow] ✅ started tow $towId');
    return towId;
  }

  static void _onPositionUpdate(Position pos) {
    if (_activeTowId == null) return;
    final now = DateTime.now();
    _buffer.add(MotorcycleTowPoint(
      lat: pos.latitude,
      lng: pos.longitude,
      timestamp: now,
    ));
    // Always update providerLocation immediately so the customer's pin
    // moves in real time. The path array flushes in batches.
    _db.collection(_collection).doc(_activeTowId).update({
      'providerLocation': {
        'lat': pos.latitude,
        'lng': pos.longitude,
        't': Timestamp.fromDate(now),
        'speedKph':
            (pos.speed * 3.6).clamp(0, 250), // m/s → km/h
        'heading': pos.heading,
      },
    }).catchError((e) {
      debugPrint('[MotorcycleTow] providerLocation write failed: $e');
    });
    final since = _lastFlushAt == null
        ? Duration.zero
        : now.difference(_lastFlushAt!);
    if (_buffer.length >= 5 || since.inSeconds >= 30) {
      _flushBuffer();
    }
  }

  static Future<void> _flushBuffer() async {
    if (_activeTowId == null || _buffer.isEmpty) return;
    final toFlush = List<MotorcycleTowPoint>.from(_buffer);
    _buffer.clear();
    _lastFlushAt = DateTime.now();
    try {
      await _db.collection(_collection).doc(_activeTowId).update({
        'path': FieldValue.arrayUnion(toFlush.map((p) => p.toMap()).toList()),
      });
    } catch (e) {
      _buffer.insertAll(0, toFlush);
      debugPrint('[MotorcycleTow] flush failed: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // STAGE TRANSITIONS
  // ──────────────────────────────────────────────────────────────────────

  /// Advance the active tow to a new stage. The provider's order card
  /// drives this — the customer's tracking screen reacts via the snapshot
  /// stream. Stage ids must come from [kMotorcycleTrackingStages].
  static Future<void> advanceStage({
    required String stageId,
    String? chatRoomId,
  }) async {
    final towId = _activeTowId;
    if (towId == null) {
      throw StateError('אין גרירה פעילה לעדכון');
    }
    final idx = motorcycleStageIndex(stageId);
    if (idx < 0) {
      throw ArgumentError('שלב לא חוקי: $stageId');
    }

    await _db.collection(_collection).doc(towId).update({
      'status': stageId,
      'lastStageChangeAt': FieldValue.serverTimestamp(),
      'stageHistory': FieldValue.arrayUnion([
        {'stage': stageId, 'at': Timestamp.fromDate(DateTime.now())},
      ]),
    });

    // Post a chat update so the customer sees stage changes inline.
    if (chatRoomId != null && chatRoomId.isNotEmpty) {
      try {
        final stage = findMotorcycleStage(stageId);
        await _db
            .collection('chats')
            .doc(chatRoomId)
            .collection('messages')
            .add({
          'senderId': FirebaseAuth.instance.currentUser?.uid ?? '',
          'message': stage != null
              ? '🔧 ${stage.name}'
              : 'עדכון סטטוס',
          'type': 'tow_stage',
          'stageId': stageId,
          'towId': towId,
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
        });
      } catch (e) {
        debugPrint('[MotorcycleTow] stage chat post failed: $e');
      }
    }

    debugPrint('[MotorcycleTow] ✅ stage → $stageId on $towId');
  }

  // ──────────────────────────────────────────────────────────────────────
  // BEFORE / AFTER PHOTOS
  // ──────────────────────────────────────────────────────────────────────

  /// Append a photo URL to the `beforePhotos` or `afterPhotos` array on
  /// the active tow doc. Called by the provider after uploading to Storage.
  /// [phase] must be 'before' or 'after'.
  static Future<void> addPhoto({
    required String url,
    required String phase,
  }) async {
    assert(phase == 'before' || phase == 'after');
    final towId = _activeTowId;
    if (towId == null) return;
    final field = phase == 'before' ? 'beforePhotos' : 'afterPhotos';
    try {
      await _db.collection(_collection).doc(towId).update({
        field: FieldValue.arrayUnion([
          {
            'url': url,
            't': Timestamp.fromDate(DateTime.now()),
          }
        ]),
      });
    } catch (e) {
      debugPrint('[MotorcycleTow] photo write failed: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // END
  // ──────────────────────────────────────────────────────────────────────

  /// Marks the tow as completed (stage 'arrived_destination'), flushes the
  /// buffer, computes summary stats, and posts a customer notification.
  /// Returns the [MotorcycleTowSummary] for UI display.
  static Future<MotorcycleTowSummary?> endTow({
    required String chatRoomId,
  }) async {
    final towId = _activeTowId;
    if (towId == null || _activeSub == null) return null;

    await _activeSub?.cancel();
    _activeSub = null;
    await _flushBuffer();

    final snap = await _db.collection(_collection).doc(towId).get();
    if (!snap.exists) {
      _activeTowId = null;
      _activeJobId = null;
      await _clearActiveFromPrefs();
      return null;
    }
    final data = snap.data()!;
    final pathRaw = (data['path'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(MotorcycleTowPoint.fromMap)
        .toList();

    final endedAt = DateTime.now();
    final startedAt = (data['startedAt'] as Timestamp).toDate();
    final durationSec = endedAt.difference(startedAt).inSeconds;
    final distanceM = _computeDistance(pathRaw);

    await _db.collection(_collection).doc(towId).update({
      'status': 'arrived_destination',
      'endedAt': Timestamp.fromDate(endedAt),
      'totalDistanceMeters': distanceM.round(),
      'totalDurationSeconds': durationSec,
    });

    if (chatRoomId.isNotEmpty) {
      try {
        await _db
            .collection('chats')
            .doc(chatRoomId)
            .collection('messages')
            .add({
          'senderId': FirebaseAuth.instance.currentUser?.uid ?? '',
          'message': '✅ הגרירה הסתיימה.\n'
              'מרחק: ${(distanceM / 1000).toStringAsFixed(2)} ק"מ\n'
              'משך: ${_formatDuration(durationSec)}',
          'type': 'tow_completed',
          'towId': towId,
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
        });
      } catch (e) {
        debugPrint('[MotorcycleTow] end chat post failed: $e');
      }
    }

    try {
      await _db.collection('notifications').add({
        'userId': data['customerId'],
        'title': '✅ הגרירה הסתיימה',
        'body': 'האופנוע הגיע ליעד — צפה בסיכום',
        'type': 'tow_completed',
        'towId': towId,
        'jobId': data['jobId'],
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[MotorcycleTow] notification failed: $e');
    }

    final summary = MotorcycleTowSummary(
      towId: towId,
      distanceMeters: distanceM,
      durationSeconds: durationSec,
      pathPoints: pathRaw.length,
    );
    _activeTowId = null;
    _activeJobId = null;
    await _clearActiveFromPrefs();
    debugPrint('[MotorcycleTow] ✅ ended tow $towId — ${summary.distanceMeters.round()}m');
    return summary;
  }

  /// Cancel an in-progress tow. Used when the customer cancels before the
  /// provider arrives, or when the provider has to abort.
  static Future<void> cancelTow({required String reason}) async {
    final towId = _activeTowId;
    if (towId == null) return;
    await _activeSub?.cancel();
    _activeSub = null;
    _buffer.clear();
    _activeTowId = null;
    _activeJobId = null;
    await _clearActiveFromPrefs();
    try {
      await _db.collection(_collection).doc(towId).update({
        'status': 'cancelled',
        'cancellationReason': reason,
        'endedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[MotorcycleTow] cancel update failed: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // CUSTOMER-SIDE STREAMS
  // ──────────────────────────────────────────────────────────────────────

  /// Stream a tow doc by id — used by the tracking screen.
  static Stream<Map<String, dynamic>?> watchTow(String towId) {
    return _db
        .collection(_collection)
        .doc(towId)
        .snapshots()
        .map((s) => s.exists ? s.data() : null);
  }

  /// All tows for a given job — sorted newest first. Used to render
  /// the customer's full history when there are multiple tows on one job.
  static Stream<List<Map<String, dynamic>>> towsForJob(String jobId) {
    return _db
        .collection(_collection)
        .where('jobId', isEqualTo: jobId)
        .orderBy('startedAt', descending: true)
        .limit(20)
        .snapshots()
        .map((q) => q.docs.map((d) => d.data()).toList());
  }

  /// Most-recent active tow for a job (status NOT in [arrived_destination,
  /// cancelled]). Returns null when none. Used by the tracking screen to
  /// auto-resolve the active tow id from the parent jobId.
  static Future<String?> findActiveTowIdForJob(String jobId) async {
    try {
      final q = await _db
          .collection(_collection)
          .where('jobId', isEqualTo: jobId)
          .orderBy('startedAt', descending: true)
          .limit(1)
          .get();
      if (q.docs.isEmpty) return null;
      final data = q.docs.first.data();
      final status = data['status'] as String? ?? '';
      if (status == 'arrived_destination' || status == 'cancelled') {
        return null;
      }
      return q.docs.first.id;
    } catch (e) {
      debugPrint('[MotorcycleTow] findActiveTowIdForJob failed: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────────

  static double _computeDistance(List<MotorcycleTowPoint> path) {
    if (path.length < 2) return 0;
    double total = 0;
    for (int i = 1; i < path.length; i++) {
      total += Geolocator.distanceBetween(
        path[i - 1].lat,
        path[i - 1].lng,
        path[i].lat,
        path[i].lng,
      );
    }
    return total;
  }

  static String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '$h ש׳ $m ד׳';
    return '$m ד׳';
  }
}
