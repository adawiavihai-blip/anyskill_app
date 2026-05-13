/// Display-side gate for the gold heart icon.
///
/// **Why this exists:** per Phase B kickoff rule (ג), the new
/// 30-day-expiry semantics are gated on the VIEWER's UID. A viewer in
/// the v2 whitelist sees the new gold-heart logic (active iff
/// `goldHeartExpiresAt > now`); a non-whitelist viewer keeps seeing the
/// legacy "permanent volunteer flag" semantics so their experience is
/// unchanged until the flag is lifted.
///
/// **What this is NOT:** the search ranking does NOT use this helper.
/// Ranking switched to the new helper for everyone (transparent
/// migration via [VolunteerService.hasActiveVolunteerBadge]) because
/// it's not a UI surface — the user only sees its effect, not the
/// ranking value itself. This file controls only the visible heart icon.
library;

import '../../screens/community/feature_flag.dart';
import '../../utils/gold_heart_helper.dart';

/// Should the gold heart icon be rendered for [ownerData] when viewed
/// by [viewerUid]?
///
/// Pass:
/// - [viewerUid]: the CURRENT user's uid (e.g.,
///   `FirebaseAuth.instance.currentUser?.uid`). Pass `null` for
///   logged-out viewers — they get the legacy semantics.
/// - [ownerData]: the user document of the person whose heart we're
///   considering displaying (NOT the viewer).
bool shouldShowHeartFor({
  required String? viewerUid,
  required Map<String, dynamic> ownerData,
}) {
  if (isCommunityV2EnabledFor(viewerUid)) {
    // V2: 30-day rolling timer. Gold heart vanishes after inactivity.
    return GoldHeartHelper.hasActiveFromUserData(ownerData);
  }
  // V1 legacy: permanent flag — the heart stays forever once earned.
  return ownerData['volunteerHeart'] == true ||
         ownerData['isVolunteer'] == true;
}
