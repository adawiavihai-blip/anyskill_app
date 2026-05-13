// One-off seed script: creates 18 polished demo provider profiles across 6 CSMs.
//
//   פנסיון ביתי     × 3  (Pet boarding — categoryDetails only, no profile blob)
//   שליחויות        × 3  (Delivery CSM   — deliveryProfile)
//   ניקיון הבית     × 3  (Cleaning CSM   — cleaningProfile)
//   הנדימן          × 3  (Handyman CSM   — handymanProfile)
//   מאמני כושר      × 3  (Fitness CSM    — fitnessTrainerProfile)
//   בייביסיטר       × 3  (Babysitter CSM — babysitterProfile)
//
// Mirrors what AdminDemoExpertsTab._save would write — see CLAUDE.md §4.7
// (demo expert profiles) + §32 / §33 / §34 / §41 / §44 / §53 (CSMs).
//
// Each demo gets:
//   users/{uid}                  — full profile (isDemo:true, isVerified:true, isOnline:true)
//   provider_listings/demo_{uid} — search-discoverable listing (same payload)
//   reviews/*                    — 3-4 reviews per expert (isDemo:true)
//
// Idempotent — re-running upserts the SAME UIDs (deterministic ids like
// `demo_handyman_1`) so the script can be re-run safely without creating
// duplicates. Reviews are wiped & re-written each run (so demo profile updates
// don't stack stale reviews).
//
// Pest control (הדברה) and motorcycle towing (גרר אופנועים) are NOT seeded here:
//   • motorcycle towing — covered by seed-motorcycle-tow-demos.js (CLAUDE.md §55)
//   • pest control      — 3 admin-created demos already exist (manual UI)
//
// Run:
//   cd functions
//   node scripts/seed-csm-demos.js
//
// Dry-run:
//   node scripts/seed-csm-demos.js --dry-run

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

// ── Shared working-hours templates ────────────────────────────────────────
const WH_BUSINESS = {
  "0": { from: "08:00", to: "19:00" },
  "1": { from: "08:00", to: "19:00" },
  "2": { from: "08:00", to: "19:00" },
  "3": { from: "08:00", to: "19:00" },
  "4": { from: "08:00", to: "19:00" },
  "5": { from: "08:00", to: "14:00" },
};
const WH_EXTENDED = {
  "0": { from: "07:00", to: "22:00" },
  "1": { from: "07:00", to: "22:00" },
  "2": { from: "07:00", to: "22:00" },
  "3": { from: "07:00", to: "22:00" },
  "4": { from: "07:00", to: "22:00" },
  "5": { from: "07:00", to: "15:00" },
  "6": { from: "20:00", to: "23:00" },
};
const WH_24_7 = {
  "0": { from: "00:00", to: "23:59" },
  "1": { from: "00:00", to: "23:59" },
  "2": { from: "00:00", to: "23:59" },
  "3": { from: "00:00", to: "23:59" },
  "4": { from: "00:00", to: "23:59" },
  "5": { from: "06:00", to: "16:00" },
  "6": { from: "21:00", to: "23:59" },
};
const WH_EVENINGS = {
  "0": { from: "16:00", to: "23:00" },
  "1": { from: "16:00", to: "23:00" },
  "2": { from: "16:00", to: "23:00" },
  "3": { from: "16:00", to: "23:00" },
  "4": { from: "12:00", to: "23:00" },
  "5": { from: "10:00", to: "14:00" },
  "6": { from: "20:00", to: "23:59" },
};
const WH_FAMILY = {
  "0": { from: "09:00", to: "21:00" },
  "1": { from: "09:00", to: "21:00" },
  "2": { from: "09:00", to: "21:00" },
  "3": { from: "09:00", to: "21:00" },
  "4": { from: "09:00", to: "16:00" },
  "6": { from: "20:00", to: "23:30" },
};

// ═══════════════════════════════════════════════════════════════════════════
// 1. פנסיון ביתי (Pet Boarding) — 3 demos
//    No CSM profile blob; provider just sets serviceType + categoryDetails
//    (per CLAUDE.md §3b dynamic schema). Daily-proof flag lives on the
//    CATEGORY schema, not the user. Gallery and bio do the heavy lifting.
// ═══════════════════════════════════════════════════════════════════════════
const PET_BOARDING = {
  serviceType: "פנסיון ביתי",
  parentCategory: "בעלי חיים",
  demos: [
    {
      uid: "demo_pet_boarding_1",
      name: "מעיין דרור — פנסיון ביתי על שפת הירקון",
      phone: "050-2233101",
      email: "maayan.pet.boarding.demo@anyskill.app",
      aboutMe:
        "אוהבת חיות בכל הלב — מארחת כלבים בביתי כבר 8 שנים. הבית כולל חצר מגודרת " +
        "של 120 מ״ר, גן ירוק ויציאה ישירה לטיילת הירקון לטיולים יומיים. תמונה + " +
        "וידאו יומי לבעלים, וטרינר אישי בקריאה, ואני ישנה איתם בסלון אם הם פוחדים. " +
        "מארחת עד 4 כלבים במקביל (רק אם הם מסתדרים יחד) — כל אחד מקבל יחס אישי. " +
        "ניסיון רב עם גזעים גדולים, מבוגרים ועם צרכים מיוחדים.",
      profileImage:
        "https://images.unsplash.com/photo-1551717743-49959800b1f6?w=400&h=400&fit=crop&q=80",
      gallery: [
        "https://images.unsplash.com/photo-1601758228041-f3b2795255f1?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1583337130417-3346a1be7dee?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1518717758536-85ae29035b6d?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1587300003388-59208cc962cb?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1546182990-dffeafbe841d?w=800&h=600&fit=crop&q=80",
      ],
      completedJobs: 312,
      pricePerHour: 180,
      workingHours: WH_24_7,
      quickTags: ["fast_response", "reliable", "experienced", "home_visit"],
      isTopRated: true,
      categoryDetails: {
        pricePerNight: 180,
        hasFencedYard: true,
        sleepsWithDog: true,
        homeType: "בית פרטי עם חצר",
        maxDogsAtSameTime: 4,
        acceptsLargeBreeds: true,
        dailyWalksCount: 3,
        dailyPhotos: true,
        dailyVideo: true,
        emergencyVet: true,
      },
      reviews: [
        {
          reviewerName: "ענת ויסברגר",
          rating: 5,
          comment:
            "השארתי את הריקה (קוקר 9 שנים) ל-10 ימים. כל יום קיבלתי תמונה ועדכון, " +
            "ולפעמים גם וידאו של טיול. מעיין באמת מבינה כלבים — נסעתי בלי דאגה.",
          daysAgo: 5,
        },
        {
          reviewerName: "שיר אילון",
          rating: 5,
          comment:
            "החצר אדירה והכלבה שלי (לברדור) חזרה רגועה ושמחה. הם ישנים יחד על המיטה. " +
            "מומלץ למי שמחפש בית, לא כלוב.",
          daysAgo: 14,
        },
        {
          reviewerName: "אורן גמליאל",
          rating: 5,
          comment:
            "כלבי הסיביר חוסקי שלי דורש המון פעילות. מעיין עשתה לו 3 טיולים ביום בירקון. " +
            "חזר בשיא הכושר. תודה!",
          daysAgo: 22,
        },
        {
          reviewerName: "ליאת בר-לב",
          rating: 5,
          comment:
            "הכלב שלי עם תרופות יומיות. מעיין נתנה אותן בדיוק בזמן, שלחה לי וידאו של זה, " +
            "ומסרה לי דוח רפואי מלא בסוף השהות.",
          daysAgo: 35,
        },
      ],
    },
    {
      uid: "demo_pet_boarding_2",
      name: "ניצן ועידן — פנסיון משפחתי בכפר סבא",
      phone: "052-4455202",
      email: "nitzan.idan.pet.demo@anyskill.app",
      aboutMe:
        "זוג חובבי כלבים + 2 ילדים קטנים = הבית שלנו הכי חי שיש. מארחים כלבים " +
        "בייתיים כבר 5 שנים, בעיקר כלבים קטנים-בינוניים שאוהבים אנרגיית משפחה. " +
        "בית פרטי בכפר סבא עם גינה מגודרת, מטעים סביב להליכות בוקר, ושכנים שמכירים " +
        "כל הכלבים. תמונה יומית, וידאו, וטרינר 2 דקות נסיעה. מוגבל לכלב אחד בו זמנית " +
        "כדי לתת לו יחס מלא — מבוקש מראש.",
      profileImage:
        "https://images.unsplash.com/photo-1450778869180-41d0601e046e?w=400&h=400&fit=crop&q=80",
      gallery: [
        "https://images.unsplash.com/photo-1583512603805-3cc6b41f3edb?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1591608971362-f08b2a75731a?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1561037404-61cd46aa615b?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1535930891776-0c2dfb7fda1a?w=800&h=600&fit=crop&q=80",
      ],
      completedJobs: 168,
      pricePerHour: 150,
      workingHours: WH_EXTENDED,
      quickTags: ["family_friendly", "patient", "experienced"],
      isTopRated: false,
      categoryDetails: {
        pricePerNight: 150,
        hasFencedYard: true,
        sleepsWithDog: false,
        homeType: "בית פרטי משפחתי",
        maxDogsAtSameTime: 1,
        acceptsLargeBreeds: false,
        dailyWalksCount: 2,
        dailyPhotos: true,
        dailyVideo: true,
        emergencyVet: true,
      },
      reviews: [
        {
          reviewerName: "תמר ארליך",
          rating: 5,
          comment:
            "מילה: ניצן ועידן הם משפחה לכלב שלי. בלי טיפת לחץ, רק אהבה. " +
            "הילדים שלהם משחקים עם בלאקי כל הזמן והוא חזר אלינו עם חיוך.",
          daysAgo: 6,
        },
        {
          reviewerName: "אופיר שלם",
          rating: 5,
          comment:
            "הכלבה שלי שייט-זו קטנה ופחדנית. הם הצליחו להוציא ממנה אנרגיה שלא ידעתי שיש לה. " +
            "תמונות יומיות, וידאו של טיולים. אצלם יותר טוב מבבית.",
          daysAgo: 11,
        },
        {
          reviewerName: "יערה מן",
          rating: 4,
          comment:
            "שירות מקצועי, מחיר הוגן, ובית חמים. הסתייגות קטנה — קצת מרוחק מהמרכז " +
            "אבל זה גם היתרון של מקום שקט.",
          daysAgo: 27,
        },
      ],
    },
    {
      uid: "demo_pet_boarding_3",
      name: "ד״ר רן שביט — פנסיון וטרינרי בית פרטי",
      phone: "054-7788303",
      email: "ran.vet.pet.demo@anyskill.app",
      aboutMe:
        "וטרינר במקצועי + מארח פנסיון ביתי לכלבים עם צרכים רפואיים. הבית מותאם " +
        "לטיפול בכלבים בריאים וגם בכאלה שצריכים תרופות יומיות, אינסולין, פיזיותרפיה " +
        "אחרי ניתוח או השגחה אחרי טיפול. מצלמות 24/7 שאתם רואים בלייב, חדר וטרינרי " +
        "מצויד בבית, וקשר ישיר עם הוטרינר שלכם. מתאים במיוחד לכלבים מבוגרים, " +
        "כלבים עם הפרעות התנהגות, או אחרי ניתוח. מחיר גבוה — אבל קיבלים שירות וטרינרי מלא.",
      profileImage:
        "https://images.unsplash.com/photo-1576091160550-2173dba999ef?w=400&h=400&fit=crop&q=80",
      gallery: [
        "https://images.unsplash.com/photo-1583337426008-2fef51aa841a?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1444212477490-ca407925329e?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1583511666445-7f6db9d4be8e?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1517849845537-4d257902454a?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1593134257782-e89567b7718a?w=800&h=600&fit=crop&q=80",
      ],
      completedJobs: 89,
      pricePerHour: 280,
      workingHours: WH_24_7,
      quickTags: ["professional", "specialist", "vet_care", "24_7"],
      isTopRated: true,
      categoryDetails: {
        pricePerNight: 280,
        hasFencedYard: true,
        sleepsWithDog: true,
        homeType: "בית עם חדר וטרינרי מצויד",
        maxDogsAtSameTime: 2,
        acceptsLargeBreeds: true,
        dailyWalksCount: 4,
        dailyPhotos: true,
        dailyVideo: true,
        emergencyVet: true,
        medicalSupervision: true,
        livestreamAccess: true,
      },
      reviews: [
        {
          reviewerName: "אלון רוזנפלד",
          rating: 5,
          comment:
            "כלב 14 עם סוכרת. ד״ר רן נתן אינסולין פעמיים ביום, מדד גלוקוז, ושלח לי " +
            "דוח מפורט. נדיר למצוא וטרינר שגם מארח. שווה כל אגורה.",
          daysAgo: 8,
        },
        {
          reviewerName: "סיון ארמון",
          rating: 5,
          comment:
            "אחרי ניתוח עצם של הכלב היה לי חששות גדולים להשאיר אותו. ד״ר רן ידע בדיוק " +
            "מה לעשות. המצלמות בלייב הם משחק מחליף — צפיתי ברגיעה.",
          daysAgo: 19,
        },
        {
          reviewerName: "אילן זוהר",
          rating: 5,
          comment:
            "כלבה מבוגרת עם דמנציה. ד״ר רן ידע לתת לה תרופות עם אוכל, ולא להלחיץ אותה. " +
            "מקצוען אמיתי.",
          daysAgo: 31,
        },
      ],
    },
  ],
};

