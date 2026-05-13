# 🎨 AnySkill Community - חבילת שדרוג מלאה

חבילת מוקאפים, מסמכי תכנון, ופרומט מפורט לClaude Code לשדרוג מערכת ההתנדבות באפליקציית AnySkill.

---

## 🚀 איך להתחיל (Quick Start)

### אם אתה בעל הפרויקט:
1. הורד את התיקייה הזאת למחשב שלך
2. פתח את הפרויקט ב-Cursor / VS Code עם Claude Code
3. הזז את התיקייה הזאת לשורש הפרויקט (ליד `lib/`)
4. אמור ל-Claude Code:
   > "קרא את הקובץ `CLAUDE_CODE_PROMPT.md` בתיקייה `anyskill_community` והתחל לעבוד לפיו. תראה גם את התיקייה `mockups` ו-`docs` לפני שאתה מתחיל."

### אם אתה Claude Code:
1. **התחל מ:** `CLAUDE_CODE_PROMPT.md` - זה המסמך הראשי
2. **לפני שאתה כותב קוד:** קרא את כל המסמכים בתיקייה `docs/`
3. **לפני כל מסך:** פתח את המוקאפ המתאים בתיקייה `mockups/`

---

## 📁 מבנה התיקייה

```
anyskill_community/
│
├── CLAUDE_CODE_PROMPT.md           ⭐ המסמך הראשי - התחל כאן!
├── README.md                        (אתה קורא את זה עכשיו)
│
├── mockups/                         17 מוקאפים HTML מעוצבים
│   ├── _shared.css                  סגנון משותף לכל המוקאפים
│   ├── 01_main_community_screen.html       מסך הקהילה הראשי
│   ├── 02_request_detail.html              כרטיס פרטי בקשה
│   ├── 03_chat.html                        צ'אט
│   ├── 04_complete_volunteering.html       סיום התנדבות
│   ├── 05_confirmation_screen.html         מסך אישור (פונה)
│   ├── 06_completion_celebration.html      ⭐ הענקת לב זהב 30 יום
│   ├── 07_my_volunteering.html             ההתנדבויות שלי
│   ├── 08_request_form.html                טופס בקשה חדשה
│   ├── 09_profile.html                     פרופיל מתנדב (עם לב זהב)
│   ├── 10_home_banner.html                 באנר במסך הבית
│   ├── 11_onboarding_intro.html            3 שקופיות onboarding
│   ├── 12_yearly_recap.html                סיכום שנתי
│   ├── 13_map_view.html                    מפה אינטראקטיבית
│   ├── 14_skills_search.html               חיפוש מיומנויות חופשי
│   ├── 15_first_gold_heart.html            ⭐ לב זהב ראשון
│   ├── 16_smart_notification.html          התראת push חכמה
│   └── 17_streak.html                      רצף שבועי
│
└── docs/                            מסמכי תכנון
    ├── DESIGN_SYSTEM.md             מערכת העיצוב המלאה
    ├── GOLD_HEART_LOGIC.md          ⭐ לוגיקת הלב הזהב המעמיקה
    ├── USER_FLOW.md                 זרימת המשתמש
    └── EXISTING_SYSTEM_SUMMARY.md   סיכום המערכת הקיימת
```

---

## 🎯 מה משדרגים?

### 1. שינוי שם הקטגוריה
**"נתינה מהלב"** → **"קהילה"**

### 2. אחידות טרמינולוגית
**"עזרה / משימה / בקשה"** → **"התנדבות / התנדבויות"**

### 3. ⭐ לב הזהב - שינוי קריטי בלוגיקה
- **לפני:** הלב מוענק אחרי ההתנדבות הראשונה ונשאר לתמיד
- **אחרי:** הלב מוענק אחרי **כל** התנדבות ופעיל למשך **30 יום בלבד**
- **כל התנדבות חדשה מאפסת את הספירה ל-30 יום נוספים**
- אם אין התנדבות חדשה תוך 30 יום - הלב נעלם אוטומטית

