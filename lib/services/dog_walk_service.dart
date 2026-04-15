/// AnySkill — Dog Walk Service (Pet Services Module)
///
/// Live GPS tracking for dog walking jobs. Workflow:
///
///   1. Provider taps **"התחל הליכון"** in their job card.
///      → [DogWalkService.startWalk] creates a `dog_walks/{walkId}` doc
///        and starts a `Geolocator.getPositionStream` listener.
///
///   2. Every position update (default: 10 m delta) is appended to the
///      doc's `path` array as `{lat, lng, t}`.
///
///   3. Provider taps **"סיים הליכון"**.
///      → [DogWalkService.endWalk] flushes the buffer, computes total
///        distance + duration, posts a chat system message + a customer
///        notification with a Google Static Maps URL of the route.
///
/// `walkId` is deterministic (`{jobId}_{startTimestamp}`) so multiple walks
/// against the same booking are supported.
///
/// **Schema gate**: this service should ONLY be invoked when the expert's
/// sub-category schema has `walkTracking: true`. The provider order card
/// in `my_bookings_screen.dart` checks the flag before showing the buttons.
///
/// **Privacy**: only the customer + provider can read the walk doc.
/// Firestore rules: `dog_walks/{walkId}` → participant-only read/write.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/pet_stay/services/pet_update_service.dart';

class DogWalkPoint {
  final double lat;
  final double lng;
  final DateTime timestamp;

  const DogWalkPoint({
    required this.lat,
    required this.lng,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'lat': lat,
        'lng': lng,
        't': Timestamp.fromDate(timestamp),
      };

  factory DogWalkPoint.fromMap(Map<String, dynamic> m) => DogWalkPoint(
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        timestamp: (m['t'] as Timestamp).toDate(),
      );
}

class DogWalkService {
  static final _db = FirebaseFirestore.instance;

  // ── Persistent state keys (SharedPreferences) ─────────────────────────
  // These survive app close / tab refresh and let us resume an interrupted
  // walk on the next mount. See [tryResumeActiveWalk].
  static const _kPrefsActiveWalkId    = 'dog_walk.activeWalkId';
  static const _kPrefsActiveJobId     = 'dog_walk.activeJobId';
  static const _kPrefsActiveCustomerId   = 'dog_walk.activeCustomerId';
  static const _kPrefsActiveCustomerName = 'dog_walk.activeCustomerName';
  static const _kPrefsActiveProviderId   = 'dog_walk.activeProviderId';
  static const _kPrefsActiveProviderName = 'dog_walk.activeProviderName';

  /// Active stream subscription — held by the singleton so the buttons
  /// in `my_bookings_screen.dart` can call start/end without managing
  /// state themselves.
  static StreamSubscription<Position>? _activeSub;
  static String? _activeWalkId;
  static String? _activeJobId;
  static final List<DogWalkPoint> _buffer = [];
  static DateTime? _lastFlushAt;

  /// True while a walk is in progress (used by UI to swap buttons).
  static bool get isWalking => _activeSub != null;

  /// The doc id of the in-progress walk, if any.
  static String? get activeWalkId => _activeWalkId;

  /// The job id that the in-progress walk is attached to, if any.
  static String? get activeJobId => _activeJobId;

  // ──────────────────────────────────────────────────────────────────────
  // Persistent state helpers
  // ──────────────────────────────────────────────────────────────────────

