/// Gold Heart Helper — single source of truth for the 30-day volunteer heart.
///
/// **The contract:** every time a volunteer completes a community task,
/// `users/{uid}.goldHeartExpiresAt` is set to `now + 30 days`. The heart
/// is shown wherever `hasActiveGoldHeart(...) == true`. No cron — pure
/// timestamp comparison at read time.
///
/// **Renewal:** every new completion overwrites the timestamp with a new
/// `now + 30 days`, so 5 completions in 1 week = 5 renewals to the same
/// always-30-days-out date. After 30 days of inactivity the heart vanishes
/// silently (the next call returns `false`).
///
/// **Migration safety:** during the rollout, `hasActiveFromUserData()` ALSO
/// honours the legacy `lastVolunteerTaskAt` field (which the old
/// [VolunteerService] still wrote). After the backfill CF runs and the
/// feature flag is removed, this fallback can be deleted.
///
/// Spec: `docs/ui-specs/anyskill_community/docs/GOLD_HEART_LOGIC.md`.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

class GoldHeartHelper {
  GoldHeartHelper._();

  /// How long a gold heart stays active after a completed task.
  /// Renewed (NOT extended) on each new completion.
  static const Duration goldHeartDuration = Duration(days: 30);

  // ── Pure checks (no Firestore reads) ────────────────────────────────────

  /// True iff the user has an active gold heart RIGHT NOW.
  ///
  /// Pass `users/{uid}.goldHeartExpiresAt` directly. Returns `false` for
  /// `null` or any timestamp `<= DateTime.now()`.
  static bool hasActiveGoldHeart(Timestamp? expiresAt) {
    if (expiresAt == null) return false;
    return expiresAt.toDate().isAfter(DateTime.now());
  }

  /// User-data variant — checks the new `goldHeartExpiresAt` field FIRST,
  /// then falls back to the legacy `lastVolunteerTaskAt + 30d` window so
  /// pre-migration users don't lose their hearts on day 1 of rollout.
  ///
  /// **Remove the legacy branch** once the backfill CF has run AND the
  /// feature flag is lifted (Phase H).
  static bool hasActiveFromUserData(Map<String, dynamic> userData) {
    // Primary: new field.
    final expires = userData['goldHeartExpiresAt'];
    if (expires is Timestamp) {
      return expires.toDate().isAfter(DateTime.now());
    }

    // Legacy fallback (deprecated — remove after backfill).
    final legacyTs = userData['lastVolunteerTaskAt'];
    if (legacyTs is Timestamp) {
      final legacyExpiry = legacyTs.toDate().add(goldHeartDuration);
      return legacyExpiry.isAfter(DateTime.now());
    }

    return false;
  }

  // ── Display helpers ─────────────────────────────────────────────────────

  /// Whole days remaining until expiry. `null` if no active heart.
  /// Always rounds DOWN — "29 days left" reads better than "30".
  static int? daysUntilExpiry(Timestamp? expiresAt) {
    if (!hasActiveGoldHeart(expiresAt)) return null;
    final diff = expiresAt!.toDate().difference(DateTime.now());
    if (diff.isNegative) return null;
    return diff.inDays;
  }

  /// Whole days remaining derived from any user-data map (handles legacy).
  static int? daysUntilExpiryFromUserData(Map<String, dynamic> userData) {
    final expires = userData['goldHeartExpiresAt'];
    if (expires is Timestamp) return daysUntilExpiry(expires);

    final legacyTs = userData['lastVolunteerTaskAt'];
    if (legacyTs is Timestamp) {
      final synthetic = Timestamp.fromDate(
        legacyTs.toDate().add(goldHeartDuration),
      );
      return daysUntilExpiry(synthetic);
    }
    return null;
  }

  /// Used in mockup 07 — `LinearProgressIndicator` width.
  /// Returns 0.0–1.0. `null` if no active heart.
  static double? progressFraction(Timestamp? expiresAt) {
    final daysLeft = daysUntilExpiry(expiresAt);
    if (daysLeft == null) return null;
    return (daysLeft / goldHeartDuration.inDays).clamp(0.0, 1.0);
  }

  /// Hebrew long-form date — "26 במאי 2026".
  /// Used in mockup 06 ("לב זהב פעיל עד 26 במאי 2026").
  static String? expiryDateHebrew(Timestamp? expiresAt) {
    if (!hasActiveGoldHeart(expiresAt)) return null;
    final d = expiresAt!.toDate();
    return '${d.day} ב${_hebrewMonth(d.month)} ${d.year}';
  }

  /// Hebrew short-form date — "26 במאי" (no year).
  /// Used in mockup 07 ("פג תוקף ב-26 במאי").
  static String? expiryDateHebrewShort(Timestamp? expiresAt) {
    if (!hasActiveGoldHeart(expiresAt)) return null;
    final d = expiresAt!.toDate();
    return '${d.day} ב${_hebrewMonth(d.month)}';
  }

  // ── Service-side: grant / renew the heart ───────────────────────────────

  /// Returns the timestamp to write into `users/{uid}.goldHeartExpiresAt`
  /// when a community task is confirmed completed.
  ///
  /// **Always 30 days from now** — never additive. A user who completes
  /// 5 tasks in one day still ends with a single 30-day window starting
  /// from the most recent completion.
  static Timestamp grantGoldHeart() {
    return Timestamp.fromDate(
      DateTime.now().add(goldHeartDuration),
    );
  }

  // ── Internal ────────────────────────────────────────────────────────────

  static const List<String> _hebrewMonths = [
    'ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני',
    'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר',
  ];

  static String _hebrewMonth(int month) => _hebrewMonths[month - 1];
}