// ═══════════════════════════════════════════════════════════════════════════
// 2. שליחויות (Delivery CSM) — 3 demos
//    Requires deliveryProfile with vehicles + deliveryTypes + pricing + rules.
//    Per save condition: deliveryProfile.vehicles MUST be non-empty.
// ═══════════════════════════════════════════════════════════════════════════
const DELIVERY = {
  serviceType: "שליחויות",
  parentCategory: "תחבורה",
  demos: [
    {
      uid: "demo_delivery_1",
      name: "אדם מוסקוביץ — שליחויות מהירות בגוש דן",
      phone: "050-3344155",
      email: "adam.delivery.demo@anyskill.app",
      aboutMe:
        "5 שנות ניסיון בשליחויות — מתמחה במשלוחי דחיפות בגוש דן. קטנוע חדש (Yamaha NMAX " +
        "2023), קסדה + תיק חום-קור. ידוע בהגעה מהירה (ממוצע 12 דקות לדחיפות), " +
        "וצילום הוכחת מסירה לכל משלוח. עובד עם עסקים, רוקחויות, ופרטיים. שעות פעילות " +
        "07:00-22:00 כל יום, ו-לילה לפי בקשה. מחיר הוגן ומחירון שקוף.",
      profileImage:
        "https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=400&h=400&fit=crop&q=80",
      gallery: [
        "https://images.unsplash.com/photo-1605164599901-db7f68c4b8c5?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1556742502-ec7c0e9f34b1?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1568349565531-3b1c1f969f9e?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1517363898874-737b62905f02?w=800&h=600&fit=crop&q=80",
      ],
      completedJobs: 1240,
      pricePerHour: 45,
      workingHours: WH_EXTENDED,
      quickTags: ["fast_response", "reliable", "tech_savvy"],
      isTopRated: true,
      deliveryProfile: {
        documents: [
          { id: "id_card", type: "id_card", nameHe: "תעודת זהות", verified: true },
          {
            id: "drv_license",
            type: "driver_license",
            nameHe: "רישיון נהיגה",
            verified: true,
            classes: ["A2"],
          },
        ],
        vehicles: [
          {
            id: "v_scooter",
            type: "scooter",
            nameHe: "Yamaha NMAX",
            manufacturer: "Yamaha",
            year: 2023,
            maxWeightKg: 30,
            photos: [],
            insuranceVerified: true,
            enabled: true,
          },
        ],
        deliveryTypes: [
          "documents",
          "small_package",
          "medium_package",
          "flowers",
        ],
        customerTypes: ["private", "business"],
        availability: {
          immediate: { enabled: true, surcharge: 25 },
          regular: { enabled: true },
          scheduled: { enabled: true },
        },
        serviceArea: {
          baseLocation: "תל אביב — פלורנטין",
          baseLocationGeo: { lat: 32.0566, lng: 34.7682 },
          coverageCities: [
            "תל אביב",
            "רמת גן",
            "גבעתיים",
            "בני ברק",
            "הרצליה",
            "פתח תקווה",
          ],
        },
        pricing: {
          documents: 35,
          small_package: 45,
          medium_package: 65,
          large_package: 0, // not offered
          flowers: 55,
          cakes: 0,
          perKmAfter5: 3.5,
        },
        rules: {
          structuredRules: [
            {
              id: "no_dangerous",
              type: "no_dangerous",
              icon: "⚠️",
              titleHe: "ללא חומרים מסוכנים",
              descHe: "אין משלוח דלק, סמים, כלי ירייה או חומרים בעירה",
              enabled: true,
              color: "red",
            },
            {
              id: "photo_proof",
              type: "photo_documentation",
              icon: "📸",
              titleHe: "צילום הוכחת מסירה",
              descHe: "כל משלוח מסתיים בתמונה של החבילה בנקודת המסירה",
              enabled: true,
              color: "blue",
            },
            {
              id: "call_before",
              type: "call_before_arrival",
              icon: "📞",
              titleHe: "התקשרות לפני הגעה",
              descHe: "מתקשר 2-3 דקות לפני להבטיח שתוכל לקבל",
              enabled: true,
              color: "green",
            },
          ],
          customRules:
            "במשלוח דחוף — תשלום בשליחה דרך האפליקציה בלבד. אין מזומן.",
        },
        businessPackages: [
          {
            id: "biz_50",
            nameHe: "📦 חבילה עסקית — 50 משלוחים/חודש",
            deliveriesPerMonth: 50,
            monthlyPrice: 1800,
            enabled: true,
            activeCustomers: 4,
          },
        ],
      },
      reviews: [
        {
          reviewerName: "רותם פלד",
          rating: 5,
          comment:
            "התקשרתי ב-21:30 בלילה. אדם הגיע ב-21:48. שירות מטורף. תמונה של החבילה " +
            "אצל השומר תוך 3 דקות. מהיום הוא השליח הקבוע שלי.",
          daysAgo: 3,
        },
        {
          reviewerName: "בועז שלוש",
          rating: 5,
          comment:
            "מנהל מסעדה קטנה — אדם הוא השליח החיצוני שלנו לעוגות יום הולדת. " +
            "אף עוגה לא הגיעה פגומה. מקצוען.",
          daysAgo: 9,
        },
        {
          reviewerName: "דנה הופמן",
          rating: 5,
          comment:
            "שלחתי מסמכים משפטיים דחופים מתל אביב לרמת גן. הגיע ב-15 דקות. " +
            "צילם את ההתקשרות, פסיכון לי. מעולה.",
          daysAgo: 16,
        },
        {
          reviewerName: "אסף הראל",
          rating: 4,
          comment:
            "טוב מאוד באזור פלורנטין/יפו, מנסה לחזור אליי כשמתחיל פקק בכניסה לעיר. " +
            "מחיר הוגן, אדם נחמד.",
          daysAgo: 24,
        },
      ],
    },
    {
      uid: "demo_delivery_2",
      name: "רינת בן-חמו — שליחויות עדינות (פרחים + עוגות)",
      phone: "052-5566255",
      email: "rinat.delivery.demo@anyskill.app",
      aboutMe:
        "מתמחה ב-משלוחים עדינים: פרחים, עוגות מעוצבות, ועוגיות. רכב Volkswagen Caddy " +
        "עם מקרר נייד לעוגות שמנת. אישה — נעימה ללקוחות שמקבלים מתנות הפתעה. צלם " +
        "תמונה של הלקוח אם מסכים. עובדת בעיקר עם פרחי בוטיק, מאפיות מעוצבות, " +
        "וחנויות שוקולד.",
      profileImage:
        "https://images.unsplash.com/photo-1593104547489-5cfb3839a3b5?w=400&h=400&fit=crop&q=80",
      gallery: [
        "https://images.unsplash.com/photo-1490312278390-ab64016e0aa9?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1558636508-e0db3814bd1d?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1546412414-e1885259563a?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1486797368629-c11e7eb44309?w=800&h=600&fit=crop&q=80",
      ],
      completedJobs: 412,
      pricePerHour: 60,
      workingHours: WH_BUSINESS,
      quickTags: ["specialist", "reliable", "fair_price"],
      isTopRated: true,
      deliveryProfile: {
        documents: [
          { id: "id_card", type: "id_card", nameHe: "תעודת זהות", verified: true },
          {
            id: "drv_license",
            type: "driver_license",
            nameHe: "רישיון נהיגה",
            verified: true,
            classes: ["B"],
          },
        ],
        vehicles: [
          {
            id: "v_car",
            type: "car",
            nameHe: "Volkswagen Caddy",
            manufacturer: "Volkswagen",
            year: 2021,
            maxWeightKg: 80,
            photos: [],
            insuranceVerified: true,
            enabled: true,
          },
        ],
        deliveryTypes: [
          "flowers",
          "cakes",
          "small_package",
          "medium_package",
        ],
        customerTypes: ["private", "business", "stores"],
        availability: {
          immediate: { enabled: true, surcharge: 35 },
          regular: { enabled: true },
          scheduled: { enabled: true },
        },
        serviceArea: {
          baseLocation: "הרצליה — מרכז",
          baseLocationGeo: { lat: 32.1624, lng: 34.8442 },
          coverageCities: [
            "הרצליה",
            "תל אביב",
            "רעננה",
            "כפר סבא",
            "רמת השרון",
            "הוד השרון",
          ],
        },
        pricing: {
          documents: 0,
          small_package: 55,
          medium_package: 75,
          large_package: 0,
          flowers: 60,
          cakes: 70,
          perKmAfter5: 4,
        },
        rules: {
          structuredRules: [
            {
              id: "photo_proof",
              type: "photo_documentation",
              icon: "📸",
              titleHe: "תמונת מסירה עם הנמען",
              descHe: "אם הנמען רוצה — צילום שלו עם הזר/העוגה",
              enabled: true,
              color: "blue",
            },
            {
              id: "weight_check",
              type: "weight_verification",
              icon: "⚖️",
              titleHe: "אימות משקל לפני יציאה",
              descHe: "שוקלת כל חבילה לפני יציאה כדי לוודא תעריף נכון",
              enabled: true,
              color: "amber",
            },
          ],
          customRules:
            "עוגות שמנת — בשיתוף פעולה עם החנות. הנמען חייב להיות בבית בזמן ההגעה.",
        },
        businessPackages: [],
      },
      reviews: [
        {
          reviewerName: "טל חזן",
          rating: 5,
          comment:
            "שלחתי לאמא שלי זר ביום ההולדת. רינת התקשרה אליה בנימוס, חיכתה שתפתח, " +
            "צילמה את הרגע. אמא שלי בכתה. תודה רינת.",
          daysAgo: 4,
        },
        {
          reviewerName: "מאיה אדלר",
          rating: 5,
          comment:
            "אנחנו חנות פרחים — רינת היא השליחה הקבועה שלנו לזרים מורכבים. " +
            "אף זר לא הגיע שבור. מקצוענית אמיתית.",
          daysAgo: 12,
        },
        {
          reviewerName: "אלונה רוזן",
          rating: 5,
          comment:
            "עוגת חתונה — לחץ קטן. רינת היה שלווה כמו שיש, הגיעה דקות לפני שביקשתי, " +
            "ושמרה על הקרם בקירור.",
          daysAgo: 25,
        },
      ],
    },
    {
      uid: "demo_delivery_3",
      name: "מוטי כהן — שליחויות B2B + ציי שליחים",
      phone: "054-6677355",
      email: "moti.delivery.demo@anyskill.app",
      aboutMe:
        "12 שנים בשליחויות B2B. מנהל צי קטן (3 קטנועים + רכב), אבל אני מסיע בעצמי " +
        "את הקריאות הגדולות. שירות עיקרי לעורכי דין, רואי חשבון, ומשרדים — חוזי " +
        "שירות חודשיים עם מחיר מוזל פר משלוח. ידוע באמינות יוצאת דופן — לא איחרתי " +
        "מעולם, ושמירה מוחלטת על דיסקרטיות במסמכים רגישים. מחירון פתוח, חשבונית מס לכל לקוח.",
      profileImage:
        "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&h=400&fit=crop&q=80",
      gallery: [
        "https://images.unsplash.com/photo-1556761175-5973dc0f32e7?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1605147376116-bba9a5e2c2ed?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1568349565531-3b1c1f969f9e?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1601758124510-52d02ddb7cbd?w=800&h=600&fit=crop&q=80",
      ],
      completedJobs: 2310,
      pricePerHour: 50,
      workingHours: WH_BUSINESS,
      quickTags: ["fleet_service", "reliable", "professional"],
      isTopRated: true,
      deliveryProfile: {
        documents: [
          { id: "id_card", type: "id_card", nameHe: "תעודת זהות", verified: true },
          {
            id: "drv_license",
            type: "driver_license",
            nameHe: "רישיון נהיגה",
            verified: true,
            classes: ["B", "A2"],
          },
        ],
        vehicles: [
          {
            id: "v_scooter",
            type: "scooter",
            nameHe: "Honda Forza 350",
            manufacturer: "Honda",
            year: 2022,
            maxWeightKg: 35,
            photos: [],
            insuranceVerified: true,
            enabled: true,
          },
          {
            id: "v_car",
            type: "car",
            nameHe: "Hyundai Staria Van",
            manufacturer: "Hyundai",
            year: 2023,
            maxWeightKg: 120,
            photos: [],
            insuranceVerified: true,
            enabled: true,
          },
        ],
        deliveryTypes: [
          "documents",
          "small_package",
          "medium_package",
          "large_package",
        ],
        customerTypes: ["business"],
        availability: {
          immediate: { enabled: true, surcharge: 30 },
          regular: { enabled: true },
          scheduled: { enabled: true },
        },
        serviceArea: {
          baseLocation: "פתח תקווה — אזור התעשייה הצפוני",
          baseLocationGeo: { lat: 32.0876, lng: 34.8855 },
          coverageCities: [
            "פתח תקווה",
            "תל אביב",
            "ראשון לציון",
            "רמת גן",
            "גבעתיים",
            "בני ברק",
            "חולון",
            "בת ים",
            "רחובות",
          ],
        },
        pricing: {
          documents: 30,
          small_package: 40,
          medium_package: 60,
          large_package: 95,
          flowers: 0,
          cakes: 0,
          perKmAfter5: 3,
        },
        rules: {
          structuredRules: [
            {
              id: "signature_required",
              type: "signature_required",
              icon: "✍️",
              titleHe: "חתימה מהנמען",
              descHe: "מסמכים משפטיים — חתימה דיגיטלית מהנמען",
              enabled: true,
              color: "indigo",
            },
            {
              id: "no_dangerous",
              type: "no_dangerous",
              icon: "⚠️",
              titleHe: "ללא חומרים מסוכנים",
              descHe: "אין משלוח כימיקלים, דלק או חומרי בעירה",
              enabled: true,
              color: "red",
            },
          ],
          customRules:
            "חוזי שירות חודשיים — חשבונית מס פלוס. דיווח חודשי עם פירוט כל המשלוחים.",
        },
        businessPackages: [
          {
            id: "biz_100",
            nameHe: "🏢 חוזה משרד — 100 משלוחים/חודש",
            deliveriesPerMonth: 100,
            monthlyPrice: 3200,
            enabled: true,
            activeCustomers: 12,
          },
          {
            id: "biz_250",
            nameHe: "🚀 חוזה ארגון — 250 משלוחים/חודש",
            deliveriesPerMonth: 250,
            monthlyPrice: 7500,
            enabled: true,
            activeCustomers: 3,
          },
        ],
      },
      reviews: [
        {
          reviewerName: 'עו"ד יואב פרידמן',
          rating: 5,
          comment:
            "המשרד שלנו עובד עם מוטי 4 שנים. הוא יודע איך לבית של כל לקוח, איך " +
            "להגיע בלי לחנות באיסור, ולא מאחר אף פעם. לא בטוח מי יכול להחליף אותו.",
          daysAgo: 7,
        },
        {
          reviewerName: "דליה ארמוני, רואת חשבון",
          rating: 5,
          comment:
            "דוחות שנתיים, אבטחה מוחלטת. מוטי הוא חלק מהמשרד שלי בכל מובן.",
          daysAgo: 15,
        },
        {
          reviewerName: "ישראל לויטס",
          rating: 5,
          comment:
            "ניהול מסעדה — מוטי לוקח אצלי משלוחים גדולים לסניפים. תעריף B2B אצלו הכי הוגן בשוק.",
          daysAgo: 26,
        },
        {
          reviewerName: "מאי אלמוג",
          rating: 4,
          comment:
            "מצוין לעסקים — לפעמים אני שולחת כפרטית, ושם זה קצת פחות זמין. אבל ב-B2B אין מתחרה.",
          daysAgo: 40,
        },
      ],
    },
  ],
};

