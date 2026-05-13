// Fitness Trainer Category-Specific Module — provider profile model.
// Follows the same pattern as MassageProfile (§3d), PestControlProfile (§32),
// DeliveryProfile (§33), CleaningProfile (§34), and HandymanProfile (§41).
//
// Key rules (per docs/ui-specs/Fitness Trainer/01_MAIN_PROMPT.md):
// • NO "online" location — only home / park / gym.
// • NO rating breakdown duplication — already exists below the block.
// • NO weekly availability — Google Calendar is already synced.
// • NO portfolio gallery duplication — already exists in profile.
// • AI = Gemini 2.5 Flash Lite (never Claude) — matches §32/33/34/41.
import 'package:cloud_firestore/cloud_firestore.dart';

/// Detects whether a given serviceType / sub-category name is the fitness
/// trainer category. Matches Hebrew "מאמני כושר" / "מאמן כושר" and English.
bool isFitnessTrainerCategory(String? serviceType) {
  if (serviceType == null) return false;
  final lower = serviceType.trim().toLowerCase();
  if (lower.isEmpty) return false;
  return lower == 'מאמני כושר' ||
      lower == 'מאמן כושר' ||
      lower == 'fitness_trainer' ||
      lower == 'personal trainer' ||
      lower.contains('מאמן כושר') ||
      lower.contains('מאמנת כושר') ||
      lower.contains('fitness') ||
      lower.contains('personal trainer');
}

// ═══════════════════════════════════════════════════════════════════════════
// CATALOGS (const, not stored)
// ═══════════════════════════════════════════════════════════════════════════

/// 12 trainer specialties available for selection (max 5 per trainer).
enum SpecialtyType {
  strength,
  fatLoss,
  pregnancy,
  seniors,
  rehab,
  flexibility,
  endurance,
  martialArts,
  calisthenics,
  functional,
  competitionPrep,
  bulking,
}

/// Catalog entry for a specialty — label, emoji, gradient colors.
class TrainerSpecialty {
  final SpecialtyType type;
  final String label;
  final String emoji;
  final List<int> colors; // [primary, secondary] as 0xAARRGGBB ints

  const TrainerSpecialty({
    required this.type,
    required this.label,
    required this.emoji,
    required this.colors,
  });

  String get id => type.name;

  static const List<TrainerSpecialty> all = [
    TrainerSpecialty(
        type: SpecialtyType.strength,
        label: 'כוח ומסה',
        emoji: '💪',
        colors: [0xFFEF4444, 0xFFDC2626]),
    TrainerSpecialty(
        type: SpecialtyType.fatLoss,
        label: 'הרזיה',
        emoji: '🔥',
        colors: [0xFFF59E0B, 0xFFD97706]),
    TrainerSpecialty(
        type: SpecialtyType.pregnancy,
        label: 'הריון ולאחר לידה',
        emoji: '🤰',
        colors: [0xFF3B82F6, 0xFF2563EB]),
    TrainerSpecialty(
        type: SpecialtyType.seniors,
        label: 'מבוגרים 50+',
        emoji: '👴',
        colors: [0xFF6366F1, 0xFF4F46E5]),
    TrainerSpecialty(
        type: SpecialtyType.rehab,
        label: 'שיקום',
        emoji: '🏥',
        colors: [0xFF10B981, 0xFF059669]),
    TrainerSpecialty(
        type: SpecialtyType.flexibility,
        label: 'גמישות',
        emoji: '🧘',
        colors: [0xFFEC4899, 0xFFDB2777]),
    TrainerSpecialty(
        type: SpecialtyType.endurance,
        label: 'סיבולת',
        emoji: '🏃',
        colors: [0xFFFBBF24, 0xFFF59E0B]),
    TrainerSpecialty(
        type: SpecialtyType.martialArts,
        label: 'לחימה',
        emoji: '🥊',
        colors: [0xFF991B1B, 0xFF7F1D1D]),
    TrainerSpecialty(
        type: SpecialtyType.calisthenics,
        label: 'קליסטניקס',
        emoji: '🤸',
        colors: [0xFF8B5CF6, 0xFF7C3AED]),
    TrainerSpecialty(
        type: SpecialtyType.functional,
        label: 'פונקציונלי',
        emoji: '🏊',
        colors: [0xFF06B6D4, 0xFF0891B2]),
    TrainerSpecialty(
        type: SpecialtyType.competitionPrep,
        label: 'הכנה לתחרויות',
        emoji: '🏆',
        colors: [0xFFA855F7, 0xFF9333EA]),
    TrainerSpecialty(
        type: SpecialtyType.bulking,
        label: 'הקצנת מסה',
        emoji: '🎯',
        colors: [0xFF14B8A6, 0xFF0D9488]),
  ];

