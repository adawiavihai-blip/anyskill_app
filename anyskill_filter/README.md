# מערכת סינון דינמית — AnySkill

## מה זה?

החלפה למודאל הסינון הקיים. במקום פילטרים אחידים לכל הקטגוריות (מחיר/דירוג/מרחק בלבד), המערכת קוראת **schema של פילטרים מ-Firestore** לכל קטגוריה. הוספת קטגוריה חדשה = עריכה ב-Firestore, בלי שינוי בקוד.

## למה זה חשוב?

- **לפני:** מורה אנגלית מסונן באותם פילטרים כמו מדביר ג'וקים
- **אחרי:** כל קטגוריה מציגה את הפילטרים הרלוונטיים שלה

---

## מבנה הקבצים

```
lib/
├── models/
│   └── filter_schema.dart          ← מודלים (Section, Option, FilterSchema)
├── services/
│   └── filter_schema_service.dart  ← קריאה מ-Firestore + cache
└── widgets/
    ├── dynamic_filter_sheet.dart   ← הקומפוננטה הראשית
    └── filter_components/
        ├── filter_section_cards.dart    ← בלוק "כרטיסים"
        ├── filter_section_chips.dart    ← בלוק "צ'יפים"
        ├── filter_section_switches.dart ← בלוק "מתגים"
        ├── filter_section_price.dart    ← בלוק "טווח מחיר"
        ├── filter_section_rating.dart   ← בלוק "דירוג"
        └── filter_section_days_time.dart← בלוק "ימים+שעות"
```

---

## שלבי הטמעה (לפי הסדר)

### שלב 1 — העתקת קבצים
העתק את כל התיקייה `lib/` למיקום המקביל בפרויקט.

### שלב 2 — תלויות
ודא שב-`pubspec.yaml` יש:
```yaml
dependencies:
  cloud_firestore: ^4.0.0  # או הגרסה שלך
  flutter:
    sdk: flutter
```

### שלב 3 — Firestore: יצירת schema לקטגוריות קיימות
פתח את Firebase Console → Firestore → `categories` collection.
לכל מסמך, הוסף שדה `filterSchema` (Map). מבנה לדוגמה ב-`firestore_seed_examples.md`.

### שלב 4 — החלפת המודאל הקיים
בקובץ `category_results_screen.dart` (שורה ~410, ~1813), במקום:
```dart
showModalBottomSheet(context: context, builder: (_) => _FilterSheet(...))
```
שים:
```dart
showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => DynamicFilterSheet(
    categoryId: widget.category.id,
    initialFilters: _activeFilters,
    onApply: (filters) {
      setState(() => _activeFilters = filters);
    },
  ),
);
```

### שלב 5 — חיבור ל-`expert_filter.dart`
המודאל מחזיר `Map<String, dynamic>` של פילטרים פעילים. הוסף ב-`filterExperts()`:
```dart
Map<String, dynamic>? categoryFilters,  // פרמטר חדש
```
ובלוגיקה — לולאה שמסננת לפי כל מפתח ב-`categoryFilters`.

---

## בדיקה מהירה

1. הרץ את האפליקציה
2. לך לקטגוריה כלשהי שכבר הוגדר לה `filterSchema`
3. לחץ על כפתור הסינון
4. אמור להיפתח המודאל החדש עם הפילטרים הספציפיים לקטגוריה

אם הקטגוריה לא הוגדרה — המודאל יציג fallback של פילטרים בסיסיים (מחיר, דירוג, מרחק).

---

## מסמכים נוספים

- `firestore_seed_examples.md` — דוגמאות JSON של schemas לקטגוריות שונות
- `INTEGRATION_NOTES.md` — נקודות חשובות והבדלים מהמערכת הישנה