// ═══════════════════════════════════════════════════════════════════════════
// 3. ניקיון הבית (Cleaning CSM) — 3 demos
//    Requires cleaningProfile with cleaningTypes non-empty.
// ═══════════════════════════════════════════════════════════════════════════
const DEFAULT_CLEANING_CHECKLIST = [
  {
    categoryId: "bedroom",
    categoryNameHe: "חדר שינה",
    categoryIcon: "🛏️",
    tasks: [
      { id: "bedroom_1", nameHe: "החלפת מצעים + סידור מיטה", withPhoto: true },
      { id: "bedroom_2", nameHe: "שאיבת אבק + ניגוב משטחים", withPhoto: false },
      { id: "bedroom_3", nameHe: "חלונות פנימיים", withPhoto: false },
    ],
  },
  {
    categoryId: "bathroom",
    categoryNameHe: "חדר אמבטיה",
    categoryIcon: "🚿",
    tasks: [
      {
        id: "bathroom_1",
        nameHe: "ניקוי מקלחת + אסלה לעומק",
        withPhoto: true,
      },
      { id: "bathroom_2", nameHe: "הסרת אבנית מברזים", withPhoto: false },
    ],
  },
  {
    categoryId: "kitchen",
    categoryNameHe: "מטבח",
    categoryIcon: "🍽️",
    tasks: [
      { id: "kitchen_1", nameHe: "משטחי עבודה + כיורים", withPhoto: false },
      {
        id: "kitchen_2",
        nameHe: "ניקוי תנור פנימי",
        withPhoto: false,
        addOn: { amount: 40, currency: "ILS" },
      },
    ],
  },
  {
    categoryId: "living_room",
    categoryNameHe: "סלון",
    categoryIcon: "🛋️",
    tasks: [
      { id: "living_1", nameHe: "שאיבת ספות + שטיחים", withPhoto: true },
      { id: "living_2", nameHe: "ניגוב משטחים + טלוויזיה", withPhoto: false },
    ],
  },
];

const DEFAULT_CLEANING_PRICING = {
  regular_home: {
    upTo60sqm: 180,
    "60to100sqm": 240,
    "100to150sqm": 320,
    over150sqm: 420,
  },
  typeMultipliers: {
    regular_home: 1.0,
    deep_renovation: 2.0,
    airbnb: 0.8,
    office: 1.5,
    store: 1.3,
    event: 1.7,
  },
  addOns: {
    oven_inside: 40,
    fridge_inside: 30,
    windows_outside: 60,
    sofa_steam: 120,
  },
};

