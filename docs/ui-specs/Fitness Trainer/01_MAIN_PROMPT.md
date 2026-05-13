# 🏋️ AnySkill CSM #6 - Fitness Trainer
## פרומפט מאסטר ל-Claude Code (גרסה v2 - FINAL)

> **CSM #6** | אחרי Massage, Pest Control, Delivery, Cleaning, Handyman
> **תת-קטגוריה:** מאמני כושר אישיים
> **תאריך:** אפריל 2026
> **גרסה:** v2.0 PRODUCTION READY

---

## ⚠️ חוקי ברזל - חובה לקרוא לפני שמתחילים!

### 🚫 מה **לא** עושים:
1. **לא מוחקים שום UI קיים** - לא Hero, לא גלריה, לא וידאו, לא אודות, לא השירות
2. **לא משכפלים פיצ'רים קיימים:**
   - ❌ אין "פירוט דירוג" (כבר קיים מתחת לבלוק)
   - ❌ אין "זמינות שבועית" (יש יומן Google מסונכרן)
   - ❌ אין "גלריית עבודות" (כבר קיימת בפרופיל)
3. **לא כוללים אונליין** במיקומי שירות (רק: בית/פארק/חדר כושר)

### ✅ מה **כן** עושים:
1. **ADD ONLY** - מוסיפים בלוק אחד חדש בלבד
2. **בצד הלקוח:** הבלוק נכנס בין סקציית "אודות" לסקציית "השירות"
3. **בצד הספק:** הבלוק נפתח אוטומטית כשבוחרים תת-קטגוריה "מאמני כושר"
4. **כל אייטם בצד הספק חייב להיות עריך:** ✏️ ערוך, 🗑️ מחק, ➕ הוסף
5. **Hebrew RTL מלא** בכל מקום
6. **AI = Gemini 2.5 Flash Lite** (לא Claude!)

---

## 🎨 Design System

### צבעי ליבה:
```dart
class FitnessTheme {
  // Primary - Energy
  static const Color primaryOrange = Color(0xFFFF6B35);
  static const Color primaryGold = Color(0xFFF59E0B);
  
  // Secondary - Health
  static const Color successGreen = Color(0xFF10B981);
  static const Color successGreenDark = Color(0xFF059669);
  
  // AI Layer
  static const Color aiPurple = Color(0xFF8B5CF6);
  static const Color aiIndigo = Color(0xFF6366F1);
  
  // Neutrals
  static const Color textDark = Color(0xFF1F2937);
  static const Color textMedium = Color(0xFF6B7280);
  static const Color textLight = Color(0xFF9CA3AF);
  static const Color bgWhite = Color(0xFFFFFFFF);
  static const Color bgCream = Color(0xFFFFF8F3);
  static const Color bgGray = Color(0xFFFAFBFC);
  static const Color borderLight = Color(0xFFFED7AA);
  static const Color borderGray = Color(0xFFE5E7EB);
  
  // Specialty colors (per chip)
  static const Map<String, List<Color>> specialtyColors = {
    'strength': [Color(0xFFEF4444), Color(0xFFDC2626)],     // אדום
    'fat_loss': [Color(0xFFF59E0B), Color(0xFFD97706)],     // כתום
    'pregnancy': [Color(0xFF3B82F6), Color(0xFF2563EB)],    // כחול
    'seniors': [Color(0xFF6366F1), Color(0xFF4F46E5)],      // אינדיגו
    'rehab': [Color(0xFF10B981), Color(0xFF059669)],        // ירוק
    'flexibility': [Color(0xFFEC4899), Color(0xFFDB2777)],  // ורוד
    'endurance': [Color(0xFFFBBF24), Color(0xFFF59E0B)],    // צהוב
    'martial_arts': [Color(0xFF991B1B), Color(0xFF7F1D1D)], // אדום כהה
  };
}
```

---

## 🏗️ ארכיטקטורה - Files Structure

