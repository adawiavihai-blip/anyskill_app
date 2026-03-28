/**
 * Temporary test script — checks whether Stripe Custom Connect accounts
 * are enabled on this platform profile.
 *
 * Usage (from the functions/ directory):
 *   node test_stripe_custom.js
 *
 * Delete this file after testing.
 */

require("dotenv").config({ path: ".env" });
const Stripe = require("stripe");

const key = process.env.STRIPE_SECRET_KEY;
if (!key) {
  console.error("ERROR: STRIPE_SECRET_KEY not found in functions/.env");
  process.exit(1);
}

console.log(`Using key: ${key.slice(0, 8)}...`);

const stripe = Stripe(key);

(async () => {
  try {
    const account = await stripe.accounts.create({
      type: "custom",
      country: "IL",
      capabilities: {
        transfers: { requested: true },
      },
    });
    console.log("\nSUCCESS — Custom accounts are enabled.");
    console.log("Account ID:", account.id);
    console.log("Deleting test account...");
    await stripe.accounts.del(account.id);
    console.log("Test account deleted.");
  } catch (err) {
    console.error("\nFAILED — Stripe error:");
    console.error("  Type   :", err.type);
    console.error("  Code   :", err.code);
    console.error("  Message:", err.message);
    if (err.raw) {
      console.error("  Raw    :", JSON.stringify(err.raw, null, 2));
    }
  }
})();