  static TrainerSpecialty? byType(SpecialtyType t) {
    for (final s in all) {
      if (s.type == t) return s;
    }
    return null;
  }

  static SpecialtyType? parse(String? raw) {
    if (raw == null) return null;
    for (final t in SpecialtyType.values) {
      if (t.name == raw) return t;
    }
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// INSTANCE MODELS (user-editable)
// ═══════════════════════════════════════════════════════════════════════════

enum PackageType { single, package, monthly }

class PricingPackage {
  final String id;
  final String name;
  final PackageType type;
  final int sessions;
  final int durationMinutes;
  final int price;
  final int? discount;
  final int? validityMonths;
  final bool isPopular;
  final bool includesFreeOnboarding;

  const PricingPackage({
    required this.id,
    required this.name,
    required this.type,
    required this.sessions,
    required this.durationMinutes,
    required this.price,
    this.discount,
    this.validityMonths,
    this.isPopular = false,
    this.includesFreeOnboarding = false,
  });

  double get pricePerSession => sessions > 0 ? price / sessions : price.toDouble();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'type': type.name,
        'sessions': sessions,
        'durationMinutes': durationMinutes,
        'price': price,
        'discount': discount,
        'validityMonths': validityMonths,
        'isPopular': isPopular,
        'includesFreeOnboarding': includesFreeOnboarding,
      };

  factory PricingPackage.fromMap(Map<String, dynamic> m) => PricingPackage(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        type: _parsePackageType(m['type']),
        sessions: (m['sessions'] as num?)?.toInt() ?? 1,
        durationMinutes: (m['durationMinutes'] as num?)?.toInt() ?? 60,
        price: (m['price'] as num?)?.toInt() ?? 0,
        discount: (m['discount'] as num?)?.toInt(),
        validityMonths: (m['validityMonths'] as num?)?.toInt(),
        isPopular: m['isPopular'] == true,
        includesFreeOnboarding: m['includesFreeOnboarding'] == true,
      );

  PricingPackage copyWith({
    String? id,
    String? name,
    PackageType? type,
    int? sessions,
    int? durationMinutes,
    int? price,
    int? discount,
    int? validityMonths,
    bool? isPopular,
    bool? includesFreeOnboarding,
  }) =>
      PricingPackage(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        sessions: sessions ?? this.sessions,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        price: price ?? this.price,
        discount: discount ?? this.discount,
        validityMonths: validityMonths ?? this.validityMonths,
        isPopular: isPopular ?? this.isPopular,
        includesFreeOnboarding:
            includesFreeOnboarding ?? this.includesFreeOnboarding,
      );

  static PackageType _parsePackageType(dynamic raw) {
    for (final t in PackageType.values) {
      if (t.name == raw) return t;
    }
    return PackageType.package;
  }
}

// ───────────────────────────────────────────────────────────────────────────

class Certification {
  final String id;
  final String name;
  final String institution;
  final int year;
  final String? imageUrl;
  final bool isVerified;