  static Future<void> _saveActiveToPrefs({
    required String walkId,
    required String jobId,
    required String customerId,
    required String customerName,
    required String providerId,
    required String providerName,
  }) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kPrefsActiveWalkId, walkId);
      await p.setString(_kPrefsActiveJobId, jobId);
      await p.setString(_kPrefsActiveCustomerId, customerId);
      await p.setString(_kPrefsActiveCustomerName, customerName);
      await p.setString(_kPrefsActiveProviderId, providerId);
      await p.setString(_kPrefsActiveProviderName, providerName);
    } catch (e) {
      debugPrint('[DogWalk] prefs save failed: $e');
    }
  }

  static Future<void> _clearActiveFromPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kPrefsActiveWalkId);
      await p.remove(_kPrefsActiveJobId);
      await p.remove(_kPrefsActiveCustomerId);
      await p.remove(_kPrefsActiveCustomerName);
      await p.remove(_kPrefsActiveProviderId);
      await p.remove(_kPrefsActiveProviderName);
    } catch (e) {
      debugPrint('[DogWalk] prefs clear failed: $e');
    }
  }

  /// Describes a walk that was persisted to SharedPreferences — used by
  /// the UI to decide whether to prompt the provider with a "Resume walk?"
  /// banner or to auto-resume silently.
  static Future<PersistedWalkInfo?> readPersistedActiveWalk() async {
    try {
      final p = await SharedPreferences.getInstance();
      final walkId = p.getString(_kPrefsActiveWalkId);
      final jobId = p.getString(_kPrefsActiveJobId);
      if (walkId == null || jobId == null) return null;
      return PersistedWalkInfo(
        walkId: walkId,
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

  /// Attempts to resume a walk that was interrupted (app close / refresh).
  /// Reads the persisted walkId, verifies the Firestore doc is still in
  /// `walking` status, and re-attaches the position stream. Returns `true`
  /// on successful resume.
  ///
  /// If the doc was deleted or already marked `finished`/`cancelled`, the
  /// stale prefs entry is cleared and the method returns `false`.
  ///
  /// Should be called from the provider's bookings screen on mount.
  static Future<bool> tryResumeActiveWalk() async {
    if (_activeSub != null) return true; // already running — no-op
    final info = await readPersistedActiveWalk();
    if (info == null) return false;

    try {
      final doc = await _db.collection('dog_walks').doc(info.walkId).get();
      if (!doc.exists) {
        debugPrint('[DogWalk] resume abort — doc missing: ${info.walkId}');
        await _clearActiveFromPrefs();
        return false;
      }
      final status = doc.data()?['status'] as String? ?? '';
      if (status != 'walking') {
        debugPrint('[DogWalk] resume abort — status=$status (not walking)');
        await _clearActiveFromPrefs();
        return false;
      }

      // Re-check permissions — if the user revoked them mid-walk, bail.
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[DogWalk] resume abort — location service disabled');
        return false;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        debugPrint('[DogWalk] resume abort — no location permission');
        return false;
      }

      // Re-attach state + stream
      _activeWalkId = info.walkId;
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
        onError: (e) => debugPrint('[DogWalk] resume stream error: $e'),
      );
      debugPrint('[DogWalk] ✅ resumed walk ${info.walkId}');
      return true;
    } catch (e) {
      debugPrint('[DogWalk] resume failed: $e');
      return false;
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // START
  // ──────────────────────────────────────────────────────────────────────

  /// Begins tracking a new walk against [jobId]. Returns the deterministic
  /// `walkId`. Throws if a walk is already active or if location services
  /// are unavailable.
  static Future<String> startWalk({
    required String jobId,
    required String customerId,
    required String customerName,
    required String providerId,
    required String providerName,
  }) async {
    if (_activeSub != null) {
      throw StateError('הליכון כבר בתהליך — סיים אותו לפני שתתחיל חדש');
    }

    // Permission + location service checks
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw StateError('שירותי מיקום מושבתים בטלפון');
    }
    var perm = await Geolocator.checkPermission();
    // Step 1 — get whileInUse if not granted yet
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      throw StateError('אין הרשאה לשירותי מיקום');
    }
    // Step 2 — best-effort upgrade to "always" so the walk keeps tracking
    // when the screen locks. On iOS this triggers a SECOND prompt; on
    // Android 10+ it opens the system settings page. Failure is OK —
    // we degrade gracefully to foreground-only tracking.
    if (perm == LocationPermission.whileInUse) {
      try {
        await Geolocator.requestPermission();
      } catch (_) {/* user can grant later */}
    }

    final startedAt = DateTime.now();
    final walkId = '${jobId}_${startedAt.millisecondsSinceEpoch}';
    _activeWalkId = walkId;
    _activeJobId = jobId;
    _buffer.clear();
    _lastFlushAt = startedAt;

    // 1. Create the walk doc
    await _db.collection('dog_walks').doc(walkId).set({
      'walkId': walkId,
      'jobId': jobId,
      'customerId': customerId,
      'customerName': customerName,
      'providerId': providerId,
      'providerName': providerName,
      'status': 'walking', // walking | finished | cancelled
      'startedAt': Timestamp.fromDate(startedAt),
      'endedAt': null,
      'path': <Map<String, dynamic>>[],
      'totalDistanceMeters': 0,
      'totalDurationSeconds': 0,
    });

    // Persist to SharedPreferences so a tab refresh / app relaunch can
    // resume the walk via tryResumeActiveWalk() on next mount.
    await _saveActiveToPrefs(
      walkId: walkId,
      jobId: jobId,
      customerId: customerId,
      customerName: customerName,
      providerId: providerId,
      providerName: providerName,
    );

    // 2. Start the position stream — 10 m delta filter, high accuracy
    _activeSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // metres
      ),
    ).listen(
      _onPositionUpdate,
      onError: (e) {
        debugPrint('[DogWalk] position stream error: $e');
      },
    );

    debugPrint('[DogWalk] ✅ started walk $walkId');
    return walkId;
  }

  static void _onPositionUpdate(Position pos) {
    if (_activeWalkId == null) return;
    _buffer.add(DogWalkPoint(
      lat: pos.latitude,
      lng: pos.longitude,
      timestamp: DateTime.now(),
    ));
    // Flush every 30 seconds OR every 5 points to keep Firestore writes
    // economical without losing fidelity.
    final since = _lastFlushAt == null
        ? Duration.zero
        : DateTime.now().difference(_lastFlushAt!);
    if (_buffer.length >= 5 || since.inSeconds >= 30) {
      _flushBuffer();
    }
  }

  static Future<void> _flushBuffer() async {
    if (_activeWalkId == null || _buffer.isEmpty) return;
    final toFlush = List<DogWalkPoint>.from(_buffer);
    _buffer.clear();
    _lastFlushAt = DateTime.now();
    try {
      await _db.collection('dog_walks').doc(_activeWalkId).update({
        'path': FieldValue.arrayUnion(toFlush.map((p) => p.toMap()).toList()),
      });
    } catch (e) {
      // On failure, push back into buffer so the next flush retries.
      _buffer.insertAll(0, toFlush);
      debugPrint('[DogWalk] flush failed: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // END
  // ──────────────────────────────────────────────────────────────────────

  /// Stops the active walk, writes a final flush, computes summary stats,
  /// and posts a system chat message to the customer with a route map URL.
  /// Returns the [WalkSummary] for UI display.
  static Future<WalkSummary?> endWalk({
    required String chatRoomId,
  }) async {
    final walkId = _activeWalkId;
    if (walkId == null || _activeSub == null) {
      return null; // nothing to end
    }

    await _activeSub?.cancel();
    _activeSub = null;
    await _flushBuffer();

    // Read the full path from the doc to compute distance + duration
    final snap = await _db.collection('dog_walks').doc(walkId).get();
    if (!snap.exists) {
      _activeWalkId = null;
      return null;
    }
    final data = snap.data()!;
    final pathRaw = (data['path'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(DogWalkPoint.fromMap)
        .toList();

    final endedAt = DateTime.now();
    final startedAt = (data['startedAt'] as Timestamp).toDate();
    final durationSec = endedAt.difference(startedAt).inSeconds;
    final distanceM = _computeDistance(pathRaw);

    // Generate a Google Static Maps URL — works without API key for small
    // requests; if the user later configures one, the URL stays valid.
    final mapUrl = _staticMapUrl(pathRaw);

    // Naive fitness-style estimates (Pet Stay Tracker v13.0.0).
    // steps: distance / avg stride (0.75 m).
    // calories: weight(kg) × km × 0.8  (very rough).
    // pace: MM:SS per km, only meaningful above ~200 m.
    final dogWeightKg = await _fetchDogWeightKg(data['jobId'] as String?);
    final km = distanceM / 1000.0;
    final steps = (distanceM / 0.75).round();
    final calories = (dogWeightKg * km * 0.8).round();
    final pace = _formatPacePerKm(durationSec, km);

    // Update the doc with final stats
    await _db.collection('dog_walks').doc(walkId).update({
      'status': 'finished',
      'endedAt': Timestamp.fromDate(endedAt),
      'totalDistanceMeters': distanceM.round(),
      'totalDurationSeconds': durationSec,
      'mapUrl': mapUrl,
      'steps': steps,
      'caloriesBurned': calories,
      'pacePerKm': pace,
    });

    // Post a system message to the chat room
    try {
      final auth = FirebaseAuth.instance.currentUser;
      await _db
          .collection('chats')
          .doc(chatRoomId)
          .collection('messages')
          .add({
        'senderId': auth?.uid ?? '',
        'senderName': data['providerName'] ?? '',
        'message': '🐕 ההליכון הסתיים!\n'
            'מרחק: ${(distanceM / 1000).toStringAsFixed(2)} ק"מ\n'
            'משך: ${_formatDuration(durationSec)}',
        'type': 'walk_summary',
        'walkId': walkId,
        if (mapUrl.isNotEmpty) 'mapUrl': mapUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    } catch (e) {
      debugPrint('[DogWalk] chat post failed: $e');
    }

    // Notify the customer
    try {
      await _db.collection('notifications').add({
        'userId': data['customerId'],
        'title': '🐕 ההליכון הסתיים',
        'body': 'הצפה לסיכום עם מפת המסלול',
        'type': 'walk_summary',
        'walkId': walkId,
        'jobId': data['jobId'],
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[DogWalk] notification failed: $e');
    }

    // Mirror walk-completion to the feed (pet_update) so the owner's
    // timeline renders the summary alongside pee/poop markers + photos.
    final customerId = data['customerId'] as String?;
    final providerId = data['providerId'] as String?;
    final jobIdStr = data['jobId'] as String?;
    if (customerId != null && providerId != null && jobIdStr != null) {
      try {
        await PetUpdateService.instance.writeWalkCompleted(
          jobId: jobIdStr,
          customerId: customerId,
          expertId: providerId,
          walkId: walkId,
          distanceKm: km,
          durationSeconds: durationSec,
          steps: steps,
          pacePerKm: pace,
        );
      } catch (e) {
        debugPrint('[DogWalk] walk_completed feed write failed: $e');
      }
    }

    final summary = WalkSummary(
      walkId: walkId,
      distanceMeters: distanceM,
      durationSeconds: durationSec,
      mapUrl: mapUrl,
      pathPoints: pathRaw.length,
    );
    _activeWalkId = null;
    _activeJobId = null;
    await _clearActiveFromPrefs();
    debugPrint('[DogWalk] ✅ ended walk $walkId — ${summary.distanceMeters.round()}m');
    return summary;
  }

  // ──────────────────────────────────────────────────────────────────────
  // MARKERS (pee / poop) — Pet Stay Tracker v13.0.0
  // ──────────────────────────────────────────────────────────────────────

  /// Adds a pee or poop marker to the active walk. Captures current GPS,
  /// appends to `dog_walks/{walkId}.markers`, posts a chat system message
  /// and a notification to the customer, and writes a `pet_update` to the
  /// feed so the owner's timeline shows it alongside other stay events.
  ///
  /// No-op if there's no active walk.
  static Future<bool> addMarker({
    required String type, // 'pee' | 'poop'
    required String chatRoomId,
  }) async {
    assert(type == 'pee' || type == 'poop');
    final walkId = _activeWalkId;
    if (walkId == null) return false;

    // Best-effort GPS — if it fails, fall back to last known path point.
    double? lat;
    double? lng;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 6));
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {
      if (_buffer.isNotEmpty) {
        lat = _buffer.last.lat;
        lng = _buffer.last.lng;
      }
    }

    final now = DateTime.now();
    final marker = {
      'type': type,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      't': Timestamp.fromDate(now),
    };

    // 1. Append to the walk doc's markers array.
    try {
      await _db.collection('dog_walks').doc(walkId).update({
        'markers': FieldValue.arrayUnion([marker]),
      });
    } catch (e) {
      debugPrint('[DogWalk] marker write failed: $e');
      return false;
    }

    // Read customerId/jobId from the walk doc for the downstream writes.
    String? customerId;
    String? providerId;
    String? jobId;
    String? providerName;
    try {
      final snap = await _db.collection('dog_walks').doc(walkId).get();
      final data = snap.data() ?? const {};
      customerId = data['customerId'] as String?;
      providerId = data['providerId'] as String?;
      jobId = data['jobId'] as String?;
      providerName = data['providerName'] as String?;
    } catch (_) {}

    // 2. Chat system message.
    if (chatRoomId.isNotEmpty) {
      try {
        await _db
            .collection('chats')
            .doc(chatRoomId)
            .collection('messages')
            .add({
          'senderId': FirebaseAuth.instance.currentUser?.uid ?? '',
          'senderName': providerName ?? '',
          'message': type == 'pee' ? '💧 הכלב עשה פיפי' : '💩 הכלב עשה קקי',
          'type': 'pet_marker',
          'markerType': type,
          'walkId': walkId,
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
        });
      } catch (e) {
        debugPrint('[DogWalk] marker chat post failed: $e');
      }
    }

    // 3. Notification to customer.
    if (customerId != null && customerId.isNotEmpty) {
      try {
        await _db.collection('notifications').add({
          'userId': customerId,
          'title': type == 'pee' ? '💧 פיפי סומן' : '💩 קקי סומן',
          'body': 'סומן במהלך ההליכון',
          'type': 'pet_marker',
          'markerType': type,
          'walkId': walkId,
          if (jobId != null) 'jobId': jobId,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('[DogWalk] marker notification failed: $e');
      }
    }

    // 4. Mirror to feed (pet_update) so the owner's timeline renders it.
    if (customerId != null && providerId != null && jobId != null) {
      try {
        await PetUpdateService.instance.writeMarker(
          jobId: jobId,
          customerId: customerId,
          expertId: providerId,
          type: type,
          walkId: walkId,
          lat: lat,
          lng: lng,
        );
      } catch (e) {
        debugPrint('[DogWalk] marker feed-write failed: $e');
      }
    }

    debugPrint('[DogWalk] ✅ marker $type on walk $walkId');
    return true;
  }

  /// Cancels an in-progress walk without producing a summary or notification.
  /// Used for accidental starts or app restarts mid-walk.
  static Future<void> cancelWalk() async {
    final walkId = _activeWalkId;
    if (walkId == null) return;
    await _activeSub?.cancel();
    _activeSub = null;
    _buffer.clear();
    _activeWalkId = null;
    _activeJobId = null;
    await _clearActiveFromPrefs();
    try {
      await _db.collection('dog_walks').doc(walkId).update({
        'status': 'cancelled',
        'endedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[DogWalk] cancel update failed: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // STREAM (customer-side live view)
  // ──────────────────────────────────────────────────────────────────────

  /// Stream a walk doc by id — used by the customer's order screen to
  /// show live progress. Returns null map when not found.
  static Stream<Map<String, dynamic>?> watchWalk(String walkId) {
    return _db
        .collection('dog_walks')
        .doc(walkId)
        .snapshots()
        .map((s) => s.exists ? s.data() : null);
  }

  /// All walks for a given job — sorted newest first.
  static Stream<List<Map<String, dynamic>>> walksForJob(String jobId) {
    return _db
        .collection('dog_walks')
        .where('jobId', isEqualTo: jobId)
        .orderBy('startedAt', descending: true)
        .limit(50)
        .snapshots()
        .map((q) => q.docs.map((d) => d.data()).toList());
  }

  // ──────────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────────

  /// Haversine distance over the path (metres).
  static double _computeDistance(List<DogWalkPoint> path) {
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

  /// Builds a free OpenStreetMap static-map URL with the path drawn as a
  /// polyline. **No API key required** — the staticmap.openstreetmap.de
  /// service is community-hosted and free for reasonable usage.
  ///
  /// Caps the path at 60 points so the URL stays well under the 8 KB limit.
  /// First point is marked green ('lightblue1'), last point is red ('ol-marker').
  static String _staticMapUrl(List<DogWalkPoint> path) {
    if (path.isEmpty) return '';
    final stride = (path.length / 60).ceil().clamp(1, 9999);
    final sample = <DogWalkPoint>[];
    for (int i = 0; i < path.length; i += stride) {
      sample.add(path[i]);
    }
    if (sample.last != path.last) sample.add(path.last);

    // Center on the path's centroid for nicer framing
    double sumLat = 0, sumLng = 0;
    for (final p in sample) {
      sumLat += p.lat;
      sumLng += p.lng;
    }
    final centerLat = sumLat / sample.length;
    final centerLng = sumLng / sample.length;

    // OSM static map polyline format:
    //   path=color:0x6366F1ff|weight:5|lat1,lng1|lat2,lng2|...
    final encoded = sample
        .map((p) => '${p.lat.toStringAsFixed(5)},${p.lng.toStringAsFixed(5)}')
        .join('|');
    return 'https://staticmap.openstreetmap.de/staticmap.php'
        '?center=${centerLat.toStringAsFixed(5)},${centerLng.toStringAsFixed(5)}'
        '&zoom=15'
        '&size=600x400'
        '&maptype=mapnik'
        '&path=color:0x6366F1ff|weight:5|$encoded'
        '&markers=${sample.first.lat},${sample.first.lng},lightblue1'
        '&markers=${sample.last.lat},${sample.last.lng},ol-marker';
  }

  static String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '$h ש׳ $m ד׳';
    return '$m ד׳';
  }

  /// Returns pace as "MM:SS" per km. For very short walks (< 0.2 km) the
  /// estimate is noisy, so we return '—' instead of a misleading number.
  static String _formatPacePerKm(int durationSec, double km) {
    if (km < 0.2 || durationSec <= 0) return '—';
    final secPerKm = (durationSec / km).round();
    final m = secPerKm ~/ 60;
    final s = secPerKm % 60;
    return '$m:${s.toString().padLeft(2, "0")}';
  }

  /// Reads the dog's weight from `jobs/{jobId}/petStay/data.dogSnapshot`
  /// for naive calorie estimation. Falls back to 15 kg when the stay
  /// doc isn't present (legacy walks created before Step 5).
  static Future<double> _fetchDogWeightKg(String? jobId) async {
    const fallback = 15.0;
    if (jobId == null || jobId.isEmpty) return fallback;
    try {
      final snap = await _db
          .collection('jobs')
          .doc(jobId)
          .collection('petStay')
          .doc('data')
          .get();
      if (!snap.exists) return fallback;
      final snapshot = snap.data()?['dogSnapshot'] as Map?;
      final w = (snapshot?['weightKg'] as num?)?.toDouble();
      return (w != null && w > 0) ? w : fallback;
    } catch (_) {
      return fallback;
    }
  }
}

class WalkSummary {
  final String walkId;
  final double distanceMeters;
  final int durationSeconds;
  final String mapUrl;
  final int pathPoints;

  const WalkSummary({
    required this.walkId,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.mapUrl,
    required this.pathPoints,
  });
}

/// Snapshot of an interrupted walk that was persisted to SharedPreferences
/// by [DogWalkService._saveActiveToPrefs]. Used by the UI (provider order
/// screen) to decide whether to prompt for resume.
class PersistedWalkInfo {
  final String walkId;
  final String jobId;
  final String customerId;
  final String customerName;
  final String providerId;
  final String providerName;

  const PersistedWalkInfo({
    required this.walkId,
    required this.jobId,
    required this.customerId,
    required this.customerName,
    required this.providerId,
    required this.providerName,
  });
}
