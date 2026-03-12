/**
 * Seed script — כותב את הקטגוריות ל-Firestore.
 * הרצה: node functions/seed_categories.js
 *
 * דרישה: קובץ serviceAccountKey.json בתיקיית הפרויקט הראשית.
 * הורד אותו מ:
 *   Firebase Console → Project Settings → Service Accounts → Generate new private key
 */

const admin = require('firebase-admin');
const fs    = require('fs');
const path  = require('path');

// ─── נתוני הקטגוריות (מקביל ל-constants.dart) ─────────────────────────────
const CATEGORIES = [
  { name: 'שיפוצים',        iconName: 'build',             img: 'https://images.unsplash.com/photo-1581094794329-c8112a89af12?w=500', order: 0 },
  { name: 'ניקיון',          iconName: 'cleaning_services', img: 'https://images.unsplash.com/photo-1581578731548-c64695cc6958?w=500', order: 1 },
  { name: 'צילום',           iconName: 'camera_alt',        img: 'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?w=500', order: 2 },
  { name: 'אימון כושר',     iconName: 'fitness_center',    img: 'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?w=500', order: 3 },
  { name: 'שיעורים פרטיים', iconName: 'school',            img: 'https://images.unsplash.com/photo-1497633762265-9d179a990aa6?w=500', order: 4 },
  { name: 'עיצוב גרפי',    iconName: 'palette',           img: 'https://images.unsplash.com/photo-1558655146-d09347e92766?w=500', order: 5 },
];

// ─── אתחול Admin SDK ────────────────────────────────────────────────────────
const keyPath = path.join(__dirname, '..', 'serviceAccountKey.json');

if (!fs.existsSync(keyPath)) {
  console.error(`
❌ לא נמצא קובץ serviceAccountKey.json.

כדי להפיק אותו:
  1. Firebase Console → Project Settings → Service Accounts
  2. לחץ "Generate new private key" → שמור כ-serviceAccountKey.json בתיקיית הפרויקט הראשית

לאחר מכן הרץ שוב: node functions/seed_categories.js
`);
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(keyPath),
  projectId:  'anyskill-6fdf3',
});

// ─── פונקציית ה-Seed ────────────────────────────────────────────────────────
async function seedCategories() {
  const db    = admin.firestore();
  const batch = db.batch();

  for (const cat of CATEGORIES) {
    const ref = db.collection('categories').doc(cat.name); // שם = doc ID
    batch.set(ref, {
      name:     cat.name,
      iconName: cat.iconName,
      img:      cat.img,
      order:    cat.order,
    });
  }

  await batch.commit();
  console.log(`✅ ${CATEGORIES.length} קטגוריות נכתבו ל-Firestore בהצלחה!`);
  CATEGORIES.forEach(c => console.log(`   • ${c.name}`));
}

seedCategories()
  .then(() => process.exit(0))
  .catch(err => {
    console.error('❌ שגיאה:', err.message);
    process.exit(1);
  });
