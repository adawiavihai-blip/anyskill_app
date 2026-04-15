/// AnyTasks 3.0 — Dart model for the `anytasks/{taskId}` Firestore document.
///
/// Provides type-safe access to all task fields with null-safe defaults.
/// Use [AnyTask.fromFirestore] to parse a DocumentSnapshot and [toMap] to
/// serialize back for writes.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

/// All possible statuses for an AnyTask document.
///
/// Transitions:
/// ```
/// open → claimed → in_progress → proof_submitted → completed
///                                                 → disputed → resolved
///      → expired (no claim within TTL)
///      → cancelled (by creator or provider)
/// ```
class AnyTaskStatus {
  AnyTaskStatus._();

  static const String open             = 'open';
  static const String claimed          = 'claimed';
  static const String inProgress       = 'in_progress';
  static const String proofSubmitted   = 'proof_submitted';
  static const String completed        = 'completed';
  static const String cancelled        = 'cancelled';
  static const String disputed         = 'disputed';
  static const String resolved         = 'resolved';
  static const String expired          = 'expired';

  /// Statuses that represent an active (non-terminal) task.
  static const Set<String> active = {
    open, claimed, inProgress, proofSubmitted, disputed,
  };

  /// Terminal statuses (task is done — no further transitions).
  static const Set<String> terminal = {
    completed, cancelled, resolved, expired,
  };
}

class AnyTask {
  // ── Identity ───────────────────────────────────────────────────────────
  final String id;
  final String creatorId;
  final String creatorName;
  final String? creatorImage;

  // ── Task Definition ────────────────────────────────────────────────────
  final String title;
  final String description;
  final String category;
  final String? subcategory;
  final double amount;
  final String currency;
  final GeoPoint? location;
  final String? locationText;
  final bool requiresPhysical;
  final DateTime? deadline;
  final String proofType; // 'photo' | 'text' | 'both'

  // ── Assignment ─────────────────────────────────────────────────────────
  final String? providerId;
  final String? providerName;
  final String? providerImage;
  final String status;
  final DateTime? claimedAt;
  final String? chatRoomId;

  // ── Escrow & Payment ───────────────────────────────────────────────────
  final double commission;
  final double netToProvider;
  final String? jobId;

  // ── Proof & Completion ─────────────────────────────────────────────────
  final String? proofText;
  final String? proofPhotoUrl;
  final DateTime? proofUploadedAt;
  final DateTime? autoReleaseDate;
  final bool autoReleased;
  final DateTime? completedAt;
  final bool confirmedByCreator;

  // ── Cancellation ───────────────────────────────────────────────────────
  final DateTime? cancelledAt;
  final String? cancelledBy; // 'creator' | 'provider' | 'system'
  final String? cancellationReason;

  // ── Anti-Fraud ─────────────────────────────────────────────────────────
  final String? creatorDeviceId;

  // ── Dispute ────────────────────────────────────────────────────────────
  final DateTime? disputedAt;
  final String? disputeReason;
  final String? disputeResolution;

  // ── Metadata ───────────────────────────────────────────────────────────
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int viewCount;
  final bool isUrgent;
  final String source;

  const AnyTask({
    required this.id,
    required this.creatorId,
    required this.creatorName,
    this.creatorImage,
    required this.title,
    required this.description,
    required this.category,
    this.subcategory,
    required this.amount,
    this.currency = 'ILS',
    this.location,
    this.locationText,
    this.requiresPhysical = false,
    this.deadline,
    this.proofType = 'photo',
    this.providerId,
    this.providerName,
    this.providerImage,
    this.status = AnyTaskStatus.open,
    this.claimedAt,
    this.chatRoomId,
    this.commission = 0,
    this.netToProvider = 0,
    this.jobId,
    this.proofText,
    this.proofPhotoUrl,
    this.proofUploadedAt,
    this.autoReleaseDate,
    this.autoReleased = false,
    this.completedAt,
    this.confirmedByCreator = false,
    this.cancelledAt,
    this.cancelledBy,
    this.cancellationReason,
    this.creatorDeviceId,
    this.disputedAt,
    this.disputeReason,
    this.disputeResolution,
    this.createdAt,
    this.updatedAt,
    this.viewCount = 0,
    this.isUrgent = false,
    this.source = 'app',
  });

  // ── Factory: Firestore → AnyTask ──────────────────────────────────────