### צד הספק (Provider):
```
lib/screens/provider/edit/blocks/fitness/
├── trainer_settings_block.dart           # Main container (~800 lines)
├── widgets/
│   ├── ai_coach_score_card.dart          # מסך ציון פרופיל מאמן
│   ├── specialties_section.dart          # תחומי התמחות
│   ├── pricing_packages_section.dart     # חבילות ומחירים
│   ├── training_locations_section.dart   # מיקומי שירות
│   ├── certifications_section.dart       # תעודות
│   ├── success_stories_section.dart      # סיפורי הצלחה
│   ├── special_offers_section.dart       # מבצעים והטבות
│   ├── performance_dashboard.dart        # לוח ביצועים פנימי
│   ├── ai_suggestions_card.dart          # הצעות חכמות
│   └── editable_item_card.dart           # Generic editable card with edit/delete
├── modals/
│   ├── add_edit_package_modal.dart       # Modal לחבילה
│   ├── add_edit_certification_modal.dart # Modal לתעודה
│   ├── add_edit_story_modal.dart         # Modal לסיפור הצלחה
│   ├── add_edit_offer_modal.dart         # Modal למבצע
│   └── add_edit_location_modal.dart      # Modal למיקום
└── models/
    ├── pricing_package.dart
    ├── certification.dart
    ├── success_story.dart
    ├── special_offer.dart
    ├── training_location.dart
    └── trainer_specialty.dart
```

### צד הלקוח (Client):
```
lib/screens/client/booking/blocks/fitness/
├── trainer_booking_block.dart            # Main container (~600 lines)
├── widgets/
│   ├── ai_match_quiz_cta.dart           # כפתור פתיחת Quiz
│   ├── personality_match_result.dart     # תוצאת התאמה (94%)
│   ├── specialties_display.dart          # תצוגת תחומי התמחות
│   ├── packages_carousel.dart            # 3 חבילות אופקיות
│   ├── locations_grid.dart               # 3 מיקומי שירות
│   ├── certifications_list.dart          # רשימת תעודות
│   ├── success_story_card.dart           # סיפור הצלחה
│   ├── monthly_journey_preview.dart      # Apple-style 3 rings
│   ├── trust_badges_grid.dart            # 4 הבטחות
│   └── active_offer_banner.dart          # באנר מבצע פעיל
└── screens/
    └── personality_quiz_screen.dart      # Quiz מלא של 5 שאלות
```

### Backend (Cloud Functions):
```
functions/src/fitness/
├── recommendTrainersByGoals.js          # AI Match
├── optimizeTrainerProfile.js            # Profile Optimizer  
└── generateCustomWorkoutPlan.js         # תכנית אימון אישית
```

---

## 📋 צד הספק - מפרט מלא

### 🎯 Section 1: AI Coach Score Card (Hero)

**מה זה:** כרטיס סגול-אינדיגו עם הציון הכולל של הפרופיל

**Features:**
- ציון כולל 0-100 (מתעדכן אוטומטית)
- סמן יעד 90 על Progress bar
- הצעה ספציפית לשיפור הבא ("+15 נק'")
- תווית "AI Coach" בפינה
- טקסט "עודכן לפני X דקות"

**Logic:**
```dart
score = baseScore + 
  (specialties.length >= 3 ? 15 : 0) +
  (certifications.length >= 1 ? 10 : 0) +
  (successStories.length >= 1 ? 15 : 0) +
  (locations.length >= 2 ? 10 : 0) +
  (pricingPackages.length >= 2 ? 10 : 0) +
  (priceVsMarket >= 0.95 ? 10 : 0) +
  (activeOffers.length >= 1 ? 10 : 0) +
  (story.length >= 200 ? 10 : 0) +
  (portfolio.length >= 5 ? 10 : 0);
```

---

### 🎯 Section 2: Specialties (תחומי התמחות)

**Features:**
- ✅ Multi-select chips (מקס 5)
- ✅ צבע ייחודי לכל chip (לפי FitnessTheme.specialtyColors)
- ✅ **כפתור × על כל chip** להסרה מהירה
- ✅ **כפתור ➕ "הוסיפי" בכותרת** הסקציה
- ✅ AI insight ירוק: "ההתמחויות שלך תואמות X% מהחיפושים באזור"

**12 התמחויות זמינות:**
1. 💪 כוח ומסה (strength)
2. 🔥 הרזיה (fat_loss)
3. 🤰 הריון ולאחר לידה (pregnancy)
4. 👴 מבוגרים 50+ (seniors)
5. 🏥 שיקום (rehab)
6. 🧘 גמישות (flexibility)
7. 🏃 סיבולת (endurance)
8. 🥊 לחימה (martial_arts)
9. 🤸 קליסטניקס (calisthenics)
10. 🏊 פונקציונלי (functional)
11. 🏆 הכנה לתחרויות (competition_prep)
12. 🎯 הקצנת מסה (bulking)

