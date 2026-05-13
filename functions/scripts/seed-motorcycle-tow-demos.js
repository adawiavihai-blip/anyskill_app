// One-off seed script: create 3 polished demo motorcycle-tow providers.
//
// Mirrors what AdminDemoExpertsTab._save would write — see CLAUDE.md §4.7
// (demo expert profiles) + §55 (motorcycle towing CSM) + §56 (CSM Build
// Checklist). Each demo gets:
//
//   users/{uid}                 — full profile (isDemo:true, isVerified:true)
//   provider_listings/demo_{uid} — search-discoverable listing
//   reviews/*                    — 3-4 reviews per expert (isDemo:true)
//
// Idempotent — re-running upserts the SAME UIDs (deterministic ids
// `demo_moto_tow_1/2/3`) so the script can be re-run safely without
// creating duplicates.
//
// Run:
//   cd functions
//   node scripts/seed-motorcycle-tow-demos.js
//
// Dry-run:
//   node scripts/seed-motorcycle-tow-demos.js --dry-run

const admin = require("firebase-admin");
const path = require("path");
const fs = require("fs");

const DRY_RUN = process.argv.includes("--dry-run");

// ── Credentials ───────────────────────────────────────────────────────────
const SA_PATH = path.join(__dirname, "..", "service-account.json");
if (fs.existsSync(SA_PATH)) {
  admin.initializeApp({ credential: admin.credential.cert(require(SA_PATH)) });
} else {
  admin.initializeApp({ projectId: "anyskill-6fdf3" });
}

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;
const Timestamp = admin.firestore.Timestamp;

// ── Shared schema bits ────────────────────────────────────────────────────
const SERVICE_TYPE = "גרר אופנועים"; // sub-category NAME (not doc id)
const PARENT_CATEGORY = "תחבורה";

const WORKING_HOURS_ALL_WEEK = {
  "0": { from: "00:00", to: "23:59" }, // Sunday — 24/7
  "1": { from: "00:00", to: "23:59" },
  "2": { from: "00:00", to: "23:59" },
  "3": { from: "00:00", to: "23:59" },
  "4": { from: "00:00", to: "23:59" },
  "5": { from: "06:00", to: "16:00" }, // Friday — short
  "6": { from: "21:00", to: "23:59" }, // Saturday — evening only
};

const WORKING_HOURS_BUSINESS = {
  "0": { from: "07:00", to: "22:00" },
  "1": { from: "07:00", to: "22:00" },
  "2": { from: "07:00", to: "22:00" },
  "3": { from: "07:00", to: "22:00" },
  "4": { from: "07:00", to: "22:00" },
  "5": { from: "07:00", to: "14:00" },
};

