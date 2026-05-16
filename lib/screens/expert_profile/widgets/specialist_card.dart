import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/location_service.dart';
import '../../../utils/safe_image_provider.dart';
import '../../../widgets/community/heart_display_helper.dart';
import '../../../widgets/pro_badge.dart';
import '../../../widgets/xp_progress_bar.dart';
import 'tokens.dart';

/// Provider hero card at the top of the expert profile screen — mirrors
/// ProfileScreen's specialist header.
///
/// Extracted from `expert_profile_screen.dart` in §80. Stateless: all data
/// flows from the [data] Map. The screen also passes the customer's current
/// [myPosition] (used for the distance row) — if null, the row renders a
/// "computing distance..." placeholder.
class SpecialistCard extends StatelessWidget {
  const SpecialistCard({
    super.key,
    required this.data,
    required this.expertId,
    required this.expertName,
    required this.myPosition,
  });

  final Map<String, dynamic> data;
  final String expertId;
  final String expertName;
  final Position? myPosition;

  @override
  Widget build(BuildContext context) {
    final profileImg = data['profileImage'] as String? ??
        data['photoUrl'] as String? ??
        data['photoURL'] as String? ?? // Firebase Auth field name
        '';
    final imgProvider = safeImageProvider(profileImg);
    final name = data['name'] as String? ?? expertName;
    final isVerified = data['isVerified'] == true;
    final isVolunteer = shouldShowHeartFor(
      viewerUid: FirebaseAuth.instance.currentUser?.uid,
      ownerData: data,
    );
    final isAnySkillPro = data['isAnySkillPro'] == true;
    final serviceType = data['serviceType'] as String? ?? '';
    final bio =
        data['aboutMe'] as String? ?? data['bio'] as String? ?? '';
    final xp = (data['xp'] as num? ?? 0).toInt();
    final rating = data['rating'] ?? '5.0';
    final reviewsCount = (data['reviewsCount'] as num? ?? 0).toInt();
    final jobsCount = (data['completedJobsCount'] as num? ??
            data['orderCount'] as num? ??
            reviewsCount)
        .toInt();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── LEFT: name, role label, specialty, bio, stats ─────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (isVerified) ...[
                          const Icon(Icons.verified,
                              color: Colors.blue, size: 18),
                          const SizedBox(width: 5),
                        ],
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: Colors.black),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(context).expProviderRole,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9CA3AF),
                          fontWeight: FontWeight.w400),
                    ),
                    if (serviceType.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(serviceType,
                          style: const TextStyle(
                              color: ExpertProfileTokens.purple,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ],
                    if (bio.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(bio,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12.5,
                              height: 1.4)),
                    ],
                    const SizedBox(height: 14),
                    _StatRow(
                      label: AppLocalizations.of(context).expJobsLabel,
                      value: '$jobsCount',
                      icon: Icons.shield_outlined,
                      iconColor: ExpertProfileTokens.purple,
                    ),
                    const Divider(
                        height: 20,
                        color: Color(0xFFF3F4F6),
                        thickness: 1),
                    _StatRow(
                      label: AppLocalizations.of(context).expRatingLabel,
                      value: '$rating',
                      icon: Icons.star_rounded,
                      iconColor: ExpertProfileTokens.gold,
                    ),
                    const Divider(
                        height: 20,
                        color: Color(0xFFF3F4F6),
                        thickness: 1),
                    // §10.6 (live bug 2026-05-16 — Roi had 2 reviews but a
                    // customer's profile view showed "0"): show a LIVE count
                    // read straight from the `reviews` collection instead of
                    // the denormalized `reviewsCount` field, which goes stale
                    // whenever the publish recalc trigger hasn't run or landed
                    // on the other identity doc (user vs listing).
                    _ReviewsCountStat(
                      expertId: expertId,
                      listingId: data['listingId'] as String?,
                      fallback: reviewsCount,
                    ),
                    _VolunteerCountStat(expertId: expertId),
                    _DistanceRow(data: data, myPosition: myPosition),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // ── RIGHT: profile photo + golden heart + Pro badge ─────
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 52,
                        backgroundColor: imgProvider != null
                            ? ExpertProfileTokens.purpleSoft
                            : const Color(0xFFE5E7EB),
                        backgroundImage: imgProvider,
                        child: imgProvider != null
                            ? null
                            : Text(
                                name.isNotEmpty
                                    ? name[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF374151)),
                              ),
                      ),
                      if (isVolunteer)
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.favorite_rounded,
                                color: Color(0xFFD4AF37), size: 18),
                          ),
                        ),
                    ],
                  ),
                  if (isAnySkillPro) ...[
                    const SizedBox(height: 10),
                    const ProBadge(),
                  ],
                ],
              ),
            ],
          ),
          if ((FirebaseAuth.instance.currentUser?.uid ?? '') ==
              expertId) ...[
            const SizedBox(height: 16),
            XpProgressBar(xp: xp),
          ],
        ],
      ),
    );
  }
}

/// Single label-value stat row used inside [SpecialistCard].
class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 6),
        Text(value,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black87)),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: Color(0xFF9CA3AF))),
      ],
    );
  }
}

