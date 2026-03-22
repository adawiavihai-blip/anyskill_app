// Dynamic Pricing Engine — v8.6.0
// Single source of truth for all pricing logic.
//
// Firestore schema additions to `users/{uid}`:
//   pricingType  : String  ('hourly' | 'fixed' | 'flexible')
//   basePrice    : double  (canonical price; mirrors pricePerHour for compatibility)
//   unitType     : String  ('hour' | 'visit' | 'session')
//   addOns       : List<Map> [{title: String, price: double}]

enum PricingType { hourly, fixed, flexible }

class AddOn {
  final String title;
  final double price;

  const AddOn({required this.title, required this.price});

  factory AddOn.fromMap(Map<String, dynamic> m) => AddOn(
        title: (m['title'] as String? ?? '').trim(),
        price: (m['price'] as num? ?? 0).toDouble(),
      );

  Map<String, dynamic> toMap() => {'title': title, 'price': price};
}

class PricingModel {
  final PricingType type;
  final double basePrice;
  final String unitType; // 'hour' | 'visit' | 'session'
  final List<AddOn> addOns;

  const PricingModel({
    required this.type,
    required this.basePrice,
    required this.unitType,
    required this.addOns,
  });

  // ── Serialisation ──────────────────────────────────────────────────────────

  static PricingType _typeFromString(String? s) {
    switch (s) {
      case 'fixed':
        return PricingType.fixed;
      case 'flexible':
        return PricingType.flexible;
      default:
        return PricingType.hourly;
    }
  }

  static String _typeToString(PricingType t) {
    switch (t) {
      case PricingType.fixed:
        return 'fixed';
      case PricingType.flexible:
        return 'flexible';
      case PricingType.hourly:
        return 'hourly';
    }
  }

  /// Reads from a Firestore user document map.
  /// Falls back to legacy `pricePerHour` if `basePrice` is absent.
  factory PricingModel.fromFirestore(Map<String, dynamic> data) {
    final base = (data['basePrice'] as num? ??
            data['pricePerHour'] as num? ??
            100)
        .toDouble();

    final rawAddOns = data['addOns'] as List<dynamic>? ?? [];

    return PricingModel(
      type:     _typeFromString(data['pricingType'] as String?),
      basePrice: base,
      unitType:  data['unitType'] as String? ?? 'hour',
      addOns:   rawAddOns
          .whereType<Map<String, dynamic>>()
          .map(AddOn.fromMap)
          .where((a) => a.title.isNotEmpty)
          .toList(),
    );
  }

  /// Returns the fields to write/update in a Firestore user document.
  /// Keeps `pricePerHour` in sync so legacy code keeps working.
  Map<String, dynamic> toFirestore() => {
        'pricingType':  _typeToString(type),
        'basePrice':    basePrice,
        'unitType':     unitType,
        'addOns':       addOns.map((a) => a.toMap()).toList(),
        'pricePerHour': basePrice, // backwards compat
      };

  // ── Derived helpers ────────────────────────────────────────────────────────

  /// Human-readable unit label (Hebrew).
  String get unitLabel {
    switch (type) {
      case PricingType.fixed:
        return 'לביקור';
      case PricingType.hourly:
        return 'לשעה';
      case PricingType.flexible:
        return 'להצעה';
    }
  }

  /// Compute total from a set of selected add-on indices.
  double total({Set<int> selectedAddOnIndices = const {}}) {
    double sum = basePrice;
    for (final i in selectedAddOnIndices) {
      if (i >= 0 && i < addOns.length) sum += addOns[i].price;
    }
    return sum;
  }

  /// Apply an urgency/surge multiplier and return the new total.
  double totalWithSurge(double multiplier, {Set<int> selectedAddOnIndices = const {}}) =>
      total(selectedAddOnIndices: selectedAddOnIndices) * multiplier;

  /// Default unit type string for a given PricingType.
  static String defaultUnitType(PricingType t) {
    switch (t) {
      case PricingType.fixed:
        return 'visit';
      case PricingType.flexible:
        return 'session';
      case PricingType.hourly:
        return 'hour';
    }
  }
}