---

### 💰 Section 3: Pricing Packages (חבילות ומחירים)

**Features:**
- ✅ "מחיר ממוצע באזור: ₪X-Y" (Smart Tip ירוק)
- ✅ רשימת חבילות עריכות
- ✅ **כפתור ➕ "חבילה חדשה" בכותרת** (גרדיאנט כתום בולט)
- ✅ **כל חבילה:** ✏️ ערוך + 🗑️ מחק
- ✅ הדגשת חבילה פופולרית (border כתום, badge "⭐ הפופולרי")
- ✅ הצגת חיסכון אם רלוונטי ("חיסכון 10%")

**Modal "ערוך/הוסף חבילה":**
```
┌─────────────────────────────────────┐
│ ✏️ עריכת חבילה                  [×]│
├─────────────────────────────────────┤
│ שם החבילה:                          │
│ [חבילת 5 אימונים           ]       │
│                                     │
│ סוג:                                │
│ ⭕ אימון יחיד  ⭕ חבילה  ⭕ מנוי   │
│                                     │
│ מספר אימונים:    משך אימון:        │
│ [5]              [60 דק' ▾]        │
│                                     │
│ מחיר כולל:       חיסכון:           │
│ [₪900]           [10%]             │
│                                     │
│ תוקף החבילה:                        │
│ [3 חודשים ▾]                       │
│                                     │
│ ☐ סמן כפופולרי ⭐                  │
│ ☐ הצע אונבורדינג חינם              │
│                                     │
│ [שמרי שינויים]    [ביטול]          │
└─────────────────────────────────────┘
```

---

### 📍 Section 4: Training Locations (איפה את מאמנת)

**Features:**
- ✅ 3 קלפיות במבנה 3-עמודות (לא 4!)
- ✅ **כפתור ➕ "מיקום" בכותרת**
- ✅ **כפתור ✏️ קטן בפינת כל קלפי**
- ✅ הצגת תוספת מחיר אם יש (לדוגמה: "+ ₪50" לבית)

**3 מיקומים אפשריים בלבד:**
1. 🏠 בבית הלקוח (יכול להוסיף תוספת מחיר)
2. 🌳 בפארק (חינם)
3. 🏋️ חדר כושר (חינם)

**❌ אין אונליין!**

**Modal "ערוך מיקום":**
```
┌─────────────────────────────────────┐
│ ✏️ ערוך מיקום שירות            [×]│
├─────────────────────────────────────┤
│ סוג מיקום:                          │
│ ⚪ בית הלקוח  ⚪ פארק  ⚪ ח. כושר  │
│                                     │
│ רדיוס שירות (ק"מ):                 │
│ [────●────────] 15 ק"מ             │
│                                     │
│ תוספת מחיר:                         │
│ [₪50] (אופציונלי)                  │
│                                     │
│ הערות:                              │
│ [מביאה ציוד...]                    │
│                                     │
│ [שמרי]    [ביטול]                  │
└─────────────────────────────────────┘
```

---

### 🎓 Section 5: Certifications (תעודות והסמכות)

**Features:**
- ✅ רשימת תעודות עם תגית "✓ מאומת" כחולה
- ✅ **כפתור ➕ "תעודה" בכותרת**
- ✅ **כל תעודה:** ✏️ ערוך + 🗑️ מחק
- ✅ הצגת שם המוסד + שנת הסמכה

**Modal "ערוך/הוסף תעודה":**
```
┌─────────────────────────────────────┐
│ ✏️ הוסיפי תעודה                 [×]│
├─────────────────────────────────────┤
│ שם התעודה:                          │
│ [NASM - Certified Personal Trainer] │
│                                     │
│ מוסד מסמיך:                         │
│ [NASM ▾] (Wingate / NASM / ACSM /  │
│         ISSA / אורט בראודה / אחר)  │
│                                     │
│ שנת הסמכה:                          │
│ [2015 ▾]                           │
│                                     │
│ העלי תמונת תעודה (אופציונלי):     │
│ [📷 העלי תמונה]                    │
│                                     │
│ ⚠️ התעודה תאומת ע"י הצוות תוך 48ש' │
│                                     │
│ [שמרי]    [ביטול]                  │
└─────────────────────────────────────┘
```

