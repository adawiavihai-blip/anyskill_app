import 'package:cloud_firestore/cloud_firestore.dart';

/// The verification lifecycle of a service provider.
enum VerificationStatus {
  /// Just signed up, waiting for admin review.
  pending,
  /// Admin approved — live in search with blue checkmark.
  verified,
  /// Provider is live but compliance not yet confirmed.
  unverifiedCompliance,
  /// Admin banned the account.
  banned,
}

/// Immutable data model for a service provider (expert).
///
/// Wraps the provider-specific fields from `users/{uid}`.
/// Not every user is a provider — use [isProvider] to check.
class ServiceProvider {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final String profileImage;

  // ── Provider status ───────────────────────────────────────────────────
  final bool isProvider;
  final bool isVerified;
  final bool isPendingExpert;
  final bool isVerifiedProvider;
  final bool isOnline;
  final bool isPromoted;
  final bool isHidden;
  final bool isBanned;
  final bool isDemo;
  final bool isTopRated;

  // ── Service & pricing ─────────────────────────────────────────────────
  final String serviceType;
  final String subCategory;
  final double pricePerHour;
  final Map<String, dynamic> categoryDetails;
  final String aboutMe;
  final List<String> gallery;
  final List<String> quickTags;

  // ── Ratings & gamification ────────────────────────────────────────────
  final double rating;
  final int reviewsCount;
  final int xp;
  final double balance;
  final double pendingBalance;

  // ── Verification data ─────────────────────────────────────────────────
  final String? verificationVideoUrl;
  final bool videoVerifiedByAdmin;
  final String? businessDocUrl;
  final bool categoryReviewedByAdmin;
  final bool pendingCategoryApproval;

  // ── Location ──────────────────────────────────────────────────────────
  final double? latitude;
  final double? longitude;

  // ── Engagement signals ────────────────────────────────────────────────
  final bool hasActiveStory;
  final DateTime? storyTimestamp;
  final DateTime? profileBoostUntil;
  final String cancellationPolicy;

  // ── Timestamps ────────────────────────────────────────────────────────
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ServiceProvider({
    required this.uid,
    this.name = '',
    this.email = '',
    this.phone = '',
    this.profileImage = '',
    this.isProvider = false,
    this.isVerified = false,
    this.isPendingExpert = false,
    this.isVerifiedProvider = true,
    this.isOnline = false,
    this.isPromoted = false,
    this.isHidden = false,
    this.isBanned = false,
    this.isDemo = false,
    this.isTopRated = false,
    this.serviceType = '',
    this.subCategory = '',
    this.pricePerHour = 0,
    this.categoryDetails = const {},
    this.aboutMe = '',
    this.gallery = const [],
    this.quickTags = const [],
    this.rating = 5.0,
    this.reviewsCount = 0,
    this.xp = 0,
    this.balance = 0,
    this.pendingBalance = 0,
    this.verificationVideoUrl,
    this.videoVerifiedByAdmin = false,
    this.businessDocUrl,
    this.categoryReviewedByAdmin = false,
    this.pendingCategoryApproval = false,
    this.latitude,
    this.longitude,
    this.hasActiveStory = false,
    this.storyTimestamp,
    this.profileBoostUntil,
    this.cancellationPolicy = 'flexible',
    this.createdAt,
    this.updatedAt,
  });

  // ── Computed properties ───────────────────────────────────────────────

  /// The current verification lifecycle state.
  VerificationStatus get verificationStatus {
    if (isBanned) return VerificationStatus.banned;
    if (isPendingExpert) return VerificationStatus.pending;
    if (isProvider && isVerified && isVerifiedProvider) {
      return VerificationStatus.verified;
    }
    if (isProvider && isVerified && !isVerifiedProvider) {
      return VerificationStatus.unverifiedCompliance;
    }
    return VerificationStatus.pending;
  }

  /// Whether this provider should appear in search results.
  bool get isSearchVisible =>
      isProvider && !isHidden && !isBanned && isVerified;

  /// Whether this provider has a location for distance ranking.
  bool get hasLocation => latitude != null && longitude != null;

