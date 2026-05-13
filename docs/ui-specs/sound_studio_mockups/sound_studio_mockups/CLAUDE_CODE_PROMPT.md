# 🎵 Prompt לקלוד קוד — שדרוג טאב הצלילים

## הקשר
אני שולח לך 4 קבצי HTML שמתפקדים כמוקאפ מלא לטאב "צלילים" המשודרג שלי. המוקאפים מציגים את הסטנדרט העיצובי, הזרימה, וההתנהגות שאני רוצה ליישם באפליקציה.

הקבצים נמצאים בתיקייה `sound_studio_mockups/`:
- `index.html` — מסך 1: סטודיו (מיפוי אירועים → צלילים)
- `library.html` — מסך 2: ספרייה (מאגר כל הצלילים)
- `analytics.html` — מסך 3: אנליטיקס (KPI, גרפים, דירוג, תובנות AI)
- `logs.html` — מסך 4: לוג מערכת (היסטוריה ובריאות מערכת)
- `assets/styles.css` — מערכת העיצוב המשותפת

---

## המטרה
שדרוג מלא של `lib/screens/admin_sounds_tab.dart` ו-`lib/services/audio_service.dart` כך שיתאימו למוקאפים, **תוך שמירה מלאה על הארכיטקטורה הקיימת ועל כל הפונקציונליות הנוכחית**.

---

## ⚠️ עקרונות חובה — אל תשבור

1. **אל תשבור את ה-AudioService הקיים.** ה-`AppSound` enum, ה-`AppEvent` enum, ה-`init()`, ה-`play()`, ה-`playEvent()`, ה-pre-buffering, וה-iOS audio unlock — כולם ממשיכים לעבוד **בדיוק כמו עכשיו**.
2. **אל תשבור את ה-Firestore paths הקיימים.** `app_settings/sounds` ו-`app_settings/event_sounds` חייבים להישאר זהים בפורמט. כל collection חדש שתיצור — צור בנפרד, אל תשנה את הקיימים.
3. **אל תשבור את ה-firestore.rules הקיימים.** ה-collection `app_settings` נשאר עם אותם הרשאות (קריאה לכולם, כתיבה רק לאדמין). הוסף rules חדשים ל-collections החדשים.
4. **אדמין בלבד.** הטאב נשאר תחת `isAdmin: true` — כל מסך ב-4 הטאבים החדשים בודק הרשאה.
5. **תמיכה מלאה ב-Web ו-iOS.** ה-iOS unlock וה-Web Audio Context חייבים להמשיך לעבוד. בדוק את זה אחרי השינויים.
6. **RTL מלא.** האפליקציה בעברית — כל הטקסט, הפריסה, והאייקונים מותאמים ל-RTL.

---

## מה צריך לבנות

### מבנה הטאב החדש
הטאב "צלילים" יהפוך לטאב עם 4 תתי-טאבים פנימיים (Tab Navigation עליונה):

```
ניהול > מערכת > צלילים
  ├── סטודיו         (existing functionality + new UI)
  ├── ספרייה         (NEW)
  ├── אנליטיקס       (NEW)
  └── לוג מערכת      (NEW)
```

יישם את זה עם `TabBar` + `TabBarView` של Flutter, **ולא** עם 4 מסכים נפרדים. ה-state של AudioService נטען פעם אחת.

---

## מסך 1: סטודיו (`index.html` הוא המראה)

### פונקציונליות
זה ה-UI המשודרג של המסך הקיים. כל הפונקציונליות הנוכחית נשמרת:
- 5 שורות אירועים (`AppEvent.values`)
- כל שורה: כפתור Play (preview), שם אירוע, תיאור, dropdown לבחירת צליל
- שינוי במיפוי כותב מיידית ל-Firestore (`app_settings/event_sounds`)
- Haptic feedback בלחיצה על Play (`HapticFeedback.lightImpact()`)
- אינדיקטור "המערכת פעילה" + מספר אירועים ממופים + "סנכרון אחרון לפני X שניות"

### הוספות חדשות
- כפתור "קבל הצעות AI" בתחתית — לעת עתה: SnackBar "AI מנתח את המיפוי הנוכחי..." (לא חייב לחבר ל-LLM אמיתי בשלב הזה)
- אנימציית fade-in כשטוענים את המסך
- כשמשנים מיפוי — toast ירוק "✓ עודכן: [שם אירוע] → [שם צליל]"

### Empty state ל-`onLogin`
אם המיפוי הוא `none`, השורה מציגה תווית "שקט מכוון" (לא empty state אדום). זו התנהגות תקינה.

---

## מסך 2: ספרייה (`library.html` הוא המראה)

