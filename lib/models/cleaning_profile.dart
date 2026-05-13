// Cleaning Category-Specific Module — provider profile model.
// Follows the same pattern as DeliveryProfile (§33) and PestControlProfile (§32).
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/firestore_map.dart';

/// Detects whether a given serviceType (sub-category name or id) is the
/// cleaning category. Matches Hebrew "נקיון"/"ניקיון" and English "cleaning".
bool isCleaningCategory(String? serviceType) {
  if (serviceType == null) return false;
  final lower = serviceType.trim().toLowerCase();
  if (lower.isEmpty) return false;
  return lower == 'נקיון' ||
      lower == 'ניקיון' ||
      lower == 'cleaning' ||
      lower.contains('נקי') ||
      lower.contains('cleaning') ||
      lower.contains('cleaner');
}

/// Main provider-side cleaning profile stored at users/{uid}.cleaningProfile.
class CleaningProfile {
  final CleaningVerifications verifications;
  final List<String> cleaningTypes;
  final List<String> customerTypes;
  final CleaningEcoMode ecoMode;
  final List<CleaningChecklistCategory> baseChecklist;
  final CleaningPricing pricing;
  final CleaningRecurringDiscounts recurringDiscounts;
  final CleaningQualityGuarantee qualityGuarantee;
  final CleaningServiceArea serviceArea;
  final List<CleaningBusinessPackage> businessPackages;

  const CleaningProfile({
    this.verifications = const CleaningVerifications(),
    this.cleaningTypes = const [],
    this.customerTypes = const [],
    this.ecoMode = const CleaningEcoMode(),
    this.baseChecklist = const [],
    this.pricing = const CleaningPricing(),
    this.recurringDiscounts = const CleaningRecurringDiscounts(),
    this.qualityGuarantee = const CleaningQualityGuarantee(),
    this.serviceArea = const CleaningServiceArea(),
    this.businessPackages = const [],
  });

  Map<String, dynamic> toMap() => {
        'verifications': verifications.toMap(),
        'cleaningTypes': cleaningTypes,
        'customerTypes': customerTypes,
        'ecoMode': ecoMode.toMap(),
        'baseChecklist': baseChecklist.map((c) => c.toMap()).toList(),
        'pricing': pricing.toMap(),
        'recurringDiscounts': recurringDiscounts.toMap(),
        'qualityGuarantee': qualityGuarantee.toMap(),
        'serviceArea': serviceArea.toMap(),
        'businessPackages': businessPackages.map((p) => p.toMap()).toList(),
      };

