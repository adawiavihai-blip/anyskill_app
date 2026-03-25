import 'package:cloud_firestore/cloud_firestore.dart';

class ReviewModel {
  final String id;
  final String jobId;
  final String reviewerId;
  final String reviewerName;
  final String revieweeId;
  final bool isClientReview;
  final Map<String, double> ratingParams;
  final double overallRating;
  final String publicComment;
  final String privateAdminComment;
  final bool isPublished;
  final String? traitTags;
  final dynamic createdAt;

  const ReviewModel({
    required this.id,
    required this.jobId,
    required this.reviewerId,
    required this.reviewerName,
    required this.revieweeId,
    required this.isClientReview,
    required this.ratingParams,
    required this.overallRating,
    required this.publicComment,
    required this.privateAdminComment,
    required this.isPublished,
    this.traitTags,
    this.createdAt,
  });

  factory ReviewModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final params = (d['ratingParams'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, (v as num? ?? 3).toDouble()));
    final overall = d['overallRating'] != null
        ? (d['overallRating'] as num).toDouble()
        : params.isEmpty
            ? (d['rating'] as num? ?? 0).toDouble()
            : params.values.fold(0.0, (a, b) => a + b) / params.length;
    return ReviewModel(
      id:                  doc.id,
      jobId:               d['jobId']?.toString()              ?? '',
      reviewerId:          d['reviewerId']?.toString()         ?? '',
      reviewerName:        d['reviewerName']?.toString()       ?? 'משתמש',
      revieweeId:          d['revieweeId']?.toString()         ?? d['expertId']?.toString() ?? '',
      isClientReview:      d['isClientReview'] as bool?        ?? true,
      ratingParams:        params,
      overallRating:       overall,
      publicComment:       d['publicComment']?.toString()      ?? d['comment']?.toString() ?? '',
      privateAdminComment: d['privateAdminComment']?.toString() ?? '',
      isPublished:         d['isPublished'] as bool?           ?? true,
      traitTags:           (d['traitTags'] as List?)?.join(','),
      createdAt:           d['createdAt'] ?? d['timestamp'],
    );
  }
}
