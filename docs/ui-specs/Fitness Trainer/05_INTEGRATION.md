# 🔌 Integration Guide
## איך לחבר את הבלוקים למסכים הקיימים + פרומפט מאסטר ל-Claude Code

> **קובץ אחרון בסדרה** - אחרי `01_MAIN`, `02_PROVIDER`, `03_CLIENT`, `04_BACKEND`  
> **מטרה:** הוראות חיבור מדויקות + הפרומפט הסופי שתעתיק ל-Claude Code

---

## 🎯 חוק הזהב

> **מוסיפים את הבלוק - לא משנים שום דבר אחר ב-UI הקיים!**

הבלוקים החדשים נכנסים ל-2 מקומות בלבד:
1. **צד הספק:** `provider_edit_screen.dart` - מתחת ל-subcategory dropdown
2. **צד הלקוח:** `provider_profile_screen.dart` - בין סקציית "אודות" לסקציית "השירות"

---

## 🛠️ אינטגרציה צד הספק

### קובץ: `lib/screens/provider/edit/provider_edit_screen.dart`

#### השלב 1: הוסף import בראש הקובץ

```dart
import 'blocks/fitness/trainer_settings_block.dart';
```

#### השלב 2: מצא את ה-subcategory dropdown

חפש משהו כמו:
```dart
DropdownButtonFormField<String>(
  value: _selectedSubcategory,
  decoration: ...,
  items: subcategories.map(...).toList(),
  onChanged: (value) => setState(() => _selectedSubcategory = value),
)
```

#### השלב 3: הוסף את הבלוק **ישר אחרי** ה-dropdown

```dart
// ====== BEGIN: Existing subcategory dropdown ======
DropdownButtonFormField<String>(
  value: _selectedSubcategory,
  decoration: ...,
  items: subcategories.map(...).toList(),
  onChanged: (value) => setState(() => _selectedSubcategory = value),
),
// ====== END: Existing subcategory dropdown ======

// ====== ADDED: Fitness CSM Block (auto-shows for fitness trainers) ======
TrainerSettingsBlock(
  providerId: widget.providerId,
  subcategory: _selectedSubcategory ?? '',
  onSaved: () {
    // Optional callback when settings are saved
    setState(() {});
  },
),
// ====== END: Fitness CSM Block ======

// ====== EXISTING: All other fields below stay UNCHANGED ======
// (description, gallery, video, etc.)
```

#### 🚨 חשוב!

הבלוק יוצג **רק** כש-`_selectedSubcategory == 'מאמני כושר'` - הוא בודק את זה בעצמו ומחזיר `SizedBox.shrink()` אחרת.

---

## 📱 אינטגרציה צד הלקוח

### קובץ: `lib/screens/client/booking/provider_profile_screen.dart`

#### השלב 1: הוסף import

```dart
import 'blocks/fitness/trainer_booking_block.dart';
```

#### השלב 2: מצא את הסקציות הקיימות

המבנה הקיים נראה כמו:
```dart
Column(
  children: [
    _buildHeroSection(provider),       // תמונה + שם + סטטיסטיקות
    _buildGalleryAndVideo(provider),   // גלריית עבודות + וידאו היכרות
    _buildAboutSection(provider),      // 👈 סקציית "אודות"
    
    // 👇 כאן צריך להוסיף את הבלוק החדש!
    
    _buildServiceSection(provider),    // 👈 סקציית "השירות"
    _buildBookingFooter(provider),     // כפתור "בחר תאריך ושעה"
  ],
)
```

#### השלב 3: הוסף את הבלוק **בין** "אודות" ל-"השירות"

```dart
Column(
  children: [
    // ====== EXISTING: Hero, Gallery, Video, About - DO NOT TOUCH ======
    _buildHeroSection(provider),
    _buildGalleryAndVideo(provider),
    _buildAboutSection(provider),
    // ====== END: Existing sections ======
    
    // ====== ADDED: Fitness CSM Block ======
    // Shows automatically only if subcategory is "מאמני כושר"
    TrainerBookingBlock(
      trainerId: provider.id,
      trainerData: provider.toMap(),
    ),
    // ====== END: Fitness CSM Block ======
    
    // ====== EXISTING: Service section + booking footer - DO NOT TOUCH ======
    _buildServiceSection(provider),
    _buildBookingFooter(provider),
    // ====== END: Existing sections ======
  ],
)
```

#### 🚨 חשוב!

הבלוק יוצג **רק** כש-`trainerData['subcategory'] == 'מאמני כושר'` - הוא בודק בעצמו.