  /// Whether the profile boost card is currently active.
  bool get isProfileBoosted =>
      profileBoostUntil != null && DateTime.now().isBefore(profileBoostUntil!);

  /// Whether there's a pending verification video for admin review.
  bool get hasUnreviewedVideo =>
      verificationVideoUrl != null &&
      verificationVideoUrl!.isNotEmpty &&
      !videoVerifiedByAdmin;

  // ── Firestore serialisation ───────────────────────────────────────────

  factory ServiceProvider.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return ServiceProvider(
      uid:                    doc.id,
      name:                   d['name']                   as String? ?? '',
      email:                  d['email']                  as String? ?? '',
      phone:                  (d['phone'] ?? d['phoneNumber']) as String? ?? '',
      profileImage:           d['profileImage']           as String? ?? '',
      isProvider:             d['isProvider']             as bool?   ?? false,
      isVerified:             d['isVerified']             as bool?   ?? false,
      isPendingExpert:        d['isPendingExpert']        as bool?   ?? false,
      isVerifiedProvider:     d['isVerifiedProvider']     as bool?   ?? true,
      isOnline:               d['isOnline']               as bool?   ?? false,
      isPromoted:             d['isPromoted']             as bool?   ?? false,
      isHidden:               d['isHidden']               as bool?   ?? false,
      isBanned:               d['isBanned']               as bool?   ?? false,
      isDemo:                 d['isDemo']                 as bool?   ?? false,
      isTopRated:             d['isTopRated']             as bool?   ?? false,
      serviceType:            d['serviceType']            as String? ?? '',
      subCategory:            d['subCategory']            as String? ?? '',
      pricePerHour:           (d['pricePerHour']          as num?)?.toDouble() ?? 0,
      categoryDetails:        (d['categoryDetails']       as Map<String, dynamic>?) ?? const {},
      aboutMe:                (d['aboutMe'] ?? d['bio'])  as String? ?? '',
      gallery:                (d['gallery']               as List?)?.cast<String>() ?? const [],
      quickTags:              (d['quickTags']             as List?)?.cast<String>() ?? const [],
      rating:                 (d['rating']                as num?)?.toDouble() ?? 5.0,
      reviewsCount:           (d['reviewsCount']          as num?)?.toInt() ?? 0,
      xp:                     (d['xp']                    as num?)?.toInt() ?? 0,
      balance:                (d['balance']               as num?)?.toDouble() ?? 0,
      pendingBalance:         (d['pendingBalance']        as num?)?.toDouble() ?? 0,
      verificationVideoUrl:   d['verificationVideoUrl']   as String?,
      videoVerifiedByAdmin:   d['videoVerifiedByAdmin']   as bool?   ?? false,
      businessDocUrl:         d['businessDocUrl']         as String?,
      categoryReviewedByAdmin: d['categoryReviewedByAdmin'] as bool? ?? false,
      pendingCategoryApproval: d['pendingCategoryApproval'] as bool? ?? false,
      latitude:               (d['latitude']              as num?)?.toDouble(),
      longitude:              (d['longitude']             as num?)?.toDouble(),
      hasActiveStory:         d['hasActiveStory']         as bool?   ?? false,
      storyTimestamp:          (d['storyTimestamp']        as Timestamp?)?.toDate(),
      profileBoostUntil:      (d['profileBoostUntil']     as Timestamp?)?.toDate(),
      cancellationPolicy:     d['cancellationPolicy']     as String? ?? 'flexible',
      createdAt:              (d['createdAt']             as Timestamp?)?.toDate(),
      updatedAt:              (d['updatedAt']             as Timestamp?)?.toDate(),
    );
  }

  /// Produces a map for Firestore writes. Only includes fields that should
  /// be written from the client (excludes server-only fields like xp, balance).
  Map<String, dynamic> toProfileUpdate() => {
    'name':               name,
    'aboutMe':            aboutMe,
    'serviceType':        serviceType,
    'subCategory':        subCategory,
    'pricePerHour':       pricePerHour,
    'categoryDetails':    categoryDetails,
    'gallery':            gallery,
    'quickTags':          quickTags,
    'cancellationPolicy': cancellationPolicy,
    'updatedAt':          FieldValue.serverTimestamp(),
  };

  // ── Immutable updates ─────────────────────────────────────────────────

  ServiceProvider copyWith({
    String? uid,
    String? name,
    String? email,
    String? phone,
    String? profileImage,
    bool? isProvider,
    bool? isVerified,
    bool? isPendingExpert,
    bool? isVerifiedProvider,
    bool? isOnline,
    bool? isPromoted,
    bool? isHidden,
    bool? isBanned,
    bool? isDemo,
    bool? isTopRated,
    String? serviceType,
    String? subCategory,
    double? pricePerHour,
    Map<String, dynamic>? categoryDetails,
    String? aboutMe,
    List<String>? gallery,
    List<String>? quickTags,
    double? rating,
    int? reviewsCount,
    int? xp,
    double? balance,
    double? pendingBalance,
    String? verificationVideoUrl,
    bool? videoVerifiedByAdmin,
    String? businessDocUrl,
    bool? categoryReviewedByAdmin,
    bool? pendingCategoryApproval,
    double? latitude,
    double? longitude,
    bool? hasActiveStory,
    DateTime? storyTimestamp,
    DateTime? profileBoostUntil,
    String? cancellationPolicy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ServiceProvider(
      uid:                    uid                    ?? this.uid,
      name:                   name                   ?? this.name,
      email:                  email                  ?? this.email,
      phone:                  phone                  ?? this.phone,
      profileImage:           profileImage           ?? this.profileImage,
      isProvider:             isProvider             ?? this.isProvider,
      isVerified:             isVerified             ?? this.isVerified,
      isPendingExpert:        isPendingExpert        ?? this.isPendingExpert,
      isVerifiedProvider:     isVerifiedProvider     ?? this.isVerifiedProvider,
      isOnline:               isOnline               ?? this.isOnline,
      isPromoted:             isPromoted             ?? this.isPromoted,
      isHidden:               isHidden               ?? this.isHidden,
      isBanned:               isBanned               ?? this.isBanned,
      isDemo:                 isDemo                 ?? this.isDemo,
      isTopRated:             isTopRated             ?? this.isTopRated,
      serviceType:            serviceType            ?? this.serviceType,
      subCategory:            subCategory            ?? this.subCategory,
      pricePerHour:           pricePerHour           ?? this.pricePerHour,
      categoryDetails:        categoryDetails        ?? this.categoryDetails,
      aboutMe:                aboutMe                ?? this.aboutMe,
      gallery:                gallery                ?? this.gallery,
      quickTags:              quickTags              ?? this.quickTags,
      rating:                 rating                 ?? this.rating,
      reviewsCount:           reviewsCount           ?? this.reviewsCount,
      xp:                     xp                     ?? this.xp,
      balance:                balance                ?? this.balance,
      pendingBalance:         pendingBalance         ?? this.pendingBalance,
      verificationVideoUrl:   verificationVideoUrl   ?? this.verificationVideoUrl,
      videoVerifiedByAdmin:   videoVerifiedByAdmin   ?? this.videoVerifiedByAdmin,
      businessDocUrl:         businessDocUrl         ?? this.businessDocUrl,
      categoryReviewedByAdmin: categoryReviewedByAdmin ?? this.categoryReviewedByAdmin,
      pendingCategoryApproval: pendingCategoryApproval ?? this.pendingCategoryApproval,
      latitude:               latitude               ?? this.latitude,
      longitude:              longitude               ?? this.longitude,
      hasActiveStory:         hasActiveStory         ?? this.hasActiveStory,
      storyTimestamp:          storyTimestamp          ?? this.storyTimestamp,
      profileBoostUntil:      profileBoostUntil      ?? this.profileBoostUntil,
      cancellationPolicy:     cancellationPolicy     ?? this.cancellationPolicy,
      createdAt:              createdAt              ?? this.createdAt,
      updatedAt:              updatedAt              ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ServiceProvider && uid == other.uid;

  @override
  int get hashCode => uid.hashCode;
}
