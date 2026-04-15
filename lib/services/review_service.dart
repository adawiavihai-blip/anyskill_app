// ignore_for_file: use_build_context_synchronously
import 'package:cloud_firestore/cloud_firestore.dart';

class ReviewService {
  ReviewService._();
  static final _db = FirebaseFirestore.instance;

  /// Submit a new double-blind review.
  /// isClientReview=true means the customer is reviewing the expert.
  /// v10.1.0: [listingId] ties the review to a specific professional identity.
  /// v14.2.0: [sourceCollection] (default 'jobs') lets AnyTasks reuse the
  /// same Airbnb-style flow — pass 'any_tasks' and jobId holds the taskId.
  /// [reviewTags] (v14.2.0) stores quick tag chips on the review doc.
  static Future<void> submitReview({
    required String jobId,
    required String reviewerId,
    required String reviewerName,
    required String revieweeId,
    required bool isClientReview,
    required Map<String, double> ratingParams,
    required String publicComment,
    required String privateAdminComment,
    String sourceCollection = 'jobs',
    String? listingId,
    String? reviewerImage,
    List<String>? reviewPhotos,
    List<String>? reviewTags,
  }) async {
    final double overall = ratingParams.isEmpty
        ? 0
        : ratingParams.values.fold(0.0, (a, b) => a + b) / ratingParams.length;

    // If no listingId provided, try to resolve from the source doc (jobs only —
    // any_tasks doesn't have listingId).
    String? resolvedListingId = listingId;
    if (resolvedListingId == null && sourceCollection == 'jobs') {
      try {
        final jobSnap = await _db.collection('jobs').doc(jobId).get();
        resolvedListingId = (jobSnap.data() ?? {})['listingId'] as String?;
      } catch (_) {}
    }

    // 1. Write review (unpublished)
    try {
      await _db.collection('reviews').add({
        'jobId':               jobId,
        'sourceCollection':    sourceCollection, // v14.2.0
        'reviewerId':          reviewerId,
        'reviewerName':        reviewerName,
        'revieweeId':          revieweeId,
        'expertId':            revieweeId, // backward-compat alias
        'isClientReview':      isClientReview,
        'ratingParams':        ratingParams,
        'overallRating':       overall,
        'rating':              double.parse(overall.toStringAsFixed(1)), // legacy alias
        'publicComment':       publicComment,
        'comment':             publicComment, // legacy alias
        'privateAdminComment': privateAdminComment,
        'isPublished':         false,
        if (resolvedListingId != null) 'listingId': resolvedListingId,
        if (reviewerImage != null) 'reviewerImage': reviewerImage,
        if (reviewPhotos != null && reviewPhotos.isNotEmpty) 'reviewPhotos': reviewPhotos,
        if (reviewTags != null && reviewTags.isNotEmpty) 'reviewTags': reviewTags,
        'createdAt':           FieldValue.serverTimestamp(),
        'timestamp':           FieldValue.serverTimestamp(), // legacy alias
      });
    } catch (e) {
      throw Exception('שגיאה בשמירת חוות הדעת: $e');
    }

    // 2. Mark this side as done on the source doc (jobs or any_tasks)
    final jobField = isClientReview ? 'clientReviewDone' : 'providerReviewDone';
    try {
      await _db.collection(sourceCollection).doc(jobId).update({
        jobField: true,
      });
    } catch (e) {
      // Review was saved in step 1 — flag update failure is non-fatal.
      // _checkAndPublish will still work when the OTHER side submits.
      // Log but don't throw so the user sees success.
      // ignore: avoid_print
      print('[ReviewService] Job flag update failed (non-fatal): $e');
    }

    // 3. Check if both sides are done — if so, publish both reviews immediately
    try {
      await _checkAndPublish(jobId, revieweeId, sourceCollection);
    } catch (e) {
      // Publish will be retried by lazyPublish (7-day fallback).
      // ignore: avoid_print
      print('[ReviewService] Auto-publish failed (non-fatal): $e');
    }
  }

