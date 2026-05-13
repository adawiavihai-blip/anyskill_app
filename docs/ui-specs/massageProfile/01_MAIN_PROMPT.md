# 🚀 AnySkill - Massage Category Upgrade | שדרוג קטגוריית עיסוי

> **קובץ ראשי - קרא אותו קודם** | **Main file - Read this first**
>
> פרויקט: שדרוג של קטגוריית עיסוי באפליקציית AnySkill ברמה עולמית.
> Project: World-class upgrade of the massage category in the AnySkill app.

---

## ⛔ עקרונות חובה - אל תפר! | CRITICAL RULES - DO NOT BREAK!

### מה אסור לשנות (לא נוגעים) | What NOT to change (untouchable)

1. **דף קטגוריית עיסוי** (רשימת כל המעסים) - **לא לשנות כלום**. נשאר כמו שהוא היום.
2. **דף פרופיל הלקוח - מבנה כללי** - לא משנים שום דבר ב:
   - Header (חץ חזרה, שם, ♡)
   - Profile card (תמונה, שם, ✓, נותן שירות, קטגוריה)
   - סטטיסטיקות קיימות (עבודות, דירוג, ביקורות, התנדבויות)
   - גלריית עבודות + וידאו היכרות
   - אודות
   - השירות (פגישה קצרה / מורחב / חבילה מלאה) - **לא נוגעים**
   - זמינות (יומן) - **לא נוגעים, נשאר היומן הקיים**
   - ביקורות
   - כפתור תחתון "בחר תאריך ושעה" - **קיים, לא משנים אותו**
3. **דף עריכת פרופיל - מבנה כללי** - לא משנים שום דבר במה שכבר קיים שם
4. **Routing של קטגוריות אחרות** - לא נוגעים
5. **לא להשתמש ב-Claude API** - השתמש ב-Gemini בלבד אם צריך AI

### מה כן משדרגים | What TO upgrade

1. **הוספת בלוק "הגדרות עיסוי" בעריכת פרופיל** - מתווסף **רק אם** המעסה סימן/ה תת-קטגוריה "עיסוי", **מתחת** לבחירת התת-קטגוריה
2. **הוספת בלוק "בנה את הטיפול שלך" בדף פרופיל הלקוח** - מתווסף **בין** "אודות" ל"השירות", **רק** למעסים שהקטגוריה שלהם היא "עיסוי"
3. **הכל מסונכרן** - מה שהמעסה סימן/ה בעריכה - יוצג בדף הלקוח
4. **כפתור "בחר תאריך ושעה"** - יפתח את **היומן הקיים באפליקציה** (לא לבנות חדש), שכבר מסונכרן עם זמינות המעסה

---

## 🎯 Goal | מטרה

להפוך את AnySkill לאפליקציה ברמה עולמית בקטגוריית עיסוי - מתחרה ל-Zeel, Soothe, Urban Company - תוך שמירה על המבנה הקיים והוספת התאמה אישית עמוקה לכל הזמנה.

---

## 📦 קבצים נוספים בפרויקט הזה | Additional files in this project

- **`02_PROVIDER_EDIT_SCREEN.md`** - מפרט מלא של דף עריכת פרופיל המעסה (השדות החדשים)
- **`03_CLIENT_BOOKING_SCREEN.md`** - מפרט מלא של דף פרופיל הלקוח (החלק החדש)

קרא את שני הקבצים הנוספים לפני שמתחיל לקודד.

---

## 🗄️ Firestore Schema - שדות חדשים

### Collection: `users` (או היכן ששמורים נותני שירות)

הוסף את השדה הבא **רק אם** המסמך מכיל `category == 'massage'` או שאחת מתת-הקטגוריות שלו היא 'massage':