---

### 📸 Section 6: Success Stories (סיפורי הצלחה)

**Features:**
- ✅ רשימת סיפורי הצלחה עם תמונות לפני/אחרי
- ✅ **כפתור ➕ "סיפור חדש" בכותרת** (גרדיאנט כתום)
- ✅ **כל סיפור:** ✏️ ערוך + 🗑️ מחק
- ✅ הצגת ⭐ דירוג + תאריך

**Modal "סיפור הצלחה חדש":**
```
┌─────────────────────────────────────┐
│ ✏️ סיפור הצלחה חדש              [×]│
├─────────────────────────────────────┤
│ שם הלקוח:                           │
│ [רינה כהן]                         │
│                                     │
│ תוצאה:                              │
│ [-15 ק"ג ב-4 חודשים]               │
│                                     │
│ תמונות:                             │
│ ┌─────┐  ┌─────┐                   │
│ │ +   │  │ +   │                   │
│ │לפני │  │אחרי │                   │
│ └─────┘  └─────┘                   │
│                                     │
│ עדות (אופציונלי):                   │
│ [סיגלית שינתה לי את החיים...]      │
│                                     │
│ ⚠️ נדרש אישור הלקוח (חתימה דיגיטלית)│
│ ☐ אישור הלקוח לפרסום נתקבל         │
│                                     │
│ [שמרי]    [ביטול]                  │
└─────────────────────────────────────┘
```

---

### 🎁 Section 7: Special Offers (מבצעים והטבות)

**Features:**
- ✅ רשימת מבצעים פעילים עם תגית "פעיל" ירוקה
- ✅ **כפתור ➕ "מבצע חדש" בכותרת** (גרדיאנט כתום)
- ✅ **כל מבצע:** ✏️ ערוך + 🗑️ מחק
- ✅ הצגת תאריך תפוגה + מספר מקומות נשארים
- ✅ "Empty State" עם הצעה: "הוסיפי 'אימון ראשון בחינם' - מגדיל פניות פי 3"

**Modal "מבצע חדש":**
```
┌─────────────────────────────────────┐
│ ✏️ מבצע חדש                     [×]│
├─────────────────────────────────────┤
│ סוג מבצע:                           │
│ ⚪ הנחה באחוזים                    │
│ ⚪ אימון ראשון חינם                │
│ ⚪ X+1 חינם                        │
│ ⚪ הצעה מותאמת                     │
│                                     │
│ כותרת המבצע:                        │
│ [🔥 שיעור ראשון ב-50%]             │
│                                     │
│ פרטים:                              │
│ [תקף ללקוחות חדשים בלבד...]        │
│                                     │
│ מספר מקומות (הגבלת כמות):          │
│ [3] (אופציונלי)                    │
│                                     │
│ תאריך תפוגה:                        │
│ [30/04/2026 📅]                    │
│                                     │
│ ☑️ הפעל מיד                        │
│                                     │
│ [שמרי]    [ביטול]                  │
└─────────────────────────────────────┘
```

---

### 📊 Section 8: Performance Dashboard (לוח ביצועים)

**Features:**
- ✅ רקע כהה (gradient navy)
- ✅ תווית 🔒 "לעיניים שלך בלבד"
- ✅ 4 KPIs בגריד 2x2:
  - 👥 לקוחות פעילים: 23 (+12%)
  - 💰 הכנסה החודש: ₪12.4K (+18%)
  - ⭐ דירוג ממוצע: 4.92 / 5
  - 🔄 שיעור החזרה: 87% (+5%)
- ✅ Achievement banner: "את ב-Top 8% של מאמנים בארץ!"

**אין כפתורי עריכה - זה רק תצוגה.**

---

### 💡 Section 9: AI Suggestions (הצעות חכמות)

**Features:**
- ✅ רקע סגול (gradient purple)
- ✅ 3-5 הצעות עם פוטנציאל באחוזים
- ✅ כל הצעה: אייקון + כותרת + תיאור + השפעה צפויה
- ✅ **כפתור ראשי "✨ החילי הכל אוטומטית"** (גרדיאנט סגול)

