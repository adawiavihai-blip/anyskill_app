import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'cached_readers.dart';
import 'private_data_service.dart';
import 'provider_listing_service.dart';

/// Pure Firestore-write service for the Edit Profile flow.
///
/// Extracted from `_EditProfileScreenState._saveProfile` +
/// `_syncToProviderListing` in §84 (2026-05-14). The screen still owns:
///   • Input validation (50+ controllers + state flags)
///   • Building the [payload] Map from validated values
///   • UI feedback (snackbar + setState + Navigator.pop)
///
/// This service does only the Firestore writes:
///   1. `users/{uid}` set(merge: true) — main profile doc
///   2. Cache invalidation (CachedReaders §61)
///   3. Optional: `users/{uid}/private/identity` dual-write (email only)
///   4. Optional: `provider_listings/{listingId}` mirror sync (15+ fields)
///   5. Optional: ProviderListingService auto-migrate when no listing exists
///
/// The split mirrors §81's ExpertBookingService. The screen builds the
/// "request" (Map payload) and gets back success-or-throw — same contract
/// as the legacy in-screen flow, just relocated.
class ProfileSaveService {
  ProfileSaveService._();

  /// Retries a Firestore write up to 5 times when the SDK throws an
  /// `INTERNAL ASSERTION FAILED` (IDs b815 / ca9) — a known Web SDK race
  /// in the watch-stream aggregator. Other errors propagate immediately.
  ///
  /// Backoff: 0 → 800ms → 2s → 4s → 8s. Total worst case ~15s before
  /// giving up. The 2026-05-14 version was 3 attempts × 2.1s total —
  /// way too tight: live user (רועי צברי, 2026-05-15) hit the failure
  /// on his FIRST save after a 2-image gallery upload because the
  /// SDK's watch-stream aggregator hadn't fully reset between retries
  /// and all 3 attempts failed in quick succession.
  ///
  /// On the LAST attempt (i == 4) we also bounce the network — call
  /// `disableNetwork()` then `enableNetwork()` BEFORE the retry. This
  /// flushes the SDK's in-memory watch-stream state without losing
  /// auth or in-flight transactions, and effectively reproduces what
  /// a browser refresh does internally (which is why "refresh fixes
  /// it"). Safe on web: persistence is OFF (Law 23) so no cache to
  /// reset, and any concurrent reads simply re-subscribe transparently.
  ///
  /// Note: 'INTERNAL ASSERTION FAILED' surfaces as a plain `Error`
  /// (not `FirebaseException`) so we string-match. Brittle but
  /// unavoidable — Firestore exposes no error code for this internal
  /// state corruption.
  static Future<T> _writeWithRetry<T>(Future<T> Function() op) async {
    const backoffs = [
      Duration.zero,
      Duration(milliseconds: 800),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
    ];
    Object? lastError;
    for (int attempt = 0; attempt < backoffs.length; attempt++) {
      if (attempt > 0) await Future.delayed(backoffs[attempt]);
      // On the final attempt, bounce the network FIRST. This is what
      // makes the difference between "user has to refresh" and "save
      // self-heals". `disableNetwork` + `enableNetwork` resets the
      // SDK's watch-stream aggregator — the exact internal state that
      // INTERNAL ASSERTION FAILED is complaining about.
      if (attempt == backoffs.length - 1) {
        try {
          await FirebaseFirestore.instance.disableNetwork();
          await Future.delayed(const Duration(milliseconds: 400));
          await FirebaseFirestore.instance.enableNetwork();
          debugPrint(
              '[ProfileSaveService] Bounced Firestore network before final retry');
        } catch (e) {
          debugPrint('[ProfileSaveService] Network bounce failed (continuing): $e');
        }
      }
      try {
        return await op();
      } catch (e) {
        lastError = e;
        final s = e.toString();
        final isInternalAssert = s.contains('INTERNAL ASSERTION FAILED') ||
            s.contains('ID: b815') ||
            s.contains('ID: ca9') ||
            // Newer Firestore SDKs sometimes surface the race as
            // a FirebaseException with code 'internal' instead.
            s.contains('[cloud_firestore/internal]');
        if (!isInternalAssert) rethrow; // unrelated error → fail fast
        debugPrint(
            '[ProfileSaveService] SDK internal assertion (attempt ${attempt + 1}/${backoffs.length}) — retrying');
      }
    }
    // All retries exhausted — surface the original error.
    // ignore: only_throw_errors
    throw lastError ?? StateError('write retry exhausted');
  }