### Firestore חדש
צור collection חדש `sound_metadata` שמחזיק לכל קובץ צליל:
```dart
{
  'id': 'wealthCrystal',
  'name': 'Wealth Crystal',
  'category': 'תשלומים',
  'categoryFilter': 'payments',  // payments | notifications | achievements | login
  'file': 'audio/wealth_crystal.mp3',
  'sizeBytes': 47000,
  'frequencyHz': '528',          // יכול להיות גם '440→880'
  'durationSeconds': 1.2,
  'bpm': 72,
  'cognitiveLoad': 'נמוך',       // נמוך | בינוני | גבוה
  'status': 'active',            // active | archived | suggested
  'tags': ['סיפוק', 'שגשוג'],
  'emotionScores': {'סיפוק': 92, 'שגשוג': 87, 'אמינות': 81},
  'psychDescription': 'תדר השגשוג',
  'createdAt': Timestamp,
  'updatedAt': Timestamp
}
```

הוסף document ראשוני לכל אחד מ-4 הצלילים הקיימים. הוסף עוד 3 צלילים בארכיון/הצעות (Crystal Bell, Coin Drop, Soft Chime) כדי שהמסך לא יהיה ריק.

### UI
- כפתור "העלה צליל חדש" בראש המסך — פותח file picker, מעלה ל-Firebase Storage תחת `sounds/uploaded/{filename}`, ואז יוצר document ב-`sound_metadata` עם המטא-דאטה הבסיסית
- Filter chips: הכל / פעילים / תשלומים / התראות / הישגים / בארכיון
- גריד 2 עמודות של כרטיסי צליל
- בחירת כרטיס פותחת בתחתית "תצוגת עומק" עם:
  - נגן waveform גדול (אפשר להשתמש ב-package `audio_waveforms` או SVG דמה אם זה מסבך יותר מדי)
  - 4 stat cards (תדר, BPM, משך, עומס קוגניטיבי)
  - גרף פרופיל תדר + bars של טביעת רגש

### שדה חדש שלא קיים: BPM ו-cognitive load
כשמעלים קובץ חדש, ערכי ברירת מחדל: BPM=80, cognitiveLoad='בינוני'. ניתן לערוך ידנית דרך כפתור עריכה בכרטיס.

---

## מסך 3: אנליטיקס (`analytics.html` הוא המראה)

### Firestore חדש
צור collection חדש `sound_events_log` שמתעד **כל השמעה**:
```dart
{
  'soundId': 'wealthCrystal',
  'eventId': 'onPaymentSuccess',
  'userId': 'user_xyz',
  'timestamp': Timestamp,
  'platform': 'iOS' | 'Android' | 'Web',
  'wasMuted': false,           // האם המשתמש כיבה צליל באפליקציה
  'followUpAction': true       // האם הייתה פעולה תוך 5 שניות אחרי הצליל (CTR)
}
```

עדכון `AudioService.playEvent()` — אחרי כל השמעה מצליחה, רשום אירוע ל-collection הזה (rate-limited: לא יותר מאירוע אחד לכל 100ms לאותו משתמש).

### UI
- 4 KPI cards עליונים: סך השמעות / CTR ממוצע / השתקות / צליל מוביל
- Time range selector: 24 שעות / 7 ימים / 30 ימים — משנה את כל הנתונים במסך
- Bar chart של 7 ימים עם stacked bars מפולחים לפי סוג צליל (`fl_chart` package מומלץ)
- Performance ranking — דירוג 4 הצלילים הפעילים לפי CTR
- AI Insight card — כרגע סטטי. אפשר להוסיף לוגיקה פשוטה: הצליל עם ה-CTR הנמוך ביותר מקבל המלצה לחלופה

### חישובים
- **סך השמעות** = `count(sound_events_log)` בטווח הזמן
- **CTR ממוצע** = `count(followUpAction=true) / count(*)` × 100
- **השתקות** = `count(wasMuted=true) / count(*)` × 100
- **דירוג** = group by `soundId`, sort by CTR desc

חשב את הנתונים ב-Cloud Function אם יש הרבה רשומות — אחרת query פשוט מהאפליקציה זה בסדר עם limit 1000.

---

## מסך 4: לוג מערכת (`logs.html` הוא המראה)

### Firestore חדש
צור collection חדש `sound_system_log`:
```dart
{
  'type': 'change' | 'upload' | 'warning' | 'system' | 'error',
  'title': 'מיפוי אירוע עודכן',
  'description': 'onPaymentSuccess שונה מ-Wealth Crystal ל-Crystal Bell',
  'actor': 'admin@app.com' | 'מערכת' | 'לקוח Web',
  'platform': 'iOS' | 'Android' | 'Web' | 'system',
  'timestamp': Timestamp,
  'metadata': { ... }   // אופציונלי: שדות נוספים לפי סוג
}
```

