/// AnySkill — AnyTask Model (AnyTasks v14.0.0)
///
/// Root doc at `any_tasks/{taskId}`. Created by the client via the Publish
/// Form; drives the entire 7-stage lifecycle. Payment flows through the
/// internal-credits ledger (mirrors the existing `jobs/{id}` escrow pattern
/// — see Section 4 of CLAUDE.md).
library;

import 'package:cloud_firestore/cloud_firestore.dart';

/// Category enum — mirrors `APP_CATEGORIES` at a high level but stays flat
/// for v1 (no sub-categories). Expand via admin once real demand surfaces.
const List<String> kTaskCategories = [
  'delivery',
  'cleaning',
  'handyman',
  'moving',
  'pet_care',
  'tech_support',
  'tutoring',
  'other',
];

const Map<String, String> kTaskCategoryLabels = {
  'delivery': 'משלוחים',
  'cleaning': 'ניקיון',
  'handyman': 'תיקונים',
  'moving': 'הובלות',
  'pet_care': 'טיפול בחיות',
  'tech_support': 'טכנולוגיה',
  'tutoring': 'שיעורים פרטיים',
  'other': 'אחר',
};

const List<String> kTaskUrgency = ['flexible', 'today', 'urgent_now'];
const Map<String, String> kTaskUrgencyLabels = {
  'flexible': 'גמיש',
  'today': 'היום',
  'urgent_now': 'דחוף עכשיו',
};

const List<String> kTaskProofTypes = ['photo', 'text', 'both'];
const Map<String, String> kTaskProofLabels = {
  'photo': 'תמונה',
  'text': 'טקסט',
  'both': 'תמונה + טקסט',
};

/// Task statuses — mirrors the spec's 7-stage lifecycle.
///   open              → published, collecting offers
///   in_progress       → provider selected, escrow charged, work underway
///   proof_submitted   → provider uploaded proof, awaiting client confirmation
///   completed         → client confirmed, escrow released
///   disputed          → admin intervention (48h SLA)
///   cancelled         → client cancelled pre-selection
///   expired           → no offers within deadline
const List<String> kTaskStatuses = [
  'open',
  'in_progress',
  'proof_submitted',
  'completed',
  'disputed',
  'cancelled',
  'expired',
];

class AnyTask {
  final String? id;

  // ── Ownership ──────────────────────────────────────────────────
  final String clientId;
  final String clientName;

  // ── Core content ───────────────────────────────────────────────
  final String title;            // max 100 chars
  final String description;      // max 2000 chars
  final String category;         // kTaskCategories
  final List<String> aiTags;     // Claude Haiku auto-suggest

  // ── Pricing ────────────────────────────────────────────────────
  final int budgetNis;           // whole NIS, min 10
  final int? agreedPriceNis;     // set when provider chosen (after counter-offer)

  // ── Scheduling ─────────────────────────────────────────────────
  final String urgency;          // kTaskUrgency
  final DateTime? deadline;      // null = flexible

  // ── Location ───────────────────────────────────────────────────
  final GeoPoint? location;
  final String? locationName;    // human-readable (e.g. "רחוב הרצל 12, תל אביב")
  final bool isRemote;

  // ── Proof requirements ─────────────────────────────────────────
  final String proofType;        // kTaskProofTypes
  final String? proofUrl;        // set after provider uploads
  final String? proofText;

  // ── Selection + escrow ─────────────────────────────────────────
  final String? selectedProviderId;
  final String? selectedProviderName;
  final String? escrowTransactionId;
  final int? platformFeeNis;     // computed inside tx (fee * agreed)
  final int? providerPayoutNis;  // agreed - fee

  // ── Status ─────────────────────────────────────────────────────
  final String status;
  final int responseCount;       // denormalized for FOMO badges

  // ── Timestamps ─────────────────────────────────────────────────
  final DateTime? createdAt;
  final DateTime? acceptedAt;    // provider chosen
  final DateTime? proofSubmittedAt;
  final DateTime? completedAt;

