# שדרוג מסך ניהול קטגוריות v3 — מדריך לאביחי

> **המסמך הזה הוא הסיכום בעברית עבורך.**
> את **המסמך באנגלית** (`01-MAIN-IMPLEMENTATION-PROMPT.md`) תיתן ל-Claude Code שיבצע אותו.

---

## מה זה כולל בקצרה

**עיצוב חדש לחלוטין** של הטאב "קטגוריות" בלשונית "מערכת" (ניהול → מערכת → קטגוריות).

**מה לא משתנה:**
- ✅ הלקוח לא רואה שום שינוי במסך הבית
- ✅ הקטגוריות עצמן בדיוק אותן קטגוריות
- ✅ ה-CSM (Cleaning, Massage, Delivery, Handyman) עובדים כרגיל
- ✅ זרימת הזמנה של הלקוח לא נוגעים בה

**מה משתנה לך כמנהל:**
- 🆕 KPI dashboard למעלה (5 מספרים חשובים)
- 🆕 חיפוש חכם + פילטרים + שמירת תצוגות
- 🆕 Sparkline (גרף קטן) של 30 ימים בכל קטגוריה
- 🆕 Conversion Funnel (צפיות → קליקים → הזמנות) בכל שורה
- 🆕 Health Score (0-100) לכל קטגוריה
- 🆕 Coverage map (כמה ערים יש ספקים)
- 🆕 Activity Log + Undo
- 🆕 Command Palette (⌘K) — הפיצ'ר הכי חזק
- 🆕 Drag & Drop לסידור מחדש
- 🆕 Bulk Actions (פעולות על כמה קטגוריות בבת אחת)
- 🆕 קיצורי מקלדת
- 🆕 AnyTasks ונתינה מהלב כבאנרים מנוהלים
- 🆕 Pin / Hide / Featured

---

## מה הולך להיווצר ב-Firebase

**שדות חדשים** ב-collection `categories` (לא נוגע בקיים):
- `analytics` — מטריקות שמתעדכנות אוטומטית כל 15 דקות
- `admin_meta` — מי ערך מתי, האם מקודם, האם מוסתר
- `csm_module` — לאיזה CSM הקטגוריה משויכת
- `custom_tags` — תגיות שאתה יכול להוסיף ידנית

**Collections חדשים:**
- `admin_activity_log` — רישום של כל שינוי שאתה עושה
- `admin_saved_views` — תצוגות שמורות שלך (פילטרים)
- `promoted_banners` — AnyTasks ונתינה מהלב כיישות מנוהלת

**Cloud Functions חדשות (3):**
1. `updateCategoryAnalytics` — רץ כל 15 דקות, מעדכן מטריקות
2. `logAdminAction` — שומר רישום של כל פעולה שלך
3. `undoAdminAction` — מבטל פעולה אחרונה

---

## איך לעבוד עם זה — המסלול המומלץ

### שלב 1 — תן ל-Claude Code את ההנחיה
פתח את Claude Code ב-VS Code, וכתוב לו:

```
תקרא את הקובץ הזה ותתחיל ב-Phase A:

[הדבק כאן את כל התוכן של 01-MAIN-IMPLEMENTATION-PROMPT.md]
```

### שלב 2 — Claude Code יבצע ב-5 שלבים (Phases)

**Phase A — Foundation** (2-3 שעות)
- שדות חדשים ב-Firestore
- Cloud Function ראשונה
- מודלים ושירותים
- בלי שום שינוי ויזואלי עדיין

**Phase B — Core UI** (4-5 שעות)
- כל הכרטיסים והשורות הבסיסיות
- מאחורי feature flag (רק אתה רואה)

**Phase C — Advanced UI** (3-4 שעות)
- Sparklines, Funnel, Health, Coverage
- Bulk Actions + Drag & Drop
- קיצורי מקלדת

**Phase D — Power Features** (4-5 שעות)
- Activity Log + Undo
- Command Palette
- Edit Dialog (5 טאבים)
- Add Wizard (3 שלבים)

**Phase E — Polish & QA** (2-3 שעות)
- Loading skeletons
- Dark mode
- RTL בדיקות
- Mobile responsive

**סה"כ זמן עבודה משוער ל-Claude Code: 15-20 שעות (יבצע פעולות במקביל)**

### שלב 3 — אישור בכל שלב
ב-Phase Plan למעלה במסמך, יש הוראה ל-Claude Code לעצור אחרי כל Phase ולחכות לאישור שלך לפני שהוא ממשיך. ככה אתה תבדוק תוצאות ביניים ולא מסיים בסוף עם משהו לא נכון.