```javascript
{
  // ...כל השדות הקיימים נשארים בדיוק כמו שהם...

  // === שדה חדש - מופיע רק למעסים ===
  "massageProfile": {
    // סוגי טיפולים שהמעסה מציע (מתוך 14 אופציות)
    "specialties": ["swedish", "deep_tissue", "pregnancy", "sports", "aromatherapy"],

    // אופציות מיקום
    "serviceLocations": {
      "home": {
        "enabled": true,
        "radiusKm": 15,
        "travelFee": 20  // מחיר נסיעה לכיוון אחד (₪) - אופציונלי
      },
      "clinic": {
        "enabled": true,
        "address": "רחוב הרצל 15, תל אביב",
        "floor": "קומה 3, דירה 12"  // אופציונלי
      }
    },

    // תוספות שמציע + מחירים
    "addOns": [
      { "id": "aromatherapy_oil", "enabled": true, "customPrice": 25 },
      { "id": "hot_stones", "enabled": true, "customPrice": 40 },
      { "id": "head_massage", "enabled": true, "customPrice": 15 },
      { "id": "hot_towels", "enabled": true, "customPrice": 20 },
      { "id": "theragun", "enabled": true, "customPrice": 30 },
      { "id": "scalp_oil_treatment", "enabled": true, "customPrice": 35 },
      { "id": "post_nap", "enabled": true, "customPrice": 20 },
      // תוספות אישיות שהמעסה הוסיף בעצמו:
      {
        "id": "custom_xyz123",
        "enabled": true,
        "isCustom": true,
        "nameHe": "טיפול ייחודי שלי",
        "icon": "✨",
        "customPrice": 50
      }
    ],

    // משכי טיפול ומחירי בסיס
    "durations": [
      { "minutes": 30, "enabled": true, "price": 100 },
      { "minutes": 60, "enabled": true, "price": 150 },
      { "minutes": 90, "enabled": true, "price": 210 },
      { "minutes": 120, "enabled": true, "price": 270 }
    ],

    // עוצמות לחץ
    "pressureLevels": ["light", "medium", "strong"],

    // סגנון שיחה
    "conversationStyles": ["chatty", "minimal"],

    // === חדש: חבילות הנחה ===
    "discountPackages": [
      {
        "id": "pkg_001",
        "name": "חבילת 5 טיפולים",
        "sessionsCount": 5,
        "discountPercent": 15,
        "validityDays": 180,
        "enabled": true
      },
      {
        "id": "pkg_002",
        "name": "חבילת 10 טיפולים",
        "sessionsCount": 10,
        "discountPercent": 25,
        "validityDays": 365,
        "enabled": true
      }
    ]
  }
}
```

### Collection: `bookings` (חדש בכל הזמנת עיסוי)

```javascript
{
  // ...שדות הזמנה קיימים...

  "massagePreferences": {
    "massageType": "swedish",
    "location": "home",  // "home" | "clinic"
    "duration": 60,
    "addOns": ["head_massage"],
    "pressureLevel": "medium",
    "focusAreas": ["neck", "upper_back"],
    "additionalNotes": "רגישות באזור הצוואר",
    "musicPreference": "calm",
    "conversationStyle": "minimal",
    "packageId": null  // אם ההזמנה היא חלק מחבילה
  },

  "priceBreakdown": {
    "basePrice": 150,
    "addOnsTotal": 15,
    "travelFee": 0,
    "discount": 0,
    "total": 165
  }
}
```

---

## 🛠️ קבצים שצריך ליצור | Files to create

### Models
- `lib/models/massage_profile.dart` - מודל הפרופיל החדש
- `lib/models/massage_booking_preferences.dart` - מודל ההעדפות בהזמנה
- `lib/models/discount_package.dart` - מודל חבילת הנחה
- `lib/models/massage_addon.dart` - מודל תוספת

### Constants
- `lib/constants/massage_specialties.dart` - 14 סוגי הטיפולים עם תרגומים, אייקונים, צבעים
- `lib/constants/massage_addons_catalog.dart` - 18 התוספות הגלובליות (קטלוג ראשי)
- `lib/constants/massage_focus_areas.dart` - 8 אזורי הגוף

### Provider Edit Screen
- `lib/screens/provider_edit/widgets/massage_settings_block.dart` - הבלוק הראשי שמופיע אחרי בחירת "עיסוי"
- `lib/screens/provider_edit/widgets/massage_specialties_picker.dart`
- `lib/screens/provider_edit/widgets/massage_locations_editor.dart`
- `lib/screens/provider_edit/widgets/massage_addons_manager.dart`
- `lib/screens/provider_edit/widgets/massage_durations_editor.dart`
- `lib/screens/provider_edit/widgets/massage_discount_packages_editor.dart`
- `lib/screens/provider_edit/widgets/massage_preferences_picker.dart`