  const Certification({
    required this.id,
    required this.name,
    required this.institution,
    required this.year,
    this.imageUrl,
    this.isVerified = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'institution': institution,
        'year': year,
        'imageUrl': imageUrl,
        'isVerified': isVerified,
      };

  factory Certification.fromMap(Map<String, dynamic> m) => Certification(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        institution: (m['institution'] ?? '').toString(),
        year: (m['year'] as num?)?.toInt() ?? DateTime.now().year,
        imageUrl: m['imageUrl'] as String?,
        isVerified: m['isVerified'] == true,
      );

  Certification copyWith({
    String? id,
    String? name,
    String? institution,
    int? year,
    String? imageUrl,
    bool? isVerified,
  }) =>
      Certification(
        id: id ?? this.id,
        name: name ?? this.name,
        institution: institution ?? this.institution,
        year: year ?? this.year,
        imageUrl: imageUrl ?? this.imageUrl,
        isVerified: isVerified ?? this.isVerified,
      );
}

// ───────────────────────────────────────────────────────────────────────────

class SuccessStory {
  final String id;
  final String clientName;
  final String result;
  final String? testimonial;
  final String? beforeImageUrl;
  final String? afterImageUrl;
  final int rating;
  final DateTime createdAt;
  final bool clientApproved;

  const SuccessStory({
    required this.id,
    required this.clientName,
    required this.result,
    this.testimonial,
    this.beforeImageUrl,
    this.afterImageUrl,
    this.rating = 5,
    required this.createdAt,
    this.clientApproved = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'clientName': clientName,
        'result': result,
        'testimonial': testimonial,
        'beforeImageUrl': beforeImageUrl,
        'afterImageUrl': afterImageUrl,
        'rating': rating,
        'createdAt': Timestamp.fromDate(createdAt),
        'clientApproved': clientApproved,
      };

  factory SuccessStory.fromMap(Map<String, dynamic> m) => SuccessStory(
        id: (m['id'] ?? '').toString(),
        clientName: (m['clientName'] ?? '').toString(),
        result: (m['result'] ?? '').toString(),
        testimonial: m['testimonial'] as String?,
        beforeImageUrl: m['beforeImageUrl'] as String?,
        afterImageUrl: m['afterImageUrl'] as String?,
        rating: (m['rating'] as num?)?.toInt() ?? 5,
        createdAt: _parseDate(m['createdAt']) ?? DateTime.now(),
        clientApproved: m['clientApproved'] == true,
      );

  SuccessStory copyWith({
    String? id,
    String? clientName,
    String? result,
    String? testimonial,
    String? beforeImageUrl,
    String? afterImageUrl,
    int? rating,
    DateTime? createdAt,
    bool? clientApproved,
  }) =>
      SuccessStory(
        id: id ?? this.id,
        clientName: clientName ?? this.clientName,
        result: result ?? this.result,
        testimonial: testimonial ?? this.testimonial,
        beforeImageUrl: beforeImageUrl ?? this.beforeImageUrl,
        afterImageUrl: afterImageUrl ?? this.afterImageUrl,
        rating: rating ?? this.rating,
        createdAt: createdAt ?? this.createdAt,
        clientApproved: clientApproved ?? this.clientApproved,
      );
}

// ───────────────────────────────────────────────────────────────────────────

enum OfferType { discount, firstFree, buyXgetY, custom }

class SpecialOffer {
  final String id;
  final OfferType type;
  final String title;
  final String description;
  final int? discountPercent;
  final int? availableSpots;
  final DateTime expiresAt;
  final bool isActive;

  const SpecialOffer({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    this.discountPercent,
    this.availableSpots,
    required this.expiresAt,
    this.isActive = true,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'title': title,
        'description': description,
        'discountPercent': discountPercent,
        'availableSpots': availableSpots,
        'expiresAt': Timestamp.fromDate(expiresAt),
        'isActive': isActive,
      };

  factory SpecialOffer.fromMap(Map<String, dynamic> m) => SpecialOffer(
        id: (m['id'] ?? '').toString(),
        type: _parseOfferType(m['type']),
        title: (m['title'] ?? '').toString(),
        description: (m['description'] ?? '').toString(),
        discountPercent: (m['discountPercent'] as num?)?.toInt(),
        availableSpots: (m['availableSpots'] as num?)?.toInt(),
        expiresAt: _parseDate(m['expiresAt']) ??
            DateTime.now().add(const Duration(days: 30)),
        isActive: m['isActive'] != false,
      );

  SpecialOffer copyWith({
    String? id,
    OfferType? type,
    String? title,
    String? description,
    int? discountPercent,
    int? availableSpots,
    DateTime? expiresAt,
    bool? isActive,
  }) =>
      SpecialOffer(
        id: id ?? this.id,
        type: type ?? this.type,
        title: title ?? this.title,
        description: description ?? this.description,
        discountPercent: discountPercent ?? this.discountPercent,
        availableSpots: availableSpots ?? this.availableSpots,
        expiresAt: expiresAt ?? this.expiresAt,
        isActive: isActive ?? this.isActive,
      );

  static OfferType _parseOfferType(dynamic raw) {
    for (final t in OfferType.values) {
      if (t.name == raw) return t;
    }
    return OfferType.discount;
  }
}

// ───────────────────────────────────────────────────────────────────────────

enum LocationType { home, park, gym }

class TrainingLocation {
  final String id;
  final LocationType type;
  final int radiusKm;
  final int? extraCost;
  final String? notes;

