import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/safe_image_provider.dart';
import 'review_photo_viewer.dart';
import 'tokens.dart';

/// Reviews subsystem for the expert profile screen.
///
/// Extracted from `expert_profile_screen.dart` in §80. The section is a
/// `StatefulWidget` that internalizes its own search query + "show all"
/// expansion state — the parent no longer carries those fields.
///
/// External state coupling kept minimal:
///   • [expertId] / [listingId] — drive the Firestore queries.
///   • [refreshKey] — bump from parent to force a stream rebuild after
///     a provider reply is sent. Used as the StreamBuilder's `ValueKey`.
///   • [onReplySent] — called after the provider reply CF succeeds so
///     the parent can bump its `_refreshTrigger`.
class ReviewsSection extends StatefulWidget {
  const ReviewsSection({
    super.key,
    required this.expertId,
    required this.listingId,
    required this.refreshKey,
    required this.onReplySent,
  });

  final String expertId;
  final String? listingId;
  final int refreshKey;
  final VoidCallback onReplySent;

  @override
  State<ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<ReviewsSection> {
  static const int _pageSize = 6;

  String _searchQuery = '';
  bool _expanded = false;

  // §10.6.7 + §15 Law 15 (live bug 2026-05-15 — רועי צברי):
  // Streams MUST be cached in initState. Previously they were created
  // inline in build() which (a) re-subscribed on every parent rebuild
  // and (b) had no supervisor timeout — on cold WebChannel the
  // `CircularProgressIndicator` showed forever because BOTH streams
  // hadn't delivered their first snapshot yet.
  // 2026-05-15 (live bug, רועי צברי "demo provider, reviews & rating
  // not shown"): UNION query over BOTH `listingId` AND `expertId`.
  // Some reviews seed paths set both fields, others only set
  // `expertId` (legacy) or only `listingId` (newer dual-identity
  // path). A single field query missed any review that didn't have
  // that exact field. UNION + client-side dedupe by docId catches
  // all of them.
  late Stream<QuerySnapshot<Map<String, dynamic>>> _reviewsByListingStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _reviewsByExpertStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _volunteerStream;
  // Cache the most recent successful snapshots so a transient
  // stream-rebuild blip doesn't flash an empty UI.
  QuerySnapshot<Map<String, dynamic>>? _lastReviewByListingSnap;
  QuerySnapshot<Map<String, dynamic>>? _lastReviewByExpertSnap;
  QuerySnapshot<Map<String, dynamic>>? _lastVolSnap;
  // Supervisor flag — after 6s without any data, render the
  // empty-state ("no reviews yet") instead of an infinite spinner.
  bool _supervisorFired = false;
  Timer? _supervisorTimer;
  int _streamsKey = 0; // bumped on refreshKey change to recreate streams

  @override
  void initState() {
    super.initState();
    _buildStreams();
    _armSupervisor();
  }

  @override
  void didUpdateWidget(covariant ReviewsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Parent bumps refreshKey after a provider reply succeeds. Re-create
    // the streams so the new review appears immediately without waiting
    // for the next snapshot tick.
    if (oldWidget.refreshKey != widget.refreshKey ||
        oldWidget.listingId != widget.listingId ||
        oldWidget.expertId != widget.expertId) {
      _streamsKey++;
      _buildStreams();
      _lastReviewByListingSnap = null;
      _lastReviewByExpertSnap = null;
      _lastVolSnap = null;
      _supervisorFired = false;
      _armSupervisor();
    }
  }

  void _buildStreams() {
    // UNION query (live bug fix 2026-05-15): always attach BOTH streams
    // and merge results client-side. Reviews seeded by older code paths
    // may have only `expertId` (no listingId yet), reviews seeded by
    // newer dual-identity code may have only `listingId` (no expertId
    // backfill yet), and demo reviews may have both. Querying only one
    // field meant we missed reviews seeded the "other way". With UNION
    // + dedupe-by-docId, every review surfaces regardless of seed shape.
    _reviewsByListingStream = (widget.listingId != null &&
            widget.listingId!.isNotEmpty)
        ? FirebaseFirestore.instance
            .collection('reviews')
            .where('listingId', isEqualTo: widget.listingId)
            .limit(100)
            .snapshots()
        : const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    _reviewsByExpertStream = widget.expertId.isNotEmpty
        ? FirebaseFirestore.instance
            .collection('reviews')
            .where('expertId', isEqualTo: widget.expertId)
            .limit(100)
            .snapshots()
        : const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    _volunteerStream = FirebaseFirestore.instance
        .collection('community_requests')
        .where('volunteerId', isEqualTo: widget.expertId)
        .where('status', isEqualTo: 'completed')
        .limit(50)
        .snapshots();
  }

  void _armSupervisor() {
    _supervisorTimer?.cancel();
    _supervisorTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      if (_lastReviewByListingSnap != null ||
          _lastReviewByExpertSnap != null ||
          _lastVolSnap != null) {
        return;
      }
      setState(() => _supervisorFired = true);
    });
  }

  @override
  void dispose() {
    _supervisorTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isProvider = currentUid == widget.expertId;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      key: ValueKey('reviews_${widget.refreshKey}_$_streamsKey'),
      stream: _reviewsByListingStream,
      builder: (context, byListingSnap) {
        if (byListingSnap.hasData) {
          _lastReviewByListingSnap = byListingSnap.data;
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _reviewsByExpertStream,
          builder: (context, byExpertSnap) {
            if (byExpertSnap.hasData) {
              _lastReviewByExpertSnap = byExpertSnap.data;
            }
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _volunteerStream,
              builder: (context, volSnap) {
                if (volSnap.hasData) _lastVolSnap = volSnap.data;
                // Use the most-recent successful snapshots — prevents
                // flash-to-empty during transient re-emits.
                final activeByListing =
                    byListingSnap.data ?? _lastReviewByListingSnap;
                final activeByExpert =
                    byExpertSnap.data ?? _lastReviewByExpertSnap;
                final activeVolData = volSnap.data ?? _lastVolSnap;
                if (byListingSnap.hasError &&
                    byExpertSnap.hasError &&
                    volSnap.hasError) {
                  return const SizedBox.shrink();
                }
                // Spinner ONLY during the supervisor's grace period AND
                // before any stream has delivered any data. After 6s
                // (supervisor fires), fall through to the empty-state
                // copy so the user never gets stuck on a spinner.
                if (activeByListing == null &&
                    activeByExpert == null &&
                    activeVolData == null &&
                    !_supervisorFired) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final items = _buildItems(
                  activeByListing,
                  activeByExpert,
                  activeVolData,
                  context,
                );
                final aggregate = _Aggregate.compute(items);

            final filtered = _searchQuery.isEmpty
                ? items
                : items.where((item) {
                    final comment = (item['comment'] ??
                            item['publicComment'] ??
                            '')
                        .toString()
                        .toLowerCase();
                    final name = (item['reviewerName'] ?? '')
                        .toString()
                        .toLowerCase();
                    final response = (item['providerResponse'] ?? '')
                        .toString()
                        .toLowerCase();
                    final thankYou = (item['thankYouNote'] ?? '')
                        .toString()
                        .toLowerCase();
                    final q = _searchQuery.toLowerCase();
                    return comment.contains(q) ||
                        name.contains(q) ||
                        response.contains(q) ||
                        thankYou.contains(q);
                  }).toList();

            final visible = _expanded
                ? filtered
                : filtered.take(_pageSize).toList();
            final hasMore = filtered.length > _pageSize && !_expanded;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (aggregate.total > 0) ...[
                  _TrustHeader(
                    total: aggregate.total,
                    avgOverall: aggregate.avgOverall,
                  ),
                  const SizedBox(height: 16),
                  if (aggregate.paramCount > 0) ...[
                    _RatingBar(
                      label: l10n.expRatingProfessional,
                      value: aggregate.avgProfessional,
                    ),
                    const SizedBox(height: 8),
                    _RatingBar(
                      label: l10n.expRatingTiming,
                      value: aggregate.avgTiming,
                    ),
                    const SizedBox(height: 8),
                    _RatingBar(
                      label: l10n.expRatingCommunication,
                      value: aggregate.avgComm,
                    ),
                    const SizedBox(height: 16),
                  ],
                  Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F7F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      textAlign: TextAlign.start,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: l10n.expSearchReviewsHint,
                        hintStyle: TextStyle(
                            color: Colors.grey[400], fontSize: 13),
                        prefixIcon: Icon(Icons.search_rounded,
                            size: 18, color: Colors.grey[400]),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onChanged: (v) => setState(() {
                        _searchQuery = v;
                        _expanded = false;
                      }),
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(),
                      Text(l10n.expReviewsTitle,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        _searchQuery.isNotEmpty
                            ? l10n.expNoReviewsMatch(_searchQuery)
                            : l10n.expertNoReviews,
                        style: const TextStyle(
                            color: Color(0xFF9CA3AF), fontSize: 14),
                      ),
                    ),
                  )
                else ...[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final useGrid = constraints.maxWidth >= 560;
                      if (useGrid) {
                        final rows = <Widget>[];
                        for (int i = 0; i < visible.length; i += 2) {
                          rows.add(IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                    child: ReviewCard(
                                  data: visible[i],
                                  isProvider: isProvider,
                                  onReplySent: widget.onReplySent,
                                )),
                                const SizedBox(width: 12),
                                if (i + 1 < visible.length)
                                  Expanded(
                                      child: ReviewCard(
                                    data: visible[i + 1],
                                    isProvider: isProvider,
                                    onReplySent: widget.onReplySent,
                                  ))
                                else
                                  const Expanded(child: SizedBox()),
                              ],
                            ),
                          ));
                          if (i + 2 < visible.length) {
                            rows.add(const SizedBox(height: 12));
                          }
                        }
                        return Column(children: rows);
                      }
                      return Column(
                        children: visible
                            .map((item) => Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 12),
                                  child: ReviewCard(
                                    data: item,
                                    isProvider: isProvider,
                                    onReplySent: widget.onReplySent,
                                  ),
                                ))
                            .toList(),
                      );
                    },
                  ),
                  if (hasMore)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => setState(() => _expanded = true),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1A1A2E),
                            side: const BorderSide(
                                color: Color(0xFF1A1A2E)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(
                            l10n.expShowAllReviews(filtered.length),
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            );
              },
            );
          },
        );
      },
    );
  }

  /// Build the unified review items list from paid reviews + volunteer
  /// reviews. Volunteer reviews come from `community_requests` and are
  /// hardcoded to 5-star (the definition of a volunteer thank-you).
  ///
  /// 2026-05-15: UNION over byListing + byExpert snapshots — dedupe by
  /// docId so a review that satisfies BOTH queries doesn't double-count.
  List<Map<String, dynamic>> _buildItems(
    QuerySnapshot<Map<String, dynamic>>? byListingSnap,
    QuerySnapshot<Map<String, dynamic>>? byExpertSnap,
    QuerySnapshot<Map<String, dynamic>>? volSnap,
    BuildContext context,
  ) {
    final items = <Map<String, dynamic>>[];
    final seenIds = <String>{};
    void addReviewSnap(QuerySnapshot<Map<String, dynamic>>? snap) {
      if (snap == null) return;
      for (final doc in snap.docs) {
        if (!seenIds.add(doc.id)) continue; // already added from the other stream
        final d = doc.data();
        final published = d['isPublished'];
        if (published != null && published != true) continue;
        items.add({...d, '_docId': doc.id, '_isVolunteer': false});
      }
    }
    addReviewSnap(byListingSnap);
    addReviewSnap(byExpertSnap);
    if (volSnap != null) {
      for (final doc in volSnap.docs) {
        final d = doc.data();
        final review = d['volunteerReview'] as String? ?? '';
        if (review.isEmpty) continue;
        final photoUrl = d['completionPhotoUrl'] as String? ?? '';
        items.add({
          'reviewerName': d['requesterName'] as String? ??
              AppLocalizations.of(context).expAnonymous,
          'reviewerId': d['requesterId'] as String?,
          'reviewerImage': d['requesterImage'] as String?,
          'comment': review,
          'rating': 5.0,
          'timestamp': d['completedAt'],
          'createdAt': d['completedAt'],
          'providerResponse': null,
          'reviewPhotos': photoUrl.isNotEmpty ? [photoUrl] : null,
          'thankYouNote': d['thankYouNote'] as String?,
          '_docId': doc.id,
          '_isVolunteer': true,
        });
      }
    }
    items.sort((a, b) {
      final aTs = (a['timestamp'] ?? a['createdAt']) as Timestamp?;
      final bTs = (b['timestamp'] ?? b['createdAt']) as Timestamp?;
      if (aTs == null || bTs == null) return 0;
      return bTs.compareTo(aTs);
    });
    return items;
  }
}

