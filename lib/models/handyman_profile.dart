// Handyman Category-Specific Module — provider profile model.
// Follows the same pattern as MassageProfile (§3d), PestControlProfile (§32),
// DeliveryProfile (§33), and CleaningProfile (§34).
//
// Key rules (per docs/ui-specs/Handyman/01_MAIN_PROMPT_HANDYMAN.md):
// • NO insurance field anywhere.
// • NO idVerification — already global in app (onboarding §3).
// • NO working hours — the existing calendar owns schedule.
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/firestore_map.dart';

/// Detects whether a given serviceType / sub-category name is the handyman
/// category. Matches Hebrew "הנדימן" / "הנדי" / "מסתור" and English "handyman".
bool isHandymanCategory(String? serviceType) {
  if (serviceType == null) return false;
  final lower = serviceType.trim().toLowerCase();
  if (lower.isEmpty) return false;
  return lower == 'הנדימן' ||
      lower == 'handyman' ||
      lower == 'handy man' ||
      lower.contains('הנדי') ||
      lower.contains('handyman') ||
      lower.contains('handy man');
}

/// Root provider-side handyman profile stored at `users/{uid}.handymanProfile`.
class HandymanProfile {
  final HandymanVerifications verifications;
  final List<HandymanSpecialty> specialties;
  final HandymanAiPhotoSettings aiPhotoToQuote;
  final HandymanPricing pricing;
  final HandymanPunchListDiscount punchListDiscount;
  final HandymanServiceArea serviceArea;
  final HandymanMaterials materials;
  final List<HandymanMaintenancePackage> maintenancePackages;

  const HandymanProfile({
    this.verifications = const HandymanVerifications(),
    this.specialties = const [],
    this.aiPhotoToQuote = const HandymanAiPhotoSettings(),
    this.pricing = const HandymanPricing(),
    this.punchListDiscount = const HandymanPunchListDiscount(),
    this.serviceArea = const HandymanServiceArea(),
    this.materials = const HandymanMaterials(),
    this.maintenancePackages = const [],
  });

  Map<String, dynamic> toMap() => {
        'verifications': verifications.toMap(),
        'specialties': specialties.map((s) => s.toMap()).toList(),
        'aiPhotoToQuote': aiPhotoToQuote.toMap(),
        'pricing': pricing.toMap(),
        'punchListDiscount': punchListDiscount.toMap(),
        'serviceArea': serviceArea.toMap(),
        'materials': materials.toMap(),
        'maintenancePackages':
            maintenancePackages.map((p) => p.toMap()).toList(),
      };

  factory HandymanProfile.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const HandymanProfile();
    return HandymanProfile(
      verifications:
          HandymanVerifications.fromMap(safeMap(raw['verifications'])),
      specialties: (raw['specialties'] as List?)
              ?.whereType<Map>()
              .map(
                  (m) => HandymanSpecialty.fromMap(Map<String, dynamic>.from(m)))
              .toList() ??
          const [],
      aiPhotoToQuote:
          HandymanAiPhotoSettings.fromMap(safeMap(raw['aiPhotoToQuote'])),
      pricing: HandymanPricing.fromMap(safeMap(raw['pricing'])),
      punchListDiscount:
          HandymanPunchListDiscount.fromMap(safeMap(raw['punchListDiscount'])),
      serviceArea: HandymanServiceArea.fromMap(safeMap(raw['serviceArea'])),
      materials: HandymanMaterials.fromMap(safeMap(raw['materials'])),
      maintenancePackages: (raw['maintenancePackages'] as List?)
              ?.whereType<Map>()
              .map((m) => HandymanMaintenancePackage.fromMap(
                  Map<String, dynamic>.from(m)))
              .toList() ??
          const [],
    );
  }

  HandymanProfile copyWith({
    HandymanVerifications? verifications,
    List<HandymanSpecialty>? specialties,
    HandymanAiPhotoSettings? aiPhotoToQuote,
    HandymanPricing? pricing,
    HandymanPunchListDiscount? punchListDiscount,
    HandymanServiceArea? serviceArea,
    HandymanMaterials? materials,
    List<HandymanMaintenancePackage>? maintenancePackages,
  }) =>
      HandymanProfile(
        verifications: verifications ?? this.verifications,
        specialties: specialties ?? this.specialties,
        aiPhotoToQuote: aiPhotoToQuote ?? this.aiPhotoToQuote,
        pricing: pricing ?? this.pricing,
        punchListDiscount: punchListDiscount ?? this.punchListDiscount,
        serviceArea: serviceArea ?? this.serviceArea,
        materials: materials ?? this.materials,
        maintenancePackages: maintenancePackages ?? this.maintenancePackages,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// VERIFICATIONS — only 2 (background check + warranty). ID is global in app.
// NO insurance field.
// ═══════════════════════════════════════════════════════════════════════════

class HandymanVerifications {
  final HandymanBackgroundCheck backgroundCheck;
  final bool warrantyEnabled;

  const HandymanVerifications({
    this.backgroundCheck = const HandymanBackgroundCheck(),
    this.warrantyEnabled = true,
  });

  Map<String, dynamic> toMap() => {
        'backgroundCheck': backgroundCheck.toMap(),
        'warrantyEnabled': warrantyEnabled,
      };

  factory HandymanVerifications.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const HandymanVerifications();
    return HandymanVerifications(
      backgroundCheck:
          HandymanBackgroundCheck.fromMap(safeMap(raw['backgroundCheck'])),
      warrantyEnabled: raw['warrantyEnabled'] as bool? ?? true,
    );
  }

  HandymanVerifications copyWith({
    HandymanBackgroundCheck? backgroundCheck,
    bool? warrantyEnabled,
  }) =>
      HandymanVerifications(
        backgroundCheck: backgroundCheck ?? this.backgroundCheck,
        warrantyEnabled: warrantyEnabled ?? this.warrantyEnabled,
      );
}

