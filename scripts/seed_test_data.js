/**
 * seed_test_data.js
 * -----------------
 * Seeds 2,000 test users (1,000 clients + 1,000 providers) into Firestore.
 * All documents are tagged with `isDemo: true` for easy cleanup.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json node seed_test_data.js
 *   -- OR --
 *   node seed_test_data.js   (if running inside a GCP environment / Firebase emulator)
 *
 * Requirements:
 *   npm install firebase-admin
 */

'use strict';

const admin = require('firebase-admin');

// ---------------------------------------------------------------------------
// Firebase init — Application Default Credentials (no hardcoded keys)
// ---------------------------------------------------------------------------
admin.initializeApp({
  projectId: 'anyskill-6fdf3',
});

const db = admin.firestore();

// ---------------------------------------------------------------------------
// Static data pools
// ---------------------------------------------------------------------------

const HEBREW_FIRST_NAMES = [
  'אבי', 'ירון', 'גל', 'תמר', 'שרה', 'דנה', 'רון', 'אורי', 'ליאת', 'נועה',
  'יובל', 'עומר', 'מיכל', 'אלון', 'שיר', 'בר', 'ניר', 'איל', 'ריטה', 'חן',
  'אסף', 'לירון', 'קרן', 'עדי', 'הדר', 'רותם', 'דור', 'יעל', 'אמיר', 'נגה',
  'ישי', 'ענת', 'שלומי', 'מור', 'ליאור', 'פז', 'נדב', 'צור', 'מאיה', 'שחר',
  'עינב', 'גיא', 'ארי', 'טל', 'ינאי', 'דביר', 'הילה', 'עמית', 'ולנטינה', 'ראם',
];

const HEBREW_LAST_NAMES = [
  'כהן', 'לוי', 'מזרחי', 'פרץ', 'ביטון', 'אברהם', 'גבאי', 'שמש', 'אוחיון', 'דהן',
  'חדד', 'אזולאי', 'אלבז', 'בנדל', 'גרוס', 'הרשקוביץ', 'ורד', 'זיו', 'חיון', 'טובי',
  'ישראלי', 'כץ', 'לנדאו', 'מלול', 'נחמיאס', 'סבג', 'עמר', 'פלד', 'צור', 'קלינגר',
  'רוזן', 'שפירא', 'תבור', 'בר-לב', 'גולן', 'דוד', 'הראל', 'ויצמן', 'זהבי', 'חורי',
];

const CITIES = [
  { name: 'תל אביב',     lat: 32.07, lng: 34.77 },
  { name: 'ירושלים',     lat: 31.77, lng: 35.21 },
  { name: 'חיפה',        lat: 32.81, lng: 35.00 },
  { name: 'באר שבע',     lat: 31.24, lng: 34.79 },
  { name: 'נתניה',       lat: 32.33, lng: 34.85 },
  { name: 'ראשון לציון', lat: 31.97, lng: 34.80 },
  { name: 'פתח תקווה',   lat: 32.09, lng: 34.88 },
  { name: 'אשדוד',       lat: 31.80, lng: 34.65 },
];

const SERVICE_CATEGORIES = [
  'ניקיון', 'אינסטלציה', 'חשמלאי', 'מזגנים', 'שיפוצים',
  'גינון',  'צביעה',     'ריצוף',  'מנעולן',  'קצבי',
  'נגרות',  'טכנאי מחשבים',
];

const PROVIDER_BIOS = [
  'מקצועי עם ניסיון של מעל 10 שנים בתחום. עבודה נקייה ואמינה.',
  'נותן שירות ברמה גבוהה, מחירים הוגנים, ממליצים עליי.',
  'זמין לקריאות דחופות, מגיע בזמן ומבצע עבודה מעולה.',
  'בעל רישיון מקצועי ואחריות על כל עבודה. קורא לי בכל שעה.',
  'ותיק בתחום, מכיר את כל הדגמים והפתרונות. ממליצים בחום.',
  'שירות אישי, מחירים תחרותיים, עבודה איכותית ללא פשרות.',
  'עובד עם הציוד הטוב ביותר, מחיר שווה ערך לאיכות.',
  'פתרונות מהירים לכל בעיה, ניסיון של שנים בתחום.',
];