  const AnyTask({
    this.id,
    required this.clientId,
    required this.clientName,
    required this.title,
    required this.description,
    required this.category,
    this.aiTags = const [],
    required this.budgetNis,
    this.agreedPriceNis,
    required this.urgency,
    this.deadline,
    this.location,
    this.locationName,
    this.isRemote = false,
    required this.proofType,
    this.proofUrl,
    this.proofText,
    this.selectedProviderId,
    this.selectedProviderName,
    this.escrowTransactionId,
    this.platformFeeNis,
    this.providerPayoutNis,
    this.status = 'open',
    this.responseCount = 0,
    this.createdAt,
    this.acceptedAt,
    this.proofSubmittedAt,
    this.completedAt,
  });

  factory AnyTask.fromMap(String id, Map<String, dynamic> d) => AnyTask(
        id: id,
        clientId: (d['clientId'] ?? '') as String,
        clientName: (d['clientName'] ?? '') as String,
        title: (d['title'] ?? '') as String,
        description: (d['description'] ?? '') as String,
        category: (d['category'] ?? 'other') as String,
        aiTags: List<String>.from(d['aiTags'] ?? const []),
        budgetNis: (d['budgetNis'] as num?)?.toInt() ?? 0,
        agreedPriceNis: (d['agreedPriceNis'] as num?)?.toInt(),
        urgency: (d['urgency'] ?? 'flexible') as String,
        deadline: (d['deadline'] as Timestamp?)?.toDate(),
        location: d['location'] as GeoPoint?,
        locationName: d['locationName'] as String?,
        isRemote: (d['isRemote'] ?? false) as bool,
        proofType: (d['proofType'] ?? 'photo') as String,
        proofUrl: d['proofUrl'] as String?,
        proofText: d['proofText'] as String?,
        selectedProviderId: d['selectedProviderId'] as String?,
        selectedProviderName: d['selectedProviderName'] as String?,
        escrowTransactionId: d['escrowTransactionId'] as String?,
        platformFeeNis: (d['platformFeeNis'] as num?)?.toInt(),
        providerPayoutNis: (d['providerPayoutNis'] as num?)?.toInt(),
        status: (d['status'] ?? 'open') as String,
        responseCount: (d['responseCount'] as num?)?.toInt() ?? 0,
        createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
        acceptedAt: (d['acceptedAt'] as Timestamp?)?.toDate(),
        proofSubmittedAt: (d['proofSubmittedAt'] as Timestamp?)?.toDate(),
        completedAt: (d['completedAt'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toMap() => {
        'clientId': clientId,
        'clientName': clientName,
        'title': title,
        'description': description,
        'category': category,
        'aiTags': aiTags,
        'budgetNis': budgetNis,
        if (agreedPriceNis != null) 'agreedPriceNis': agreedPriceNis,
        'urgency': urgency,
        if (deadline != null) 'deadline': Timestamp.fromDate(deadline!),
        if (location != null) 'location': location,
        if (locationName != null) 'locationName': locationName,
        'isRemote': isRemote,
        'proofType': proofType,
        if (proofUrl != null) 'proofUrl': proofUrl,
        if (proofText != null) 'proofText': proofText,
        if (selectedProviderId != null) 'selectedProviderId': selectedProviderId,
        if (selectedProviderName != null) 'selectedProviderName': selectedProviderName,
        if (escrowTransactionId != null) 'escrowTransactionId': escrowTransactionId,
        if (platformFeeNis != null) 'platformFeeNis': platformFeeNis,
        if (providerPayoutNis != null) 'providerPayoutNis': providerPayoutNis,
        'status': status,
        'responseCount': responseCount,
      };

  /// "You receive: ₪X net" math — used on provider accept buttons.
  /// Callers pass feePercent in [0.0..1.0]. Matches spec section 7.
  static int computeNet(int gross, double feePercent) =>
      (gross - (gross * feePercent).round()).clamp(0, gross);
}
