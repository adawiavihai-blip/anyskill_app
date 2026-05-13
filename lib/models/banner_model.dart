import 'package:cloud_firestore/cloud_firestore.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Banner data model — Firestore collection `banners`
//
// This model extends the existing schema (title, subtitle, placement,
// isActive, order, imageUrl, color1/color2, iconName, expiresAt,
// providerId/Name/Photo, clicks) with the fields needed for the v15.x
// banners admin redesign — scoped purple palette, provider_carousel type,
// analytics (impressions + attributedRevenue), and A/B testing schema.
//
// Backward-compat rules (Phase-2 decision #2):
//  - DB field name STAYS `placement` (not renamed to `type`). The Dart
//    enum is named `BannerType` to match the spec but serializes to the
//    `placement` field so existing docs + the home_tab `_PromoCarousel`
//    stream keep working untouched.
//  - Every new field is optional with a sensible default on missing —
//    the legacy banner docs (before this PR) deserialize cleanly.
//  - Legacy single-featured-provider fields (providerId/Name/Photo)
//    stay separate from the new `providerCarousel` nested object.
//
// `promoted_banners` (categories_v3 §45) is a separate collection and is
// out of scope for this redesign — see note in Section §49 of CLAUDE.md.
// ═══════════════════════════════════════════════════════════════════════════

/// The kind of banner surface — serializes to the DB `placement` field.
enum BannerType {
  homeCarousel('home_carousel'),
  wallet('wallet'),
  popup('popup'),
  topBar('top_bar'),
  providerCarousel('provider_carousel'),
  // ── Phase 4 (Subcategory Banners admin, 2026-04-26) ─────────────────
  /// Renders at the top of a sub-category screen on the customer side.
  /// Either pinned to a specific `subcategoryId` OR — when
  /// `isDefaultGlobalSubcat == true` — used as the global default for
  /// any subcategory without a dedicated banner.
  subcategory('subcategory');

  final String dbValue;
  const BannerType(this.dbValue);

  static BannerType fromDb(String? value) {
    if (value == null) return BannerType.homeCarousel;
    for (final t in values) {
      if (t.dbValue == value) return t;
    }
    return BannerType.homeCarousel;
  }

  String get hebrewLabel => switch (this) {
        BannerType.homeCarousel => 'קרוסלה',
        BannerType.wallet => 'ארנק',
        BannerType.popup => 'פופ-אפ',
        BannerType.topBar => 'באנר עליון',
        BannerType.providerCarousel => 'נותני שירות',
        BannerType.subcategory => 'תת-קטגוריה',
      };
}

/// Derived lifecycle state of a banner — NOT stored; computed from
/// `isActive` + `startDate` + `endDate/expiresAt` + historical metrics.
enum BannerStatus {
  active,
  scheduled,
  draft,
  expired;

  String get hebrewLabel => switch (this) {
        BannerStatus.active => 'פעיל',
        BannerStatus.scheduled => 'מתוזמן',
        BannerStatus.draft => 'טיוטה',
        BannerStatus.expired => 'הסתיים',
      };
}

/// How the rotating provider cards are ordered in a provider_carousel.
enum ProviderSortMode {
  ai('ai'),
  random('random'),
  rating('rating'),
  manual('manual');

  final String dbValue;
  const ProviderSortMode(this.dbValue);

  static ProviderSortMode fromDb(String? v) {
    for (final m in values) {
      if (m.dbValue == v) return m;
    }
    return ProviderSortMode.ai;
  }

  String get hebrewLabel => switch (this) {
        ProviderSortMode.ai => 'חכם · AI',
        ProviderSortMode.random => 'אקראי',
        ProviderSortMode.rating => 'לפי דירוג',
        ProviderSortMode.manual => 'סדר ידני',
      };
}

/// The transition animation between cards in a provider_carousel.
enum CarouselTransition {
  slide('slide'),
  fade('fade'),
  zoom('zoom'),
  flip('flip');

  final String dbValue;
  const CarouselTransition(this.dbValue);