/// Live count of an expert's reviews, read straight from the `reviews`
/// collection — NOT the denormalized `users/{uid}.reviewsCount` /
/// `provider_listings/{id}.reviewsCount` field.
///
/// §10.6 (live bug 2026-05-16 — Roi had 2 reviews but a customer's profile
/// view showed "0"): the denormalized counter only refreshes when the
/// review-publish recalc trigger runs, and it can land on the wrong
/// identity doc (user doc vs listing doc). Counting live mirrors exactly
/// what [ReviewsSection] renders below, so the card stat and the reviews
/// list can never disagree. UNION of `expertId` + `listingId`, deduped by
/// docId — matches the proven query union in `reviews_section.dart`.
class _ReviewsCountStat extends StatelessWidget {
  const _ReviewsCountStat({
    required this.expertId,
    required this.listingId,
    required this.fallback,
  });

  final String expertId;
  final String? listingId;
  final int fallback;

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final byExpert = db
        .collection('reviews')
        .where('expertId', isEqualTo: expertId)
        .limit(100)
        .snapshots();
    final byListing = (listingId != null && listingId!.isNotEmpty)
        ? db
            .collection('reviews')
            .where('listingId', isEqualTo: listingId)
            .limit(100)
            .snapshots()
        : null;

    Widget row(int count) => _StatRow(
          label: AppLocalizations.of(context).expReviewsLabel,
          value: '$count',
          icon: Icons.chat_bubble_outline_rounded,
          iconColor: Colors.teal,
        );

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: byExpert,
      builder: (_, expertSnap) {
        if (byListing == null) {
          if (!expertSnap.hasData) return row(fallback);
          return row(_countVisible([expertSnap.data]));
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: byListing,
          builder: (_, listingSnap) {
            if (!expertSnap.hasData && !listingSnap.hasData) {
              return row(fallback);
            }
            return row(_countVisible([expertSnap.data, listingSnap.data]));
          },
        );
      },
    );
  }

  /// Dedupe by docId across the union snapshots, then count reviews that
  /// would be visible to a customer. Matches [ReviewsSection]'s filter: a
  /// review counts when `isPublished == true` OR the field is absent
  /// (legacy reviews predate the double-blind publish flag).
  static int _countVisible(
      List<QuerySnapshot<Map<String, dynamic>>?> snaps) {
    final counted = <String>{};
    final rejected = <String>{};
    for (final snap in snaps) {
      if (snap == null) continue;
      for (final doc in snap.docs) {
        if (counted.contains(doc.id) || rejected.contains(doc.id)) continue;
        final published = doc.data()['isPublished'];
        if (published != null && published != true) {
          rejected.add(doc.id);
        } else {
          counted.add(doc.id);
        }
      }
    }
    return counted.length;
  }
}

/// Real-time count of completed community tasks where this expert
/// volunteered. Streams from `community_requests` (limit 100).
class _VolunteerCountStat extends StatelessWidget {
  const _VolunteerCountStat({required this.expertId});

  final String expertId;

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('community_requests')
        .where('volunteerId', isEqualTo: expertId)
        .where('status', isEqualTo: 'completed')
        .limit(100)
        .snapshots();
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (_, snap) {
        final count = snap.hasData ? snap.data!.size : 0;
        return Column(
          children: [
            const Divider(
                height: 20, color: Color(0xFFF3F4F6), thickness: 1),
            _StatRow(
              label: AppLocalizations.of(context).expVolunteersLabel,
              value: '$count',
              icon: Icons.favorite_rounded,
              iconColor: const Color(0xFFD4AF37),
            ),
          ],
        );
      },
    );
  }
}

/// Distance-from-you row under the volunteer counter. Uses [myPosition]
/// (passed from the parent screen, which owns the location lifecycle)
/// + the provider's lat/lng on the user doc. If either side is unknown,
/// the row shows a placeholder label.
class _DistanceRow extends StatelessWidget {
  const _DistanceRow({required this.data, required this.myPosition});

  final Map<String, dynamic> data;
  final Position? myPosition;

  @override
  Widget build(BuildContext context) {
    final myPos = myPosition ?? LocationService.cached;
    final providerLat = (data['latitude'] as num?)?.toDouble();
    final providerLng = (data['longitude'] as num?)?.toDouble();

    String label;
    Color color = const Color(0xFF10B981);

    if (myPos == null) {
      label = 'מחשב מרחק...';
      color = const Color(0xFF9CA3AF);
    } else if (providerLat == null || providerLng == null) {
      label = 'מרחק לא ידוע';
      color = const Color(0xFF9CA3AF);
    } else {
      try {
        final meters = Geolocator.distanceBetween(
            myPos.latitude, myPos.longitude, providerLat, providerLng);
        label = meters < 1000
            ? 'בשכונתך'
            : '${(meters / 1000).toStringAsFixed(1)} ק"מ';
      } catch (_) {
        label = 'מרחק לא ידוע';
        color = const Color(0xFF9CA3AF);
      }
    }

    return Column(
      children: [
        const Divider(height: 20, color: Color(0xFFF3F4F6), thickness: 1),
        _StatRow(
          label: 'מרחק ממך',
          value: label,
          icon: Icons.location_on_rounded,
          iconColor: color,
        ),
      ],
    );
  }
}