### Client Profile Screen
- `lib/screens/provider_profile/widgets/build_your_treatment_block.dart` - הבלוק הראשי
- `lib/screens/provider_profile/widgets/preference_card_wrapper.dart` - עטיפה לכל סקציה
- `lib/screens/provider_profile/widgets/massage_type_selector.dart`
- `lib/screens/provider_profile/widgets/location_selector.dart`
- `lib/screens/provider_profile/widgets/duration_selector.dart`
- `lib/screens/provider_profile/widgets/pressure_slider.dart`
- `lib/screens/provider_profile/widgets/focus_areas_selector.dart` (כולל body SVG)
- `lib/screens/provider_profile/widgets/addons_selector.dart`
- `lib/screens/provider_profile/widgets/discount_packages_display.dart`
- `lib/screens/provider_profile/widgets/ambiance_selector.dart`
- `lib/screens/provider_profile/widgets/booking_summary_bar.dart` - סיכום עם המחיר

### Services
- `lib/services/massage_booking_service.dart` - לוגיקת חישוב מחירים, סנכרון, שמירת העדפות
- `lib/services/massage_smart_suggestions_service.dart` - המלצות אוטומטיות (חזרה על הזמנה אחרונה, AI suggestions)

### Cloud Functions (functions/index.js)
- `syncMassageProfileToProviderProfile` - מסנכרן את ההגדרות עם הפרופיל הציבורי
- `calculatePackageDiscount` - מחשב הנחות חבילה

---

## 🌐 Localization | תרגומים

הוסף ל-`l10n/app_he.arb` ו-`l10n/app_en.arb` - רשימה מלאה ב-`02_PROVIDER_EDIT_SCREEN.md` ו-`03_CLIENT_BOOKING_SCREEN.md`.

---

## ✅ Acceptance Criteria | קריטריונים לקבלה

### חובה לעבוד | Must work
- [ ] בעריכת פרופיל - בחירת תת-קטגוריה "עיסוי" פותחת **אוטומטית** את בלוק "הגדרות עיסוי" מתחת
- [ ] ביטול בחירת "עיסוי" - מסתיר את הבלוק (אבל שומר את ההגדרות במקרה שיחזיר)
- [ ] כל ההגדרות נשמרות ל-Firestore תחת `massageProfile`
- [ ] בדף פרופיל הלקוח - אם הקטגוריה היא "עיסוי" - מופיע אוטומטית בלוק "בנה את הטיפול שלך" בין "אודות" ל"השירות"
- [ ] רק סוגי טיפולים שהמעסה סימן - מוצגים ללקוח
- [ ] רק תוספות שהמעסה אישר - מוצגות ללקוח, עם המחירים שהיא קבעה
- [ ] בחירת "בקליניקה" - מציגה את הכתובת שהמעסה הזינה
- [ ] בחירת "בבית הלקוח" - מציגה "המעסה מגיעה אליך · עד 30 דק׳" + מחיר הנסיעה אם הוגדר
- [ ] חבילות הנחה - אם המעסה הגדיר, מופיעות בדף הלקוח כסקציה נפרדת
- [ ] לחיצה על "בחר תאריך ושעה" - פותחת את **היומן הקיים** (לא חדש!) עם זמינות המעסה
- [ ] סיכום הזמנה בתחתית מתעדכן בזמן אמת לפי הבחירות
- [ ] תמיכה מלאה ב-RTL (עברית)
- [ ] תמיכה ב-light/dark mode
- [ ] flutter analyze: 0 issues

### אסור | Must NOT happen
- [ ] **לא לגעת** בחלקים הקיימים של דף הפרופיל (Header, Profile card, Stats, Gallery, About, Services, Calendar, Reviews, CTA button)
- [ ] **לא לגעת** ביומן הקיים - להשתמש בו כפי שהוא
- [ ] **לא לשנות** את routing של קטגוריות אחרות
- [ ] **לא להוסיף** monthly subscriptions בשום מקום
- [ ] **לא להשתמש** ב-Claude API (Gemini בלבד אם צריך)
- [ ] **לא להציג** הגדרות עיסוי אם המעסה לא בחר תת-קטגוריה "עיסוי"

---

## 🎨 Design System

