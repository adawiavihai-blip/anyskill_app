// ignore_for_file: use_build_context_synchronously
import 'package:cloud_firestore/cloud_firestore.dart';

class ReviewService {
  ReviewService._();
  static final _db = FirebaseFirestore.instance;

  /// Submit a new double-blind review.
  /// isClientReview=true means the customer is reviewing the expert.
  static Future<void> submitReview({
    required String jobId,
    required String reviewerId,
    required String reviewerName,
    required String revieweeId,
    required bool isClientReview,
    required Map<String, double> ratingParams,
    required String publicComment,
    required String privateAdminComment,
  }) async {
    final double overall = ratingParams.isEmpty
        ? 0
        : ratingParams.values.fold(0.0, (a, b) => a + b) / ratingParams.length;

    // 1. Write review (unpublished)
    await _db.collection('reviews').add({
      'jobId':               jobId,
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
      'createdAt':           FieldValue.serverTimestamp(),
      'timestamp':           FieldValue.serverTimestamp(), // legacy alias
    });

    // 2. Mark this side as done on the job doc
    final jobField = isClientReview ? 'clientReviewDone' : 'providerReviewDone';
    await _db.collection('jobs').doc(jobId).update({
      jobField: true,
    });

    // 3. Check if both sides are done — if so, publish both reviews immediately
    await _checkAndPublish(jobId, revieweeId);
  }

  /// Checks job doc — if both sides reviewed, publishes all reviews for this job.
  static Future<void> _checkAndPublish(String jobId, String revieweeId) async {
    final jobSnap = await _db.collection('jobs').doc(jobId).get();
    if (!jobSnap.exists) return;
    final job = jobSnap.data() ?? {};
    final clientDone   = job['clientReviewDone']   == true;
    final providerDone = job['providerReviewDone'] == true;

    if (clientDone && providerDone) {
      // Always recalculate using the job's expertId, not revieweeId.
      // When the provider submits last, revieweeId is the customerId —
      // passing that to _recalcExpertRating would update the wrong user's rating.
      final expertId = job['expertId'] as String? ?? revieweeId;
      await _publishJobReviews(jobId, expertId);
    }
  }

  /// Publishes all reviews for a job AND updates both the expert's and
  /// the customer's aggregate ratings.
  static Future<void> _publishJobReviews(String jobId, String expertId) async {
    final jobSnap = await _db.collection('jobs').doc(jobId).get();
    final customerId = (jobSnap.data() ?? {})['customerId'] as String? ?? '';

    final snap = await _db
        .collection('reviews')
        .where('jobId', isEqualTo: jobId)
        .where('isPublished', isEqualTo: false)
        .get();

    if (snap.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'isPublished': true});
    }
    await batch.commit();

    // Update both parties' ratings in parallel
    await Future.wait([
      _recalcExpertRating(expertId),
      if (customerId.isNotEmpty) _recalcCustomerRating(customerId),
    ]);
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
