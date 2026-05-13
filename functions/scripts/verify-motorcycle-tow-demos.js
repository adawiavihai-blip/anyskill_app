// Verify the 3 motorcycle-tow demos are queryable the way search uses.
const admin = require("firebase-admin");
const path = require("path");
const fs = require("fs");

const SA_PATH = path.join(__dirname, "..", "service-account.json");
if (fs.existsSync(SA_PATH)) {
  admin.initializeApp({ credential: admin.credential.cert(require(SA_PATH)) });
} else {
  admin.initializeApp({ projectId: "anyskill-6fdf3" });
}

(async () => {
  const db = admin.firestore();

  // Mirrors what CategoryResultsScreen queries for motorcycle towing.
  const listingsSnap = await db
    .collection("provider_listings")
    .where("serviceType", "==", "גרר אופנועים")
    .get();

  console.log(`\n=== provider_listings (serviceType=="גרר אופנועים") ===`);
  console.log(`Total matches: ${listingsSnap.size}`);
  for (const d of listingsSnap.docs) {
    const data = d.data();
    console.log(`\n  📋 listing id: ${d.id}`);
    console.log(`     uid:          ${data.uid}`);
    console.log(`     name:         ${data.name}`);
    console.log(`     rating:       ${data.rating} (${data.reviewsCount} reviews)`);
    console.log(`     pricePerHour: ₪${data.pricePerHour}`);
    console.log(`     isDemo:       ${data.isDemo}`);
    console.log(`     isHidden:     ${data.isHidden}`);
    console.log(`     isOnline:     ${data.isOnline}`);
    console.log(`     isVerified:   ${data.isVerified}`);
    console.log(`     gallery:      ${(data.gallery || []).length} images`);
    console.log(
      `     moto profile: ${data.motorcycleTowProfile ? "✅" : "❌"} ` +
        (data.motorcycleTowProfile
          ? `(${(data.motorcycleTowProfile.bikeTypeIds || []).length} bike types, ` +
            `radius ${data.motorcycleTowProfile.serviceArea?.radiusKm || "?"}km)`
          : "")
    );
  }

  // Also check the user docs.
  console.log(`\n=== users (isProvider==true, serviceType=="גרר אופנועים") ===`);
  const usersSnap = await db
    .collection("users")
    .where("isProvider", "==", true)
    .where("serviceType", "==", "גרר אופנועים")
    .get();
  console.log(`Total matches: ${usersSnap.size}`);
  for (const d of usersSnap.docs) {
    const data = d.data();
    console.log(`   ${d.id} — ${data.name} (rating ${data.rating})`);
  }

  // And the reviews.
  console.log(`\n=== reviews (per expert) ===`);
  for (const uid of ["demo_moto_tow_1", "demo_moto_tow_2", "demo_moto_tow_3"]) {
    const rs = await db.collection("reviews").where("expertId", "==", uid).get();
    console.log(`   ${uid}: ${rs.size} review(s)`);
  }

  process.exit(0);
})();
