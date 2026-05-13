import 'package:cloud_firestore/cloud_firestore.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// VIP subscription model — Firestore collection `vip_subscriptions/`.
///
/// Created in Phase 3 of the Banners Studio rewrite (CLAUDE.md §49 →
/// new §51 once shipped). Tracks who's in the 30-slot VIP rail at the
/// top of the home tab, how they got there (paid / admin-comp / trial),
/// and their renewal terms.
///
/// **Single source of truth (Phase 3 → Phase 5):**
///   Phase 3 ships the admin UI + admin-comp grants only. Paid
///   subscriptions populate from Phase 5's `purchaseVipWithCredits`
///   Cloud Function. The customer-facing carousel is STILL driven by
///   `banners/{id}.providerCarousel.providerIds` until Phase 5 syncs
///   them via the `vip_carousel_state/current` doc.
///
/// **Money note (CLAUDE.md §2):** Stripe was removed in v11.9.x.
/// `pricePerMonth` is denominated in INTERNAL CREDITS (₪1 = 1 credit).
/// When the Israeli payment provider lands, the `purchaseVipWithCredits`
/// CF gets a sibling for cards — schema unchanged.
/// ═══════════════════════════════════════════════════════════════════════════

/// Lifecycle state of a single subscription.
enum VipSubscriptionStatus {
  active('active'),
  expired('expired'),
  pending('pending'),
  waitlist('waitlist'),
  adminComp('admin_comp');

  final String dbValue;
  const VipSubscriptionStatus(this.dbValue);

  static VipSubscriptionStatus fromDb(String? v) {
    for (final s in values) {
      if (s.dbValue == v) return s;
    }
    return VipSubscriptionStatus.active;
  }

  String get hebrewLabel => switch (this) {
        VipSubscriptionStatus.active => 'פעיל',
        VipSubscriptionStatus.expired => 'פג תוקף',
        VipSubscriptionStatus.pending => 'ממתין',
        VipSubscriptionStatus.waitlist => 'ברשימת המתנה',
        VipSubscriptionStatus.adminComp => 'חינם · מנהל',
      };
}

/// How the subscription got created.
enum VipSubscriptionType {
  paid('paid'),
  adminComp('admin_comp'),
  trial('trial');

  final String dbValue;
  const VipSubscriptionType(this.dbValue);

  static VipSubscriptionType fromDb(String? v) {
    for (final t in values) {
      if (t.dbValue == v) return t;
    }
    return VipSubscriptionType.paid;
  }

  String get hebrewLabel => switch (this) {
        VipSubscriptionType.paid => 'משלם',
        VipSubscriptionType.adminComp => 'חינם · מנהל',
        VipSubscriptionType.trial => 'תקופת ניסיון',
      };
}

/// Admin-comp duration presets. `permanent` writes `null` for endDate.
enum VipCompDuration {
  trial30d('trial_30d', 30),
  oneMonth('1_month', 30),
  threeMonths('3_months', 90),
  permanent('permanent', null);

  final String dbValue;

  /// Days from now to set endDate. `null` for permanent grants.
  final int? days;

  const VipCompDuration(this.dbValue, this.days);

  static VipCompDuration fromDb(String? v) {
    for (final d in values) {
      if (d.dbValue == v) return d;
    }
    return VipCompDuration.oneMonth;
  }

  String get hebrewLabel => switch (this) {
        VipCompDuration.trial30d => 'ניסיון 30 ימים',
        VipCompDuration.oneMonth => 'חודש',
        VipCompDuration.threeMonths => '3 חודשים',
        VipCompDuration.permanent => 'קבוע',
      };
}

class VipSubscription {
  final String id;
  final String providerId;
  final VipSubscriptionStatus status;
  final VipSubscriptionType type;

  final DateTime? startDate;
  final DateTime? endDate;

  /// True = auto-renew with internal credits at the end of the period.
  /// Always false for adminComp grants.
  final bool autoRenew;

  /// In credits (₪1 == 1 credit). 99 is the standard tier.
  final int pricePerMonth;

  /// Slot index (1-30) when status==active and rotation is "fixed". Null
  /// when on waitlist or in fair_daily mode.
  final int? carouselPosition;
  final int? waitlistPosition;

  // ── Admin-comp specific ────────────────────────────────────────────
  final String? compReason;
  final VipCompDuration? compDuration;
  final String? grantedBy;
  final DateTime? grantedAt;