class _Aggregate {
  const _Aggregate({
    required this.total,
    required this.paramCount,
    required this.avgOverall,
    required this.avgProfessional,
    required this.avgTiming,
    required this.avgComm,
  });

  final int total;
  final int paramCount;
  final double avgOverall;
  final double avgProfessional;
  final double avgTiming;
  final double avgComm;

  static _Aggregate compute(List<Map<String, dynamic>> items) {
    double avgOverall = 0, avgProfessional = 0, avgTiming = 0, avgComm = 0;
    int paramCount = 0;
    for (final item in items) {
      final params = item['ratingParams'] as Map<String, dynamic>?;
      if (params != null && params.isNotEmpty) {
        avgProfessional += (params['professional'] as num? ?? 0).toDouble();
        avgTiming += (params['timing'] as num? ?? 0).toDouble();
        avgComm += (params['communication'] as num? ?? 0).toDouble();
        paramCount++;
      }
      avgOverall +=
          (item['rating'] as num? ?? item['overallRating'] as num? ?? 0)
              .toDouble();
    }
    final total = items.length;
    if (total > 0) avgOverall /= total;
    if (paramCount > 0) {
      avgProfessional /= paramCount;
      avgTiming /= paramCount;
      avgComm /= paramCount;
    }
    return _Aggregate(
      total: total,
      paramCount: paramCount,
      avgOverall: avgOverall,
      avgProfessional: avgProfessional,
      avgTiming: avgTiming,
      avgComm: avgComm,
    );
  }
}