// ── 3 demo experts ────────────────────────────────────────────────────────
const DEMOS = [
  {
    uid: "demo_moto_tow_1",
    name: "אבי כהן — גרר אופנועים 24/7",
    phone: "050-1234567",
    email: "avi.tow.demo@anyskill.app",
    aboutMe:
      "ותיק בענף הגרירה — 12 שנות ניסיון בגרירת אופנועי ספורט, אדוונצ׳ר וקרוזרים. " +
      "צי משאיות פלטה מצוידות בעריסות גלגל ורצועות בד רכות. זמין 24/7 לכל גוש דן " +
      "והשפלה. מטפל בכל סוגי המקרים — תאונות, חילוץ משטח, פנצ׳רים ותקלות מנוע. " +
      "מחיר הוגן, אמינות מלאה, ובעיקר — בעל הניסיון להעביר את האופנוע שלך ללא שריטה.",
    profileImage:
      "https://images.unsplash.com/photo-1556157382-97eda2d62296?w=400&h=400&fit=crop&q=80",
    gallery: [
      "https://images.unsplash.com/photo-1597007030739-6d2e7172ee6b?w=800&h=600&fit=crop&q=80",
      "https://images.unsplash.com/photo-1568772585407-9361f9bf3a87?w=800&h=600&fit=crop&q=80",
      "https://images.unsplash.com/photo-1558981403-c5f9899a28bc?w=800&h=600&fit=crop&q=80",
      "https://images.unsplash.com/photo-1547549082-6bc09f2049ae?w=800&h=600&fit=crop&q=80",
    ],
    completedJobs: 487,
    rating: 4.9,
    reviewsCount: 142,
    pricePerHour: 180,
    workingHours: WORKING_HOURS_ALL_WEEK,
    quickTags: ["fast_response", "reliable", "professional", "24_7"],
    isTopRated: true,
    motorcycleTowProfile: {
      bikeTypeIds: ["sport", "cruiser", "adventure", "scooter", "vintage"],
      pricing: {
        basePrice: 180,
        pricePerKm: 4.5,
        includedKm: 10,
        nightSurchargePercent: 25,
        nightStartHour: 22,
        nightEndHour: 6,
        emergencySurchargePercent: 50,
      },
      equipment: {
        flatbed: true,
        wheelCradle: true,
        softStraps: true,
        electricWinch: true,
        towDolly: false,
      },
      serviceCases: [
        "accident",
        "engine_fault",
        "flat_tire",
        "dead_battery",
        "planned_tow",
        "off_terrain_rescue",
        "intercity",
      ],
      serviceArea: {
        mode: "radius",
        baseAddress: "תל אביב, ישראל",
        baseLat: 32.0853,
        baseLng: 34.7818,
        radiusKm: 60,
        polygonPoints: [],
      },
      smartFeatures: {
        beforeAfterPhotos: true,
        instantQuote: true,
        internalChat: true,
      },
    },
    reviews: [
      {
        reviewerName: "יואב לוי",
        rating: 5,
        comment:
          "הזמנתי בלילה אחרי שהאופנוע (סוזוקי GSX-R750) נתקע באיילון. אבי הגיע בתוך " +
          "25 דקות, עבד בזהירות מקסימלית, ועלות הסופית הייתה בדיוק כמו שהוסכם בצ׳אט. " +
          "המלצה חמה!",
        daysAgo: 4,
      },
      {
        reviewerName: "רונן מזרחי",
        rating: 5,
        comment:
          "השירות הטוב ביותר שקיבלתי. רצועות רכות, פלטה רחבה, ואפס נזק לאופנוע " +
          "האדוונצ׳ר שלי. ימליץ לכל אופנוען רציני.",
        daysAgo: 11,
      },
      {
        reviewerName: "טל פרידמן",
        rating: 5,
        comment:
          "הציוד שלו ברמה אחרת — עריסת גלגל, כננת חשמלית, הכל. מקצוען אמיתי.",
        daysAgo: 22,
      },
      {
        reviewerName: "אורן בן-דוד",
        rating: 4,
        comment:
          "הגיע מהר, אבל היה צריך לחכות קצת בגלל פקקים. עבודה איכותית, מחיר הוגן.",
        daysAgo: 35,
      },
    ],
  },

  {
    uid: "demo_moto_tow_2",
    name: "שלומי בנימין — גרר ספורט מקצועי",
    phone: "052-9876543",
    email: "shlomi.sport.tow.demo@anyskill.app",
    aboutMe:
      "מתמחה בגרירת אופנועי ספורט וסופר-ספורט — דוקאטי, BMW S1000RR, ימהה R1, " +
      "אפריליה RSV4. כל הקלינטים שלי הם רוכבי טראק וחובבי ביצועים. ציוד מותאם, " +
      "ידע מעמיק במסגרות מירוץ ובאופציות הקיבוע הנכונות לכל דגם. שירות מנמרצת " +
      "וחיוני — תאונות במסלול, חילוץ ממרוצים, ושינוע בין מוסכים מתמחים.",
    profileImage:
      "https://images.unsplash.com/photo-1531746020798-e6953c6e8e04?w=400&h=400&fit=crop&q=80",
    gallery: [
      "https://images.unsplash.com/photo-1568772585407-9361f9bf3a87?w=800&h=600&fit=crop&q=80",
      "https://images.unsplash.com/photo-1568160571-2ddc7a8a8bf6?w=800&h=600&fit=crop&q=80",
      "https://images.unsplash.com/photo-1591216105232-d23bea36b827?w=800&h=600&fit=crop&q=80",
      "https://images.unsplash.com/photo-1517466787929-bc90951d0974?w=800&h=600&fit=crop&q=80",
    ],
    completedJobs: 312,
    rating: 4.8,
    reviewsCount: 89,
    pricePerHour: 220,
    workingHours: WORKING_HOURS_BUSINESS,
    quickTags: ["specialist", "professional", "fair_price"],
    isTopRated: true,
    motorcycleTowProfile: {
      bikeTypeIds: ["sport", "adventure", "vintage"],
      pricing: {
        basePrice: 220,
        pricePerKm: 5.0,
        includedKm: 8,
        nightSurchargePercent: 30,
        nightStartHour: 22,
        nightEndHour: 6,
        emergencySurchargePercent: 60,
      },
      equipment: {
        flatbed: true,
        wheelCradle: true,
        softStraps: true,
        electricWinch: true,
        towDolly: true,
      },
      serviceCases: [
        "accident",
        "engine_fault",
        "planned_tow",
        "intercity",
        "off_terrain_rescue",
      ],
      serviceArea: {
        mode: "radius",
        baseAddress: "הרצליה, ישראל",
        baseLat: 32.16627,
        baseLng: 34.84368,
        radiusKm: 80,
        polygonPoints: [],
      },
      smartFeatures: {
        beforeAfterPhotos: true,
        instantQuote: true,
        internalChat: true,
      },
    },
    reviews: [
      {
        reviewerName: "דניאל סופר",
        rating: 5,
        comment:
          "האופנוע שלי (BMW S1000RR) זקוק לטיפול עדין מאוד. שלומי ידע בדיוק איך " +
          "לתפוס אותו במסגרת ולקבע עם רצועות הספציפיות. עשרים דקות מהרגע שצלצלתי.",
        daysAgo: 6,
      },
      {
        reviewerName: "אסף הראל",
        rating: 5,
        comment:
          "התקשרתי אחרי תאונה קלה בכביש החוף. שלומי הגיע, צילם הכל לפני ההעמסה, " +
          "והעביר את האופנוע למוסך שביקשתי. שירות לקוחות מצוין.",
        daysAgo: 14,
      },
      {
        reviewerName: "עידן שטיינברג",
        rating: 5,
        comment:
          "הוא היחיד בארץ שאני סומך עליו עם הדוקאטי פניגאלה שלי. נקודה.",
        daysAgo: 28,
      },
      {
        reviewerName: "ניר אזולאי",
        rating: 4,
        comment:
          "מקצועי מאוד, יקר טיפה מהממוצע אבל מקבלים תמורה אמיתית.",
        daysAgo: 41,
      },
    ],
  },

  {
    uid: "demo_moto_tow_3",
    name: "מאיר אברהמי — גרר כל אופנוע",
    phone: "054-5551234",
    email: "meir.kol.tow.demo@anyskill.app",
    aboutMe:
      "8 שנים בענף עם התמחות בקטנועי שליחים, אופנועי שטח ואופנועים וינטג׳. " +
      "מבין שאופנוע תקוע משמעו פגיעה בפרנסה, אז אני מגיע מהר ובמחיר הוגן. " +
      "צי משאיות פלטה + דולי עגלה לקטנועים קטנים. שירות מיוחד לציי שליחויות — " +
      "חוזי שירות חודשיים עם תעריפים מוזלים. גם חילוץ מהשטח ופנצ׳רים בבתי לקוח.",
    profileImage:
      "https://images.unsplash.com/photo-1492562080023-ab3db95bfbce?w=400&h=400&fit=crop&q=80",
    gallery: [
      "https://images.unsplash.com/photo-1591216105232-d23bea36b827?w=800&h=600&fit=crop&q=80",
      "https://images.unsplash.com/photo-1547549082-6bc09f2049ae?w=800&h=600&fit=crop&q=80",
      "https://images.unsplash.com/photo-1609630875171-b1321377ee65?w=800&h=600&fit=crop&q=80",
      "https://images.unsplash.com/photo-1599819811279-d5ad9cccf838?w=800&h=600&fit=crop&q=80",
    ],
    completedJobs: 256,
    rating: 4.7,
    reviewsCount: 71,
    pricePerHour: 150,
    workingHours: WORKING_HOURS_ALL_WEEK,
    quickTags: ["fast_response", "fair_price", "fleet_service"],
    isTopRated: false,
    motorcycleTowProfile: {
      bikeTypeIds: ["scooter", "offroad", "vintage", "cruiser"],
      pricing: {
        basePrice: 150,
        pricePerKm: 4.0,
        includedKm: 12,
        nightSurchargePercent: 20,
        nightStartHour: 23,
        nightEndHour: 5,
        emergencySurchargePercent: 40,
      },
      equipment: {
        flatbed: true,
        wheelCradle: true,
        softStraps: true,
        electricWinch: false,
        towDolly: true,
      },
      serviceCases: [
        "accident",
        "engine_fault",
        "flat_tire",
        "dead_battery",
        "planned_tow",
        "off_terrain_rescue",
        "wrong_fuel",
        "lockout",
      ],
      serviceArea: {
        mode: "radius",
        baseAddress: "ראשון לציון, ישראל",
        baseLat: 31.96, // adjusted to keep within IL bounds
        baseLng: 34.804,
        radiusKm: 45,
        polygonPoints: [],
      },
      smartFeatures: {
        beforeAfterPhotos: true,
        instantQuote: true,
        internalChat: true,
      },
    },
    reviews: [
      {
        reviewerName: "אלון רוזן",
        rating: 5,
        comment:
          "ניהול חברת שליחויות עם 12 קטנועים. מאיר הוא הספק הבלעדי שלי לגרירות. " +
          "מהיר, אמין, ומחירים סבירים. ממליץ בלי היסוס.",
        daysAgo: 9,
      },
      {
        reviewerName: "שגיא בן-ארי",
        rating: 5,
        comment:
          "החזיר לי לקטנוע אחרי שדיממתי את המצבר בחיפה. הביא חוסם, מילא דלק, " +
          "וטסטו שהכל עובד. שירות 360.",
        daysAgo: 18,
      },
      {
        reviewerName: "אילן זוהר",
        rating: 4,
        comment:
          "הוינטג׳ שלי (טריומף בונבייל 1973) הגיע בשלום למוסך. מאיר ידע " +
          "להתייחס אליו בעדינות.",
        daysAgo: 33,
      },
      {
        reviewerName: "יוסי שמש",
        rating: 5,
        comment:
          "גרירה הכי זולה שמצאתי + שירות מעולה. מה עוד אפשר לבקש?",
        daysAgo: 52,
      },
    ],
  },
];