  static CarouselTransition fromDb(String? v) {
    for (final t in values) {
      if (t.dbValue == v) return t;
    }
    return CarouselTransition.fade;
  }

  String get hebrewLabel => switch (this) {
        CarouselTransition.slide => 'החלקה',
        CarouselTransition.fade => 'עמעום',
        CarouselTransition.zoom => 'הגדלה',
        CarouselTransition.flip => 'היפוך',
      };
}

/// Per-card display toggles inside a provider_carousel.
class CarouselDisplayOptions {
  final bool showProfilePic;
  final bool showRating;
  final bool showGallery;
  final int galleryCount;
  final bool showCategory;
  final bool showPrice;
  final bool showAvailability;

  const CarouselDisplayOptions({
    this.showProfilePic = true,
    this.showRating = true,
    this.showGallery = true,
    this.galleryCount = 3,
    this.showCategory = true,
    this.showPrice = false,
    this.showAvailability = true,
  });

  factory CarouselDisplayOptions.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const CarouselDisplayOptions();
    return CarouselDisplayOptions(
      showProfilePic: m['showProfilePic'] as bool? ?? true,
      showRating: m['showRating'] as bool? ?? true,
      showGallery: m['showGallery'] as bool? ?? true,
      galleryCount: (m['galleryCount'] as num?)?.toInt() ?? 3,
      showCategory: m['showCategory'] as bool? ?? true,
      showPrice: m['showPrice'] as bool? ?? false,
      showAvailability: m['showAvailability'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        'showProfilePic': showProfilePic,
        'showRating': showRating,
        'showGallery': showGallery,
        'galleryCount': galleryCount,
        'showCategory': showCategory,
        'showPrice': showPrice,
        'showAvailability': showAvailability,
      };

  CarouselDisplayOptions copyWith({
    bool? showProfilePic,
    bool? showRating,
    bool? showGallery,
    int? galleryCount,
    bool? showCategory,
    bool? showPrice,
    bool? showAvailability,
  }) =>
      CarouselDisplayOptions(
        showProfilePic: showProfilePic ?? this.showProfilePic,
        showRating: showRating ?? this.showRating,
        showGallery: showGallery ?? this.showGallery,
        galleryCount: galleryCount ?? this.galleryCount,
        showCategory: showCategory ?? this.showCategory,
        showPrice: showPrice ?? this.showPrice,
        showAvailability: showAvailability ?? this.showAvailability,
      );
}

/// Configuration for a `provider_carousel`-typed banner.
///
/// Stored as nested Map under `banners/{id}.providerCarousel`. Absent on
/// legacy banner types — always-null for homeCarousel/wallet/popup/topBar.
class ProviderCarouselConfig {
  /// 2–20 provider uids (enforced client-side in wizard + server-side
  /// via CF if reordering via AI).
  final List<String> providerIds;

  /// Milliseconds between card swaps. Clamp to 2000–8000.
  final int rotationDurationMs;

  final ProviderSortMode sortMode;
  final CarouselTransition transition;
  final CarouselDisplayOptions display;

  const ProviderCarouselConfig({
    this.providerIds = const [],
    this.rotationDurationMs = 4000,
    this.sortMode = ProviderSortMode.ai,
    this.transition = CarouselTransition.fade,
    this.display = const CarouselDisplayOptions(),
  });

  factory ProviderCarouselConfig.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const ProviderCarouselConfig();
    final raw = (m['providerIds'] as List?) ?? const [];
    // Defensive cast for `display` — Firestore sometimes returns nested
    // maps as `Map<dynamic, dynamic>`, which would crash a direct
    // `as Map<String, dynamic>?` with the dreaded "Null check operator
    // used on a null value" on web (we ate it for a week before tracking
    // it down). `Map<String, dynamic>.from(...)` succeeds for either.
    final rawDisplay = m['display'];
    final display = rawDisplay is Map
        ? Map<String, dynamic>.from(rawDisplay)
        : null;
    final clamped =
        ((m['rotationDurationMs'] as num?)?.toInt() ?? 4000).clamp(2000, 8000);
    return ProviderCarouselConfig(
      providerIds: raw.whereType<String>().toList(),
      rotationDurationMs: clamped.toInt(),
      sortMode: ProviderSortMode.fromDb(m['sortMode'] as String?),
      transition: CarouselTransition.fromDb(m['transition'] as String?),
      display: CarouselDisplayOptions.fromMap(display),
    );
  }

