/**
 * One-off READ-ONLY local script — inspect provider_carousel banners
 * and report which one (if any) the home tab will render at the top.
 *
 * Mirrors the matching predicate in:
 *   - lib/screens/home_tab.dart `_ProviderCarouselsRail`
 *   - lib/screens/admin_banners_v2/live_vip_panel.dart
 *
 * Run:
 *   cd functions
 *   node scripts/inspect-vip-banners.js
 *
 * Requires: `firebase login` (uses Application Default Credentials).
 */

const admin = require("firebase-admin");
const path = require("path");
const fs = require("fs");

const SA_PATH = path.join(__dirname, "..", "service-account.json");
if (fs.existsSync(SA_PATH)) {
  admin.initializeApp({
    credential: admin.credential.cert(require(SA_PATH)),
  });
} else {
  admin.initializeApp({ projectId: "anyskill-6fdf3" });
}

const db = admin.firestore();

function tsToIso(t) {
  if (!t) return null;
  if (typeof t.toDate === "function") return t.toDate().toISOString();
  return String(t);
}

(async () => {
  console.log("[Inspect] Scanning all banners (limit 200)…\n");
  const snap = await db.collection("banners").limit(200).get();

  const all = snap.docs.map((d) => ({ id: d.id, ...d.data() }));

  // ── 1. Group by placement ──────────────────────────────────────────
  const byPlacement = {};
  for (const b of all) {
    const p = b.placement || "(missing)";
    byPlacement[p] = (byPlacement[p] || 0) + 1;
  }
  console.log("== Banner counts by placement ==");
  for (const [p, n] of Object.entries(byPlacement)) {
    console.log(`  ${p.padEnd(22)} → ${n}`);
  }
  console.log("");

  // ── 2. provider_carousel — full eligibility check ──────────────────
  const pc = all.filter((b) => b.placement === "provider_carousel");
  console.log(`== provider_carousel docs: ${pc.length} ==`);
  if (pc.length === 0) {
    console.log("  ⚠️  No `provider_carousel` banners exist.");
  }

  const now = new Date();
  const eligible = [];
  for (const b of pc) {
    const isActive = b.isActive === undefined ? true : b.isActive === true;
    const expiresAt = b.expiresAt && b.expiresAt.toDate ? b.expiresAt.toDate() : null;
    const expired = expiresAt && !(expiresAt > now);
    const cfg = b.providerCarousel;
    const ids =
      cfg && Array.isArray(cfg.providerIds)
        ? cfg.providerIds.filter((x) => typeof x === "string")
        : [];
    const enoughProviders = ids.length >= 2;
    const reasonsBlocked = [];
    if (!isActive) reasonsBlocked.push("isActive=false");
    if (expired) reasonsBlocked.push(`expiresAt past (${tsToIso(b.expiresAt)})`);
    if (cfg == null || typeof cfg !== "object")
      reasonsBlocked.push("providerCarousel field missing or wrong shape");
    if (!enoughProviders)
      reasonsBlocked.push(`providerIds.length=${ids.length} (need ≥2)`);
    const passes = reasonsBlocked.length === 0;
    if (passes) eligible.push({ b, ids });

    console.log(`  • ${b.id}`);
    console.log(`    title: ${b.title || "(empty)"}`);
    console.log(`    order: ${b.order ?? "(none)"}`);
    console.log(`    isActive: ${b.isActive ?? "(missing → defaults true)"}`);
    console.log(`    expiresAt: ${tsToIso(b.expiresAt) || "(none)"}`);
    console.log(`    providerCarousel: ${cfg ? "present" : "MISSING"}`);
    if (cfg) {
      console.log(`      providerIds.length: ${ids.length}`);
      console.log(`      providerIds: ${JSON.stringify(ids)}`);
      console.log(`      rotationDurationMs: ${cfg.rotationDurationMs}`);
      console.log(`      sortMode: ${cfg.sortMode}`);
      console.log(`      transition: ${cfg.transition}`);
    }
    console.log(`    eligible-for-home-rail: ${passes ? "✅ YES" : "❌ NO"}`);
    if (!passes) console.log(`      blockers: ${reasonsBlocked.join("; ")}`);
    console.log("");
  }

  // ── 3. Sort eligible by order (same client-side sort the rail does) ─
  eligible.sort((a, b) => {
    const ao = (a.b.order ?? 999) | 0;
    const bo = (b.b.order ?? 999) | 0;
    return ao - bo;
  });

  console.log("== What the home tab + VIP panel will show ==");
  if (eligible.length === 0) {
    console.log("  ⚠️  Zero eligible banners. Home tab shows nothing for this rail.");
    console.log("      The new VIP panel will show the empty-state card.");
  } else {
    const winner = eligible[0];
    console.log(`  ✅ Winner: ${winner.b.id} ("${winner.b.title || "(empty)"}")`);
    console.log(`     ${winner.ids.length} providers in rotation`);

    // Resolve provider names for the winner so we can prove sync
    console.log("");
    console.log("== Resolving provider names for winner ==");
    for (const uid of winner.ids) {
      try {
        const u = await db.collection("users").doc(uid).get();
        const d = u.exists ? u.data() : null;
        if (d) {
          const photo = d.profileImage ? "(has photo)" : "(no photo)";
          console.log(`  • ${uid}  →  ${d.name || "(no name)"} [${d.serviceType || "—"}] ${photo}`);
        } else {
          console.log(`  • ${uid}  →  ⚠️  user doc MISSING`);
        }
      } catch (e) {
        console.log(`  • ${uid}  →  error: ${e.message}`);
      }
    }
  }

  // ── 4. Legacy home_carousel inventory (in case the user's "VIP banner" is actually this) ──
  const hc = all.filter((b) => b.placement === "home_carousel");
  if (hc.length > 0) {
    console.log("");
    console.log("== Legacy `home_carousel` banners (NOT shown in VIP tab) ==");
    for (const b of hc) {
      const active = b.isActive === undefined ? true : b.isActive === true;
      console.log(
        `  • ${b.id}  active=${active}  title="${b.title || ""}"  ` +
        `providerId=${b.providerId || "(none)"}  providerName=${b.providerName || "(none)"}`,
      );
    }
    console.log(
      "  ℹ️  If your 'top VIP banner' on home tab is actually one of these,",
    );
    console.log(
      "     it's a single-provider gradient card (legacy v1), NOT the rotating",
    );
    console.log(
      "     provider_carousel rail. The new VIP tab does not target this type.",
    );
  }

  process.exit(0);
})().catch((e) => {
  console.error("[Inspect] Fatal:", e);
  process.exit(1);
});