class _TrustHeader extends StatelessWidget {
  const _TrustHeader({required this.total, required this.avgOverall});

  final int total;
  final double avgOverall;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '$total ביקורות',
          style:
              const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
        ),
        Row(
          children: [
            Text(
              avgOverall.toStringAsFixed(2),
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E),
                height: 1,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.star_rounded,
                color: ExpertProfileTokens.gold, size: 28),
          ],
        ),
      ],
    );
  }
}

class _RatingBar extends StatelessWidget {
  const _RatingBar({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final fraction = (value / 5.0).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(value.toStringAsFixed(1),
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151))),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Stack(
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(3)),
              ),
              FractionallySizedBox(
                widthFactor: fraction,
                child: Container(
                  height: 6,
                  decoration: const BoxDecoration(
                    color: ExpertProfileTokens.gold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: Color(0xFF6B7280))),
      ],
    );
  }
}

/// Single review card (Airbnb-style, volunteer-aware).
///
/// Used by [ReviewsSection]. Exposed publicly because demo / preview
/// flows might want to render a single sample card.
class ReviewCard extends StatelessWidget {
  const ReviewCard({
    super.key,
    required this.data,
    required this.isProvider,
    required this.onReplySent,
  });

  final Map<String, dynamic> data;
  final bool isProvider;
  final VoidCallback onReplySent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isVolunteer = data['_isVolunteer'] as bool? ?? false;
    final docId = data['_docId'] as String? ?? '';
    final rating =
        (data['rating'] as num? ?? data['overallRating'] as num? ?? 5)
            .toDouble();
    final name = data['reviewerName'] as String? ?? l10n.expertDefaultReviewer;
    final comment = (data['comment'] ?? data['publicComment'] ?? '')
        .toString()
        .trim();
    final ts = (data['timestamp'] ?? data['createdAt']) as Timestamp?;
    final date =
        ts != null ? DateFormat('MMM yyyy', 'he').format(ts.toDate()) : '';
    final response = data['providerResponse'] as String?;
    final reviewerImage = data['reviewerImage'] as String?;
    final reviewerId = data['reviewerId'] as String?;
    final thankYou = data['thankYouNote'] as String?;
    final photos = (data['reviewPhotos'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .where((url) => url.isNotEmpty)
        .toList();
    final imgProvider = safeImageProvider(reviewerImage);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isVolunteer ? const Color(0xFFFFFBEB) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isVolunteer
              ? ExpertProfileTokens.gold.withValues(alpha: 0.3)
              : const Color(0xFFF3F4F6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isVolunteer) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFD4AF37), Color(0xFFB8860B)],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.favorite_rounded,
                      color: Colors.white, size: 11),
                  const SizedBox(width: 3),
                  Text(
                    l10n.expCommunityVolunteerBadge,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                        5,
                        (i) => Icon(
                              i < rating.round()
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              color: ExpertProfileTokens.gold,
                              size: 14,
                            )),
                  ),
                  if (date.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(date,
                        style: const TextStyle(
                            color: Color(0xFF9CA3AF), fontSize: 11)),
                  ],
                ],
              ),
              const Spacer(),
              if (isVolunteer)
                const Padding(
                  padding: EdgeInsetsDirectional.only(end: 4),
                  child: Icon(Icons.favorite_rounded,
                      color: ExpertProfileTokens.gold, size: 14),
                ),
              Text(name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFF1A1A2E))),
              const SizedBox(width: 8),
              imgProvider != null
                  ? CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFFE5E7EB),
                      backgroundImage: imgProvider,
                    )
                  : (reviewerId != null && reviewerId.isNotEmpty)
                      ? FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance
                              .collection('users')
                              .doc(reviewerId)
                              .get(),
                          builder: (_, snap) {
                            if (snap.hasData && snap.data!.exists) {
                              final userData = snap.data!.data()
                                      as Map<String, dynamic>? ??
                                  {};
                              final fetchedImg = safeImageProvider(
                                  userData['profileImage'] as String?);
                              if (fetchedImg != null) {
                                return CircleAvatar(
                                  radius: 18,
                                  backgroundColor:
                                      const Color(0xFFE5E7EB),
                                  backgroundImage: fetchedImg,
                                );
                              }
                            }
                            return _InitialsAvatar(name: name);
                          },
                        )
                      : _InitialsAvatar(name: name),
            ],
          ),
          const SizedBox(height: 10),
          if (comment.isNotEmpty)
            Text(comment,
                textAlign: TextAlign.start,
                style: TextStyle(
                    fontSize: 13.5, height: 1.55, color: Colors.grey[700])),
          if (isVolunteer && thankYou != null && thankYou.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: ExpertProfileTokens.gold.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.format_quote_rounded,
                      size: 14, color: ExpertProfileTokens.gold),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(thankYou,
                        textAlign: TextAlign.start,
                        style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey[700])),
                  ),
                ],
              ),
            ),
          ],
          if (photos != null && photos.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) => GestureDetector(
                  onTap: () => ReviewPhotoViewer.show(ctx, photos, i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      photos[i],
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 72,
                        height: 72,
                        color: const Color(0xFFE5E7EB),
                        child: const Icon(Icons.broken_image_rounded,
                            color: Color(0xFF9CA3AF), size: 20),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (!isVolunteer && response != null && response.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(l10n.expertProviderResponse,
                          style: const TextStyle(
                              color: Color(0xFF374151),
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(width: 4),
                      const Icon(Icons.subdirectory_arrow_left_rounded,
                          size: 14, color: Color(0xFF9CA3AF)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(response,
                      textAlign: TextAlign.start,
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: Colors.grey[600])),
                ],
              ),
            ),
          ] else if (!isVolunteer && isProvider && docId.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: ExpertProfileTokens.purple,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2)),
                icon: const Icon(Icons.reply_rounded, size: 15),
                label: Text(l10n.expertAddReply,
                    style: const TextStyle(fontSize: 12)),
                onPressed: () => ProviderReplyDialog.show(
                  context,
                  reviewDocId: docId,
                  onReplySent: onReplySent,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Initials-only fallback avatar for reviewers without a profile image.
class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: const Color(0xFFE5E7EB),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF374151),
            fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Provider reply bottom-sheet. Writes `providerResponse` directly to
/// the review doc, then calls [onReplySent] so the parent screen can
/// bump its refresh trigger.
class ProviderReplyDialog {
  ProviderReplyDialog._();

  static void show(
    BuildContext context, {
    required String reviewDocId,
    required VoidCallback onReplySent,
  }) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(10))),
                ),
                const SizedBox(height: 16),
                Text(l10n.expertAddReplyTitle,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  maxLines: 4,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    hintText: l10n.expertReplyHint,
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: ExpertProfileTokens.purple, width: 1.5)),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: ExpertProfileTokens.purple,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0),
                  onPressed: () async {
                    final text = ctrl.text.trim();
                    if (text.isEmpty) return;
                    final replyErrorText = l10n.expertReplyError;
                    try {
                      await FirebaseFirestore.instance
                          .collection('reviews')
                          .doc(reviewDocId)
                          .update({'providerResponse': text});
                      if (ctx.mounted) Navigator.pop(ctx);
                      onReplySent();
                    } catch (_) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                          backgroundColor: Colors.red,
                          content: Text(replyErrorText),
                        ));
                      }
                    }
                  },
                  child: Text(l10n.expertPublishReply,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() => ctrl.dispose());
  }
}
