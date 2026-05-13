class MassageProfile {
  final List<String> specialties;
  final MassageServiceLocations serviceLocations;
  final List<MassageAddon> addOns;
  final List<MassageDuration> durations;
  final List<String> pressureLevels;
  final List<String> conversationStyles;
  final List<DiscountPackage> discountPackages;

  const MassageProfile({
    this.specialties = const [],
    this.serviceLocations = const MassageServiceLocations(),
    this.addOns = const [],
    this.durations = const [],
    this.pressureLevels = const ['light', 'medium', 'strong'],
    this.conversationStyles = const ['chatty', 'minimal'],
    this.discountPackages = const [],
  });

  factory MassageProfile.fromMap(Map<String, dynamic> map) {
    return MassageProfile(
      specialties: List<String>.from(map['specialties'] ?? []),
      serviceLocations: MassageServiceLocations.fromMap(
          Map<String, dynamic>.from(map['serviceLocations'] ?? {})),
      addOns: (map['addOns'] as List? ?? [])
          .map((e) => MassageAddon.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      durations: (map['durations'] as List? ?? [])
          .map((e) => MassageDuration.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      pressureLevels: List<String>.from(map['pressureLevels'] ?? ['light', 'medium', 'strong']),
      conversationStyles: List<String>.from(map['conversationStyles'] ?? ['chatty', 'minimal']),
      discountPackages: (map['discountPackages'] as List? ?? [])
          .map((e) => DiscountPackage.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'specialties': specialties,
        'serviceLocations': serviceLocations.toMap(),
        'addOns': addOns.map((a) => a.toMap()).toList(),
        'durations': durations.map((d) => d.toMap()).toList(),
        'pressureLevels': pressureLevels,
        'conversationStyles': conversationStyles,
        'discountPackages': discountPackages.map((p) => p.toMap()).toList(),
      };

  MassageProfile copyWith({
    List<String>? specialties,
    MassageServiceLocations? serviceLocations,
    List<MassageAddon>? addOns,
    List<MassageDuration>? durations,
    List<String>? pressureLevels,
    List<String>? conversationStyles,
    List<DiscountPackage>? discountPackages,
  }) =>
      MassageProfile(
        specialties: specialties ?? this.specialties,
        serviceLocations: serviceLocations ?? this.serviceLocations,
        addOns: addOns ?? this.addOns,
        durations: durations ?? this.durations,
        pressureLevels: pressureLevels ?? this.pressureLevels,
        conversationStyles: conversationStyles ?? this.conversationStyles,
        discountPackages: discountPackages ?? this.discountPackages,
      );
}

class MassageServiceLocations {
  final HomeService home;
  final ClinicService clinic;

  const MassageServiceLocations({
    this.home = const HomeService(),
    this.clinic = const ClinicService(),
  });

  factory MassageServiceLocations.fromMap(Map<String, dynamic> map) =>
      MassageServiceLocations(
        home: HomeService.fromMap(Map<String, dynamic>.from(map['home'] ?? {})),
        clinic: ClinicService.fromMap(Map<String, dynamic>.from(map['clinic'] ?? {})),
      );

  Map<String, dynamic> toMap() => {
        'home': home.toMap(),
        'clinic': clinic.toMap(),
      };
}

class HomeService {
  final bool enabled;
  final int radiusKm;
  final int travelFee;

  const HomeService({this.enabled = false, this.radiusKm = 15, this.travelFee = 0});

  factory HomeService.fromMap(Map<String, dynamic> m) => HomeService(
        enabled: m['enabled'] == true,
        radiusKm: (m['radiusKm'] as num?)?.toInt() ?? 15,
        travelFee: (m['travelFee'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'radiusKm': radiusKm,
        'travelFee': travelFee,
      };
}

class ClinicService {
  final bool enabled;
  final String address;
  final String floor;

  const ClinicService({this.enabled = false, this.address = '', this.floor = ''});

  factory ClinicService.fromMap(Map<String, dynamic> m) => ClinicService(
        enabled: m['enabled'] == true,
        address: m['address'] as String? ?? '',
        floor: m['floor'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'address': address,
        'floor': floor,
      };
}

class MassageAddon {
  final String id;
  final bool enabled;
  final int customPrice;
  final bool isCustom;
  final String? nameHe;
  final String? icon;
  final String? descriptionHe;

  const MassageAddon({
    required this.id,
    this.enabled = false,
    this.customPrice = 0,
    this.isCustom = false,
    this.nameHe,
    this.icon,
    this.descriptionHe,
  });

  factory MassageAddon.fromMap(Map<String, dynamic> m) => MassageAddon(
        id: m['id'] as String? ?? '',
        enabled: m['enabled'] == true,
        customPrice: (m['customPrice'] as num?)?.toInt() ?? 0,
        isCustom: m['isCustom'] == true,
        nameHe: m['nameHe'] as String?,
        icon: m['icon'] as String?,
        descriptionHe: m['descriptionHe'] as String?,
      );

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'id': id,
      'enabled': enabled,
      'customPrice': customPrice,
    };
    if (isCustom) {
      map['isCustom'] = true;
      if (nameHe != null) map['nameHe'] = nameHe;
      if (icon != null) map['icon'] = icon;
      if (descriptionHe != null) map['descriptionHe'] = descriptionHe;
    }
    return map;
  }

  MassageAddon copyWith({
    bool? enabled,
    int? customPrice,
  }) =>
      MassageAddon(
        id: id,
        enabled: enabled ?? this.enabled,
        customPrice: customPrice ?? this.customPrice,
        isCustom: isCustom,
        nameHe: nameHe,
        icon: icon,
        descriptionHe: descriptionHe,
      );
}

class MassageDuration {
  final int minutes;
  final bool enabled;
  final int price;

  const MassageDuration({required this.minutes, this.enabled = true, this.price = 0});

  factory MassageDuration.fromMap(Map<String, dynamic> m) => MassageDuration(
        minutes: (m['minutes'] as num?)?.toInt() ?? 60,
        enabled: m['enabled'] != false,
        price: (m['price'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'minutes': minutes,
        'enabled': enabled,
        'price': price,
      };

  MassageDuration copyWith({bool? enabled, int? price}) => MassageDuration(
        minutes: minutes,
        enabled: enabled ?? this.enabled,
        price: price ?? this.price,
      );
}

class DiscountPackage {
  final String id;
  final String name;
  final int sessionsCount;
  final int discountPercent;
  final int validityDays;
  final bool enabled;

  const DiscountPackage({
    required this.id,
    required this.name,
    this.sessionsCount = 5,
    this.discountPercent = 15,
    this.validityDays = 180,
    this.enabled = true,
  });

  factory DiscountPackage.fromMap(Map<String, dynamic> m) => DiscountPackage(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        sessionsCount: (m['sessionsCount'] as num?)?.toInt() ?? 5,
        discountPercent: (m['discountPercent'] as num?)?.toInt() ?? 15,
        validityDays: (m['validityDays'] as num?)?.toInt() ?? 180,
        enabled: m['enabled'] != false,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'sessionsCount': sessionsCount,
        'discountPercent': discountPercent,
        'validityDays': validityDays,
        'enabled': enabled,
      };
}

bool isMassageCategory(String? serviceType) {
  if (serviceType == null) return false;
  final lower = serviceType.trim().toLowerCase();
  return lower == 'עיסוי' || lower == 'massage' || lower.contains('עיסוי');
}