### מתי לרשום ל-log
1. **change** — בכל שינוי ב-`app_settings/sounds` או `app_settings/event_sounds`
2. **upload** — בכל העלאת קובץ חדש לספרייה
3. **warning** — חישוב יומי (Cloud Function או client side): אם השתקות לצליל מסוים > 4% → רישום אזהרה
4. **system** — סנכרון Firestore הצליח / iOS Audio Context שוחרר / כל אירוע מערכת
5. **error** — Pre-buffering נכשל / Firestore write נכשל / כל שגיאה ב-AudioService

### UI
- 4 health cards למעלה: AudioService / Pre-buffering / iOS Unlock / Firestore Sync
  - כל אחד מציג סטטוס דינמי בזמן אמת מה-AudioService instance הנוכחי
- Filter chips: הכל / שינויים / שגיאות / אזהרות / העלאות / מערכת
- Timeline של רשומות, מהחדש לישן
- כפתור "יצא לוג" — מייצא CSV של כל הרשומות בטווח הזמן הנוכחי
- כפתור "טען עוד 20" — pagination

### Health cards — איך הם מתעדכנים
ה-AudioService חושף getters חדשים:
```dart
class AudioService {
  bool get isInitialized => _isInitialized;
  Map<AppSound, bool> get bufferedSounds => _bufferedStatus;
  bool get iosAudioUnlocked => _iosUnlocked;
  Duration get firestoreSyncLatency => _lastSyncDuration;
}
```

המסך מאזין ל-stream של ה-AudioService ומעדכן את הקלפים.

---

## משימות מסודרות לפי שלבים

### שלב 1 — תשתית
- [ ] צור את 3 ה-collections החדשים ב-Firestore עם documents ראשוניים
- [ ] עדכן `firestore.rules` — read לכולם, write רק לאדמין על `sound_metadata` ו-`sound_system_log`. על `sound_events_log` — write לכל משתמש מאומת (כי כל user רושם השמעות שלו)
- [ ] הוסף getters חדשים ל-`AudioService`: `isInitialized`, `bufferedSounds`, `iosAudioUnlocked`, `firestoreSyncLatency`
- [ ] הוסף stream `audioServiceStateStream` שפולט שינויי סטטוס
- [ ] הוסף לוגיקת רישום ל-`sound_events_log` בתוך `playEvent()` (rate-limited)
- [ ] הוסף לוגיקת רישום ל-`sound_system_log` בכל שינוי settings

### שלב 2 — UI
- [ ] בנה `SoundStudioScreen` חדש שיחליף את `admin_sounds_tab.dart`
- [ ] בנה `TabBar` עם 4 tabs
- [ ] בנה `StudioTab` (מסך 1) — במלואו עם הפונקציונליות הקיימת
- [ ] בנה `LibraryTab` (מסך 2) — כולל upload, filter, deep dive
- [ ] בנה `AnalyticsTab` (מסך 3) — כולל KPI, chart, ranking
- [ ] בנה `SystemLogsTab` (מסך 4) — כולל health cards, filter, timeline, export

### שלב 3 — Polish
- [ ] אנימציות fade-in בכל המעברים
- [ ] Toasts לכל פעולה (שינוי, העלאה, שגיאה)
- [ ] כל הטקסטים בעברית, RTL מלא
- [ ] אייקונים עקביים (אפשר Heroicons / Material Icons / SVG ידני לפי המוקאפים)
- [ ] צבעים בדיוק כמו ב-styles.css המצורף

### שלב 4 — בדיקות (חובה!)
ראה סעיף "Self-Verification Checklist" למטה.

---

## ✅ Self-Verification Checklist — חייב להעביר את כל הבדיקות

לפני שאתה מודיע לי "סיימתי", הרץ את הבדיקות הבאות **ותדווח לי על התוצאה של כל אחת**:

### 1. בדיקות פונקציונליות בסיסיות
- [ ] הטאב הראשי "צלילים" נטען ב-`ניהול > מערכת > צלילים`
- [ ] 4 תתי-הטאבים מופיעים ועובדים (לחיצה משנה תוכן)
- [ ] הטאב "סטודיו" מציג 5 שורות אירועים עם הצלילים הנכונים
- [ ] לחיצה על כפתור Play בכל שורה משמיעה את הצליל
- [ ] שינוי dropdown משנה את המיפוי וכותב ל-Firestore (`app_settings/event_sounds`)
- [ ] הטאב "ספרייה" מציג את כל 7 הצלילים מ-`sound_metadata`
- [ ] Filter chips בספרייה עובדים (סינון אמיתי לפי סטטוס/קטגוריה)
- [ ] לחיצה על כרטיס בספרייה פותחת deep dive עם נתונים נכונים
- [ ] הטאב "אנליטיקס" מציג נתונים אמיתיים מ-`sound_events_log`
- [ ] Time range selector באנליטיקס משנה את כל הנתונים במסך
- [ ] הטאב "לוג מערכת" מציג רשומות מ-`sound_system_log`
- [ ] Health cards בלוג מציגים סטטוס דינמי (לא hard-coded)
- [ ] Filter chips בלוג עובדים