**דוגמאות הצעות:**
- 📸 "הוסיפי תמונות לפני/אחרי" → +15%
- 💰 "המחיר שלך 18% מתחת לשוק" → +18%
- 🎁 "הפעילי 'אימון ראשון בחינם'" → +25%
- 🏆 "הוסיפי תעודה מ-NASM" → +25%
- 📝 "הסיפור שלך קצר מדי" → +10%

---

### 🎬 Footer: Action Bar

**2 כפתורים:**
- 👀 "תצוגה מקדימה" (אפור עם border)
- 💾 "שמרי שינויים" (גרדיאנט כתום עם shadow)

---

## 📱 צד הלקוח - מפרט מלא

### 🤖 Section 1: AI Match Quiz CTA

**Features:**
- ✅ רקע סגול (gradient purple)
- ✅ אייקון 🤖 + טקסט "בדוק התאמה אישית עם AI"
- ✅ כפתור גדול "✨ מצא את ההתאמה המושלמת ←"
- ✅ בלחיצה: פותח Modal עם Quiz של 5 שאלות

**Quiz Questions (5):**
1. **🎯 מה המטרה שלך?**
   - 💪 לבנות שריר
   - 🔥 להוריד במשקל
   - 🏃 לשפר סיבולת
   - 🧘 גמישות והרגעה
   - 🏆 הכנה לאירוע

2. **📊 רמת ניסיון?**
   - 🌱 מתחיל
   - 🌳 בינוני
   - 🏔️ מתקדם

3. **📅 כמה ימים בשבוע?**
   - 1-2 / 3-4 / 5+

4. **📍 איפה תעדיפי להתאמן?**
   - בית / פארק / חדר כושר

5. **🎭 איזה סגנון מאמן?**
   - 🔥 מוטיבטור
   - 🧘 רגוע
   - 📊 דאטה
   - 💝 חברותי

---

### 🎯 Section 2: Personality Match Result

**Features:**
- ✅ רקע כתום-זהב עדין
- ✅ עיגול ירוק עם ציון התאמה (לדוגמה: 94%)
- ✅ 4 קלפיות הסבר למה זו התאמה טובה

**מציג רק אם הלקוח השלים את ה-Quiz**

---

### 🎯 Section 3: Specialties Display

**Features:**
- ✅ Chips צבעוניים (לפי FitnessTheme.specialtyColors)
- ✅ קריאה בלבד (לא עריך מצד הלקוח)

---

### 💰 Section 4: Packages Carousel

**Features:**
- ✅ 3 חבילות בגריד אופקי
- ✅ החבילה הפופולרית: גרדיאנט כתום, מורם, badge "⭐ פופולרי"
- ✅ הצגת חיסכון אם רלוונטי

---

### 📍 Section 5: Locations Grid

**Features:**
- ✅ 3 קלפיות (בית/פארק/חדר כושר)
- ✅ אייקון + שם + סטטוס

---

### 🎓 Section 6: Certifications List

**Features:**
- ✅ רשימה עם תגית "✓ מאומת" כחולה
- ✅ שם תעודה + מוסד + שנה

---

### 🎮 Section 7: Monthly Journey Preview

**Features:**
- ✅ רקע כהה (navy gradient)
- ✅ Apple-style 3 rings (CustomPaint)
- ✅ 4 stats: streak, workouts, strength gain, badges
- ✅ "תהיי ב-Top 15% בארץ!" banner

**🔥 הסקציה הכי מטורפת!** יוצרת aspiration אצל הלקוח.

---

### 📸 Section 8: Success Story Card

**Features:**
- ✅ עדות לקוח עם תמונות לפני/אחרי
- ✅ ⭐ דירוג + תאריך

---

### 🛡️ Section 9: Trust Badges Grid

**Features:**
- ✅ 4 הבטחות בגריד 2x2:
  - 🛡️ הבטחת מרוצה
  - 💯 החזר 100%
  - 🔐 תשלום מאובטח
  - ⭐ מאמן מאומת

---

### ⏰ Section 10: Active Offer Banner

**Features:**
- ✅ באנר כתום עדין עם dashed border
- ✅ הצגת המבצע + מספר מקומות נשארים

---

## 🤖 Cloud Functions (Gemini 2.5 Flash Lite)

