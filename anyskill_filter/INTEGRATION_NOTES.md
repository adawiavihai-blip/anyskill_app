# הוראות אינטגרציה — שלב אחר שלב

מסמך זה מיועד ל-**Claude Code**. תן לו אותו ישירות עם שאר הקבצים והוא ידע מה לעשות.

---

## 🎯 מטרה

החלפת מודאל הסינון הישן (`_FilterSheet` ב-`global_search_bar.dart` + `_showRatingFilterSheet`/`_showDistanceFilterSheet` ב-`category_results_screen.dart`) במערכת דינמית שטוענת פילטרים מ-Firestore לכל קטגוריה.

---

## 📋 צ'קליסט יישום

### ☐ שלב 1: העתקת קבצים
```
lib/models/filter_schema.dart                          ← חדש
lib/services/filter_schema_service.dart                ← חדש
lib/widgets/dynamic_filter_sheet.dart                  ← חדש
lib/widgets/filter_components/                         ← תיקייה חדשה (6 קבצים)
```
ודא שאין התנגשויות עם קבצים קיימים.

### ☐ שלב 2: אימות תלויות
פתח `pubspec.yaml` וודא שיש:
```yaml
dependencies:
  cloud_firestore: ^4.0.0
  flutter:
    sdk: flutter
```
אם cloud_firestore כבר קיים בגרסה אחרת — זה בסדר, אל תשנה.

### ☐ שלב 3: יצירת schema לקטגוריה ראשונה (לבדיקה)
פתח Firebase Console → Firestore → `categories`. בחר קטגוריה אחת (למשל "אנגלית" או "הדברה") והוסף לה שדה `filterSchema` (Map). מבנה ב-`firestore_seed_examples.md`.

**אל תיגע בכל הקטגוריות בבת אחת** — תתחיל מאחת, תבדוק שעובד, ואז תכפיל.

### ☐ שלב 4: החלפה ב-`category_results_screen.dart`

**מצא** (סביב שורה 410, 1813, 1863, 2239, 2288):
```dart
showModalBottomSheet(
  context: context,
  builder: (_) => _FilterSheet(...),
)
```

**החלף ל:**
```dart
showModalBottomSheet(
  context: context,
  isScrollControlled: true,        // חובה — בלי זה המודאל ייחתך
  backgroundColor: Colors.transparent,
  builder: (_) => DynamicFilterSheet(
    categoryId: widget.category.id,        // או מאיפה שאתה לוקח את ה-ID
    initialFilters: _activeFilters ?? {},
    estimatedResultCount: _experts.length, // אופציונלי
    onApply: (filters) {
      setState(() {
        _activeFilters = filters;
        _refilterExperts();   // הפונקציה הקיימת שלך
      });
    },
  ),
);
```

ובראש הקובץ, הוסף:
```dart
import 'package:[YOUR_PROJECT]/widgets/dynamic_filter_sheet.dart';
```
(החלף `[YOUR_PROJECT]` בשם הפרויקט שלך מ-`pubspec.yaml`)

### ☐ שלב 5: הרחבת `expert_filter.dart`

הקובץ הקיים (`filterExperts()`) מקבל פרמטרים בודדים. נוסיף לו פרמטר חדש:

**הוסף לחתימה:**
```dart
List<Map<String, dynamic>> filterExperts(
  List<Map<String, dynamic>> experts, {
  String query = '',
  bool underHundred = false,
  double minRating = 0,
  double? maxPricePerHour,
  double? maxDistanceKm,
  Position? myPosition,
  bool onlineOnly = false,
  Map<String, dynamic>? dynamicFilters,  // ← חדש
}) {
  // ... הקוד הקיים ...

  // בסוף, לפני ה-return:
  if (dynamicFilters != null && dynamicFilters.isNotEmpty) {
    experts = _applyDynamicFilters(experts, dynamicFilters);
  }

  return experts;
}
```

**הוסף פונקציה חדשה בסוף הקובץ:**
```dart
List<Map<String, dynamic>> _applyDynamicFilters(
  List<Map<String, dynamic>> experts,
  Map<String, dynamic> filters,
) {
  return experts.where((expert) {
    for (final entry in filters.entries) {
      final sectionId = entry.key;
      final value = entry.value;

      // דוגמאות לטיפול בכל סוג. תאים בהתאם ל-providerField שב-schema:
      switch (sectionId) {
        case 'price':
          final price = (expert['pricePerHour'] as num?)?.toDouble() ?? 0;
          final from = (value['from'] as num?)?.toDouble() ?? 0;
          final to = (value['to'] as num?)?.toDouble() ?? double.infinity;
          if (price < from || price > to) return false;
          break;

        case 'rating':
          final rating = (expert['rating'] as num?)?.toDouble() ?? 0;
          if (rating < (value as double)) return false;
          break;

        case 'pests':
        case 'service':
        case 'animal':
          // multi-select chips
          final selected = value as Set<String>;
          final providerData = expert['pestControlProfile']?['pestTypes'] ??
                              expert['petCareProfile']?['services'] ??
                              [];
          final providerSet = (providerData as List).cast<String>().toSet();
          if (!selected.any(providerSet.contains)) return false;
          break;

        case 'traits':
        case 'license':
        case 'cert':
          // switches — לבדוק שכל ה-flags פעילים
          final required = value as Set<String>;
          for (final flag in required) {
            if (expert[flag] != true && expert['categoryTags']?.contains(flag) != true) {
              return false;
            }
          }
          break;

        case 'goal':
        case 'format':
        case 'urgency':
          // single-select cards
          final tags = (expert['categoryTags'] as List?)?.cast<String>() ?? [];
          if (!tags.contains(value as String)) return false;
          break;

        case 'availability':
          // ימים+שעות — בדוק מול workingHours
          final days = value['days'] as Set<int>?;
          if (days != null && days.isNotEmpty) {
            final workingHours = expert['workingHours'] as Map?;
            if (workingHours == null) return false;
            final hasMatchingDay = days.any(
              (d) => workingHours.containsKey(d.toString()),
            );
            if (!hasMatchingDay) return false;
          }
          break;
      }
    }
    return true;
  }).toList();
}
```

