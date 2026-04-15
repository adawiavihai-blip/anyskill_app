/// AnySkill — Dynamic Service Schema Widgets
///
/// ## Schema model
///
/// `categories/{catId}.serviceSchema` can be ONE of two shapes:
///   * **v1 (legacy)** — `List<Map>` of [SchemaField] only.
///   * **v2 (current)** — `Map<String, dynamic>` with:
///       `version`, `unitType`, `fields[]`, `bundles[]`, `surcharge{}`,
///       `depositPercent`, `defaultPolicy`, `bookingRequirements[]`.
///
/// Both shapes are auto-detected by [ServiceSchema.fromRaw] / [parseSchema].
/// Provider values are stored at `users/{uid}.categoryDetails`:
///   * Regular schema fields: `{fieldId: value}`
///   * Provider-customized bundles: `{'_bundles': {bundleId: {price, enabled}}}`
///   * Provider-customized surcharge: `{'_surcharge': {nightPct, weekendPct}}`
///
/// ## Widgets
///   1. [DynamicSchemaForm] — v1 fields-only form (legacy, still works)
///   2. [DynamicServiceSchemaForm] — v2 full-featured form (fields + bundles + surcharge + deposit)
///   3. [CategorySpecsDisplay] — read-only display for public profiles/cards
///   4. [ServiceSchemaDisplay] — v2 read-only display (fields + bundles + surcharge)
///
/// Schema field types: `number`, `text`, `bool`, `dropdown`
library;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

import '../utils/safe_image_provider.dart';

// ── Schema Model ─────────────────────────────────────────────────────────────

class SchemaField {
  final String id;
  final String label;
  final String type; // 'number' | 'text' | 'bool' | 'dropdown'
  final String unit; // e.g., '₪/ללילה', '₪/לשעה', 'מחיר גלובלי', ''
  final List<String> options; // for dropdown type

  const SchemaField({
    required this.id,
    required this.label,
    required this.type,
    this.unit = '',
    this.options = const [],
  });

  factory SchemaField.fromMap(Map<String, dynamic> m) {
    return SchemaField(
      id: m['id'] as String? ?? '',
      label: m['label'] as String? ?? '',
      type: m['type'] as String? ?? 'text',
      unit: m['unit'] as String? ?? '',
      options: List<String>.from(m['options'] ?? []),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'type': type,
        'unit': unit,
        if (options.isNotEmpty) 'options': options,
      };

  /// True if this is the primary price field (first number with a ₪ unit).
  bool get isPriceField => type == 'number' && unit.contains('₪');
}

// ── ServiceSchema v2 — Bundles ───────────────────────────────────────────────

/// A multi-tier pricing bundle (e.g., "1 session ₪200", "10 sessions ₪1500").
/// Defined by the admin in the category schema as a template; providers can
/// override the price and enable/disable individual bundles per profile.
class PricingBundle {
  final String id;
  final String label;       // e.g. "חבילת 4 סשנים"
  final String description; // e.g. "חיסכון 12% על הסשן הבודד"
  final double price;       // template price (₪)
  final int qty;            // how many units (1 = single, 4 = pack of 4)
  final String unit;        // 'session' | 'visit' | 'hour' | 'event' | ...
  final double savingsPercent;

  const PricingBundle({
    required this.id,
    required this.label,
    this.description = '',
    required this.price,
    this.qty = 1,
    this.unit = 'session',
    this.savingsPercent = 0,
  });

  factory PricingBundle.fromMap(Map<String, dynamic> m) => PricingBundle(
        id: m['id'] as String? ?? '',
        label: m['label'] as String? ?? '',
        description: m['description'] as String? ?? '',
        price: (m['price'] as num? ?? 0).toDouble(),
        qty: (m['qty'] as num? ?? 1).toInt(),
        unit: m['unit'] as String? ?? 'session',
        savingsPercent: (m['savingsPercent'] as num? ?? 0).toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        if (description.isNotEmpty) 'description': description,
        'price': price,
        'qty': qty,
        'unit': unit,
        if (savingsPercent > 0) 'savingsPercent': savingsPercent,
      };
}

// ── ServiceSchema v2 — Surcharge ─────────────────────────────────────────────

/// Off-hours / emergency surcharge config. Stored on the schema as a
/// suggestion; providers can override the percentages on their profile.
class SurchargeConfig {
  final double nightPercent;     // e.g. 25 = +25% for night calls
  final double weekendPercent;   // e.g. 15 = +15% on Sat/Fri eve
  final int nightStartHour;      // 0-23
  final int nightEndHour;        // 0-23

  const SurchargeConfig({
    this.nightPercent = 0,
    this.weekendPercent = 0,
    this.nightStartHour = 22,
    this.nightEndHour = 7,
  });

