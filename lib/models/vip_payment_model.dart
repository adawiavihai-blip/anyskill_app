import 'package:cloud_firestore/cloud_firestore.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// VIP payment record — Firestore collection `vip_payments/`.
///
/// Created by:
///   - `purchaseVipWithCredits` CF (Phase 5) — provider buys with internal
///     credits.
///   - Phase 6 monthly billing CF — auto-renew charges.
///   - Future Tranzila/PayPlus integration — replace just the charge fn.
///
/// **Money note (CLAUDE.md §2):** `paymentMethod: 'credits'` is the
/// only writer in Phase 5 since Stripe was removed in v11.9.x. When the
/// Israeli payment provider lands, only the charge function flips —
/// the schema (and the admin Payments screen reading it) stays
/// unchanged.
/// ═══════════════════════════════════════════════════════════════════════════

enum VipPaymentStatus {
  paid('paid'),
  pending('pending'),
  failed('failed'),
  refunded('refunded'),
  comp('comp');

  final String dbValue;
  const VipPaymentStatus(this.dbValue);

  static VipPaymentStatus fromDb(String? v) {
    for (final s in values) {
      if (s.dbValue == v) return s;
    }
    return VipPaymentStatus.paid;
  }

  String get hebrewLabel => switch (this) {
        VipPaymentStatus.paid => 'שולם',
        VipPaymentStatus.pending => 'בהמתנה',
        VipPaymentStatus.failed => 'נכשל',
        VipPaymentStatus.refunded => 'הוחזר',
        VipPaymentStatus.comp => 'חינם · מנהל',
      };
}

enum VipRenewalType {
  auto('auto'),
  manual('manual'),
  initial('initial');

  final String dbValue;
  const VipRenewalType(this.dbValue);

  static VipRenewalType fromDb(String? v) {
    for (final t in values) {
      if (t.dbValue == v) return t;
    }
    return VipRenewalType.initial;
  }

  String get hebrewLabel => switch (this) {
        VipRenewalType.auto => 'חידוש אוטו',
        VipRenewalType.manual => 'חידוש ידני',
        VipRenewalType.initial => 'מנוי ראשוני',
      };
}

class VipPayment {
  final String id;
  final String providerId;
  final String subscriptionId;

  /// In credits / ILS (₪1 = 1 credit). Always positive — refunds write a
  /// new doc with status: 'refunded' rather than mutating the original.
  final int amount;

  /// Currency code — always 'ILS' in Phase 5.
  final String currency;

  final VipPaymentStatus status;

  /// Phase 5: always 'credits'. Will become 'visa' / 'mastercard' /
  /// 'amex' once the Israeli payment provider is integrated.
  final String paymentMethod;

  final String? cardLast4;
  final DateTime? paymentDate;
  final String? failureReason;
  final String? invoiceUrl;
  final bool isRenewal;
  final VipRenewalType renewalType;

  // ── Metadata ─────────────────────────────────────────────────────────
  final DateTime? createdAt;

  const VipPayment({
    required this.id,
    required this.providerId,
    required this.subscriptionId,
    required this.amount,
    this.currency = 'ILS',
    this.status = VipPaymentStatus.paid,
    this.paymentMethod = 'credits',
    this.cardLast4,
    this.paymentDate,
    this.failureReason,
    this.invoiceUrl,
    this.isRenewal = false,
    this.renewalType = VipRenewalType.initial,
    this.createdAt,
  });

  factory VipPayment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return VipPayment(
      id: doc.id,
      providerId: (d['providerId'] as String?) ?? '',
      subscriptionId: (d['subscriptionId'] as String?) ?? '',
      amount: (d['amount'] as num?)?.toInt() ?? 0,
      currency: (d['currency'] as String?) ?? 'ILS',
      status: VipPaymentStatus.fromDb(d['status'] as String?),
      paymentMethod: (d['paymentMethod'] as String?) ?? 'credits',
      cardLast4: d['cardLast4'] as String?,
      paymentDate: (d['paymentDate'] as Timestamp?)?.toDate(),
      failureReason: d['failureReason'] as String?,
      invoiceUrl: d['invoiceUrl'] as String?,
      isRenewal: d['isRenewal'] as bool? ?? false,
      renewalType: VipRenewalType.fromDb(d['renewalType'] as String?),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'providerId': providerId,
        'subscriptionId': subscriptionId,
        'amount': amount,
        'currency': currency,
        'status': status.dbValue,
        'paymentMethod': paymentMethod,
        if (cardLast4 != null) 'cardLast4': cardLast4,
        if (paymentDate != null)
          'paymentDate': Timestamp.fromDate(paymentDate!),
        if (failureReason != null) 'failureReason': failureReason,
        if (invoiceUrl != null) 'invoiceUrl': invoiceUrl,
        'isRenewal': isRenewal,
        'renewalType': renewalType.dbValue,
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      };
}
