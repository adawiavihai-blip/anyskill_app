/// AnySkill — Dynamic Service Schema Widgets
///
/// Two main widgets:
///   1. [DynamicSchemaForm] — edit mode for provider profile setup
///   2. [CategorySpecsDisplay] — read-only display for public profiles/cards
///
/// Schema is loaded from `categories/{catId}.serviceSchema` in Firestore.
/// Provider values are stored in `users/{uid}.categoryDetails`.
///
/// Schema field types: number, text, bool, dropdown
library;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