  bool get isActive => nightPercent > 0 || weekendPercent > 0;

  factory SurchargeConfig.fromMap(Map<String, dynamic> m) => SurchargeConfig(
        nightPercent: (m['nightPercent'] as num? ?? 0).toDouble(),
        weekendPercent: (m['weekendPercent'] as num? ?? 0).toDouble(),
        nightStartHour: (m['nightStartHour'] as num? ?? 22).toInt(),
        nightEndHour: (m['nightEndHour'] as num? ?? 7).toInt(),
      );

  Map<String, dynamic> toMap() => {
        'nightPercent': nightPercent,
        'weekendPercent': weekendPercent,
        'nightStartHour': nightStartHour,
        'nightEndHour': nightEndHour,
      };
}

// ── ServiceSchema v2 — Booking Requirements ──────────────────────────────────

/// Contextual input the customer MUST provide before confirming a booking
/// (e.g. car model for towing, photo of sofa for cleaning, address for pest).
/// Stored on `jobs/{id}.bookingRequirementValues` after submission.
class BookingRequirement {
  final String id;
  final String label;
  final String type;       // 'text' | 'number' | 'image' | 'phone' | 'address' | 'dropdown'
  final bool required;
  final String helpText;
  final List<String> options; // for dropdown

  const BookingRequirement({
    required this.id,
    required this.label,
    this.type = 'text',
    this.required = true,
    this.helpText = '',
    this.options = const [],
  });

  factory BookingRequirement.fromMap(Map<String, dynamic> m) => BookingRequirement(
        id: m['id'] as String? ?? '',
        label: m['label'] as String? ?? '',
        type: m['type'] as String? ?? 'text',
        required: m['required'] as bool? ?? true,
        helpText: m['helpText'] as String? ?? '',
        options: List<String>.from(m['options'] ?? []),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'type': type,
        'required': required,
        if (helpText.isNotEmpty) 'helpText': helpText,
        if (options.isNotEmpty) 'options': options,
      };
}

// ── ServiceSchema v2 — Top-level model ───────────────────────────────────────

/// Full service schema for a sub-category. Defines what fields a provider
/// must fill, what bundles they can offer, surcharge defaults, deposit %,
/// default cancellation policy, and contextual booking inputs.
///
/// **Backwards compatible**: [ServiceSchema.fromRaw] accepts both v1 (List)
/// and v2 (Map) shapes from Firestore. v1 schemas auto-upgrade to v2 with
/// safe defaults (no bundles, no surcharge, flexible policy).
class ServiceSchema {
  /// Allowed unit types — drives the default labels in the form
  /// and the headline-price suffix on search cards.
  static const List<String> kUnitTypes = [
    'per_hour',     // ₪/לשעה
    'per_visit',    // ₪/קריאה
    'per_session',  // ₪/סשן
    'per_room',     // ₪/חדר
    'per_event',    // ₪/אירוע
    'per_call',     // ₪/קריאה (חירום)
    'per_person',   // ₪/אדם
    'per_night',    // ₪/ללילה (pet boarding)
    'per_walk',     // ₪/הליכון (dog walking)
    'flat',         // ₪ (one-off)
  ];

  final int version;
  final String unitType;
  final List<SchemaField> fields;
  final List<PricingBundle> bundles;
  final SurchargeConfig? surcharge;
  final double depositPercent;
  final String defaultPolicy;
  final List<BookingRequirement> bookingRequirements;

  // ── v2.1 — Industry-specific feature flags ─────────────────────────────
  /// Home services (pest, plumbing, electrician, carpentry).
  /// When true, the booking sheet REQUIRES at least one image upload
  /// (added automatically as a required `image` booking requirement) and
  /// shows the "Visual Diagnosis" badge.
  final bool requireVisualDiagnosis;

  /// When true, the booking summary displays a green "מחיר נעול" badge
  /// telling the customer the price is binding once the provider sees the
  /// uploaded photos. Pairs naturally with [requireVisualDiagnosis].
  final bool priceLocked;

  /// Pet services — dog walking. When true, the provider's order screen
  /// shows the "התחל הליכון" / "סיים הליכון" buttons backed by
  /// `DogWalkService` (LatLng route → `dog_walks/{walkId}` doc).
  final bool walkTracking;

  /// Pet services — boarding/pension. When true, the provider's order
  /// screen prompts a daily "1 photo + 1 video" upload via
  /// `BoardingProofService`. Updates flow to the customer's chat.
  final bool dailyProof;

  const ServiceSchema({
    this.version = 2,
    this.unitType = 'per_hour',
    this.fields = const [],
    this.bundles = const [],
    this.surcharge,
    this.depositPercent = 0,
    this.defaultPolicy = 'flexible',
    this.bookingRequirements = const [],
    this.requireVisualDiagnosis = false,
    this.priceLocked = false,
    this.walkTracking = false,
    this.dailyProof = false,
  });