const CLEANING = {
  serviceType: "ניקיון הבית",
  parentCategory: "שירותי בית",
  demos: [
    {
      uid: "demo_cleaning_1",
      name: "סבטלנה איבנובה — ניקיון לעומק לבית",
      phone: "050-4477122",
      email: "svetlana.cleaning.demo@anyskill.app",
      aboutMe:
        "10 שנים בענף הניקיון בישראל, מתמחה בניקיונות עומק לבתים פרטיים ודירות לאחר שיפוץ. " +
        "תעודת זהות מאומתת, ביקורת רקע פלילית נקייה, ו-12 לקוחות קבועים שיכולים להמליץ. " +
        "מביאה את כל הציוד והחומרים — אקולוגיים מבית EcoCert. עובדת בשעות הבוקר בלבד " +
        "(07:00-15:00) ומחויבת לתוצאה — אחרי שאני עוזבת, הבית מבריק.",
      profileImage:
        "https://images.unsplash.com/photo-1581578731548-c64695cc6952?w=400&h=400&fit=crop&q=80",
      gallery: [
        "https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1527515637462-cff94eecc1ac?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1584622650111-993a426fbf0a?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1583947582886-f40ec95dd752?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1599982888793-3a17b29df84f?w=800&h=600&fit=crop&q=80",
      ],
      completedJobs: 487,
      pricePerHour: 80,
      workingHours: {
        "0": { from: "07:00", to: "15:00" },
        "1": { from: "07:00", to: "15:00" },
        "2": { from: "07:00", to: "15:00" },
        "3": { from: "07:00", to: "15:00" },
        "4": { from: "07:00", to: "15:00" },
      },
      quickTags: ["experienced", "reliable", "professional"],
      isTopRated: true,
      cleaningProfile: {
        verifications: {
          idVerified: true,
          backgroundChecked: true,
          referencesCount: 12,
          referencesVerified: true,
          insuranceAmount: 50000,
          insuranceProvider: "מגדל ביטוח",
          insuranceValidUntil: "2026-12-31",
        },
        cleaningTypes: ["regular_home", "deep_renovation", "airbnb"],
        customerTypes: ["private", "stores"],
        ecoMode: { enabled: true, surcharge: 25, certified: "EcoCert" },
        baseChecklist: DEFAULT_CLEANING_CHECKLIST,
        pricing: DEFAULT_CLEANING_PRICING,
        recurringDiscounts: { weekly: 18, biweekly: 12, monthly: 6 },
        qualityGuarantee: {
          enabled: true,
          reportWindowHours: 24,
          reCleanFree: true,
          fullRefund: true,
        },
        serviceArea: {
          cities: ["תל אביב", "רמת גן", "גבעתיים", "הרצליה", "רעננה"],
          workHours: {
            morning_7_12: true,
            afternoon_12_17: true,
            evening_17_22: false,
            weekend: false,
          },
        },
        businessPackages: [],
      },
      reviews: [
        {
          reviewerName: "אורית בן-יוסף",
          rating: 5,
          comment:
            "סבטלנה ניקתה אצלי דירה אחרי שיפוץ. אבק היה בכל מקום — היא הוציאה את הכל " +
            "ביום אחד. רואים שיש לה ניסיון. תעריף הוגן ועבודה מקצועית.",
          daysAgo: 6,
        },
        {
          reviewerName: "אמית כרמלי",
          rating: 5,
          comment:
            "ניקיון שבועי קבוע 6 חודשים — הבית תמיד נראה אותו דבר טוב כשאני חוזרת. " +
            "סבטלנה אחראית, לא מאחרת, ומתייחסת לבית כמו לשלה.",
          daysAgo: 13,
        },
        {
          reviewerName: "רוני שפירא",
          rating: 5,
          comment:
            "חומרים אקולוגיים זה חשוב לי בגלל ילדים קטנים. סבטלנה הגיעה עם מותג EcoCert " +
            "מאושר. הבית מבריק וגם בריא.",
          daysAgo: 21,
        },
      ],
    },
    {
      uid: "demo_cleaning_2",
      name: 'חברת "בית נקי" — צוות ניקיון לדירות גדולות',
      phone: "052-8899233",
      email: "bait.naki.cleaning.demo@anyskill.app",
      aboutMe:
        "חברה משפחתית — אם, אבא, ו-2 בנים בוגרים. מתמחים בדירות מעל 120 מ״ר ובתים פרטיים. " +
        "צוות של 3-4 אנשים מגיע יחד, מסיים דירה רגילה ב-2.5 שעות. ביטוח חבות 100,000₪ " +
        "מצרפים לכל עבודה. מקבלים גם משכירים שזקוקים לניקוי בין דיירים, ו-AirBnB-קים.",
      profileImage:
        "https://images.unsplash.com/photo-1521791136064-7986c2920216?w=400&h=400&fit=crop&q=80",
      gallery: [
        "https://images.unsplash.com/photo-1581578017093-cd30fce4eeb7?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1607619056574-7b8d3ee536b2?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1558317374-067fb5f30001?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1581539250439-c96689b516dd?w=800&h=600&fit=crop&q=80",
      ],
      completedJobs: 1280,
      pricePerHour: 110,
      workingHours: WH_BUSINESS,
      quickTags: ["fleet_service", "experienced", "fair_price"],
      isTopRated: true,
      cleaningProfile: {
        verifications: {
          idVerified: true,
          backgroundChecked: true,
          referencesCount: 25,
          referencesVerified: true,
          insuranceAmount: 100000,
          insuranceProvider: "הראל ביטוח",
          insuranceValidUntil: "2026-11-30",
        },
        cleaningTypes: ["regular_home", "airbnb", "office", "store"],
        customerTypes: ["private", "business", "stores"],
        ecoMode: { enabled: false, surcharge: 25, certified: "EcoCert" },
        baseChecklist: DEFAULT_CLEANING_CHECKLIST,
        pricing: DEFAULT_CLEANING_PRICING,
        recurringDiscounts: { weekly: 15, biweekly: 10, monthly: 5 },
        qualityGuarantee: {
          enabled: true,
          reportWindowHours: 24,
          reCleanFree: true,
          fullRefund: false,
        },
        serviceArea: {
          cities: [
            "תל אביב",
            "רמת גן",
            "גבעתיים",
            "הרצליה",
            "פתח תקווה",
            "רעננה",
            "כפר סבא",
            "ראשון לציון",
          ],
          workHours: {
            morning_7_12: true,
            afternoon_12_17: true,
            evening_17_22: false,
            weekend: false,
          },
        },
        businessPackages: [
          {
            id: "biz_4x",
            nameHe: "📅 4 ביקורים/חודש",
            visitsPerMonth: 4,
            monthlyPrice: 1290,
            enabled: true,
            activeCustomers: 18,
          },
          {
            id: "biz_8x",
            nameHe: "🚀 8 ביקורים/חודש",
            visitsPerMonth: 8,
            monthlyPrice: 2380,
            enabled: true,
            activeCustomers: 6,
          },
        ],
      },
      reviews: [
        {
          reviewerName: "ענת רוטשילד",
          rating: 5,
          comment:
            "דירה 4 חדרים, צוות של 4 הגיעו, סיימו ב-2.5 שעות. הם רעננים, נחמדים, " +
            "ומקצועיים. השכן שלי שכר אותם אחרי שראה את הבית שלי.",
          daysAgo: 4,
        },
        {
          reviewerName: "יאיר חכמון",
          rating: 5,
          comment:
            "מנהל 3 דירות AirBnB. הצוות הזה הציל לי החיים. ניקוי בין דיירים תוך 90 דקות, " +
            "בלי לפספס פרט. המומלצים הקבועים שלי.",
          daysAgo: 11,
        },
        {
          reviewerName: "תמר אביב",
          rating: 4,
          comment:
            "מקצועיים ועובדים מהר. רק חבל שהם לא חוזרים מאוחר בערב — לפעמים זה כן צריך.",
          daysAgo: 19,
        },
        {
          reviewerName: "אופיר רובינשטיין",
          rating: 5,
          comment:
            "הזמנו ניקיון משרד 200 מ״ר אחרי אירוע. הם הגיעו עם ציוד מקצועי, " +
            "סיימו לפני שעת בוקר. שירות B2B אדיר.",
          daysAgo: 28,
        },
      ],
    },
    {
      uid: "demo_cleaning_3",
      name: "אופירה לוי — ניקיון אקולוגי לבתים עם ילדים",
      phone: "054-9911344",
      email: "ofira.eco.cleaning.demo@anyskill.app",
      aboutMe:
        "מתמחה בניקיון בתים עם ילדים קטנים — חומרים אקולוגיים בלבד, ללא ריחות חזקים, " +
        "ללא כימיקלים שמשאירים שאריות. תעודת EcoCert + אישור מי״צ. מתחילה תמיד באזורים " +
        "שילדים נוגעים בהם (סוכת, צעצועים, רצפת סלון). שעות הצהריים אחר הצהריים בלבד " +
        "(11:00-17:00) כדי לא להפריע לילדים בלילה. שפה משותפת עם הורים שאוהבים בית בריא.",
      profileImage:
        "https://images.unsplash.com/photo-1573497019418-b400bb3ab074?w=400&h=400&fit=crop&q=80",
      gallery: [
        "https://images.unsplash.com/photo-1584820927498-cfe5211fd8bf?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1527515673510-8aa116e2aa75?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1581578731548-c64695cc6952?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?w=800&h=600&fit=crop&q=80",
      ],
      completedJobs: 234,
      pricePerHour: 95,
      workingHours: {
        "0": { from: "11:00", to: "17:00" },
        "1": { from: "11:00", to: "17:00" },
        "2": { from: "11:00", to: "17:00" },
        "3": { from: "11:00", to: "17:00" },
        "4": { from: "11:00", to: "16:00" },
      },
      quickTags: ["family_friendly", "specialist", "eco_friendly"],
      isTopRated: true,
      cleaningProfile: {
        verifications: {
          idVerified: true,
          backgroundChecked: true,
          referencesCount: 8,
          referencesVerified: true,
          insuranceAmount: 25000,
          insuranceProvider: "ביטוח ישיר",
          insuranceValidUntil: "2027-03-15",
        },
        cleaningTypes: ["regular_home"],
        customerTypes: ["private"],
        ecoMode: { enabled: true, surcharge: 20, certified: "EcoCert" },
        baseChecklist: DEFAULT_CLEANING_CHECKLIST,
        pricing: {
          regular_home: {
            upTo60sqm: 220,
            "60to100sqm": 280,
            "100to150sqm": 360,
            over150sqm: 460,
          },
          typeMultipliers: DEFAULT_CLEANING_PRICING.typeMultipliers,
          addOns: { ...DEFAULT_CLEANING_PRICING.addOns, sofa_steam: 140 },
        },
        recurringDiscounts: { weekly: 20, biweekly: 12, monthly: 6 },
        qualityGuarantee: {
          enabled: true,
          reportWindowHours: 48,
          reCleanFree: true,
          fullRefund: true,
        },
        serviceArea: {
          cities: ["תל אביב", "רמת גן", "גבעתיים", "רמת השרון"],
          workHours: {
            morning_7_12: true,
            afternoon_12_17: true,
            evening_17_22: false,
            weekend: false,
          },
        },
        businessPackages: [],
      },
      reviews: [
        {
          reviewerName: "מיכל ארביב",
          rating: 5,
          comment:
            "אמא ל-2 ילדים, בני 3 ו-1. שכרתי את אופירה כדי שלא יהיה לי מצפון. " +
            "החומרים שלה אמיתיים — בלי ריח כימי. הילדים שלי לא מקטרים יותר.",
          daysAgo: 7,
        },
        {
          reviewerName: "לימור גרין",
          rating: 5,
          comment:
            "סובלת מאסטמה, וכל ריח חזק זה אסון. אופירה השתמשה רק בחומרים אקולוגיים " +
            "טבעיים — חזרתי הביתה ונשמתי לעומק. ראיתי שינוי באמת.",
          daysAgo: 16,
        },
        {
          reviewerName: "אורן יזרעאלי",
          rating: 5,
          comment:
            "בעל אישה הרה — חיפשנו ניקיון בלי כימיקלים. אופירה היה הבחירה הברורה. " +
            "מקצועית, אקולוגית, וגם נחמדה.",
          daysAgo: 24,
        },
      ],
    },
  ],
};

// ═══════════════════════════════════════════════════════════════════════════
// 4. הנדימן (Handyman CSM) — 3 demos
//    Requires handymanProfile with at least one active specialty.
// ═══════════════════════════════════════════════════════════════════════════
function activeSpecialty(id, nameHe, icon, basePrice, estimatedMinutes, yearCount, popularity) {
  return {
    id,
    nameHe,
    icon,
    active: true,
    yearCount,
    ...(popularity ? { popularity } : {}),
    basePrice,
    estimatedMinutes,
  };
}