### Colors
```dart
// Primary
const primaryDark = Color(0xFF1A1A1A);
const primaryDarkSecondary = Color(0xFF2D3142);

// Backgrounds
const cream = Color(0xFFFBFAF6);
const creamSecondary = Color(0xFFF5F2EC);
const creamBorder = Color(0xFFEAE7DF);
const surfacePrimary = Color(0xFFFFFFFF);

// Specialty pastels (for icon backgrounds)
const swedishBg = Color(0xFFE1F5EE);
const deepTissueBg = Color(0xFFFFF1ED);
const pregnancyBg = Color(0xFFFFF0F5);
const hotStonesBg = Color(0xFFFFF8E7);
const sportsBg = Color(0xFFEBF5FF);
const couplesBg = Color(0xFFF3E8FF);
const aromaBg = Color(0xFFECFDF5);

// Status
const successGreen = Color(0xFF10B981);
const warningAmber = Color(0xFFF59E0B);
const focusAreaBg = Color(0xFFFFF8E7);
const focusAreaText = Color(0xFF92400E);

// Hero gradient
const heroGradientStart = Color(0xFF2D3142);
const heroGradientEnd = Color(0xFF4A5060);
```

### Typography
```dart
// Sizes
const h1 = 22.0;     // Page title
const h2 = 17.0;     // Section title
const h3 = 14.0;     // Subsection title
const body = 13.0;   // Body text
const caption = 11.0; // Captions, labels
const tiny = 10.0;   // Tags, badges

// Weights - only use these two!
const regular = FontWeight.w400;
const medium = FontWeight.w500;
```

### Spacing & Radius
```dart
const cardRadius = 20.0;        // Major cards
const elementRadius = 14.0;     // Inner elements
const chipRadius = 999.0;       // Pills/chips
const cardPadding = 18.0;       // Inside cards
const cardGap = 12.0;           // Between cards
```

### Component Patterns

**Active selection (selected state):**
```dart
decoration: BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A1A1A), Color(0xFF2D3142)],
  ),
  borderRadius: BorderRadius.circular(14),
)
```

**Inactive selection:**
```dart
decoration: BoxDecoration(
  color: Colors.white,
  border: Border.all(color: Color(0xFFEAE7DF), width: 1),
  borderRadius: BorderRadius.circular(14),
)
```

**Section card wrapper:**
```dart
decoration: BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(20),
)
padding: EdgeInsets.all(18)
```

---

## 🚀 סדר ביצוע מומלץ | Recommended Order

### Phase 1: Foundation (יום 1-2)
1. Models + constants
2. Firestore schema migrations (אם צריך)
3. Localization files

### Phase 2: Provider Edit Screen (יום 3-5)
1. בלוק `MassageSettingsBlock` עם conditional rendering לפי תת-קטגוריה
2. כל ה-pickers (specialties, locations, addons, durations, packages, preferences)
3. שמירה ל-Firestore

### Phase 3: Client Profile Screen (יום 6-8)
1. בלוק `BuildYourTreatmentBlock` עם conditional rendering לפי קטגוריה
2. כל הסלקטורים
3. סנכרון עם המעסה (real-time streams)
4. סיכום הזמנה דינמי
5. חיבור ל-CTA הקיים שפותח את היומן הקיים

### Phase 4: Smart Features (יום 9)
1. Smart suggestions (חזרה להעדפות אחרונות)
2. AI recommendations (Gemini)
3. Animations & microinteractions

### Phase 5: Testing (יום 10)
1. Test flow מלא: יצירת מעסה → הגדרות → לקוח → הזמנה
2. Edge cases (מעסה ללא תוספות, ללא קליניקה, וכו')
3. RTL & dark mode
4. Performance optimization
5. flutter analyze - 0 issues

---

## 📊 KPIs להצלחה | Success Metrics

לאחר ההשקה - מדידה דרך AI CEO Agent:
- **Conversion rate** מקטגוריית עיסוי להזמנה (יעד: +40%)
- **AOV (Average Order Value)** מתוספות (יעד: +25%)
- **Time to booking** מכניסה לפרופיל ועד הזמנה (יעד: <60 שניות)
- **Repeat bookings** - לקוחות שחוזרים תוך 30 יום (יעד: >35%)
- **Provider satisfaction** - מעסים שמילאו את כל ההגדרות (יעד: >85%)

---

## 🤖 Built for AnySkill - Claude Code Implementation

המסמך הזה הוא הבסיס. עבור פרטים מלאים על כל מסך - ראה את שני הקבצים הנוספים. בהצלחה! 🚀