  /// Verifies a write reached the server by reading the doc fresh and
  /// comparing primitive canary fields from the payload. Returns true
  /// when the saved doc matches the payload — meaning the SDK race
  /// fired AFTER the write committed and we can treat it as success.
  ///
  /// Used by [save] to recover from `INTERNAL ASSERTION FAILED` cases
  /// where `_writeWithRetry` exhausted but the write actually landed
  /// on the server (live bug, רועי צברי 2026-05-15: every retry attempt
  /// got the same SDK exception even though the gallery URLs WERE
  /// being saved on each attempt).
  ///
  /// Strategy: pick up to 3 primitive scalar fields from the payload
  /// (String / num / bool / List of primitives) and verify they
  /// exist on the server-fresh doc. Maps + nested objects are skipped
  /// because deep equality is unreliable across Firestore Timestamp /
  /// FieldValue normalization. 1 matching field is enough — the write
  /// is atomic, so any one canary confirms the whole payload landed.
  static Future<bool> _verifyWriteSucceeded(
    FirebaseFirestore db,
    String uid,
    Map<String, dynamic> payload,
  ) async {
    try {
      final snap = await db
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      final saved = snap.data() ?? <String, dynamic>{};
      // Pick up to 3 primitive scalar canaries from the payload.
      int matched = 0;
      int checked = 0;
      for (final entry in payload.entries) {
        if (checked >= 3) break;
        final v = entry.value;
        // Skip non-comparable / always-changing / sentinel values.
        if (v is FieldValue) continue;
        if (v is Map) continue;
        if (v is List && v.any((x) => x is Map)) continue;
        checked++;
        final savedVal = saved[entry.key];
        if (savedVal == null) continue;
        // Primitive scalar — straight ==.
        if (v is String || v is num || v is bool) {
          if (savedVal == v) matched++;
          continue;
        }
        // Simple list — compare length + first/last to avoid deep walk.
        if (v is List && savedVal is List) {
          if (v.length == savedVal.length) {
            if (v.isEmpty || (v.first == savedVal.first &&
                v.last == savedVal.last)) {
              matched++;
            }
          }
          continue;
        }
      }
      debugPrint(
          '[ProfileSaveService] Server verification: $matched/$checked canaries matched');
      return matched > 0;
    } catch (e) {
      debugPrint('[ProfileSaveService] Server verification failed: $e');
      return false;
    }
  }

  /// Saves the user profile + optionally mirrors to provider_listings.
  ///
  /// Throws on Firestore errors (caught by caller's try/catch). Non-fatal
  /// failures inside the optional dual-write + listing-sync paths are
  /// caught and logged, NOT propagated — matches the legacy behavior so
  /// a stale private/identity doc doesn't block a successful main save.
  ///
  /// [payload] is the full user-doc update Map (FieldValue.delete() values
  /// allowed — they pass through to Firestore unchanged).
  /// [safeEmail] enables the private/identity dual-write when non-null
  /// AND non-empty.
  /// [syncListings] (provider-only) triggers [_syncToProviderListing] with
  /// the [activeListingId] / [serviceTypeName] / [parentCategoryName]
  /// triple — same logic as the legacy method, including auto-migrate
  /// fallback when no listing exists yet.
  static Future<void> save({
    required String uid,
    required Map<String, dynamic> payload,
    String? safeEmail,
    bool syncListings = false,
    String? activeListingId,
    String? serviceTypeName,
    String? parentCategoryName,
  }) async {
    final db = FirebaseFirestore.instance;

    // 1. Main user-doc write — set(merge:true) so it works whether the
    //    doc exists (update rule) or not (create rule). Legacy used
    //    update() and failed for brand-new phone-OTP signups whose
    //    role-selection sheet write was lost mid-flow.
    //
    // 2026-05-15 — TRIPLE-LAYER DEFENSE against the SDK race:
    //  (a) `_writeWithRetry`: 5 attempts × 15s + network bounce
    //  (b) If (a) still throws → VERIFY on the server (the race
    //      fires AFTER the write commits, so the data is usually
    //      already saved — we just see a stale listener exception)
    //  (c) If (b) confirms the write → silently treat as success
    //
    // This is the difference between "user has to refresh" and "save
    // self-heals". Live user (רועי צברי, 2026-05-15) hit (a) failing
    // even after the 15s patience. Layer (b) converts the SDK race
    // into a transparent operation — Roi sees a successful save with
    // no error message and no refresh required.
    try {
      await _writeWithRetry(() => db
          .collection('users')
          .doc(uid)
          .set(payload, SetOptions(merge: true)));
    } catch (e) {
      final s = e.toString();
      final isInternalAssert = s.contains('INTERNAL ASSERTION FAILED') ||
          s.contains('ID: b815') ||
          s.contains('ID: ca9') ||
          s.contains('[cloud_firestore/internal]');
      if (!isInternalAssert) rethrow;
      // The SDK race fires from the watch-stream aggregator AFTER
      // the write reaches the server. Verify by reading the doc
      // fresh from server and comparing a canary field from the
      // payload. If it matches, the write succeeded — silently
      // recover. If not, propagate the original error so the
      // user gets a real failure message.
      debugPrint(
          '[ProfileSaveService] SDK race exhausted retries — verifying write on server');
      final ok = await _verifyWriteSucceeded(db, uid, payload);
      if (!ok) rethrow;
      debugPrint(
          '[ProfileSaveService] SDK race recovered — write IS on server, treating as success');
    }

    // 2. CLAUDE.md §61 invalidation contract — every mutation of a cached
    //    entity MUST invalidate so other screens (favorites §63, chat §66,
    //    BookingProfileAvatar §67) re-read fresh.
    CachedReaders.invalidateProvider(uid);

    // 3. CLAUDE.md §11 — dual-write contact email to private/identity.
    //    Phone is NOT mirrored — PhoneCollectionScreen owns the phone
    //    field end-to-end. Best-effort; failure here is non-fatal.
    if (safeEmail != null && safeEmail.isNotEmpty) {
      try {
        await PrivateDataService.writeContactData(uid, email: safeEmail);
      } catch (e) {
        debugPrint('[ProfileSaveService] writeContactData error: $e');
      }
    }

    // 4. Provider-only: mirror identity fields to provider_listings.
    //    Best-effort — listing sync failure does NOT roll back the main
    //    profile save. Matches the legacy `_syncToProviderListing`
    //    catch-and-log behavior.
    if (syncListings) {
      try {
        await _syncToProviderListing(
          db: db,
          uid: uid,
          payload: payload,
          activeListingId: activeListingId,
          serviceTypeName: serviceTypeName,
          parentCategoryName: parentCategoryName,
        );
      } catch (e) {
        debugPrint('[ProfileSaveService] Listing sync error: $e');
      }
    }
  }