async function main() {
  console.log(`[Seed Moto Tow Demos] DRY_RUN=${DRY_RUN}`);
  console.log(`[Seed] Creating ${DEMOS.length} demo provider(s)…\n`);

  let created = 0;
  let updated = 0;
  let reviewsWritten = 0;
  let errors = 0;

  for (const demo of DEMOS) {
    try {
      const uid = demo.uid;
      const listingId = `demo_${uid}`;

      // ── 1. user doc ──────────────────────────────────────────────────────
      const userData = {
        uid,
        name: demo.name,
        phone: demo.phone,
        email: demo.email,
        aboutMe: demo.aboutMe,
        profileImage: demo.profileImage,
        serviceType: SERVICE_TYPE,
        subCategoryName: SERVICE_TYPE,
        parentCategory: PARENT_CATEGORY,
        gallery: demo.gallery,
        completedJobs: demo.completedJobs,
        rating: demo.rating,
        reviewsCount: demo.reviewsCount,
        pricePerHour: demo.pricePerHour,
        categoryDetails: {},
        workingHours: demo.workingHours,
        cancellationPolicy: "moderate",
        quickTags: demo.quickTags,
        motorcycleTowProfile: demo.motorcycleTowProfile,
        responseTimeMinutes: 12,
        isProvider: true,
        isCustomer: false,
        isDemo: true,
        isOnline: true,
        isVerified: true,
        isTopRated: demo.isTopRated,
        isAnySkillPro: demo.isTopRated,
        isHidden: false,
        balance: 0,
        listingIds: [listingId],
        activeIdentityCount: 1,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      };

      // ── 2. provider_listings doc ─────────────────────────────────────────
      const listingData = {
        uid,
        identityIndex: 0,
        name: demo.name,
        profileImage: demo.profileImage,
        isVerified: true,
        isHidden: false,
        isDemo: true,
        isVolunteer: false,
        isOnline: true,
        isAnySkillPro: demo.isTopRated,
        isPromoted: false,
        serviceType: SERVICE_TYPE,
        parentCategory: PARENT_CATEGORY,
        subCategory: SERVICE_TYPE,
        aboutMe: demo.aboutMe,
        pricePerHour: demo.pricePerHour,
        gallery: demo.gallery,
        categoryDetails: {},
        quickTags: demo.quickTags,
        workingHours: demo.workingHours,
        cancellationPolicy: "moderate",
        motorcycleTowProfile: demo.motorcycleTowProfile,
        responseTimeMinutes: 12,
        rating: demo.rating,
        reviewsCount: demo.reviewsCount,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      };

      if (DRY_RUN) {
        console.log(`   [dry-run] would write users/${uid} (${demo.name})`);
        console.log(`   [dry-run] would write provider_listings/${listingId}`);
        console.log(`   [dry-run] would write ${demo.reviews.length} reviews`);
      } else {
        // Check whether the doc exists so we report create vs update
        const exists = (await db.collection("users").doc(uid).get()).exists;
        await db.collection("users").doc(uid).set(userData, { merge: true });
        await db
          .collection("provider_listings")
          .doc(listingId)
          .set(listingData, { merge: true });

        if (exists) {
          updated++;
        } else {
          created++;
        }

        // ── 3. reviews ────────────────────────────────────────────────────
        // First, clean up old demo reviews for this expert to avoid stacking
        // on each run.
        const existingReviews = await db
          .collection("reviews")
          .where("expertId", "==", uid)
          .where("isDemo", "==", true)
          .get();
        const batch = db.batch();
        for (const r of existingReviews.docs) {
          batch.delete(r.ref);
        }
        for (const r of demo.reviews) {
          const date = new Date(Date.now() - r.daysAgo * 24 * 60 * 60 * 1000);
          const ref = db.collection("reviews").doc();
          batch.set(ref, {
            expertId: uid,
            listingId,
            reviewerId: `demo_reviewer_${ref.id}`,
            reviewerName: r.reviewerName,
            rating: r.rating,
            comment: r.comment,
            timestamp: Timestamp.fromDate(date),
            traitTags: ["professional", "punctual"],
            isDemo: true,
          });
          reviewsWritten++;
        }
        await batch.commit();

        console.log(
          `   ✅ ${demo.name} (${uid}) — ${demo.reviews.length} reviews`
        );
      }
    } catch (e) {
      errors++;
      console.error(`   ❌ ${demo.name}: ${e.message}`);
    }
  }

  console.log("\n[Seed] DONE.");
  console.log(`   created: ${created}`);
  console.log(`   updated: ${updated}`);
  console.log(`   reviews: ${reviewsWritten}`);
  console.log(`   errors:  ${errors}`);
  process.exit(errors > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error("[Seed] FATAL:", e);
  process.exit(1);
});