### שלב 4 — Feature Flag
**חשוב:** המסך החדש יעבוד מאחורי feature flag בשם `enable_categories_v3` ב-Firebase Remote Config. ככה:
- בהתחלה רק אתה רואה אותו (admin_uid שלך)
- המסך הישן עדיין עובד כברירת מחדל לכל השאר
- אחרי בדיקה — מעלים את ה-flag ל-true גלובלי
- בלי סיכון של "שבירה" של מערכת ייצור

---

## מה לעשות לפני שמתחילים

### בדיקות מקדימות (5 דקות)

1. **גיבוי Firestore:** הרץ `firebase firestore:export gs://anyskill-6fdf3.appspot.com/backups/$(date +%Y%m%d)`
2. **Branch חדש ב-Git:** `git checkout -b feature/categories-v3-pro`
3. **ודא שאתה ב-flutter stable:** `flutter doctor`
4. **בדוק שהפרויקט נפתח:** `flutter run -d chrome`

### דברים שאתה צריך לוודא ל-Claude Code

כשאתה נותן ל-Claude Code את ההנחיה, ציין במפורש:

> **חשוב:**
> - אני משתמש ב-Provider לניהול state (לא Riverpod)  ← *או Riverpod אם זה מה שאתה משתמש*
> - הפונט הראשי הוא [Heebo / Rubik / אחר]
> - יש לי Firebase project: anyskill-6fdf3
> - לפני שאתה כותב קוד, תקרא את CLAUDE.md בשורש הפרויקט
> - תעצור אחרי כל Phase ותחכה לאישור שלי
> - תריץ flutter analyze אחרי כל קובץ חדש

---

## מה צפוי בכל שלב — תוצרים

### אחרי Phase A
- ✅ Firestore עם שדות חדשים
- ✅ Cloud Function deployed
- ✅ Models + Services + Controller
- ❌ עדיין אין שינוי ויזואלי

### אחרי Phase B
- ✅ הטאב הוחלף (מאחורי feature flag)
- ✅ אתה רואה את הקטגוריות בעיצוב חדש
- ✅ KPI cards למעלה
- ✅ Search + Filter + Sort
- ⚠️ עדיין בלי sparklines / advanced features

### אחרי Phase C
- ✅ Sparklines בכל שורה
- ✅ Conversion funnel
- ✅ Health score
- ✅ Drag & Drop עובד
- ✅ Bulk actions
- ✅ קיצורי מקלדת

### אחרי Phase D
- ✅ Activity Log עם Undo
- ✅ Command Palette (⌘K) עובד
- ✅ Edit Dialog מלא (5 טאבים)
- ✅ Add Wizard (3 שלבים)

### אחרי Phase E
- ✅ הכל מלוטש
- ✅ Mobile responsive
- ✅ Dark mode
- ✅ Loading states
- ✅ Hebrew RTL מושלם
- ✅ flutter analyze: 0 issues

---

## אחרי שהכל עובד

### החלטה: מתי להעלות feature flag לכולם
המלצה: השאר על `false` שבוע, תעבוד עם זה בעצמך כל יום, כשאתה בטוח שאין באגים — תעלה ל-`true`.

### עדכון CLAUDE.md
ההנחיה כבר אומרת ל-Claude Code לתעד את הסעיף החדש (§32) ב-CLAUDE.md, כדי שעתידיים של Claude Code יבינו את הארכיטקטורה.

### ארכיוב הקוד הישן
אחרי 2 שבועות יציבים, העבר את הקוד הישן ל-`lib/admin/legacy/` ובסוף הסר אותו לגמרי.

---

## פתרון בעיות נפוצות

**"flutter analyze מציג issues":**
- בקש מ-Claude Code לתקן: "תקן את כל ה-issues שמופיעים ב-flutter analyze"

**"הסנכרון עם Firestore לא עובד בזמן אמת":**
- ודא שיש אינדקסים composite (ראה §5 במסמך הראשי)
- בדוק שה-rules מאפשרים read לאדמין

**"Activity Log לא נשמר":**
- ודא ש-Cloud Function `logAdminAction` deployed
- בדוק שאתה מחובר עם משתמש שיש לו role: 'admin'

**"המסך החדש לא מופיע":**
- בדוק את `enable_categories_v3` ב-Remote Config
- ודא ש-uid שלך ב-whitelist

---

## תוכן הקבצים בתיקייה הזאת

1. **`01-MAIN-IMPLEMENTATION-PROMPT.md`** — המסמך באנגלית עבור Claude Code (15 פרקים, ~800 שורות)
2. **`02-AVIHAI-GUIDE-HEBREW.md`** — המדריך הזה (לעיון שלך)
3. **`03-QUICK-START-COMMAND.md`** — פקודה מקוצרת אם אתה רוצה רק להתחיל מהר

---

**בהצלחה! 🚀**

זה הולך להיות שדרוג שיחסוך לך שעות עבודה ויעלה את AnySkill לרמה של מוצרים גלובליים.
