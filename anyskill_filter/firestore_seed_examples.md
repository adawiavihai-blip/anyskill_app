# דוגמאות Firestore Schema

קופי-פייסט ל-Firebase Console או JS seeder.

> **חשוב:** המבנה הוא `categories/{categoryId}` עם שדה `filterSchema` (Map).

---

## דוגמה 1 — מורי אנגלית (categoryId: `english_tutors`)

```json
{
  "name": "מורי אנגלית",
  "csm": null,
  "parentCategory": "שיעורים פרטיים",
  "filterSchema": {
    "version": 1,
    "searchPlaceholder": "חפש מורה לפי שם או התמחות",
    "sections": [
      {
        "id": "goal",
        "title": "המטרה שלך",
        "subtitle": "בחר אחד",
        "type": "cards",
        "providerField": "categoryTags",
        "singleSelect": true,
        "required": true,
        "options": [
          {"value": "bagrut", "label": "בגרות באנגלית", "meta": "34 מורים", "emoji": "🎓", "bgColor": "#FECACA"},
          {"value": "conv",   "label": "שיחה שוטפת",  "meta": "52 מורים", "emoji": "💬", "bgColor": "#BFDBFE"},
          {"value": "ielts",  "label": "IELTS / TOEFL","meta": "18 מומחים","emoji": "🌍", "bgColor": "#C7D2FE"},
          {"value": "kids",   "label": "לילדים",       "meta": "29 מורים", "emoji": "🧸", "bgColor": "#FDE68A"}
        ]
      },
      {
        "id": "price",
        "title": "תקציב לשעה",
        "subtitle": "חציון אזורי: ₪130",
        "type": "price",
        "providerField": "pricePerHour",
        "extra": {
          "min": 0,
          "max": 500,
          "defaultRange": [80, 200],
          "histogram": [14, 22, 35, 55, 78, 100, 92, 74, 58, 42, 30, 18, 12, 8, 5]
        }
      },
      {
        "id": "format",
        "title": "איפה?",
        "subtitle": "פורמט מועדף",
        "type": "cards",
        "providerField": "tutorProfile.format",
        "singleSelect": true,
        "options": [
          {"value": "online", "label": "אונליין",     "meta": "98 זמינים", "emoji": "💻"},
          {"value": "myhome", "label": "בבית שלי",   "meta": "42 בקרבתך", "emoji": "🏠"},
          {"value": "theirs", "label": "אצל המורה",  "meta": "31 בקרבתך", "emoji": "📍"}
        ]
      },
      {
        "id": "availability",
        "title": "מתי נוח?",
        "subtitle": "בחר ימים ושעות",
        "type": "daysTime",
        "providerField": "workingHours"
      },
      {
        "id": "traits",
        "title": "פרופיל המורה",
        "subtitle": "מה חשוב לך?",
        "type": "switches",
        "providerField": "categoryTags",
        "options": [
          {"value": "certified", "label": "מוסמך משרד החינוך",        "meta": "42 מורים · 5+ שנות ניסיון",     "emoji": "🎓", "bgColor": "#6366F1"},
          {"value": "native",    "label": "דובר אנגלית כשפת אם",      "meta": "26 מורים · בריטי/אמריקאי",       "emoji": "🇬🇧", "bgColor": "#3B82F6"},
          {"value": "trial",     "label": "שיעור ניסיון חינם",        "meta": "19 מורים · ללא התחייבות",        "emoji": "🎁", "bgColor": "#10B981"},
          {"value": "responsive","label": "מגיב בתוך 15 דקות",        "meta": "23 מורים · מהיר ויעיל",          "emoji": "⚡", "bgColor": "#F59E0B"}
        ]
      },
      {
        "id": "rating",
        "title": "דירוג",
        "subtitle": "איכות מובטחת",
        "type": "rating",
        "providerField": "rating"
      }
    ]
  }
}
```

---

## דוגמה 2 — הדברה (categoryId: `pest_control`)

