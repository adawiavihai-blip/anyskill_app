import 'package:firebase_auth/firebase_auth.dart';

/// Hard-coded feature gate for the v3 categories admin tab (Phase B).
///
/// Per Q3-C decision (CLAUDE.md plan, 2026-04-20):
/// only the project owner sees the new tab during the soft-launch period.
/// All other admins continue to see the legacy `AdminCategoriesManagementTab`.
///
/// When we're ready to widen the audience, replace [isCategoriesV3Enabled]
/// with a Firestore-backed flag (option Q3-B) — no UI changes required as
/// long as the boolean signature is preserved.
class CategoriesV3FeatureFlag {
  CategoriesV3FeatureFlag._();

  /// Whitelist of admin uids that may see the v3 tab. Currently a single uid
  /// (Avihai). Add more here when widening — or migrate to Firestore.
  static const Set<String> _whitelistedUids = <String>{
    'mZuhdMgtgjPPCYzWjXA3KNvr41F2', // Avihai (project owner)
  };

  /// `true` if the currently signed-in user should see the v3 tab.
  /// Defaults to `false` when nobody is signed in (defensive).
  static bool get isCategoriesV3Enabled {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return false;
    return _whitelistedUids.contains(uid);
  }
}
