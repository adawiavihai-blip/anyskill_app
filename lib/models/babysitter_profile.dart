// Babysitter category-specific module (CSM) — see CLAUDE.md §53.
//
// Mirrors the structural pattern of:
//   - lib/models/pest_control_profile.dart  (§32)
//   - lib/models/cleaning_profile.dart      (§34)
//   - lib/models/handyman_profile.dart      (§41)
//   - lib/models/fitness_trainer_profile.dart (§44)
//
// Domain rules captured:
//  • Smart Auto-Billing: per-#-children rates + night/holiday/late surcharges.
//  • Verified Address: address fields are captured at booking time (lives on
//    the job doc, NOT here) — but the provider can declare the supported
//    service area + arrival radius for GPS validation.
//  • Background check + first-aid certification surface as Trust Badges in
//    the client block.

class BabysitterProfile {
  final BabysitterExperience experience;
  final List<String> ageGroups;
  final List<String> servicesOffered;
  final List<BabysitterCertification> certifications;
  final BabysitterPricingConfig pricing;
  final BabysitterAvailability availability;
  final BabysitterServiceArea serviceArea;
  final BabysitterTrustBadges trust;
  final String introNote;

  const BabysitterProfile({
    this.experience = const BabysitterExperience(),
    this.ageGroups = const [],
    this.servicesOffered = const [],
    this.certifications = const [],
    this.pricing = const BabysitterPricingConfig(),
    this.availability = const BabysitterAvailability(),
    this.serviceArea = const BabysitterServiceArea(),
    this.trust = const BabysitterTrustBadges(),
    this.introNote = '',
  });