const HANDYMAN = {
  serviceType: "הנדימן",
  parentCategory: "שירותי בית",
  demos: [
    {
      uid: "demo_handyman_1",
      name: "אבי שוסטר — הנדימן ותיק לכל הבית",
      phone: "050-5566144",
      email: "avi.handyman.demo@anyskill.app",
      aboutMe:
        "20 שנה בעבודות יד — תליית טלוויזיה, הרכבת רהיטים, אינסטלציה קלה, חשמל קל, " +
        "וצביעה. עובד עם כלים מקצועיים (Bosch + Makita) ומחירון שקוף. בא עם המכונית " +
        "מצוידת לכל יום. ידוע במהירות + ניקיון — לא משאיר אבק או צבע על הרצפה. " +
        "מבצע 3-4 משימות בקריאה אחת ב-50% הנחה דרך Punch List. ביטוח ערבות אישית, " +
        "וביקורת רקע פלילית נקייה — מאומתת ע״י AnySkill.",
      profileImage:
        "https://images.unsplash.com/photo-1530268729831-4b0b9e170218?w=400&h=400&fit=crop&q=80",
      gallery: [
        "https://images.unsplash.com/photo-1581094271901-8022df4466f9?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1574786500086-3afad5fafdb1?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1581244277943-fe4a9c777189?w=800&h=600&fit=crop&q=80",
      ],
      completedJobs: 1820,
      pricePerHour: 150,
      workingHours: WH_EXTENDED,
      quickTags: ["experienced", "fast_response", "reliable", "fair_price"],
      isTopRated: true,
      handymanProfile: {
        verifications: {
          backgroundCheck: {
            verified: true,
            verifiedAt: Timestamp.fromDate(new Date(Date.now() - 90 * 24 * 60 * 60 * 1000)),
          },
          warrantyEnabled: true,
        },
        specialties: [
          activeSpecialty("tv_mounting", "תליית טלוויזיה", "📺", 180, 60, 20, "hot"),
          activeSpecialty("furniture_assembly", "הרכבת רהיטים", "🪑", 220, 120, 20, "hot"),
          activeSpecialty("plumbing_fix", "אינסטלציה קלה", "🚿", 140, 90, 18, "urgent"),
          activeSpecialty("electrical_minor", "חשמל קל", "💡", 150, 60, 15, "urgent"),
          activeSpecialty("painting", "צביעה", "🎨", 200, 180, 20),
          activeSpecialty("drywall", "גבס", "🔨", 95, 30, 18),
          activeSpecialty("doors", "דלתות", "🚪", 160, 60, 20),
          activeSpecialty("furniture_repair", "תיקון רהיטים", "🔧", 130, 45, 18),
        ],
        aiPhotoToQuote: {
          enabled: true,
          categories: { plumbing: true, electrical: true, drywall: true, furniture: true },
        },
        pricing: { custom: [], emergencySurcharge: 50 },
        punchListDiscount: { "2_jobs": 10, "3_jobs": 20, "4_plus_jobs": 30 },
        serviceArea: {
          cities: [
            "תל אביב",
            "רמת גן",
            "גבעתיים",
            "הרצליה",
            "פתח תקווה",
            "ראשון לציון",
            "רעננה",
            "כפר סבא",
          ],
          emergency24_7: false,
          bufferMinutes: 30,
        },
        materials: { toolsIncluded: true, policy: "flexible" },
        maintenancePackages: [
          {
            id: "basic",
            nameHe: "בייסיק — 2 ביקורים/שנה",
            visitsPerYear: 2,
            yearlyPrice: 890,
            enabled: true,
            activeCustomers: 12,
            popular: false,
          },
          {
            id: "premium",
            nameHe: "פרימיום — 4 ביקורים/שנה",
            visitsPerYear: 4,
            yearlyPrice: 1690,
            enabled: true,
            activeCustomers: 22,
            popular: true,
          },
          {
            id: "vip",
            nameHe: "VIP — ביקורים לא מוגבלים",
            visitsPerYear: -1,
            yearlyPrice: 2990,
            enabled: true,
            activeCustomers: 4,
            popular: false,
          },
        ],
      },
      reviews: [
        {
          reviewerName: "תומר ניצן",
          rating: 5,
          comment:
            "אבי הגיע, הסתכל ברשימה, ועשה הכל ב-3 שעות: תלה 2 טלוויזיות, הרכיב ארון " +
            "IKEA-קליק, ותיקן ברז דולף. מקצוען-על.",
          daysAgo: 5,
        },
        {
          reviewerName: "אילנה ברקוביץ׳",
          rating: 5,
          comment:
            "הוא בא, ראה, ופתר. ידע איך לתלות טלוויזיה 75״ על קיר גבס בלי לפגוע. " +
            "ממליצה לכל מי שצריך עבודה ברמה.",
          daysAgo: 11,
        },
        {
          reviewerName: "אריאל סלע",
          rating: 5,
          comment:
            "פנצ׳ר באמבטיה ב-21:00. אבי הגיע תוך שעה, החליף את החלק, ועלה לי 320₪. " +
            "מקצועי מהיר ולא מוצץ דם.",
          daysAgo: 18,
        },
        {
          reviewerName: "תמר וייסמן",
          rating: 4,
          comment:
            "מקצוען אמיתי. רק אומר שאבי תפוס המון, צריך לתאם 3-4 ימים מראש לפעמים.",
          daysAgo: 26,
        },
      ],
    },
    {
      uid: "demo_handyman_2",
      name: "יוסי מטלון — הנדימן 24/7 לחירומים",
      phone: "052-7788244",
      email: "yossi.handyman.demo@anyskill.app",
      aboutMe:
        "מתמחה בחירומים — אינסטלציה, חשמל קל, מנעולים. זמין 24/7 כולל לילות, שבתות " +
        "וחגים. מגיע בתוך שעה לרוב המקרים בתל אביב/גוש דן. תוספת חירום: 50% למחיר " +
        "הבסיסי בלבד, ללא הפתעות. רואה את עצמי כאמבולנס של הבית — מצליח לפתור 95% " +
        "מהבעיות בקריאה אחת, גם בעיות שאחרים לא הצליחו.",
      profileImage:
        "https://images.unsplash.com/photo-1565884280295-98eb83e41c65?w=400&h=400&fit=crop&q=80",
      gallery: [
        "https://images.unsplash.com/photo-1521791055366-0d553872125f?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1581244249285-6e5b2caaf60d?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1542013936693-884638332954?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1530268729831-4b0b9e170218?w=800&h=600&fit=crop&q=80",
      ],
      completedJobs: 612,
      pricePerHour: 220,
      workingHours: WH_24_7,
      quickTags: ["fast_response", "24_7", "professional"],
      isTopRated: true,
      handymanProfile: {
        verifications: {
          backgroundCheck: {
            verified: true,
            verifiedAt: Timestamp.fromDate(new Date(Date.now() - 60 * 24 * 60 * 60 * 1000)),
          },
          warrantyEnabled: true,
        },
        specialties: [
          activeSpecialty("plumbing_fix", "אינסטלציה קלה", "🚿", 220, 90, 12, "urgent"),
          activeSpecialty("electrical_minor", "חשמל קל", "💡", 240, 60, 10, "urgent"),
          activeSpecialty("locks", "מנעולים", "🔐", 280, 60, 10, "urgent"),
          activeSpecialty("doors", "דלתות", "🚪", 220, 60, 12),
          activeSpecialty("bathroom_fix", "תיקוני אמבטיה", "🚽", 240, 60, 12),
          activeSpecialty("kitchen_fix", "תיקוני מטבח", "🍳", 240, 75, 10),
        ],
        aiPhotoToQuote: {
          enabled: true,
          categories: { plumbing: true, electrical: true, drywall: false, furniture: false },
        },
        pricing: { custom: [], emergencySurcharge: 50 },
        punchListDiscount: { "2_jobs": 5, "3_jobs": 10, "4_plus_jobs": 15 },
        serviceArea: {
          cities: [
            "תל אביב",
            "רמת גן",
            "גבעתיים",
            "בני ברק",
            "הרצליה",
            "חולון",
            "בת ים",
          ],
          emergency24_7: true,
          bufferMinutes: 15,
        },
        materials: { toolsIncluded: true, policy: "i_buy" },
        maintenancePackages: [],
      },
      reviews: [
        {
          reviewerName: "רן עשור",
          rating: 5,
          comment:
            "ברז התפוצץ בשבת ב-23:00. יוסי הגיע ב-23:55. עצר את המים, החליף את החלק, " +
            "ועלה לי 480₪. שווה כל אגורה.",
          daysAgo: 4,
        },
        {
          reviewerName: "ענת ארגוב",
          rating: 5,
          comment:
            "נעולה מחוץ לבית בערב חג. יוסי הגיע ב-30 דקות, פתח את הדלת בלי שבירה. " +
            "אבירי אמיתי.",
          daysAgo: 13,
        },
        {
          reviewerName: "אופיר ענבל",
          rating: 5,
          comment:
            "מקצוען של חירומים. מחיר גבוה — אבל מקבל מה ששילמת.",
          daysAgo: 20,
        },
      ],
    },
    {
      uid: "demo_handyman_3",
      name: "סער דגן — הנדימן עם התמחות בעיצוב פנים",
      phone: "054-3344155",
      email: "saar.handyman.demo@anyskill.app",
      aboutMe:
        "8 שנים בענף — הנדימן עם רקע בעיצוב פנים. מתמחה בתליית תמונות + מראות, התקנת " +
        "מדפים, גופי תאורה, וילונות. הופך את הבית למוצג. אהיה בעל הטעם והכלים שיעזרו " +
        "לך לתכנן את הקיר/פינה. מחיר מעט גבוה מהממוצע — אבל מבטיח עבודה שמשתלמת בעין. " +
        "מחירון פתוח לכל פריט בשירות.",
      profileImage:
        "https://images.unsplash.com/photo-1492562080023-ab3db95bfbce?w=400&h=400&fit=crop&q=80",
      gallery: [
        "https://images.unsplash.com/photo-1493663284031-b7e3aefcae8e?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1567016376408-0226e4d0c1ea?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1505691938895-1758d7feb511?w=800&h=600&fit=crop&q=80",
      ],
      completedJobs: 348,
      pricePerHour: 175,
      workingHours: WH_BUSINESS,
      quickTags: ["specialist", "professional", "reliable"],
      isTopRated: false,
      handymanProfile: {
        verifications: {
          backgroundCheck: {
            verified: true,
            verifiedAt: Timestamp.fromDate(new Date(Date.now() - 120 * 24 * 60 * 60 * 1000)),
          },
          warrantyEnabled: true,
        },
        specialties: [
          activeSpecialty("picture_hanging", "תליית תמונות ומראות", "🖼️", 90, 30, 8, "hot"),
          activeSpecialty("shelves", "מדפים", "🗄️", 120, 30, 8),
          activeSpecialty("light_fixtures", "גופי תאורה", "💡", 170, 60, 7),
          activeSpecialty("curtains", "וילונות", "🪟", 140, 45, 8),
          activeSpecialty("blinds", "תריסים", "🪟", 130, 45, 6),
          activeSpecialty("furniture_assembly", "הרכבת רהיטים", "🪑", 250, 120, 8),
          activeSpecialty("ceiling_fan", "מאווררי תקרה", "🪭", 220, 75, 6),
        ],
        aiPhotoToQuote: {
          enabled: true,
          categories: { plumbing: false, electrical: true, drywall: true, furniture: true },
        },
        pricing: {
          custom: [
            { serviceId: "picture_hanging", price: 90 },
            { serviceId: "shelves", price: 120 },
          ],
          emergencySurcharge: 40,
        },
        punchListDiscount: { "2_jobs": 12, "3_jobs": 22, "4_plus_jobs": 32 },
        serviceArea: {
          cities: ["תל אביב", "רמת גן", "גבעתיים", "הרצליה", "רמת השרון", "רעננה"],
          emergency24_7: false,
          bufferMinutes: 30,
        },
        materials: { toolsIncluded: true, policy: "flexible" },
        maintenancePackages: [
          {
            id: "premium",
            nameHe: "פרימיום — 4 ביקורים/שנה",
            visitsPerYear: 4,
            yearlyPrice: 1790,
            enabled: true,
            activeCustomers: 8,
            popular: true,
          },
        ],
      },
      reviews: [
        {
          reviewerName: "נטלי כהן",
          rating: 5,
          comment:
            "סער יודע איך לתלות תמונה. תליתי איתו קולקציה של 12 תמונות בסלון — " +
            "כל אחת בגובה הנכון, מרווחים זהים. כמו מוזיאון.",
          daysAgo: 8,
        },
        {
          reviewerName: "אורי דוידוף",
          rating: 5,
          comment:
            "מאוורר תקרה + 4 מנורות בסלון. עבודה נקייה, ללא חורים מיותרים. הזמנתי " +
            "אותו עוד פעם לחדר השינה.",
          daysAgo: 17,
        },
        {
          reviewerName: "מירב גנני",
          rating: 5,
          comment:
            "התקין לי מערכת מדפים פתוחים מ-IKEA, בקיר לא ישר. הוא יישר את הכל בלי " +
            "טיפת תלונה. סבלני ומדויק.",
          daysAgo: 30,
        },
      ],
    },
  ],
};

