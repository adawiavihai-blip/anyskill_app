/**
 * payments.js — Stripe Connect + Morning (Green Invoice) Cloud Functions
 *
 * Payment Architecture: "Separate Charges and Transfers" (true escrow)
 * ─────────────────────────────────────────────────────────────────────
 *  1. Customer pays → funds land on the AnySkill PLATFORM Stripe account.
 *  2. Funds sit there until the job is confirmed complete (no 7-day auth limit).
 *  3. On completion → CF calls stripe.transfers.create() to push net amount
 *     to the provider's Stripe Express connected account.
 *  4. Platform retains the commission (application_fee) automatically.
 *
 * This is the Wolt/Uber Eats model (not Destination Charges, which transfers
 * at payment time and defeats the escrow purpose).
 *
 * Secrets — set ONCE via CLI, never in code:
 *   firebase functions:secrets:set STRIPE_SECRET_KEY
 *   firebase functions:secrets:set STRIPE_WEBHOOK_SECRET
 *   firebase functions:secrets:set MORNING_API_KEY
 *   firebase functions:secrets:set MORNING_SECRET
 */

"use strict";

const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret }                  = require("firebase-functions/params");
const admin                             = require("firebase-admin");

// STRIPE_SECRET_KEY is read from process.env (set via functions/.env file).
// All other secrets remain in Secret Manager (they were working).
const STRIPE_WEBHOOK_SECRET = defineSecret("STRIPE_WEBHOOK_SECRET");
const MORNING_API_KEY       = defineSecret("MORNING_API_KEY");
const MORNING_SECRET        = defineSecret("MORNING_SECRET");

/**
 * Returns the Stripe secret key from the environment.
 * Logs the first 4 chars so Firebase Logs confirm the correct key was loaded.
 * Throws a clear Error if the variable is missing — surfaced as HttpsError.
 */
function getStripeKey() {
  const key = process.env.STRIPE_SECRET_KEY;
  if (!key || key.length < 20) {
    const hint = key ? `(len=${key.length})` : "(undefined)";
    console.error(
      `[Stripe] STRIPE_SECRET_KEY is missing or too short ${hint}. ` +
      "Add it to functions/.env and redeploy.",
    );
    throw new Error("STRIPE_SECRET_KEY not configured");
  }
  console.log(`[Stripe] key OK: ${key.slice(0, 4)}...${key.slice(-4)}`);
  return key;
}

// admin.initializeApp() is called once in index.js — do NOT call it here.
const db = () => admin.firestore();

// ─────────────────────────────────────────────────────────────────────────────
// INTERNAL HELPERS
// ─────────────────────────────────────────────────────────────────────────────

/** Convert ₪ shekels → agorot (Stripe's smallest ILS unit, like cents). */
function toAgorot(shekel) {
  return Math.round(shekel * 100);
}

/** Get or create a Stripe Customer for a Firebase user. */
async function getOrCreateCustomer(stripe, uid) {
  const ref  = db().collection("users").doc(uid);
  const snap = await ref.get();
  const data = snap.data() || {};

  if (data.stripeCustomerId) return data.stripeCustomerId;

  const customer = await stripe.customers.create({
    email:    data.email    || "",
    name:     data.fullName || data.name || "",
    metadata: { firebaseUid: uid },
  });

  await ref.update({ stripeCustomerId: customer.id });
  return customer.id;
}

/** Fetch Morning (Green Invoice) JWT token. */
async function getMorningToken(apiKey, secret) {
  const res = await fetch("https://api.greeninvoice.co.il/api/v1/account/token", {
    method:  "POST",
    headers: { "Content-Type": "application/json" },
    body:    JSON.stringify({ id: apiKey, secret }),
  });
  const json = await res.json();
  if (!json.token) throw new Error(`Morning auth failed: ${JSON.stringify(json)}`);
  return json.token;
}

/**
 * Create a Morning tax invoice (חשבונית מס).
 * documentType 320 = Tax Invoice | 400 = Tax Invoice + Receipt
 */
