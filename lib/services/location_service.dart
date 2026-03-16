import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'permission_service.dart';

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

  // ── Permission-aware request (shows premium dialog ONCE) ──────────────────
  /// Shows our premium in-app dialog before the OS prompt — but only once.
  /// Subsequent calls respect the stored answer from SharedPreferences:
  ///   granted → silently get position (no dialog)
  ///   denied  → return null immediately (no dialog, no OS prompt)
  static Future<Position?> requestAndGet(BuildContext context) async {
    if (_cached != null) return _cached;

    // ── 1. Check locally-stored answer ─────────────────────────────────────
    final stored = await PermissionService.getLocationStatus();

    if (stored == PermissionService.denied) {
      // User already said no — respect it, never re-prompt.
      return null;
    }

    if (stored == PermissionService.granted) {
      // Previously granted — verify OS hasn't revoked it (silent check).
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always) {
        return _fetchPosition();
      }
      // OS permission was revoked — update local record and fall through.
      await PermissionService.saveLocationStatus(PermissionService.denied);
      if (context.mounted) _showDeniedSnack(context);
      return null;
    }

    // ── 2. Never asked yet — check current OS status ────────────────────────
    final perm = await Geolocator.checkPermission();

    if (perm == LocationPermission.deniedForever) {
      await PermissionService.saveLocationStatus(PermissionService.denied);
      if (context.mounted) _showDeniedSnack(context);
      return null;
    }

    if (perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always) {
      // OS already granted (e.g. from location_module or a previous install).
      await PermissionService.saveLocationStatus(PermissionService.granted);
      return _fetchPosition();
    }

    // ── 3. Show our branded in-app dialog (the only time we ever show it) ───
    if (!context.mounted) return null;
    final proceed = await _showPermissionDialog(context);

    if (!proceed) {
      // User tapped "לא עכשיו" — store denied so we never show the dialog again.
      await PermissionService.saveLocationStatus(PermissionService.denied);
      return null;
    }

    // ── 4. User agreed — now ask the OS ─────────────────────────────────────
    final granted = await Geolocator.requestPermission();

    if (granted == LocationPermission.whileInUse ||
        granted == LocationPermission.always) {
      await PermissionService.saveLocationStatus(PermissionService.granted);
      return _fetchPosition();
    }

    // OS denied (or permanently denied)
    await PermissionService.saveLocationStatus(PermissionService.denied);
    if (granted == LocationPermission.deniedForever && context.mounted) {
      _showDeniedSnack(context);
    }
    return null;
  }

  /// Gets position only if permission is already granted — no dialog.
  static Future<Position?> getIfGranted() async {
    if (_cached != null) return _cached;
    final perm = await Geolocator.checkPermission();
    if (perm != LocationPermission.whileInUse &&
        perm != LocationPermission.always) { return null; }
    return _fetchPosition();
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
  static Future<Position?> _fetchPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      _cached = pos;
      return pos;
    } catch (_) {
      return null;
    }
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

  static void _showDeniedSnack(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
            'הגישה למיקום נחסמה. ניתן לשנות זאת בהגדרות המכשיר.'),
        action: SnackBarAction(
          label: 'הגדרות',
          textColor: Colors.white,
          onPressed: () => Geolocator.openAppSettings(),
        ),
        backgroundColor: Colors.grey[850],
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