  factory CleaningProfile.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const CleaningProfile();
    return CleaningProfile(
      verifications:
          CleaningVerifications.fromMap(safeMap(raw['verifications'])),
      cleaningTypes:
          (raw['cleaningTypes'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      customerTypes:
          (raw['customerTypes'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      ecoMode: CleaningEcoMode.fromMap(safeMap(raw['ecoMode'])),
      baseChecklist: (raw['baseChecklist'] as List?)
              ?.whereType<Map>()
              .map((m) => CleaningChecklistCategory.fromMap(
                  Map<String, dynamic>.from(m)))
              .toList() ??
          const [],
      pricing: CleaningPricing.fromMap(safeMap(raw['pricing'])),
      recurringDiscounts: CleaningRecurringDiscounts.fromMap(
          safeMap(raw['recurringDiscounts'])),
      qualityGuarantee:
          CleaningQualityGuarantee.fromMap(safeMap(raw['qualityGuarantee'])),
      serviceArea: CleaningServiceArea.fromMap(safeMap(raw['serviceArea'])),
      businessPackages: (raw['businessPackages'] as List?)
              ?.whereType<Map>()
              .map((m) =>
                  CleaningBusinessPackage.fromMap(Map<String, dynamic>.from(m)))
              .toList() ??
          const [],
    );
  }

  CleaningProfile copyWith({
    CleaningVerifications? verifications,
    List<String>? cleaningTypes,
    List<String>? customerTypes,
    CleaningEcoMode? ecoMode,
    List<CleaningChecklistCategory>? baseChecklist,
    CleaningPricing? pricing,
    CleaningRecurringDiscounts? recurringDiscounts,
    CleaningQualityGuarantee? qualityGuarantee,
    CleaningServiceArea? serviceArea,
    List<CleaningBusinessPackage>? businessPackages,
  }) =>
      CleaningProfile(
        verifications: verifications ?? this.verifications,
        cleaningTypes: cleaningTypes ?? this.cleaningTypes,
        customerTypes: customerTypes ?? this.customerTypes,
        ecoMode: ecoMode ?? this.ecoMode,
        baseChecklist: baseChecklist ?? this.baseChecklist,
        pricing: pricing ?? this.pricing,
        recurringDiscounts: recurringDiscounts ?? this.recurringDiscounts,
        qualityGuarantee: qualityGuarantee ?? this.qualityGuarantee,
        serviceArea: serviceArea ?? this.serviceArea,
        businessPackages: businessPackages ?? this.businessPackages,
      );
}

class CleaningVerifications {
  final bool idVerified;
  final DateTime? idVerifiedAt;
  final bool backgroundChecked;
  final DateTime? backgroundCheckedAt;
  final int referencesCount;
  final bool referencesVerified;
  final int insuranceAmount;
  final String insuranceProvider;
  final String insuranceValidUntil;

  const CleaningVerifications({
    this.idVerified = false,
    this.idVerifiedAt,
    this.backgroundChecked = false,
    this.backgroundCheckedAt,
    this.referencesCount = 0,
    this.referencesVerified = false,
    this.insuranceAmount = 10000,
    this.insuranceProvider = '',
    this.insuranceValidUntil = '',
  });

  bool get isComplete =>
      idVerified && backgroundChecked && referencesCount >= 3;

  Map<String, dynamic> toMap() => {
        'idVerified': idVerified,
        if (idVerifiedAt != null)
          'idVerifiedAt': Timestamp.fromDate(idVerifiedAt!),
        'backgroundChecked': backgroundChecked,
        if (backgroundCheckedAt != null)
          'backgroundCheckedAt': Timestamp.fromDate(backgroundCheckedAt!),
        'referencesCount': referencesCount,
        'referencesVerified': referencesVerified,
        'insuranceAmount': insuranceAmount,
        'insuranceProvider': insuranceProvider,
        'insuranceValidUntil': insuranceValidUntil,
      };

  factory CleaningVerifications.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const CleaningVerifications();
    DateTime? ts(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    return CleaningVerifications(
      idVerified: raw['idVerified'] == true,
      idVerifiedAt: ts(raw['idVerifiedAt']),
      backgroundChecked: raw['backgroundChecked'] == true,
      backgroundCheckedAt: ts(raw['backgroundCheckedAt']),
      referencesCount: (raw['referencesCount'] as num?)?.toInt() ?? 0,
      referencesVerified: raw['referencesVerified'] == true,
      insuranceAmount: (raw['insuranceAmount'] as num?)?.toInt() ?? 10000,
      insuranceProvider: raw['insuranceProvider']?.toString() ?? '',
      insuranceValidUntil: raw['insuranceValidUntil']?.toString() ?? '',
    );
  }

  CleaningVerifications copyWith({
    bool? idVerified,
    DateTime? idVerifiedAt,
    bool? backgroundChecked,
    DateTime? backgroundCheckedAt,
    int? referencesCount,
    bool? referencesVerified,
    int? insuranceAmount,
    String? insuranceProvider,
    String? insuranceValidUntil,
  }) =>
      CleaningVerifications(
        idVerified: idVerified ?? this.idVerified,
        idVerifiedAt: idVerifiedAt ?? this.idVerifiedAt,
        backgroundChecked: backgroundChecked ?? this.backgroundChecked,
        backgroundCheckedAt: backgroundCheckedAt ?? this.backgroundCheckedAt,
        referencesCount: referencesCount ?? this.referencesCount,
        referencesVerified: referencesVerified ?? this.referencesVerified,
        insuranceAmount: insuranceAmount ?? this.insuranceAmount,
        insuranceProvider: insuranceProvider ?? this.insuranceProvider,
        insuranceValidUntil: insuranceValidUntil ?? this.insuranceValidUntil,
      );
}

class CleaningEcoMode {
  final bool enabled;
  final int surcharge;
  final String certified;

  const CleaningEcoMode({
    this.enabled = false,
    this.surcharge = 25,
    this.certified = 'EcoCert',
  });

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'surcharge': surcharge,
        'certified': certified,
      };

  factory CleaningEcoMode.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const CleaningEcoMode();
    return CleaningEcoMode(
      enabled: raw['enabled'] == true,
      surcharge: (raw['surcharge'] as num?)?.toInt() ?? 25,
      certified: raw['certified']?.toString() ?? 'EcoCert',
    );
  }
}

class CleaningChecklistCategory {
  final String categoryId;
  final String categoryNameHe;
  final String categoryIcon;
  final List<CleaningTask> tasks;

