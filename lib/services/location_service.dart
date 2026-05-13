import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'permission_service.dart';
// Conditional import: stub on native, real JS-interop impl on web.
import '_web_geo_stub.dart' if (dart.library.js_interop) '_web_geo_web.dart'
    as web_geo;

class LocationService {
  LocationService._();

  static Position? _cached;

  /// In-memory cache — available instantly with no I/O.
  static Position? get cached => _cached;

  // ── Silent init (called once in HomeScreen.initState) ──────────────────────
  /// If permission is already granted, fetches position and stores it in
  /// users/{uid}.  Shows NO dialog — purely silent.
  static Future<void> init(String uid) async {
    if (uid.isEmpty) return;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.whileInUse &&
          perm != LocationPermission.always) { return; }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      _cached = pos;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'latitude': pos.latitude, 'longitude': pos.longitude});
    } catch (_) {
      // Enhancement — never block the app
    }
  }

  // ── Permission-aware request (OS-first, stored answer second) ─────────────
  /// Strategy: the OS/browser is the source of truth. A stored "denied" from
  /// our in-app dialog should only prevent us from re-prompting — it must
  /// never block us when the user has since granted at the browser level.
  /// On web, when geolocator silently returns null, we fall through to a
  /// direct JS-interop call to `navigator.geolocation.getCurrentPosition`.
  ///
  /// All logging uses raw `print` (not `debugPrint`) because debugPrint is
  /// stripped by dart2js in release web builds, which would hide exactly
  /// the diagnostics we need when the field reports a bug.
  static Future<Position?> requestAndGet(BuildContext context) async {
    // ignore: avoid_print
    print('[LocationService] requestAndGet: ENTRY (kIsWeb=$kIsWeb cached=${_cached != null})');
    if (_cached != null) return _cached;

    // ── 1. OS is source of truth — check it first ──────────────────────────
    LocationPermission osPerm;
    try {
      osPerm = await Geolocator.checkPermission();
      // ignore: avoid_print
      print('[LocationService] OS checkPermission = $osPerm');
    } catch (e, st) {
      // ignore: avoid_print
      print('[LocationService] checkPermission THREW: $e\n$st');
      osPerm = LocationPermission.denied;
    }

    if (osPerm == LocationPermission.whileInUse ||
        osPerm == LocationPermission.always) {
      // Browser/OS says YES. Heal stored state if it was stale and fetch.
      await PermissionService.saveLocationStatus(PermissionService.granted);
      final pos = await _fetchPosition();
      // ignore: avoid_print
      print('[LocationService] OS granted → _fetchPosition = '
          '${pos == null ? "null" : "(${pos.latitude}, ${pos.longitude})"}');
      if (pos != null) return pos;

      // Geolocator returned null even though OS said yes → web bug. Fall
      // through to direct JS interop.
      if (kIsWeb) {
        // ignore: avoid_print
        print('[LocationService] Geolocator returned null with OS=granted → trying JS interop fallback');
        final webPos = await web_geo.webGetCurrentPositionDirect();
        if (webPos != null) {
          _cached = webPos;
          // ignore: avoid_print
          print('[LocationService] JS interop fallback succeeded: (${webPos.latitude}, ${webPos.longitude})');
          return webPos;
        }
        // ignore: avoid_print
        print('[LocationService] JS interop fallback also returned null');
      }
      return null;
    }

    // ── 2. OS has NOT granted — consult stored memory ──────────────────────
    final stored = await PermissionService.getLocationStatus();
    // ignore: avoid_print
    print('[LocationService] OS=$osPerm stored=$stored');

    if (stored == PermissionService.denied) {
      // User explicitly said no to our dialog — respect it, never re-prompt.
      // BUT: on web we still try the direct JS path, because the browser
      // permission UI is what the user controls — if they granted it there
      // we should honor that even if our Dart-side checkPermission lies.
      if (kIsWeb) {
        // ignore: avoid_print
        print('[LocationService] stored=denied + web → trying JS interop as final attempt');
        final webPos = await web_geo.webGetCurrentPositionDirect();
        if (webPos != null) {
          _cached = webPos;
          await PermissionService.saveLocationStatus(PermissionService.granted);
          // ignore: avoid_print
          print('[LocationService] JS interop recovered: (${webPos.latitude}, ${webPos.longitude}) — healing stored to granted');
          return webPos;
        }
      }
      // ignore: avoid_print
      print('[LocationService] stored=denied AND OS=$osPerm AND JS fallback failed → returning null');
      return null;
    }

    if (osPerm == LocationPermission.deniedForever) {
      await PermissionService.saveLocationStatus(PermissionService.denied);
      // ignore: avoid_print
      print('[LocationService] deniedForever → returning null');
      return null;
    }

    // ── 3. Never asked yet — show our branded in-app dialog ────────────────
    if (!context.mounted) return null;
    final proceed = await _showPermissionDialog(context);

    if (!proceed) {
      await PermissionService.saveLocationStatus(PermissionService.denied);
      return null;
    }

    // ── 4. User agreed — now ask the OS ────────────────────────────────────
    final granted = await Geolocator.requestPermission();
    // ignore: avoid_print
    print('[LocationService] requestPermission returned = $granted');

    if (granted == LocationPermission.whileInUse ||
        granted == LocationPermission.always) {
      await PermissionService.saveLocationStatus(PermissionService.granted);
      final pos = await _fetchPosition();
      if (pos != null) return pos;
      // Same fallback — geolocator may still return null on web.
      if (kIsWeb) {
        final webPos = await web_geo.webGetCurrentPositionDirect();
        if (webPos != null) {
          _cached = webPos;
          return webPos;
        }
      }
      return null;
    }

    await PermissionService.saveLocationStatus(PermissionService.denied);
    // ignore: avoid_print
    print('[LocationService] OS denied (deniedForever=${granted == LocationPermission.deniedForever}) → null');
    return null;
  }

  /// Gets position only if permission is already granted — no dialog.
  /// On web, falls through to direct JS interop when geolocator silently
  /// returns null even with permission granted.
  static Future<Position?> getIfGranted() async {
    // ignore: avoid_print
    print('[LocationService] getIfGranted: ENTRY (kIsWeb=$kIsWeb cached=${_cached != null})');
    if (_cached != null) return _cached;
    LocationPermission perm;
    try {
      perm = await Geolocator.checkPermission();
      // ignore: avoid_print
      print('[LocationService] getIfGranted: OS = $perm');
    } catch (e) {
      // ignore: avoid_print
      print('[LocationService] getIfGranted: checkPermission threw: $e');
      perm = LocationPermission.denied;
    }
    if (perm != LocationPermission.whileInUse &&
        perm != LocationPermission.always) {
      // On web, the Permissions API in some browsers reports denied/prompt
      // even when the user has actually allowed access. Try JS interop
      // anyway — if the browser blocks, it'll surface PERMISSION_DENIED.
      if (kIsWeb) {
        // ignore: avoid_print
        print('[LocationService] getIfGranted: OS=$perm on web → trying JS interop');
        final webPos = await web_geo.webGetCurrentPositionDirect();
        if (webPos != null) {
          _cached = webPos;
          return webPos;
        }
      }
      return null;
    }
    final pos = await _fetchPosition();
    if (pos != null) return pos;
    if (kIsWeb) {
      // ignore: avoid_print
      print('[LocationService] getIfGranted: geolocator returned null with OS=granted → JS interop');
      final webPos = await web_geo.webGetCurrentPositionDirect();
      if (webPos != null) _cached = webPos;
      return webPos;
    }
    return null;
  }

  // ── v9.9.0: Provider location broadcasting ─────────────────────────────────
  // When a provider toggles "Online", we start periodic location updates
  // to Firestore. This powers the map view for customers.
  // Location is stored as latitude/longitude + a geohash for efficient
  // proximity queries. Updates stop when provider goes offline.

  static Timer? _broadcastTimer;

  /// Start broadcasting location every 60 seconds. Call when provider goes online.
  static void startBroadcasting(String uid) {
    stopBroadcasting();
    // Immediate first update
    _broadcastPosition(uid);
    _broadcastTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _broadcastPosition(uid);
    });
  }

  /// Stop broadcasting. Call when provider goes offline or app disposes.
  static void stopBroadcasting() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
  }

  static Future<void> _broadcastPosition(String uid) async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.whileInUse &&
          perm != LocationPermission.always) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
      _cached = pos;
      final geohash = _encodeGeohash(pos.latitude, pos.longitude, precision: 7);
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'geohash': geohash,
        'locationUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[Location] Broadcast error: $e');
    }
  }

  /// Simple geohash encoder — produces a base-32 string of [precision] chars.
  /// Used for efficient proximity prefix queries (e.g., all providers in the
  /// same ~150m×150m cell share the same 7-char geohash prefix).
  static String _encodeGeohash(double lat, double lng, {int precision = 7}) {
    const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
    var minLat = -90.0, maxLat = 90.0;
    var minLng = -180.0, maxLng = 180.0;
    var isLng = true;
    var bit = 0;
    var ch = 0;
    final hash = StringBuffer();

    while (hash.length < precision) {
      final mid = isLng ? (minLng + maxLng) / 2 : (minLat + maxLat) / 2;
      final val = isLng ? lng : lat;
      if (val >= mid) {
        ch |= (1 << (4 - bit));
        if (isLng) { minLng = mid; } else { minLat = mid; }
      } else {
        if (isLng) { maxLng = mid; } else { maxLat = mid; }
      }
      isLng = !isLng;
      if (++bit == 5) {
        hash.write(base32[ch]);
        bit = 0;
        ch = 0;
      }
    }
    return hash.toString();
  }

  // ── Distance helpers ───────────────────────────────────────────────────────
  /// Returns a Hebrew distance label: "בשכונתך" < 1 km, else "X.X ק״מ".
  static String distanceLabel(
      double myLat, double myLng, double targetLat, double targetLng) {
    final meters =
        Geolocator.distanceBetween(myLat, myLng, targetLat, targetLng);
    if (meters < 1000) return 'בשכונתך';
    final km = meters / 1000;
    return '${km.toStringAsFixed(1)} ק"מ';
  }

  /// Returns distance in meters, or null if any coordinate is missing.
  static double? distanceMeters(
      double myLat, double myLng, double? lat, double? lng) {
    if (lat == null || lng == null) return null;
    return Geolocator.distanceBetween(myLat, myLng, lat, lng);
  }

  // ── Internal ───────────────────────────────────────────────────────────────
  /// Fetches a fresh position via the geolocator package. Discriminates
  /// between exception types so we can see the actual reason in the
  /// console (LocationServiceDisabledException, PermissionDeniedException,
  /// TimeoutException, etc.) instead of a generic "fetch failed".
  ///
  /// Falls back to `getLastKnownPosition` if the live fix fails. The web
  /// JS-interop fallback lives in the callers (`requestAndGet` /
  /// `getIfGranted`) — this method stays geolocator-only.
  static Future<Position?> _fetchPosition() async {
    // ignore: avoid_print
    print('[LocationService] _fetchPosition: calling Geolocator.getCurrentPosition (timeLimit 15s)');
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      _cached = pos;
      // ignore: avoid_print
      print('[LocationService] _fetchPosition: success (${pos.latitude}, ${pos.longitude})');
      return pos;
    } on LocationServiceDisabledException catch (e) {
      // ignore: avoid_print
      print('[LocationService] _fetchPosition: LocationServiceDisabledException — $e (location services off in OS)');
    } on PermissionDeniedException catch (e) {
      // ignore: avoid_print
      print('[LocationService] _fetchPosition: PermissionDeniedException — $e (browser/OS denied)');
    } on TimeoutException catch (e) {
      // ignore: avoid_print
      print('[LocationService] _fetchPosition: TimeoutException — $e (no fix within 15s)');
    } catch (e, st) {
      // ignore: avoid_print
      print('[LocationService] _fetchPosition: unexpected error — $e\n$st');
    }
    // Try last-known as a final fallback
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        _cached = last;
        // ignore: avoid_print
        print('[LocationService] _fetchPosition: using getLastKnownPosition (${last.latitude}, ${last.longitude})');
        return last;
      }
      // ignore: avoid_print
      print('[LocationService] _fetchPosition: getLastKnownPosition returned null');
    } catch (e2) {
      // ignore: avoid_print
      print('[LocationService] _fetchPosition: getLastKnownPosition threw: $e2');
    }
    return null;
  }

  // ── Premium permission dialog ──────────────────────────────────────────────
  static Future<bool> _showPermissionDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: const Icon(Icons.location_on_rounded,
                    color: Colors.white, size: 33),
              ),
              const SizedBox(height: 22),
              const Text(
                'שיפור חוויית החיפוש',
                style:
                    TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'נאפשר לאפליקציה לגשת למיקומך כדי להציג ספקים קרובים אליך ולמיין תוצאות לפי מרחק.',
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    height: 1.55),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 26),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'אפשר גישה למיקום',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('לא עכשיו',
                    style:
                        TextStyle(color: Colors.grey[500], fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

}