// ═══════════════════════════════════════════════════════════════════════════
// 5. מאמני כושר (Fitness Trainer CSM) — 3 demos
//    Requires fitnessTrainerProfile with selectedSpecialties non-empty.
// ═══════════════════════════════════════════════════════════════════════════
function fitnessPackage(id, name, type, sessions, durationMinutes, price, isPopular, includesFreeOnboarding, discount, validityMonths) {
  return {
    id,
    name,
    type,
    sessions,
    durationMinutes,
    price,
    discount: discount || null,
    validityMonths: validityMonths || null,
    isPopular: !!isPopular,
    includesFreeOnboarding: !!includesFreeOnboarding,
  };
}

function fitnessLocation(id, type, radiusKm, extraCost, notes) {
  return { id, type, radiusKm, extraCost: extraCost || null, notes: notes || null };
}

const FITNESS = {
  serviceType: "מאמני כושר",
  parentCategory: "כושר וספורט",
  demos: [
    {
      uid: "demo_fitness_1",
      name: "רון אדלמן — מאמן כושר אישי + תזונה",
      phone: "050-6677233",
      email: "ron.fitness.demo@anyskill.app",
      aboutMe:
        "מאמן כושר אישי 10 שנים, בעל תעודת NASM-CPT + תזונאי מוסמך. מתמחה בהרזיה " +
        "ובניית מסת שריר לגברים ונשים 25-50. עובד בעיקר בחדרי כושר (Holmes Place, " +
        "Gympass) ובבית הלקוח. אישיות רגועה, מבוססת נתונים — מעקב מדויק על משקלים, " +
        "תוכנית תזונה אישית, ודיווח שבועי. תוצאות מובטחות תוך 12 שבועות או החזר כספי.",
      profileImage:
        "https://images.unsplash.com/photo-1583454110551-21f2fa2afe61?w=400&h=400&fit=crop&q=80",
      gallery: [
        "https://images.unsplash.com/photo-1574680096145-d05b474e2155?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1517836357463-d25dfeac3438?w=800&h=600&fit=crop&q=80",
      ],
      completedJobs: 845,
      pricePerHour: 220,
      workingHours: {
        "0": { from: "06:00", to: "21:00" },
        "1": { from: "06:00", to: "21:00" },
        "2": { from: "06:00", to: "21:00" },
        "3": { from: "06:00", to: "21:00" },
        "4": { from: "06:00", to: "14:00" },
      },
      quickTags: ["professional", "experienced", "reliable"],
      isTopRated: true,
      fitnessTrainerProfile: {
        selectedSpecialties: ["strength", "fatLoss", "endurance"],
        packages: [
          fitnessPackage("p_trial", "אימון ניסיון", "single", 1, 60, 180, false, true),
          fitnessPackage("p_8", "חבילת 8 אימונים", "package", 8, 60, 1440, false, false, 10, 3),
          fitnessPackage("p_12", "חבילת 12 אימונים", "package", 12, 60, 1980, true, true, 15, 4),
          fitnessPackage("p_monthly", "מנוי חודשי — 12 אימונים", "monthly", 12, 60, 2200, false, true),
        ],
        locations: [
          fitnessLocation("l_gym", "gym", 10, 0, "Holmes Place הוד השרון / שפת הים"),
          fitnessLocation("l_home", "home", 15, 30, "בבית הלקוח — אזור הרצליה/הוד השרון"),
        ],
        certifications: [
          { id: "c_nasm", name: "NASM-CPT", institution: "אורט בראודה", year: 2015, imageUrl: null, isVerified: true },
          { id: "c_nutr", name: "תזונאי מוסמך", institution: "אורט בראודה", year: 2018, imageUrl: null, isVerified: true },
        ],
        successStories: [
          {
            id: "s1",
            clientName: "ד״ר מאיה (אנונימי)",
            result: "ירדה 18 ק״ג ב-6 חודשים, יציבה לעבודה בעמידה ארוכה",
            testimonial: "רון נתן לי תקווה ותוכנית, ובעיקר משמעת. חזרתי לחיים.",
            beforeImageUrl: null,
            afterImageUrl: null,
            rating: 5,
            createdAt: Timestamp.fromDate(new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)),
            clientApproved: true,
          },
        ],
        offers: [
          {
            id: "o1",
            type: "firstFree",
            title: "אימון ראשון חינם",
            description: "אבחון מקצועי + תוכנית אישית בלי התחייבות",
            discountPercent: 100,
            availableSpots: 8,
            expiresAt: Timestamp.fromDate(new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)),
            isActive: true,
          },
        ],
        profileScore: 88,
        aiSuggestions: [],
      },
      reviews: [
        {
          reviewerName: "אסף לוי",
          rating: 5,
          comment:
            "רון לקח אותי מ-92 קילו ל-78 ב-9 חודשים. גם תזונה גם אימון. גישה שיטתית, " +
            "ידע מעולה. ממליץ בלי היסוס.",
          daysAgo: 7,
        },
        {
          reviewerName: "תהילה בר-נר",
          rating: 5,
          comment:
            "פעם ראשונה שאני נדבק עם מאמן יותר מחודש. הסיבה: רון מתאים את התוכנית כל שבוע " +
            "לפי מה שעבד ומה שלא. מקצוען-של.",
          daysAgo: 14,
        },
        {
          reviewerName: "עומר נחום",
          rating: 4,
          comment:
            "מאמן מעולה, רק חבל שהוא מאוד עסוק. צריך לתאם 2 שבועות מראש לפעמים.",
          daysAgo: 22,
        },
      ],
    },
    {
      uid: "demo_fitness_2",
      name: "טל סגל — מאמנת כושר נשים + הריון",
      phone: "052-9911344",
      email: "tal.fitness.demo@anyskill.app",
      aboutMe:
        "מאמנת כושר אישית 6 שנים, מומחית באימון נשים — לפני, בזמן ואחרי הריון. " +
        "תעודת ACSM + תעודת הכשרה מ-Wingate בכושר לנשים בהריון. מאמנת בבית הלקוחה " +
        "או בפארק (חוף הים, פארק רעננה). יחס אמהי, סבלני, ומסביר כל תרגיל ולמה. " +
        "מבטיחה: לעולם לא תרגיש לבד עם אימון לא ברור.",
      profileImage:
        "https://images.unsplash.com/photo-1518611012118-696072aa579a?w=400&h=400&fit=crop&q=80",
      gallery: [
        "https://images.unsplash.com/photo-1518310383802-640c2de311b2?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1532187863486-abf9dbad1b69?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1593810451137-3c2cf81bb4f7?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1518611012118-696072aa579a?w=800&h=600&fit=crop&q=80",
      ],
      completedJobs: 412,
      pricePerHour: 180,
      workingHours: WH_FAMILY,
      quickTags: ["specialist", "patient", "family_friendly"],
      isTopRated: true,
      fitnessTrainerProfile: {
        selectedSpecialties: ["pregnancy", "fatLoss", "flexibility", "functional"],
        packages: [
          fitnessPackage("p_trial", "אימון אבחון חינם", "single", 1, 45, 0, false, true),
          fitnessPackage("p_pregnancy_pack", "חבילת הריון — 10 אימונים", "package", 10, 50, 1700, true, true, 10, 3),
          fitnessPackage("p_postpartum", "חזרה אחרי לידה — 8 אימונים", "package", 8, 45, 1280, false, true, null, 2),
          fitnessPackage("p_monthly", "מנוי חודשי — 8 אימונים", "monthly", 8, 60, 1400, false, false),
        ],
        locations: [
          fitnessLocation("l_home", "home", 12, 0, "בבית הלקוחה"),
          fitnessLocation("l_park", "park", 15, 0, "פארק רעננה / חוף הרצליה"),
        ],
        certifications: [
          { id: "c_acsm", name: "ACSM-CPT", institution: "ACSM", year: 2017, imageUrl: null, isVerified: true },
          { id: "c_preg", name: "כושר לנשים בהריון", institution: "Wingate", year: 2019, imageUrl: null, isVerified: true },
        ],
        successStories: [
          {
            id: "s1",
            clientName: "מאיה (אנונימי)",
            result: "חזרה לכושר 8 שבועות אחרי לידה ראשונה",
            testimonial: "טל ידעה איך לבנות לי בטחון מחדש. תודה.",
            beforeImageUrl: null,
            afterImageUrl: null,
            rating: 5,
            createdAt: Timestamp.fromDate(new Date(Date.now() - 60 * 24 * 60 * 60 * 1000)),
            clientApproved: true,
          },
        ],
        offers: [
          {
            id: "o1",
            type: "discount",
            title: "10% הנחה למצטרפות חדשות",
            description: "10% הנחה על חבילת ההריון לחודש הבא",
            discountPercent: 10,
            availableSpots: 5,
            expiresAt: Timestamp.fromDate(new Date(Date.now() + 45 * 24 * 60 * 60 * 1000)),
            isActive: true,
          },
        ],
        profileScore: 82,
        aiSuggestions: [],
      },
      reviews: [
        {
          reviewerName: "מיכל בן-עמי",
          rating: 5,
          comment:
            "בשליש השני של ההריון התחלתי עם טל. היא ידעה בדיוק מה אפשר ומה לא. " +
            "חזרתי לעבודה אחרי לידה כשאני בכושר אדיר.",
          daysAgo: 5,
        },
        {
          reviewerName: "שיר מימוני",
          rating: 5,
          comment:
            "אחרי לידה שנייה הייתי שבורה. טל בנתה לי תוכנית מהוקצעת, התחלנו ב-20 דקות ביום. " +
            "תוך 3 חודשים — כושר חזק יותר משהיה לפני.",
          daysAgo: 12,
        },
        {
          reviewerName: "סיון פינס",
          rating: 5,
          comment:
            "אישית, סבלנית, מקצועית. טל הופכת אימון לחוויה.",
          daysAgo: 20,
        },
      ],
    },
    {
      uid: "demo_fitness_3",
      name: "ענבר ירדן — מאמנת כוח + מסת שריר",
      phone: "054-7788455",
      email: "inbar.fitness.demo@anyskill.app",
      aboutMe:
        "5 שנים בענף, מתמחה בכוח ומסה — בעיקר נשים שמפחדות מצעד פעם ראשונה למסעדת הברזל. " +
        "תעודת ISSA + Squat University-קוצ׳. עובדת ב-Holmes Place פתח תקווה ובבית הלקוחה. " +
        "סטייל: ישיר, מצחיק, ובלי לסבול 'אני לא יכולה'. עם תוצאות אמיתיות — לקוחות שלי " +
        "מתאמנות גם 3 שנים אחרי שעזבו אותי.",
      profileImage:
        "https://images.unsplash.com/photo-1594381898411-846e7d193883?w=400&h=400&fit=crop&q=80",
      gallery: [
        "https://images.unsplash.com/photo-1532384748853-8f54a8f476e2?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1599058917765-a780eda07a3e?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1518611012118-696072aa579a?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1517836357463-d25dfeac3438?w=800&h=600&fit=crop&q=80",
      ],
      completedJobs: 287,
      pricePerHour: 195,
      workingHours: WH_EVENINGS,
      quickTags: ["specialist", "experienced"],
      isTopRated: false,
      fitnessTrainerProfile: {
        selectedSpecialties: ["strength", "bulking", "competitionPrep"],
        packages: [
          fitnessPackage("p_single", "אימון בודד", "single", 1, 60, 220, false, false),
          fitnessPackage("p_10", "חבילת 10 אימונים", "package", 10, 60, 1980, true, false, 10, 3),
          fitnessPackage("p_comp", "הכנה לתחרות — 12 שבועות", "package", 24, 75, 4800, false, true, null, 4),
        ],
        locations: [
          fitnessLocation("l_gym", "gym", 8, 0, "Holmes Place פתח תקווה / Gymforce"),
          fitnessLocation("l_home", "home", 10, 40, "בבית הלקוחה — אזור מרכז"),
        ],
        certifications: [
          { id: "c_issa", name: "ISSA-CPT", institution: "ISSA", year: 2019, imageUrl: null, isVerified: true },
        ],
        successStories: [],
        offers: [],
        profileScore: 72,
        aiSuggestions: [],
      },
      reviews: [
        {
          reviewerName: "מעיין רונן",
          rating: 5,
          comment:
            "פחדתי לגעת במשקולות. ענבר לקחה אותי מ-0 לסקווט 80 קילו ב-8 חודשים. " +
            "שינוי חיים, בלי הגזמה.",
          daysAgo: 6,
        },
        {
          reviewerName: "דנה רוזנברג",
          rating: 5,
          comment:
            "מצחיקה, ישירה, ובעיקר — היא יודעת מה היא עושה. כל פגישה היא תכנון מדויק.",
          daysAgo: 14,
        },
        {
          reviewerName: "ליטל אסולין",
          rating: 4,
          comment:
            "תוצאות אמיתיות. רק לפעמים קשה לתאם — היא ביקושת.",
          daysAgo: 23,
        },
      ],
    },
  ],
};

