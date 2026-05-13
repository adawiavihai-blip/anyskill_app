#!/usr/bin/env node
/**
 * seed_filter_schemas.js
 *
 * סקריפט להעלאת filterSchema לכל הקטגוריות ב-Firestore בבת אחת.
 * מריץ פעם אחת — מסיים את כל העבודה הידנית.
 *
 * שימוש:
 *   1. ודא ש-firebase-admin מותקן: npm install firebase-admin
 *   2. ודא שיש לך serviceAccountKey.json (הוראות ב-HOW_TO_RUN.md)
 *   3. הרץ: node seed_filter_schemas.js
 *
 * מה הסקריפט עושה:
 *   - מתחבר ל-Firestore עם credentials של admin
 *   - מוצא את כל הקטגוריות ב-collection "categories"
 *   - מעדכן בכל אחת את שדה filterSchema לפי המיפוי SCHEMAS למטה
 *   - לא מוחק שום שדה אחר — רק מוסיף/מעדכן filterSchema
 *   - בטוח להרצה חוזרת (idempotent)
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

// ============================================================================
// ה-SCHEMAS — מיפוי שם קטגוריה (כפי שמופיע ב-Firestore) → filterSchema
// ============================================================================
//
// 💡 איך לערוך:
//   - להוסיף קטגוריה חדשה: פשוט הוסף key חדש (שם הקטגוריה בעברית)
//   - להוריד קטגוריה: מחק את ה-key
//   - לשנות פילטרים: ערוך את ה-sections של הקטגוריה הרלוונטית
//
// 💡 הסקריפט מוצא את הקטגוריה לפי השדה name. אם השם בקובץ הזה
//    לא תואם בדיוק לשם ב-Firestore, הקטגוריה תידלג.

const SCHEMAS = {

  // ==========================================================================
  // עיסוי
  // ==========================================================================
  'עיסוי': {
    version: 1,
    searchPlaceholder: 'חפש מעסה',
    sections: [
      {
        id: 'massageType',
        title: 'סוג העיסוי',
        subtitle: 'בחר אחד או יותר',
        type: 'chips',
        providerField: 'massageProfile.specialties',
        options: [
          { value: 'swedish',   label: 'עיסוי שוודי',         emoji: '💆' },
          { value: 'deep',      label: 'עיסוי רקמות עמוק',     emoji: '💪' },
          { value: 'thai',      label: 'עיסוי תאילנדי',       emoji: '🧘' },
          { value: 'shiatsu',   label: 'שיאצו',               emoji: '✨' },
          { value: 'pregnancy', label: 'עיסוי הריון',         emoji: '🤰' },
        ],
      },
      {
        id: 'location',
        title: 'איפה?',
        subtitle: 'מקום העיסוי',
        type: 'cards',
        providerField: 'massageProfile.serviceLocations',
        singleSelect: true,
        options: [
          { value: 'home',   label: 'בבית שלי', emoji: '🏠' },
          { value: 'clinic', label: 'בקליניקה', emoji: '🏥' },
        ],
      },
      {
        id: 'rating',
        title: 'דירוג מינימלי',
        type: 'rating',
        providerField: 'rating',
      },
      {
        id: 'price',
        title: 'טווח מחירים',
        type: 'price',
        providerField: 'pricePerHour',
        extra: { min: 0, max: 1000, defaultRange: [200, 500] },
      },
    ],
  },

  // ==========================================================================
  // הדברה
  // ==========================================================================
  'הדברה': {
    version: 1,
    searchPlaceholder: 'חפש מדביר',
    sections: [
      {
        id: 'urgency',
        title: 'דחיפות',
        subtitle: 'מתי אתה צריך?',
        type: 'cards',
        singleSelect: true,
        required: true,
        providerField: 'pestControlProfile.emergency24_7',
        options: [
          { value: 'now',     label: 'חירום עכשיו', emoji: '🚨' },
          { value: 'today',   label: 'היום',         emoji: '⏱' },
          { value: 'planned', label: 'תיאום מראש',   emoji: '📅' },
        ],
      },
      {
        id: 'pests',
        title: 'סוג מזיק',
        type: 'chips',
        providerField: 'pestControlProfile.pestTypes',
        options: [
          { value: 'roach',  label: 'ג׳וקים',     emoji: '🪳' },
          { value: 'ants',   label: 'נמלים',      emoji: '🐜' },
          { value: 'mice',   label: 'עכברים',     emoji: '🐭' },
          { value: 'rats',   label: 'חולדות',     emoji: '🐀' },
          { value: 'bedbug', label: 'פשפשי מיטה'              },
          { value: 'snake',  label: 'נחשים',      emoji: '🐍' },
        ],
      },
      {
        id: 'method',
        title: 'שיטת טיפול',
        subtitle: 'חשוב במיוחד עם ילדים וחיות',
        type: 'cards',
        providerField: 'pestControlProfile.treatmentMethods',
        options: [
          { value: 'green',  label: 'ירוק/אורגני',   emoji: '🌿' },
          { value: 'spray',  label: 'ריסוס סטנדרטי', emoji: '💨' },
          { value: 'heat',   label: 'טיפול בחום',    emoji: '🔥' },
          { value: 'inject', label: 'הזרקה ממוקדת',  emoji: '⚗' },
        ],
      },
      {
        id: 'rating',
        title: 'דירוג מינימלי',
        type: 'rating',
        providerField: 'rating',
      },
      {
        id: 'price',
        title: 'טווח מחירים',
        type: 'price',
        providerField: 'pricePerHour',
        extra: { min: 0, max: 2000, defaultRange: [250, 800] },
      },
    ],
  },

  // ==========================================================================
  // ניקיון בית
  // ==========================================================================
  'ניקיון הבית': {
    version: 1,
    searchPlaceholder: 'חפש מנקה',
    sections: [
      {
        id: 'cleaningType',
        title: 'סוג ניקיון',
        type: 'cards',
        providerField: 'cleaningProfile.cleaningTypes',
        options: [
          { value: 'regular',  label: 'ניקיון רגיל',   emoji: '⌂' },
          { value: 'deep',     label: 'ניקיון יסודי',  emoji: '★' },
          { value: 'reno',     label: 'אחרי שיפוץ',    emoji: '🔨' },
          { value: 'airbnb',   label: 'Airbnb',        emoji: '🛏' },
        ],
      },
      {
        id: 'frequency',
        title: 'תדירות',
        subtitle: 'הנחה אוטומטית לקבועים',
        type: 'cards',
        singleSelect: true,
        providerField: 'cleaningProfile.recurringDiscounts',
        options: [
          { value: 'once',     label: 'חד-פעמי',           emoji: '1️⃣' },
          { value: 'weekly',   label: 'שבועי · -15%',     emoji: '📅' },
          { value: 'biweekly', label: 'דו-שבועי · -10%', emoji: '🗓' },
        ],
      },
      {
        id: 'rating',
        title: 'דירוג מינימלי',
        type: 'rating',
        providerField: 'rating',
      },
      {
        id: 'price',
        title: 'מחיר לשעה',
        type: 'price',
        providerField: 'pricePerHour',
        extra: { min: 0, max: 300, defaultRange: [70, 150] },
      },
    ],
  },

  // ==========================================================================
  // אנגלית (שיעורים פרטיים)
  // ==========================================================================
  'אנגלית': {
    version: 1,
    searchPlaceholder: 'חפש מורה לאנגלית',
    sections: [
      {
        id: 'goal',
        title: 'המטרה שלך',
        type: 'cards',
        singleSelect: true,
        required: true,
        providerField: 'categoryTags',
        options: [
          { value: 'bagrut', label: 'בגרות באנגלית',   emoji: '🎓' },
          { value: 'conv',   label: 'שיחה שוטפת',      emoji: '💬' },
          { value: 'ielts',  label: 'IELTS / TOEFL',  emoji: '🌍' },
          { value: 'kids',   label: 'לילדים',          emoji: '🧸' },
        ],
      },
      {
        id: 'format',
        title: 'איפה?',
        type: 'cards',
        singleSelect: true,
        providerField: 'categoryTags',
        options: [
          { value: 'online', label: 'אונליין',    emoji: '💻' },
          { value: 'myhome', label: 'בבית שלי',   emoji: '🏠' },
          { value: 'theirs', label: 'אצל המורה',  emoji: '📍' },
        ],
      },
      {
        id: 'rating',
        title: 'דירוג מינימלי',
        type: 'rating',
        providerField: 'rating',
      },
      {
        id: 'price',
        title: 'מחיר לשעה',
        type: 'price',
        providerField: 'pricePerHour',
        extra: { min: 0, max: 500, defaultRange: [80, 200] },
      },
    ],
  },

};

// ============================================================================
// לוגיקת ההרצה — לא צריך לערוך מתחת לכאן
// ============================================================================

(async () => {
  console.log('\n🔍 מחפש קטגוריות ב-Firestore...\n');

  const snapshot = await db.collection('categories').get();
  console.log(`✓ נמצאו ${snapshot.size} קטגוריות.\n`);

  let updated = 0;
  let skipped = 0;
  const notFound = [];

  for (const [name, schema] of Object.entries(SCHEMAS)) {
    // מוצא קטגוריה לפי שדה name או לפי ID של המסמך
    let matched = null;
    snapshot.forEach((doc) => {
      const data = doc.data();
      if (data.name === name || doc.id === name) {
        matched = doc;
      }
    });

    if (!matched) {
      console.log(`⚠️  "${name}" — לא נמצאה ב-Firestore (דילוג)`);
      notFound.push(name);
      skipped++;
      continue;
    }

    await matched.ref.update({ filterSchema: schema });
    console.log(`✅ "${name}" — עודכן בהצלחה (${schema.sections.length} sections)`);
    updated++;
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`✓ עודכנו: ${updated} קטגוריות`);
  console.log(`⊘ דולגו:  ${skipped} קטגוריות`);
  if (notFound.length > 0) {
    console.log(`\n💡 קטגוריות שלא נמצאו (ייתכן ושמן שונה ב-Firestore):`);
    notFound.forEach((n) => console.log(`   - "${n}"`));
    console.log(`\n   פתח Firestore → categories → בדוק את שם הקטגוריה`);
    console.log(`   (השדה "name") ועדכן את ה-key בסקריפט הזה.`);
  }
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  process.exit(0);
})().catch((err) => {
  console.error('\n❌ שגיאה:', err.message);
  process.exit(1);
});