### 1. `recommendTrainersByGoals`
**Trigger:** Client completes quiz  
**Input:** Quiz answers (5 questions)  
**Output:** Top 5 matched trainers with match scores 0-100 + reasons

### 2. `optimizeTrainerProfile`
**Trigger:** Trainer opens AI Coach Score card  
**Input:** Trainer profile data  
**Output:** Score 0-100 + top 5 improvement suggestions

### 3. `generateCustomWorkoutPlan`
**Trigger:** After first session booking  
**Input:** Goals + experience + frequency  
**Output:** 4-week personalized workout plan in Hebrew

---

## 🎯 הוראות יישום ל-Claude Code

### שלב 1: הכנה
```bash
# צור את כל התיקיות
mkdir -p lib/screens/provider/edit/blocks/fitness/{widgets,modals,models}
mkdir -p lib/screens/client/booking/blocks/fitness/{widgets,screens}
mkdir -p functions/src/fitness
```

### שלב 2: צד הספק (לפי הסדר!)
1. צור את ה-models (5 קבצים)
2. צור את `editable_item_card.dart` (Generic component)
3. צור את `trainer_settings_block.dart` (Master container)
4. צור את ה-widgets (10 קבצים)
5. צור את ה-modals (5 קבצים)
6. **טסט:** `flutter analyze` → צריך להיות 0 issues

### שלב 3: צד הלקוח
1. צור את `trainer_booking_block.dart` (Master container)
2. צור את ה-widgets (10 קבצים)
3. צור את `personality_quiz_screen.dart`
4. **טסט:** `flutter analyze` → צריך להיות 0 issues

### שלב 4: Backend
1. צור את 3 ה-Cloud Functions
2. הוסף `recommendTrainersByGoals` ל-functions/index.js
3. **טסט:** `firebase functions:config:get`

### שלב 5: אינטגרציה
1. ב-`provider_edit_screen.dart`: הוסף קריאה ל-`TrainerSettingsBlock` כשsubcategory = "מאמני כושר"
2. ב-`client_booking_screen.dart`: הוסף קריאה ל-`TrainerBookingBlock` בין "אודות" ל-"השירות"
3. **טסט:** App run + manual flow

### שלב 6: תיעוד
1. עדכן `CLAUDE.md` Section §42:
   ```markdown
   ## §42 Personal Trainer / Fitness Coach CSM ✅ COMPLETED
   - 6 sections in client (no online, no rating breakdown duplication)
   - 9 sections in provider (no weekly availability - synced via Calendar)
   - All items editable (✏️ + 🗑️ + ➕)
   - 3 Cloud Functions (Gemini 2.5 Flash Lite)
   ```

---

## ✅ Definition of Done

- [ ] כל הקבצים נוצרו (~30 קבצים)
- [ ] `flutter analyze` מחזיר 0 issues
- [ ] `flutter build web --release` עובר בהצלחה
- [ ] 3 Cloud Functions פרוסים ועובדים
- [ ] CLAUDE.md §42 עודכן
- [ ] בלוק הספק נפתח אוטומטית עם בחירת תת-קטגוריה
- [ ] בלוק הלקוח מופיע בין "אודות" ל-"השירות"
- [ ] כל ✏️ פותח Modal לעריכה
- [ ] כל 🗑️ מבצע מחיקה (עם confirmation)
- [ ] כל ➕ מוסיף פריט חדש דרך Modal
- [ ] AI Coach Score עובד עם Gemini
- [ ] Personality Quiz עובד עם Gemini
- [ ] עיצוב RTL מלא בעברית

---

## 🎁 Bonus Features (אם נשאר זמן)

1. **Drag-to-reorder** של חבילות ותעודות
2. **Confetti animation** בעת השלמת Quiz
3. **Skeleton loaders** לכל הסקציות
4. **Pull-to-refresh** על הדאשבורד
5. **Share button** לפרופיל המאמן

---

**🎯 כל הפרטים נמצאים בקבצים הנפרדים:**
- `02_PROVIDER_CODE.md` - קוד מפורט לכל widget בצד הספק
- `03_CLIENT_CODE.md` - קוד מפורט לכל widget בצד הלקוח
- `04_BACKEND_CODE.md` - 3 Cloud Functions מלאים
- `05_INTEGRATION.md` - איך לחבר את הבלוקים למסכים הקיימים