  factory AnyTask.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return AnyTask(
      id:                 doc.id,
      creatorId:          d['creatorId'] as String? ?? '',
      creatorName:        d['creatorName'] as String? ?? '',
      creatorImage:       d['creatorImage'] as String?,
      title:              d['title'] as String? ?? '',
      description:        d['description'] as String? ?? '',
      category:           d['category'] as String? ?? '',
      subcategory:        d['subcategory'] as String?,
      amount:             (d['amount'] as num? ?? 0).toDouble(),
      currency:           d['currency'] as String? ?? 'ILS',
      location:           d['location'] as GeoPoint?,
      locationText:       d['locationText'] as String?,
      requiresPhysical:   d['requiresPhysical'] as bool? ?? false,
      deadline:           (d['deadline'] as Timestamp?)?.toDate(),
      proofType:          d['proofType'] as String? ?? 'photo',
      providerId:         d['providerId'] as String?,
      providerName:       d['providerName'] as String?,
      providerImage:      d['providerImage'] as String?,
      status:             d['status'] as String? ?? AnyTaskStatus.open,
      claimedAt:          (d['claimedAt'] as Timestamp?)?.toDate(),
      chatRoomId:         d['chatRoomId'] as String?,
      commission:         (d['commission'] as num? ?? 0).toDouble(),
      netToProvider:      (d['netToProvider'] as num? ?? 0).toDouble(),
      jobId:              d['jobId'] as String?,
      proofText:          d['proofText'] as String?,
      proofPhotoUrl:      d['proofPhotoUrl'] as String?,
      proofUploadedAt:    (d['proofUploadedAt'] as Timestamp?)?.toDate(),
      autoReleaseDate:    (d['autoReleaseDate'] as Timestamp?)?.toDate(),
      autoReleased:       d['autoReleased'] as bool? ?? false,
      completedAt:        (d['completedAt'] as Timestamp?)?.toDate(),
      confirmedByCreator: d['confirmedByCreator'] as bool? ?? false,
      cancelledAt:        (d['cancelledAt'] as Timestamp?)?.toDate(),
      cancelledBy:        d['cancelledBy'] as String?,
      cancellationReason: d['cancellationReason'] as String?,
      creatorDeviceId:    d['creatorDeviceId'] as String?,
      disputedAt:         (d['disputedAt'] as Timestamp?)?.toDate(),
      disputeReason:      d['disputeReason'] as String?,
      disputeResolution:  d['disputeResolution'] as String?,
      createdAt:          (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt:          (d['updatedAt'] as Timestamp?)?.toDate(),
      viewCount:          (d['viewCount'] as num? ?? 0).toInt(),
      isUrgent:           d['isUrgent'] as bool? ?? false,
      source:             d['source'] as String? ?? 'app',
    );
  }

  // ── Serialization: AnyTask → Map (for Firestore writes) ───────────────

  Map<String, dynamic> toMap() => {
    'creatorId':          creatorId,
    'creatorName':        creatorName,
    'creatorImage':       creatorImage,
    'title':              title,
    'description':        description,
    'category':           category,
    'subcategory':        subcategory,
    'amount':             amount,
    'currency':           currency,
    'location':           location,
    'locationText':       locationText,
    'requiresPhysical':   requiresPhysical,
    'deadline':           deadline != null ? Timestamp.fromDate(deadline!) : null,
    'proofType':          proofType,
    'providerId':         providerId,
    'providerName':       providerName,
    'providerImage':      providerImage,
    'status':             status,
    'claimedAt':          claimedAt != null ? Timestamp.fromDate(claimedAt!) : null,
    'chatRoomId':         chatRoomId,
    'commission':         commission,
    'netToProvider':      netToProvider,
    'jobId':              jobId,
    'proofText':          proofText,
    'proofPhotoUrl':      proofPhotoUrl,
    'proofUploadedAt':    proofUploadedAt != null ? Timestamp.fromDate(proofUploadedAt!) : null,
    'autoReleaseDate':    autoReleaseDate != null ? Timestamp.fromDate(autoReleaseDate!) : null,
    'autoReleased':       autoReleased,
    'completedAt':        completedAt != null ? Timestamp.fromDate(completedAt!) : null,
    'confirmedByCreator': confirmedByCreator,
    'cancelledAt':        cancelledAt != null ? Timestamp.fromDate(cancelledAt!) : null,
    'cancelledBy':        cancelledBy,
    'cancellationReason': cancellationReason,
    'creatorDeviceId':    creatorDeviceId,
    'disputedAt':         disputedAt != null ? Timestamp.fromDate(disputedAt!) : null,
    'disputeReason':      disputeReason,
    'disputeResolution':  disputeResolution,
    'viewCount':          viewCount,
    'isUrgent':           isUrgent,
    'source':             source,
  };

  // ── Convenience getters ───────────────────────────────────────────────

  bool get isActive   => AnyTaskStatus.active.contains(status);
  bool get isTerminal => AnyTaskStatus.terminal.contains(status);
  bool get isClaimed  => providerId != null && providerId!.isNotEmpty;
  bool get hasProof   => (proofPhotoUrl != null && proofPhotoUrl!.isNotEmpty) ||
                         (proofText != null && proofText!.isNotEmpty);

  /// Hours remaining until auto-release. Null if not in proof_submitted state.
  double? get hoursUntilAutoRelease {
    if (autoReleaseDate == null) return null;
    final diff = autoReleaseDate!.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return diff.inMinutes / 60.0;
  }
}
