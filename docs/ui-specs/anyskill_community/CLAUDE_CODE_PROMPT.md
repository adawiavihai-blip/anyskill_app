# 🎯 משימה: שדרוג מערכת ההתנדבות "קהילה" ב-AnySkill

## רקע
המערכת הקיימת באפליקציה נקראת "נתינה מהלב" (גרסה v11.0.0). היא קיימת ופועלת מקצה לקצה - אבל ה-UI/UX שלה לא ברמה של אפליקציות בינלאומיות. המשימה שלך היא **לשדרג את כל החוויה** ל-design system פרימיום (סגנון Linear/Stripe/Airbnb 2026).

---

## 🚨 שינויים קריטיים - חובה ליישם

### 1. שינוי שם הקטגוריה
**מ:** "נתינה מהלב" / "Community"
**ל:** "קהילה" (Community)

עדכן בכל מקום:
- `lib/screens/community_hub_screen.dart` - כותרת המסך
- `lib/screens/home_tab.dart` - הבאנר במסך הבית
- כל קבצי ה-localization (`he.dart`, `en.dart` וכו')
- כל ה-keys של תרגום שמכילים "נתינה" → "קהילה"

### 2. שינוי הטרמינולוגיה - מילה אחת לכל המערכת
החלף **בכל מקום** את המילים הבאות במילה אחידה: **"התנדבות" / "התנדבויות"**

| לפני | אחרי |
|---|---|
| בקשת עזרה | בקשת התנדבות |
| משימה / משימות | התנדבות / התנדבויות |
| עזרה / עזרות | התנדבות / התנדבויות |
| המשימות שלי | ההתנדבויות שלי |
| בקש עזרה | בקש התנדבות |
| תן עזרה | בקשות פתוחות |

### 3. ⭐ קריטי - לוגיקת הלב הזהב (שינוי מהותי!)

**המצב היום:** הלב הזהב הוא **קבוע לתמיד** - מוענק אחרי ההתנדבות הראשונה ולא נעלם.

**המצב החדש שצריך:** הלב הזהב הוא **תג זמני של 30 יום** - מוענק לאחר *כל* התנדבות שהושלמה ומחודש בכל התנדבות חדשה.

#### לוגיקה מדויקת:
```
- אחרי כל סיום התנדבות (סטטוס completed):
  → הצג לב זהב על תמונת הפרופיל למשך 30 יום מרגע הסיום
  → אם המשתמש מבצע התנדבות נוספת בתוך 30 הימים → הטיימר מתאפס ל-30 יום נוספים
  → אחרי 30 יום ללא התנדבות חדשה → הלב הזהב נעלם אוטומטית

- שדה ב-Firestore: goldHeartExpiresAt: Timestamp
  - מתעדכן בכל completed: now() + 30 days
  - הצגת הלב מבוססת על: goldHeartExpiresAt > now()
  - בלי cron - בדיקה בזמן אמת בכל קריאה
```

#### יישום טכני:
1. **שינוי בקובץ `lib/services/community_hub_service.dart`:**
   - שדה ישן `volunteerHeart: bool` → **השאר אבל אל תשתמש**
   - שדה חדש `goldHeartExpiresAt: Timestamp`
   - בפונקציה שמטפלת ב-completed → `goldHeartExpiresAt = Timestamp.fromDate(DateTime.now().add(Duration(days: 30)))`

2. **בכל מקום שמציג לב זהב:**
   ```dart
   bool get hasGoldHeart {
     if (goldHeartExpiresAt == null) return false;
     return goldHeartExpiresAt!.toDate().isAfter(DateTime.now());
   }
   ```

3. **השדה הקיים `hasActiveVolunteerBadge` (Active Volunteer) נמחק** - הלב הזהב **מחליף אותו** (שניהם היו 30 יום, אז כעת רק שדה אחד).

4. **השפעה על דירוג חיפוש (`search_ranking_service.dart`):**
   - +50 נקודות בדירוג כל עוד `goldHeartExpiresAt > now()`

#### עדכון Firestore Rules:
```
שדות מותרים לעדכון בסיום התנדבות:
- goldHeartExpiresAt (חדש - חובה)
- volunteerTaskCount
- communityBadges (Starter/Pillar/Angel - אלה נשארים קבועים!)
- communityXP

שדות שנמחקו:
- volunteerHeart (לא בשימוש יותר, אפשר להשאיר לתאימות לאחור)
- hasActiveVolunteerBadge (מוחלף ע"י goldHeartExpiresAt)
- lastVolunteerTaskAt (מוחלף ע"י goldHeartExpiresAt)
```

---

## 🎨 Design System - חובה ליישם בכל המסכים

### צבעים
```dart
// Primary
Color primaryBlack = Color(0xFF18181B);     // כפתורים ראשיים, טקסט ראשי
Color primaryWhite = Color(0xFFFFFFFF);     // רקע ראשי
Color background = Color(0xFFF5F5F4);       // רקע משני (מחוץ למסך)
Color surface = Color(0xFFFAFAF9);          // רקע שדות, כרטיסים משניים

// Text
Color textPrimary = Color(0xFF18181B);      // טקסט ראשי
Color textSecondary = Color(0xFF52525B);    // טקסט משני (תיאורים)
Color textTertiary = Color(0xFF71717A);     // מטא-מידע
Color textMuted = Color(0xFFA1A1AA);        // טקסט מעומעם

// Borders
Color borderPrimary = Color(0x14000000);    // 0.5px borders (rgba(0,0,0,0.08))
Color borderSubtle = Color(0x0F000000);     // dividers (rgba(0,0,0,0.06))

// Gold (לב זהב - קריטי!)
Color goldHeart = Color(0xFFA87F2A);        // הזהב הראשי
Color goldHeartLight = Color(0x14A87F2A);   // רקעים זהב חיוורים
Color goldHeartBorder = Color(0x40A87F2A);  // borders זהב

// Status colors
Color success = Color(0xFF16A34A);          // ירוק - הצלחה
Color warning = Color(0xFFF59E0B);          // כתום - אזהרה
Color warningText = Color(0xFFB45309);
Color danger = Color(0xFFB91C1C);           // אדום - דחיפות
Color dangerBg = Color(0xFFFEF2F2);
Color info = Color(0xFF0EA5E9);             // כחול - מידע
Color infoBg = Color(0xFFF0F9FF);

// Star rating
Color starGold = Color(0xFFFBBF24);
```

### Typography
```dart
// משתמש בפונט: SF Pro Display (iOS) / Inter (Android)
// משקלים: 400 (regular), 500 (medium), 600 (semibold)
// אסור: 700+ (כבד מדי), 300- (דק מדי)

// Letter-spacing קריטי לתחושה פרימיום:
// - כותרות גדולות (24px+): -0.4 to -0.8px
// - כותרות בינוניות (15-22px): -0.2 to -0.3px
// - טקסט רגיל (12-14px): -0.1px
// - טקסט קטן עם uppercase: +0.2 to +0.3px

// גדלים סטנדרטיים:
fontSize 32 - מספר ראשי (hero stat)
fontSize 22 - כותרת מסך
fontSize 16 - שם / כותרת תוכן
fontSize 15 - כותרת בכרטיס
fontSize 14 - כפתור / חשוב
fontSize 13 - תיאור / טקסט גוף
fontSize 12 - מטא / label
fontSize 11 - footer / muted
fontSize 10 - חתימה / timestamp
```

### Spacing
```dart
// כל המספרים בפיקסלים, מבוססים על מערכת 4px:
padding: 4, 8, 10, 12, 14, 16, 18, 20, 24, 28, 32

// padding סטנדרטיים:
- מסך מלא (horizontal): 20px
- בתוך כרטיס: 14-16px
- בתוך כפתור: 12-14px (vertical), 16-20px (horizontal)
- בין סקציות: 24-32px
```

### Border Radius
```dart
borderRadius:
- 8px - badges, chips קטנים
- 10-12px - שדות, alerts
- 14px - כרטיסים קטנים
- 18-22px - כרטיסים גדולים
- 24px - מסכים מלאים (top/bottom sheets)
- 100px - כפתורים, pills (pill-shaped)
- 50% - אווטארים, אייקונים עגולים
```

### Components

#### כפתור ראשי (Primary Button)
```dart
ElevatedButton(
  style: ElevatedButton.styleFrom(
    backgroundColor: Color(0xFF18181B),
    foregroundColor: Colors.white,
    padding: EdgeInsets.symmetric(vertical: 14),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(100),
    ),
    elevation: 0,
    textStyle: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
    ),
  ),
)
```

#### כפתור משני (Secondary Button)
```dart
OutlinedButton(
  style: OutlinedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Color(0xFF18181B),
    side: BorderSide(color: Color(0x1F000000), width: 0.5),
    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 18),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(100),
    ),
  ),
)
```

#### Pill / Chip
```dart
Container(
  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  decoration: BoxDecoration(
    color: isSelected ? Color(0xFF18181B) : Colors.transparent,
    border: Border.all(
      color: isSelected ? Colors.transparent : Color(0x1F000000),
      width: 0.5,
    ),
    borderRadius: BorderRadius.circular(100),
  ),
  child: Text(
    label,
    style: TextStyle(
      fontSize: 12,
      color: isSelected ? Colors.white : Color(0xFF52525B),
      fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
      letterSpacing: -0.1,
    ),
  ),
)
```

---

## 📱 רשימת המסכים לעיצוב מחדש

ראה את התיקייה `mockups/` עבור MOCKUP HTML של כל מסך. **חובה לעקוב אחרי המוקאפים בדיוק.**

### 1. `mockups/01_main_community_screen.html`
המסך הראשי של הקהילה. **הסרה מלאה של הגרדיאנטים האדום-ורוד-סגול הקיימים.** כעת המסך מינימליסטי על רקע לבן עם:
- Stats hero בראש המסך (147 התנדבויות החודש + +23%)
- Social proof bar ("דניאל ועוד 2 שכנים שלך התנדבו השבוע")
- "המומלצים החודש" - כרטיסי מתנדבים פעילים עם לב זהב
- 2 לשוניות: "בקשות פתוחות" / "ההתנדבויות שלי"
- פילטרים: הכל, קרוב אליי, קשישים, חיילים, משפחות
- Feed של בקשות במבנה list-style (כמו Linear/GitHub)

### 2. `mockups/02_request_detail.html`
כרטיס פרטי בקשה לפני תפיסה. שורות מידע אופקיות (קטגוריה, סוג, מיקום, משך). אזור תגמול בתחתית עם לב זהב.

### 3. `mockups/03_chat.html`
צ'אט מתנדב-פונה בסגנון iMessage. בועות שחור-לבן, checkmarks כחולים, שורת סטטוס למעלה.

### 4. `mockups/04_complete_volunteering.html`
מסך סיום התנדבות (מתנדב מעלה תמונת הוכחה). אזור drag-drop, אזהרת פרטיות בכחול.

### 5. `mockups/05_confirmation_screen.html`
מסך אישור סיום (פונה). דירוג כוכבים גדול, ביקורת חובה (10+ תווים), פתק תודה אופציונלי בקופסת זהב.

### 6. `mockups/06_completion_celebration.html`
חגיגת השלמת התנדבות (רקע שחור, לב זהב מרכזי, פתק תודה מודגש). **קריטי: זה המסך שמעניק את הלב הזהב ל-30 יום!**

### 7. `mockups/07_my_volunteering.html`
"ההתנדבויות שלי" - 2 stats (XP + דירוג ממוצע), פס דרגה, 2 לשוניות (פעילות + היסטוריה).

### 8. `mockups/08_request_form.html`
טופס פרסום בקשת התנדבות. 3 שלבים, פס התקדמות עליון.

### 9. `mockups/09_profile.html`
פרופיל מתנדב - לב זהב על האווטאר (אם תקף), 3 stats, פס דרגה, ביקורת אחרונה.

### 10. `mockups/10_home_banner.html`
הבאנר במסך הבית. **רקע שחור** במקום הגרדיאנט הוורוד-סגול הקיים. מציג facepile + CTA.

### 11. `mockups/11_onboarding_intro.html`
3 שקופיות onboarding למשתמש שפותח את "קהילה" בפעם הראשונה.

### 12. `mockups/12_yearly_recap.html`
סיכום שנתי בסגנון Spotify Wrapped - לשיתוף ברשתות חברתיות.

### 13. `mockups/13_map_view.html`
מפה אינטראקטיבית עם פינים. כרטיס פרטים תחתון.

### 14. `mockups/14_skills_search.html`
חיפוש חכם של מיומנויות. אדם מגדיר מיומנויות חופשיות → מקבל התראות מותאמות.

### 15. `mockups/15_first_gold_heart.html`
חגיגת קבלת הלב הזהב לאחר ההתנדבות הראשונה. **קריטי: יש להבהיר שזה זמני ל-30 יום.**

### 16. `mockups/16_smart_notification.html`
התראת push חכמה - "בקשה דחופה במרחק 4 דקות הליכה" עם countdown.

### 17. `mockups/17_streak.html`
רצף שבועי של התנדבויות - גישה אנושית בלי לחץ.

---

## 🛠️ הוראות יישום מפורטות

### שלב 1: סקירת המוקאפים (חובה!)
לפני שתתחיל לכתוב קוד:
1. פתח כל אחד מ-17 מוקאפי ה-HTML שבתיקייה `mockups/`
2. צלם screenshots של כל אחד
3. הבן את המבנה, הצבעים, המרווחים, ה-typography

### שלב 2: עדכון מערכת העיצוב
1. צור קובץ `lib/theme/community_theme.dart` עם כל הצבעים, fonts, ו-spacing מהמערכת לעיל
2. צור widgets משותפים:
   - `lib/widgets/community/primary_button.dart`
   - `lib/widgets/community/secondary_button.dart`
   - `lib/widgets/community/pill_chip.dart`
   - `lib/widgets/community/avatar_with_gold_heart.dart` ← **קריטי**
   - `lib/widgets/community/stat_block.dart`
   - `lib/widgets/community/section_header.dart`

### שלב 3: יישום הלוגיקה החדשה של הלב הזהב
1. עדכן `lib/services/community_hub_service.dart`:
   - הוסף `goldHeartExpiresAt` כ-Timestamp בכל user document
   - בפונקציה `_handleConfirmation` (או בכל מקום שמסמן completed) - עדכן את השדה
2. צור הלפר:
```dart
// lib/utils/gold_heart_helper.dart
class GoldHeartHelper {
  static bool hasActiveGoldHeart(Timestamp? expiresAt) {
    if (expiresAt == null) return false;
    return expiresAt.toDate().isAfter(DateTime.now());
  }

  static int? daysUntilExpiry(Timestamp? expiresAt) {
    if (!hasActiveGoldHeart(expiresAt)) return null;
    return expiresAt!.toDate().difference(DateTime.now()).inDays;
  }
}
```
3. עדכן את ה-widget של האווטאר עם הלב להשתמש ב-helper הזה

### שלב 4: עיצוב מחדש של המסכים
לפי הסדר:
1. ראשון - המסך הראשי (`community_hub_screen.dart`) + הבאנר במסך הבית
2. שני - הפרופיל (חובה שיציג לב זהב נכון!)
3. שלישי - מסך השלמת התנדבות (כי שם הלב מוענק)
4. רביעי - שאר המסכים

### שלב 5: עדכון תרגומים
החלף את כל ה-keys שמכילים "נתינה" / "עזרה" / "משימה" / "בקשה" → "התנדבות"

### שלב 6: בדיקות
1. ודא שהלב הזהב מופיע אחרי השלמת התנדבות
2. ודא שהלב נעלם אחרי 30 יום (יש להריץ עם תאריך מדומה)
3. ודא שהלב מתחדש כשמבצעים התנדבות נוספת
4. ודא שהבונוס בדירוג חיפוש עובד נכון (+50 כל עוד יש לב זהב פעיל)

---

## ⚠️ מה אסור!

1. ❌ **אסור** להשאיר את הגרדיאנטים אדום-ורוד-סגול
2. ❌ **אסור** להשאיר את האייקונים האימוג'י המוגזמים (👴🎖️👨‍👩‍👧🤝)
3. ❌ **אסור** להשאיר badges מצועצעים עם הרבה צבעים
4. ❌ **אסור** להוסיף אנימציות פועמות (pulse, scale infinite)
5. ❌ **אסור** להשתמש ב-elevation/shadows מוגזמים - רק `border: 0.5px`
6. ❌ **אסור** להשתמש בצבעי טקסט מתחת ל-#A1A1AA (לא קריא)
7. ❌ **אסור** טקסטים מתחת ל-11px (a11y)
8. ❌ **אסור** להשאיר את המילים "עזרה/משימה/בקשה" בממשק - רק "התנדבות"

---

## ✅ Definition of Done

המערכת תיחשב מוכנה כאשר:
- [ ] כל 17 המסכים עוצבו לפי המוקאפים
- [ ] שם הקטגוריה "קהילה" בכל מקום
- [ ] כל הטרמינולוגיה אחידה - "התנדבות / התנדבויות"
- [ ] לוגיקת הלב הזהב 30 יום עובדת מקצה לקצה
- [ ] Firestore rules מעודכנים
- [ ] תרגומים מעודכנים בכל השפות
- [ ] לא נשאר ולו גרדיאנט אדום-ורוד-סגול אחד במערכת
- [ ] בדיקה ידנית של flow מלא: יצירת בקשה → תפיסה → צ'אט → סיום → אישור → הענקת לב זהב → היעלמות אחרי 30 יום

---

## 📚 קבצים נלווים בתיקייה זו

- `mockups/` - 17 קבצי HTML של המסכים
- `docs/DESIGN_SYSTEM.md` - מערכת העיצוב המלאה
- `docs/USER_FLOW.md` - זרימת המשתמש המלאה
- `docs/GOLD_HEART_LOGIC.md` - לוגיקת הלב הזהב המעמיקה
- `docs/EXISTING_SYSTEM_SUMMARY.md` - סיכום המערכת הקיימת (לפני השדרוג)

---

## 💬 הערות אחרונות

- אם משהו לא ברור במוקאפים - העדף את הגישה המינימליסטית ולא את המעוצבת
- אם יש קונפליקט בין המוקאפ למה שכתוב כאן - **המוקאפ קובע** (חוץ מבעניין הלב הזהב 30 יום שזה ההיגיון העסקי)
- שמור על האנגלית הקיימת בקוד - שינויים רק בתצוגה (UI)
- אין צורך לשנות את שמות הקבצים הקיימים (community_hub_screen.dart נשאר)

בהצלחה! 🚀