  Map<String, dynamic> toMap() => {
        'providerIds': providerIds,
        'rotationDurationMs': rotationDurationMs.clamp(2000, 8000),
        'sortMode': sortMode.dbValue,
        'transition': transition.dbValue,
        'display': display.toMap(),
      };

  ProviderCarouselConfig copyWith({
    List<String>? providerIds,
    int? rotationDurationMs,
    ProviderSortMode? sortMode,
    CarouselTransition? transition,
    CarouselDisplayOptions? display,
  }) =>
      ProviderCarouselConfig(
        providerIds: providerIds ?? this.providerIds,
        rotationDurationMs: rotationDurationMs ?? this.rotationDurationMs,
        sortMode: sortMode ?? this.sortMode,
        transition: transition ?? this.transition,
        display: display ?? this.display,
      );

  /// Total seconds for one full rotation of all cards.
  double get fullCycleSeconds =>
      (providerIds.length * rotationDurationMs) / 1000.0;

  bool get isValid =>
      providerIds.length >= 2 && providerIds.length <= 20;

  /// Returns a Hebrew error message if the config is invalid, or null
  /// when it's safe to publish.
  ///
  /// ⚠️ TODO(phase-5): the admin wizard in Phase 5 MUST call this
  /// before enabling the "פרסם" CTA — otherwise a provider_carousel
  /// banner with 1 or 21+ providers can be written to Firestore.
  /// `toFirestore` intentionally does NOT throw on invalid input so
  /// the admin UI never crashes mid-save. The hard enforcement layer
  /// (Firestore security rule on `banners/{id}.providerCarousel.providerIds`
  /// size) is Phase-10 QA work.
  String? validate() {
    if (providerIds.length < 2) {
      return 'בחר לפחות 2 נותני שירות';
    }
    if (providerIds.length > 20) {
      return 'ניתן להוסיף עד 20 נותני שירות (נבחרו ${providerIds.length})';
    }
    if (rotationDurationMs < 2000 || rotationDurationMs > 8000) {
      return 'משך הצגה חייב להיות בין 2 ל-8 שניות';
    }
    return null;
  }
}

/// A single A/B variant. Schema only in this phase — no runtime split
/// until the A/B feature ships in a later PR (prompt §9, decision #3).
class BannerAbVariant {
  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final double trafficPercent; // 0-100, sum across variants == 100
  final int impressions;
  final int clicks;

  const BannerAbVariant({
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.trafficPercent = 50,
    this.impressions = 0,
    this.clicks = 0,
  });