class HandymanBackgroundCheck {
  final bool verified;
  final DateTime? verifiedAt;
  final String? documentUrl;

  const HandymanBackgroundCheck({
    this.verified = false,
    this.verifiedAt,
    this.documentUrl,
  });

  Map<String, dynamic> toMap() => {
        'verified': verified,
        if (verifiedAt != null) 'verifiedAt': Timestamp.fromDate(verifiedAt!),
        if (documentUrl != null) 'documentUrl': documentUrl,
      };

  factory HandymanBackgroundCheck.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const HandymanBackgroundCheck();
    return HandymanBackgroundCheck(
      verified: raw['verified'] as bool? ?? false,
      verifiedAt: raw['verifiedAt'] is Timestamp
          ? (raw['verifiedAt'] as Timestamp).toDate()
          : null,
      documentUrl: raw['documentUrl'] as String?,
    );
  }

  HandymanBackgroundCheck copyWith({
    bool? verified,
    DateTime? verifiedAt,
    String? documentUrl,
  }) =>
      HandymanBackgroundCheck(
        verified: verified ?? this.verified,
        verifiedAt: verifiedAt ?? this.verifiedAt,
        documentUrl: documentUrl ?? this.documentUrl,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// SPECIALTY — one of 23 trades the provider offers.
// ═══════════════════════════════════════════════════════════════════════════

class HandymanSpecialty {
  final String id;
  final String nameHe;
  final String icon;
  final bool active;
  final int yearCount;
  final String? popularity; // hot | urgent | null
  final double basePrice;
  final int estimatedMinutes;

  const HandymanSpecialty({
    required this.id,
    required this.nameHe,
    required this.icon,
    this.active = false,
    this.yearCount = 0,
    this.popularity,
    this.basePrice = 150,
    this.estimatedMinutes = 60,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'nameHe': nameHe,
        'icon': icon,
        'active': active,
        'yearCount': yearCount,
        if (popularity != null) 'popularity': popularity,
        'basePrice': basePrice,
        'estimatedMinutes': estimatedMinutes,
      };

  factory HandymanSpecialty.fromMap(Map<String, dynamic> raw) {
    return HandymanSpecialty(
      id: raw['id'] as String? ?? '',
      nameHe: raw['nameHe'] as String? ?? '',
      icon: raw['icon'] as String? ?? '🛠️',
      active: raw['active'] as bool? ?? false,
      yearCount: (raw['yearCount'] as num?)?.toInt() ?? 0,
      popularity: raw['popularity'] as String?,
      basePrice: (raw['basePrice'] as num?)?.toDouble() ?? 150,
      estimatedMinutes: (raw['estimatedMinutes'] as num?)?.toInt() ?? 60,
    );
  }

  HandymanSpecialty copyWith({
    String? id,
    String? nameHe,
    String? icon,
    bool? active,
    int? yearCount,
    String? popularity,
    double? basePrice,
    int? estimatedMinutes,
  }) =>
      HandymanSpecialty(
        id: id ?? this.id,
        nameHe: nameHe ?? this.nameHe,
        icon: icon ?? this.icon,
        active: active ?? this.active,
        yearCount: yearCount ?? this.yearCount,
        popularity: popularity ?? this.popularity,
        basePrice: basePrice ?? this.basePrice,
        estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// AI PHOTO-TO-QUOTE SETTINGS — enable + category toggles.
// ═══════════════════════════════════════════════════════════════════════════

class HandymanAiPhotoSettings {
  final bool enabled;
  final bool plumbing;
  final bool electrical;
  final bool drywall;
  final bool furniture;

  const HandymanAiPhotoSettings({
    this.enabled = true,
    this.plumbing = true,
    this.electrical = true,
    this.drywall = true,
    this.furniture = true,
  });

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'categories': {
          'plumbing': plumbing,
          'electrical': electrical,
          'drywall': drywall,
          'furniture': furniture,
        },
      };

  factory HandymanAiPhotoSettings.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const HandymanAiPhotoSettings();
    final cats = (raw['categories'] is Map)
        ? Map<String, dynamic>.from(raw['categories'] as Map)
        : <String, dynamic>{};
    return HandymanAiPhotoSettings(
      enabled: raw['enabled'] as bool? ?? true,
      plumbing: cats['plumbing'] as bool? ?? true,
      electrical: cats['electrical'] as bool? ?? true,
      drywall: cats['drywall'] as bool? ?? true,
      furniture: cats['furniture'] as bool? ?? true,
    );
  }

  HandymanAiPhotoSettings copyWith({
    bool? enabled,
    bool? plumbing,
    bool? electrical,
    bool? drywall,
    bool? furniture,
  }) =>
      HandymanAiPhotoSettings(
        enabled: enabled ?? this.enabled,
        plumbing: plumbing ?? this.plumbing,
        electrical: electrical ?? this.electrical,
        drywall: drywall ?? this.drywall,
        furniture: furniture ?? this.furniture,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// PRICING — custom per-service overrides + emergency surcharge.
// ═══════════════════════════════════════════════════════════════════════════

class HandymanPricing {
  /// { serviceId -> NIS price } — overrides specialty.basePrice when set.
  final Map<String, double> customPrices;
  final double emergencySurcharge;

  const HandymanPricing({
    this.customPrices = const {},
    this.emergencySurcharge = 50,
  });

  Map<String, dynamic> toMap() => {
        'custom': customPrices.entries
            .map((e) => {'serviceId': e.key, 'price': e.value})
            .toList(),
        'emergencySurcharge': emergencySurcharge,
      };

  factory HandymanPricing.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const HandymanPricing();
    final custom = <String, double>{};
    final list = raw['custom'] as List?;
    if (list != null) {
      for (final e in list.whereType<Map>()) {
        final m = Map<String, dynamic>.from(e);
        final id = m['serviceId'] as String?;
        final p = (m['price'] as num?)?.toDouble();
        if (id != null && p != null) custom[id] = p;
      }
    }
    return HandymanPricing(
      customPrices: custom,
      emergencySurcharge:
          (raw['emergencySurcharge'] as num?)?.toDouble() ?? 50,
    );
  }

  double priceFor(String serviceId, double fallback) =>
      customPrices[serviceId] ?? fallback;

  HandymanPricing copyWith({
    Map<String, double>? customPrices,
    double? emergencySurcharge,
  }) =>
      HandymanPricing(
        customPrices: customPrices ?? this.customPrices,
        emergencySurcharge: emergencySurcharge ?? this.emergencySurcharge,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// PUNCH LIST DISCOUNT — graduated % off when multiple jobs per visit.
// ═══════════════════════════════════════════════════════════════════════════

class HandymanPunchListDiscount {
  final int twoJobs;
  final int threeJobs;
  final int fourPlusJobs;

  const HandymanPunchListDiscount({
    this.twoJobs = 10,
    this.threeJobs = 20,
    this.fourPlusJobs = 30,
  });

  Map<String, dynamic> toMap() => {
        '2_jobs': twoJobs,
        '3_jobs': threeJobs,
        '4_plus_jobs': fourPlusJobs,
      };

  factory HandymanPunchListDiscount.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const HandymanPunchListDiscount();
    return HandymanPunchListDiscount(
      twoJobs: (raw['2_jobs'] as num?)?.toInt() ?? 10,
      threeJobs: (raw['3_jobs'] as num?)?.toInt() ?? 20,
      fourPlusJobs: (raw['4_plus_jobs'] as num?)?.toInt() ?? 30,
    );
  }

  /// Percentage (0-30) to subtract from services subtotal for a given
  /// punch-list size.
  int percentFor(int jobCount) {
    if (jobCount >= 4) return fourPlusJobs;
    if (jobCount == 3) return threeJobs;
    if (jobCount == 2) return twoJobs;
    return 0;
  }

  HandymanPunchListDiscount copyWith({
    int? twoJobs,
    int? threeJobs,
    int? fourPlusJobs,
  }) =>
      HandymanPunchListDiscount(
        twoJobs: twoJobs ?? this.twoJobs,
        threeJobs: threeJobs ?? this.threeJobs,
        fourPlusJobs: fourPlusJobs ?? this.fourPlusJobs,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// SERVICE AREA — cities + 24/7 flag + buffer. NO work-hours (that's calendar).
// ═══════════════════════════════════════════════════════════════════════════

class HandymanServiceArea {
  final List<String> cities;
  final bool emergency24_7;
  final int bufferMinutes;

  const HandymanServiceArea({
    this.cities = const [],
    this.emergency24_7 = false,
    this.bufferMinutes = 30,
  });

  Map<String, dynamic> toMap() => {
        'cities': cities,
        'emergency24_7': emergency24_7,
        'bufferMinutes': bufferMinutes,
      };

  factory HandymanServiceArea.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const HandymanServiceArea();
    return HandymanServiceArea(
      cities:
          (raw['cities'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      emergency24_7: raw['emergency24_7'] as bool? ?? false,
      bufferMinutes: (raw['bufferMinutes'] as num?)?.toInt() ?? 30,
    );
  }

  HandymanServiceArea copyWith({
    List<String>? cities,
    bool? emergency24_7,
    int? bufferMinutes,
  }) =>
      HandymanServiceArea(
        cities: cities ?? this.cities,
        emergency24_7: emergency24_7 ?? this.emergency24_7,
        bufferMinutes: bufferMinutes ?? this.bufferMinutes,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// MATERIALS — who buys + tools included toggle.
// policy: i_buy | client_buys | flexible
// ═══════════════════════════════════════════════════════════════════════════

class HandymanMaterials {
  final bool toolsIncluded;
  final String policy;

  const HandymanMaterials({
    this.toolsIncluded = true,
    this.policy = 'i_buy',
  });

  Map<String, dynamic> toMap() => {
        'toolsIncluded': toolsIncluded,
        'policy': policy,
      };

  factory HandymanMaterials.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const HandymanMaterials();
    return HandymanMaterials(
      toolsIncluded: raw['toolsIncluded'] as bool? ?? true,
      policy: raw['policy'] as String? ?? 'i_buy',
    );
  }

  HandymanMaterials copyWith({bool? toolsIncluded, String? policy}) =>
      HandymanMaterials(
        toolsIncluded: toolsIncluded ?? this.toolsIncluded,
        policy: policy ?? this.policy,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// MAINTENANCE PACKAGE — yearly contract tier.
// ═══════════════════════════════════════════════════════════════════════════

class HandymanMaintenancePackage {
  final String id;
  final String nameHe;
  final int visitsPerYear; // -1 = unlimited (VIP)
  final double yearlyPrice;
  final bool enabled;
  final int activeCustomers;
  final bool popular;

  const HandymanMaintenancePackage({
    required this.id,
    required this.nameHe,
    required this.visitsPerYear,
    required this.yearlyPrice,
    this.enabled = true,
    this.activeCustomers = 0,
    this.popular = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'nameHe': nameHe,
        'visitsPerYear': visitsPerYear,
        'yearlyPrice': yearlyPrice,
        'enabled': enabled,
        'activeCustomers': activeCustomers,
        'popular': popular,
      };

  factory HandymanMaintenancePackage.fromMap(Map<String, dynamic> raw) {
    return HandymanMaintenancePackage(
      id: raw['id'] as String? ?? '',
      nameHe: raw['nameHe'] as String? ?? '',
      visitsPerYear: (raw['visitsPerYear'] as num?)?.toInt() ?? 0,
      yearlyPrice: (raw['yearlyPrice'] as num?)?.toDouble() ?? 0,
      enabled: raw['enabled'] as bool? ?? true,
      activeCustomers: (raw['activeCustomers'] as num?)?.toInt() ?? 0,
      popular: raw['popular'] as bool? ?? false,
    );
  }

  HandymanMaintenancePackage copyWith({
    String? id,
    String? nameHe,
    int? visitsPerYear,
    double? yearlyPrice,
    bool? enabled,
    int? activeCustomers,
    bool? popular,
  }) =>
      HandymanMaintenancePackage(
        id: id ?? this.id,
        nameHe: nameHe ?? this.nameHe,
        visitsPerYear: visitsPerYear ?? this.visitsPerYear,
        yearlyPrice: yearlyPrice ?? this.yearlyPrice,
        enabled: enabled ?? this.enabled,
        activeCustomers: activeCustomers ?? this.activeCustomers,
        popular: popular ?? this.popular,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// CLIENT-SIDE BOOKING TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// Captured from the booking block and frozen onto `jobs/{id}.handymanPreferences`.
class HandymanBookingPreferences {
  final List<HandymanPunchListItem> punchList;
  final HandymanAiDiagnosis? aiPhotoDiagnosis;
  final String problemDescription;
  final HandymanPropertyInfo propertyInfo;
  final String materialsOption; // provider_buys | client_brings
  final double estimatedMaterialsCost;
  final List<HandymanMaterialItem> materialsBreakdown;
  final String urgency; // emergency | today | scheduled | maintenance_contract
  final String? maintenancePackageId;
  final Map<String, double> priceBreakdown;
  final bool warranty12MonthsIncluded;

  const HandymanBookingPreferences({
    this.punchList = const [],
    this.aiPhotoDiagnosis,
    this.problemDescription = '',
    this.propertyInfo = const HandymanPropertyInfo(),
    this.materialsOption = 'provider_buys',
    this.estimatedMaterialsCost = 0,
    this.materialsBreakdown = const [],
    this.urgency = 'today',
    this.maintenancePackageId,
    this.priceBreakdown = const {},
    this.warranty12MonthsIncluded = true,
  });

  Map<String, dynamic> toMap() => {
        'punchList': punchList.map((p) => p.toMap()).toList(),
        if (aiPhotoDiagnosis != null)
          'aiPhotoDiagnosis': aiPhotoDiagnosis!.toMap(),
        'problemDescription': problemDescription,
        'propertyInfo': propertyInfo.toMap(),
        'materialsOption': materialsOption,
        'estimatedMaterialsCost': estimatedMaterialsCost,
        'materialsBreakdown':
            materialsBreakdown.map((m) => m.toMap()).toList(),
        'urgency': urgency,
        if (maintenancePackageId != null)
          'maintenancePackageId': maintenancePackageId,
        'priceBreakdown': priceBreakdown,
        'warranty12MonthsIncluded': warranty12MonthsIncluded,
      };
}

class HandymanPunchListItem {
  final String serviceId;
  final String nameHe;
  final String icon;
  final int estimatedMinutes;
  final double price;
  final int priority;

  const HandymanPunchListItem({
    required this.serviceId,
    required this.nameHe,
    required this.icon,
    required this.estimatedMinutes,
    required this.price,
    required this.priority,
  });

  Map<String, dynamic> toMap() => {
        'serviceId': serviceId,
        'nameHe': nameHe,
        'icon': icon,
        'estimatedMinutes': estimatedMinutes,
        'price': price,
        'priority': priority,
      };
}

class HandymanAiDiagnosis {
  final List<String> photoUrls;
  final String identifiedProblem;
  final double confidence;
  final String aiAnalysis;
  final String category;
  final int estimatedDurationMinutes;
  final double estimatedPrice;
  final double estimatedMaterialsCost;
  final List<HandymanMaterialItem> recommendedMaterials;
  final String urgencyLevel;
  final bool clientApproved;

  const HandymanAiDiagnosis({
    this.photoUrls = const [],
    this.identifiedProblem = '',
    this.confidence = 0,
    this.aiAnalysis = '',
    this.category = 'other',
    this.estimatedDurationMinutes = 60,
    this.estimatedPrice = 0,
    this.estimatedMaterialsCost = 0,
    this.recommendedMaterials = const [],
    this.urgencyLevel = 'medium',
    this.clientApproved = false,
  });

  Map<String, dynamic> toMap() => {
        'photoUrls': photoUrls,
        'identifiedProblem': identifiedProblem,
        'confidence': confidence,
        'aiAnalysis': aiAnalysis,
        'category': category,
        'estimatedDurationMinutes': estimatedDurationMinutes,
        'estimatedPrice': estimatedPrice,
        'estimatedMaterialsCost': estimatedMaterialsCost,
        'recommendedMaterials':
            recommendedMaterials.map((m) => m.toMap()).toList(),
        'urgencyLevel': urgencyLevel,
        'clientApproved': clientApproved,
      };

  factory HandymanAiDiagnosis.fromJson(Map<String, dynamic>? raw) {
    if (raw == null) return const HandymanAiDiagnosis();
    return HandymanAiDiagnosis(
      photoUrls:
          (raw['photoUrls'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      identifiedProblem: raw['identifiedProblem'] as String? ?? '',
      confidence: (raw['confidence'] as num?)?.toDouble() ?? 0,
      aiAnalysis: raw['aiAnalysis'] as String? ?? '',
      category: raw['category'] as String? ?? 'other',
      estimatedDurationMinutes:
          (raw['estimatedDurationMinutes'] as num?)?.toInt() ?? 60,
      estimatedPrice: (raw['estimatedPrice'] as num?)?.toDouble() ?? 0,
      estimatedMaterialsCost:
          (raw['estimatedMaterialsCost'] as num?)?.toDouble() ?? 0,
      recommendedMaterials: (raw['recommendedMaterials'] as List?)
              ?.whereType<Map>()
              .map((m) =>
                  HandymanMaterialItem.fromMap(Map<String, dynamic>.from(m)))
              .toList() ??
          const [],
      urgencyLevel: raw['urgencyLevel'] as String? ?? 'medium',
      clientApproved: raw['clientApproved'] as bool? ?? false,
    );
  }

  HandymanAiDiagnosis copyWith({bool? clientApproved}) => HandymanAiDiagnosis(
        photoUrls: photoUrls,
        identifiedProblem: identifiedProblem,
        confidence: confidence,
        aiAnalysis: aiAnalysis,
        category: category,
        estimatedDurationMinutes: estimatedDurationMinutes,
        estimatedPrice: estimatedPrice,
        estimatedMaterialsCost: estimatedMaterialsCost,
        recommendedMaterials: recommendedMaterials,
        urgencyLevel: urgencyLevel,
        clientApproved: clientApproved ?? this.clientApproved,
      );
}

class HandymanMaterialItem {
  final String name;
  final double price;
  final String? details;

  const HandymanMaterialItem({
    required this.name,
    required this.price,
    this.details,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'price': price,
        if (details != null) 'details': details,
      };

  factory HandymanMaterialItem.fromMap(Map<String, dynamic> raw) {
    return HandymanMaterialItem(
      name: raw['name'] as String? ?? '',
      price: (raw['price'] as num?)?.toDouble() ?? 0,
      details: raw['details'] as String?,
    );
  }
}

class HandymanPropertyInfo {
  final String? ceilingHeight; // "2.6m" etc.
  final String? wallType; // drywall | concrete | ...
  final int? floor;
  final bool hasElevator;
  final bool parkingAvailable;

  const HandymanPropertyInfo({
    this.ceilingHeight,
    this.wallType,
    this.floor,
    this.hasElevator = false,
    this.parkingAvailable = false,
  });

  Map<String, dynamic> toMap() => {
        if (ceilingHeight != null) 'ceilingHeight': ceilingHeight,
        if (wallType != null) 'wallType': wallType,
        if (floor != null) 'floor': floor,
        'hasElevator': hasElevator,
        'parkingAvailable': parkingAvailable,
      };

  HandymanPropertyInfo copyWith({
    String? ceilingHeight,
    String? wallType,
    int? floor,
    bool? hasElevator,
    bool? parkingAvailable,
  }) =>
      HandymanPropertyInfo(
        ceilingHeight: ceilingHeight ?? this.ceilingHeight,
        wallType: wallType ?? this.wallType,
        floor: floor ?? this.floor,
        hasElevator: hasElevator ?? this.hasElevator,
        parkingAvailable: parkingAvailable ?? this.parkingAvailable,
      );
}