---

## 🔧 בדיקות אינטגרציה

### בדיקה 1: צד הספק
```
1. היכנס לעריכת פרופיל של מאמן כושר
2. ודא שהבלוק החדש מופיע מתחת ל-subcategory
3. שנה את ה-subcategory ל-"מטפלים אלטרנטיביים" → הבלוק נעלם
4. החזר ל-"מאמני כושר" → הבלוק חוזר
5. נסה: ✏️ ערוך / 🗑️ מחק / ➕ הוסף - הכל עובד
6. לחץ "💾 שמרי שינויים" → הנתונים נשמרים ב-Firestore
```

### בדיקה 2: צד הלקוח
```
1. היכנס לפרופיל של מאמן כושר (כמו סיגלית מלסה)
2. ודא שהבלוק מופיע בין "אודות" ל-"השירות"
3. ודא שהגלריה, האודות, ופירוט הדירוג נשארים בדיוק כמו שהיו
4. לחץ "✨ מצא את ההתאמה המושלמת" → Quiz נפתח
5. השלם את ה-Quiz → תוצאת התאמה מתקבלת מ-Gemini
6. גלול למטה → ראה את כל 10 הסקציות
```

### בדיקה 3: לקוח שאינו מאמן כושר
```
1. היכנס לפרופיל של נותן שירות אחר (לא מאמן כושר)
2. ודא שהבלוק החדש לא מופיע
3. ודא שהמבנה המקורי של הפרופיל נשמר
```

---

## 📝 עדכון `CLAUDE.md`

הוסף את הסעיף הבא ל-`CLAUDE.md` שלך:

```markdown
## §42 Personal Trainer / Fitness Coach CSM ✅ COMPLETED (April 2026)

### Architecture
- **Provider Side:** TrainerSettingsBlock (9 sections, all editable)
- **Client Side:** TrainerBookingBlock (10 sections, no duplications)
- **Color Palette:** Orange (#FF6B35) + Gold (#F59E0B) + Green (#10B981) + Purple AI (#8B5CF6)
- **AI Engine:** Gemini 2.5 Flash Lite (per hybrid AI architecture §12c, §31)

### What's INCLUDED
**Provider (9 sections):**
1. AI Coach Score Card (0-100 + improvement suggestions)
2. Specialties (12 options, max 5 selected, with × removal)
3. Pricing Packages (editable list with ✏️/🗑️ + Smart Tip)
4. Training Locations (3 only: home/park/gym - NO online)
5. Certifications (editable list with verified badge)
6. Success Stories (before/after photos with editable list)
7. Special Offers (editable list with active badge)
8. Performance Dashboard (4 KPIs - read-only, private)
9. AI Suggestions (5 improvement tips with apply-all button)

**Client (10 sections):**
1. AI Match Quiz CTA (purple gradient button)
2. Personality Match Result (94% with 4 reasons)
3. Specialties Display (colorful chips)
4. Packages Carousel (3 horizontal, popular elevated)
5. Locations Grid (3 cards: home/park/gym)
6. Certifications List (with verified badges)
7. Monthly Journey Preview (Apple-style 3 rings + 4 stats)
8. Success Story Card (before/after slider)
9. Trust Badges Grid (4 guarantees in 2x2)
10. Active Offer Banner (urgency element)

### What's EXPLICITLY EXCLUDED
- ❌ NO online training option (only home/park/gym)
- ❌ NO rating breakdown duplication (already exists below the block)
- ❌ NO weekly availability widget (Google Calendar already synced)
- ❌ NO portfolio gallery duplication (already exists in profile)

### Files Created
**Provider:**
- `lib/screens/provider/edit/blocks/fitness/trainer_settings_block.dart`
- `lib/screens/provider/edit/blocks/fitness/widgets/` (10 widgets)
- `lib/screens/provider/edit/blocks/fitness/modals/` (5 modals)
- `lib/screens/provider/edit/blocks/fitness/models/` (6 models)

**Client:**
- `lib/screens/client/booking/blocks/fitness/trainer_booking_block.dart`
- `lib/screens/client/booking/blocks/fitness/widgets/` (10 widgets)
- `lib/screens/client/booking/blocks/fitness/screens/personality_quiz_screen.dart`

**Backend (Cloud Functions - Gemini 2.5 Flash Lite):**
- `functions/src/fitness/recommendTrainersByGoals.js`
- `functions/src/fitness/optimizeTrainerProfile.js`
- `functions/src/fitness/generateCustomWorkoutPlan.js`

### Integration Points
- Provider: `provider_edit_screen.dart` - block added below subcategory dropdown
- Client: `provider_profile_screen.dart` - block added between "About" and "Service" sections
- Both blocks self-hide when subcategory != "מאמני כושר"

### Verification
- ✅ flutter analyze: 0 issues
- ✅ Hebrew RTL throughout
- ✅ All items editable (✏️ + 🗑️ + ➕)
- ✅ Mobile + Tablet + Desktop responsive
- ✅ HapticFeedback on all interactions
- ✅ Confirmation dialogs before delete
- ✅ Smooth animations (300ms standard)
```