async function createMorningInvoice(token, { fromName, toName, toEmail, amountShekel, description, documentType = 320 }) {
  const res = await fetch("https://api.greeninvoice.co.il/api/v1/documents", {
    method:  "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      description,
      type:     documentType,
      lang:     "he",
      currency: "ILS",
      vatType:  0,
      client:   { name: toName, emails: toEmail ? [toEmail] : [] },
      income: [{
        description,
        quantity: 1,
        price:    amountShekel,
        currency: "ILS",
        vatType:  0,
      }],
      payment: [{ type: 1, price: amountShekel, currency: "ILS" }],
      remarks: `מופק אוטומטית ע"י AnySkill — ${new Date().toLocaleDateString("he-IL")}`,
    }),
  });
  const json = await res.json();
  if (!json.id) throw new Error(`Morning invoice failed: ${JSON.stringify(json)}`);
  return { id: json.id, url: json.url || null };
}

// ─────────────────────────────────────────────────────────────────────────────
// 1.  createPaymentIntent
//     Called by Flutter before showing the Stripe Payment Sheet.
//     Returns { clientSecret, jobId } to the client.
// ─────────────────────────────────────────────────────────────────────────────
exports.createPaymentIntent = onCall(
  { cors: true },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "נדרשת התחברות.");

    const { quoteId } = request.data;
    if (!quoteId) throw new HttpsError("invalid-argument", "quoteId חסר.");

    const stripe = require("stripe")(getStripeKey());

    // ── Load quote ─────────────────────────────────────────────────────────
    const quoteSnap = await db().collection("quotes").doc(quoteId).get();
    if (!quoteSnap.exists)       throw new HttpsError("not-found",        "הצעת המחיר לא נמצאה.");
    const quote = quoteSnap.data();
    if (quote.status === "paid") throw new HttpsError("already-exists",   "הצעת המחיר כבר שולמה.");
    if (quote.clientId !== request.auth.uid)
                                  throw new HttpsError("permission-denied","אין גישה להצעה זו.");

    // ── Load commission % ──────────────────────────────────────────────────
    const adminSnap   = await db().collection("admin").doc("admin").collection("settings").doc("settings").get();
    const feePct      = (adminSnap.data() || {}).feePercentage || 0.10;
    const commission  = parseFloat((quote.amount * feePct).toFixed(2));
    const netExpert   = parseFloat((quote.amount - commission).toFixed(2));

    // ── Get or create Stripe Customer ──────────────────────────────────────
    const customerId = await getOrCreateCustomer(stripe, request.auth.uid);

    // ── Create PaymentIntent (capture to platform — true escrow) ───────────
    // No transfer_data here; funds stay on platform until releaseEscrow() fires.
    const pi = await stripe.paymentIntents.create({
      amount:                    toAgorot(quote.amount),
      currency:                  "ils",
      customer:                  customerId,
      automatic_payment_methods: { enabled: true },
      // transfer_group links this PI to future stripe.transfers.create() calls
      transfer_group:            `job_${quoteId}`,
      metadata: {
        quoteId,
        clientId:   request.auth.uid,
        providerId: quote.providerId,
        commission: String(commission),
        netExpert:  String(netExpert),
      },
    });

    // ── Pre-create job doc (status: awaiting_payment) ──────────────────────
    const userSnap   = await db().collection("users").doc(request.auth.uid).get();
    const userData   = userSnap.data() || {};
    const provSnap   = await db().collection("users").doc(quote.providerId).get();
    const provData   = provSnap.data() || {};

    const jobRef = db().collection("jobs").doc();
    await jobRef.set({
      expertId:              quote.providerId,
      expertName:            quote.providerName || provData.fullName || provData.name || "",
      customerId:            request.auth.uid,
      customerName:          userData.fullName  || userData.name    || "",
      totalAmount:           quote.amount,
      netAmountForExpert:    netExpert,
      commission,
      description:           quote.description || "",
      status:                "awaiting_payment",
      source:                "stripe",
      quoteId,
      chatRoomId:            quote.chatRoomId || "",
      stripePaymentIntentId: pi.id,
      stripeTransferGroup:   `job_${quoteId}`,
      isLocked:              false,
      clientReviewDone:      false,
      providerReviewDone:    false,
      createdAt:             admin.firestore.FieldValue.serverTimestamp(),
    });

    // Store pending job reference on quote for webhook correlation
    await db().collection("quotes").doc(quoteId).update({
      pendingJobId:          jobRef.id,
      stripePaymentIntentId: pi.id,
    });

    return { clientSecret: pi.client_secret, jobId: jobRef.id };
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// 2.  handleStripeWebhook
//     Stripe → this HTTPS endpoint via Dashboard → Developers → Webhooks.
//     Register URL: https://us-central1-anyskill-6fdf3.cloudfunctions.net/handleStripeWebhook
//     Events to listen: payment_intent.succeeded, payment_intent.payment_failed,
//                       account.updated
// ─────────────────────────────────────────────────────────────────────────────
exports.handleStripeWebhook = onRequest(
  { secrets: [STRIPE_WEBHOOK_SECRET] },
  async (req, res) => {
    const stripe = require("stripe")(getStripeKey());
    const sig    = req.headers["stripe-signature"];

    let event;
    try {
      event = stripe.webhooks.constructEvent(req.rawBody, sig, STRIPE_WEBHOOK_SECRET.value());
    } catch (err) {
      console.error("Webhook signature verification failed:", err.message);
      return res.status(400).send(`Webhook Error: ${err.message}`);
    }

    // ── payment_intent.succeeded ───────────────────────────────────────────
    if (event.type === "payment_intent.succeeded") {
      const pi = event.data.object;

      const jobSnaps = await db()
        .collection("jobs")
        .where("stripePaymentIntentId", "==", pi.id)
        .limit(1)
        .get();

      if (jobSnaps.empty) {
        console.warn("No job doc for PI:", pi.id);
        return res.status(200).send("ok — no job");
      }

      const jobDoc  = jobSnaps.docs[0];
      const job     = jobDoc.data();

      // Idempotency guard
      if (job.status !== "awaiting_payment") {
        return res.status(200).send("already processed");
      }

      const batch = db().batch();

      batch.update(jobDoc.ref, {
        status: "paid_escrow",
        paidAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      if (job.quoteId) {
        batch.update(db().collection("quotes").doc(job.quoteId), {
          status: "paid",
          jobId:  jobDoc.id,
          paidAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      batch.set(db().collection("platform_earnings").doc(), {
        jobId:          jobDoc.id,
        amount:         job.commission,
        sourceExpertId: job.expertId,
        stripeIntentId: pi.id,
        timestamp:      admin.firestore.FieldValue.serverTimestamp(),
        status:         "pending_escrow",
      });

      batch.set(db().collection("transactions").doc(), {
        senderId:       job.customerId,
        senderName:     job.customerName,
        receiverId:     job.expertId,
        receiverName:   job.expertName,
        amount:         job.totalAmount,
        type:           "quote_payment",
        jobId:          jobDoc.id,
        quoteId:        job.quoteId || "",
        payoutStatus:   "pending",
        stripeIntentId: pi.id,
        timestamp:      admin.firestore.FieldValue.serverTimestamp(),
      });

      if (job.chatRoomId) {
        batch.set(
          db().collection("chats").doc(job.chatRoomId).collection("messages").doc(),
          {
            senderId:  "system",
            message:   `✅ ₪${Number(job.totalAmount).toFixed(0)} שולמו ונעולים באסקרו. ניתן להתחיל בעבודה!`,
            type:      "system_alert",
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
          }
        );
      }

      await batch.commit();
    }

    // ── payment_intent.payment_failed ──────────────────────────────────────
    if (event.type === "payment_intent.payment_failed") {
      const pi = event.data.object;

      const jobSnaps = await db()
        .collection("jobs")
        .where("stripePaymentIntentId", "==", pi.id)
        .limit(1)
        .get();

      if (!jobSnaps.empty) {
        await jobSnaps.docs[0].ref.update({
          status:        "payment_failed",
          failureReason: pi.last_payment_error?.message || "unknown",
        });
      }
    }

    // ── account.updated — Custom Connect KYC status sync ─────────────────
    if (event.type === "account.updated") {
      const account  = event.data.object;
      const uid      = account.metadata?.firebaseUid;
      if (!uid) return res.status(200).send("no uid");

      const currentlyDue   = account.requirements?.currently_due   || [];
      const pastDue        = account.requirements?.past_due        || [];
      const pendingVerif   = account.requirements?.pending_verification || [];
      const disabledReason = account.requirements?.disabled_reason || null;
      const payoutsEnabled = account.payouts_enabled  || false;
      const detailsSubmitted = account.details_submitted || false;

      // Firestore sync — single source of truth for Flutter UI
      const batch = db().batch();
      batch.update(db().collection("users").doc(uid), {
        stripePayoutsEnabled:       payoutsEnabled,
        stripeDetailsSubmitted:     detailsSubmitted,
        stripeOnboardingComplete:   detailsSubmitted && payoutsEnabled,
        stripeRequirementsDue:      currentlyDue,
        stripeRequirementsPastDue:  pastDue,
        stripePendingVerification:  pendingVerif,
        stripeDisabledReason:       disabledReason,
        stripeStatusUpdatedAt:      admin.firestore.FieldValue.serverTimestamp(),
      });

      // In-app notification if Stripe needs more documents
      if (pastDue.length > 0 || disabledReason) {
        batch.set(db().collection("notifications").doc(), {
          userId:    uid,
          title:     "נדרש אימות נוסף",
          body:      "Stripe דורשת מסמכים נוספים כדי להפעיל את חשבון התשלומים שלך. פתח את הגדרות הארנק.",
          isRead:    false,
          type:      "stripe_verification",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      // Notify on full activation
      if (payoutsEnabled && detailsSubmitted) {
        batch.set(db().collection("notifications").doc(), {
          userId:    uid,
          title:     "חשבון התשלומים פעיל!",
          body:      "חשבון הבנק שלך אומת בהצלחה. אתה יכול לקבל תשלומים עכשיו.",
          isRead:    false,
          type:      "stripe_activated",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
    }

    return res.status(200).send("ok");
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// 3.  releaseEscrow
//     Called when the customer confirms job completion.
//     Transfers net amount to provider's Express account + generates invoices.
// ─────────────────────────────────────────────────────────────────────────────
exports.releaseEscrow = onCall(
  { cors: true, secrets: [MORNING_API_KEY, MORNING_SECRET] },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "נדרשת התחברות.");

    const { jobId } = request.data;
    if (!jobId) throw new HttpsError("invalid-argument", "jobId חסר.");

    const jobSnap = await db().collection("jobs").doc(jobId).get();
    if (!jobSnap.exists) throw new HttpsError("not-found", "העבודה לא נמצאה.");
    const job = jobSnap.data();

    if (job.customerId !== request.auth.uid && job.expertId !== request.auth.uid) {
      throw new HttpsError("permission-denied", "אין גישה להזמנה זו.");
    }

    if (job.status === "completed") {
      throw new HttpsError("already-exists", "ההזמנה כבר הושלמה.");
    }

    if (!["paid_escrow", "expert_completed"].includes(job.status)) {
      throw new HttpsError("failed-precondition", `לא ניתן לשחרר מסטטוס: ${job.status}`);
    }

    // Admin dispute lock guard
    if (job.isLocked) {
      throw new HttpsError("failed-precondition", "ההזמנה נעולה לצורך בדיקת מחלוקת. פנה לתמיכת AnySkill.");
    }

    const stripe = require("stripe")(getStripeKey());

    // ── Verify the PI was actually captured ───────────────────────────────
    const pi = await stripe.paymentIntents.retrieve(job.stripePaymentIntentId);
    if (pi.status !== "succeeded") {
      throw new HttpsError("failed-precondition", "התשלום לא אושר ע\"י Stripe. פנה לתמיכה.");
    }

    // ── Load provider's Stripe Express account ─────────────────────────────
    const provSnap = await db().collection("users").doc(job.expertId).get();
    const provData = provSnap.data() || {};

    if (!provData.stripeAccountId || !provData.stripePayoutsEnabled) {
      throw new HttpsError(
        "failed-precondition",
        "הספק טרם הגדיר חשבון בנק לקבלת תשלומים. אנא פנה לתמיכה.",
      );
    }

    // ── Transfer net amount to provider ───────────────────────────────────
    // Separate Charges and Transfers: funds already on platform account,
    // now we push the net portion to the provider's Express account.
    const transfer = await stripe.transfers.create({
      amount:         toAgorot(job.netAmountForExpert),
      currency:       "ils",
      destination:    provData.stripeAccountId,
      transfer_group: job.stripeTransferGroup || `job_${job.quoteId}`,
      metadata:       { jobId, expertId: job.expertId, customerId: job.customerId },
    });

    // ── Generate Morning invoices (non-critical — don't block on failure) ──
    let invoiceAId = null, invoiceAUrl = null;
    let invoiceBId = null, invoiceBUrl = null;

    try {
      const morningToken = await getMorningToken(MORNING_API_KEY.value(), MORNING_SECRET.value());

      const custSnap = await db().collection("users").doc(job.customerId).get();
      const custData = custSnap.data() || {};

      // Document A: Provider → Customer (full service amount)
      const invoiceA = await createMorningInvoice(morningToken, {
        fromName:     provData.fullName || provData.businessName || "ספק שירות",
        toName:       custData.fullName || custData.name || "לקוח",
        toEmail:      custData.email   || "",
        amountShekel: job.totalAmount,
        description:  job.description  || "שירות דרך AnySkill",
        documentType: 320,
      });
      invoiceAId  = invoiceA.id;
      invoiceAUrl = invoiceA.url;

      // Document B: AnySkill → Provider (commission only)
      const invoiceB = await createMorningInvoice(morningToken, {
        fromName:     "AnySkill",
        toName:       provData.fullName || provData.businessName || "ספק",
        toEmail:      provData.email   || "",
        amountShekel: job.commission,
        description:  `עמלת פלטפורמה AnySkill — הזמנה #${jobId.slice(-6).toUpperCase()}`,
        documentType: 320,
      });
      invoiceBId  = invoiceB.id;
      invoiceBUrl = invoiceB.url;
    } catch (invoiceErr) {
      console.error("Morning invoice generation failed (non-critical):", invoiceErr.message);
    }

    // ── Commit to Firestore ────────────────────────────────────────────────
    const batch = db().batch();

    batch.update(db().collection("jobs").doc(jobId), {
      status:           "completed",
      completedAt:      admin.firestore.FieldValue.serverTimestamp(),
      stripeTransferId: transfer.id,
      invoiceAId,
      invoiceAUrl,
      invoiceBId,
      invoiceBUrl,
    });

    // Settle platform earnings record
    const earningsSnap = await db()
      .collection("platform_earnings")
      .where("jobId", "==", jobId)
      .limit(1)
      .get();
    if (!earningsSnap.empty) {
      batch.update(earningsSnap.docs[0].ref, { status: "settled", settledAt: admin.firestore.FieldValue.serverTimestamp() });
    }

    // Update transaction payout status
    const txSnap = await db()
      .collection("transactions")
      .where("jobId", "==", jobId)
      .limit(1)
      .get();
    if (!txSnap.empty) {
      batch.update(txSnap.docs[0].ref, { payoutStatus: "completed" });
    }

    await batch.commit();

    // System chat message
    if (job.chatRoomId) {
      await db().collection("chats").doc(job.chatRoomId).collection("messages").add({
        senderId:  "system",
        message:   "🎉 העבודה הושלמה! התשלום שוחרר לספק.",
        type:      "system_alert",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    return { success: true, transferId: transfer.id, invoiceAUrl, invoiceBUrl };
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// 4.  onboardProvider  (onRequest — accepts direct HTTP POST with Bearer token)
//     Creates (or retrieves) a Stripe Express connected account for a provider,
//     then generates an AccountLink URL and returns { url } so the Flutter app
//     can redirect the user to Stripe's hosted onboarding page.
//
//     Request body (JSON): { returnUrl, refreshUrl }
//     Auth: Authorization: Bearer <Firebase ID token>
// ─────────────────────────────────────────────────────────────────────────────
exports.onboardProvider = onRequest(
  { cors: false },
  async (req, res) => {
    // ── CORS — allow the web app origin and preflight requests ───────────────
    const allowedOrigins = [
      "https://anyskill-6fdf3.web.app",
      "https://anyskill-6fdf3.firebaseapp.com",
    ];
    const origin = req.headers["origin"] || "";
    if (allowedOrigins.includes(origin)) {
      res.set("Access-Control-Allow-Origin", origin);
    } else {
      res.set("Access-Control-Allow-Origin", "https://anyskill-6fdf3.web.app");
    }
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
    res.set("Access-Control-Max-Age", "3600");

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    // ── 1. Verify Firebase ID token from Authorization header ─────────────────
    const authHeader = req.headers["authorization"] || "";
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing or invalid Authorization header" });
      return;
    }
    const idToken = authHeader.slice(7);
    let uid;
    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      uid = decoded.uid;
    } catch (authErr) {
      console.error("[onboardProvider] Token verification failed:", authErr.message);
      res.status(401).json({ error: "Invalid or expired ID token" });
      return;
    }

    try {
      // ── 2. Key check ────────────────────────────────────────────────────────
      console.log("[Stripe] Environment Check: " +
        (process.env.STRIPE_SECRET_KEY ? "Key Loaded" : "Key MISSING"));
      const stripe = require("stripe")(getStripeKey());

      // ── 3. Parse returnUrl / refreshUrl from request body ──────────────────
      const { returnUrl, refreshUrl } = req.body || {};
      if (!returnUrl || !refreshUrl) {
        res.status(400).json({ error: "returnUrl and refreshUrl are required" });
        return;
      }

      // ── 4. Load user — get or create Stripe Express account ───────────────
      const userRef  = db().collection("users").doc(uid);
      const userSnap = await userRef.get();
      const userData = userSnap.data() || {};

      let stripeAccountId = userData.stripeAccountId;

      if (!stripeAccountId) {
        const providerCountry = ((userData.country) || "IL").toUpperCase();
        console.log("[onboardProvider] Creating custom account for uid:", uid,
          "| country:", providerCountry);

        const accountParams = {
          type:             "custom",
          country:          providerCountry,
          default_currency: "ils",
          capabilities: {
            transfers: { requested: true },
          },
          business_profile: {
            url: "https://anyskill-6fdf3.web.app",
          },
          metadata: { firebaseUid: uid },
        };
        if (userData.email) accountParams.email = userData.email;

        const account = await stripe.accounts.create(accountParams);
        stripeAccountId = account.id;
        console.log("[onboardProvider] Account created:", stripeAccountId);

        await userRef.update({
          stripeAccountId,
          stripeOnboardingComplete: false,
          stripePayoutsEnabled:     false,
          stripeDetailsSubmitted:   false,
        });
      } else {
        console.log("[onboardProvider] Existing account:", stripeAccountId);
      }

      // ── 5. Create AccountLink (hosted onboarding URL) ──────────────────────
      const accountLink = await stripe.accountLinks.create({
        account:     stripeAccountId,
        refresh_url: refreshUrl,
        return_url:  returnUrl,
        type:        "account_onboarding",
      });
      console.log("[onboardProvider] AccountLink created for:", stripeAccountId);

      res.status(200).json({ url: accountLink.url });

    } catch (err) {
      console.error("[onboardProvider] Error:", {
        type:    err.type,
        code:    err.code,
        message: err.message,
        param:   err.param,
        raw:     err.raw ? JSON.stringify(err.raw) : undefined,
      });
      res.status(500).json({ error: err.message || "שגיאה ביצירת חשבון. ראה לוגים." });
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// 4b. updateStripeAccount
//     Called from Flutter after the provider fills in their personal details
//     and IBAN in the app's own UI.
//
//     Expected request.data:
//       stripeAccountId  — from onboardProvider (stored in Firestore)
//       firstName        — individual first name
//       lastName         — individual last name
//       dobDay           — date of birth day   (int)
//       dobMonth         — date of birth month (int)
//       dobYear          — date of birth year  (int)
//       idNumber         — national ID / passport number
//       ibanNumber       — full IBAN string (e.g. "PT50...")
//       ipAddress        — client IP for Stripe ToS acceptance (request.rawRequest.ip)
//
//     Returns { success: true, requirementsRemaining: [...] }
// ─────────────────────────────────────────────────────────────────────────────
exports.updateStripeAccount = onCall(
  { cors: true },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "נדרשת התחברות.");

    const uid = request.auth.uid;
    const {
      stripeAccountId,
      firstName, lastName,
      dobDay, dobMonth, dobYear,
      idNumber,
      ibanNumber,
      ipAddress,
    } = request.data || {};

    // ── Input validation ────────────────────────────────────────────────────
    if (!stripeAccountId) throw new HttpsError("invalid-argument", "stripeAccountId חסר.");
    if (!firstName || !lastName) throw new HttpsError("invalid-argument", "שם מלא חסר.");
    if (!dobDay || !dobMonth || !dobYear) throw new HttpsError("invalid-argument", "תאריך לידה חסר.");
    if (!ibanNumber) throw new HttpsError("invalid-argument", "IBAN חסר.");

    // ── Security: verify the accountId belongs to this Firebase user ────────
    const userSnap = await db().collection("users").doc(uid).get();
    const userData = userSnap.data() || {};
    if (userData.stripeAccountId !== stripeAccountId) {
      throw new HttpsError("permission-denied", "חשבון Stripe אינו שייך למשתמש זה.");
    }

    const stripe = require("stripe")(getStripeKey());

    try {
      // ── 1. Update individual details + accept Stripe ToS ─────────────────
      const updated = await stripe.accounts.update(stripeAccountId, {
        business_type: "individual",
        individual: {
          first_name: firstName,
          last_name:  lastName,
          dob: {
            day:   Number(dobDay),
            month: Number(dobMonth),
            year:  Number(dobYear),
          },
          ...(idNumber ? { id_number: idNumber } : {}),
          // Address defaults to platform country if provider hasn't supplied one yet
          address: {
            country: (userData.country || "PT").toUpperCase(),
          },
        },
        // ToS acceptance is mandatory for Custom accounts
        tos_acceptance: {
          date: Math.floor(Date.now() / 1000),
          ip:   ipAddress || "127.0.0.1",
        },
      });

      // ── 2. Attach IBAN as the payout bank account ─────────────────────────
      // Stripe accepts the raw IBAN string as account_number for EU countries.
      await stripe.accounts.createExternalAccount(stripeAccountId, {
        external_account: {
          object:               "bank_account",
          country:              (userData.country || "PT").toUpperCase(),
          currency:             "eur",
          account_holder_name:  `${firstName} ${lastName}`,
          account_holder_type:  "individual",
          account_number:       ibanNumber.replace(/\s/g, ""), // strip spaces
        },
      });

      // ── 3. Sync status back to Firestore ──────────────────────────────────
      await db().collection("users").doc(uid).update({
        stripeDetailsSubmitted:   true,
        stripePayoutsEnabled:     updated.payouts_enabled     || false,
        stripeOnboardingComplete: updated.details_submitted   || false,
        stripeRequirementsDue:    updated.requirements?.currently_due || [],
      });

      return {
        success:              true,
        payoutsEnabled:       updated.payouts_enabled   || false,
        detailsSubmitted:     updated.details_submitted || false,
        requirementsRemaining: updated.requirements?.currently_due || [],
      };

    } catch (err) {
      console.error("updateStripeAccount error:", {
        type: err.type, code: err.code, message: err.message, param: err.param,
      });
      throw new HttpsError("internal", err.message || "שגיאה בעדכון חשבון Stripe.");
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// 5.  processRefund
//     Admin or customer requests a partial/full refund.
//     Cancels the escrow transfer if not yet released, or issues Stripe refund.
// ─────────────────────────────────────────────────────────────────────────────
exports.processRefund = onCall(
  { cors: true },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "נדרשת התחברות.");

    const { jobId, amountShekel, reason } = request.data || {};
    if (!jobId) throw new HttpsError("invalid-argument", "jobId חסר.");

    const stripe  = require("stripe")(getStripeKey());
    const jobSnap = await db().collection("jobs").doc(jobId).get();
    if (!jobSnap.exists) throw new HttpsError("not-found", "העבודה לא נמצאה.");
    const job = jobSnap.data();

    // Auth check: admin or the customer
    const callerSnap = await db().collection("users").doc(request.auth.uid).get();
    const isAdmin    = (callerSnap.data() || {}).isAdmin === true;
    if (!isAdmin && job.customerId !== request.auth.uid) {
      throw new HttpsError("permission-denied", "אין הרשאה להגיש החזר.");
    }

    if (!job.stripePaymentIntentId) {
      throw new HttpsError("failed-precondition", "אין תשלום Stripe מקושר להזמנה זו.");
    }

    const fullAmount    = job.totalAmount;
    const refundShekel  = amountShekel || fullAmount;
    const isFullRefund  = refundShekel >= fullAmount;

    const refund = await stripe.refunds.create({
      payment_intent: job.stripePaymentIntentId,
      amount:         toAgorot(refundShekel),
      reason:         "requested_by_customer",
      metadata:       { jobId, requestedBy: request.auth.uid, reason: reason || "" },
    });

    await db().collection("jobs").doc(jobId).update({
      status:         isFullRefund ? "refunded" : "partial_refund",
      stripeRefundId: refund.id,
      refundedAmount: refundShekel,
      refundedAt:     admin.firestore.FieldValue.serverTimestamp(),
      refundReason:   reason || "",
      isLocked:       false,
    });

    // Notify customer
    await db().collection("notifications").add({
      userId:    job.customerId,
      title:     isFullRefund ? "החזר כספי מלא אושר" : "החזר כספי חלקי אושר",
      body:      `₪${refundShekel.toFixed(0)} יוחזרו לאמצעי התשלום שלך תוך 5–10 ימי עסקים.`,
      isRead:    false,
      type:      "refund",
      jobId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true, refundId: refund.id, refundedAmount: refundShekel };
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// listPaymentMethods — return the customer's saved Stripe cards
// ─────────────────────────────────────────────────────────────────────────────
exports.listPaymentMethods = onCall(
  { cors: true },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required");
    const stripe = require("stripe")(getStripeKey());

    const customerId = await getOrCreateCustomer(stripe, request.auth.uid);
    const { data } = await stripe.paymentMethods.list({
      customer: customerId,
      type:     "card",
    });

    return {
      cards: data.map((pm) => ({
        id:       pm.id,
        brand:    pm.card.brand,      // "visa" | "mastercard" | "amex" | ...
        last4:    pm.card.last4,
        expMonth: pm.card.exp_month,
        expYear:  pm.card.exp_year,
      })),
    };
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// createSetupIntent — let a customer save a card without paying now
// ─────────────────────────────────────────────────────────────────────────────
exports.createSetupIntent = onCall(
  { cors: true },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required");
    const stripe = require("stripe")(getStripeKey());

    const customerId = await getOrCreateCustomer(stripe, request.auth.uid);
    const setupIntent = await stripe.setupIntents.create({
      customer:             customerId,
      payment_method_types: ["card"], // required for Payment Sheet compatibility
      usage:                "off_session", // card can be charged without customer present
    });

    return { clientSecret: setupIntent.client_secret };
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// createStripeSetupSession — web-only: Stripe-hosted card-save checkout
// ─────────────────────────────────────────────────────────────────────────────
// Called by StripeService._addPaymentMethodWeb() when kIsWeb == true.
// Returns a Stripe Checkout Session URL in 'setup' mode so the user can
// securely add a card on Stripe's hosted page without any SDK on the client.
exports.createStripeSetupSession = onCall(
  { cors: true },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required");
    const stripe = require("stripe")(getStripeKey());

    const customerId = await getOrCreateCustomer(stripe, request.auth.uid);
    const session = await stripe.checkout.sessions.create({
      customer:             customerId,
      mode:                 "setup",
      payment_method_types: ["card"],
      // User is returned to the app after completing or cancelling.
      success_url: "https://anyskill-6fdf3.web.app/?stripe_setup=success",
      cancel_url:  "https://anyskill-6fdf3.web.app/?stripe_setup=cancel",
    });

    return { url: session.url };
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// createStripePaymentSession — web-only: Stripe-hosted payment checkout
// ─────────────────────────────────────────────────────────────────────────────
// Called by StripeService._payQuoteWeb() when kIsWeb == true.
// Creates a Stripe Checkout Session in 'payment' mode for the given quote.
exports.createStripePaymentSession = onCall(
  { cors: true },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required");
    const { quoteId } = request.data;
    if (!quoteId) throw new HttpsError("invalid-argument", "quoteId required");

    const stripe = require("stripe")(getStripeKey());
    const db     = admin.firestore();

    // Load quote to get amount and expert details.
    const quoteSnap = await db.collection("quotes").doc(quoteId).get();
    if (!quoteSnap.exists) throw new HttpsError("not-found", "Quote not found");
    const quote = quoteSnap.data();

    const amountAgorot = Math.round((quote.totalAmount || 0) * 100); // ILS → agorot
    if (amountAgorot <= 0) throw new HttpsError("invalid-argument", "Invalid quote amount");

    const customerId = await getOrCreateCustomer(stripe, request.auth.uid);
    const session = await stripe.checkout.sessions.create({
      customer:             customerId,
      mode:                 "payment",
      payment_method_types: ["card"],
      line_items: [{
        price_data: {
          currency:     "ils",
          unit_amount:  amountAgorot,
          product_data: { name: `AnySkill — ${quote.serviceType || "שירות"}` },
        },
        quantity: 1,
      }],
      metadata: { quoteId, expertId: quote.expertId || "", clientId: request.auth.uid },
      success_url: `https://anyskill-6fdf3.web.app/?stripe_payment=success&quoteId=${quoteId}`,
      cancel_url:  `https://anyskill-6fdf3.web.app/?stripe_payment=cancel&quoteId=${quoteId}`,
    });

    return { url: session.url };
  }
);