  factory BannerAbVariant.fromMap(Map<String, dynamic> m) => BannerAbVariant(
        id: m['id'] as String? ?? '',
        title: m['title'] as String? ?? '',
        subtitle: m['subtitle'] as String?,
        imageUrl: m['imageUrl'] as String?,
        trafficPercent: (m['trafficPercent'] as num?)?.toDouble() ?? 50,
        impressions: (m['impressions'] as num?)?.toInt() ?? 0,
        clicks: (m['clicks'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'trafficPercent': trafficPercent,
        'impressions': impressions,
        'clicks': clicks,
      };

  double get ctr => impressions == 0 ? 0 : (clicks / impressions) * 100;
}

/// Immutable view of a single banner doc — Firestore path `banners/{id}`.
class BannerModel {
  final String id;

  // ── Copy (existing fields) ────────────────────────────────────────────
  final String title;
  final String subtitle;

  // ── Placement / type (serializes to DB field `placement`) ──────────
  final BannerType type;

  // ── Lifecycle ─────────────────────────────────────────────────────────
  final bool isActive;
  final int order;
  final DateTime? startDate; // new — null means "active immediately"
  final DateTime? endDate;   // maps to DB field `expiresAt`

  // ── Display (existing fields) ────────────────────────────────────────
  final String imageUrl;      // empty == gradient mode
  final String color1;        // hex without '#', e.g. '667EEA'
  final String color2;
  final String iconName;

  // ── Legacy single featured provider (kept for back-compat) ───────────
  final String? providerId;
  final String? providerName;
  final String? providerPhoto;

  // ── NEW — provider_carousel config ───────────────────────────────────
  final ProviderCarouselConfig? providerCarousel;

  // ── NEW — analytics ──────────────────────────────────────────────────
  final int impressions;
  final int clicks;
  final double attributedRevenue;

  // ── NEW — A/B schema (UI deferred per decision #3) ───────────────────
  final bool hasAbTest;
  final List<BannerAbVariant> abVariants;

  // ── NEW — Phase 2 (Banner Edit screen, 2026-04-25) ──────────────────
  /// 'gradient' | 'image' (informational — UI tracks last user choice).
  /// Fallback rule: if `imageUrl` is non-empty, treat as 'image'; else
  /// 'gradient'. Used by [Section 2 — Design] of the edit screen so
  /// switching back to gradient mode after deleting an image preserves
  /// the user's intent.
  final String? designStyle;

  /// Picked emoji for the banner thumbnail / runtime icon — overrides
  /// `iconName` when present. 10 hand-picked options surfaced in the
  /// edit-screen icon picker.
  final String? iconEmoji;

  /// Per-day schedule hours, e.g. `{sun:[8,12,16], mon:[...]}`. Schema
  /// only in Phase 2 — runtime gating ships in Phase 6 (CLAUDE.md §50
  /// notes: home_tab + ProviderCarouselBanner respect it later).
  final Map<String, List<int>>? scheduleHours;

  // ── NEW — Phase 4 (Subcategory Banners admin, 2026-04-26) ───────────
  /// When [type] == subcategory, the doc id of the target subcategory
  /// (categories collection, where parentId != ''). Null + `isDefault…
  /// GlobalSubcat: true` = global default for any unbanned subcategory.
  final String? subcategoryId;

  /// True iff this is THE one global default subcategory banner. At most
  /// one such doc should exist; the admin UI enforces single-instance.
  final bool isDefaultGlobalSubcat;

  // ── Metadata ─────────────────────────────────────────────────────────
  final DateTime? createdAt;
  final String? createdBy; // admin uid

  const BannerModel({
    required this.id,
    this.title = '',
    this.subtitle = '',
    this.type = BannerType.homeCarousel,
    this.isActive = true,
    this.order = 999,
    this.startDate,
    this.endDate,
    this.imageUrl = '',
    this.color1 = '667EEA',
    this.color2 = '764BA2',
    this.iconName = 'stars',
    this.providerId,
    this.providerName,
    this.providerPhoto,
    this.providerCarousel,
    this.impressions = 0,
    this.clicks = 0,
    this.attributedRevenue = 0,
    this.hasAbTest = false,
    this.abVariants = const [],
    this.designStyle,
    this.iconEmoji,
    this.scheduleHours,
    this.subcategoryId,
    this.isDefaultGlobalSubcat = false,
    this.createdAt,
    this.createdBy,
  });

  factory BannerModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return BannerModel.fromMap(doc.id, d);
  }

  factory BannerModel.fromMap(String id, Map<String, dynamic> d) {
    final type = BannerType.fromDb(d['placement'] as String?);
    final rawCarousel = d['providerCarousel'];
    final rawSchedule = d['scheduleHours'];
    Map<String, List<int>>? schedule;
    if (rawSchedule is Map) {
      schedule = <String, List<int>>{};
      rawSchedule.forEach((k, v) {
        if (k is String && v is List) {
          schedule![k] =
              v.whereType<num>().map((n) => n.toInt()).toList();
        }
      });
      if (schedule.isEmpty) schedule = null;
    }
    return BannerModel(
      id: id,
      title: (d['title'] as String?) ?? '',
      subtitle: (d['subtitle'] as String?) ?? '',
      type: type,
      isActive: d['isActive'] as bool? ?? true,
      order: (d['order'] as num?)?.toInt() ?? 999,
      startDate: (d['startDate'] as Timestamp?)?.toDate(),
      endDate: (d['expiresAt'] as Timestamp?)?.toDate(),
      imageUrl: (d['imageUrl'] as String?) ?? '',
      color1: (d['color1'] as String?) ?? '667EEA',
      color2: (d['color2'] as String?) ?? '764BA2',
      iconName: (d['iconName'] as String?) ?? 'stars',
      providerId: d['providerId'] as String?,
      providerName: d['providerName'] as String?,
      providerPhoto: d['providerPhoto'] as String?,
      // Provider carousel config can ride on TWO placements:
      // - `providerCarousel` (the global VIP rail on the home tab)
      // - `subcategory` with `designStyle == 'provider_carousel'` (a
      //   provider rail rendered inside CategoryResultsScreen header)
      // Both share the same wizard + runtime widget.
      providerCarousel: (rawCarousel is Map<String, dynamic> &&
              (type == BannerType.providerCarousel ||
                  type == BannerType.subcategory))
          ? ProviderCarouselConfig.fromMap(rawCarousel)
          : null,
      impressions: (d['impressions'] as num?)?.toInt() ?? 0,
      clicks: (d['clicks'] as num?)?.toInt() ?? 0,
      attributedRevenue:
          (d['attributedRevenue'] as num?)?.toDouble() ?? 0,
      hasAbTest: d['hasAbTest'] as bool? ?? false,
      abVariants: ((d['abVariants'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BannerAbVariant.fromMap)
          .toList(),
      designStyle: d['designStyle'] as String?,
      iconEmoji: d['iconEmoji'] as String?,
      scheduleHours: schedule,
      subcategoryId: d['subcategoryId'] as String?,
      isDefaultGlobalSubcat: d['isDefaultGlobalSubcat'] as bool? ?? false,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      createdBy: d['createdBy'] as String?,
    );
  }

  /// Serializes to the Firestore write shape used by `admin_banners_tab.dart`.
  ///
  /// Legacy fields stay at the top level; new fields are written beside
  /// them. An unknown-to-legacy reader (e.g. `_PromoCarousel` in
  /// `home_tab.dart`) simply ignores the new keys.
  Map<String, dynamic> toFirestore() => {
        'title': title,
        'subtitle': subtitle,
        'placement': type.dbValue,
        'isActive': isActive,
        'order': order,
        if (startDate != null) 'startDate': Timestamp.fromDate(startDate!),
        'expiresAt':
            endDate != null ? Timestamp.fromDate(endDate!) : null,
        'imageUrl': imageUrl,
        'color1': color1,
        'color2': color2,
        'iconName': iconName,
        if (providerId != null) 'providerId': providerId,
        if (providerName != null) 'providerName': providerName,
        if (providerPhoto != null) 'providerPhoto': providerPhoto,
        if (providerCarousel != null)
          'providerCarousel': providerCarousel!.toMap(),
        'impressions': impressions,
        'clicks': clicks,
        if (attributedRevenue > 0) 'attributedRevenue': attributedRevenue,
        'hasAbTest': hasAbTest,
        if (abVariants.isNotEmpty)
          'abVariants': abVariants.map((v) => v.toMap()).toList(),
        if (designStyle != null) 'designStyle': designStyle,
        if (iconEmoji != null) 'iconEmoji': iconEmoji,
        if (scheduleHours != null && scheduleHours!.isNotEmpty)
          'scheduleHours': scheduleHours,
        if (subcategoryId != null) 'subcategoryId': subcategoryId,
        if (isDefaultGlobalSubcat) 'isDefaultGlobalSubcat': true,
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
        if (createdBy != null) 'createdBy': createdBy,
      };

  /// Click-through rate as a percentage (0-100).
  double get ctr => impressions == 0 ? 0 : (clicks / impressions) * 100;

  /// Derived [BannerStatus] based on `isActive` + dates + history.
  ///
  /// Priority:
  ///  1. `endDate` in the past   → expired
  ///  2. `isActive == false`      → draft (if no clicks) or expired (if had)
  ///  3. `startDate` in the future → scheduled
  ///  4. otherwise                → active
  BannerStatus get status {
    final now = DateTime.now();
    if (endDate != null && endDate!.isBefore(now)) {
      return BannerStatus.expired;
    }
    if (!isActive) {
      return clicks > 0 || impressions > 0
          ? BannerStatus.expired
          : BannerStatus.draft;
    }
    if (startDate != null && startDate!.isAfter(now)) {
      return BannerStatus.scheduled;
    }
    return BannerStatus.active;
  }

  /// Same-shape copyWith — supports null-override via sentinel wrappers
  /// for nullable fields (caller passes an explicit `null` to clear).
  BannerModel copyWith({
    String? title,
    String? subtitle,
    BannerType? type,
    bool? isActive,
    int? order,
    Object? startDate = _sentinel,
    Object? endDate = _sentinel,
    String? imageUrl,
    String? color1,
    String? color2,
    String? iconName,
    Object? providerId = _sentinel,
    Object? providerName = _sentinel,
    Object? providerPhoto = _sentinel,
    Object? providerCarousel = _sentinel,
    int? impressions,
    int? clicks,
    double? attributedRevenue,
    bool? hasAbTest,
    List<BannerAbVariant>? abVariants,
    Object? designStyle = _sentinel,
    Object? iconEmoji = _sentinel,
    Object? scheduleHours = _sentinel,
    Object? subcategoryId = _sentinel,
    bool? isDefaultGlobalSubcat,
    DateTime? createdAt,
    String? createdBy,
  }) =>
      BannerModel(
        id: id,
        title: title ?? this.title,
        subtitle: subtitle ?? this.subtitle,
        type: type ?? this.type,
        isActive: isActive ?? this.isActive,
        order: order ?? this.order,
        startDate: identical(startDate, _sentinel)
            ? this.startDate
            : startDate as DateTime?,
        endDate: identical(endDate, _sentinel)
            ? this.endDate
            : endDate as DateTime?,
        imageUrl: imageUrl ?? this.imageUrl,
        color1: color1 ?? this.color1,
        color2: color2 ?? this.color2,
        iconName: iconName ?? this.iconName,
        providerId: identical(providerId, _sentinel)
            ? this.providerId
            : providerId as String?,
        providerName: identical(providerName, _sentinel)
            ? this.providerName
            : providerName as String?,
        providerPhoto: identical(providerPhoto, _sentinel)
            ? this.providerPhoto
            : providerPhoto as String?,
        providerCarousel: identical(providerCarousel, _sentinel)
            ? this.providerCarousel
            : providerCarousel as ProviderCarouselConfig?,
        impressions: impressions ?? this.impressions,
        clicks: clicks ?? this.clicks,
        attributedRevenue: attributedRevenue ?? this.attributedRevenue,
        hasAbTest: hasAbTest ?? this.hasAbTest,
        abVariants: abVariants ?? this.abVariants,
        designStyle: identical(designStyle, _sentinel)
            ? this.designStyle
            : designStyle as String?,
        iconEmoji: identical(iconEmoji, _sentinel)
            ? this.iconEmoji
            : iconEmoji as String?,
        scheduleHours: identical(scheduleHours, _sentinel)
            ? this.scheduleHours
            : scheduleHours as Map<String, List<int>>?,
        subcategoryId: identical(subcategoryId, _sentinel)
            ? this.subcategoryId
            : subcategoryId as String?,
        isDefaultGlobalSubcat:
            isDefaultGlobalSubcat ?? this.isDefaultGlobalSubcat,
        createdAt: createdAt ?? this.createdAt,
        createdBy: createdBy ?? this.createdBy,
      );

  static const Object _sentinel = Object();
}