  /// Checks source doc — if both sides reviewed, publishes all reviews for it.
  static Future<void> _checkAndPublish(
      String jobId, String revieweeId, String sourceCollection) async {
    final jobSnap = await _db.collection(sourceCollection).doc(jobId).get();
    if (!jobSnap.exists) return;
    final job = jobSnap.data() ?? {};
    final clientDone   = job['clientReviewDone']   == true;
    final providerDone = job['providerReviewDone'] == true;

    if (clientDone && providerDone) {
      // Always recalculate using the source's expertId, not revieweeId.
      // When the provider submits last, revieweeId is the customerId —
      // passing that to _recalcExpertRating would update the wrong user's rating.
      final expertId = (job['expertId'] as String?) ??
          (job['selectedProviderId'] as String?) ??
          revieweeId;
      await _publishJobReviews(jobId, expertId, sourceCollection);
    }
  }

  /// Publishes all reviews for a job AND updates both the expert's and
  /// the customer's aggregate ratings.
  /// v10.5.0: Also recalculates the per-listing rating so each identity
  /// has its own independent rating/reviewsCount.
  /// v11.9.0: Idempotent — if both sides call simultaneously, the second
  /// call finds zero unpublished reviews and exits early. Rating recalcs
  /// are also idempotent (read-then-write of the same aggregate).
  static Future<void> _publishJobReviews(
      String jobId, String expertId, String sourceCollection) async {
    final jobSnap = await _db.collection(sourceCollection).doc(jobId).get();
    final jobData = jobSnap.data() ?? {};
    final customerId = (jobData['customerId'] as String?) ??
        (jobData['clientId'] as String?) ??
        '';
    final listingId = jobData['listingId'] as String?;

    final snap = await _db
        .collection('reviews')
        .where('jobId', isEqualTo: jobId)
        .where('isPublished', isEqualTo: false)
        .get();

    // Idempotency: if another call already published, exit silently.
    if (snap.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'isPublished': true});
    }
    try {
      await batch.commit();
    } catch (e) {
      // If batch fails (e.g., already published by race), log and exit.
      // Ratings will be recalculated next time lazyPublish runs.
      // ignore: avoid_print
      print('[ReviewService] Publish batch failed (may be race): $e');
      return;
    }

    // Update ratings in parallel: user doc (global) + listing doc (per-identity).
    // Each recalc is idempotent — reads ALL published reviews, recomputes average.
    try {
      await Future.wait([
        _recalcExpertRating(expertId),
        if (customerId.isNotEmpty) _recalcCustomerRating(customerId),
        if (listingId != null) _recalcListingRating(listingId),
      ]);
    } catch (e) {
      // Rating recalc failure is non-fatal — will be corrected on next profile view.
      // ignore: avoid_print
      print('[ReviewService] Rating recalc failed (non-fatal): $e');
    }
  }

  /// Recalculates the expert's aggregate rating from all published client reviews.
  static Future<void> _recalcExpertRating(String expertId) async {
    if (expertId.isEmpty) return;
    final snap = await _db
        .collection('reviews')
        .where('revieweeId', isEqualTo: expertId)
        .where('isClientReview', isEqualTo: true)
        .where('isPublished', isEqualTo: true)
        .limit(100)
        .get();

    if (snap.docs.isEmpty) return;

    double totalRating = 0;
    int count = 0;
    for (final doc in snap.docs) {
      final d = doc.data();
      final r = (d['overallRating'] as num?)?.toDouble()
          ?? (d['rating'] as num?)?.toDouble()
          ?? 0;
      if (r > 0) {
        totalRating += r;
        count++;
      }
    }
    if (count == 0) return;
    final avg = double.parse((totalRating / count).toStringAsFixed(1));

    await _db.collection('users').doc(expertId).update({
      'rating':       avg,
      'reviewsCount': count,
    });
  }

  /// Recalculates the customer's aggregate rating from all published expert reviews.
  static Future<void> _recalcCustomerRating(String customerId) async {
    if (customerId.isEmpty) return;
    final snap = await _db
        .collection('reviews')
        .where('revieweeId', isEqualTo: customerId)
        .where('isClientReview', isEqualTo: false)
        .where('isPublished', isEqualTo: true)
        .limit(100)
        .get();

    if (snap.docs.isEmpty) return;

    double totalRating = 0;
    int count = 0;
    for (final doc in snap.docs) {
      final d = doc.data();
      final r = (d['overallRating'] as num?)?.toDouble()
          ?? (d['rating'] as num?)?.toDouble()
          ?? 0;
      if (r > 0) {
        totalRating += r;
        count++;
      }
    }
    if (count == 0) return;
    final avg = double.parse((totalRating / count).toStringAsFixed(1));

    await _db.collection('users').doc(customerId).update({
      'customerRating':       avg,
      'customerReviewsCount': count,
    });
  }

  /// v10.5.0: Recalculates rating/reviewsCount on a specific provider_listing doc.
  /// Only counts published client reviews that have this listingId.
  static Future<void> _recalcListingRating(String listingId) async {
    if (listingId.isEmpty) return;
    final snap = await _db
        .collection('reviews')
        .where('listingId', isEqualTo: listingId)
        .where('isClientReview', isEqualTo: true)
        .where('isPublished', isEqualTo: true)
        .limit(100)
        .get();

    double totalRating = 0;
    int count = 0;
    for (final doc in snap.docs) {
      final d = doc.data();
      final r = (d['overallRating'] as num?)?.toDouble()
          ?? (d['rating'] as num?)?.toDouble()
          ?? 0;
      if (r > 0) {
        totalRating += r;
        count++;
      }
    }

    final avg = count > 0
        ? double.parse((totalRating / count).toStringAsFixed(1))
        : 5.0; // Default rating for new identities with no reviews

    await _db.collection('provider_listings').doc(listingId).update({
      'rating':       avg,
      'reviewsCount': count,
    });
  }

  /// Stream of reviews for an expert (filter isPublished client-side to avoid composite index).
  static Stream<QuerySnapshot> streamPublishedReviews(String expertId) {
    return _db
        .collection('reviews')
        .where('revieweeId', isEqualTo: expertId)
        .limit(30)
        .snapshots();
  }

  /// Stream of expert-written reviews for a customer.
  static Stream<QuerySnapshot> streamCustomerReviews(String customerId) {
    return _db
        .collection('reviews')
        .where('revieweeId', isEqualTo: customerId)
        .where('isClientReview', isEqualTo: false)
        .limit(20)
        .snapshots();
  }

  /// Returns true if the current user has already reviewed this job.
  static Future<bool> hasReviewed({
    required String jobId,
    required String reviewerId,
  }) async {
    final snap = await _db
        .collection('reviews')
        .where('jobId', isEqualTo: jobId)
        .where('reviewerId', isEqualTo: reviewerId)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  /// Lazy auto-publish: checks if any review for this job is older than 7 days
  /// and not yet published. Called when reviews are displayed.
  static Future<void> lazyPublish(
      String jobId, String expertId, String customerId) async {
    if (jobId.isEmpty) return;
    final cutoff =
        Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 7)));
    final snap = await _db
        .collection('reviews')
        .where('jobId', isEqualTo: jobId)
        .where('isPublished', isEqualTo: false)
        .get();

    final toPublish = snap.docs.where((doc) {
      final ts = doc.data()['createdAt'] as Timestamp?;
      return ts != null && ts.compareTo(cutoff) <= 0;
    }).toList();

    if (toPublish.isEmpty) return;

    final batch = _db.batch();
    for (final doc in toPublish) {
      batch.update(doc.reference, {'isPublished': true});
    }
    await batch.commit();
    await Future.wait([
      _recalcExpertRating(expertId),
      if (customerId.isNotEmpty) _recalcCustomerRating(customerId),
    ]);
  }
}
