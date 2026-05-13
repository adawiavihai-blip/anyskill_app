/// Delivery CSM (Category-Specific Module) v15.x
///
/// Data model for the "משלוחים" (delivery) sub-category.
/// Stored at `users/{uid}.deliveryProfile` as a nested Map.
class DeliveryProfile {
  final List<DeliveryDocument> documents;
  final List<DeliveryVehicle> vehicles;
  final List<String> deliveryTypes;
  final List<String> customerTypes;
  final DeliveryAvailability availability;
  final DeliveryServiceArea serviceArea;
  final DeliveryPricing pricing;
  final CourierRules rules;
  final List<BusinessPackage> businessPackages;

  const DeliveryProfile({
    this.documents = const [],
    this.vehicles = const [],
    this.deliveryTypes = const [],
    this.customerTypes = const [],
    this.availability = const DeliveryAvailability(),
    this.serviceArea = const DeliveryServiceArea(),
    this.pricing = const DeliveryPricing(),
    this.rules = const CourierRules(),
    this.businessPackages = const [],
  });

  factory DeliveryProfile.fromMap(Map<String, dynamic> map) {
    return DeliveryProfile(
      documents: (map['documents'] as List? ?? [])
          .whereType<Map>()
          .map((e) => DeliveryDocument.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      vehicles: (map['vehicles'] as List? ?? [])
          .whereType<Map>()
          .map((e) => DeliveryVehicle.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      deliveryTypes: List<String>.from(map['deliveryTypes'] ?? []),
      customerTypes: List<String>.from(map['customerTypes'] ?? []),
      availability: DeliveryAvailability.fromMap(
          Map<String, dynamic>.from(map['availability'] ?? {})),
      serviceArea: DeliveryServiceArea.fromMap(
          Map<String, dynamic>.from(map['serviceArea'] ?? {})),
      pricing: DeliveryPricing.fromMap(
          Map<String, dynamic>.from(map['pricing'] ?? {})),
      rules: CourierRules.fromMap(
          Map<String, dynamic>.from(map['rules'] ?? {})),
      businessPackages: (map['businessPackages'] as List? ?? [])
          .whereType<Map>()
          .map((e) => BusinessPackage.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'documents': documents.map((d) => d.toMap()).toList(),
        'vehicles': vehicles.map((v) => v.toMap()).toList(),
        'deliveryTypes': deliveryTypes,
        'customerTypes': customerTypes,
        'availability': availability.toMap(),
        'serviceArea': serviceArea.toMap(),
        'pricing': pricing.toMap(),
        'rules': rules.toMap(),
        'businessPackages':
            businessPackages.map((p) => p.toMap()).toList(),
      };

  DeliveryProfile copyWith({
    List<DeliveryDocument>? documents,
    List<DeliveryVehicle>? vehicles,
    List<String>? deliveryTypes,
    List<String>? customerTypes,
    DeliveryAvailability? availability,
    DeliveryServiceArea? serviceArea,
    DeliveryPricing? pricing,
    CourierRules? rules,
    List<BusinessPackage>? businessPackages,
  }) =>
      DeliveryProfile(
        documents: documents ?? this.documents,
        vehicles: vehicles ?? this.vehicles,
        deliveryTypes: deliveryTypes ?? this.deliveryTypes,
        customerTypes: customerTypes ?? this.customerTypes,
        availability: availability ?? this.availability,
        serviceArea: serviceArea ?? this.serviceArea,
        pricing: pricing ?? this.pricing,
        rules: rules ?? this.rules,
        businessPackages: businessPackages ?? this.businessPackages,
      );
}

class DeliveryDocument {
  final String id;
  final String type; // id_card | driver_license | vehicle_insurance
  final String nameHe;
  final bool verified;
  final String? verifiedAt;
  final String? validUntil;
  final List<String> classes; // e.g. driver license classes ["B", "A2"]

  const DeliveryDocument({
    required this.id,
    required this.type,
    required this.nameHe,
    this.verified = false,
    this.verifiedAt,
    this.validUntil,
    this.classes = const [],
  });

  factory DeliveryDocument.fromMap(Map<String, dynamic> map) =>
      DeliveryDocument(
        id: map['id'] as String? ?? '',
        type: map['type'] as String? ?? '',
        nameHe: map['nameHe'] as String? ?? '',
        verified: map['verified'] as bool? ?? false,
        verifiedAt: map['verifiedAt'] as String?,
        validUntil: map['validUntil'] as String?,
        classes: List<String>.from(map['classes'] ?? []),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'nameHe': nameHe,
        'verified': verified,
        if (verifiedAt != null) 'verifiedAt': verifiedAt,
        if (validUntil != null) 'validUntil': validUntil,
        if (classes.isNotEmpty) 'classes': classes,
      };

  DeliveryDocument copyWith({
    String? id,
    String? type,
    String? nameHe,
    bool? verified,
    String? verifiedAt,
    String? validUntil,
    List<String>? classes,
  }) =>
      DeliveryDocument(
        id: id ?? this.id,
        type: type ?? this.type,
        nameHe: nameHe ?? this.nameHe,
        verified: verified ?? this.verified,
        verifiedAt: verifiedAt ?? this.verifiedAt,
        validUntil: validUntil ?? this.validUntil,
        classes: classes ?? this.classes,
      );
}

class DeliveryVehicle {
  final String id;
  final String type; // scooter | car
  final String nameHe;
  final String manufacturer;
  final int year;
  final int maxWeightKg;
  final List<String> photos;
  final bool insuranceVerified;
  final bool enabled;

  const DeliveryVehicle({
    required this.id,
    required this.type,
    required this.nameHe,
    this.manufacturer = '',
    this.year = 0,
    this.maxWeightKg = 0,
    this.photos = const [],
    this.insuranceVerified = false,
    this.enabled = true,
  });

  factory DeliveryVehicle.fromMap(Map<String, dynamic> map) => DeliveryVehicle(
        id: map['id'] as String? ?? '',
        type: map['type'] as String? ?? '',
        nameHe: map['nameHe'] as String? ?? '',
        manufacturer: map['manufacturer'] as String? ?? '',
        year: (map['year'] as num?)?.toInt() ?? 0,
        maxWeightKg: (map['maxWeightKg'] as num?)?.toInt() ?? 0,
        photos: List<String>.from(map['photos'] ?? []),
        insuranceVerified: map['insuranceVerified'] as bool? ?? false,
        enabled: map['enabled'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'nameHe': nameHe,
        'manufacturer': manufacturer,
        'year': year,
        'maxWeightKg': maxWeightKg,
        'photos': photos,
        'insuranceVerified': insuranceVerified,
        'enabled': enabled,
      };

  DeliveryVehicle copyWith({
    String? id,
    String? type,
    String? nameHe,
    String? manufacturer,
    int? year,
    int? maxWeightKg,
    List<String>? photos,
    bool? insuranceVerified,
    bool? enabled,
  }) =>
      DeliveryVehicle(
        id: id ?? this.id,
        type: type ?? this.type,
        nameHe: nameHe ?? this.nameHe,
        manufacturer: manufacturer ?? this.manufacturer,
        year: year ?? this.year,
        maxWeightKg: maxWeightKg ?? this.maxWeightKg,
        photos: photos ?? this.photos,
        insuranceVerified: insuranceVerified ?? this.insuranceVerified,
        enabled: enabled ?? this.enabled,
      );
}

class DeliveryAvailability {
  final DeliveryImmediateOption immediate;
  final bool regularEnabled;
  final bool scheduledEnabled;

  const DeliveryAvailability({
    this.immediate = const DeliveryImmediateOption(),
    this.regularEnabled = true,
    this.scheduledEnabled = true,
  });

  factory DeliveryAvailability.fromMap(Map<String, dynamic> map) =>
      DeliveryAvailability(
        immediate: DeliveryImmediateOption.fromMap(
            Map<String, dynamic>.from(map['immediate'] ?? {})),
        regularEnabled:
            (map['regular'] as Map?)?['enabled'] as bool? ?? true,
        scheduledEnabled:
            (map['scheduled'] as Map?)?['enabled'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {
        'immediate': immediate.toMap(),
        'regular': {'enabled': regularEnabled},
        'scheduled': {'enabled': scheduledEnabled},
      };
}

class DeliveryImmediateOption {
  final bool enabled;
  final int surcharge;

  const DeliveryImmediateOption({
    this.enabled = true,
    this.surcharge = 25,
  });

  factory DeliveryImmediateOption.fromMap(Map<String, dynamic> map) =>
      DeliveryImmediateOption(
        enabled: map['enabled'] as bool? ?? true,
        surcharge: (map['surcharge'] as num?)?.toInt() ?? 25,
      );

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'surcharge': surcharge,
      };
}

class DeliveryServiceArea {
  final String baseLocation;
  final double? baseLat;
  final double? baseLng;
  final List<String> coverageCities;

  const DeliveryServiceArea({
    this.baseLocation = '',
    this.baseLat,
    this.baseLng,
    this.coverageCities = const [],
  });

  factory DeliveryServiceArea.fromMap(Map<String, dynamic> map) {
    final geo = map['baseLocationGeo'] as Map?;
    return DeliveryServiceArea(
      baseLocation: map['baseLocation'] as String? ?? '',
      baseLat: (geo?['lat'] as num?)?.toDouble(),
      baseLng: (geo?['lng'] as num?)?.toDouble(),
      coverageCities: List<String>.from(map['coverageCities'] ?? []),
    );
  }

  Map<String, dynamic> toMap() => {
        'baseLocation': baseLocation,
        if (baseLat != null && baseLng != null)
          'baseLocationGeo': {'lat': baseLat, 'lng': baseLng},
        'coverageCities': coverageCities,
      };
}

class DeliveryPricing {
  final int documents;
  final int smallPackage;
  final int mediumPackage;
  final int largePackage;
  final int flowers;
  final int cakes;
  final double perKmAfter5;

  const DeliveryPricing({
    this.documents = 35,
    this.smallPackage = 45,
    this.mediumPackage = 65,
    this.largePackage = 90,
    this.flowers = 50,
    this.cakes = 55,
    this.perKmAfter5 = 3.5,
  });

  factory DeliveryPricing.fromMap(Map<String, dynamic> map) => DeliveryPricing(
        documents: (map['documents'] as num?)?.toInt() ?? 35,
        smallPackage: (map['small_package'] as num?)?.toInt() ?? 45,
        mediumPackage: (map['medium_package'] as num?)?.toInt() ?? 65,
        largePackage: (map['large_package'] as num?)?.toInt() ?? 90,
        flowers: (map['flowers'] as num?)?.toInt() ?? 50,
        cakes: (map['cakes'] as num?)?.toInt() ?? 55,
        perKmAfter5: (map['perKmAfter5'] as num?)?.toDouble() ?? 3.5,
      );

  Map<String, dynamic> toMap() => {
        'documents': documents,
        'small_package': smallPackage,
        'medium_package': mediumPackage,
        'large_package': largePackage,
        'flowers': flowers,
        'cakes': cakes,
        'perKmAfter5': perKmAfter5,
      };

  int priceFor(String packageType) {
    switch (packageType) {
      case 'documents':
        return documents;
      case 'small_package':
        return smallPackage;
      case 'medium_package':
        return mediumPackage;
      case 'large_package':
        return largePackage;
      case 'flowers':
        return flowers;
      case 'cakes':
        return cakes;
    }
    return smallPackage;
  }
}

class CourierRules {
  final List<StructuredCourierRule> structuredRules;
  final String customRules;

  const CourierRules({
    this.structuredRules = const [],
    this.customRules = '',
  });

  factory CourierRules.fromMap(Map<String, dynamic> map) => CourierRules(
        structuredRules: (map['structuredRules'] as List? ?? [])
            .whereType<Map>()
            .map((e) =>
                StructuredCourierRule.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
        customRules: map['customRules'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'structuredRules':
            structuredRules.map((r) => r.toMap()).toList(),
        'customRules': customRules,
      };
}

class StructuredCourierRule {
  final String id;
  final String type;
  final String icon;
  final String titleHe;
  final String descHe;
  final bool enabled;
  final String color;

  const StructuredCourierRule({
    required this.id,
    required this.type,
    required this.icon,
    required this.titleHe,
    required this.descHe,
    this.enabled = false,
    this.color = 'grey',
  });

  factory StructuredCourierRule.fromMap(Map<String, dynamic> map) =>
      StructuredCourierRule(
        id: map['id'] as String? ?? '',
        type: map['type'] as String? ?? '',
        icon: map['icon'] as String? ?? '',
        titleHe: map['titleHe'] as String? ?? '',
        descHe: map['descHe'] as String? ?? '',
        enabled: map['enabled'] as bool? ?? false,
        color: map['color'] as String? ?? 'grey',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'icon': icon,
        'titleHe': titleHe,
        'descHe': descHe,
        'enabled': enabled,
        'color': color,
      };
}

class BusinessPackage {
  final String id;
  final String nameHe;
  final int deliveriesPerMonth;
  final int monthlyPrice;
  final bool enabled;
  final int activeCustomers;

  const BusinessPackage({
    required this.id,
    required this.nameHe,
    required this.deliveriesPerMonth,
    required this.monthlyPrice,
    this.enabled = true,
    this.activeCustomers = 0,
  });

  factory BusinessPackage.fromMap(Map<String, dynamic> map) => BusinessPackage(
        id: map['id'] as String? ?? '',
        nameHe: map['nameHe'] as String? ?? '',
        deliveriesPerMonth:
            (map['deliveriesPerMonth'] as num?)?.toInt() ?? 0,
        monthlyPrice: (map['monthlyPrice'] as num?)?.toInt() ?? 0,
        enabled: map['enabled'] as bool? ?? true,
        activeCustomers: (map['activeCustomers'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'nameHe': nameHe,
        'deliveriesPerMonth': deliveriesPerMonth,
        'monthlyPrice': monthlyPrice,
        'enabled': enabled,
        'activeCustomers': activeCustomers,
      };
}

/// Category detector — matches 'משלוחים', 'delivery', 'שליחים', 'courier'.
bool isDeliveryCategory(String? serviceType) {
  if (serviceType == null) return false;
  final lower = serviceType.trim().toLowerCase();
  return lower == 'משלוחים' ||
      lower == 'delivery' ||
      lower == 'שליחים' ||
      lower == 'courier' ||
      lower.contains('משלוח') ||
      lower.contains('שליח') ||
      lower.contains('deliver') ||
      lower.contains('courier');
}