  const CleaningChecklistCategory({
    required this.categoryId,
    required this.categoryNameHe,
    required this.categoryIcon,
    this.tasks = const [],
  });

  Map<String, dynamic> toMap() => {
        'categoryId': categoryId,
        'categoryNameHe': categoryNameHe,
        'categoryIcon': categoryIcon,
        'tasks': tasks.map((t) => t.toMap()).toList(),
      };

  factory CleaningChecklistCategory.fromMap(Map<String, dynamic> raw) {
    return CleaningChecklistCategory(
      categoryId: raw['categoryId']?.toString() ?? '',
      categoryNameHe: raw['categoryNameHe']?.toString() ?? '',
      categoryIcon: raw['categoryIcon']?.toString() ?? '🧹',
      tasks: (raw['tasks'] as List?)
              ?.whereType<Map>()
              .map((m) => CleaningTask.fromMap(Map<String, dynamic>.from(m)))
              .toList() ??
          const [],
    );
  }

  CleaningChecklistCategory copyWith({
    String? categoryNameHe,
    String? categoryIcon,
    List<CleaningTask>? tasks,
  }) =>
      CleaningChecklistCategory(
        categoryId: categoryId,
        categoryNameHe: categoryNameHe ?? this.categoryNameHe,
        categoryIcon: categoryIcon ?? this.categoryIcon,
        tasks: tasks ?? this.tasks,
      );
}

class CleaningTask {
  final String id;
  final String nameHe;
  final bool withPhoto;
  final int? addOnAmount;

  const CleaningTask({
    required this.id,
    required this.nameHe,
    this.withPhoto = false,
    this.addOnAmount,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'nameHe': nameHe,
        'withPhoto': withPhoto,
        if (addOnAmount != null)
          'addOn': {'amount': addOnAmount, 'currency': 'ILS'},
      };

  factory CleaningTask.fromMap(Map<String, dynamic> raw) {
    int? addOn;
    final addOnRaw = raw['addOn'];
    if (addOnRaw is Map) {
      addOn = (addOnRaw['amount'] as num?)?.toInt();
    }
    return CleaningTask(
      id: raw['id']?.toString() ?? '',
      nameHe: raw['nameHe']?.toString() ?? '',
      withPhoto: raw['withPhoto'] == true,
      addOnAmount: addOn,
    );
  }

  CleaningTask copyWith({
    String? nameHe,
    bool? withPhoto,
    int? addOnAmount,
    bool clearAddOn = false,
  }) =>
      CleaningTask(
        id: id,
        nameHe: nameHe ?? this.nameHe,
        withPhoto: withPhoto ?? this.withPhoto,
        addOnAmount: clearAddOn ? null : (addOnAmount ?? this.addOnAmount),
      );
}

class CleaningPricing {
  /// Base price per size tier for regular_home.
  final Map<String, int> regularHome;