// ═══════════════════════════════════════════════════════════════════════════
// 6. בייביסיטר (Babysitter CSM) — 3 demos
//    Requires babysitterProfile (no condition gate).
// ═══════════════════════════════════════════════════════════════════════════
const BABYSITTER = {
  serviceType: "בייביסיטר",
  parentCategory: "משפחה וילדים",
  demos: [
    {
      uid: "demo_babysitter_1",
      name: "אורי שטינברג — בייביסיטרית בכירה (סטודנטית לחינוך)",
      phone: "050-2233166",
      email: "ori.babysitter.demo@anyskill.app",
      aboutMe:
        "סטודנטית שנה ג׳ לחינוך וילדים בגיל הרך באוניברסיטת תל אביב. 4 שנות ניסיון " +
        "כבייביסיטרית קבועה אצל 3 משפחות. תעודת עזרה ראשונה לתינוקות (BLS) מ-מד״א, " +
        "תעודת רקע פלילי נקייה, ו-2 הורים שיכולים להעיד עליי. נחמדה, סבלנית, ויודעת " +
        "להתאים את עצמי לגיל. עוסקת באמת בילדים — לא בטלפון.",
      profileImage:
        "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=400&h=400&fit=crop&q=80",
      gallery: [
        "https://images.unsplash.com/photo-1582213782179-e0d53f98f2ca?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1503454537195-1dcabb73ffb9?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1607274033693-12d75c9fc3a3?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1602030638412-bb8dcc0bc8b0?w=800&h=600&fit=crop&q=80",
      ],
      completedJobs: 156,
      pricePerHour: 65,
      workingHours: WH_FAMILY,
      quickTags: ["family_friendly", "patient", "responsive"],
      isTopRated: true,
      babysitterProfile: {
        experience: { yearsExperience: 4, totalFamilies: 8, hasOwnChildren: false },
        ageGroups: ["infant", "toddler", "preschool", "school_age"],
        servicesOffered: [
          "feeding",
          "bath",
          "bedtime",
          "homework",
          "play_activities",
          "outdoor",
          "pickup_school",
        ],
        certifications: [
          { id: "c1", type: "first_aid", nameHe: "עזרה ראשונה לתינוקות (BLS)", issuedBy: "מד״א", verified: true },
          { id: "c2", type: "childcare_diploma", nameHe: "שנה ג׳ לחינוך וילדים בגיל הרך", issuedBy: "אוניברסיטת תל אביב", verified: true },
        ],
        pricing: {
          rateOneChild: 65,
          rateTwoChildren: 85,
          rateThreePlusChildren: 105,
          nightSurchargePercent: 20,
          nightStartsAtHour: 22,
          nightEndsAtHour: 6,
          holidaySurchargePercent: 50,
          lateFeePerInterval: 40,
          lateFeeIntervalMinutes: 15,
          lateFeeMaxAmount: 500,
          minimumBookingHours: 2,
          overnightFlatRate: 0,
          lastMinuteSurchargePercent: 30,
          lastMinuteThresholdHours: 2,
        },
        availability: {
          availableDays: [0, 1, 2, 3, 4, 6],
          acceptsLastMinute: true,
          acceptsOvernight: false,
          acceptsHolidays: true,
        },
        serviceArea: {
          cities: ["תל אביב", "רמת גן", "גבעתיים", "רמת השרון"],
          arrivalRadiusMeters: 50,
          travelFeeOutsideRadius: 25,
          freeRadiusKm: 8,
        },
        trust: {
          backgroundChecked: true,
          idVerified: true,
          referencesAvailable: true,
          referencesCount: 4,
        },
        introNote:
          "שלום, אני אורי 😊 אם הילדים שלכם מתחת לגיל 12 ואתם רוצים מישהי שיוצרת איתם " +
          "פעילות אמיתית, אני האדם. הזמן ביחד בילדים מקצועית — לא לפני הטלוויזיה.",
      },
      reviews: [
        {
          reviewerName: "שירה אדלר",
          rating: 5,
          comment:
            "אורי שמרה על הבן שלי בן 3 ועל התינוקת בת 8 חודשים. הילדים אהבו אותה. " +
            "היא יצרה איתם פעילות יצירה כל הערב, התינוקת נרדמה איתה בידיים. נדיר.",
          daysAgo: 5,
        },
        {
          reviewerName: "תמר ליבסקינד",
          rating: 5,
          comment:
            "סטודנטית לחינוך זה לא רק תעודה — אורי מבינה ילדים. עזרה בשיעורי בית, " +
            "המציאה משחקי תפקידים, ו-הילד שלי אמר 'אני אוהב את אורי'.",
          daysAgo: 13,
        },
        {
          reviewerName: "אסף ברנע",
          rating: 5,
          comment:
            "ערב יציאה חירום — אורי הסכימה ברגע האחרון, חיוך גדול, ושמרה על הקטנים שלנו " +
            "מצוין. הביאה לנו 5 דקות שלוות. תודה!",
          daysAgo: 20,
        },
        {
          reviewerName: "נעמה גולן",
          rating: 4,
          comment:
            "נחמדה ואחראית. צריך לתאם 3-4 ימים מראש כי היא לומדת.",
          daysAgo: 28,
        },
      ],
    },
    {
      uid: "demo_babysitter_2",
      name: "סבטלנה ולודיצקי — מטפלת מומחית בתינוקות",
      phone: "052-3344277",
      email: "svetlana.babysitter.demo@anyskill.app",
      aboutMe:
        "12 שנה כמטפלת בילדים, מתמחה בתינוקות (0-2). 3 ילדים משלי, ו-15 שנה ניסיון " +
        "מצטבר אצל משפחות בישראל ובחו״ל. תעודת אחות סיעודית בילדים (קוצ׳ פוסט-ניאונטל) " +
        "מ-בית חולים שניידר. עובדת בעיקר בשעות יום (07:00-18:00) אצל משפחות עם תינוק " +
        "ראשון. יודעת הרגעה, הנקה (גם משאבה), אמבטיה. שמה לב לפרטים — תינוקות תחתי " +
        "ידיים זה לקדש.",
      profileImage:
        "https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=400&h=400&fit=crop&q=80",
      gallery: [
        "https://images.unsplash.com/photo-1518780664697-55e3ad937233?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1607274033693-12d75c9fc3a3?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1606960848155-5d3d77c50aac?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1607495536830-5bf91c5cd1c1?w=800&h=600&fit=crop&q=80",
      ],
      completedJobs: 487,
      pricePerHour: 90,
      workingHours: {
        "0": { from: "07:00", to: "18:00" },
        "1": { from: "07:00", to: "18:00" },
        "2": { from: "07:00", to: "18:00" },
        "3": { from: "07:00", to: "18:00" },
        "4": { from: "07:00", to: "16:00" },
      },
      quickTags: ["experienced", "specialist", "patient", "reliable"],
      isTopRated: true,
      babysitterProfile: {
        experience: { yearsExperience: 12, totalFamilies: 18, hasOwnChildren: true },
        ageGroups: ["infant", "toddler"],
        servicesOffered: [
          "feeding",
          "bath",
          "bedtime",
          "play_activities",
          "outdoor",
          "light_housework",
        ],
        certifications: [
          { id: "c1", type: "first_aid", nameHe: "עזרה ראשונה לתינוקות (BLS)", issuedBy: "מד״א", verified: true },
          { id: "c2", type: "childcare_diploma", nameHe: "תעודת אחות סיעודית — ילדים", issuedBy: "בית חולים שניידר", verified: true },
        ],
        pricing: {
          rateOneChild: 90,
          rateTwoChildren: 120,
          rateThreePlusChildren: 150,
          nightSurchargePercent: 25,
          nightStartsAtHour: 22,
          nightEndsAtHour: 6,
          holidaySurchargePercent: 50,
          lateFeePerInterval: 50,
          lateFeeIntervalMinutes: 15,
          lateFeeMaxAmount: 600,
          minimumBookingHours: 3,
          overnightFlatRate: 0,
          lastMinuteSurchargePercent: 35,
          lastMinuteThresholdHours: 3,
        },
        availability: {
          availableDays: [0, 1, 2, 3, 4],
          acceptsLastMinute: true,
          acceptsOvernight: false,
          acceptsHolidays: false,
        },
        serviceArea: {
          cities: ["פתח תקווה", "רמת גן", "גבעתיים", "תל אביב", "בני ברק"],
          arrivalRadiusMeters: 50,
          travelFeeOutsideRadius: 30,
          freeRadiusKm: 10,
        },
        trust: {
          backgroundChecked: true,
          idVerified: true,
          referencesAvailable: true,
          referencesCount: 8,
        },
        introNote:
          "אני סבטלנה. אם זה התינוק הראשון שלכם ואתם לחוצים — אני נושמת לעומק, סבלנית, " +
          "ויודעת בדיוק מה לעשות. הגעתי כדי שתוכלו לנשום שוב.",
      },
      reviews: [
        {
          reviewerName: "ענת ארליך",
          rating: 5,
          comment:
            "תינוק ראשון, אחרי לידה קשה. סבטלנה הצילה אותנו. ידעה איך להרגיע אותו, " +
            "איך לקרר, ובעיקר — איך לתת לי לישון. מטפלת אדירה.",
          daysAgo: 4,
        },
        {
          reviewerName: "תמר ירדן",
          rating: 5,
          comment:
            "תאומים בני 4 חודשים. סבטלנה הצליחה לתאם להם זמני שינה ואכילה. " +
            "השוואה לפני ואחרי = יום ולילה.",
          daysAgo: 13,
        },
        {
          reviewerName: "רותם בן-דוד",
          rating: 5,
          comment:
            "מקצועית מאוד. ידעה לזהות תפרחת באבחנה, וגרמה לנו ללכת לרופא. " +
            "התפרחת התברר כאלרגיה לזמן. הצילה את התינוק שלנו.",
          daysAgo: 22,
        },
      ],
    },
    {
      uid: "demo_babysitter_3",
      name: "ניצן שובל — בייביסיטרית לימי שישי ושבת",
      phone: "054-5566377",
      email: "nitzan.babysitter.demo@anyskill.app",
      aboutMe:
        "תלמידת תיכון שנה י״ב, אוהבת ילדים מגיל 4 ומעלה. זמינה שישי-שבת, וערבים. " +
        "תעודת מד״א בעזרה ראשונה, בייביסיט אצל 4 משפחות 3 שנים. נחמדה, יוזמת, " +
        "אופה עוגיות עם הילדים, יודעת לבחור סרטים מתאימים, ועוזרת בשיעורי בית. " +
        "מחיר נוח לבייביסיטר ערב — מתאימה לזוגות שרוצים לצאת.",
      profileImage:
        "https://images.unsplash.com/photo-1517677208171-0bc6725a3e60?w=400&h=400&fit=crop&q=80",
      gallery: [
        "https://images.unsplash.com/photo-1503454537195-1dcabb73ffb9?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1545558014-8692077e9b5c?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1606960848155-5d3d77c50aac?w=800&h=600&fit=crop&q=80",
        "https://images.unsplash.com/photo-1602030638412-bb8dcc0bc8b0?w=800&h=600&fit=crop&q=80",
      ],
      completedJobs: 78,
      pricePerHour: 50,
      workingHours: WH_EVENINGS,
      quickTags: ["family_friendly", "fair_price", "responsive"],
      isTopRated: false,
      babysitterProfile: {
        experience: { yearsExperience: 3, totalFamilies: 4, hasOwnChildren: false },
        ageGroups: ["preschool", "school_age", "teen"],
        servicesOffered: [
          "feeding",
          "bath",
          "bedtime",
          "homework",
          "play_activities",
          "outdoor",
        ],
        certifications: [
          { id: "c1", type: "first_aid", nameHe: "עזרה ראשונה (תיכון)", issuedBy: "מד״א", verified: true },
        ],
        pricing: {
          rateOneChild: 50,
          rateTwoChildren: 65,
          rateThreePlusChildren: 80,
          nightSurchargePercent: 15,
          nightStartsAtHour: 23,
          nightEndsAtHour: 6,
          holidaySurchargePercent: 30,
          lateFeePerInterval: 30,
          lateFeeIntervalMinutes: 15,
          lateFeeMaxAmount: 300,
          minimumBookingHours: 2,
          overnightFlatRate: 0,
          lastMinuteSurchargePercent: 20,
          lastMinuteThresholdHours: 1,
        },
        availability: {
          availableDays: [3, 4, 5, 6],
          acceptsLastMinute: true,
          acceptsOvernight: false,
          acceptsHolidays: true,
        },
        serviceArea: {
          cities: ["תל אביב", "רמת גן", "גבעתיים"],
          arrivalRadiusMeters: 50,
          travelFeeOutsideRadius: 20,
          freeRadiusKm: 6,
        },
        trust: {
          backgroundChecked: false,
          idVerified: true,
          referencesAvailable: true,
          referencesCount: 3,
        },
        introNote:
          "היי! אני ניצן, תיכוניסטית בשנה אחרונה. אם אתם רוצים לצאת ערב חמישי, שישי " +
          "או שבת, וצריכים מישהי אחראית ונחמדה — כאן 🤗",
      },
      reviews: [
        {
          reviewerName: "מעיין רוטשילד",
          rating: 5,
          comment:
            "ניצן שמרה על 2 הילדים שלי (5 ו-8) בערב שישי. כשחזרנו, הם ישנו אחרי שאפו " +
            "עוגיות יחד. מתוקה, בוגרת לגילה, ומחיר הוגן.",
          daysAgo: 8,
        },
        {
          reviewerName: "אילן צדוק",
          rating: 5,
          comment:
            "תלמידה רצינית, נחמדה לילדים. נחמד שיש בייביסיטרית במחיר סטודנטית.",
          daysAgo: 16,
        },
        {
          reviewerName: "סופי אליהו",
          rating: 4,
          comment:
            "טובה, אבל לא לכל ערב — לפעמים יש לה בחינות. תאם זמינות מראש.",
          daysAgo: 24,
        },
      ],
    },
  ],
};

