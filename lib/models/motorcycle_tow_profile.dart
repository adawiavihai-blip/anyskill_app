// Motorcycle Towing CSM — provider profile model + booking preferences.
// Follows the same pattern as MassageProfile (§3d), HandymanProfile (§41),
// BabysitterProfile (§53).
//
// Sub-category gate: "גרר אופנועים" / "motorcycle towing" / variants.
// The category itself lives in Firestore (Categories v3 §45) — this module
// detects the sub-category via fuzzy string match on `users/{uid}.serviceType`.
//
// Hardcoded rules:
//  - NO insurance field (already global in app onboarding §3).
//  - NO availability/calendar (existing `users/{uid}.workingHours` owns it).
//  - NO chat (existing ChatScreen).
//  - NO documents/licenses (general onboarding handles them).
//  - Bike-types catalog is Firestore-backed (admin uploads images);
//    use [kMotorcycleBikeTypesFallback] only as offline seed.
import '../utils/firestore_map.dart';

/// True when the given serviceType (sub-category name) resolves to motorcycle
/// towing. Matches the Hebrew "גרר אופנועים" + variants and a few common
/// transliterations.
bool isMotorcycleTowingCategory(String? serviceType) {
  if (serviceType == null) return false;
  final lower = serviceType.trim().toLowerCase();
  if (lower.isEmpty) return false;
  return lower == 'גרר אופנועים' ||
      lower == 'גרר אופנוע' ||
      lower == 'motorcycle towing' ||
      lower == 'motorcycle tow' ||
      lower == 'bike towing' ||
      (lower.contains('גרר') && lower.contains('אופנוע')) ||
      (lower.contains('motorcycle') && lower.contains('tow')) ||
      (lower.contains('bike') && lower.contains('tow'));
}

// ═════════════════════════════════════════════════════════════════════════
// PROVIDER PROFILE — saved at `users/{uid}.motorcycleTowProfile`
// ═════════════════════════════════════════════════════════════════════════

/// Root provider-side motorcycle towing profile.
class MotorcycleTowProfile {
  /// IDs of bike types this provider tows (matches doc IDs in Firestore
  /// collection `motorcycle_bike_types/{id}` + the offline seed list in
  /// `lib/constants/motorcycle_bike_types_catalog.dart`).
  final List<String> bikeTypeIds;
  final MotorcycleTowPricing pricing;
  final MotorcycleTowEquipment equipment;
  /// IDs of service-call types accepted (see motorcycle_service_cases_catalog).
  final List<String> serviceCases;
  final MotorcycleTowServiceArea serviceArea;
  final MotorcycleTowSmartFeatures smartFeatures;

  const MotorcycleTowProfile({
    this.bikeTypeIds = const [],
    this.pricing = const MotorcycleTowPricing(),
    this.equipment = const MotorcycleTowEquipment(),
    this.serviceCases = const [],
    this.serviceArea = const MotorcycleTowServiceArea(),
    this.smartFeatures = const MotorcycleTowSmartFeatures(),
  });

  Map<String, dynamic> toMap() => {
        'bikeTypeIds': bikeTypeIds,
        'pricing': pricing.toMap(),
        'equipment': equipment.toMap(),
        'serviceCases': serviceCases,
        'serviceArea': serviceArea.toMap(),
        'smartFeatures': smartFeatures.toMap(),
      };