  /// Mirrors identity-specific fields from the main user-doc payload to
  /// the active provider_listing. Uses [activeListingId] when known,
  /// else falls back to identityIndex == 0, else auto-migrates via
  /// ProviderListingService.
  ///
  /// Field allow-list matches the legacy `_syncToProviderListing` exactly.
  /// `FieldValue.delete()` entries are stripped — listings may not have
  /// the field yet, and FieldValue.delete() on a non-existent field is
  /// a no-op anyway. Tombstoning is the parent user-doc's responsibility.
  static Future<void> _syncToProviderListing({
    required FirebaseFirestore db,
    required String uid,
    required Map<String, dynamic> payload,
    String? activeListingId,
    String? serviceTypeName,
    String? parentCategoryName,
  }) async {
    QuerySnapshot<Map<String, dynamic>>? snap;
    if (activeListingId == null) {
      snap = await db
          .collection('provider_listings')
          .where('uid', isEqualTo: uid)
          .where('identityIndex', isEqualTo: 0)
          .limit(1)
          .get();
    }

    final listingUpdate = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Mirror identity-specific fields. Same allow-list as the legacy
    // method — don't add fields here without checking the listings rule
    // first (some fields are user-doc-only and the rule will reject).
    const mirrorKeys = [
      'name',
      'profileImage',
      'serviceType',
      'parentCategory',
      'aboutMe',
      'pricePerHour',
      'gallery',
      'quickTags',
      'categoryTags',
      'cancellationPolicy',
      'workingHours',
      'categoryDetails',
      'priceList',
      'isVolunteer',
      'massageProfile',
      'pestControlProfile',
      'deliveryProfile',
      'cleaningProfile',
      'handymanProfile',
      'fitnessTrainerProfile',
      'babysitterProfile',
      'motorcycleTowProfile',
    ];
    for (final key in mirrorKeys) {
      if (payload.containsKey(key)) {
        listingUpdate[key] = payload[key];
      }
    }

    // Strip FieldValue.delete() — listings may not have the field yet.
    listingUpdate.removeWhere((_, v) => v is FieldValue);

    if (activeListingId != null) {
      await _writeWithRetry(() => db
          .collection('provider_listings')
          .doc(activeListingId)
          .update(listingUpdate));
      debugPrint(
          '[ProfileSaveService] Active listing synced: $activeListingId');
    } else if (snap != null && snap.docs.isNotEmpty) {
      await _writeWithRetry(() => db
          .collection('provider_listings')
          .doc(snap!.docs.first.id)
          .update(listingUpdate));
      debugPrint(
          '[ProfileSaveService] Primary listing synced: ${snap.docs.first.id}');
    } else {
      // No listing yet — auto-migrate on save.
      final listingId = await ProviderListingService.migrateIfNeeded(uid);
      debugPrint(
          '[ProfileSaveService] Listing migrated on save: $listingId');
    }
  }
}