  const TrainingLocation({
    required this.id,
    required this.type,
    this.radiusKm = 15,
    this.extraCost,
    this.notes,
  });

  String get displayName {
    switch (type) {
      case LocationType.home:
        return 'בבית הלקוח';
      case LocationType.park:
        return 'בפארק';
      case LocationType.gym:
        return 'חדר כושר';
    }
  }

  String get emoji {
    switch (type) {
      case LocationType.home:
        return '🏠';
      case LocationType.park:
        return '🌳';
      case LocationType.gym:
        return '🏋️';
    }
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'radiusKm': radiusKm,
        'extraCost': extraCost,
        'notes': notes,
      };

  factory TrainingLocation.fromMap(Map<String, dynamic> m) => TrainingLocation(
        id: (m['id'] ?? '').toString(),
        type: _parseLocationType(m['type']),
        radiusKm: (m['radiusKm'] as num?)?.toInt() ?? 15,
        extraCost: (m['extraCost'] as num?)?.toInt(),
        notes: m['notes'] as String?,
      );

  TrainingLocation copyWith({
    String? id,
    LocationType? type,
    int? radiusKm,
    int? extraCost,
    String? notes,
  }) =>
      TrainingLocation(
        id: id ?? this.id,
        type: type ?? this.type,
        radiusKm: radiusKm ?? this.radiusKm,
        extraCost: extraCost ?? this.extraCost,
        notes: notes ?? this.notes,
      );