---

## ✅ Final Test Checklist

### Code Quality
- [ ] `flutter analyze` returns 0 issues
- [ ] `flutter test` passes (if tests exist)
- [ ] No new warnings in console
- [ ] No `print()` statements left in production code

### UX Behavior
- [ ] Block auto-shows only for fitness trainers
- [ ] Block auto-hides for other categories
- [ ] All ✏️ buttons open Modals
- [ ] All 🗑️ buttons show confirmation
- [ ] All ➕ buttons add new items
- [ ] All animations smooth
- [ ] HapticFeedback on every tap

### Backend
- [ ] All 3 Cloud Functions deployed
- [ ] GEMINI_API_KEY set as Firebase secret
- [ ] Firestore rules updated and deployed
- [ ] Functions return correct data within 5s
- [ ] Fallback responses work if Gemini fails

### Visual
- [ ] Hebrew RTL works in all sections
- [ ] Apple-style 3 rings animate on load
- [ ] Match quiz score displays correctly
- [ ] All gradient colors render properly
- [ ] Mobile layout looks good (test 360px width)
- [ ] Desktop layout looks good (test 1024px+)

---

# 🚀 הפרומפט הסופי ל-Claude Code

> **העתק את כל הבלוק הזה ושלח ל-Claude Code:**

```
Claude, אני רוצה שתבנה את ה-CSM של מאמני כושר ל-AnySkill (CSM #6).

זה ה-CSM השישי במערכת (אחרי Massage, Pest Control, Delivery, Cleaning, Handyman).

============================
📁 קבצי תיעוד מלאים
============================

יש 5 קבצי MD בתיקייה /docs/csm_fitness_v2/:
1. 01_MAIN_PROMPT.md - הספציפיקציה המלאה
2. 02_PROVIDER_CODE.md - קוד מפורט לצד הספק
3. 03_CLIENT_CODE.md - קוד מפורט לצד הלקוח
4. 04_BACKEND_CODE.md - 3 Cloud Functions
5. 05_INTEGRATION.md - איך לחבר את הבלוקים

קרא את כולם לפני שמתחילים.

============================
🚨 חוקי ברזל (חובה!)
============================

1. ADD ONLY - לא לשנות שום UI קיים
2. בלוק הספק נפתח אוטומטית כשבוחרים "מאמני כושר"
3. בלוק הלקוח נכנס בין "אודות" ל-"השירות"
4. כל אייטם בצד הספק חייב כפתורי ✏️ ערוך + 🗑️ מחק + ➕ הוסף
5. אין אונליין - רק 3 מיקומים: בית/פארק/חדר כושר
6. אין פירוט דירוג (קיים כבר מתחת לבלוק)
7. אין זמינות שבועית (Google Calendar כבר מסונכרן)
8. אין גלריית עבודות (קיימת כבר)
9. Hebrew RTL מלא
10. AI = Gemini 2.5 Flash Lite (לא Claude!)

============================
📋 סדר ביצוע
============================

שלב 1: צור את כל התיקיות
שלב 2: צד הספק
   - 6 models
   - editable_item_card.dart (generic)
   - trainer_settings_block.dart (master container)
   - 9 widgets לסקציות
   - 5 modals לעריכה/הוספה
   - flutter analyze → 0 issues

שלב 3: צד הלקוח
   - trainer_booking_block.dart (master container)
   - 10 widgets לסקציות
   - personality_quiz_screen.dart
   - flutter analyze → 0 issues

שלב 4: Backend
   - 3 Cloud Functions (לפי 04_BACKEND_CODE.md)
   - הגדר GEMINI_API_KEY כ-secret
   - עדכן firestore.rules
   - פרוס: firebase deploy --only functions

שלב 5: אינטגרציה
   - הוסף קריאה ל-TrainerSettingsBlock ב-provider_edit_screen.dart
   - הוסף קריאה ל-TrainerBookingBlock ב-provider_profile_screen.dart
   - בדוק שהבלוקים מופיעים רק לתת-קטגוריה הנכונה

שלב 6: תיעוד
   - עדכן CLAUDE.md בסעיף §42 (לפי הטקסט ב-05_INTEGRATION.md)

============================
✅ Definition of Done
============================

- כל הקבצים נוצרו (~30 קבצים)
- flutter analyze מחזיר 0 issues
- 3 Cloud Functions פרוסים ועובדים
- CLAUDE.md §42 עודכן
- בלוק הספק נפתח אוטומטית עם בחירת תת-קטגוריה
- בלוק הלקוח מופיע בין "אודות" ל-"השירות"
- כל ✏️ פותח Modal לעריכה
- כל 🗑️ מבצע מחיקה (עם confirmation)
- כל ➕ מוסיף פריט חדש דרך Modal
- AI Coach Score עובד עם Gemini
- Personality Quiz עובד עם Gemini

============================
📊 דווח התקדמות
============================

אחרי כל 5 קבצים, דווח לי על ההתקדמות.
דווח גם על כל בעיה או החלטה לא ברורה.

תתחיל עכשיו ב-models של הספק. בהצלחה! 💪
```

