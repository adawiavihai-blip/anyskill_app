/// AnySkill — Live Location Service
///
/// Broadcasts the provider's current GPS coordinates so the customer's
/// Active Booking Detail screen can render a live-moving marker on the
/// map (Wolt/Uber-style).
///
/// Write side (provider):
///   * Call [startBroadcasting] when the provider taps "אני בדרך 🚗" or
///     when work has started (`workStartedAt` is set).
///   * Call [stopBroadcasting] when the job is completed, cancelled, or
///     the app resigns active.
///
/// Read side (customer):
///   * Subscribe to [streamLocation] with the provider's uid from the
///     Active Booking Detail screen.
///
/// Firestore schema — `provider_live_location/{providerUid}`:
/// ```
/// {
///   providerId: string,
///   lat: number,
///   lng: number,
///   heading: number?,   // degrees 0-360
///   speed: number?,     // m/s
///   accuracy: number?,  // meters
///   updatedAt: Timestamp,
///   activeJobId: string?,
/// }
/// ```
///
/// The document is a single-doc-per-provider (keyed by uid) so the
/// customer can find it without a query. The provider owns + writes it;
/// any authenticated user can read (participants enforced at the UI
/// layer — the data is coarse live GPS, not sensitive history).
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LiveLocation {
  final double lat;
  final double lng;
  final double? heading;
  final double? speed;
  final double? accuracy;
  final DateTime updatedAt;
  final String? activeJobId;

  const LiveLocation({
    required this.lat,
    required this.lng,
    required this.updatedAt,
    this.heading,
    this.speed,
    this.accuracy,
    this.activeJobId,
  });

  factory LiveLocation.fromMap(Map<String, dynamic> m) => LiveLocation(
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        heading: (m['heading'] as num?)?.toDouble(),
        speed: (m['speed'] as num?)?.toDouble(),
        accuracy: (m['accuracy'] as num?)?.toDouble(),
        updatedAt:
            (m['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        activeJobId: m['activeJobId'] as String?,
      );

  /// Considered "fresh" if last update was within the last minute.
  bool get isFresh =>
      DateTime.now().difference(updatedAt).inSeconds < 60;
}

class LiveLocationService {
  static final _db = FirebaseFirestore.instance;

  static StreamSubscription<Position>? _sub;
  static String? _activeUid;
  static String? _activeJobId;
  static DateTime _lastWriteAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// True while the provider is broadcasting.
  static bool get isBroadcasting => _sub != null;

  static DocumentReference<Map<String, dynamic>> _docRef(String uid) =>
      _db.collection('provider_live_location').doc(uid);

  // ──────────────────────────────────────────────────────────────────────
  // WRITE — Provider broadcasts their location
  // ──────────────────────────────────────────────────────────────────────

  /// Starts broadcasting the current user's location to Firestore.
  /// Safe to call multiple times — no-op if already broadcasting.
  /// Throws [StateError] if location permission is denied.
  static Future<void> startBroadcasting({
    required String activeJobId,
  }) async {
    if (_sub != null) {
      _activeJobId = activeJobId;
      return; // already running
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('משתמש לא מחובר');
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
    if (perm == LocationPermission.whileInUse) {
      // Best-effort upgrade to "always" — keeps broadcasting when the
      // screen locks while the provider is driving. Failure is OK.
      try {
        await Geolocator.requestPermission();
      } catch (_) {/* user can grant later */}
    }

    _activeUid = uid;
    _activeJobId = activeJobId;

    // Write an immediate one-shot position so the customer sees a marker
    // without waiting for the first stream update.
    try {
      final pos = await Geolocator.getCurrentPosition();
      await _writePosition(uid, pos);
    } catch (e) {
      debugPrint('[LiveLocation] initial position failed: $e');
    }

    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen(
      (pos) => _onPosition(pos),
      onError: (e) => debugPrint('[LiveLocation] stream error: $e'),
    );

    debugPrint(
        '[LiveLocation] ✅ broadcasting started uid=$uid job=$activeJobId');
  }

  static Future<void> _onPosition(Position pos) async {
    final uid = _activeUid;
    if (uid == null) return;
    // Throttle writes — at most one per 6 seconds to keep Firestore cost
    // under control. Distance filter already pre-filters small moves.
    final now = DateTime.now();
    if (now.difference(_lastWriteAt).inSeconds < 6) return;
    _lastWriteAt = now;
    await _writePosition(uid, pos);
  }

  static Future<void> _writePosition(String uid, Position pos) async {
    try {
      await _docRef(uid).set({
        'providerId': uid,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'heading': pos.heading,
        'speed': pos.speed,
        'accuracy': pos.accuracy,
        'updatedAt': FieldValue.serverTimestamp(),
        if (_activeJobId != null) 'activeJobId': _activeJobId,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[LiveLocation] write failed: $e');
    }
  }

  /// Stops the broadcast stream and deletes the Firestore doc so the
  /// customer's map falls back to the stored `clientLat/Lng` destination.
  /// Safe to call even when not broadcasting.
  static Future<void> stopBroadcasting() async {
    await _sub?.cancel();
    _sub = null;
    final uid = _activeUid;
    _activeUid = null;
    _activeJobId = null;
    if (uid != null) {
      try {
        await _docRef(uid).delete();
      } catch (e) {
        debugPrint('[LiveLocation] delete failed: $e');
      }
    }
    debugPrint('[LiveLocation] 🛑 broadcasting stopped');
  }

  // ──────────────────────────────────────────────────────────────────────
  // READ — Customer streams provider's location
  // ──────────────────────────────────────────────────────────────────────

  /// Streams the provider's live location. Emits `null` when no doc
  /// exists (provider isn't broadcasting) or the last update is stale
  /// (> 90 seconds old).
  static Stream<LiveLocation?> streamLocation(String providerUid) {
    return _docRef(providerUid).snapshots().map((snap) {
      if (!snap.exists) return null;
      final data = snap.data();
      if (data == null) return null;
      try {
        final loc = LiveLocation.fromMap(data);
        // Hide stale — the provider may have crashed or lost signal.
        if (DateTime.now().difference(loc.updatedAt).inSeconds > 90) {
          return null;
        }
        return loc;
      } catch (e) {
        debugPrint('[LiveLocation] parse failed: $e');
        return null;
      }
    });
  }
}
