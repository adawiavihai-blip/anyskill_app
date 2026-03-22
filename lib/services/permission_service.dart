import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Centralised permission memory — "Ask Once, Remember Forever".
///
/// Status values (same set for both permissions):
///   null       — never asked on this device
///   'granted'  — user allowed
///   'denied'   — user refused (our dialog or OS); do not re-prompt
///
/// Backed by SharedPreferences (persists across restarts, cleared only on
/// uninstall). On login, we also cross-check the Firestore user document so
/// a reinstall can recover previously-granted state from the server.
class PermissionService {
  PermissionService._();

  // ── SharedPreferences keys (versioned — bump if schema changes) ────────────
  static const _kNotif              = 'perm_notif_v1';
  static const _kLocation           = 'perm_location_v1';
  static const _kHasSeenPermissions = 'has_seen_permissions_v1';

  // ── Status constants ───────────────────────────────────────────────────────
  static const granted = 'granted';
  static const denied  = 'denied';

  // ── Notification status ────────────────────────────────────────────────────

  static Future<String?> getNotificationStatus() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kNotif);
  }

  static Future<void> saveNotificationStatus(String status) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kNotif, status);
    debugPrint('PermissionService: notification → $status');
  }

  // ── Location status ────────────────────────────────────────────────────────

  static Future<String?> getLocationStatus() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kLocation);
  }

  static Future<void> saveLocationStatus(String status) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLocation, status);
    debugPrint('PermissionService: location → $status');
  }

  // ── One-time permission onboarding screen flag ────────────────────────────

  static Future<bool> hasSeenPermissions() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kHasSeenPermissions) ?? false;
  }

  static Future<void> markPermissionsSeen() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kHasSeenPermissions, true);
    debugPrint('PermissionService: hasSeenPermissions → true');
  }

  // ── Firestore recovery (called once on login) ──────────────────────────────
  /// Reads the logged-in user's Firestore doc and infers permission status from
  /// data already stored there (fcmToken → notifications granted; latitude →
  /// location granted). Only writes locally if no local answer exists yet —
  /// useful after a reinstall where SharedPreferences was cleared.
  static Future<void> recoverFromFirestore() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final prefs = await SharedPreferences.getInstance();
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = doc.data() ?? {};

      // Notification: having a stored fcmToken means the user granted at
      // least once on a previous install.
      if (prefs.getString(_kNotif) == null) {
        final hasToken = (data['fcmToken'] as String? ?? '').isNotEmpty;
        if (hasToken) {
          await prefs.setString(_kNotif, granted);
          debugPrint('PermissionService: recovered notification=granted from Firestore');
        }
      }

      // Location: having lat/lng in Firestore means location was granted before.
      if (prefs.getString(_kLocation) == null) {
        final hasLocation = data['latitude'] != null;
        if (hasLocation) {
          await prefs.setString(_kLocation, granted);
          debugPrint('PermissionService: recovered location=granted from Firestore');
        }
      }
    } catch (e) {
      debugPrint('PermissionService: recoverFromFirestore error: $e');
    }
  }
}