  /// Empty schema — used as a safe fallback when no schema exists.
  factory ServiceSchema.empty() => const ServiceSchema();

  bool get isEmpty =>
      fields.isEmpty &&
      bundles.isEmpty &&
      bookingRequirements.isEmpty &&
      (surcharge == null || !surcharge!.isActive);

  /// Auto-detects v1 (List) vs v2 (Map). Returns an empty schema for null
  /// or malformed input — never throws.
  factory ServiceSchema.fromRaw(dynamic raw) {
    if (raw == null) return ServiceSchema.empty();

    if (raw is List) {
      // v1 legacy — just fields
      return ServiceSchema(
        version: 1,
        unitType: 'per_hour',
        fields: parseSchema(raw),
        bundles: const [],
        surcharge: null,
        depositPercent: 0,
        defaultPolicy: 'flexible',
        bookingRequirements: const [],
      );
    }

    if (raw is Map<String, dynamic>) {
      return ServiceSchema(
        version: (raw['version'] as num? ?? 2).toInt(),
        unitType: raw['unitType'] as String? ?? 'per_hour',
        fields: parseSchema(raw['fields'] as List<dynamic>?),
        bundles: ((raw['bundles'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(PricingBundle.fromMap)
            .toList(),
        surcharge: raw['surcharge'] is Map<String, dynamic>
            ? SurchargeConfig.fromMap(raw['surcharge'] as Map<String, dynamic>)
            : null,
        depositPercent: (raw['depositPercent'] as num? ?? 0).toDouble(),
        defaultPolicy: raw['defaultPolicy'] as String? ?? 'flexible',
        bookingRequirements:
            ((raw['bookingRequirements'] as List<dynamic>?) ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(BookingRequirement.fromMap)
                .toList(),
        requireVisualDiagnosis:
            raw['requireVisualDiagnosis'] as bool? ?? false,
        priceLocked: raw['priceLocked'] as bool? ?? false,
        walkTracking: raw['walkTracking'] as bool? ?? false,
        dailyProof: raw['dailyProof'] as bool? ?? false,
      );
    }

    return ServiceSchema.empty();
  }

  Map<String, dynamic> toMap() => {
        'version': version,
        'unitType': unitType,
        'fields': fields.map((f) => f.toMap()).toList(),
        'bundles': bundles.map((b) => b.toMap()).toList(),
        if (surcharge != null) 'surcharge': surcharge!.toMap(),
        'depositPercent': depositPercent,
        'defaultPolicy': defaultPolicy,
        'bookingRequirements':
            bookingRequirements.map((r) => r.toMap()).toList(),
        if (requireVisualDiagnosis) 'requireVisualDiagnosis': true,
        if (priceLocked) 'priceLocked': true,
        if (walkTracking) 'walkTracking': true,
        if (dailyProof) 'dailyProof': true,
      };

  /// Hebrew label for a unit type — used in form headers + search cards.
  static String unitLabel(String unit) {
    switch (unit) {
      case 'per_hour':    return 'לפי שעה';
      case 'per_visit':   return 'לפי קריאת שירות';
      case 'per_session': return 'לפי סשן';
      case 'per_room':    return 'לפי חדר';
      case 'per_event':   return 'לפי אירוע';
      case 'per_call':    return 'לפי קריאת חירום';
      case 'per_person':  return 'לפי אדם';
      case 'per_night':   return 'לפי לילה';
      case 'per_walk':    return 'לפי הליכון';
      case 'flat':        return 'מחיר גלובלי';
      default:            return unit;
    }
  }
}

/// Loads the full v2 schema for a category by name. Returns
/// [ServiceSchema.empty] when none exists.
Future<ServiceSchema> loadServiceSchemaFor(String categoryName) async {
  if (categoryName.trim().isEmpty) return ServiceSchema.empty();
  final snap = await FirebaseFirestore.instance
      .collection('categories')
      .where('name', isEqualTo: categoryName)
      .limit(1)
      .get();
  if (snap.docs.isEmpty) return ServiceSchema.empty();
  return ServiceSchema.fromRaw(snap.docs.first.data()['serviceSchema']);
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Parses a Firestore schema list into typed fields.
List<SchemaField> parseSchema(List<dynamic>? raw) {
  if (raw == null) return [];
  return raw
      .whereType<Map<String, dynamic>>()
      .map((m) => SchemaField.fromMap(m))
      .where((f) => f.id.isNotEmpty)
      .toList();
}

/// Loads schema for a category from Firestore. Returns empty list if none.
Future<List<SchemaField>> loadSchemaForCategory(String categoryName) async {
  final snap = await FirebaseFirestore.instance
      .collection('categories')
      .where('name', isEqualTo: categoryName)
      .limit(1)
      .get();
  if (snap.docs.isEmpty) return [];
  final data = snap.docs.first.data();
  return parseSchema(data['serviceSchema'] as List<dynamic>?);
}

/// Returns the primary price field from a schema (first number with ₪ unit).
SchemaField? primaryPriceField(List<SchemaField> schema) {
  for (final f in schema) {
    if (f.isPriceField) return f;
  }
  return null;
}

/// Extracts the primary price + unit label from user data + schema.
/// Falls back to pricePerHour + "לשעה" if no schema exists.
(String price, String unitLabel) primaryPriceDisplay(
  Map<String, dynamic> userData,
  List<SchemaField> schema,
) {
  final details = userData['categoryDetails'] as Map<String, dynamic>? ?? {};
  final field = primaryPriceField(schema);

  if (field != null && details.containsKey(field.id)) {
    final val = details[field.id];
    final price = (val is num) ? val.toStringAsFixed(0) : val.toString();
    return (price, field.unit);
  }

  // Fallback
  final price = (userData['pricePerHour'] as num? ?? 100).toStringAsFixed(0);
  return (price, '₪/לשעה');
}

// ═══════════════════════════════════════════════════════════════════════════════
// EDIT MODE — Dynamic Schema Form
// ═══════════════════════════════════════════════════════════════════════════════

class DynamicSchemaForm extends StatefulWidget {
  final List<SchemaField> schema;
  final Map<String, dynamic> initialValues;
  final ValueChanged<Map<String, dynamic>> onChanged;

  const DynamicSchemaForm({
    super.key,
    required this.schema,
    required this.initialValues,
    required this.onChanged,
  });

  @override
  State<DynamicSchemaForm> createState() => _DynamicSchemaFormState();
}

class _DynamicSchemaFormState extends State<DynamicSchemaForm> {
  late Map<String, dynamic> _values;
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _values = Map<String, dynamic>.from(widget.initialValues);
    for (final field in widget.schema) {
      if (field.type == 'number' || field.type == 'text') {
        _controllers[field.id] = TextEditingController(
          text: (_values[field.id] ?? '').toString(),
        );
      }
    }
  }

  void _update(String id, dynamic value) {
    _values[id] = value;
    widget.onChanged(Map<String, dynamic>.from(_values));
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.schema.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune, size: 14, color: Color(0xFF6366F1)),
              SizedBox(width: 6),
              Text(
                'פרטי שירות לקטגוריה',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6366F1),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...widget.schema.map((field) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _buildField(field),
            )),
      ],
    );
  }