  /// Multiplier per cleaningType (e.g., deep_renovation = 2.0, airbnb = 0.8).
  final Map<String, double> typeMultipliers;

  /// Add-on prices by id.
  final Map<String, int> addOns;

  const CleaningPricing({
    this.regularHome = const {
      'upTo60sqm': 180,
      '60to100sqm': 240,
      '100to150sqm': 320,
      'over150sqm': 420,
    },
    this.typeMultipliers = const {
      'regular_home': 1.0,
      'deep_renovation': 2.0,
      'airbnb': 0.8,
      'office': 1.5,
      'store': 1.3,
      'event': 1.7,
    },
    this.addOns = const {
      'oven_inside': 40,
      'fridge_inside': 30,
      'windows_outside': 60,
      'sofa_steam': 120,
    },
  });

  Map<String, dynamic> toMap() => {
        'regular_home': regularHome,
        'typeMultipliers': typeMultipliers,
        'addOns': addOns,
      };

  factory CleaningPricing.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const CleaningPricing();
    Map<String, int> intMap(dynamic v, Map<String, int> fallback) {
      if (v is! Map) return fallback;
      final out = <String, int>{};
      v.forEach((k, val) {
        if (val is num) out[k.toString()] = val.toInt();
      });
      return out.isEmpty ? fallback : out;
    }

    Map<String, double> dblMap(dynamic v, Map<String, double> fallback) {
      if (v is! Map) return fallback;
      final out = <String, double>{};
      v.forEach((k, val) {
        if (val is num) out[k.toString()] = val.toDouble();
      });
      return out.isEmpty ? fallback : out;
    }

    const defaults = CleaningPricing();
    return CleaningPricing(
      regularHome: intMap(raw['regular_home'], defaults.regularHome),
      typeMultipliers:
          dblMap(raw['typeMultipliers'], defaults.typeMultipliers),
      addOns: intMap(raw['addOns'], defaults.addOns),
    );
  }

  /// Tier key for a given square-meter count.
  static String tierFromSqm(int sqm) {
    if (sqm <= 60) return 'upTo60sqm';
    if (sqm <= 100) return '60to100sqm';
    if (sqm <= 150) return '100to150sqm';
    return 'over150sqm';
  }

  /// Base price for (cleaningType, squareMeters).
  double basePriceFor(String cleaningType, int sqm) {
    final tier = tierFromSqm(sqm);
    final regularBase = (regularHome[tier] ?? 240).toDouble();
    final multiplier = typeMultipliers[cleaningType] ?? 1.0;
    return regularBase * multiplier;
  }

  CleaningPricing copyWith({
    Map<String, int>? regularHome,
    Map<String, double>? typeMultipliers,
    Map<String, int>? addOns,
  }) =>
      CleaningPricing(
        regularHome: regularHome ?? this.regularHome,
        typeMultipliers: typeMultipliers ?? this.typeMultipliers,
        addOns: addOns ?? this.addOns,
      );
}

class CleaningRecurringDiscounts {
  final int weekly;
  final int biweekly;
  final int monthly;

  const CleaningRecurringDiscounts({
    this.weekly = 15,
    this.biweekly = 10,
    this.monthly = 5,
  });

  int discountFor(String frequency) {
    switch (frequency) {
      case 'weekly':
        return weekly;
      case 'biweekly':
        return biweekly;
      case 'monthly':
        return monthly;
    }
    return 0;
  }

  Map<String, dynamic> toMap() =>
      {'weekly': weekly, 'biweekly': biweekly, 'monthly': monthly};

