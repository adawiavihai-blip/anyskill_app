import 'package:cloud_firestore/cloud_firestore.dart';

/// A single field in a category's dynamic service schema.
///
/// Example: `{id: 'pricePerNight', label: 'מחיר ללילה', type: 'number', unit: '₪/ללילה'}`
class SchemaField {
  final String id;
  final String label;
  final String type; // 'number' | 'text' | 'bool' | 'dropdown'
  final String unit;
  final List<String> options; // for dropdown type

  const SchemaField({
    required this.id,
    this.label = '',
    this.type = 'text',
    this.unit = '',
    this.options = const [],
  });

  factory SchemaField.fromMap(Map<String, dynamic> m) => SchemaField(
    id:      m['id']      as String? ?? '',
    label:   m['label']   as String? ?? '',
    type:    m['type']    as String? ?? 'text',
    unit:    m['unit']    as String? ?? '',
    options: (m['options'] as List?)?.cast<String>() ?? const [],
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'label': label, 'type': type, 'unit': unit,
    if (options.isNotEmpty) 'options': options,
  };

  /// True if this is the primary price field (first number field with ₪ unit).
  bool get isPriceField => type == 'number' && unit.contains('₪');
}

/// Immutable data model for a category document.
///
/// Firestore path: `categories/{id}`
class Category {
  final String id;
  final String name;
  final String img;
  final String iconName;
  final int order;
  final String parentId; // empty = top-level
  final int clickCount;
  final int bookingCount;
  final DateTime? createdAt;
  final bool autoCreated;
  final bool isHidden;
  final List<SchemaField> serviceSchema;

  const Category({
    required this.id,
    this.name = '',
    this.img = '',
    this.iconName = '',
    this.order = 999,
    this.parentId = '',
    this.clickCount = 0,
    this.bookingCount = 0,
    this.createdAt,
    this.autoCreated = false,
    this.isHidden = false,
    this.serviceSchema = const [],
  });

  bool get isTopLevel => parentId.isEmpty;
  bool get isSubCategory => parentId.isNotEmpty;
  bool get hasImage => img.isNotEmpty;
  bool get hasSchema => serviceSchema.isNotEmpty;

  /// The primary price field from the schema, if any.
  SchemaField? get primaryPriceField {
    try {
      return serviceSchema.firstWhere((f) => f.isPriceField);
    } catch (_) {
      return null;
    }
  }

  // ── Firestore serialisation ───────────────────────────────────────────

  factory Category.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return Category(
      id:            doc.id,
      name:          d['name']         as String? ?? '',
      img:           d['img']          as String? ?? '',
      iconName:      d['iconName']     as String? ?? '',
      order:         (d['order']       as num?)?.toInt() ?? 999,
      parentId:      d['parentId']     as String? ?? '',
      clickCount:    (d['clickCount']  as num?)?.toInt() ?? 0,
      bookingCount:  (d['bookingCount'] as num?)?.toInt() ?? 0,
      createdAt:     (d['createdAt']   as Timestamp?)?.toDate(),
      autoCreated:   d['autoCreated']  as bool? ?? false,
      isHidden:      d['isHidden']     as bool? ?? false,
      serviceSchema: (d['serviceSchema'] as List?)
          ?.map((e) => SchemaField.fromMap(e as Map<String, dynamic>))
          .toList() ?? const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'name':          name,
    'img':           img,
    'iconName':      iconName,
    'order':         order,
    'parentId':      parentId,
    'clickCount':    clickCount,
    'bookingCount':  bookingCount,
    'createdAt':     createdAt != null ? Timestamp.fromDate(createdAt!) : null,
    'autoCreated':   autoCreated,
    'isHidden':      isHidden,
    if (serviceSchema.isNotEmpty)
      'serviceSchema': serviceSchema.map((f) => f.toJson()).toList(),
  };

  // ── Immutable updates ─────────────────────────────────────────────────

  Category copyWith({
    String? id,
    String? name,
    String? img,
    String? iconName,
    int? order,
    String? parentId,
    int? clickCount,
    int? bookingCount,
    DateTime? createdAt,
    bool? autoCreated,
    bool? isHidden,
    List<SchemaField>? serviceSchema,
  }) {
    return Category(
      id:            id            ?? this.id,
      name:          name          ?? this.name,
      img:           img           ?? this.img,
      iconName:      iconName      ?? this.iconName,
      order:         order         ?? this.order,
      parentId:      parentId      ?? this.parentId,
      clickCount:    clickCount    ?? this.clickCount,
      bookingCount:  bookingCount  ?? this.bookingCount,
      createdAt:     createdAt     ?? this.createdAt,
      autoCreated:   autoCreated   ?? this.autoCreated,
      isHidden:      isHidden      ?? this.isHidden,
      serviceSchema: serviceSchema ?? this.serviceSchema,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Category && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