### 2. בדיקות שלמות הארכיטקטורה
- [ ] `AppSound` enum נשאר זהה — לא נוסף או הוסר ערך
- [ ] `AppEvent` enum נשאר זהה — לא נוסף או הוסר ערך
- [ ] `AudioService.init()` עדיין קורא pre-buffering לכל 4 הצלילים
- [ ] `AudioService.play(AppSound)` עדיין עובד מקוד אפליקציה רגיל
- [ ] `AudioService.playEvent(AppEvent)` עדיין מכבד את המיפוי מ-Firestore
- [ ] `AudioService.playEvent(AppEvent.onLogin)` עם מיפוי `none` — לא משמיע כלום אבל מפעיל haptic
- [ ] iOS audio unlock עדיין עובד (pointer-down ראשון משחרר)
- [ ] שינוי דרך הסטודיו משתקף מיידית באפליקציה (Firestore stream)

### 3. בדיקות אבטחה
- [ ] משתמש שאינו אדמין לא יכול להגיע לטאב הצלילים
- [ ] משתמש שאינו אדמין לא יכול לכתוב ל-`sound_metadata` (Firestore rules)
- [ ] משתמש שאינו אדמין לא יכול לכתוב ל-`app_settings/sounds`
- [ ] משתמש מאומת רגיל יכול לכתוב ל-`sound_events_log` (כי הוא מתעד את השמעות שלו)
- [ ] קריאה ל-`sound_metadata` מותרת לכולם (כי אנליטיקס יכולה להשתמש בה)

### 4. בדיקות UI/UX
- [ ] כל הטקסט בעברית, RTL מלא
- [ ] אין טקסט באנגלית שאמור להיות בעברית
- [ ] כל הצבעים תואמים ל-`assets/styles.css`
- [ ] אין overflow ב-mobile (תבדוק על מסך 375px)
- [ ] אין overflow בדסקטופ (תבדוק על מסך 1440px)
- [ ] אנימציית fade-in עובדת במעבר בין טאבים
- [ ] Toasts מופיעים בכל פעולה (לפחות 2 שניות, אז נעלמים)

### 5. בדיקות Edge Cases
- [ ] אם `sound_metadata` ריק — מציג empty state, לא crash
- [ ] אם `sound_events_log` ריק — מציג "אין נתונים מספיקים", לא crash
- [ ] אם Firestore לא זמין — מציג offline state, לא crash
- [ ] אם משתמש לחץ Play על צליל שעדיין לא הסתיים pre-buffering — מציג loading, לא משמיע אילם
- [ ] העלאת קובץ > 5MB — דחייה עם הודעת שגיאה
- [ ] העלאת קובץ שאינו mp3/wav — דחייה עם הודעת שגיאה

### 6. בדיקות אינטגרציה
- [ ] הצליל "Wealth Crystal" מתנגן ב-`chat_screen.dart` כאשר אסקרו משחרר תשלום
- [ ] הצליל "Solution Snap" מתנגן ב-`home_screen.dart` כאשר נמצאת התאמת AI
- [ ] הצליל "Opportunity Pulse" מתנגן ב-`opportunities_screen.dart` בהזדמנות חדשה
- [ ] הצליל "Growth Ascend" מתנגן ב-`course_player_screen.dart` בסיום קורס
- [ ] לאחר השמעה — נרשם entry ב-`sound_events_log`
- [ ] לאחר שינוי מיפוי — נרשם entry ב-`sound_system_log`

---

## פלט נדרש בסיום

כשסיימת:
1. סיכום קצר של מה שעשית (3-5 שורות)
2. רשימת קבצים שנוצרו/שונו
3. הדבק את ה-`firestore.rules` המעודכן
4. תוצאת כל בדיקה ב-Self-Verification Checklist (✅ או ❌ עם הסבר)
5. Screenshot של כל אחד מ-4 המסכים (אם אפשר)
6. רשימת items שעדיין דורשים תשומת לב (אם יש)

---

## הערה אחרונה
המוקאפים הם **המקור הויזואלי** שלי. אם משהו במוקאפ סותר את האפשרויות הטכניות של Flutter — תגיד לי לפני שאתה משנה ידנית. עדיף לדבר מאשר לסטות בשקט.

תודה! 🎵
