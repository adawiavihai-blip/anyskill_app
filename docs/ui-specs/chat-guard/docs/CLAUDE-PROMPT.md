# 📋 הנחיות ל-Claude - שילוב Chat Guard AI באפליקציה

## 🎯 המשימה
שלב את מערכת Chat Guard AI באפליקציית המרקטפלייס הקיימת של המשתמש, תוך שמירה על:
1. **סנכרון מלא** - כל הנתונים מגיעים מהDB ומתעדכנים בזמן אמת
2. **כפתורים פעילים** - כל פעולה בדשבורד משפיעה בפועל על המערכת
3. **שילוב חלק** - המערכת משתלבת בצ'אט הקיים ללא שינוי מהותי

## 📁 קבצים שקיבלת

```
chat-guard/
├── frontend/
│   ├── admin-dashboard.html    ← דשבורד האדמין (הבסיס)
│   └── chat-guard.js           ← הלוגיקה של הדשבורד
├── backend/
│   ├── detection-engine.js     ← מנוע הזיהוי (הלב)
│   ├── api-routes.js           ← נקודות API
│   └── risk-scorer.js          ← חישוב ציון סיכון
└── database/
    └── schema.sql              ← מבנה הטבלאות
```

## 🔧 משימות הביצוע

### משימה 1: התאם את ה-DataLayer למערכת הקיימת
בקובץ `frontend/chat-guard.js` יש אובייקט בשם `DataLayer` בתחילת הקובץ. **זהו נקודת החיבור היחידה לדאטה** - כל שאר הקוד משתמש בו.

**החלף את הפונקציות הבאות** מ-localStorage לקריאות DB אמיתיות:
- `getWords()` - שלוף את המילים מבסיס הנתונים
- `saveWords()` - שמור מילים לDB
- `getIncidents()` - שלוף תקריות
- `getSettings()` - שלוף הגדרות
- `saveSettings()` - שמור הגדרות
- `getStats()` - חשב KPIs

### משימה 2: שלב את מנוע הזיהוי בצ'אט
בכל מקום באפליקציה שבו נשלחת הודעה בצ'אט, הוסף לפני השליחה:

```javascript
// דוגמה ב-pseudocode
async function sendMessage(message, userId, chatId) {
  // 1. בדוק עם Chat Guard
  const check = await fetch('/api/check', {
    method: 'POST',
    body: JSON.stringify({ message, userId, chatId })
  }).then(r => r.json());

  // 2. פעל לפי ההחלטה
  switch (check.action) {
    case 'allowed':
      // שלח רגיל
      await actuallyeSendMessage(message);
      break;

    case 'warned':
      // שלח רגיל + הצג טיפ למשתמש
      await actuallyeSendMessage(message);
      showTipToUser(check.reason);
      break;

    case 'rewritten':
      // הצג למשתמש הצעה לחלופה
      const useRewrite = await askUser(
        'הודעתך עלולה להיות מסוכנת. רוצה לשלוח גרסה בטוחה?',
        check.rewrite
      );
      await actuallyeSendMessage(useRewrite ? check.rewrite : message);
      break;

    case 'blocked':
      // חסום ושלח אזהרה
      showBlockModal(check.reason);
      // אל תשלח את ההודעה
      break;

    case 'suspended':
      // חסום וסמן למנהל
      showAccountSuspendedModal();
      await notifyAdmin(userId);
      break;
  }
}
```

### משימה 3: התקן את בסיס הנתונים
הרץ את `database/schema.sql` (או צור את אותם Collections ב-Firebase).

### משימה 4: חבר את נקודות ה-API
התקן את הראוטים מ-`backend/api-routes.js`:
- `GET /api/words` - רשימת מילים
- `POST /api/words` - הוספה
- `PUT /api/words/:id` - עריכה
- `DELETE /api/words/:id` - מחיקה
- `POST /api/check` - בדיקת הודעה (הנקודה הכי חשובה!)
- `GET /api/incidents` - תקריות
- `GET /api/stats` - KPIs
- `GET /api/settings` - הגדרות
- `PUT /api/settings` - עדכון הגדרות

### משימה 5: הוסף סנכרון Real-time
כדי שהדשבורד יתעדכן מיידית כשמוסיפים מילה (גם ממכשיר אחר):

**אפשרות א' - WebSocket/Socket.io:**
```javascript
// Backend
io.on('connection', (socket) => {
  socket.join('admin-room');
});
// כשמילה מתווספת:
io.to('admin-room').emit('words-updated');
```

**אפשרות ב' - Firebase Realtime:**
```javascript
// Frontend
firebase.firestore().collection('blocked_words')
  .onSnapshot(() => loadAll());
```

**אפשרות ג' - Supabase Realtime:**
```javascript
// Frontend
supabase.channel('words')
  .on('postgres_changes', { event: '*', table: 'blocked_words' },
      () => loadAll())
  .subscribe();
```

## ✅ צ'קליסט לבדיקה

לאחר ההטמעה, ודא:

- [ ] הדשבורד נטען עם מילים מה-DB (לא מ-localStorage)
- [ ] הוספת מילה חדשה מופיעה מיד ברשימה
- [ ] מחיקת מילה מסירה אותה מיד
- [ ] עריכת מילה שומרת את השינויים
- [ ] שליחת הודעה שמכילה "מזומן" בצ'אט → נחסמת/מוחלפת
- [ ] ההודעה מופיעה בטאב "תקריות חיות" מיידית
- [ ] KPIs מתעדכנים כשקורה משהו
- [ ] שינוי הגדרות משפיע על הבדיקות הבאות
- [ ] פתיחת הדשבורד מ-2 טאבים שונים → שינוי בטאב אחד מופיע בשני

## 🎨 עיצוב
הדשבורד כבר מגיע מעוצב ב-RTL עם צבעים סגולים תואמים. אם האפליקציה שלך משתמשת בצבעים אחרים, ערוך את ה-CSS בתחילת `admin-dashboard.html`.

## 🔐 אבטחה
**חשוב מאוד:**
1. נקודת `POST /api/check` חייבת לקרות בצד השרת, לא בדפדפן
2. הגן על נקודות הניהול (`/api/words`, `/api/settings`) עם authentication
3. רק משתמשים עם role='admin' יכולים לגשת ל-dashboard

## 💡 טיפים
- התחל עם localStorage (ברירת המחדל) כדי לראות שהכל עובד
- רק אחרי שהכל רץ תקין - חבר ל-DB אמיתי
- ה-Detection Engine ב-`backend/detection-engine.js` מכיל הרבה יותר לוגיקה מהפרונט - השתמש בו בצד השרת

## 📞 צור קשר עם המשתמש אם:
- יש אי-בהירות לגבי הסטאק הטכני של האפליקציה
- צריך החלטה עיצובית
- יש צורך בפיצ'ר נוסף שלא קיים בקבצים

בהצלחה! 🚀