  factory MotorcycleTowProfile.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const MotorcycleTowProfile();
    return MotorcycleTowProfile(
      bikeTypeIds: (raw['bikeTypeIds'] as List?)
              ?.whereType<String>()
              .toList() ??
          const [],
      pricing: MotorcycleTowPricing.fromMap(safeMap(raw['pricing'])),
      equipment: MotorcycleTowEquipment.fromMap(safeMap(raw['equipment'])),
      serviceCases:
          (raw['serviceCases'] as List?)?.whereType<String>().toList() ??
              const [],
      serviceArea:
          MotorcycleTowServiceArea.fromMap(safeMap(raw['serviceArea'])),
      smartFeatures:
          MotorcycleTowSmartFeatures.fromMap(safeMap(raw['smartFeatures'])),
    );
  }

  MotorcycleTowProfile copyWith({
    List<String>? bikeTypeIds,
    MotorcycleTowPricing? pricing,
    MotorcycleTowEquipment? equipment,
    List<String>? serviceCases,
    MotorcycleTowServiceArea? serviceArea,
    MotorcycleTowSmartFeatures? smartFeatures,
  }) =>
      MotorcycleTowProfile(
        bikeTypeIds: bikeTypeIds ?? this.bikeTypeIds,
        pricing: pricing ?? this.pricing,
        equipment: equipment ?? this.equipment,
        serviceCases: serviceCases ?? this.serviceCases,
        serviceArea: serviceArea ?? this.serviceArea,
        smartFeatures: smartFeatures ?? this.smartFeatures,
      );

  /// Section completion flags — drives the progress bar in the settings UI.
  bool get hasBikeTypes => bikeTypeIds.isNotEmpty;
  bool get hasPricing => pricing.basePrice > 0 && pricing.pricePerKm > 0;
  bool get hasEquipment => equipment.anyEnabled;
  bool get hasServiceCases => serviceCases.isNotEmpty;
  bool get hasServiceArea => serviceArea.isConfigured;

  /// Completion percentage 0-100. Hard required: bikes + pricing + area.
  /// Optional: equipment + cases + smart features.
  int get completionPercent {
    final flags = [
      hasBikeTypes,
      hasPricing,
      hasEquipment,
      hasServiceCases,
      hasServiceArea,
    ];
    final done = flags.where((f) => f).length;
    return (done / flags.length * 100).round();
  }
}

/// Pricing config. All values are NIS / fractions of 100.
class MotorcycleTowPricing {
  /// Minimum call-out fee (includes [includedKm] kilometres).
  final double basePrice;
  /// Price per extra kilometre beyond [includedKm].
  final double pricePerKm;
  /// Kilometres bundled into the base price.
  final int includedKm;
  /// Surcharge applied at night / on Saturdays. Stored as 0-100, NOT a
  /// fraction. Multiplier on the (basePrice + kmFee) subtotal.
  final double nightSurchargePercent;
  /// 0-23. Inclusive start of the night window. Wraps midnight.
  final int nightStartHour;
  /// 0-23. Inclusive end of the night window.
  final int nightEndHour;
  /// Surcharge applied when urgency==immediate (<30 min ETA).
  /// Stored as 0-100. Applied on the (subtotal + nightSurcharge).
  final double emergencySurchargePercent;

  const MotorcycleTowPricing({
    this.basePrice = 180,
    this.pricePerKm = 4.5,
    this.includedKm = 10,
    this.nightSurchargePercent = 25,
    this.nightStartHour = 22,
    this.nightEndHour = 6,
    this.emergencySurchargePercent = 50,
  });

  Map<String, dynamic> toMap() => {
        'basePrice': basePrice,
        'pricePerKm': pricePerKm,
        'includedKm': includedKm,
        'nightSurchargePercent': nightSurchargePercent,
        'nightStartHour': nightStartHour,
        'nightEndHour': nightEndHour,
        'emergencySurchargePercent': emergencySurchargePercent,
      };

  factory MotorcycleTowPricing.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const MotorcycleTowPricing();
    double d(String k, double fb) => (raw[k] as num?)?.toDouble() ?? fb;
    int i(String k, int fb) => (raw[k] as num?)?.toInt() ?? fb;
    return MotorcycleTowPricing(
      basePrice: d('basePrice', 180),
      pricePerKm: d('pricePerKm', 4.5),
      includedKm: i('includedKm', 10),
      nightSurchargePercent: d('nightSurchargePercent', 25),
      nightStartHour: i('nightStartHour', 22),
      nightEndHour: i('nightEndHour', 6),
      emergencySurchargePercent: d('emergencySurchargePercent', 50),
    );
  }

  MotorcycleTowPricing copyWith({
    double? basePrice,
    double? pricePerKm,
    int? includedKm,
    double? nightSurchargePercent,
    int? nightStartHour,
    int? nightEndHour,
    double? emergencySurchargePercent,
  }) =>
      MotorcycleTowPricing(
        basePrice: basePrice ?? this.basePrice,
        pricePerKm: pricePerKm ?? this.pricePerKm,
        includedKm: includedKm ?? this.includedKm,
        nightSurchargePercent:
            nightSurchargePercent ?? this.nightSurchargePercent,
        nightStartHour: nightStartHour ?? this.nightStartHour,
        nightEndHour: nightEndHour ?? this.nightEndHour,
        emergencySurchargePercent:
            emergencySurchargePercent ?? this.emergencySurchargePercent,
      );

  /// True when the given local hour falls inside the night window.
  /// Handles the midnight wrap (start 22 → end 6 means 22-23 AND 0-6).
  bool isNightHour(int hour) {
    if (nightStartHour == nightEndHour) return false;
    if (nightStartHour < nightEndHour) {
      return hour >= nightStartHour && hour < nightEndHour;
    }
    return hour >= nightStartHour || hour < nightEndHour;
  }
}