### 4. עיצוב מחדש מקצה לקצה
- מינימליזם בסגנון Linear/Stripe/Airbnb 2026
- פלטה: שחור (#18181B), לבן, זהב יחיד (#A87F2A)
- בלי גרדיאנטים, בלי אימוג'י, בלי shadows כבדים
- 17 מסכים מעוצבים מחדש

---

## 📺 איך לראות את המוקאפים?

פשוט פתח את כל קובץ HTML בדפדפן:

**Mac/Linux:**
```bash
open mockups/01_main_community_screen.html
```

**Windows:**
```bash
start mockups/01_main_community_screen.html
```

או פשוט גרור את הקובץ לחלון הדפדפן.

המוקאפים תוכננו לתצוגה במחשב כמסגרת טלפון (390px רוחב). אפשר לפתוח כמה במקביל.

---

## 🎬 הסדר המומלץ ל-Claude Code

```
שלב 1 (Setup - חובה):
✓ קרא את CLAUDE_CODE_PROMPT.md
✓ קרא את כל הקבצים ב-docs/
✓ פתח וחקור את המוקאפים ב-mockups/

שלב 2 (Foundation):
✓ צור lib/theme/community_theme.dart עם הצבעים והפונטים
✓ צור lib/utils/gold_heart_helper.dart
✓ צור lib/widgets/community/avatar_with_gold_heart.dart

שלב 3 (Core Logic):
✓ עדכן lib/services/community_hub_service.dart - שדה goldHeartExpiresAt
✓ עדכן functions/src/community.ts - Cloud Function להענקת לב זהב
✓ עדכן firestore.rules
✓ עדכן lib/services/search_ranking_service.dart - בונוס +50

שלב 4 (Critical UI - הסדר חשוב!):
✓ מסך 06 - Completion Celebration (כאן הלב מוענק)
✓ מסך 09 - Profile (כאן הלב מוצג)
✓ מסך 15 - First Gold Heart (פעם ראשונה)
✓ מסך 07 - My Volunteering (הפס של 30 הימים)

שלב 5 (Main UI):
✓ מסך 10 - Home Banner (באנר במסך הבית)
✓ מסך 01 - Community Main Screen
✓ מסך 02 - Request Detail
✓ מסך 03 - Chat
✓ מסך 04 - Complete Volunteering
✓ מסך 05 - Confirmation Screen

שלב 6 (Secondary UI):
✓ מסך 08 - Request Form
✓ מסך 11 - Onboarding (3 שקופיות)
✓ מסך 13 - Map View
✓ מסך 14 - Skills Search

שלב 7 (Special Moments):
✓ מסך 12 - Yearly Recap
✓ מסך 16 - Smart Notification
✓ מסך 17 - Streak

שלב 8 (Localization):
✓ עדכן את כל קבצי ה-l10n
✓ החלף "נתינה" → "קהילה"
✓ החלף "עזרה / משימה" → "התנדבות"

שלב 9 (Testing):
✓ בדוק flow מקצה לקצה: בקשה → תפיסה → סיום → אישור → לב זהב
✓ בדוק שהלב נעלם אחרי 30 יום (זמן מדומה)
✓ בדוק שהלב מתחדש בהתנדבות חדשה
✓ בדוק שהבונוס בחיפוש +50 פעיל
```

---

## ❓ שאלות נפוצות

**ש: למה הלב הזהב הופך זמני?**
ת: כי לב קבוע = משתמש מתנדב פעם אחת ושוכח. לב זמני = תמריץ חזרה. 30 יום זה הזמן שעובר מספיק כדי לאלץ פעילות חוזרת אבל לא מספיק קצר ליצירת לחץ.

**ש: האם המערכת הקיימת תיהרס?**
ת: לא. הלוגיקה העסקית הליבתית (anti-fraud, XP, דרגות) נשארת זהה. רק ה-UI ולוגיקת הלב הזהב משתנים.

**ש: כמה זמן ייקח ליישם?**
ת: עם Claude Code - 6-10 שעות עבודה לכל הפרויקט. לבד - 3-5 ימי עבודה.

**ש: מה לגבי Production?**
ת: לפני deploy - חובה לבדוק migration: כל המשתמשים הקיימים שיש להם `volunteerHeart: true` צריכים לקבל `goldHeartExpiresAt` מתאים (או ערך null אם הם לא התנדבו ב-30 יום האחרונים).

**ש: למה גם המסכים החדשים שלא היו במערכת (מפה, חיפוש מיומנויות, סיכום שנתי)?**
ת: אלה שיפורים אסטרטגיים שיעצימו את הקהילה. אפשר לדחות אותם אם רוצים MVP מהיר.

---

## 📝 רישיון ושימוש

החבילה הזאת נוצרה במיוחד עבור AnySkill. כל המוקאפים, הקוד, והדוקומנטציה - לשימוש פנימי בפרויקט בלבד.

---

**גרסה:** 2.0
**תאריך:** אפריל 2026
**יעד:** AnySkill Community Module Upgrade

🚀 **בהצלחה!**
