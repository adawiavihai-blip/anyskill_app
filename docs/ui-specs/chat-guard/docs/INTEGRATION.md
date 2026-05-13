# 🔗 מדריך שילוב - Chat Guard AI

## שלבי ההטמעה

### 1️⃣ התקנת בסיס הנתונים (5 דקות)
- [ ] פתח את `database/schema.sql`
- [ ] הרץ אותו ב-SQL שלך
  - PostgreSQL: `psql your_db < schema.sql`
  - MySQL: `mysql your_db < schema.sql`
  - Supabase: העתק לעורך SQL ותריץ
  - Firebase: צור Collections לפי ההערות בסוף הקובץ

### 2️⃣ התקנת ה-Backend (10 דקות)
- [ ] העתק את `backend/detection-engine.js` לפרויקט שלך
- [ ] העתק את `backend/risk-scorer.js`
- [ ] העתק את `backend/api-routes.js`
- [ ] רשום את הראוטים ב-Express/Fastify/Next.js:

```javascript
// Express example
const { registerRoutes } = require('./backend/api-routes');
const app = express();
registerRoutes(app, database);
```

### 3️⃣ התקנת ה-Dashboard (5 דקות)
- [ ] העתק את `frontend/admin-dashboard.html` ו-`frontend/chat-guard.js`
- [ ] הנח אותם בתיקיית הפאנל הניהולי
- [ ] ערוך את `DataLayer` בראש `chat-guard.js` כדי לקרוא ל-API שלך:

```javascript
const DataLayer = {
  async getWords() {
    const res = await fetch('/api/words');
    const data = await res.json();
    return data.words;
  },
  async saveWords(words) {
    // לא בשימוש עם API - מחק
  },
  // ... עדכן את כל שאר הפונקציות בהתאם
};
```

### 4️⃣ שילוב בצ'אט הקיים (15 דקות)
זה החלק הכי חשוב. במקום שבו שולחים הודעה בצ'אט שלך:

**לפני:**
```javascript
async function sendChatMessage(message) {
  await db.collection('messages').insertOne({
    text: message,
    userId: currentUser.id,
    chatId: chatId,
    timestamp: new Date()
  });
  showMessageInChat(message);
}
```

**אחרי:**
```javascript
async function sendChatMessage(message) {
  // שלב 1: בדוק עם Chat Guard
  const check = await fetch('/api/check', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      message,
      userId: currentUser.id,
      chatId: chatId
    })
  }).then(r => r.json());

  // שלב 2: פעל לפי ההחלטה
  if (check.action === 'blocked' || check.action === 'suspended') {
    showBlockAlert(check.reason);
    return; // אל תשלח
  }

  if (check.action === 'rewritten') {
    const useRewrite = confirm(
      `הודעתך עלולה לסכן אותך.\n\nהצעתנו: "${check.rewrite}"\n\nלשלוח את הגרסה הבטוחה?`
    );
    if (useRewrite) message = check.rewrite;
  }

  // שלב 3: שלח את ההודעה
  await db.collection('messages').insertOne({
    text: message,
    userId: currentUser.id,
    chatId: chatId,
    timestamp: new Date(),
    chatGuardScore: check.score  // שמור לצורך אנליטיקה
  });
  showMessageInChat(message);

  // שלב 4: אם הייתה אזהרה - הצג טיפ
  if (check.action === 'warned') {
    showTipToUser(check.reason);
  }
}
```

### 5️⃣ סנכרון Real-time (10 דקות)
בחר שיטה לפי הטכנולוגיה שלך:

**Firebase Firestore (הקל ביותר):**
```javascript
// ב-chat-guard.js, החלף את DataLayer.getWords:
async getWords() {
  return new Promise((resolve) => {
    firebase.firestore()
      .collection('blocked_words')
      .onSnapshot(snapshot => {
        const words = snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
        resolve(words);
        // תן ל-state ב-UI להתעדכן אוטומטית:
        state.words = words;
        renderWords();
      });
  });
}
```

**Supabase:**
```javascript
supabase.channel('blocked_words_changes')
  .on('postgres_changes',
      { event: '*', schema: 'public', table: 'blocked_words' },
      () => loadAll())
  .subscribe();
```

**WebSocket:**
```javascript
const socket = io();
socket.on('chatguard-update', (evt) => {
  if (evt.type === 'words') loadAll();
});
```

### 6️⃣ בדיקה (5 דקות)
1. פתח את הדשבורד
2. הוסף מילה חדשה, לדוגמה "דולר"
3. לך לצ'אט ונסה לשלוח: "בוא תעביר לי דולר"
4. ההודעה צריכה להיחסם
5. חזור לדשבורד → טאב "תקריות" → הניסיון שלך מופיע שם

## 🎯 סיום

אם הכל עובד, תראה:
- ✅ הוספת מילה בדשבורד → חוסמת מיידית בצ'אט
- ✅ תקריות מופיעות בדשבורד תוך שניות
- ✅ KPIs מתעדכנים אוטומטית
- ✅ המשתמש מקבל חוויה חלקה עם הודעות ברורות

## 🆘 בעיות נפוצות

**"המילים לא נשמרות":**
- בדוק שה-DataLayer מצביע ל-API הנכון
- בדוק שה-DB מחובר ומריצה את הטבלאות

**"ההודעות לא נחסמות בצ'אט":**
- ודא שחיברת את `/api/check` לפני שליחת כל הודעה
- בדוק את ה-Console ל-errors

**"הדשבורד לא מתעדכן real-time":**
- חיבור ה-Real-time (WebSocket/Firebase/Supabase) לא מחובר
- בדוק שה-event listener רשום כמו שצריך
