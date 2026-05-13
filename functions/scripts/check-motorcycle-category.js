// One-off probe: confirm the "גרר אופנועים" category exists and
// inspect its doc id + parent linkage.
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
  const variants = ["גרר אופנועים", "גרר אופנוע", "Motorcycle Towing"];
  for (const v of variants) {
    const snap = await db.collection("categories").where("name", "==", v).limit(3).get();
    console.log(`[${v}] → ${snap.size} match(es)`);
    for (const d of snap.docs) {
      const data = d.data();
      console.log("   id:", d.id);
      console.log("   parentId:", data.parentId || "(none)");
      console.log("   iconUrl:", (data.iconUrl || "").slice(0, 80));
    }
  }
  // Find parent (תחבורה or similar)
  console.log("\n--- candidate parents ---");
  for (const p of ["תחבורה", "Transportation", "רכב", "אופנועים"]) {
    const snap = await db.collection("categories").where("name", "==", p).limit(2).get();
    if (snap.size > 0) {
      console.log(`[${p}] →`, snap.docs.map(d => d.id).join(", "));
    }
  }
  process.exit(0);
})();