  factory CleaningRecurringDiscounts.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const CleaningRecurringDiscounts();
    return CleaningRecurringDiscounts(
      weekly: (raw['weekly'] as num?)?.toInt() ?? 15,
      biweekly: (raw['biweekly'] as num?)?.toInt() ?? 10,
      monthly: (raw['monthly'] as num?)?.toInt() ?? 5,
    );
  }
}

class CleaningQualityGuarantee {
  final bool enabled;
  final int reportWindowHours;
  final bool reCleanFree;
  final bool fullRefund;

  const CleaningQualityGuarantee({
    this.enabled = true,
    this.reportWindowHours = 24,
    this.reCleanFree = true,
    this.fullRefund = true,
  });

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'reportWindowHours': reportWindowHours,
        'reCleanFree': reCleanFree,
        'fullRefund': fullRefund,
      };

  factory CleaningQualityGuarantee.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const CleaningQualityGuarantee();
    return CleaningQualityGuarantee(
      enabled: raw['enabled'] != false,
      reportWindowHours:
          (raw['reportWindowHours'] as num?)?.toInt() ?? 24,
      reCleanFree: raw['reCleanFree'] != false,
      fullRefund: raw['fullRefund'] != false,
    );
  }
}

class CleaningServiceArea {
  final List<String> cities;
  final Map<String, bool> workHours;

  const CleaningServiceArea({
    this.cities = const [],
    this.workHours = const {
      'morning_7_12': true,
      'afternoon_12_17': true,
      'evening_17_22': false,
      'weekend': false,
    },
  });

  Map<String, dynamic> toMap() =>
      {'cities': cities, 'workHours': workHours};

  factory CleaningServiceArea.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const CleaningServiceArea();
    final hours = <String, bool>{};
    final h = raw['workHours'];
    if (h is Map) {
      h.forEach((k, v) => hours[k.toString()] = v == true);
    }
    return CleaningServiceArea(
      cities:
          (raw['cities'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      workHours: hours.isEmpty ? const CleaningServiceArea().workHours : hours,
    );
  }

  CleaningServiceArea copyWith({
    List<String>? cities,
    Map<String, bool>? workHours,
  }) =>
      CleaningServiceArea(
        cities: cities ?? this.cities,
        workHours: workHours ?? this.workHours,
      );
}

class CleaningBusinessPackage {
  final String id;
  final String nameHe;
  final int visitsPerMonth;
  final int monthlyPrice;
  final bool enabled;
  final int activeCustomers;

  const CleaningBusinessPackage({
    required this.id,
    required this.nameHe,
    required this.visitsPerMonth,
    required this.monthlyPrice,
    this.enabled = true,
    this.activeCustomers = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'nameHe': nameHe,
        'visitsPerMonth': visitsPerMonth,
        'monthlyPrice': monthlyPrice,
        'enabled': enabled,
        'activeCustomers': activeCustomers,
      };

  factory CleaningBusinessPackage.fromMap(Map<String, dynamic> raw) {
    return CleaningBusinessPackage(
      id: raw['id']?.toString() ?? '',
      nameHe: raw['nameHe']?.toString() ?? '',
      visitsPerMonth: (raw['visitsPerMonth'] as num?)?.toInt() ?? 4,
      monthlyPrice: (raw['monthlyPrice'] as num?)?.toInt() ?? 0,
      enabled: raw['enabled'] != false,
      activeCustomers: (raw['activeCustomers'] as num?)?.toInt() ?? 0,
    );
  }

  CleaningBusinessPackage copyWith({
    String? nameHe,
    int? visitsPerMonth,
    int? monthlyPrice,
    bool? enabled,
    int? activeCustomers,
  }) =>
      CleaningBusinessPackage(
        id: id,
        nameHe: nameHe ?? this.nameHe,
        visitsPerMonth: visitsPerMonth ?? this.visitsPerMonth,
        monthlyPrice: monthlyPrice ?? this.monthlyPrice,
        enabled: enabled ?? this.enabled,
        activeCustomers: activeCustomers ?? this.activeCustomers,
      );
}