  Widget _buildField(SchemaField field) {
    return switch (field.type) {
      'number' => _buildNumberField(field),
      'text' => _buildTextField(field),
      'bool' => _buildBoolField(field),
      'dropdown' => _buildDropdownField(field),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _buildNumberField(SchemaField field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          field.label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _controllers[field.id],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.start,
          onChanged: (v) => _update(field.id, double.tryParse(v) ?? 0),
          decoration: InputDecoration(
            suffixText: field.unit,
            suffixStyle: const TextStyle(
                color: Color(0xFF6366F1),
                fontWeight: FontWeight.w600,
                fontSize: 13),
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFF6366F1), width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(SchemaField field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          field.label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _controllers[field.id],
          textAlign: TextAlign.start,
          onChanged: (v) => _update(field.id, v),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFF6366F1), width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildBoolField(SchemaField field) {
    final val = _values[field.id] == true;
    return Row(
      children: [
        Expanded(
          child: Text(
            field.label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ),
        Switch(
          value: val,
          activeColor: const Color(0xFF6366F1),
          onChanged: (v) {
            setState(() => _values[field.id] = v);
            _update(field.id, v);
          },
        ),
      ],
    );
  }

  Widget _buildDropdownField(SchemaField field) {
    final val = _values[field.id] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          field.label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: field.options.contains(val) ? val : null,
          isExpanded: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          hint: const Text('בחר...'),
          items: field.options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: (v) {
            setState(() => _values[field.id] = v);
            _update(field.id, v);
          },
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// READ-ONLY — Category Specs Display (for public profile + search cards)
// ═══════════════════════════════════════════════════════════════════════════════

class CategorySpecsDisplay extends StatelessWidget {
  final List<SchemaField> schema;
  final Map<String, dynamic> values;

  /// If true, shows only the primary price field inline (for search cards).
  final bool compact;

  const CategorySpecsDisplay({
    super.key,
    required this.schema,
    required this.values,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (schema.isEmpty || values.isEmpty) return const SizedBox.shrink();

    if (compact) return _buildCompact();
    return _buildFull();
  }

  Widget _buildCompact() {
    // Show only the primary price field
    final field = primaryPriceField(schema);
    if (field == null || !values.containsKey(field.id)) {
      return const SizedBox.shrink();
    }
    final val = values[field.id];
    final display = (val is num) ? val.toStringAsFixed(0) : val.toString();
    return Text(
      '$display ${field.unit}',
      style: const TextStyle(
        fontSize: 11,
        color: Color(0xFF6366F1),
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildFull() {
    // Filter out fields with no value
    final populated = schema.where((f) => values.containsKey(f.id)).toList();
    if (populated.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Color(0xFF6366F1)),
              SizedBox(width: 6),
              Text(
                'פרטי שירות',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6366F1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...populated.map((f) => _specRow(f)),
        ],
      ),
    );
  }

  Widget _specRow(SchemaField field) {
    final val = values[field.id];
    String display;

    if (field.type == 'bool') {
      display = val == true ? 'כן' : 'לא';
    } else if (field.type == 'number') {
      display = '${(val as num?)?.toStringAsFixed(0) ?? '—'}'
          '${field.unit.isNotEmpty ? ' ${field.unit}' : ''}';
    } else {
      display = val?.toString() ?? '—';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              field.label,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
          Text(
            display,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EDIT MODE — Full v2 Service Schema Form
// (fields + bundles + surcharge + deposit + booking requirements preview)
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider-facing v2 form. Renders ALL pieces of a [ServiceSchema]:
///   * Schema fields (delegates to existing [DynamicSchemaForm] internals)
///   * Pricing bundles — provider can enable + override price
///   * Off-hours surcharge — provider can override percentages or disable
///   * Deposit % — read-only display (defined by admin, not editable)
///   * Booking requirements — read-only preview (shown to customer at booking)
///
/// Provider customizations are stored in `users/{uid}.categoryDetails` under
/// reserved keys: `_bundles`, `_surcharge`. Regular schema field values use
/// their `id` as the key (existing v1 behavior — unchanged).
class DynamicServiceSchemaForm extends StatefulWidget {
  final ServiceSchema schema;
  final Map<String, dynamic> initialValues;
  final ValueChanged<Map<String, dynamic>> onChanged;

  const DynamicServiceSchemaForm({
    super.key,
    required this.schema,
    required this.initialValues,
    required this.onChanged,
  });

  @override
  State<DynamicServiceSchemaForm> createState() =>
      _DynamicServiceSchemaFormState();
}

class _DynamicServiceSchemaFormState extends State<DynamicServiceSchemaForm> {
  late Map<String, dynamic> _values;

  // Per-bundle controllers
  final Map<String, TextEditingController> _bundleCtrls = {};
  final Map<String, bool> _bundleEnabled = {};

  // Surcharge controllers
  late final TextEditingController _nightPctCtrl;
  late final TextEditingController _weekendPctCtrl;
  late bool _surchargeEnabled;

  @override
  void initState() {
    super.initState();
    _values = Map<String, dynamic>.from(widget.initialValues);

    // Init bundle state from existing _bundles map (provider customizations)
    final providerBundles =
        (_values['_bundles'] as Map<String, dynamic>?) ?? {};
    for (final b in widget.schema.bundles) {
      final saved = providerBundles[b.id] as Map<String, dynamic>?;
      final price = saved?['price'] as num? ?? b.price;
      _bundleCtrls[b.id] = TextEditingController(
        text: price > 0 ? price.toStringAsFixed(0) : '',
      );
      _bundleEnabled[b.id] = saved?['enabled'] as bool? ?? false;
    }

    // Surcharge state
    final providerSurcharge =
        (_values['_surcharge'] as Map<String, dynamic>?) ?? {};
    final defaultNight = widget.schema.surcharge?.nightPercent ?? 0;
    final defaultWeekend = widget.schema.surcharge?.weekendPercent ?? 0;
    _nightPctCtrl = TextEditingController(
      text: ((providerSurcharge['nightPct'] as num?) ?? defaultNight)
          .toStringAsFixed(0),
    );
    _weekendPctCtrl = TextEditingController(
      text: ((providerSurcharge['weekendPct'] as num?) ?? defaultWeekend)
          .toStringAsFixed(0),
    );
    _surchargeEnabled = providerSurcharge['enabled'] as bool? ??
        (widget.schema.surcharge?.isActive ?? false);
  }

  @override
  void dispose() {
    for (final c in _bundleCtrls.values) {
      c.dispose();
    }
    _nightPctCtrl.dispose();
    _weekendPctCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    // Persist bundles
    final bundlesOut = <String, dynamic>{};
    for (final b in widget.schema.bundles) {
      bundlesOut[b.id] = {
        'enabled': _bundleEnabled[b.id] ?? false,
        'price': double.tryParse(_bundleCtrls[b.id]?.text ?? '') ?? 0,
      };
    }
    if (bundlesOut.isNotEmpty) {
      _values['_bundles'] = bundlesOut;
    }

    // Persist surcharge
    if (widget.schema.surcharge != null) {
      _values['_surcharge'] = {
        'enabled': _surchargeEnabled,
        'nightPct': double.tryParse(_nightPctCtrl.text) ?? 0,
        'weekendPct': double.tryParse(_weekendPctCtrl.text) ?? 0,
      };
    }
    widget.onChanged(Map<String, dynamic>.from(_values));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.schema.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Unit type label ───────────────────────────────────────────────
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tune, size: 14, color: Color(0xFF6366F1)),
              const SizedBox(width: 6),
              Text(
                'תמחור — ${ServiceSchema.unitLabel(widget.schema.unitType)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6366F1),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Schema fields ─────────────────────────────────────────────────
        if (widget.schema.fields.isNotEmpty)
          DynamicSchemaForm(
            schema: widget.schema.fields,
            initialValues: _values,
            onChanged: (vals) {
              // Merge regular field values back, preserving _bundles / _surcharge
              for (final entry in vals.entries) {
                _values[entry.key] = entry.value;
              }
              _emit();
            },
          ),

        // ── Bundles (multi-tier pricing) ──────────────────────────────────
        if (widget.schema.bundles.isNotEmpty) ...[
          const SizedBox(height: 18),
          _sectionHeader(
              icon: Icons.layers_rounded,
              title: 'חבילות ומחירים מיוחדים'),
          const SizedBox(height: 4),
          Text(
            'הפעל חבילות שאתה מעוניין להציע ללקוחות. השאר את המחיר על 0 כדי להסתיר חבילה.',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          ...widget.schema.bundles.map(_buildBundleRow),
        ],

        // ── Surcharge ─────────────────────────────────────────────────────
        if (widget.schema.surcharge != null) ...[
          const SizedBox(height: 18),
          _sectionHeader(
              icon: Icons.nights_stay_rounded,
              title: 'תוספת חירום / מחוץ לשעות'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'הפעל תוספת על קריאות לילה / סוף שבוע',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF7C2D12),
                        ),
                      ),
                    ),
                    Switch(
                      value: _surchargeEnabled,
                      activeColor: const Color(0xFFF97316),
                      onChanged: (v) {
                        setState(() => _surchargeEnabled = v);
                        _emit();
                      },
                    ),
                  ],
                ),
                if (_surchargeEnabled) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nightPctCtrl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.start,
                          onChanged: (_) => _emit(),
                          decoration: const InputDecoration(
                            labelText: 'תוספת לילה',
                            suffixText: '%',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _weekendPctCtrl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.start,
                          onChanged: (_) => _emit(),
                          decoration: const InputDecoration(
                            labelText: 'תוספת סוף שבוע',
                            suffixText: '%',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],

        // ── Deposit (read-only, set by admin) ─────────────────────────────
        if (widget.schema.depositPercent > 0) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline,
                    color: Color(0xFF1D4ED8), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'פיקדון מקדים: ${widget.schema.depositPercent.toStringAsFixed(0)}% — נקבע על ידי האדמין',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1E40AF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // ── Booking requirements (preview, read-only) ─────────────────────
        if (widget.schema.bookingRequirements.isNotEmpty) ...[
          const SizedBox(height: 18),
          _sectionHeader(
              icon: Icons.fact_check_outlined,
              title: 'מידע שלקוחות יידרשו לספק בהזמנה'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.schema.bookingRequirements.map((r) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        r.required ? Icons.check_circle : Icons.circle_outlined,
                        size: 14,
                        color: r.required
                            ? const Color(0xFF10B981)
                            : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${r.label}${r.required ? " (חובה)" : " (אופציונלי)"}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBundleRow(PricingBundle b) {
    final enabled = _bundleEnabled[b.id] ?? false;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: enabled
            ? const Color(0xFFEEF2FF)
            : Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: enabled
              ? const Color(0xFF6366F1).withValues(alpha: 0.4)
              : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Switch(
            value: enabled,
            activeColor: const Color(0xFF6366F1),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) {
              setState(() => _bundleEnabled[b.id] = v);
              _emit();
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                if (b.savingsPercent > 0)
                  Text(
                    'חיסכון ${b.savingsPercent.toStringAsFixed(0)}% מול בודד',
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFF10B981)),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 95,
            child: TextField(
              controller: _bundleCtrls[b.id],
              enabled: enabled,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              onChanged: (_) => _emit(),
              decoration: const InputDecoration(
                hintText: '₪',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader({required IconData icon, required String title}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF6366F1)),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A2E),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// READ-ONLY — Service Schema Display (public profile + booking summary)
// ═══════════════════════════════════════════════════════════════════════════════

/// Read-only display of a v2 [ServiceSchema] with the provider's customized
/// values. Shows: spec fields, enabled bundles, active surcharge, deposit %.
class ServiceSchemaDisplay extends StatelessWidget {
  final ServiceSchema schema;
  final Map<String, dynamic> values;

  const ServiceSchemaDisplay({
    super.key,
    required this.schema,
    required this.values,
  });

  @override
  Widget build(BuildContext context) {
    if (schema.isEmpty) return const SizedBox.shrink();

    final enabledBundles = _enabledBundles();
    final surchargeActive = _isSurchargeActive();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Standard spec fields (existing widget — unchanged behavior)
        if (schema.fields.isNotEmpty)
          CategorySpecsDisplay(schema: schema.fields, values: values),

        // Enabled bundles
        if (enabledBundles.isNotEmpty) ...[
          const SizedBox(height: 12),
          _bundlesCard(enabledBundles),
        ],

        // Surcharge banner
        if (surchargeActive) ...[
          const SizedBox(height: 12),
          _surchargeCard(),
        ],

        // Deposit notice
        if (schema.depositPercent > 0) ...[
          const SizedBox(height: 12),
          _depositCard(),
        ],
      ],
    );
  }

  List<({PricingBundle bundle, double price})> _enabledBundles() {
    final providerBundles =
        (values['_bundles'] as Map<String, dynamic>?) ?? const {};
    final out = <({PricingBundle bundle, double price})>[];
    for (final b in schema.bundles) {
      final saved = providerBundles[b.id] as Map<String, dynamic>?;
      final enabled = saved?['enabled'] as bool? ?? false;
      final price = (saved?['price'] as num? ?? 0).toDouble();
      if (enabled && price > 0) {
        out.add((bundle: b, price: price));
      }
    }
    return out;
  }

  bool _isSurchargeActive() {
    final providerSurcharge =
        (values['_surcharge'] as Map<String, dynamic>?) ?? const {};
    final enabled = providerSurcharge['enabled'] as bool? ??
        (schema.surcharge?.isActive ?? false);
    return enabled && schema.surcharge != null;
  }

  Widget _bundlesCard(List<({PricingBundle bundle, double price})> bundles) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.layers_rounded,
                  size: 16, color: Color(0xFF6366F1)),
              SizedBox(width: 6),
              Text(
                'חבילות זמינות',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6366F1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...bundles.map((row) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.bundle.label,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        if (row.bundle.savingsPercent > 0)
                          Text(
                            'חיסכון ${row.bundle.savingsPercent.toStringAsFixed(0)}%',
                            style: const TextStyle(
                                fontSize: 10, color: Color(0xFF10B981)),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '₪${row.price.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6366F1),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _surchargeCard() {
    final providerSurcharge =
        (values['_surcharge'] as Map<String, dynamic>?) ?? const {};
    final night = (providerSurcharge['nightPct'] as num? ??
            schema.surcharge!.nightPercent)
        .toDouble();
    final weekend = (providerSurcharge['weekendPct'] as num? ??
            schema.surcharge!.weekendPercent)
        .toDouble();

    final parts = <String>[];
    if (night > 0) parts.add('לילה +${night.toStringAsFixed(0)}%');
    if (weekend > 0) parts.add('סוף שבוע +${weekend.toStringAsFixed(0)}%');
    if (parts.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.nights_stay_rounded,
              color: Color(0xFFF97316), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'תוספת מחיר: ${parts.join(' • ')}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF7C2D12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _depositCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: Color(0xFF1D4ED8), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'פיקדון מקדים: ${schema.depositPercent.toStringAsFixed(0)}% מהסכום הכולל',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E40AF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BOOKING REQUIREMENTS — Customer-facing form (rendered before "Pay & Secure")
// ═══════════════════════════════════════════════════════════════════════════════

/// Renders the customer input form for [ServiceSchema.bookingRequirements].
/// Used in the booking confirmation sheet on `expert_profile_screen.dart`.
/// Saves answers via [onChanged] as `{requirementId: value}`. The host
/// screen writes the final map to `jobs/{id}.bookingRequirementValues`.
class BookingRequirementsForm extends StatefulWidget {
  final List<BookingRequirement> requirements;
  final Map<String, dynamic> initialValues;
  final ValueChanged<Map<String, dynamic>> onChanged;

  const BookingRequirementsForm({
    super.key,
    required this.requirements,
    required this.initialValues,
    required this.onChanged,
  });

  @override
  State<BookingRequirementsForm> createState() =>
      _BookingRequirementsFormState();
}

class _BookingRequirementsFormState extends State<BookingRequirementsForm> {
  late Map<String, dynamic> _values;
  final Map<String, TextEditingController> _ctrls = {};

  /// Per-requirement upload state — drives the spinner overlay on image fields.
  final Set<String> _uploadingIds = {};

  @override
  void initState() {
    super.initState();
    _values = Map<String, dynamic>.from(widget.initialValues);
    for (final r in widget.requirements) {
      if (r.type == 'text' ||
          r.type == 'number' ||
          r.type == 'phone' ||
          r.type == 'address') {
        _ctrls[r.id] = TextEditingController(
          text: (_values[r.id] ?? '').toString(),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(String id, dynamic v) {
    _values[id] = v;
    widget.onChanged(Map<String, dynamic>.from(_values));
  }

  /// Picks an image (camera-first, fallback to gallery) and uploads to
  /// Storage at `booking_requirements/{customerUid}/{requirementId}_{ts}.jpg`.
  /// Stores the resulting download URL on `_values[requirement.id]`.
  Future<void> _pickAndUploadImage(BookingRequirement r) async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('צלם תמונה'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('בחר מהגלריה'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    setState(() => _uploadingIds.add(r.id));
    try {
      final xfile = await picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1200,
      );
      if (xfile == null) {
        if (mounted) setState(() => _uploadingIds.remove(r.id));
        return;
      }
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance
          .ref('booking_requirements/$uid/${r.id}_$ts.jpg');
      final bytes = await xfile.readAsBytes();
      await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() {
        _uploadingIds.remove(r.id);
      });
      _set(r.id, url);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingIds.remove(r.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאת העלאת תמונה: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.requirements.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fact_check_outlined,
                  size: 14, color: Color(0xFF6366F1)),
              SizedBox(width: 6),
              Text(
                'פרטים נוספים שנותן השירות זקוק להם',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6366F1),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ...widget.requirements.map(_buildField),
      ],
    );
  }

  Widget _buildField(BookingRequirement r) {
    Widget input;
    switch (r.type) {
      case 'dropdown':
        final val = _values[r.id] as String?;
        input = DropdownButtonFormField<String>(
          value: r.options.contains(val) ? val : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: r.label + (r.required ? ' *' : ''),
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 12),
          ),
          items: r.options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: (v) {
            setState(() => _values[r.id] = v);
            _set(r.id, v);
          },
        );
        break;
      case 'image':
        final url = _values[r.id] as String?;
        final isUploading = _uploadingIds.contains(r.id);
        final hasImage = url != null && url.isNotEmpty;
        input = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Label row
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                r.label + (r.required ? ' *' : ''),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            if (r.helpText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  r.helpText,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ),
            // Preview + actions
            GestureDetector(
              onTap: isUploading ? null : () => _pickAndUploadImage(r),
              child: Container(
                height: hasImage ? 140 : 60,
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasImage
                        ? const Color(0xFF10B981).withValues(alpha: 0.4)
                        : const Color(0xFF6366F1).withValues(alpha: 0.4),
                  ),
                  image: (hasImage && safeImageProvider(url) != null)
                      ? DecorationImage(
                          image: safeImageProvider(url)!,
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: isUploading
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : (hasImage
                        ? Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.check_rounded,
                                    color: Colors.white, size: 16),
                              ),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add_a_photo_outlined,
                                  color: Color(0xFF6366F1), size: 20),
                              const SizedBox(width: 8),
                              Text(
                                hasImage ? 'החלף תמונה' : 'הוסף תמונה',
                                style: const TextStyle(
                                  color: Color(0xFF6366F1),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          )),
              ),
            ),
            if (hasImage)
              TextButton.icon(
                onPressed: isUploading
                    ? null
                    : () {
                        setState(() => _values[r.id] = '');
                        _set(r.id, '');
                      },
                icon: const Icon(Icons.delete_outline,
                    size: 14, color: Colors.red),
                label: const Text('הסר תמונה',
                    style: TextStyle(fontSize: 11, color: Colors.red)),
              ),
          ],
        );
        break;
      case 'number':
        input = TextField(
          controller: _ctrls[r.id],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.start,
          onChanged: (v) => _set(r.id, double.tryParse(v) ?? 0),
          decoration: InputDecoration(
            labelText: r.label + (r.required ? ' *' : ''),
            helperText: r.helpText.isNotEmpty ? r.helpText : null,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 12),
          ),
        );
        break;
      case 'phone':
      case 'address':
      case 'text':
      default:
        input = TextField(
          controller: _ctrls[r.id],
          keyboardType: r.type == 'phone'
              ? TextInputType.phone
              : TextInputType.text,
          maxLines: r.type == 'text' && r.label.length > 30 ? 2 : 1,
          textAlign: TextAlign.start,
          onChanged: (v) => _set(r.id, v),
          decoration: InputDecoration(
            labelText: r.label + (r.required ? ' *' : ''),
            helperText: r.helpText.isNotEmpty ? r.helpText : null,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 12),
          ),
        );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: input,
    );
  }
}