const CLIENT_BIOS = [
  'מחפש שירותים איכותיים לדירתי.',
  'צריך עזרה עם עבודות שיפוץ ותחזוקה.',
  'בעלים של בית פרטי, תמיד צריך עזרה.',
  'שוכר דירה, מחפש בעלי מקצוע מהימנים.',
  '',
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function pick(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function randomFloat(min, max, decimals = 1) {
  return parseFloat((Math.random() * (max - min) + min).toFixed(decimals));
}

function generateName() {
  return `${pick(HEBREW_FIRST_NAMES)} ${pick(HEBREW_LAST_NAMES)}`;
}

function generateEmail(index) {
  const prefix = `demo_user_${String(index).padStart(4, '0')}`;
  return `${prefix}@anyskill-demo.test`;
}

function generatePhone() {
  const prefixes = ['050', '052', '053', '054', '058'];
  return `${pick(prefixes)}-${randomInt(1000000, 9999999)}`;
}

function generateFcmToken(uid) {
  // Realistic-looking but fake FCM token
  const hex = () => Math.random().toString(16).slice(2).padEnd(16, '0');
  return `demo_fcm_${uid}_${hex()}${hex()}`;
}

function generateProviderDoc(index, uid) {
  const city = pick(CITIES);
  const name = generateName();
  const category = pick(SERVICE_CATEGORIES);
  const now = admin.firestore.Timestamp.now();
  const createdDaysAgo = randomInt(30, 730);
  const createdAt = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() - createdDaysAgo * 86400 * 1000)
  );

  return {
    uid,
    name,
    email: generateEmail(index),
    phone: generatePhone(),
    city: city.name,
    location: new admin.firestore.GeoPoint(
      city.lat + randomFloat(-0.05, 0.05, 4),
      city.lng + randomFloat(-0.05, 0.05, 4)
    ),
    balance: randomFloat(0, 5000, 2),
    pendingBalance: randomFloat(0, 1000, 2),
    xp: randomInt(100, 5000),
    rating: randomFloat(3.5, 5.0, 1),
    reviewsCount: randomInt(5, 200),
    isProvider: true,
    isCustomer: false,
    isVerified: true,
    isOnline: Math.random() > 0.4,
    isDemo: true,
    isHidden: false,
    serviceType: category,
    aboutMe: pick(PROVIDER_BIOS),
    pricePerHour: randomInt(80, 350),
    profileImage: `https://picsum.photos/seed/${uid}/200/200`,
    gallery: [],
    fcmToken: generateFcmToken(uid),
    certifiedCategories: Math.random() > 0.5 ? [category] : [],
    createdAt,
    lastActiveAt: now,
  };
}

function generateClientDoc(index, uid) {
  const city = pick(CITIES);
  const name = generateName();
  const now = admin.firestore.Timestamp.now();
  const createdDaysAgo = randomInt(7, 365);
  const createdAt = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() - createdDaysAgo * 86400 * 1000)
  );

  return {
    uid,
    name,
    email: generateEmail(1000 + index), // offset so emails don't collide with providers
    phone: generatePhone(),
    city: city.name,
    location: new admin.firestore.GeoPoint(
      city.lat + randomFloat(-0.05, 0.05, 4),
      city.lng + randomFloat(-0.05, 0.05, 4)
    ),
    balance: randomFloat(200, 2000, 2),
    pendingBalance: 0,
    xp: randomInt(0, 500),
    rating: 0,
    reviewsCount: 0,
    isProvider: false,
    isCustomer: true,
    isVerified: false,
    isOnline: Math.random() > 0.6,
    isDemo: true,
    isHidden: false,
    serviceType: null,
    aboutMe: pick(CLIENT_BIOS),
    pricePerHour: 0,
    profileImage: `https://picsum.photos/seed/client_${uid}/200/200`,
    gallery: [],
    fcmToken: generateFcmToken(uid),
    certifiedCategories: [],
    createdAt,
    lastActiveAt: now,
  };
}

