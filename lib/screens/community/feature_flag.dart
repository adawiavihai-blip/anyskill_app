/// Feature flag for the redesigned Community module (v2 — "קהילה").
///
/// **The contract:**
/// - When the user's UID is in [_communityV2Whitelist], all routes
///   under `lib/screens/community/` activate AND the home banner +
///   profile heart switch to the new design.
/// - For every other UID, the legacy code paths (the 3,855-line
///   [community_hub_screen.dart] monolith and the red-pink-purple home
///   banner) keep rendering exactly as before.
///
/// **Rollback:** clear the whitelist and the entire app falls back to
/// the legacy v1 paths in one frame. No Firestore writes need to be
/// reverted — the only data layer change is the new
/// `users/{uid}.goldHeartExpiresAt` field, which is additive and
/// ignored by legacy code.
///
/// **Promotion plan:**
/// 1. Owner adds their own UID to [_communityV2Whitelist] and tests
///    locally. (Get the UID from Firebase Console → Authentication.)
/// 2. After Phase B ships and the backfill CF runs, add 1-2 admin UIDs
///    for parallel QA.
/// 3. After Phase H QA passes, replace the whitelist body with
///    `return true;` to ship to all users.
/// 4. After 1 week of stability, delete this file and inline `true`
///    everywhere it's referenced.
///
/// **NEVER** add CFs, Firestore queries, or Remote Config to this file.
/// A hard-coded list keeps the rollout reversible in one git revert.
/// (Same precedent as Categories v3 — see CLAUDE.md §45.)
library;

/// UIDs that were used during staged rollout. Kept here only as a
/// historical record — the gate now opens for every signed-in user
/// (promotion plan step 3). Restore the whitelist branch below to
/// roll back in one git diff if needed.
// ignore: unused_element
const Set<String> _communityV2Whitelist = {
  // Owner — adawiavihai@gmail.com
  'mZuhdMgtgjPPCYzWjXA3KNvr41F2',
};

/// Returns `true` iff [uid] should see the redesigned Community module.
///
/// Pass `null` (e.g., logged-out users) → always returns `false`.
/// Pass an empty string → always returns `false`.
///
/// **Rollout (2026-05-07):** opened to every signed-in user. To roll
/// back to the whitelist, replace the body with
/// `return _communityV2Whitelist.contains(uid);`.
bool isCommunityV2EnabledFor(String? uid) {
  if (uid == null || uid.isEmpty) return false;
  return true;
}

/// Convenience for screens that already have a `users/{uid}` map.
bool isCommunityV2EnabledForUser(Map<String, dynamic>? userData) {
  final uid = userData?['uid'] as String?;
  return isCommunityV2EnabledFor(uid);
}
