/// AnySkill — TaskResponse Model (AnyTasks v14.0.0)
///
/// Provider's response to a published task. Two types:
///   • 'accept'        — provider accepts at listed price, one tap
///   • 'counter_offer' — provider suggests different price + message
///
/// Lives at `any_tasks/{taskId}/responses/{responseId}` (subcollection).
/// Subcollection keeps security rules simple (inherit participant check
/// from parent task via `get(/any_tasks/$(taskId))`).
library;

import 'package:cloud_firestore/cloud_firestore.dart';

class TaskResponse {
  final String? id;
  final String taskId;
  final String providerId;
  final String providerName;
  final String? providerImage;

  /// 'accept' | 'counter_offer'
  final String responseType;

  /// Null for 'accept' (= task's listed budget). Required for counter_offer.
  final int? offeredPriceNis;

  /// Optional message. Required for counter_offer (spec: "Why is this price fair").
  final String message;

  /// Denormalized provider stats for the comparison screen.
  final double providerRating;
  final int providerCompletedCount;
  final double? distanceKm;

  /// 'pending' | 'chosen' | 'rejected'
  final String status;

  final DateTime? createdAt;
  final DateTime? expiresAt; // 24h for counter_offers

  const TaskResponse({
    this.id,
    required this.taskId,
    required this.providerId,
    required this.providerName,
    this.providerImage,
    required this.responseType,
    this.offeredPriceNis,
    this.message = '',
    this.providerRating = 0.0,
    this.providerCompletedCount = 0,
    this.distanceKm,
    this.status = 'pending',
    this.createdAt,
    this.expiresAt,
  });

  factory TaskResponse.fromMap(String id, Map<String, dynamic> d) => TaskResponse(
        id: id,
        taskId: (d['taskId'] ?? '') as String,
        providerId: (d['providerId'] ?? '') as String,
        providerName: (d['providerName'] ?? '') as String,
        providerImage: d['providerImage'] as String?,
        responseType: (d['responseType'] ?? 'accept') as String,
        offeredPriceNis: (d['offeredPriceNis'] as num?)?.toInt(),
        message: (d['message'] ?? '') as String,
        providerRating: (d['providerRating'] as num?)?.toDouble() ?? 0.0,
        providerCompletedCount:
            (d['providerCompletedCount'] as num?)?.toInt() ?? 0,
        distanceKm: (d['distanceKm'] as num?)?.toDouble(),
        status: (d['status'] ?? 'pending') as String,
        createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
        expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toMap() => {
        'taskId': taskId,
        'providerId': providerId,
        'providerName': providerName,
        if (providerImage != null) 'providerImage': providerImage,
        'responseType': responseType,
        if (offeredPriceNis != null) 'offeredPriceNis': offeredPriceNis,
        'message': message,
        'providerRating': providerRating,
        'providerCompletedCount': providerCompletedCount,
        if (distanceKm != null) 'distanceKm': distanceKm,
        'status': status,
        if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt!),
      };
}
