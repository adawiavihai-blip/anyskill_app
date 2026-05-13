# 📡 Chat Guard AI - תיעוד API

## Base URL
```
https://your-app.com/api
```

## Authentication
כל נקודות הקצה דורשות authentication. הוסף header:
```
Authorization: Bearer YOUR_TOKEN
```

---

## 🔑 נקודת הקצה הכי חשובה

### `POST /api/check`
הנקודה שהאפליקציה קוראת לה לבדיקת כל הודעה לפני שליחה.

**Request:**
```json
{
  "message": "בוא נסדר את זה במזומן",
  "userId": "USR-48291",
  "chatId": "CHAT-12345"
}
```

**Response:**
```json
{
  "success": true,
  "detected": true,
  "action": "blocked",
  "severity": "high",
  "score": 60,
  "rewrite": null,
  "reason": "זוהה ניסיון להעברת תשלום מחוץ לאפליקציה"
}
```

**Possible actions:**
- `allowed` - שלח רגיל
- `warned` - שלח אבל הצג טיפ
- `rewritten` - הצע חלופה (נמצאת ב-field `rewrite`)
- `blocked` - אל תשלח
- `suspended` - חסום את החשבון

---

## 📝 ניהול מילים

### `GET /api/words`
```json
{
  "success": true,
  "words": [
    {
      "id": "w_1",
      "text": "מזומן",
      "category": "payment",
      "severity": "high",
      "notes": "",
      "hits": 142,
      "createdAt": "2026-04-20T10:30:00Z"
    }
  ]
}
```

### `POST /api/words`
**Request:**
```json
{
  "text": "כסף",
  "category": "payment",
  "severity": "medium",
  "notes": "הוסף על ידי מנהל"
}
```

**Response:**
```json
{
  "success": true,
  "word": { "id": "w_abc", "text": "כסף", ... }
}
```

### `PUT /api/words/:id`
עריכת מילה קיימת. Body זהה ל-POST.

### `DELETE /api/words/:id`
מחיקת מילה.

---

## 🚨 תקריות

### `GET /api/incidents`
**Query params:**
- `severity` (optional) - סינון לפי חומרה: low/medium/high/critical
- `userId` (optional) - סינון לפי משתמש
- `limit` (default: 50)
- `offset` (default: 0)

**Response:**
```json
{
  "success": true,
  "incidents": [...],
  "total": 427
}
```

---

## 📊 סטטיסטיקות

### `GET /api/stats`
```json
{
  "success": true,
  "stats": {
    "totalWords": 15,
    "attemptsToday": 47,
    "blockedToday": 42,
    "suspiciousUsers": 8,
    "changeFromYesterday": 23
  }
}
```

---

## ⚙️ הגדרות

### `GET /api/settings`
```json
{
  "success": true,
  "settings": {
    "sensitivity": 65,
    "detectSpaces": true,
    "detectLeetspeak": true,
    "detectEmoji": true,
    "detectPhoneNumbers": true,
    "detectLinks": true
  }
}
```

### `PUT /api/settings`
Body זהה ל-Response של GET.

---

## 🔔 Real-time Updates

### WebSocket (Socket.io)
```javascript
socket.on('chatguard-update', (data) => {
  // data.type: 'words' | 'incidents' | 'settings'
  // data.timestamp: Date
  reloadDashboard();
});
```

### Firebase Realtime
```javascript
firebase.firestore()
  .collection('blocked_words')
  .onSnapshot(() => {
    reloadDashboard();
  });
```

---

## ⚠️ Error Handling

כל תשובה מכילה `success: boolean`. במקרה של שגיאה:

```json
{
  "success": false,
  "error": "מילה זו כבר קיימת"
}
```

**HTTP Status Codes:**
- `200` - הצלחה
- `400` - בקשה לא תקינה
- `401` - לא מאומת
- `403` - אין הרשאה
- `404` - לא נמצא
- `500` - שגיאת שרת
