// lib/models/filter_schema.dart
//
// מודלים לסינון דינמי. נטענים מ-Firestore ומגדירים איך מודאל הסינון נראה
// לכל קטגוריה. הוספת קטגוריה חדשה = יצירת FilterSchema ב-Firestore, ללא קוד.

import 'package:flutter/foundation.dart';

/// סוג בלוק הסינון. כל סוג מרונדר על ידי widget אחר.
enum FilterSectionType {
  cards,        // כרטיסים גדולים עם אייקון (לבחירה ראשית)
  chips,        // צ'יפים קטנים (לבחירה מרובה קומפקטית)
  switches,     // שורות עם תיאור ארוך + מתג
  price,        // טווח מחירים עם היסטוגרמה
  rating,       // דירוג מינימלי (4.0+/4.5+/4.8+)
  daysTime,     // ימים בשבוע + חלקי יום
  banner,       // הודעת מידע (לא פילטר)
}

/// אופציה בודדת בתוך section (כרטיס/צ'יפ/מתג)
@immutable
class FilterOption {
  final String value;          // הערך שיישמר ב-state ויישלח ל-Firestore query
  final String label;          // הטקסט שמופיע למשתמש
  final String? meta;          // טקסט משני: "42 מורים" / "+₪250"
  final String? emoji;         // אימוג'י (אופציונלי)
  final String? bgColor;       // hex או gradient string
  final int? count;            // כמה ספקים תואמים (להצגה דינמית)

  const FilterOption({
    required this.value,
    required this.label,
    this.meta,
    this.emoji,
    this.bgColor,
    this.count,
  });

  factory FilterOption.fromMap(Map<String, dynamic> m) => FilterOption(
        value: m['value'] as String,
        label: m['label'] as String,
        meta: m['meta'] as String?,
        emoji: m['emoji'] as String?,
        bgColor: m['bgColor'] as String?,
        count: m['count'] as int?,
      );

  Map<String, dynamic> toMap() => {
        'value': value,
        'label': label,
        if (meta != null) 'meta': meta,
        if (emoji != null) 'emoji': emoji,
        if (bgColor != null) 'bgColor': bgColor,
        if (count != null) 'count': count,
      };
}

/// section של פילטר (קבוצת אופציות מסוג אחד)
@immutable
class FilterSection {
  final String id;                  // מזהה ייחודי, יישמר כמפתח ב-state
  final String title;               // כותרת ("המטרה שלך")
  final String? subtitle;           // תיאור משני ("בחר אחד")
  final FilterSectionType type;
  final String? providerField;      // שדה ב-providers/{uid} לבדוק מולו
                                    // לדוגמה: "petCareProfile.animalTypes"
  final bool singleSelect;          // לכרטיסים: האם רק אחד או מרובה
  final bool required;              // מציג תג "חובה"
  final List<FilterOption> options; // לכרטיסים/צ'יפים/מתגים
  final Map<String, dynamic>? extra; // מידע נוסף לפי type
                                     // price: {min, max, histogram, defaultRange}
                                     // banner: {html, severity}

  const FilterSection({
    required this.id,
    required this.title,
    required this.type,
    this.subtitle,
    this.providerField,
    this.singleSelect = false,
    this.required = false,
    this.options = const [],
    this.extra,
  });

  factory FilterSection.fromMap(Map<String, dynamic> m) {
    return FilterSection(
      id: m['id'] as String,
      title: m['title'] as String,
      subtitle: m['subtitle'] as String?,
      type: _parseType(m['type'] as String?),
      providerField: m['providerField'] as String?,
      singleSelect: m['singleSelect'] as bool? ?? false,
      required: m['required'] as bool? ?? false,
      options: (m['options'] as List?)
              ?.map((o) => FilterOption.fromMap(Map<String, dynamic>.from(o)))
              .toList() ??
          [],
      extra: m['extra'] != null ? Map<String, dynamic>.from(m['extra']) : null,
    );
  }

  static FilterSectionType _parseType(String? s) {
    switch (s) {
      case 'cards':
        return FilterSectionType.cards;
      case 'chips':
        return FilterSectionType.chips;
      case 'switches':
        return FilterSectionType.switches;
      case 'price':
        return FilterSectionType.price;
      case 'rating':
        return FilterSectionType.rating;
      case 'daysTime':
      case 'days_time':
        return FilterSectionType.daysTime;
      case 'banner':
        return FilterSectionType.banner;
      default:
        return FilterSectionType.chips;
    }
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        'type': type.name,
        if (providerField != null) 'providerField': providerField,
        'singleSelect': singleSelect,
        'required': required,
        'options': options.map((o) => o.toMap()).toList(),
        if (extra != null) 'extra': extra,
      };
}

/// ה-schema המלא של קטגוריה
@immutable
class FilterSchema {
  final String categoryId;
  final String categoryLabel;
  final String? searchPlaceholder;
  final List<FilterSection> sections;
  final int version;             // לעדכוני schema עתידיים

  const FilterSchema({
    required this.categoryId,
    required this.categoryLabel,
    required this.sections,
    this.searchPlaceholder,
    this.version = 1,
  });

  factory FilterSchema.fromFirestore(String id, Map<String, dynamic> data) {
    final schemaMap = data['filterSchema'] as Map<String, dynamic>?;
    final sections = (schemaMap?['sections'] as List?)
            ?.map((s) => FilterSection.fromMap(Map<String, dynamic>.from(s)))
            .toList() ??
        [];
    return FilterSchema(
      categoryId: id,
      categoryLabel: data['name'] as String? ?? '',
      searchPlaceholder: schemaMap?['searchPlaceholder'] as String?,
      sections: sections,
      version: schemaMap?['version'] as int? ?? 1,
    );
  }

  /// fallback בסיסי לקטגוריות בלי schema מוגדר
  factory FilterSchema.fallback(String id, String label) => FilterSchema(
        categoryId: id,
        categoryLabel: label,
        searchPlaceholder: 'חפש $label',
        sections: [
          const FilterSection(
            id: 'price',
            title: 'מחיר לשעה',
            type: FilterSectionType.price,
            providerField: 'pricePerHour',
            extra: {'min': 0, 'max': 500, 'defaultRange': [0, 500]},
          ),
          const FilterSection(
            id: 'rating',
            title: 'דירוג מינימלי',
            type: FilterSectionType.rating,
            providerField: 'rating',
          ),
        ],
      );
}
