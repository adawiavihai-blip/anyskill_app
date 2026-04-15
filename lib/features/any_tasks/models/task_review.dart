/// AnySkill — TaskReview Model (AnyTasks v14.0.0)
///
/// Lives at `any_tasks/{taskId}/reviews/{reviewId}`. Simpler than the
/// main `reviews` collection (Section 5 of CLAUDE.md) — AnyTasks is
/// micro-task transactional, so we skip the double-blind mechanic and
/// store a single 1–5 star rating + short comment. Client rates provider
/// at completion time.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

class TaskReview {
  final String? id;
  final String taskId;
  final String reviewerId;    // always the client
  final String revieweeId;    // always the provider
  final int rating;           // 1–5
  final String comment;       // max 500
  final DateTime? createdAt;

  const TaskReview({
    this.id,
    required this.taskId,
    required this.reviewerId,
    required this.revieweeId,
    required this.rating,
    this.comment = '',
    this.createdAt,
  });

  factory TaskReview.fromMap(String id, Map<String, dynamic> d) => TaskReview(
        id: id,
        taskId: (d['taskId'] ?? '') as String,
        reviewerId: (d['reviewerId'] ?? '') as String,
        revieweeId: (d['revieweeId'] ?? '') as String,
        rating: (d['rating'] as num?)?.toInt() ?? 0,
        comment: (d['comment'] ?? '') as String,
        createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toMap() => {
        'taskId': taskId,
        'reviewerId': reviewerId,
        'revieweeId': revieweeId,
        'rating': rating,
        'comment': comment,
      };
}