⚠️ **חשוב:** המיפוי בין `sectionId` ל-`providerField` תלוי בשמות השדות בפרופיל הספק שלך. תאם את ה-`switch` למבנה האמיתי. הדוגמה למעלה היא נקודת התחלה.

### ☐ שלב 6: בדיקה ראשונית
1. הרץ `flutter run` או `flutter run -d chrome`
2. נווט לקטגוריה שיצרת לה schema
3. לחץ על כפתור הסינון → אמור להיפתח המודאל החדש
4. ודא ש:
   - הפילטרים מתאימים לקטגוריה
   - לחיצה משנה את "X תוצאות" בכפתור התחתון
   - "הצג" סוגר וחוזר עם תוצאות מסוננות

### ☐ שלב 7: ניקוי קוד ישן (אחרי שעובד!)
- הסר את `_FilterSheet`, `_showRatingFilterSheet`, `_showDistanceFilterSheet`
- הסר את ה-state הקודם: `_filterUnder100`, `_minRating`, `_maxDistanceKm`
- החלף ב-`Map<String, dynamic> _activeFilters = {}` יחיד

---

## 🔄 איך מוסיפים קטגוריה חדשה אחרי?

1. פתח Firebase Console → `categories`
2. הוסף מסמך חדש (או ערוך קיים)
3. הוסף שדה `filterSchema` עם המבנה מ-`firestore_seed_examples.md`
4. **זהו.** האפליקציה תרים את זה תוך 30 דקות (cache TTL).
   להאצה מיידית בקוד:
   ```dart
   FilterSchemaService.instance.invalidate(categoryId);
   ```

---

## ⚠️ נקודות לתשומת לב

### 1. לקטגוריות בלי schema
המערכת תציג fallback של מחיר + דירוג בלבד. **לא תקרוס**. זה מאפשר להעלות לאוויר בלי להגדיר schema לכל הקטגוריות מראש.

### 2. שינוי ב-Firestore לא דורש פרסום גרסה
כל שינוי ב-`filterSchema` משפיע על האפליקציה תוך 30 דקות (או מיידי עם invalidate). **אין צורך ב-App Store / Play Store update.**

### 3. תאימות לאחור (`expert_filter.dart`)
הפרמטר `dynamicFilters` הוא אופציונלי. כל הקריאות הקיימות ל-`filterExperts()` ימשיכו לעבוד בלי שינוי. רק קריאות חדשות יעבירו את ה-filters החדשים.

### 4. ביצועים
- ה-schema נטען פעם ב-30 דק' (cache)
- הפילטור עצמו רץ client-side על הרשימה הקיימת — אותו ביצועים כמו לפני
- לא נוספות שאילתות Firestore חדשות בעת סינון

### 5. RTL + פונט
הקוד משתמש ב-`Directionality(textDirection: TextDirection.rtl)`. הפונט יילקח אוטומטית מ-`ThemeData` של האפליקציה (שכבר מוגדר Assistant ב-CLAUDE.md §6.4).

### 6. Haptic feedback
מובנה — `HapticFeedback.lightImpact()` בכל לחיצה על פילטר, `mediumImpact` באיפוס/החלה.

---

## 🐛 פתרון בעיות נפוצות

| בעיה | סיבה | פתרון |
|---|---|---|
| המודאל נחתך מלמעלה | חסר `isScrollControlled: true` | הוסף ל-`showModalBottomSheet` |
| הפילטרים לא מופיעים | אין `filterSchema` ב-Firestore | תופיע fallback. הוסף schema לקטגוריה |
| המספר בכפתור לא מתעדכן | `estimatedResultCount` לא מועבר | העבר את `_experts.length` |
| איפוס לא מנקה state | ה-parent לא מקבל את `{}` | ודא ש-`onApply: (f) => setState(() => _activeFilters = f)` רץ |
| הרבה גלילה כשאין הרבה פילטרים | זה תקין | המודאל מתאים את עצמו לתוכן (`mainAxisSize: min`) |

---

## 📞 הצעדים הבאים (אחרי שזה עובד)

1. **שלב 2 (Phase 2):** Live count אמיתי מ-Firestore (במקום אומדן). ראה TODO ב-`dynamic_filter_sheet.dart` שורה 62.
2. **שלב 3 (Phase 3):** Saved searches — שמירת הפילטרים ב-`users/{uid}/saved_searches`.
3. **שלב 4 (Phase 4):** פאנל אדמין לעריכת `filterSchema` ב-UI (במקום Firebase Console).
4. **שלב 5 (Phase 5):** Analytics — `activity_log` writes על כל toggle של פילטר.

---

**זהו. הצלחה!**