  // ── Aggregate metrics (populated by analytics CF in Phase 6) ───────
  final int totalImpressions;
  final int totalClicks;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const VipSubscription({
    required this.id,
    required this.providerId,
    required this.status,
    required this.type,
    this.startDate,
    this.endDate,
    this.autoRenew = false,
    this.pricePerMonth = 99,
    this.carouselPosition,
    this.waitlistPosition,
    this.compReason,
    this.compDuration,
    this.grantedBy,
    this.grantedAt,
    this.totalImpressions = 0,
    this.totalClicks = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory VipSubscription.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return VipSubscription(
      id: doc.id,
      providerId: (d['providerId'] as String?) ?? '',
      status: VipSubscriptionStatus.fromDb(d['status'] as String?),
      type: VipSubscriptionType.fromDb(d['type'] as String?),
      startDate: (d['startDate'] as Timestamp?)?.toDate(),
      endDate: (d['endDate'] as Timestamp?)?.toDate(),
      autoRenew: d['autoRenew'] as bool? ?? false,
      pricePerMonth: (d['pricePerMonth'] as num?)?.toInt() ?? 99,
      carouselPosition: (d['carouselPosition'] as num?)?.toInt(),
      waitlistPosition: (d['waitlistPosition'] as num?)?.toInt(),
      compReason: d['compReason'] as String?,
      compDuration: d['compDuration'] != null
          ? VipCompDuration.fromDb(d['compDuration'] as String?)
          : null,
      grantedBy: d['grantedBy'] as String?,
      grantedAt: (d['grantedAt'] as Timestamp?)?.toDate(),
      totalImpressions: (d['totalImpressions'] as num?)?.toInt() ?? 0,
      totalClicks: (d['totalClicks'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'providerId': providerId,
        'status': status.dbValue,
        'type': type.dbValue,
        if (startDate != null) 'startDate': Timestamp.fromDate(startDate!),
        'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
        'autoRenew': autoRenew,
        'pricePerMonth': pricePerMonth,
        if (carouselPosition != null) 'carouselPosition': carouselPosition,
        if (waitlistPosition != null) 'waitlistPosition': waitlistPosition,
        if (compReason != null) 'compReason': compReason,
        if (compDuration != null) 'compDuration': compDuration!.dbValue,
        if (grantedBy != null) 'grantedBy': grantedBy,
        if (grantedAt != null) 'grantedAt': Timestamp.fromDate(grantedAt!),
        'totalImpressions': totalImpressions,
        'totalClicks': totalClicks,
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
        if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      };

  /// Days remaining before [endDate], or null for permanent / undated.
  int? get daysRemaining {
    if (endDate == null) return null;
    final diff = endDate!.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  /// True iff the period has fully elapsed.
  bool get isExpired {
    if (endDate == null) return false;
    return endDate!.isBefore(DateTime.now());
  }

  /// Aggregate CTR (0-100). 0 when no impressions.
  double get ctr =>
      totalImpressions == 0 ? 0 : (totalClicks / totalImpressions) * 100;

  VipSubscription copyWith({
    String? providerId,
    VipSubscriptionStatus? status,
    VipSubscriptionType? type,
    Object? startDate = _sentinel,
    Object? endDate = _sentinel,
    bool? autoRenew,
    int? pricePerMonth,
    Object? carouselPosition = _sentinel,
    Object? waitlistPosition = _sentinel,
    Object? compReason = _sentinel,
    Object? compDuration = _sentinel,
    Object? grantedBy = _sentinel,
    Object? grantedAt = _sentinel,
    int? totalImpressions,
    int? totalClicks,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      VipSubscription(
        id: id,
        providerId: providerId ?? this.providerId,
        status: status ?? this.status,
        type: type ?? this.type,
        startDate: identical(startDate, _sentinel)
            ? this.startDate
            : startDate as DateTime?,
        endDate: identical(endDate, _sentinel)
            ? this.endDate
            : endDate as DateTime?,
        autoRenew: autoRenew ?? this.autoRenew,
        pricePerMonth: pricePerMonth ?? this.pricePerMonth,
        carouselPosition: identical(carouselPosition, _sentinel)
            ? this.carouselPosition
            : carouselPosition as int?,
        waitlistPosition: identical(waitlistPosition, _sentinel)
            ? this.waitlistPosition
            : waitlistPosition as int?,
        compReason: identical(compReason, _sentinel)
            ? this.compReason
            : compReason as String?,
        compDuration: identical(compDuration, _sentinel)
            ? this.compDuration
            : compDuration as VipCompDuration?,
        grantedBy: identical(grantedBy, _sentinel)
            ? this.grantedBy
            : grantedBy as String?,
        grantedAt: identical(grantedAt, _sentinel)
            ? this.grantedAt
            : grantedAt as DateTime?,
        totalImpressions: totalImpressions ?? this.totalImpressions,
        totalClicks: totalClicks ?? this.totalClicks,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  static const Object _sentinel = Object();
}