```json
{
  "name": "הדברה",
  "csm": "pest_control",
  "parentCategory": "ניקיון",
  "filterSchema": {
    "version": 1,
    "searchPlaceholder": "חפש מדביר",
    "sections": [
      {
        "id": "urgency",
        "title": "דחיפות",
        "subtitle": "מתי אתה צריך?",
        "type": "cards",
        "providerField": "pestControlProfile.emergency24_7",
        "singleSelect": true,
        "required": true,
        "options": [
          {"value": "now",     "label": "חירום עכשיו",  "meta": "4 זמינים · הגעה 45 דק", "emoji": "🚨", "bgColor": "#FECACA"},
          {"value": "today",   "label": "היום",          "meta": "8 זמינים",              "emoji": "⏱",  "bgColor": "#FDE68A"},
          {"value": "planned", "label": "תיאום מראש",   "meta": "12 זמינים",             "emoji": "📅"}
        ]
      },
      {
        "id": "pests",
        "title": "סוג מזיק",
        "subtitle": "בחר מה הבעיה",
        "type": "chips",
        "providerField": "pestControlProfile.pestTypes",
        "options": [
          {"value": "roach",  "label": "ג׳וקים",       "meta": "+₪250", "emoji": "🪳"},
          {"value": "ants",   "label": "נמלים",        "meta": "+₪180", "emoji": "🐜"},
          {"value": "mice",   "label": "עכברים",       "meta": "+₪300", "emoji": "🐭"},
          {"value": "rats",   "label": "חולדות",       "meta": "+₪400", "emoji": "🐀"},
          {"value": "bedbug", "label": "פשפשי מיטה",   "meta": "+₪500"},
          {"value": "snake",  "label": "נחשים",        "meta": "רישיון נדרש", "emoji": "🐍"}
        ]
      },
      {
        "id": "method",
        "title": "שיטת טיפול",
        "subtitle": "חשוב במיוחד עם ילדים וחיות",
        "type": "cards",
        "providerField": "pestControlProfile.treatmentMethods",
        "options": [
          {"value": "green",  "label": "ירוק/אורגני",      "meta": "8 ספקים · בטוח לכולם",  "emoji": "🌿"},
          {"value": "spray",  "label": "ריסוס סטנדרטי",    "meta": "12 ספקים · פינוי 4 שעות","emoji": "💨"},
          {"value": "heat",   "label": "טיפול בחום",       "meta": "3 ספקים · ללא כימיקלים", "emoji": "🔥"},
          {"value": "inject", "label": "הזרקה ממוקדת",    "meta": "5 ספקים",                "emoji": "⚗"}
        ]
      },
      {
        "id": "license",
        "title": "רישיונות ואחריות",
        "subtitle": "חובה חוקית בישראל",
        "type": "switches",
        "providerField": "pestControlProfile.licenses",
        "options": [
          {"value": "env",        "label": "רישיון משרד הגנת הסביבה", "meta": "10 ספקים · 87% מהמדבירים",      "emoji": "🛡", "bgColor": "#10B981"},
          {"value": "snake_lic",  "label": "רישיון תפיסת נחשים",     "meta": "3 ספקים · נדרש לתפיסת בע״ח",     "emoji": "📜", "bgColor": "#F59E0B"},
          {"value": "warranty",   "label": "אחריות 6+ חודשים",       "meta": "7 ספקים",                        "emoji": "⟲", "bgColor": "#6366F1"}
        ]
      },
      {
        "id": "rating",
        "title": "דירוג",
        "type": "rating",
        "providerField": "rating"
      }
    ]
  }
}
```

---

## דוגמה 3 — קטגוריה חדשה לגמרי (categoryId: `pet_care`)