---

## 🎁 בונוס: סקריפט הפעלה מהיר

יצרתי לך גם סקריפט שיעזור להגדיר את כל הסביבה בצעד אחד:

### `setup_fitness_csm.sh`
```bash
#!/bin/bash

echo "🏋️ מגדיר את AnySkill Fitness CSM..."

# 1. Create directories
mkdir -p lib/screens/provider/edit/blocks/fitness/{widgets,modals,models}
mkdir -p lib/screens/client/booking/blocks/fitness/{widgets,screens}
mkdir -p functions/src/fitness

echo "✅ תיקיות נוצרו"

# 2. Install Cloud Function dependencies
cd functions
npm install @google/generative-ai
cd ..

echo "✅ חבילות הותקנו"

# 3. Set GEMINI API Key (interactive)
echo "🔑 עכשיו תזין את ה-Gemini API Key (קבל מ-https://aistudio.google.com):"
firebase functions:secrets:set GEMINI_API_KEY

echo "✅ Secret הוגדר"

# 4. Final message
echo ""
echo "🎉 הסביבה מוכנה!"
echo "📋 הצעד הבא: שלח את הפרומפט מ-05_INTEGRATION.md ל-Claude Code"
```

תריץ אותו עם:
```bash
chmod +x setup_fitness_csm.sh
./setup_fitness_csm.sh
```

---

## 📞 אם משהו לא עובד

### בעיה: הבלוק לא מופיע בצד הספק
- וודא שה-subcategory הוא בדיוק `'מאמני כושר'` (לא `'מאמן כושר'` או `'fitness_trainer'`)
- בדוק את ה-import: `import 'blocks/fitness/trainer_settings_block.dart';`
- הרץ `flutter clean && flutter pub get`

### בעיה: ה-AI Match Quiz לא מחזיר תוצאה
- בדוק שה-Cloud Function פרוס: `firebase functions:list`
- בדוק שה-GEMINI_API_KEY מוגדר: `firebase functions:secrets:access GEMINI_API_KEY`
- בדוק את הלוגים: `firebase functions:log --only recommendTrainersByGoals`

### בעיה: הכפתורי עריכה לא פותחים Modal
- וודא שיצרת את כל ה-Modals (5 קבצים תחת `modals/`)
- בדוק שה-imports נכונים בכל widget

### בעיה: flutter analyze מציג שגיאות
- שלח לי את השגיאות הספציפיות ואני אעזור לתקן

---

## 🏆 מה אתה מקבל בסוף?

1. ✅ **CSM שישי מלא** למאמני כושר
2. ✅ **חוויית לקוח של אפליקציה ברמה עולמית** (Match AI, Apple Rings, Trust Badges)
3. ✅ **חוויית ספק עם עריכה מלאה** (כל פריט עריך + AI Coach)
4. ✅ **3 Cloud Functions** עם Gemini AI
5. ✅ **0 כפילויות** עם UI הקיים
6. ✅ **Hebrew RTL** מלא
7. ✅ **תיעוד CLAUDE.md** מעודכן

---

**🎯 מוכן ליישום! שלח את הפרומפט ל-Claude Code ותן לו 8-12 שעות לבנות הכל.**

*v2.0 PRODUCTION READY | אפריל 2026 | AnySkill Engineering*