  factory BabysitterProfile.fromMap(Map<String, dynamic> map) {
    return BabysitterProfile(
      experience: BabysitterExperience.fromMap(
          Map<String, dynamic>.from(map['experience'] ?? {})),
      ageGroups: List<String>.from(map['ageGroups'] ?? const []),
      servicesOffered:
          List<String>.from(map['servicesOffered'] ?? const []),
      certifications: (map['certifications'] as List? ?? const [])
          .whereType<Map>()
          .map((e) =>
              BabysitterCertification.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      pricing: BabysitterPricingConfig.fromMap(
          Map<String, dynamic>.from(map['pricing'] ?? {})),
      availability: BabysitterAvailability.fromMap(
          Map<String, dynamic>.from(map['availability'] ?? {})),
      serviceArea: BabysitterServiceArea.fromMap(
          Map<String, dynamic>.from(map['serviceArea'] ?? {})),
      trust: BabysitterTrustBadges.fromMap(
          Map<String, dynamic>.from(map['trust'] ?? {})),
      introNote: map['introNote'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'experience': experience.toMap(),
        'ageGroups': ageGroups,
        'servicesOffered': servicesOffered,
        'certifications': certifications.map((c) => c.toMap()).toList(),
        'pricing': pricing.toMap(),
        'availability': availability.toMap(),
        'serviceArea': serviceArea.toMap(),
        'trust': trust.toMap(),
        'introNote': introNote,
      };

  BabysitterProfile copyWith({
    BabysitterExperience? experience,
    List<String>? ageGroups,
    List<String>? servicesOffered,
    List<BabysitterCertification>? certifications,
    BabysitterPricingConfig? pricing,
    BabysitterAvailability? availability,
    BabysitterServiceArea? serviceArea,
    BabysitterTrustBadges? trust,
    String? introNote,
  }) =>
      BabysitterProfile(
        experience: experience ?? this.experience,
        ageGroups: ageGroups ?? this.ageGroups,
        servicesOffered: servicesOffered ?? this.servicesOffered,
        certifications: certifications ?? this.certifications,
        pricing: pricing ?? this.pricing,
        availability: availability ?? this.availability,
        serviceArea: serviceArea ?? this.serviceArea,
        trust: trust ?? this.trust,
        introNote: introNote ?? this.introNote,
      );
}

class BabysitterExperience {
  final int yearsExperience;
  final int totalFamilies;
  final bool hasOwnChildren;

  const BabysitterExperience({
    this.yearsExperience = 0,
    this.totalFamilies = 0,
    this.hasOwnChildren = false,
  });

  factory BabysitterExperience.fromMap(Map<String, dynamic> map) =>
      BabysitterExperience(
        yearsExperience: (map['yearsExperience'] as num? ?? 0).toInt(),
        totalFamilies: (map['totalFamilies'] as num? ?? 0).toInt(),
        hasOwnChildren: map['hasOwnChildren'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
        'yearsExperience': yearsExperience,
        'totalFamilies': totalFamilies,
        'hasOwnChildren': hasOwnChildren,
      };
}

class BabysitterCertification {
  final String id;
  final String type; // first_aid | bls | childcare_diploma | teaching_cert | other
  final String nameHe;
  final String? validUntil;
  final String? issuedBy;
  final bool verified;

  const BabysitterCertification({
    required this.id,
    required this.type,
    required this.nameHe,
    this.validUntil,
    this.issuedBy,
    this.verified = false,
  });

  factory BabysitterCertification.fromMap(Map<String, dynamic> map) =>
      BabysitterCertification(
        id: map['id'] as String? ?? '',
        type: map['type'] as String? ?? '',
        nameHe: map['nameHe'] as String? ?? '',
        validUntil: map['validUntil'] as String?,
        issuedBy: map['issuedBy'] as String?,
        verified: map['verified'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'nameHe': nameHe,
        if (validUntil != null) 'validUntil': validUntil,
        if (issuedBy != null) 'issuedBy': issuedBy,
        'verified': verified,
      };
}

/// Smart Auto-Billing rules — the heart of the babysitter CSM.
/// All amounts are NIS (₪).
class BabysitterPricingConfig {
  /// Hourly rate when watching 1 child.
  final double rateOneChild;

  /// Hourly rate when watching 2 children.
  final double rateTwoChildren;

  /// Hourly rate when watching 3+ children.
  final double rateThreePlusChildren;

  /// Percent surcharge added to the hourly rate during night hours
  /// (e.g. 20 = +20% on each night-hour).
  final int nightSurchargePercent;

  /// Hour (24h) at which night surcharge starts. Default 22 = 22:00.
  final int nightStartsAtHour;

  /// Hour (24h) at which night surcharge ends. Default 6 = 06:00.
  /// Surcharge applies to hours that start at or after [nightStartsAtHour]
  /// OR that start before [nightEndsAtHour].
  final int nightEndsAtHour;

  /// Percent surcharge added to the entire bill on Israeli holidays.
  final int holidaySurchargePercent;

  /// NIS charged per [lateFeeIntervalMinutes] of parent lateness past
  /// `agreedEndTime`. Default 40₪ per 15 min.
  final double lateFeePerInterval;

  /// Granularity for lateness rounding. Always rounded UP.
  final int lateFeeIntervalMinutes;

  /// Hard cap on lateness fee, prevents abuse.
  final double lateFeeMaxAmount;

  /// Minimum bookable shift in hours. Bookings shorter are rejected client-side.
  final int minimumBookingHours;

  /// Optional flat overnight rate (e.g. 20:00–08:00). 0 = disabled (use hourly).
  final double overnightFlatRate;

  /// Surcharge percent for last-minute bookings (less than [lastMinuteThresholdHours] in advance).
  final int lastMinuteSurchargePercent;
  final int lastMinuteThresholdHours;

  const BabysitterPricingConfig({
    this.rateOneChild = 60,
    this.rateTwoChildren = 80,
    this.rateThreePlusChildren = 100,
    this.nightSurchargePercent = 20,
    this.nightStartsAtHour = 22,
    this.nightEndsAtHour = 6,
    this.holidaySurchargePercent = 50,
    this.lateFeePerInterval = 40,
    this.lateFeeIntervalMinutes = 15,
    this.lateFeeMaxAmount = 500,
    this.minimumBookingHours = 2,
    this.overnightFlatRate = 0,
    this.lastMinuteSurchargePercent = 30,
    this.lastMinuteThresholdHours = 1,
  });

  factory BabysitterPricingConfig.fromMap(Map<String, dynamic> map) =>
      BabysitterPricingConfig(
        rateOneChild: (map['rateOneChild'] as num? ?? 60).toDouble(),
        rateTwoChildren: (map['rateTwoChildren'] as num? ?? 80).toDouble(),
        rateThreePlusChildren:
            (map['rateThreePlusChildren'] as num? ?? 100).toDouble(),
        nightSurchargePercent:
            (map['nightSurchargePercent'] as num? ?? 20).toInt(),
        nightStartsAtHour: (map['nightStartsAtHour'] as num? ?? 22).toInt(),
        nightEndsAtHour: (map['nightEndsAtHour'] as num? ?? 6).toInt(),
        holidaySurchargePercent:
            (map['holidaySurchargePercent'] as num? ?? 50).toInt(),
        lateFeePerInterval:
            (map['lateFeePerInterval'] as num? ?? 40).toDouble(),
        lateFeeIntervalMinutes:
            (map['lateFeeIntervalMinutes'] as num? ?? 15).toInt(),
        lateFeeMaxAmount:
            (map['lateFeeMaxAmount'] as num? ?? 500).toDouble(),
        minimumBookingHours: (map['minimumBookingHours'] as num? ?? 2).toInt(),
        overnightFlatRate: (map['overnightFlatRate'] as num? ?? 0).toDouble(),
        lastMinuteSurchargePercent:
            (map['lastMinuteSurchargePercent'] as num? ?? 30).toInt(),
        lastMinuteThresholdHours:
            (map['lastMinuteThresholdHours'] as num? ?? 1).toInt(),
      );

  Map<String, dynamic> toMap() => {
        'rateOneChild': rateOneChild,
        'rateTwoChildren': rateTwoChildren,
        'rateThreePlusChildren': rateThreePlusChildren,
        'nightSurchargePercent': nightSurchargePercent,
        'nightStartsAtHour': nightStartsAtHour,
        'nightEndsAtHour': nightEndsAtHour,
        'holidaySurchargePercent': holidaySurchargePercent,
        'lateFeePerInterval': lateFeePerInterval,
        'lateFeeIntervalMinutes': lateFeeIntervalMinutes,
        'lateFeeMaxAmount': lateFeeMaxAmount,
        'minimumBookingHours': minimumBookingHours,
        'overnightFlatRate': overnightFlatRate,
        'lastMinuteSurchargePercent': lastMinuteSurchargePercent,
        'lastMinuteThresholdHours': lastMinuteThresholdHours,
      };

  BabysitterPricingConfig copyWith({
    double? rateOneChild,
    double? rateTwoChildren,
    double? rateThreePlusChildren,
    int? nightSurchargePercent,
    int? nightStartsAtHour,
    int? nightEndsAtHour,
    int? holidaySurchargePercent,
    double? lateFeePerInterval,
    int? lateFeeIntervalMinutes,
    double? lateFeeMaxAmount,
    int? minimumBookingHours,
    double? overnightFlatRate,
    int? lastMinuteSurchargePercent,
    int? lastMinuteThresholdHours,
  }) =>
      BabysitterPricingConfig(
        rateOneChild: rateOneChild ?? this.rateOneChild,
        rateTwoChildren: rateTwoChildren ?? this.rateTwoChildren,
        rateThreePlusChildren:
            rateThreePlusChildren ?? this.rateThreePlusChildren,
        nightSurchargePercent:
            nightSurchargePercent ?? this.nightSurchargePercent,
        nightStartsAtHour: nightStartsAtHour ?? this.nightStartsAtHour,
        nightEndsAtHour: nightEndsAtHour ?? this.nightEndsAtHour,
        holidaySurchargePercent:
            holidaySurchargePercent ?? this.holidaySurchargePercent,
        lateFeePerInterval: lateFeePerInterval ?? this.lateFeePerInterval,
        lateFeeIntervalMinutes:
            lateFeeIntervalMinutes ?? this.lateFeeIntervalMinutes,
        lateFeeMaxAmount: lateFeeMaxAmount ?? this.lateFeeMaxAmount,
        minimumBookingHours: minimumBookingHours ?? this.minimumBookingHours,
        overnightFlatRate: overnightFlatRate ?? this.overnightFlatRate,
        lastMinuteSurchargePercent:
            lastMinuteSurchargePercent ?? this.lastMinuteSurchargePercent,
        lastMinuteThresholdHours:
            lastMinuteThresholdHours ?? this.lastMinuteThresholdHours,
      );

  /// Returns the hourly rate for a given # of children.
  double rateForChildren(int numChildren) {
    if (numChildren <= 1) return rateOneChild;
    if (numChildren == 2) return rateTwoChildren;
    return rateThreePlusChildren;
  }
}

class BabysitterAvailability {
  /// Available days of the week. 0 = Sunday … 6 = Saturday.
  final List<int> availableDays;
  final bool acceptsLastMinute;
  final bool acceptsOvernight;
  final bool acceptsHolidays;

  const BabysitterAvailability({
    this.availableDays = const [0, 1, 2, 3, 4, 5, 6],
    this.acceptsLastMinute = true,
    this.acceptsOvernight = false,
    this.acceptsHolidays = true,
  });

  factory BabysitterAvailability.fromMap(Map<String, dynamic> map) =>
      BabysitterAvailability(
        availableDays:
            List<int>.from(map['availableDays'] ?? const [0, 1, 2, 3, 4, 5, 6]),
        acceptsLastMinute: map['acceptsLastMinute'] as bool? ?? true,
        acceptsOvernight: map['acceptsOvernight'] as bool? ?? false,
        acceptsHolidays: map['acceptsHolidays'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {
        'availableDays': availableDays,
        'acceptsLastMinute': acceptsLastMinute,
        'acceptsOvernight': acceptsOvernight,
        'acceptsHolidays': acceptsHolidays,
      };
}

class BabysitterServiceArea {
  /// Cities the babysitter is willing to travel to.
  final List<String> cities;

  /// GPS arrival radius (meters) — when the babysitter taps "Start Job",
  /// her current GPS must be within this distance from the booking address.
  /// Used by the existing job-lifecycle layer (NOT this CSM block).
  final int arrivalRadiusMeters;

  /// Travel surcharge for trips outside [freeRadiusKm].
  final int travelFeeOutsideRadius;
  final int freeRadiusKm;

  const BabysitterServiceArea({
    this.cities = const [],
    this.arrivalRadiusMeters = 50,
    this.travelFeeOutsideRadius = 30,
    this.freeRadiusKm = 10,
  });

  factory BabysitterServiceArea.fromMap(Map<String, dynamic> map) =>
      BabysitterServiceArea(
        cities: List<String>.from(map['cities'] ?? const []),
        arrivalRadiusMeters:
            (map['arrivalRadiusMeters'] as num? ?? 50).toInt(),
        travelFeeOutsideRadius:
            (map['travelFeeOutsideRadius'] as num? ?? 30).toInt(),
        freeRadiusKm: (map['freeRadiusKm'] as num? ?? 10).toInt(),
      );

  Map<String, dynamic> toMap() => {
        'cities': cities,
        'arrivalRadiusMeters': arrivalRadiusMeters,
        'travelFeeOutsideRadius': travelFeeOutsideRadius,
        'freeRadiusKm': freeRadiusKm,
      };
}

class BabysitterTrustBadges {
  final bool backgroundChecked;
  final bool idVerified;
  final bool referencesAvailable;
  final int referencesCount;

  const BabysitterTrustBadges({
    this.backgroundChecked = false,
    this.idVerified = false,
    this.referencesAvailable = false,
    this.referencesCount = 0,
  });

  factory BabysitterTrustBadges.fromMap(Map<String, dynamic> map) =>
      BabysitterTrustBadges(
        backgroundChecked: map['backgroundChecked'] as bool? ?? false,
        idVerified: map['idVerified'] as bool? ?? false,
        referencesAvailable: map['referencesAvailable'] as bool? ?? false,
        referencesCount: (map['referencesCount'] as num? ?? 0).toInt(),
      );

  Map<String, dynamic> toMap() => {
        'backgroundChecked': backgroundChecked,
        'idVerified': idVerified,
        'referencesAvailable': referencesAvailable,
        'referencesCount': referencesCount,
      };
}

/// Detector — mirror of `isFitnessTrainerCategory`, `isPestControlCategory`, etc.
/// Matches the Hebrew & English spellings the user might enter for the
/// babysitter sub-category.
bool isBabysitterCategory(String? serviceType) {
  if (serviceType == null) return false;
  final lower = serviceType.trim().toLowerCase();
  if (lower.isEmpty) return false;
  return lower == 'בייביסיטר' ||
      lower == 'בייביסיטרים' ||
      lower == 'שמרטף' ||
      lower == 'שמרטפים' ||
      lower == 'שמרטפות' ||
      lower == 'babysitter' ||
      lower == 'baby sitter' ||
      lower == 'nanny' ||
      lower.contains('בייביסיטר') ||
      lower.contains('שמרטף') ||
      lower.contains('שמרטפ') ||
      lower.contains('babysit') ||
      lower.contains('nanny');
}