/// Tow-truck equipment + technique flags.
class MotorcycleTowEquipment {
  final bool flatbed;
  final bool wheelCradle;
  final bool softStraps;
  final bool electricWinch;
  final bool towDolly;

  const MotorcycleTowEquipment({
    this.flatbed = true,
    this.wheelCradle = true,
    this.softStraps = true,
    this.electricWinch = true,
    this.towDolly = false,
  });

  Map<String, dynamic> toMap() => {
        'flatbed': flatbed,
        'wheelCradle': wheelCradle,
        'softStraps': softStraps,
        'electricWinch': electricWinch,
        'towDolly': towDolly,
      };

  factory MotorcycleTowEquipment.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const MotorcycleTowEquipment();
    bool b(String k, bool fb) => raw[k] is bool ? raw[k] as bool : fb;
    return MotorcycleTowEquipment(
      flatbed: b('flatbed', true),
      wheelCradle: b('wheelCradle', true),
      softStraps: b('softStraps', true),
      electricWinch: b('electricWinch', true),
      towDolly: b('towDolly', false),
    );
  }

  MotorcycleTowEquipment copyWith({
    bool? flatbed,
    bool? wheelCradle,
    bool? softStraps,
    bool? electricWinch,
    bool? towDolly,
  }) =>
      MotorcycleTowEquipment(
        flatbed: flatbed ?? this.flatbed,
        wheelCradle: wheelCradle ?? this.wheelCradle,
        softStraps: softStraps ?? this.softStraps,
        electricWinch: electricWinch ?? this.electricWinch,
        towDolly: towDolly ?? this.towDolly,
      );

  bool get anyEnabled =>
      flatbed || wheelCradle || softStraps || electricWinch || towDolly;

  /// Returns a list of `{id, label}` records for the customer profile view —
  /// only the enabled techniques are included.
  List<Map<String, String>> get enabledList {
    final items = <Map<String, String>>[];
    if (flatbed) items.add({'id': 'flatbed', 'label': 'משאית פלטה (Flatbed)'});
    if (wheelCradle) {
      items.add({'id': 'wheelCradle', 'label': 'עריסת גלגל קדמי'});
    }
    if (softStraps) items.add({'id': 'softStraps', 'label': 'רצועות בד רכות'});
    if (electricWinch) items.add({'id': 'electricWinch', 'label': 'כננת חשמלית'});
    if (towDolly) items.add({'id': 'towDolly', 'label': 'דולי עגלה'});
    return items;
  }
}

/// Service area — radius from base, OR a hand-drawn polygon.
class MotorcycleTowServiceArea {
  /// 'radius' | 'polygon'.
  final String mode;
  final String baseAddress;
  final double baseLat;
  final double baseLng;
  final double radiusKm;
  final List<MotorcycleTowGeoPoint> polygonPoints;

  const MotorcycleTowServiceArea({
    this.mode = 'radius',
    this.baseAddress = '',
    this.baseLat = 32.0853,
    this.baseLng = 34.7818,
    this.radiusKm = 50,
    this.polygonPoints = const [],
  });

  Map<String, dynamic> toMap() => {
        'mode': mode,
        'baseAddress': baseAddress,
        'baseLat': baseLat,
        'baseLng': baseLng,
        'radiusKm': radiusKm,
        'polygonPoints': polygonPoints.map((p) => p.toMap()).toList(),
      };

  factory MotorcycleTowServiceArea.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const MotorcycleTowServiceArea();
    return MotorcycleTowServiceArea(
      mode: raw['mode'] as String? ?? 'radius',
      baseAddress: raw['baseAddress'] as String? ?? '',
      baseLat: (raw['baseLat'] as num?)?.toDouble() ?? 32.0853,
      baseLng: (raw['baseLng'] as num?)?.toDouble() ?? 34.7818,
      radiusKm: (raw['radiusKm'] as num?)?.toDouble() ?? 50,
      polygonPoints: (raw['polygonPoints'] as List?)
              ?.whereType<Map>()
              .map((m) =>
                  MotorcycleTowGeoPoint.fromMap(Map<String, dynamic>.from(m)))
              .toList() ??
          const [],
    );
  }

  MotorcycleTowServiceArea copyWith({
    String? mode,
    String? baseAddress,
    double? baseLat,
    double? baseLng,
    double? radiusKm,
    List<MotorcycleTowGeoPoint>? polygonPoints,
  }) =>
      MotorcycleTowServiceArea(
        mode: mode ?? this.mode,
        baseAddress: baseAddress ?? this.baseAddress,
        baseLat: baseLat ?? this.baseLat,
        baseLng: baseLng ?? this.baseLng,
        radiusKm: radiusKm ?? this.radiusKm,
        polygonPoints: polygonPoints ?? this.polygonPoints,
      );

  bool get isConfigured =>
      baseAddress.isNotEmpty &&
      ((mode == 'radius' && radiusKm > 0) ||
          (mode == 'polygon' && polygonPoints.length >= 3));
}