// ═══════════════════════════════════════════════════════════════════════════
// MAIN — write everything to Firestore
// ═══════════════════════════════════════════════════════════════════════════
const ALL_GROUPS = [
  { groupKey: "pet_boarding", csmField: null, payload: PET_BOARDING },
  { groupKey: "delivery", csmField: "deliveryProfile", payload: DELIVERY },
  { groupKey: "cleaning", csmField: "cleaningProfile", payload: CLEANING },
  { groupKey: "handyman", csmField: "handymanProfile", payload: HANDYMAN },
  { groupKey: "fitness", csmField: "fitnessTrainerProfile", payload: FITNESS },
  { groupKey: "babysitter", csmField: "babysitterProfile", payload: BABYSITTER },
];

async function writeOne(serviceType, parentCategory, csmField, demo) {
  const uid = demo.uid;
  const listingId = `demo_${uid}`;

  // Build user doc
  const userData = {
    uid,
    name: demo.name,
    phone: demo.phone,
    email: demo.email,
    aboutMe: demo.aboutMe,
    profileImage: demo.profileImage,
    serviceType,
    subCategoryName: serviceType,
    parentCategory,
    gallery: demo.gallery || [],
    completedJobs: demo.completedJobs,
    rating: 0, // recomputed below from review docs
    reviewsCount: (demo.reviews || []).length,
    pricePerHour: demo.pricePerHour,
    categoryDetails: demo.categoryDetails || {},
    workingHours: demo.workingHours,
    cancellationPolicy: "moderate",
    quickTags: demo.quickTags,
    responseTimeMinutes: 12,
    isProvider: true,
    isCustomer: false,
    isDemo: true,
    isOnline: true,
    isVerified: true,
    isTopRated: !!demo.isTopRated,
    isAnySkillPro: !!demo.isTopRated,
    isHidden: false,
    balance: 0,
    listingIds: [listingId],
    activeIdentityCount: 1,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (csmField) {
    userData[csmField] = demo[csmField];
  }

  // Build listing doc (parallel structure)
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
    isAnySkillPro: !!demo.isTopRated,
    isPromoted: false,
    serviceType,
    parentCategory,
    subCategory: serviceType,
    aboutMe: demo.aboutMe,
    pricePerHour: demo.pricePerHour,
    gallery: demo.gallery || [],
    categoryDetails: demo.categoryDetails || {},
    quickTags: demo.quickTags,
    workingHours: demo.workingHours,
    cancellationPolicy: "moderate",
    responseTimeMinutes: 12,
    rating: 0,
    reviewsCount: (demo.reviews || []).length,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (csmField) {
    listingData[csmField] = demo[csmField];
  }

  // Compute average rating from reviews
  const reviews = demo.reviews || [];
  if (reviews.length > 0) {
    const avg = reviews.reduce((s, r) => s + r.rating, 0) / reviews.length;
    userData.rating = Math.round(avg * 10) / 10;
    listingData.rating = userData.rating;
  }

  if (DRY_RUN) {
    console.log(
      `   [dry-run] users/${uid} (${demo.name}) — ${
        reviews.length
      } reviews — ${csmField ? "csm=" + csmField : "no csm field"}`
    );
    return { created: 0, updated: 0, reviewsWritten: 0 };
  }

  const exists = (await db.collection("users").doc(uid).get()).exists;
  await db.collection("users").doc(uid).set(userData, { merge: true });
  await db
    .collection("provider_listings")
    .doc(listingId)
    .set(listingData, { merge: true });

  // Refresh reviews — delete old demo reviews for this expert, then write fresh.
  const existingReviews = await db
    .collection("reviews")
    .where("expertId", "==", uid)
    .where("isDemo", "==", true)
    .get();
  const batch = db.batch();
  for (const r of existingReviews.docs) batch.delete(r.ref);

  let reviewsWritten = 0;
  for (const r of reviews) {
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

  return { created: exists ? 0 : 1, updated: exists ? 1 : 0, reviewsWritten };
}

async function main() {
  console.log(`[Seed CSM Demos] DRY_RUN=${DRY_RUN}`);
  let totalCreated = 0;
  let totalUpdated = 0;
  let totalReviews = 0;
  let totalErrors = 0;

  for (const group of ALL_GROUPS) {
    console.log(
      `\n=== ${group.groupKey.toUpperCase()} (${group.payload.serviceType}) ===`
    );
    for (const demo of group.payload.demos) {
      try {
        const r = await writeOne(
          group.payload.serviceType,
          group.payload.parentCategory,
          group.csmField,
          demo
        );
        totalCreated += r.created;
        totalUpdated += r.updated;
        totalReviews += r.reviewsWritten;
        if (!DRY_RUN) {
          console.log(`   ✅ ${demo.name} — ${r.reviewsWritten} reviews`);
        }
      } catch (e) {
        totalErrors++;
        console.error(`   ❌ ${demo.name}: ${e.message}`);
      }
    }
  }

  console.log("\n[Seed CSM Demos] DONE.");
  console.log(`   created: ${totalCreated}`);
  console.log(`   updated: ${totalUpdated}`);
  console.log(`   reviews: ${totalReviews}`);
  console.log(`   errors:  ${totalErrors}`);
  process.exit(totalErrors > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error("[Seed CSM Demos] FATAL:", e);
  process.exit(1);
});
