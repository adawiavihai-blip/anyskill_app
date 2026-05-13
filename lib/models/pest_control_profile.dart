class PestControlProfile {
  final List<PestLicense> licenses;
  final List<String> pestTypes;
  final List<String> treatmentMethods;
  final List<String> customerTypes;
  final PestAvailability availability;
  final PestServiceArea serviceArea;
  final Map<String, int> basePricing;
  final PestWarranty warrantyAndService;
  final List<MaintenancePackage> maintenancePackages;
  final TreatmentInstructions treatmentInstructions;

  const PestControlProfile({
    this.licenses = const [],
    this.pestTypes = const [],
    this.treatmentMethods = const [],
    this.customerTypes = const [],
    this.availability = const PestAvailability(),
    this.serviceArea = const PestServiceArea(),
    this.basePricing = const {},
    this.warrantyAndService = const PestWarranty(),
    this.maintenancePackages = const [],
    this.treatmentInstructions = const TreatmentInstructions(),
  });

  factory PestControlProfile.fromMap(Map<String, dynamic> map) {
    return PestControlProfile(
      licenses: (map['licenses'] as List? ?? [])
          .map((e) => PestLicense.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      pestTypes: List<String>.from(map['pestTypes'] ?? []),
      treatmentMethods: List<String>.from(map['treatmentMethods'] ?? []),
      customerTypes: List<String>.from(map['customerTypes'] ?? []),
      availability: PestAvailability.fromMap(
          Map<String, dynamic>.from(map['availability'] ?? {})),
      serviceArea: PestServiceArea.fromMap(
          Map<String, dynamic>.from(map['serviceArea'] ?? {})),
      basePricing: Map<String, int>.from(map['basePricing'] ?? {}),
      warrantyAndService: PestWarranty.fromMap(
          Map<String, dynamic>.from(map['warrantyAndService'] ?? {})),
      maintenancePackages: (map['maintenancePackages'] as List? ?? [])
          .map((e) =>
              MaintenancePackage.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      treatmentInstructions: TreatmentInstructions.fromMap(
          Map<String, dynamic>.from(map['treatmentInstructions'] ?? {})),
    );
  }

  Map<String, dynamic> toMap() => {
        'licenses': licenses.map((l) => l.toMap()).toList(),
        'pestTypes': pestTypes,
        'treatmentMethods': treatmentMethods,
        'customerTypes': customerTypes,
        'availability': availability.toMap(),
        'serviceArea': serviceArea.toMap(),
        'basePricing': basePricing,
        'warrantyAndService': warrantyAndService.toMap(),
        'maintenancePackages':
            maintenancePackages.map((p) => p.toMap()).toList(),
        'treatmentInstructions': treatmentInstructions.toMap(),
      };

  PestControlProfile copyWith({
    List<PestLicense>? licenses,
    List<String>? pestTypes,
    List<String>? treatmentMethods,
    List<String>? customerTypes,
    PestAvailability? availability,
    PestServiceArea? serviceArea,
    Map<String, int>? basePricing,
    PestWarranty? warrantyAndService,
    List<MaintenancePackage>? maintenancePackages,
    TreatmentInstructions? treatmentInstructions,
  }) =>
      PestControlProfile(
        licenses: licenses ?? this.licenses,
        pestTypes: pestTypes ?? this.pestTypes,
        treatmentMethods: treatmentMethods ?? this.treatmentMethods,
        customerTypes: customerTypes ?? this.customerTypes,
        availability: availability ?? this.availability,
        serviceArea: serviceArea ?? this.serviceArea,
        basePricing: basePricing ?? this.basePricing,
        warrantyAndService: warrantyAndService ?? this.warrantyAndService,
        maintenancePackages:
            maintenancePackages ?? this.maintenancePackages,
        treatmentInstructions:
            treatmentInstructions ?? this.treatmentInstructions,
      );
}

class PestLicense {
  final String id;
  final String type;
  final String nameHe;
  final String licenseNumber;
  final String? validUntil;
  final String? issuedBy;
  final bool verified;
  final String? verifiedAt;

  const PestLicense({
    required this.id,
    required this.type,
    required this.nameHe,
    this.licenseNumber = '',
    this.validUntil,
    this.issuedBy,
    this.verified = false,
    this.verifiedAt,
  });

  factory PestLicense.fromMap(Map<String, dynamic> map) => PestLicense(
        id: map['id'] as String? ?? '',
        type: map['type'] as String? ?? '',
        nameHe: map['nameHe'] as String? ?? '',
        licenseNumber: map['licenseNumber'] as String? ?? '',
        validUntil: map['validUntil'] as String?,
        issuedBy: map['issuedBy'] as String?,
        verified: map['verified'] as bool? ?? false,
        verifiedAt: map['verifiedAt'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'nameHe': nameHe,
        'licenseNumber': licenseNumber,
        if (validUntil != null) 'validUntil': validUntil,
        if (issuedBy != null) 'issuedBy': issuedBy,
        'verified': verified,
        if (verifiedAt != null) 'verifiedAt': verifiedAt,
      };
}

class PestAvailability {
  final PestEmergencyService emergencyService;
  final bool available247;
  final int averageArrivalTime;

  const PestAvailability({
    this.emergencyService = const PestEmergencyService(),
    this.available247 = false,
    this.averageArrivalTime = 45,
  });

  factory PestAvailability.fromMap(Map<String, dynamic> map) =>
      PestAvailability(
        emergencyService: PestEmergencyService.fromMap(
            Map<String, dynamic>.from(map['emergencyService'] ?? {})),
        available247: map['available247'] as bool? ?? false,
        averageArrivalTime: map['averageArrivalTime'] as int? ?? 45,
      );

  Map<String, dynamic> toMap() => {
        'emergencyService': emergencyService.toMap(),
        'available247': available247,
        'averageArrivalTime': averageArrivalTime,
      };
}

class PestEmergencyService {
  final bool enabled;
  final int additionalFee;

  const PestEmergencyService({
    this.enabled = false,
    this.additionalFee = 150,
  });

  factory PestEmergencyService.fromMap(Map<String, dynamic> map) =>
      PestEmergencyService(
        enabled: map['enabled'] as bool? ?? false,
        additionalFee: map['additionalFee'] as int? ?? 150,
      );

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'additionalFee': additionalFee,
      };
}

class PestServiceArea {
  final int radiusKm;
  final int travelFee;
  final int freeRadiusKm;

  const PestServiceArea({
    this.radiusKm = 30,
    this.travelFee = 40,
    this.freeRadiusKm = 15,
  });

  factory PestServiceArea.fromMap(Map<String, dynamic> map) =>
      PestServiceArea(
        radiusKm: map['radiusKm'] as int? ?? 30,
        travelFee: map['travelFee'] as int? ?? 40,
        freeRadiusKm: map['freeRadiusKm'] as int? ?? 15,
      );

  Map<String, dynamic> toMap() => {
        'radiusKm': radiusKm,
        'travelFee': travelFee,
        'freeRadiusKm': freeRadiusKm,
      };
}

class PestWarranty {
  final int warrantyMonths;
  final bool digitalReport;
  final bool beforeAfterPhotos;

  const PestWarranty({
    this.warrantyMonths = 3,
    this.digitalReport = true,
    this.beforeAfterPhotos = true,
  });

  factory PestWarranty.fromMap(Map<String, dynamic> map) => PestWarranty(
        warrantyMonths: map['warrantyMonths'] as int? ?? 3,
        digitalReport: map['digitalReport'] as bool? ?? true,
        beforeAfterPhotos: map['beforeAfterPhotos'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {
        'warrantyMonths': warrantyMonths,
        'digitalReport': digitalReport,
        'beforeAfterPhotos': beforeAfterPhotos,
      };
}

class MaintenancePackage {
  final String id;
  final String nameHe;
  final String type;
  final int treatmentsCount;
  final int discountPercent;
  final int pricePerTreatment;
  final bool enabled;

  const MaintenancePackage({
    required this.id,
    required this.nameHe,
    required this.type,
    required this.treatmentsCount,
    this.discountPercent = 0,
    required this.pricePerTreatment,
    this.enabled = true,
  });

  factory MaintenancePackage.fromMap(Map<String, dynamic> map) =>
      MaintenancePackage(
        id: map['id'] as String? ?? '',
        nameHe: map['nameHe'] as String? ?? '',
        type: map['type'] as String? ?? '',
        treatmentsCount: map['treatmentsCount'] as int? ?? 0,
        discountPercent: map['discountPercent'] as int? ?? 0,
        pricePerTreatment: map['pricePerTreatment'] as int? ?? 0,
        enabled: map['enabled'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'nameHe': nameHe,
        'type': type,
        'treatmentsCount': treatmentsCount,
        'discountPercent': discountPercent,
        'pricePerTreatment': pricePerTreatment,
        'enabled': enabled,
      };
}

class TreatmentInstructions {
  final List<StructuredInstruction> structuredInstructions;
  final String customInstructions;

  const TreatmentInstructions({
    this.structuredInstructions = const [],
    this.customInstructions = '',
  });

  factory TreatmentInstructions.fromMap(Map<String, dynamic> map) =>
      TreatmentInstructions(
        structuredInstructions:
            (map['structuredInstructions'] as List? ?? [])
                .whereType<Map>()
                .map((e) => StructuredInstruction.fromMap(
                    Map<String, dynamic>.from(e)))
                .toList(),
        customInstructions:
            map['customInstructions'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'structuredInstructions':
            structuredInstructions.map((i) => i.toMap()).toList(),
        'customInstructions': customInstructions,
      };
}

class StructuredInstruction {
  final String id;
  final String type;
  final String icon;
  final String titleHe;
  final bool enabled;
  final String? duration;
  final String color;

  const StructuredInstruction({
    required this.id,
    required this.type,
    required this.icon,
    required this.titleHe,
    this.enabled = false,
    this.duration,
    this.color = 'grey',
  });

  factory StructuredInstruction.fromMap(Map<String, dynamic> map) =>
      StructuredInstruction(
        id: map['id'] as String? ?? '',
        type: map['type'] as String? ?? '',
        icon: map['icon'] as String? ?? '',
        titleHe: map['titleHe'] as String? ?? '',
        enabled: map['enabled'] as bool? ?? false,
        duration: map['duration'] as String?,
        color: map['color'] as String? ?? 'grey',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'icon': icon,
        'titleHe': titleHe,
        'enabled': enabled,
        if (duration != null) 'duration': duration,
        'color': color,
      };
}

bool isPestControlCategory(String? serviceType) {
  if (serviceType == null) return false;
  final lower = serviceType.trim().toLowerCase();
  return lower == 'הדברה' ||
      lower == 'pest_control' ||
      lower == 'pest control' ||
      lower.contains('הדברה') ||
      lower.contains('מדביר');
}