  static LocationType _parseLocationType(dynamic raw) {
    for (final t in LocationType.values) {
      if (t.name == raw) return t;
    }
    return LocationType.gym;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ROOT PROFILE
// ═══════════════════════════════════════════════════════════════════════════

/// Root provider-side fitness trainer profile stored at
/// `users/{uid}.fitnessTrainerProfile`.
class FitnessTrainerProfile {
  final List<SpecialtyType> selectedSpecialties; // max 5
  final List<PricingPackage> packages;
  final List<TrainingLocation> locations;
  final List<Certification> certifications;
  final List<SuccessStory> successStories;
  final List<SpecialOffer> offers;
  final int profileScore; // 0-100, written by optimizeTrainerProfile CF
  final List<Map<String, dynamic>> aiSuggestions;
  final DateTime? lastOptimized;

  const FitnessTrainerProfile({
    this.selectedSpecialties = const [],
    this.packages = const [],
    this.locations = const [],
    this.certifications = const [],
    this.successStories = const [],
    this.offers = const [],
    this.profileScore = 0,
    this.aiSuggestions = const [],
    this.lastOptimized,
  });

  Map<String, dynamic> toMap() => {
        'selectedSpecialties':
            selectedSpecialties.map((t) => t.name).toList(),
        'packages': packages.map((p) => p.toMap()).toList(),
        'locations': locations.map((l) => l.toMap()).toList(),
        'certifications': certifications.map((c) => c.toMap()).toList(),
        'successStories': successStories.map((s) => s.toMap()).toList(),
        'offers': offers.map((o) => o.toMap()).toList(),
        'profileScore': profileScore,
        'aiSuggestions': aiSuggestions,
        if (lastOptimized != null)
          'lastOptimized': Timestamp.fromDate(lastOptimized!),
      };

  factory FitnessTrainerProfile.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const FitnessTrainerProfile();
    return FitnessTrainerProfile(
      selectedSpecialties: (raw['selectedSpecialties'] as List?)
              ?.map((e) => TrainerSpecialty.parse(e?.toString()))
              .whereType<SpecialtyType>()
              .toList() ??
          const [],
      packages: (raw['packages'] as List?)
              ?.whereType<Map>()
              .map((m) => PricingPackage.fromMap(Map<String, dynamic>.from(m)))
              .toList() ??
          const [],
      locations: (raw['locations'] as List?)
              ?.whereType<Map>()
              .map((m) =>
                  TrainingLocation.fromMap(Map<String, dynamic>.from(m)))
              .toList() ??
          const [],
      certifications: (raw['certifications'] as List?)
              ?.whereType<Map>()
              .map((m) => Certification.fromMap(Map<String, dynamic>.from(m)))
              .toList() ??
          const [],
      successStories: (raw['successStories'] as List?)
              ?.whereType<Map>()
              .map((m) => SuccessStory.fromMap(Map<String, dynamic>.from(m)))
              .toList() ??
          const [],
      offers: (raw['offers'] as List?)
              ?.whereType<Map>()
              .map((m) => SpecialOffer.fromMap(Map<String, dynamic>.from(m)))
              .toList() ??
          const [],
      profileScore: (raw['profileScore'] as num?)?.toInt() ?? 0,
      aiSuggestions: (raw['aiSuggestions'] as List?)
              ?.whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList() ??
          const [],
      lastOptimized: _parseDate(raw['lastOptimized']),
    );
  }

  FitnessTrainerProfile copyWith({
    List<SpecialtyType>? selectedSpecialties,
    List<PricingPackage>? packages,
    List<TrainingLocation>? locations,
    List<Certification>? certifications,
    List<SuccessStory>? successStories,
    List<SpecialOffer>? offers,
    int? profileScore,
    List<Map<String, dynamic>>? aiSuggestions,
    DateTime? lastOptimized,
  }) =>
      FitnessTrainerProfile(
        selectedSpecialties: selectedSpecialties ?? this.selectedSpecialties,
        packages: packages ?? this.packages,
        locations: locations ?? this.locations,
        certifications: certifications ?? this.certifications,
        successStories: successStories ?? this.successStories,
        offers: offers ?? this.offers,
        profileScore: profileScore ?? this.profileScore,
        aiSuggestions: aiSuggestions ?? this.aiSuggestions,
        lastOptimized: lastOptimized ?? this.lastOptimized,
      );

  /// Returns the list of active offers (isActive && !isExpired).
  List<SpecialOffer> get activeOffers =>
      offers.where((o) => o.isActive && !o.isExpired).toList();

  /// The popular package (isPopular == true), or null.
  PricingPackage? get popularPackage {
    for (final p in packages) {
      if (p.isPopular) return p;
    }
    return null;
  }

  /// Deterministic fallback profile score — used when the CF hasn't run yet.
  /// Matches the same formula as the server-side `optimizeTrainerProfile` CF
  /// so the UI is never blank.
  int get fallbackScore {
    int s = 0;
    if (selectedSpecialties.length >= 3) {
      s += 15;
    } else if (selectedSpecialties.isNotEmpty) {
      s += 8;
    }
    final verifiedCerts = certifications.where((c) => c.isVerified).length;
    s += (verifiedCerts * 5).clamp(0, 15);
    if (packages.length >= 2) s += 10;
    s += (locations.length * 4).clamp(0, 10);
    s += (successStories.length * 5).clamp(0, 15);
    if (activeOffers.isNotEmpty) s += 10;
    // Placeholder for portfolio (not part of this model) +10
    return s.clamp(0, 100);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// INTERNAL HELPERS
// ═══════════════════════════════════════════════════════════════════════════

DateTime? _parseDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  if (raw is String) return DateTime.tryParse(raw);
  if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
  return null;
}