class MotorcycleTowGeoPoint {
  final double lat;
  final double lng;
  const MotorcycleTowGeoPoint({required this.lat, required this.lng});

  Map<String, dynamic> toMap() => {'lat': lat, 'lng': lng};

  factory MotorcycleTowGeoPoint.fromMap(Map<String, dynamic> m) =>
      MotorcycleTowGeoPoint(
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
      );
}

class MotorcycleTowSmartFeatures {
  final bool beforeAfterPhotos;
  final bool instantQuote;
  final bool internalChat;

  const MotorcycleTowSmartFeatures({
    this.beforeAfterPhotos = true,
    this.instantQuote = true,
    this.internalChat = true,
  });

  Map<String, dynamic> toMap() => {
        'beforeAfterPhotos': beforeAfterPhotos,
        'instantQuote': instantQuote,
        'internalChat': internalChat,
      };

  factory MotorcycleTowSmartFeatures.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const MotorcycleTowSmartFeatures();
    bool b(String k, bool fb) => raw[k] is bool ? raw[k] as bool : fb;
    return MotorcycleTowSmartFeatures(
      beforeAfterPhotos: b('beforeAfterPhotos', true),
      instantQuote: b('instantQuote', true),
      internalChat: b('internalChat', true),
    );
  }

  MotorcycleTowSmartFeatures copyWith({
    bool? beforeAfterPhotos,
    bool? instantQuote,
    bool? internalChat,
  }) =>
      MotorcycleTowSmartFeatures(
        beforeAfterPhotos: beforeAfterPhotos ?? this.beforeAfterPhotos,
        instantQuote: instantQuote ?? this.instantQuote,
        internalChat: internalChat ?? this.internalChat,
      );
}

// ═════════════════════════════════════════════════════════════════════════
// CLIENT-SIDE BOOKING PREFERENCES — saved at `jobs/{id}.motorcycleTowPreferences`
// ═════════════════════════════════════════════════════════════════════════

/// Snapshot of customer choices captured by [MotorcycleTowBookingBlock] at
/// booking time. Threaded through the existing escrow flow ("Pay & Secure").
class MotorcycleTowBookingPreferences {
  /// Bike type id (matches Firestore `motorcycle_bike_types/{id}` OR a
  /// catalog seed id).
  final String bikeTypeId;
  /// Optional bike model free-text (e.g. "Yamaha MT-07").
  final String bikeModel;
  /// Reason for tow — see motorcycle_service_cases_catalog.
  final String issueId;
  final String issueDetails;
  /// Pickup point.
  final String pickupAddress;
  final double? pickupLat;
  final double? pickupLng;
  /// Drop-off point (workshop / home / etc.).
  final String dropoffAddress;
  final double? dropoffLat;
  final double? dropoffLng;
  /// Estimated route distance (km) — used for kmFee math.
  final double distanceKm;
  /// Urgency id — see motorcycle_urgency_levels.
  final String urgencyId;
  /// Only when urgency == 'scheduled'.
  final DateTime? scheduledAt;
  /// Caller name + phone for the driver.
  final String contactName;
  final String contactPhone;
  /// Photos uploaded before pickup (recommended).
  final List<String> beforePhotoUrls;
  final MotorcycleTowPriceBreakdown priceBreakdown;

  const MotorcycleTowBookingPreferences({
    this.bikeTypeId = '',
    this.bikeModel = '',
    this.issueId = '',
    this.issueDetails = '',
    this.pickupAddress = '',
    this.pickupLat,
    this.pickupLng,
    this.dropoffAddress = '',
    this.dropoffLat,
    this.dropoffLng,
    this.distanceKm = 0,
    this.urgencyId = 'within_hour',
    this.scheduledAt,
    this.contactName = '',
    this.contactPhone = '',
    this.beforePhotoUrls = const [],
    this.priceBreakdown = const MotorcycleTowPriceBreakdown(),
  });