```json
{
  "name": "בעלי חיים",
  "csm": "pet_care",
  "parentCategory": null,
  "filterSchema": {
    "version": 1,
    "searchPlaceholder": "חפש שירות לחיית מחמד",
    "sections": [
      {
        "id": "intro",
        "type": "banner",
        "title": "",
        "extra": {
          "html": "🆕 קטגוריה חדשה! אנחנו עדיין מגייסים ספקים. ספקים: 28."
        }
      },
      {
        "id": "animal",
        "title": "סוג חיית מחמד",
        "type": "cards",
        "providerField": "petCareProfile.animalTypes",
        "options": [
          {"value": "dog",    "label": "כלבים",     "meta": "18 ספקים", "emoji": "🐕"},
          {"value": "cat",    "label": "חתולים",    "meta": "15 ספקים", "emoji": "🐈"},
          {"value": "bird",   "label": "ציפורים",   "meta": "4 ספקים",  "emoji": "🦜"},
          {"value": "exotic", "label": "אקזוטיים",  "meta": "2 ספקים",  "emoji": "🦎"}
        ]
      },
      {
        "id": "service",
        "title": "איזה שירות?",
        "subtitle": "בחר אחד או יותר",
        "type": "chips",
        "providerField": "petCareProfile.services",
        "options": [
          {"value": "walk",     "label": "הליכות",            "meta": "12 זמינים", "emoji": "🦮"},
          {"value": "sitting",  "label": "פנסיון",            "meta": "8 זמינים",  "emoji": "🏠"},
          {"value": "grooming", "label": "טיפוח",             "meta": "6 זמינים",  "emoji": "✂️"},
          {"value": "vet",      "label": "וטרינר עד הבית",    "meta": "4 זמינים",  "emoji": "⚕️"},
          {"value": "vaccine",  "label": "חיסון",             "meta": "3 זמינים",  "emoji": "💉"},
          {"value": "training", "label": "אילוף",             "meta": "7 זמינים",  "emoji": "🎓"}
        ]
      },
      {
        "id": "cert",
        "title": "הסמכות מקצועיות",
        "type": "switches",
        "providerField": "petCareProfile.certifications",
        "options": [
          {"value": "vet_cert",  "label": "תעודת וטרינר רשמית", "meta": "4 ספקים",          "emoji": "⚕️", "bgColor": "#10B981"},
          {"value": "trainer",   "label": "מאלף מוסמך IGP",     "meta": "3 ספקים · מתקדם",  "emoji": "🏅", "bgColor": "#F59E0B"},
          {"value": "insurance", "label": "ביטוח אחריות לחיה",  "meta": "12 ספקים",         "emoji": "🛡", "bgColor": "#3B82F6"}
        ]
      },
      {
        "id": "price",
        "title": "תקציב לביקור",
        "subtitle": "מחיר ממוצע: ₪150",
        "type": "price",
        "providerField": "petCareProfile.pricePerVisit",
        "extra": {
          "min": 0, "max": 500, "defaultRange": [80, 250],
          "histogram": [8, 18, 42, 65, 100, 82, 55, 32, 20, 12, 8, 5, 3, 2, 1]
        }
      }
    ]
  }
}
```

---

## איך להוסיף ב-Firebase Console (3 דקות)

1. פתח Firebase Console → Firestore Database
2. לך ל-collection `categories`
3. בחר במסמך הקטגוריה (או צור חדש)
4. הוסף שדה חדש בשם `filterSchema` מסוג `Map`
5. בתוך ה-Map, הדבק את ה-JSON שלמעלה (בלי השדה החיצוני `name`)
6. שמור — האפליקציה תרים את זה תוך 30 דקות (TTL של ה-cache), או מיד אם תקרא ל-`FilterSchemaService.instance.invalidate(categoryId)`

---

## טיפ: סקריפט seed (Node.js)

אם יש לך הרבה קטגוריות, השתמש ב-`firebase-admin`:

```javascript
const admin = require('firebase-admin');
admin.initializeApp({/* credentials */});

const db = admin.firestore();
const schemas = {
  english_tutors: { /* JSON מלמעלה */ },
  pest_control: { /* ... */ },
  pet_care: { /* ... */ }
};

(async () => {
  for (const [id, data] of Object.entries(schemas)) {
    await db.collection('categories').doc(id).set(data, { merge: true });
    console.log(`✓ ${id}`);
  }
})();
```