// ---------------------------------------------------------------------------
// Batch writer — splits into chunks of 500 (Firestore hard limit)
// ---------------------------------------------------------------------------

const BATCH_SIZE = 500;

async function writeBatch(docs) {
  // docs: Array of { ref: DocumentReference, data: Object }
  const chunks = [];
  for (let i = 0; i < docs.length; i += BATCH_SIZE) {
    chunks.push(docs.slice(i, i + BATCH_SIZE));
  }

  for (const chunk of chunks) {
    const batch = db.batch();
    for (const { ref, data } of chunk) {
      batch.set(ref, data);
    }
    await batch.commit();
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const TOTAL_PROVIDERS = 1000;
  const TOTAL_CLIENTS   = 1000;
  const PROGRESS_INTERVAL = 100;

  console.log('=== AnySkill Seed Script ===');
  console.log(`Project : anyskill-6fdf3`);
  console.log(`Seeding : ${TOTAL_PROVIDERS} providers + ${TOTAL_CLIENTS} clients`);
  console.log('');

  const startTime = Date.now();

  // --- Providers ---
  console.log('--- Generating providers ---');
  let providerDocs = [];
  let providerCount = 0;

  for (let i = 0; i < TOTAL_PROVIDERS; i++) {
    const uid = `demo_provider_${String(i).padStart(4, '0')}`;
    const data = generateProviderDoc(i, uid);
    providerDocs.push({ ref: db.collection('users').doc(uid), data });

    providerCount++;
    if (providerCount % PROGRESS_INTERVAL === 0) {
      console.log(`  Queued  ${providerCount} / ${TOTAL_PROVIDERS} providers...`);
    }

    // Write in chunks of 500 to avoid holding too much in memory
    if (providerDocs.length === BATCH_SIZE) {
      await writeBatch(providerDocs);
      console.log(`  Written ${providerCount} providers to Firestore`);
      providerDocs = [];
    }
  }
  // Flush remaining
  if (providerDocs.length > 0) {
    await writeBatch(providerDocs);
    console.log(`  Written ${providerCount} providers to Firestore (final flush)`);
  }

  // --- Clients ---
  console.log('');
  console.log('--- Generating clients ---');
  let clientDocs = [];
  let clientCount = 0;

  for (let i = 0; i < TOTAL_CLIENTS; i++) {
    const uid = `demo_client_${String(i).padStart(4, '0')}`;
    const data = generateClientDoc(i, uid);
    clientDocs.push({ ref: db.collection('users').doc(uid), data });

    clientCount++;
    if (clientCount % PROGRESS_INTERVAL === 0) {
      console.log(`  Queued  ${clientCount} / ${TOTAL_CLIENTS} clients...`);
    }

    if (clientDocs.length === BATCH_SIZE) {
      await writeBatch(clientDocs);
      console.log(`  Written ${clientCount} clients to Firestore`);
      clientDocs = [];
    }
  }
  if (clientDocs.length > 0) {
    await writeBatch(clientDocs);
    console.log(`  Written ${clientCount} clients to Firestore (final flush)`);
  }

  const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
  const total = providerCount + clientCount;

  console.log('');
  console.log('=== SUMMARY ===');
  console.log(`  Providers written : ${providerCount}`);
  console.log(`  Clients written   : ${clientCount}`);
  console.log(`  Total written     : ${total}`);
  console.log(`  Elapsed time      : ${elapsed}s`);
  console.log('');
  console.log('All demo documents tagged with isDemo: true');
  console.log('Run cleanup_test_data.js to remove them.');
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