  Map<String, dynamic> toMap() => {
        'bikeTypeId': bikeTypeId,
        'bikeModel': bikeModel,
        'issueId': issueId,
        'issueDetails': issueDetails,
        'pickupAddress': pickupAddress,
        if (pickupLat != null) 'pickupLat': pickupLat,
        if (pickupLng != null) 'pickupLng': pickupLng,
        'dropoffAddress': dropoffAddress,
        if (dropoffLat != null) 'dropoffLat': dropoffLat,
        if (dropoffLng != null) 'dropoffLng': dropoffLng,
        'distanceKm': distanceKm,
        'urgencyId': urgencyId,
        if (scheduledAt != null)
          'scheduledAt': scheduledAt!.toUtc().toIso8601String(),
        'contactName': contactName,
        'contactPhone': contactPhone,
        'beforePhotoUrls': beforePhotoUrls,
        'priceBreakdown': priceBreakdown.toMap(),
      };

  MotorcycleTowBookingPreferences copyWith({
    String? bikeTypeId,
    String? bikeModel,
    String? issueId,
    String? issueDetails,
    String? pickupAddress,
    double? pickupLat,
    double? pickupLng,
    String? dropoffAddress,
    double? dropoffLat,
    double? dropoffLng,
    double? distanceKm,
    String? urgencyId,
    DateTime? scheduledAt,
    String? contactName,
    String? contactPhone,
    List<String>? beforePhotoUrls,
    MotorcycleTowPriceBreakdown? priceBreakdown,
  }) =>
      MotorcycleTowBookingPreferences(
        bikeTypeId: bikeTypeId ?? this.bikeTypeId,
        bikeModel: bikeModel ?? this.bikeModel,
        issueId: issueId ?? this.issueId,
        issueDetails: issueDetails ?? this.issueDetails,
        pickupAddress: pickupAddress ?? this.pickupAddress,
        pickupLat: pickupLat ?? this.pickupLat,
        pickupLng: pickupLng ?? this.pickupLng,
        dropoffAddress: dropoffAddress ?? this.dropoffAddress,
        dropoffLat: dropoffLat ?? this.dropoffLat,
        dropoffLng: dropoffLng ?? this.dropoffLng,
        distanceKm: distanceKm ?? this.distanceKm,
        urgencyId: urgencyId ?? this.urgencyId,
        scheduledAt: scheduledAt ?? this.scheduledAt,
        contactName: contactName ?? this.contactName,
        contactPhone: contactPhone ?? this.contactPhone,
        beforePhotoUrls: beforePhotoUrls ?? this.beforePhotoUrls,
        priceBreakdown: priceBreakdown ?? this.priceBreakdown,
      );

  /// Required-field gate before "Pay & Secure" can be enabled.
  bool get isReady =>
      bikeTypeId.isNotEmpty &&
      issueId.isNotEmpty &&
      pickupAddress.isNotEmpty &&
      dropoffAddress.isNotEmpty &&
      contactName.isNotEmpty &&
      contactPhone.isNotEmpty;
}

/// Final price breakdown — every component rounded to 2 decimals so the
/// numbers shown in the UI EQUAL what we store on the job.
class MotorcycleTowPriceBreakdown {
  final double basePrice;
  final double kmFee;
  final double nightSurcharge;
  final double emergencySurcharge;
  final double total;
  final double extraKm;

  const MotorcycleTowPriceBreakdown({
    this.basePrice = 0,
    this.kmFee = 0,
    this.nightSurcharge = 0,
    this.emergencySurcharge = 0,
    this.total = 0,
    this.extraKm = 0,
  });

  Map<String, dynamic> toMap() => {
        'basePrice': basePrice,
        'kmFee': kmFee,
        'nightSurcharge': nightSurcharge,
        'emergencySurcharge': emergencySurcharge,
        'total': total,
        'extraKm': extraKm,
      };

  factory MotorcycleTowPriceBreakdown.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const MotorcycleTowPriceBreakdown();
    double d(String k) => (raw[k] as num?)?.toDouble() ?? 0;
    return MotorcycleTowPriceBreakdown(
      basePrice: d('basePrice'),
      kmFee: d('kmFee'),
      nightSurcharge: d('nightSurcharge'),
      emergencySurcharge: d('emergencySurcharge'),
      total: d('total'),
      extraKm: d('extraKm'),
    );
  }
}
