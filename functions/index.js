const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
// @anthropic-ai/sdk v0.54 is a CJS package ("type":"commonjs").
// Using top-level require() instead of dynamic await import() avoids the
// "Anthropic is not a constructor" error that occurs because dynamic import()
// of a CJS module wraps module.exports as the `default` property (an object,
// not the class itself).
const { default: Anthropic } = require("@anthropic-ai/sdk");

// ── Secrets (set via: firebase functions:secrets:set ANTHROPIC_API_KEY) ────────
const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");

admin.initializeApp();

// ── Payment Cloud Functions (Stripe Connect + Morning invoicing) ─────────────
// Exported from payments.js to keep index.js focused on platform logic.
const payments = require("./payments");

// ── Financial rounding (NIS = 2 decimal places) ─────────────────────────────
// JavaScript floating point: 100 * 0.10 = 10.000000000000002
// This helper prevents ghost agorot and ensures fee + net = total exactly.
function roundNIS(n) { return Math.round(n * 100) / 100; }

// Flat (root-level) exports — current Flutter clients call these directly.
exports.createPaymentIntent        = payments.createPaymentIntent;
exports.handleStripeWebhook        = payments.handleStripeWebhook;
exports.releaseEscrow              = payments.releaseEscrow;
exports.onboardProvider            = payments.onboardProvider;
exports.processRefund              = payments.processRefund;
exports.listPaymentMethods         = payments.listPaymentMethods;
exports.createSetupIntent          = payments.createSetupIntent;
exports.createStripeSetupSession   = payments.createStripeSetupSession;
exports.createStripePaymentSession = payments.createStripePaymentSession;
exports.updateStripeAccount        = payments.updateStripeAccount;

// ── Backward-compat grouped export ───────────────────────────────────────────
// Older / cached Flutter web builds call  payments-createProviderOnboarding
// (the grouped path from the pre-refactor structure).  This alias keeps those
// clients working until the new hosting build propagates everywhere.
// Safe to remove once all clients are on the current build.
exports.payments = {
  createProviderOnboarding: payments.onboardProvider,
};

// מספר ה-shards לכל מונה unreadCount — מפיץ כתיבות ומונע write contention
const NUM_SHARDS = 5;

// ── Financial Health: Claude Haiku cost tracking ──────────────────────────────
// claude-haiku-4-5-20251001 pricing (as of 2025):
//   Input:  $0.80  per million tokens → $0.0000008  / token
//   Output: $4.00  per million tokens → $0.000004   / token
const _COST_PER_INPUT_TOKEN  = 0.0000008;
const _COST_PER_OUTPUT_TOKEN = 0.000004;
const _KILL_SWITCH_DEFAULT   = 100; // $100 hard monthly limit

/** Increments system_stats/billing with the cost of one Claude call.
 *  Auto-resets on month change. Activates kill-switch if limit exceeded.
 *  Fire-and-forget: call as  _trackApiCost(db, i, o).catch(()=>{}) */
async function _trackApiCost(db, inputTokens, outputTokens) {
    const cost     = (inputTokens  * _COST_PER_INPUT_TOKEN)
                   + (outputTokens * _COST_PER_OUTPUT_TOKEN);
    const monthKey = new Date().toISOString().slice(0, 7); // "YYYY-MM"
    const ref      = db.collection("system_stats").doc("billing");
    try {
        await db.runTransaction(async (tx) => {
            const snap  = await tx.get(ref);
            const data  = snap.exists ? snap.data() : {};
            const isNew = !data.month_key || data.month_key !== monthKey;
            if (isNew) {
                tx.set(ref, {
                    month_key:                monthKey,
                    current_month_api_cost:   cost,
                    current_month_infra_cost: 0,
                    total_input_tokens:       inputTokens,
                    total_output_tokens:      outputTokens,
                    api_call_count:           1,
                    ai_kill_switch_active:    false,
                    budget_limit:             data.budget_limit    || 50,
                    kill_switch_limit:        data.kill_switch_limit || _KILL_SWITCH_DEFAULT,
                    last_updated:             admin.firestore.FieldValue.serverTimestamp(),
                });
            } else {
                const newCost   = (data.current_month_api_cost || 0) + cost;
                const killLimit = data.kill_switch_limit || _KILL_SWITCH_DEFAULT;
                tx.set(ref, {
                    current_month_api_cost: newCost,
                    total_input_tokens:     admin.firestore.FieldValue.increment(inputTokens),
                    total_output_tokens:    admin.firestore.FieldValue.increment(outputTokens),
                    api_call_count:         admin.firestore.FieldValue.increment(1),
                    ai_kill_switch_active:  newCost >= killLimit,
                    last_updated:           admin.firestore.FieldValue.serverTimestamp(),
                }, { merge: true });
            }
        });
    } catch (e) {
        console.warn("_trackApiCost: silent fail", e.message);
    }
}

/** Returns true if the AI kill-switch is NOT active.
 *  Fails open (returns true) on any read error so users are never blocked. */
async function _isAiEnabled(db) {
    try {
        const snap = await db.collection("system_stats").doc("billing").get();
        if (!snap.exists) return true;
        return snap.data().ai_kill_switch_active !== true;
    } catch (_) {
        return true;
    }
}

// QA: הפונקציה מאזינה ליצירת הודעה חדשה בתוך הצא'טים
// maxInstances + concurrency מאפשרים עד 100 * 500 = 50,000 בקשות במקביל ללא cold starts
exports.sendchatnotification = onDocumentCreated(
    {
      document: "chats/{roomId}/messages/{messageId}",
      // minInstances: 1 keeps one warm instance ready at all times,
      // eliminating cold-start latency (~800ms) on the hot notification path.
      // Cost: ~$1.50/mo for one always-on instance vs. UX degradation at scale.
      minInstances: 1,
      maxInstances: 100,
      concurrency: 500,
    },
    async (event) => {
    const snapshot = event.data;
    if (!snapshot) return null;

    const messageData = snapshot.data();
    const receiverId = messageData.receiverId;
    const senderId = messageData.senderId;
    const messageText = messageData.message || "";
    const type = messageData.type || 'text';

    try {
        // 1. שליפת שם השולח
        const senderSnap = await admin.firestore().collection('users').doc(senderId).get();
        const senderName = senderSnap.exists ? (senderSnap.data().displayName || senderSnap.data().name || 'AnySkill') : 'הודעה חדשה';

        // 2. שליפת ה-Token של המקבל
        const receiverSnap = await admin.firestore().collection('users').doc(receiverId).get();
        if (!receiverSnap.exists) {
            console.log(`QA: Receiver ${receiverId} not found`);
            return null;
        }

        const receiverData = receiverSnap.data();
        
        // QA Fix: סדר עדיפויות לשליפת הטוקן לפי ה-Database האמיתי שלך
        const targetToken = receiverData.fcmToken || receiverData.deviceToken;

        if (!targetToken) {
            console.log(`QA: No token found for user: ${receiverId}`);
            return null;
        }

        // 3. הגדרת תוכן ההתראה
        let notificationBody = messageText;
        if (type === 'image') notificationBody = '📷 שלח/ה לך תמונה';
        if (type === 'location') notificationBody = '📍 שיתפ/ה איתך מיקום';
        if (type === 'audio') notificationBody = '🎤 שלח/ה הודעה קולית';

        // 3b. חישוב badge count עבור iOS (unread בשיחה הנוכחית + 1)
        let badgeCount = 1;
        try {
            const chatSnap = await admin.firestore()
                .collection('chats').doc(event.params.roomId).get();
            badgeCount = (((chatSnap.data() || {})[`unreadCount_${receiverId}`]) || 0) + 1;
        } catch (_) { /* fallback to 1 */ }

        // 4. בניית ה-Payload ל-FCM
        const messagePayload = {
            token: targetToken,
            notification: {
                title: senderName,
                body: notificationBody,
            },
            data: {
                senderId:   senderId,
                roomId:     event.params.roomId,
                chatRoomId: event.params.roomId, // Flutter's PendingNotification reads this
                click_action: "FLUTTER_NOTIFICATION_CLICK",
                type: "chat",
            },
            android: {
                priority: "high",
                notification: { channelId: "anyskill_chats" },
            },
            apns: {
                headers: { "apns-priority": "10" },
                payload: { aps: { badge: badgeCount, sound: "default" } },
            },
            webpush: {
                notification: {
                    icon: "/icons/Icon-192.png",
                    badge: "/icons/Icon-192.png",
                    click_action: "https://anyskill-6fdf3.web.app",
                },
                fcm_options: { link: "https://anyskill-6fdf3.web.app" },
            },
        };

        // 5. השליחה
        await admin.messaging().send(messagePayload);
        // Save to notification inbox (chat — only if not a system message)
        if (senderId !== 'system') {
            await admin.firestore().collection('notifications').add({
                userId: receiverId,
                title: senderName,
                body: notificationBody,
                type: 'chat',
                data: { senderId, roomId: event.params.roomId },
                isRead: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
        console.log(`QA: Notification sent to ${receiverId} from ${senderName}`);

        // 6. עדכון מטאדאטה של השיחה + distributed counter (רק אם לא system message)
        if (senderId !== 'system' && receiverId) {
            const roomId = event.params.roomId;
            const chatDocRef = admin.firestore().collection('chats').doc(roomId);

            // בחירת shard אקראי — מפיץ את הכתיבה על פני NUM_SHARDS מסמכים
            const shardIndex = Math.floor(Math.random() * NUM_SHARDS);
            const shardRef = chatDocRef
                .collection('unread_shards')
                .doc(`${receiverId}_${shardIndex}`);

            const metaBatch = admin.firestore().batch();

            // עדכון shard — increment אטומי ב-1 מסמך אקראי (ללא contention)
            metaBatch.set(shardRef, {
                count: admin.firestore.FieldValue.increment(1),
                uid: receiverId,
            }, { merge: true });

            // עדכון chat doc: lastMessage + מונה מדנורמלי
            // כותב אחד (Cloud Function) — אין תחרות עם הלקוח
            const lastMessageText = type === 'text' ? messageText : `שלח/ה ${type}`;
            metaBatch.set(chatDocRef, {
                lastMessage: lastMessageText,
                lastMessageTime: admin.firestore.FieldValue.serverTimestamp(),
                lastSenderId: senderId,
                [`unreadCount_${receiverId}`]: admin.firestore.FieldValue.increment(1),
            }, { merge: true });

            await metaBatch.commit();
            console.log(`QA: Chat metadata updated for room ${roomId}, shard ${shardIndex}`);
        }

    } catch (error) {
        console.error('QA Error - sending notification:', error);
    }
    return null;
});

// ── New booking → notify expert ───────────────────────────────────────────
exports.sendbookingnotification = onDocumentCreated("jobs/{jobId}", async (event) => {
    const jobData = event.data.data();
    const expertId = jobData.expertId;
    if (!expertId) return null;

    const customerName = jobData.customerName || 'לקוח';
    let dateInfo = '';
    if (jobData.appointmentDate && jobData.appointmentTime) {
        const d = jobData.appointmentDate.toDate();
        dateInfo = ` — ${d.getDate()}/${d.getMonth() + 1} בשעה ${jobData.appointmentTime}`;
    }

    try {
        const expertSnap = await admin.firestore().collection('users').doc(expertId).get();
        if (!expertSnap.exists) return null;
        const token = expertSnap.data().fcmToken || expertSnap.data().deviceToken;
        if (!token) return null;

        const bookingTitle = 'הזמנה חדשה! 🎉';
        const bookingBody = `${customerName} הזמין/ה שירות${dateInfo}`;
        await admin.messaging().send({
            token,
            notification: { title: bookingTitle, body: bookingBody },
            android: {
                priority: "high",
                notification: { channelId: "anyskill_default" },
            },
            apns: {
                headers: { "apns-priority": "10" },
                payload: { aps: { sound: "default", contentAvailable: 1 } },
            },
            webpush: {
                notification: { icon: '/icons/Icon-192.png' },
                fcm_options: { link: 'https://anyskill-6fdf3.web.app' },
            },
            data: { type: 'new_booking', jobId: event.params.jobId },
        });
        await admin.firestore().collection('notifications').add({
            userId: expertId,
            title: bookingTitle,
            body: bookingBody,
            type: 'new_booking',
            data: { jobId: event.params.jobId },
            isRead: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`Booking notification sent to expert ${expertId}`);
    } catch (error) {
        console.error('Error sending booking notification:', error);
    }
    return null;
});

// ── Job status change → notify the relevant party ─────────────────────────
exports.sendjobstatusnotification = onDocumentUpdated("jobs/{jobId}", async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();

    if (before.status === after.status) return null;

    let targetUserId, title, body;

    if (after.status === 'expert_completed') {
        // Expert marked done → notify customer to release payment
        targetUserId = after.customerId;
        title = 'המומחה סיים! ✅';
        body  = `${after.expertName || 'המומחה'} סיים את העבודה. לחץ לשחרור התשלום.`;

    } else if (after.status === 'completed') {
        // Customer released payment → notify expert
        targetUserId = after.expertId;
        title = 'התשלום שוחרר! 💰';
        body  = `${after.customerName || 'הלקוח'} אישר את העבודה. הכסף נוסף לארנק שלך.`;

    } else {
        return null;
    }

    try {
        const userSnap = await admin.firestore().collection('users').doc(targetUserId).get();
        if (!userSnap.exists) return null;
        const token = userSnap.data().fcmToken || userSnap.data().deviceToken;
        if (!token) return null;

        await admin.messaging().send({
            token,
            notification: { title, body },
            android: {
                priority: "high",
                notification: { channelId: "anyskill_default" },
            },
            apns: {
                headers: { "apns-priority": "10" },
                payload: { aps: { sound: "default", contentAvailable: 1 } },
            },
            webpush: {
                notification: { icon: '/icons/Icon-192.png' },
                fcm_options: { link: 'https://anyskill-6fdf3.web.app' },
            },
            data: { type: 'job_status', jobId: event.params.jobId, status: after.status },
        });
        await admin.firestore().collection('notifications').add({
            userId: targetUserId,
            title,
            body,
            type: 'job_status',
            data: { jobId: event.params.jobId, status: after.status },
            isRead: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`Job status notification (${after.status}) sent to ${targetUserId}`);
    } catch (error) {
        console.error('Error sending job status notification:', error);
    }
    return null;
});

// ── Callable: שחרור תשלום מאסקרו (Admin SDK — עוקף חוקי Firestore) ──────────
exports.processPaymentRelease = onCall(async (request) => {
    console.log('[PPR] ── START ──────────────────────────────────');

    // STEP 1: Auth check
    if (!request.auth) {
        console.error('[PPR] STEP1 FAIL: no auth');
        throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }
    console.log(`[PPR] STEP1 OK: callerUid=${request.auth.uid}`);

    // STEP 2: Input validation
    const { jobId, expertId, expertName, customerName, totalAmount } = request.data;
    console.log(`[PPR] STEP2 input: jobId=${jobId}, expertId=${expertId}, totalAmount=${totalAmount}, customerName=${customerName}, expertName=${expertName}`);
    if (!jobId || !expertId || totalAmount == null) {
        console.error('[PPR] STEP2 FAIL: missing required fields');
        throw new HttpsError('invalid-argument', 'jobId, expertId and totalAmount are required.');
    }
    console.log('[PPR] STEP2 OK: inputs valid');

    const db = admin.firestore();
    const jobRef = db.collection('jobs').doc(jobId);
    const expertRef = db.collection('users').doc(expertId);
    const adminSettingsRef = db.collection('admin').doc('admin').collection('settings').doc('settings');

    // STEP 3: Load & validate job
    let jobSnap;
    try {
        jobSnap = await jobRef.get();
    } catch (e) {
        console.error(`[PPR] STEP3 FAIL: could not read job — ${e.message}`);
        throw new HttpsError('internal', `Could not read job: ${e.message}`);
    }
    if (!jobSnap.exists) {
        console.error(`[PPR] STEP3 FAIL: job ${jobId} does not exist`);
        throw new HttpsError('not-found', 'Job not found.');
    }
    const jobData = jobSnap.data();
    console.log(`[PPR] STEP3 OK: job exists. status=${jobData.status}, customerId=${jobData.customerId}`);

    // STEP 4: Caller == customer?
    if (jobData.customerId !== request.auth.uid) {
        console.error(`[PPR] STEP4 FAIL: caller ${request.auth.uid} != customerId ${jobData.customerId}`);
        throw new HttpsError('permission-denied', 'Only the customer of this job can release payment.');
    }
    console.log('[PPR] STEP4 OK: caller is the customer');

    // STEP 5: Status check
    if (jobData.status !== 'expert_completed') {
        console.error(`[PPR] STEP5 FAIL: status='${jobData.status}', expected 'expert_completed'`);
        throw new HttpsError('failed-precondition', `Job status is '${jobData.status}', expected 'expert_completed'.`);
    }
    console.log('[PPR] STEP5 OK: status is expert_completed');

    // PRE-TRANSACTION: resolve category ref for bookingCount increment
    // (queries are not allowed inside transactions — must do this outside)
    let categoryRef = null;
    try {
        const expertSnapForCat = await expertRef.get();
        const serviceType = expertSnapForCat.exists
            ? (expertSnapForCat.data().serviceType || '') : '';
        if (serviceType) {
            const catSnap = await db.collection('categories')
                .where('name', '==', serviceType).limit(1).get();
            if (!catSnap.empty) categoryRef = catSnap.docs[0].ref;
        }
        console.log(`[PPR] PRE-TX: serviceType=${serviceType}, categoryRef=${categoryRef ? categoryRef.id : 'none'}`);
    } catch (e) {
        console.warn(`[PPR] PRE-TX: could not resolve category — ${e.message}`);
    }

    // STEP 6: Firestore transaction
    try {
        await db.runTransaction(async (tx) => {
            console.log('[PPR] STEP6 TX: reading adminSettings + expertData...');
            // Read both docs before any writes (Firestore transaction requirement)
            const [adminSnap, expertDataSnap] = await Promise.all([
                tx.get(adminSettingsRef),
                tx.get(expertRef),
            ]);

            // Per-provider commission takes priority; fall back to global setting
            const customCommission = expertDataSnap.exists
                ? expertDataSnap.data().customCommission
                : undefined;
            const globalFee = adminSnap.exists ? (adminSnap.data().feePercentage ?? 0.10) : 0.10;
            const feePercentage = (customCommission != null) ? customCommission : globalFee;

            const feeAmount   = roundNIS(totalAmount * feePercentage);
            const netToExpert = roundNIS(totalAmount - feeAmount);
            console.log(`[PPR] STEP6 TX: feePercentage=${feePercentage} (${customCommission != null ? 'custom' : 'global'}), feeAmount=${feeAmount}, netToExpert=${netToExpert}`);

            // ── Edge case: provider deleted their account mid-transaction ──────
            // Firestore tx.update() throws DOCUMENT_NOT_FOUND on a missing doc.
            // We still complete the job and record earnings, but credit a
            // 'deleted_expert_funds' holding doc instead of a missing user doc.
            const expertExists = expertDataSnap.exists;
            if (!expertExists) {
                console.warn(`[PPR] STEP6 TX: expert ${expertId} not found — crediting holding account`);
                tx.set(db.collection('deleted_expert_funds').doc(expertId), {
                    expertId,
                    pendingBalance: admin.firestore.FieldValue.increment(netToExpert),
                    lastJobId:      jobId,
                    updatedAt:      admin.firestore.FieldValue.serverTimestamp(),
                }, { merge: true });
            }

            console.log('[PPR] STEP6 TX: updating job...');
            tx.update(jobRef, {
                status: 'completed',
                completedAt: admin.firestore.FieldValue.serverTimestamp(),
                feeAmount,
                netAmountForExpert: netToExpert,
                ...(expertExists ? {} : { expertAccountDeleted: true }),
            });

            if (expertExists) {
                console.log('[PPR] STEP6 TX: updating expert balance + orderCount...');
                tx.update(expertRef, {
                    balance:     admin.firestore.FieldValue.increment(netToExpert),
                    orderCount:  admin.firestore.FieldValue.increment(1),
                });
            }

            // Increment category bookingCount (powers Trending badges on Discover)
            if (categoryRef) {
                console.log(`[PPR] STEP6 TX: incrementing bookingCount on category ${categoryRef.id}`);
                tx.set(categoryRef, {
                    bookingCount: admin.firestore.FieldValue.increment(1),
                }, { merge: true });
            }

            console.log('[PPR] STEP6 TX: updating admin settings...');
            tx.set(adminSettingsRef, {
                totalPlatformBalance: admin.firestore.FieldValue.increment(feeAmount),
                lastFinanceUpdate: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });

            console.log('[PPR] STEP6 TX: writing platform_earnings...');
            tx.set(db.collection('platform_earnings').doc(), {
                jobId,
                amount: feeAmount,
                customerName: customerName || 'לקוח',
                expertName:   expertName   || 'מומחה',
                description:  `${customerName || 'לקוח'} ➔ ${expertName || 'מומחה'}`,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
            });

            console.log('[PPR] STEP6 TX: writing transaction record...');
            tx.set(db.collection('transactions').doc(), {
                userId: expertId,
                amount: netToExpert,
                title: `קיבלת תשלום — ${customerName || 'לקוח'}`,
                type: 'earning',
                clientName: customerName || 'לקוח',
                jobId,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
            });

            console.log('[PPR] STEP6 TX: all writes queued, committing...');
        });

        console.log(`[PPR] STEP6 OK: transaction committed. job=${jobId} completed`);
        console.log('[PPR] ── END (success) ────────────────────────────');
        return { success: true };

    } catch (e) {
        console.error(`[PPR] STEP6 FAIL: transaction threw — code=${e.code} message=${e.message}`);
        console.error('[PPR] full error:', JSON.stringify(e, Object.getOwnPropertyNames(e)));
        throw new HttpsError('internal', `Payment release failed: ${e.message}`);
    }
});

// ── Callable: מחיקת משתמש (Admin SDK — דורש הרשאת admin) ────────────────────
exports.deleteUser = onCall(async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }

    // אימות שהמשתמש הקורא הוא מנהל
    const callerSnap = await admin.firestore().collection('users').doc(request.auth.uid).get();
    if (request.auth.token.email !== 'adawiavihai@gmail.com'
        && (!callerSnap.exists || !callerSnap.data().isAdmin)) {
        throw new HttpsError('permission-denied', 'Caller is not an admin.');
    }

    const { uid } = request.data;
    if (!uid) throw new HttpsError('invalid-argument', 'uid is required.');

    // מחיקת חשבון ה-Auth (user-not-found = כבר נמחק, לא שגיאה קשה)
    try {
        await admin.auth().deleteUser(uid);
    } catch (e) {
        if (e.code !== 'auth/user-not-found') {
            throw new HttpsError('internal', `Auth deletion failed: ${e.message}`);
        }
    }

    // מחיקת מסמך ה-Firestore
    await admin.firestore().collection('users').doc(uid).delete();

    console.log(`Admin ${request.auth.uid} deleted user ${uid}`);
    return { success: true };
});

// ── Anticipatory Design ── Recurring services list ─────────────────────────────
const RECURRING_SERVICES = ['ניקיון', 'גינון', 'כושר ואימון', 'הדברה', 'שרברבות'];

// When a job completes for a recurring service → schedule a rebook reminder in 30 days
exports.scheduleRebookReminder = onDocumentUpdated("jobs/{jobId}", async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    if (before.status === after.status || after.status !== 'completed') return null;

    const customerId   = after.customerId;
    const expertId     = after.expertId;
    const expertName   = after.expertName   || 'המומחה';
    const customerName = after.customerName || 'הלקוח';
    if (!customerId || !expertId) return null;

    // Fetch expert serviceType (not stored on job doc)
    const expertSnap = await admin.firestore().collection('users').doc(expertId).get();
    if (!expertSnap.exists) return null;
    const serviceType = expertSnap.data().serviceType || '';
    if (!RECURRING_SERVICES.includes(serviceType)) return null;

    const sendAt = new Date();
    sendAt.setDate(sendAt.getDate() + 30);

    await admin.firestore().collection('scheduled_reminders').add({
        type:         'rebook',
        customerId,
        expertId,
        expertName,
        customerName,
        serviceType,
        jobId:        event.params.jobId,
        sendAt:       admin.firestore.Timestamp.fromDate(sendAt),
        status:       'pending',
        createdAt:    admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`Rebook reminder scheduled for ${customerName} → ${expertName} (${serviceType}) in 30 days`);
    return null;
});

// Daily cron at 09:00 IST — sends any pending rebook reminders whose sendAt has passed
exports.sendRebookReminders = onSchedule(
    { schedule: '0 9 * * *', timeZone: 'Asia/Jerusalem' },
    async () => {
        const db  = admin.firestore();
        const now = new Date();

        const snap = await db.collection('scheduled_reminders')
            .where('status',  '==', 'pending')
            .where('sendAt',  '<=', admin.firestore.Timestamp.fromDate(now))
            .limit(100)
            .get();

        if (snap.empty) {
            console.log('sendRebookReminders: no pending reminders');
            return;
        }

        const batch = db.batch();

        for (const doc of snap.docs) {
            const r = doc.data();
            try {
                // Fetch customer FCM token
                const customerSnap = await db.collection('users').doc(r.customerId).get();
                if (!customerSnap.exists) { batch.update(doc.ref, { status: 'skipped_no_user' }); continue; }
                const token = customerSnap.data().fcmToken || customerSnap.data().deviceToken;
                if (!token)  { batch.update(doc.ref, { status: 'skipped_no_token' }); continue; }

                const title = `${r.customerName}, הגיע הזמן ל${r.serviceType} שוב! 🏠`;
                const body  = `לפני 30 ימים הזמנת את ${r.expertName}. הזמן שוב בלחיצה אחת!`;

                await admin.messaging().send({
                    token,
                    notification: { title, body },
                    android: {
                        priority: "high",
                        notification: { channelId: "anyskill_default" },
                    },
                    apns: {
                        headers: { "apns-priority": "10" },
                        payload: { aps: { sound: "default", contentAvailable: 1 } },
                    },
                    webpush: {
                        notification: { icon: '/icons/Icon-192.png', badge: '/icons/Icon-192.png' },
                        fcm_options:  { link: 'https://anyskill-6fdf3.web.app' },
                    },
                    data: { type: 'rebook_reminder', expertId: r.expertId, expertName: r.expertName },
                });

                // Save to notification inbox
                await db.collection('notifications').add({
                    userId:    r.customerId,
                    title,
                    body,
                    type:      'rebook_reminder',
                    data:      { expertId: r.expertId, expertName: r.expertName, jobId: r.jobId },
                    isRead:    false,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });

                batch.update(doc.ref, { status: 'sent', sentAt: admin.firestore.FieldValue.serverTimestamp() });
                console.log(`Rebook reminder sent to ${r.customerName} for ${r.expertName}`);
            } catch (e) {
                console.error(`Rebook reminder error for ${r.customerId}:`, e.message);
                batch.update(doc.ref, { status: 'error', error: e.message });
            }
        }

        await batch.commit();
        console.log(`sendRebookReminders: processed ${snap.size} reminders`);
    }
);

// ── Gamification helpers ───────────────────────────────────────────────────────
// Reads level thresholds from settings_gamification/app_levels (admin-configurable).
// Falls back to silver=500, gold=2000 when the doc doesn't exist yet.
async function _awardXpDynamic(uid, points, reason) {
    const db         = admin.firestore();
    const levelsSnap = await db.collection('settings_gamification').doc('app_levels').get();
    const levels     = levelsSnap.data() || {};
    const silverThr  = typeof levels.silver === 'number' ? levels.silver : 500;
    const goldThr    = typeof levels.gold   === 'number' ? levels.gold   : 2000;
    const userRef    = db.collection('users').doc(uid);

    await db.runTransaction(async (tx) => {
        const snap = await tx.get(userRef);
        if (!snap.exists) return;
        const data      = snap.data();
        const currentXp = typeof data.current_xp === 'number' ? data.current_xp
                        : typeof data.xp          === 'number' ? data.xp : 0;
        const finalXp   = Math.max(0, currentXp + points);
        const level     = finalXp >= goldThr  ? 'gold'
                        : finalXp >= silverThr ? 'silver'
                        :                       'bronze';
        tx.update(userRef, { xp: finalXp, current_xp: finalXp, level });
    });
    console.log(`XP: ${points >= 0 ? '+' : ''}${points} to ${uid} for ${reason}`);
}

// ── Job completed → +100 XP (or +300 XP for volunteer jobs) ─────────────────
exports.awardXpJobCompleted = onDocumentUpdated("jobs/{jobId}", async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    if (before.status === after.status) return null;
    if (after.status !== 'completed')   return null;
    const expertId = after.expertId;
    if (!expertId) return null;

    const isVolunteerJob = after.isVolunteer === true;

    try {
        if (isVolunteerJob) {
            // 3× XP multiplier for volunteer jobs
            await _awardXpDynamic(expertId, 300, 'volunteer_job_completed');

            // Track volunteer task counter + award gold badge at 5
            const db      = admin.firestore();
            const userRef = db.collection('users').doc(expertId);
            await db.runTransaction(async (tx) => {
                const snap  = await tx.get(userRef);
                if (!snap.exists) return;
                const data  = snap.data();
                const count = (data.volunteerTasksCompleted ?? 0) + 1;
                const update = { volunteerTasksCompleted: count };
                if (count >= 5) update.volunteerBadge = 'gold';
                tx.update(userRef, update);
            });

            // Notify the expert
            await db.collection('notifications').add({
                userId:    expertId,
                title:     '🌟 3× XP על עזרה לקהילה!',
                body:      'קיבלת 300 XP על עזרה לקהילה! המשך כך ❤️',
                type:      'volunteer_xp',
                isRead:    false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        } else {
            await _awardXpDynamic(expertId, 100, 'job_completed');
        }
    } catch (e) {
        console.error('XP job_completed error:', e);
    }
    return null;
});

// ── 5-star review → +50 XP to expert ─────────────────────────────────────────
exports.awardXpFiveStarReview = onDocumentCreated("reviews/{reviewId}", async (event) => {
    const review = event.data.data();
    if (!review || review.rating !== 5) return null;
    const expertId = review.expertId;
    if (!expertId) return null;
    try {
        await _awardXpDynamic(expertId, 50, 'five_star_review');
    } catch (e) {
        console.error('XP five_star_review error:', e);
    }
    return null;
});

// ── Quick response <5 min → +25 XP to provider ───────────────────────────────
exports.awardXpQuickResponse = onDocumentCreated(
    { document: "chats/{roomId}/messages/{messageId}", maxInstances: 50 },
    async (event) => {
        const msg = event.data.data();
        const senderId   = msg.senderId;
        const receiverId = msg.receiverId;
        if (!senderId || !receiverId || senderId === 'system') return null;

        const db = admin.firestore();

        // Only award XP when the sender is a provider
        const senderSnap = await db.collection('users').doc(senderId).get();
        if (!senderSnap.exists || !senderSnap.data().isProvider) return null;

        // Check this is the provider's FIRST message in this room
        // (the trigger doc is already written, so limit(2) → size>1 means they replied before)
        const senderMsgsSnap = await db
            .collection('chats').doc(event.params.roomId)
            .collection('messages')
            .where('senderId', '==', senderId)
            .limit(2)
            .get();
        if (senderMsgsSnap.size > 1) return null;

        // Find client's most recent message before this response
        const clientMsgsSnap = await db
            .collection('chats').doc(event.params.roomId)
            .collection('messages')
            .where('senderId', '==', receiverId)
            .orderBy('timestamp', 'desc')
            .limit(1)
            .get();
        if (clientMsgsSnap.empty) return null;

        const clientTs  = clientMsgsSnap.docs[0].data().timestamp?.toDate();
        const providerTs = msg.timestamp?.toDate() || new Date();
        if (!clientTs) return null;

        const diffMins = (providerTs - clientTs) / 60000;
        if (diffMins < 0 || diffMins > 5) return null;

        try {
            await _awardXp(senderId, 25, 'quick_response');
        } catch (e) {
            console.error('XP quick_response error:', e);
        }
        return null;
    }
);

// ── Callable: סימון הודעות כנקראו (Admin SDK — ללא מגבלות client) ──────────────
// מוחלף על פעולת batch כבדה בצד הלקוח. מאפס shards + שדה מדנורמלי + isRead
exports.processMarkAsRead = onCall({ minInstances: 1, concurrency: 80 }, async (request) => {
    // אימות: רק המשתמש עצמו יכול לאפס את המונה שלו
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }

    const { chatRoomId, userId } = request.data;

    if (request.auth.uid !== userId) {
        throw new HttpsError('permission-denied', 'You can only mark your own messages as read.');
    }

    if (!chatRoomId || !userId) {
        throw new HttpsError('invalid-argument', 'chatRoomId and userId are required.');
    }

    const db = admin.firestore();
    const chatDocRef = db.collection('chats').doc(chatRoomId);

    try {
        // 1. שליפת הודעות שלא נקראו — מוגבל ל-100 למניעת batch גדול מדי
        const unreadSnap = await db
            .collection('chats').doc(chatRoomId)
            .collection('messages')
            .where('receiverId', '==', userId)
            .where('isRead', '==', false)
            .limit(100)
            .get();

        const batch = db.batch();

        // 2. סימון כל הודעה כנקראה
        unreadSnap.docs.forEach(doc => batch.update(doc.ref, { isRead: true }));

        // 3. איפוס כל NUM_SHARDS ה-shards של המשתמש
        for (let i = 0; i < NUM_SHARDS; i++) {
            const shardRef = chatDocRef
                .collection('unread_shards')
                .doc(`${userId}_${i}`);
            batch.set(shardRef, { count: 0, uid: userId }, { merge: true });
        }

        // 4. איפוס השדה המדנורמלי בכתב השיחה
        batch.update(chatDocRef, { [`unreadCount_${userId}`]: 0 });

        await batch.commit();

        console.log(`QA: processMarkAsRead — ${unreadSnap.size} messages marked, shards reset for ${userId} in ${chatRoomId}`);
        return { success: true, markedCount: unreadSnap.size };

    } catch (error) {
        console.error('QA Error - processMarkAsRead:', error);
        throw new HttpsError('internal', `Mark-as-read failed: ${error.message}`);
    }
});

// ── Receipt Email — triggered when job reaches 'completed' ───────────────
// Writes to the `mail` collection consumed by the Firebase Trigger Email
// extension (https://extensions.dev/extensions/firebase/firestore-send-email).
// Install the extension with collection path = "mail" to enable delivery.

exports.sendReceiptEmail = onDocumentUpdated(
    { document: 'jobs/{jobId}', maxInstances: 20 },
    async (event) => {
        const before = event.data.before.data();
        const after  = event.data.after.data();

        // Only fire once: when status transitions to 'completed'
        if (before.status === 'completed' || after.status !== 'completed') return null;

        const db    = admin.firestore();
        const jobId = event.params.jobId;

        // Sanitise all user-supplied strings before interpolating into HTML.
        // Prevents XSS payloads in names from appearing in email clients.
        const _esc = (s) => (s || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');

        // ── Resolve email addresses ──────────────────────────────────────
        const [customerSnap, expertSnap] = await Promise.all([
            db.collection('users').doc(after.customerId).get(),
            db.collection('users').doc(after.expertId).get(),
        ]);

        const customerEmail = customerSnap.data()?.email;
        const expertEmail   = expertSnap.data()?.email;
        const expertTaxId   = expertSnap.data()?.taxId || '';

        const total      = after.totalPaidByCustomer || 0;
        const commission = after.commissionAmount    || 0;
        const net        = after.netAmountForExpert  || (total - commission);
        const feePct     = total > 0 ? Math.round((commission / total) * 100) : 0;
        const receiptNum = jobId.substring(0, 8).toUpperCase();

        const apptDate = after.appointmentDate?.toDate
            ? after.appointmentDate.toDate().toLocaleDateString('he-IL')
            : '—';
        const apptTime  = after.appointmentTime || '';
        const dateLabel = apptTime ? `${apptDate} · ${apptTime}` : apptDate;

        // ── Shared HTML receipt template ─────────────────────────────────
        const receiptHtml = (recipientType) => `
<!DOCTYPE html>
<html dir="rtl" lang="he">
<head><meta charset="UTF-8">
<style>
  body { font-family: Arial, sans-serif; background: #f5f7fa; margin: 0; padding: 20px; direction: rtl; }
  .card { background: #fff; border-radius: 16px; max-width: 520px; margin: 0 auto; overflow: hidden; box-shadow: 0 4px 20px rgba(0,0,0,.08); }
  .header { background: linear-gradient(135deg,#1a1a2e,#16213e); color: #fff; padding: 24px 28px; }
  .header h1 { margin: 0 0 4px; font-size: 22px; }
  .header p  { margin: 0; color: rgba(255,255,255,.6); font-size: 12px; }
  .body   { padding: 24px 28px; }
  .row    { display: flex; justify-content: space-between; margin-bottom: 10px; font-size: 14px; }
  .row .label { color: #888; }
  .divider { border: none; border-top: 1px solid #eee; margin: 16px 0; }
  .total  { background: #1a1a2e; color: #fff; border-radius: 12px; padding: 14px 18px; display: flex; justify-content: space-between; align-items: center; margin-top: 10px; }
  .total .amount { font-size: 22px; font-weight: 900; }
  .badge  { display: inline-block; background: #ecfdf5; color: #065f46; border: 1px solid #6ee7b7; border-radius: 20px; padding: 5px 14px; font-size: 12px; font-weight: bold; margin-top: 16px; }
  .note   { font-size: 11px; color: #aaa; margin-top: 16px; line-height: 1.5; }
  .footer { text-align: center; padding: 16px; background: #f9fafb; color: #bbb; font-size: 11px; }
</style>
</head>
<body>
<div class="card">
  <div class="header">
    <div style="display:flex;justify-content:space-between;align-items:flex-start">
      <div style="text-align:left">
        <div style="font-size:11px;color:rgba(255,255,255,.5);font-family:monospace">#${receiptNum}</div>
        <div style="font-size:11px;color:rgba(255,255,255,.4)">${new Date().toLocaleDateString('he-IL')}</div>
      </div>
      <div>
        <h1>AnySkill</h1>
        <p>קבלה דיגיטלית${recipientType === 'expert' ? ' — ספק' : ' — לקוח'}</p>
      </div>
    </div>
  </div>
  <div class="body">
    <div class="row"><span class="label">לקוח</span><span><strong>${_esc(after.customerName) || '—'}</strong></span></div>
    <div class="row"><span class="label">נותן שירות</span><span><strong>${_esc(after.expertName) || '—'}</strong></span></div>
    <div class="row"><span class="label">תאריך שירות</span><span>${_esc(dateLabel)}</span></div>
    ${expertTaxId ? `<div class="row"><span class="label">ח.פ / ת.ז ספק</span><span>${_esc(expertTaxId)}</span></div>` : ''}
    <hr class="divider"/>
    <div class="row"><span class="label">מחיר שירות</span><span>₪${net.toFixed(2)}</span></div>
    <div class="row" style="color:#aaa"><span class="label">עמלת פלטפורמה (${feePct}%)</span><span>₪${commission.toFixed(2)}</span></div>
    <div class="total">
      <span class="amount">₪${total.toFixed(2)}</span>
      <span style="color:rgba(255,255,255,.7);font-size:13px">סה"כ שולם</span>
    </div>
    <div style="text-align:center"><span class="badge">✓ העסקה הושלמה בהצלחה</span></div>
    <p class="note">מסמך זה הוא אישור עסקה ואינו חשבונית מס רשמית.</p>
  </div>
  <div class="footer">AnySkill — עסקאות מאובטחות &bull; מספר עסקה: ${receiptNum}</div>
</div>
</body></html>`;

        const batch = db.batch();

        // Email to customer
        if (customerEmail) {
            batch.set(db.collection('mail').doc(), {
                to:      [customerEmail],
                message: {
                    subject: `קבלה על שירות מ-${_esc(after.expertName)} — AnySkill #${receiptNum}`,
                    html:    receiptHtml('customer'),
                },
            });
        }

        // Email to expert (shows net amount)
        if (expertEmail) {
            batch.set(db.collection('mail').doc(), {
                to:      [expertEmail],
                message: {
                    subject: `סיכום עסקה עם ${_esc(after.customerName)} — AnySkill #${receiptNum}`,
                    html:    receiptHtml('expert'),
                },
            });
        }

        if (customerEmail || expertEmail) {
            await batch.commit();
            console.log(`sendReceiptEmail: queued for job ${jobId} (customer=${!!customerEmail}, expert=${!!expertEmail})`);
        }
        return null;
    }
);

// ── VIP Subscription ──────────────────────────────────────────────────────
// Callable: deducts ₪99 from balance and activates isPromoted for 30 days.

exports.activateVipSubscription = onCall(async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Not authenticated');

    const db       = admin.firestore();
    const userRef  = db.collection('users').doc(uid);
    const txRef    = db.collection('transactions').doc();
    const VIP_PRICE = 99;
    const VIP_DAYS  = 30;

    await db.runTransaction(async (tx) => {
        const userDoc = await tx.get(userRef);
        if (!userDoc.exists) throw new HttpsError('not-found', 'User not found');

        const balance = userDoc.data()?.balance ?? 0;
        if (balance < VIP_PRICE) {
            throw new HttpsError(
                'failed-precondition',
                `יתרה לא מספיקה. נדרש ₪${VIP_PRICE}, יש ₪${balance}`
            );
        }

        const expiryDate = new Date();
        expiryDate.setDate(expiryDate.getDate() + VIP_DAYS);

        tx.update(userRef, {
            balance:              admin.firestore.FieldValue.increment(-VIP_PRICE),
            isPromoted:           true,
            promotionExpiryDate:  admin.firestore.Timestamp.fromDate(expiryDate),
        });

        tx.set(txRef, {
            userId:    uid,
            amount:    -VIP_PRICE,
            title:     `מנוי VIP — חשיפה מוגברת (${VIP_DAYS} יום)`,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            type:      'vip_subscription',
        });
    });

    console.log(`VIP activated for ${uid} for ${VIP_DAYS} days`);
    return { success: true };
});

// ── VIP Expiry — daily cron at 00:30 IST ─────────────────────────────────
// Clears isPromoted for any provider whose promotionExpiryDate has passed.

exports.expireVipSubscriptions = onSchedule(
    { schedule: '30 0 * * *', timeZone: 'Asia/Jerusalem' },
    async (_event) => {
        const db  = admin.firestore();
        const now = admin.firestore.Timestamp.now();

        const expired = await db.collection('users')
            .where('isPromoted',          '==', true)
            .where('promotionExpiryDate', '<=', now)
            .get();

        if (expired.empty) {
            console.log('expireVipSubscriptions: no expired VIPs');
            return;
        }

        const batch = db.batch();
        for (const doc of expired.docs) {
            batch.update(doc.ref, { isPromoted: false });
        }
        await batch.commit();
        console.log(`expireVipSubscriptions: cleared ${expired.size} expired VIP(s)`);
    }
);

// ════════════════════════════════════════════════════════════════════════════
// RETENTION & ENGAGEMENT SYSTEM
// ════════════════════════════════════════════════════════════════════════════

// ── Write a "completed_works" doc when a job finishes (Inspiration Feed) ──────
// Powers the _InspirationFeed widget in search_page.dart.
// Keeps only: expertId, expertName, serviceType, coverImage, city, completedAt.

exports.writeCompletedWork = onDocumentUpdated(
    { document: "jobs/{jobId}", maxInstances: 10 },
    async (event) => {
        const before = event.data.before.data();
        const after  = event.data.after.data();
        if (before.status === 'completed' || after.status !== 'completed') return null;

        const expertId = after.expertId;
        if (!expertId) return null;

        const db = admin.firestore();
        try {
            const expertSnap = await db.collection('users').doc(expertId).get();
            if (!expertSnap.exists) return null;
            const expertData = expertSnap.data();

            await db.collection('completed_works').add({
                expertId,
                expertName:   after.expertName  || expertData.name || 'מומחה',
                serviceType:  expertData.serviceType || '',
                coverImage:   expertData.profileImage || '',
                city:         expertData.city || '',
                rating:       expertData.rating || 5.0,
                completedAt:  admin.firestore.FieldValue.serverTimestamp(),
            });
            console.log(`Inspiration Feed: completed_work written for expert ${expertId}`);
        } catch (e) {
            console.error('writeCompletedWork error:', e);
        }
        return null;
    }
);

// ── Geo-completion notifications — notify nearby users when a job finishes ──
// Sends up to 15 push notifications to customers in the same city as the expert.
// Throttled: each user receives at most 1 geo-notification per 6 hours.

exports.sendGeoCompletionNotifications = onDocumentUpdated(
    { document: "jobs/{jobId}", maxInstances: 5 },
    async (event) => {
        const before = event.data.before.data();
        const after  = event.data.after.data();
        if (before.status === 'completed' || after.status !== 'completed') return null;

        const expertId = after.expertId;
        if (!expertId) return null;

        const db = admin.firestore();
        try {
            const expertSnap = await db.collection('users').doc(expertId).get();
            if (!expertSnap.exists) return null;
            const expertData  = expertSnap.data();
            const city        = expertData.city        || '';
            const serviceType = expertData.serviceType || '';
            const expertName  = expertData.name        || 'מומחה';
            if (!city) return null;

            // Find up to 15 nearby customers (non-providers)
            const nearbySnap = await db.collection('users')
                .where('city', '==', city)
                .where('isProvider', '==', false)
                .limit(15)
                .get();
            if (nearbySnap.empty) return null;

            const sixHoursAgo = new Date(Date.now() - 6 * 3600 * 1000);
            const title = `מומחה מוביל סיים עבודה ב${city}! 📍`;
            const body  = `${expertName} (${serviceType}) זמין עכשיו לשירות נוסף.`;

            const sends = nearbySnap.docs
                .filter(d => {
                    if (d.id === expertId || d.id === after.customerId) return false;
                    const lastNotify = d.data().geoNotifyLastAt?.toDate();
                    if (lastNotify && lastNotify > sixHoursAgo) return false;
                    return !!(d.data().fcmToken || d.data().deviceToken);
                })
                .map(async d => {
                    const token = d.data().fcmToken || d.data().deviceToken;
                    try {
                        await admin.messaging().send({
                            token,
                            notification: { title, body },
                            android: {
                                priority: "high",
                                notification: { channelId: "anyskill_default" },
                            },
                            apns: {
                                headers: { "apns-priority": "10" },
                                payload: { aps: { sound: "default", contentAvailable: 1 } },
                            },
                            webpush: {
                                notification: { icon: '/icons/Icon-192.png' },
                                fcm_options: { link: 'https://anyskill-6fdf3.web.app' },
                            },
                            data: { type: 'geo_nearby', expertId, city },
                        });
                        const batch = db.batch();
                        batch.set(db.collection('notifications').doc(), {
                            userId: d.id, title, body, type: 'geo_nearby',
                            data: { expertId, city, serviceType },
                            isRead: false,
                            createdAt: admin.firestore.FieldValue.serverTimestamp(),
                        });
                        batch.update(d.ref, {
                            geoNotifyLastAt: admin.firestore.FieldValue.serverTimestamp(),
                        });
                        await batch.commit();
                    } catch (e) {
                        console.error(`Geo notify error for ${d.id}:`, e.message);
                    }
                });

            await Promise.all(sends);
            console.log(`Geo notifications sent to ${sends.length} users in ${city}`);
        } catch (e) {
            console.error('sendGeoCompletionNotifications error:', e);
        }
        return null;
    }
);

// ── Monthly seasonal notifications (1st of each month, 10:00 IST) ────────────
// Sends contextual push about season-relevant services to all users with tokens.
// Users can opt out via users/{uid}.disableSeasonalNotifs = true.

const SEASONAL_MAP = {
    2:  { title: 'האביב כבר כאן! 🌸', body: 'הגיע הזמן לניקיון מזגן, גינון ורענון הבית.' },
    3:  { title: 'מוכן לקיץ? ☀️',     body: 'קבל הצעות על שיפוץ, צביעה וריהוט חדש.' },
    5:  { title: 'קיץ חם בפתח! 🏖️',   body: 'בדוק שהמזגן שלך מוכן לגל החום הבא.' },
    8:  { title: 'הסתיו הגיע 🍂',      body: 'זמן מצוין להכין את הבית לחורף — שרברב, חשמלאי ועוד.' },
    10: { title: 'החורף מתקרב ❄️',     body: 'דאג לחימום, בידוד וצנרת לפני הגשמים.' },
};

exports.sendSeasonalNotifications = onSchedule(
    { schedule: '0 10 1 * *', timeZone: 'Asia/Jerusalem', maxInstances: 1 },
    async () => {
        const db    = admin.firestore();
        const month = new Date().getMonth();
        const seasonal = SEASONAL_MAP[month];
        if (!seasonal) {
            console.log('sendSeasonalNotifications: no campaign for month', month);
            return;
        }

        const { title, body } = seasonal;
        let totalSent = 0;
        let lastDoc   = null;

        // Paginate through all users in batches of 500
        do {
            let query = db.collection('users').orderBy('__name__').limit(500);
            if (lastDoc) query = query.startAfter(lastDoc);

            const snap = await query.get();
            if (snap.empty) break;

            for (const doc of snap.docs) {
                const userData = doc.data();
                const token    = userData.fcmToken || userData.deviceToken;
                if (!token || userData.disableSeasonalNotifs === true) continue;

                try {
                    await admin.messaging().send({
                        token,
                        notification: { title, body },
                        android: {
                            priority: "high",
                            notification: { channelId: "anyskill_default" },
                        },
                        apns: {
                            headers: { "apns-priority": "10" },
                            payload: { aps: { sound: "default", contentAvailable: 1 } },
                        },
                        webpush: {
                            notification: { icon: '/icons/Icon-192.png' },
                            fcm_options: { link: 'https://anyskill-6fdf3.web.app' },
                        },
                        data: { type: 'seasonal', month: String(month) },
                    });
                    await db.collection('notifications').add({
                        userId: doc.id, title, body, type: 'seasonal',
                        data: { month: String(month) },
                        isRead: false,
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                    totalSent++;
                } catch (e) {
                    console.error(`Seasonal notify error for ${doc.id}:`, e.message);
                }
            }

            lastDoc = snap.docs[snap.docs.length - 1];
        } while (true);

        console.log(`sendSeasonalNotifications: sent ${totalSent} for month ${month}`);
    }
);

// ── Weekly inactivity reminders — every Sunday 11:00 IST ─────────────────────
// Targets customers who haven't booked in 60+ days.
// Requires users/{uid}.lastBookingAt to be stamped on job creation
// (done by awardCreditsOnBooking below via the same trigger).
// Users can opt out via users/{uid}.disableInactivityNotifs = true.

exports.sendInactivityReminders = onSchedule(
    { schedule: '0 11 * * 0', timeZone: 'Asia/Jerusalem', maxInstances: 1 },
    async () => {
        const db     = admin.firestore();
        const cutoff = new Date();
        cutoff.setDate(cutoff.getDate() - 60);
        const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);

        const snap = await db.collection('users')
            .where('isProvider',   '==', false)
            .where('lastBookingAt', '<',  cutoffTs)
            .limit(200)
            .get();

        let sent = 0;
        for (const doc of snap.docs) {
            const userData = doc.data();
            const token    = userData.fcmToken || userData.deviceToken;
            if (!token || userData.disableInactivityNotifs === true) continue;

            const name  = userData.name || 'יקר/ה';
            const title = `${name}, מתגעגעים אליך! 👋`;
            const body  = 'כבר 60 יום לא הזמנת שירות. גלה מה חדש ב-AnySkill!';

            try {
                await admin.messaging().send({
                    token,
                    notification: { title, body },
                    android: {
                        priority: "high",
                        notification: { channelId: "anyskill_default" },
                    },
                    apns: {
                        headers: { "apns-priority": "10" },
                        payload: { aps: { sound: "default", contentAvailable: 1 } },
                    },
                    webpush: {
                        notification: { icon: '/icons/Icon-192.png' },
                        fcm_options: { link: 'https://anyskill-6fdf3.web.app' },
                    },
                    data: { type: 'inactivity_reminder' },
                });
                await db.collection('notifications').add({
                    userId: doc.id, title, body, type: 'inactivity_reminder',
                    data: {}, isRead: false,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                sent++;
            } catch (e) {
                console.error(`Inactivity notify error for ${doc.id}:`, e.message);
            }
        }
        console.log(`sendInactivityReminders: sent ${sent} notifications`);
    }
);

// ── Award loyalty credits when customer creates a booking (+50 credits) ────────
// Also stamps lastBookingAt for the inactivity reminder query above.

exports.awardCreditsOnBooking = onDocumentCreated(
    { document: "jobs/{jobId}", maxInstances: 50 },
    async (event) => {
        const jobData    = event.data.data();
        const customerId = jobData.customerId;
        if (!customerId) return null;

        const db                  = admin.firestore();
        const CREDITS_PER_BOOKING = 50;

        try {
            await db.collection('users').doc(customerId).update({
                credits:       admin.firestore.FieldValue.increment(CREDITS_PER_BOOKING),
                lastBookingAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            console.log(`Credits: +${CREDITS_PER_BOOKING} to customer ${customerId}`);
        } catch (e) {
            console.error('awardCreditsOnBooking error:', e);
        }
        return null;
    }
);

// ── Award loyalty credits when customer leaves a photo review (+30 credits) ───

exports.awardCreditsOnPhotoReview = onDocumentCreated(
    { document: "reviews/{reviewId}", maxInstances: 30 },
    async (event) => {
        const review   = event.data.data();
        const reviewer = review.reviewerId;
        const photos   = review.photos || [];
        if (!reviewer || !Array.isArray(photos) || photos.length === 0) return null;

        const CREDITS_PER_PHOTO_REVIEW = 30;
        const db = admin.firestore();
        try {
            await db.collection('users').doc(reviewer).update({
                credits: admin.firestore.FieldValue.increment(CREDITS_PER_PHOTO_REVIEW),
            });
            console.log(`Credits: +${CREDITS_PER_PHOTO_REVIEW} to reviewer ${reviewer}`);
        } catch (e) {
            console.error('awardCreditsOnPhotoReview error:', e);
        }
        return null;
    }
);

// ─────────────────────────────────────────────────────────────────────────────
// Admin email notification — new user registration
// ─────────────────────────────────────────────────────────────────────────────
//
// HOW IT WORKS
// ─────────────
// Triggers whenever a new document is created in users/{uid}.
// Writes a doc to the `mail` collection, which the Firebase "Trigger Email"
// extension picks up and sends via your configured SMTP provider.
//
// SETUP (one-time)
// ─────────────────
// 1. Install the Firebase Trigger Email extension:
//    https://firebase.google.com/products/extensions/firebase-firestore-send-email
//    Choose "mail" as the collection name when prompted.
//
// 2. Configure SMTP credentials in the extension settings.
//    Recommended free options:
//      • Brevo (formerly Sendinblue) — 300 emails/day free
//        SMTP host: smtp-relay.brevo.com  port: 587
//      • Mailjet — 200 emails/day free
//        SMTP host: in-v3.mailjet.com     port: 587
//    For both: create an account → Settings → SMTP & API → copy credentials.
//
// 3. Deploy this function:
//    firebase deploy --only functions:notifyadminonregister
//
// ─────────────────────────────────────────────────────────────────────────────

const ADMIN_EMAIL = "adawiavihai@gmail.com";

/** Formats a Firestore Timestamp (or null) as a Hebrew locale date-time string. */
function formatDate(ts) {
    if (!ts) return "לא ידוע";
    try {
        return ts.toDate().toLocaleString("he-IL", {
            timeZone:    "Asia/Jerusalem",
            day:         "2-digit",
            month:       "2-digit",
            year:        "numeric",
            hour:        "2-digit",
            minute:      "2-digit",
        });
    } catch (_) {
        return String(ts);
    }
}

/** Returns a badge-style HTML pill for the user type. */
function userTypePill(isProvider) {
    const label = isProvider ? "נותן שירות" : "לקוח";
    const bg    = isProvider ? "#6366F1"    : "#10B981";
    return `<span style="display:inline-block;background:${bg};color:#fff;`
         + `padding:3px 12px;border-radius:99px;font-size:12px;`
         + `font-weight:700;">${label}</span>`;
}

/** Builds the full HTML body for the admin notification email. */
function buildEmailHtml({ uid, name, email, isProvider, userType,
                          createdAt, city, serviceType, businessType, phone }) {
    const accentColor = "#6366F1";
    const bgLight     = "#F5F5FF";

    return `<!DOCTYPE html>
<html dir="rtl" lang="he">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>משתמש חדש נרשם</title>
</head>
<body style="margin:0;padding:0;background:#F0F0FF;font-family:Arial,Helvetica,sans-serif;direction:rtl;">

  <!-- Wrapper -->
  <table width="100%" cellpadding="0" cellspacing="0" border="0"
         style="background:#F0F0FF;padding:32px 16px;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" border="0"
               style="max-width:600px;width:100%;background:#fff;
                      border-radius:20px;overflow:hidden;
                      box-shadow:0 4px 24px rgba(99,102,241,.15);">

          <!-- Header -->
          <tr>
            <td style="background:linear-gradient(135deg,#4F46E5 0%,${accentColor} 50%,#8B5CF6 100%);
                        padding:32px 32px 28px;text-align:center;">
              <div style="font-size:28px;font-weight:900;color:#fff;
                          letter-spacing:0.5px;margin-bottom:6px;">
                AnySkill
              </div>
              <div style="font-size:13px;color:rgba(255,255,255,.80);">
                פאנל ניהול — התראה אוטומטית
              </div>
            </td>
          </tr>

          <!-- Alert banner -->
          <tr>
            <td style="background:#EEF2FF;padding:16px 32px;
                        border-bottom:1px solid #E0E7FF;">
              <table width="100%" cellpadding="0" cellspacing="0">
                <tr>
                  <td style="font-size:22px;vertical-align:middle;">🎉</td>
                  <td width="12"></td>
                  <td>
                    <div style="font-size:16px;font-weight:700;color:#1E1B4B;">
                      משתמש חדש נרשם לפלטפורמה
                    </div>
                    <div style="font-size:12px;color:#6B7280;margin-top:2px;">
                      ${createdAt}
                    </div>
                  </td>
                  <td align="left">${userTypePill(isProvider)}</td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Details card -->
          <tr>
            <td style="padding:28px 32px;">
              <table width="100%" cellpadding="0" cellspacing="0"
                     style="background:${bgLight};border-radius:14px;
                            overflow:hidden;border:1px solid #E0E7FF;">

                ${_row("👤", "שם מלא",         name)}
                ${_row("✉️", "אימייל",          email)}
                ${_row("🏷️", "סוג משתמש",      userType)}
                ${_row("🛠️", "תחום / קטגוריה", serviceType || "לא צוין")}
                ${isProvider ? _row("🏢", "סוג עסק", businessType || "לא צוין") : ""}
                ${_row("📱", "טלפון",           phone || "לא צוין")}
                ${_row("📍", "מיקום",           city)}
                ${_row("🆔", "UID",             uid)}
                ${_row("📅", "תאריך הרשמה",   createdAt)}

              </table>
            </td>
          </tr>

          <!-- CTA -->
          <tr>
            <td style="padding:0 32px 28px;text-align:center;">
              <a href="https://console.firebase.google.com/project/_/firestore/data/~2Fusers~2F${uid}"
                 target="_blank"
                 style="display:inline-block;background:linear-gradient(135deg,#4F46E5,${accentColor});
                         color:#fff;text-decoration:none;font-size:14px;font-weight:700;
                         padding:12px 28px;border-radius:10px;
                         box-shadow:0 4px 12px rgba(99,102,241,.35);">
                פתח בFirestore Console →
              </a>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="background:#F9F9FF;padding:18px 32px;
                        border-top:1px solid #E0E7FF;text-align:center;">
              <div style="font-size:11px;color:#9CA3AF;">
                הודעה זו נשלחה אוטומטית על ידי AnySkill Cloud Functions<br/>
                לא להשיב על מייל זה — לפניות: ${ADMIN_EMAIL}
              </div>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>

</body>
</html>`;
}

/** Returns a single detail row for the details table. */
function _row(emoji, label, value) {
    return `
    <tr>
      <td style="padding:12px 16px;border-bottom:1px solid #E0E7FF;width:36px;
                  font-size:16px;vertical-align:top;">${emoji}</td>
      <td style="padding:12px 8px 12px 0;border-bottom:1px solid #E0E7FF;
                  width:130px;font-size:13px;color:#6B7280;
                  font-weight:600;vertical-align:top;">${label}</td>
      <td style="padding:12px 16px 12px 0;border-bottom:1px solid #E0E7FF;
                  font-size:13px;color:#1E1B4B;
                  font-weight:700;vertical-align:top;">${value}</td>
    </tr>`;
}

// ── The Cloud Function ────────────────────────────────────────────────────────

exports.notifyadminonregister = onDocumentUpdated(
    {
        document:    "users/{uid}",
        maxInstances: 10,
        region:      "us-central1",
    },
    async (event) => {
        if (!event.data) return null;

        const before = event.data.before.data();
        const after  = event.data.after.data();
        const uid    = event.params.uid;

        // Only fire when onboardingComplete transitions false → true
        if (before.onboardingComplete === true || after.onboardingComplete !== true) return null;

        // Skip system-created users (e.g. service accounts)
        if (uid === "anyskill_system") return null;

        const data        = after;
        const isProvider  = data.isProvider === true;
        const name        = data.name        || "לא צוין";
        const email       = data.email       || "לא צוין";
        const phone       = data.phone       || "";
        const serviceType = isProvider ? (data.serviceType || "לא צוין") : "—";
        const businessType = isProvider ? (data.businessType || "לא צוין") : null;
        const userType    = isProvider ? "נותן שירות (ספק)" : "לקוח";

        // Location: try multiple field names your app might populate
        const city = data.city
            || data.locationCity
            || data.location
            || (data.locationData && data.locationData.city)
            || "לא צוין";

        const createdAt = formatDate(data.createdAt);

        const html = buildEmailHtml({
            uid, name, email, isProvider, userType,
            createdAt, city, serviceType, businessType, phone,
        });

        const subject = `🆕 [AnySkill] נרשם ${userType}: ${name}`;

        // ── Method A: Firebase Trigger Email extension (recommended) ──────────
        // Writes a doc to the `mail` collection; the extension delivers it.
        // Make sure the extension is installed and SMTP is configured.
        try {
            await admin.firestore().collection("mail").add({
                to:      ADMIN_EMAIL,
                message: { subject, html },
            });
            console.log(`Admin notification sent for new user: ${uid} (${email})`);
        } catch (err) {
            console.error("notifyadminonregister: failed to queue mail doc:", err);
        }

        return null;

        // ── Method B: Nodemailer (alternative — uncomment if you prefer SMTP) ─
        //
        // SETUP:
        //   1. cd functions && npm install nodemailer
        //   2. firebase functions:secrets:set SMTP_USER SMTP_PASS
        //   3. Add "runWith({ secrets: ['SMTP_USER','SMTP_PASS'] })" to the
        //      function options (v2 syntax shown below).
        //
        // const nodemailer = require("nodemailer");
        // const { defineSecret } = require("firebase-functions/params");
        // const SMTP_USER = defineSecret("SMTP_USER");
        // const SMTP_PASS = defineSecret("SMTP_PASS");
        //
        // const transporter = nodemailer.createTransport({
        //     host: "smtp-relay.brevo.com",   // or smtp.mailjet.com
        //     port: 587,
        //     secure: false,
        //     auth: {
        //         user: SMTP_USER.value(),
        //         pass: SMTP_PASS.value(),
        //     },
        // });
        //
        // await transporter.sendMail({
        //     from: `"AnySkill Admin" <${SMTP_USER.value()}>`,
        //     to:   ADMIN_EMAIL,
        //     subject,
        //     html,
        // });
    }
);

// =============================================================================
// ─── AI Category Mapping Engine ───────────────────────────────────────────────
// =============================================================================
//
// Flow:
//   1. Provider completes onboarding → Flutter calls `categorizeprovider`
//   2. Function fetches live categories from Firestore + calls Claude
//   3a. Confidence ≥ 0.90  → auto-assign, update user.serviceType immediately
//   3b. Confidence < 0.90  → write to `categories_pending`, email admin
//   4. Admin opens PendingCategoriesScreen → calls `approvecategory`
//   5. Approval creates a real `categories` doc; provider is updated
// =============================================================================

// ── System prompt (injected into every Claude call) ───────────────────────────
const _CATEGORY_SYSTEM_PROMPT = `\
You are AnySkill's category routing AI for an Israeli service marketplace.
Your task: given a service provider's free-text description, map it to the best
existing category OR create a normalized new category + subcategory.

RESPOND WITH ONLY VALID JSON — no markdown fences, no explanation text.

Required JSON schema:
{
  "action":                     "match" | "new",
  "confidence":                 0.0–1.0,
  "matched_category_id":        "<Firestore doc ID> | null",
  "matched_category_name":      "<Hebrew name> | null",
  "suggested_category_name":    "<Hebrew name> | null",
  "suggested_subcategory_name": "<Hebrew name> | null",
  "image_prompt":               "<English Midjourney/DALL-E prompt> | null",
  "keywords":                   ["<Hebrew keyword>", ...],
  "reasoning":                  "<brief Hebrew explanation>"
}

Rules:
• action="match"  when confidence >= 0.90 — fill matched_category_id/name
• action="new"    when confidence <  0.90 — fill suggested_category_name
• suggested_subcategory_name is ALWAYS required for BOTH actions — never null or empty.
  For match: derive the subcategory from the provider's specific service within that category.
  For new:   generate a specific subcategory for the new category.

NORMALIZATION (critical):
• Always use the broadest, most standard industry category name.
  Examples: "Cat Sitter" → category="טיפול בחיות מחמד", sub="שמירה על חתולים"
            "Kitty Care" → category="טיפול בחיות מחמד", sub="טיפול בחתולים"
            "Wedding DJ" → category="מוזיקה ואירועים", sub="DJ לאירועים"
            "Excel Tutor" → category="שיעורים פרטיים", sub="הדרכת Excel"
            "House cleaner" → category="ניקיון", sub="ניקיון דירות"
            "Window washer" → category="ניקיון", sub="ניקיון חלונות"
• Different descriptions of the same profession MUST produce the SAME category name.
• Avoid overly specific or literal translations of the user's words.
• Prefer existing categories when semantically close (confidence threshold 0.85 is enough for a very close match).
• suggested_category_name must be 2–4 Hebrew words, general, reusable across many providers.
• suggested_subcategory_name must be 2–5 Hebrew words, specific to this provider's exact service.

• image_prompt (new categories only): professional Israeli service photo —
  real person in action, clean bright background, photorealistic 8K.
• keywords: 4–7 Hebrew synonyms/related terms for semantic search.
• reasoning: one sentence in Hebrew explaining your decision.
• Output JSON only. Any non-JSON output will cause an error.`;

// ── Helper: email HTML for pending-category admin alert ───────────────────────
function buildPendingCategoryEmail({ uid, serviceDescription, suggestedCategoryName,
    suggestedSubCategoryName, imagePrompt, confidence, reasoning, pendingId }) {
    const pct = Math.round((confidence || 0) * 100);
    return `<!DOCTYPE html>
<html dir="rtl" lang="he">
<head><meta charset="UTF-8"/><title>קטגוריה ממתינה</title></head>
<body style="margin:0;padding:24px;background:#F0F0FF;font-family:Arial,sans-serif;direction:rtl;">
  <div style="max-width:560px;margin:auto;background:#fff;border-radius:16px;overflow:hidden;
              box-shadow:0 4px 20px rgba(99,102,241,.15);">
    <div style="background:linear-gradient(135deg,#4F46E5,#6366F1,#8B5CF6);padding:28px 28px 20px;text-align:center;">
      <div style="font-size:24px;font-weight:900;color:#fff;">AnySkill 🤖</div>
      <div style="font-size:13px;color:rgba(255,255,255,.8);margin-top:4px;">קטגוריה חדשה ממתינה לאישורך</div>
    </div>
    <div style="padding:24px 28px;">
      <table width="100%" cellpadding="0" cellspacing="0">
        <tr><td style="padding:8px 0;color:#6B7280;font-size:13px;">תיאור הספק</td>
            <td style="padding:8px 0;font-weight:700;font-size:14px;text-align:left;">${serviceDescription}</td></tr>
        <tr><td style="padding:8px 0;color:#6B7280;font-size:13px;">קטגוריה מוצעת</td>
            <td style="padding:8px 0;font-weight:700;font-size:14px;color:#6366F1;text-align:left;">${suggestedCategoryName || "—"}</td></tr>
        <tr><td style="padding:8px 0;color:#6B7280;font-size:13px;">תת-קטגוריה</td>
            <td style="padding:8px 0;font-size:13px;text-align:left;">${suggestedSubCategoryName || "—"}</td></tr>
        <tr><td style="padding:8px 0;color:#6B7280;font-size:13px;">ביטחון AI</td>
            <td style="padding:8px 0;text-align:left;">
              <span style="background:#FEF3C7;color:#D97706;padding:3px 10px;border-radius:99px;font-size:12px;font-weight:700;">${pct}%</span>
            </td></tr>
        <tr><td style="padding:8px 0;color:#6B7280;font-size:13px;">הנמקה</td>
            <td style="padding:8px 0;font-size:13px;text-align:left;">${reasoning || "—"}</td></tr>
        ${imagePrompt ? `<tr><td style="padding:8px 0;color:#6B7280;font-size:13px;">פרומפט לתמונה</td>
            <td style="padding:8px 0;font-size:11px;color:#6366F1;text-align:left;font-style:italic;">${imagePrompt}</td></tr>` : ""}
        <tr><td style="padding:8px 0;color:#6B7280;font-size:13px;">UID הספק</td>
            <td style="padding:8px 0;font-size:11px;color:#9CA3AF;text-align:left;">${uid}</td></tr>
      </table>
      <div style="margin-top:20px;text-align:center;">
        <a href="https://console.firebase.google.com/project/anyskill-6fdf3/firestore/data/~2Fcategories_pending~2F${pendingId}"
           style="display:inline-block;background:linear-gradient(135deg,#4F46E5,#6366F1);color:#fff;
                  text-decoration:none;padding:12px 28px;border-radius:10px;font-weight:700;font-size:14px;">
          פתח בקונסול לאישור ←
        </a>
      </div>
    </div>
  </div>
</body></html>`;
}

// ── categorizeprovider — callable from Flutter ────────────────────────────────
exports.categorizeprovider = onCall(
    { secrets: [ANTHROPIC_API_KEY], maxInstances: 10, region: "us-central1", memory: "512MiB" },
    async (request) => {
        // Auth is optional — callers during sign-up are not yet authenticated.
        // uid is null for anonymous callers; user-doc writes are skipped below.
        const uid = request.auth?.uid || null;

        const { serviceDescription } = request.data;
        if (!serviceDescription || typeof serviceDescription !== "string" || serviceDescription.trim().length < 2) {
            throw new HttpsError("invalid-argument", "serviceDescription is required");
        }

        const db  = admin.firestore();

        // 1. Fetch all top-level live categories from Firestore
        const catSnap = await db.collection("categories")
            .where("parentId", "==", "")
            .limit(60)
            .get();

        const existingCategories = catSnap.docs.map(d => ({
            id:       d.id,
            name:     d.data().name     || "",
            keywords: d.data().keywords || [],
        }));

        // 2. Build the user message
        const categoryList = existingCategories.length > 0
            ? existingCategories
                .map((c, i) => `${i + 1}. id="${c.id}" name="${c.name}"${c.keywords.length ? ` keywords=[${c.keywords.join(", ")}]` : ""}`)
                .join("\n")
            : "(no categories exist yet — suggest a new one)";

        const userMessage =
            `Provider service description: "${serviceDescription.trim()}"\n\n` +
            `Existing categories:\n${categoryList}\n\n` +
            `Map this provider. Return JSON only.`;

        // 3. Call Claude (haiku — fast + cheap for classification)
        // ── Secret resolution ────────────────────────────────────────────────
        // For Gen2 functions, defineSecret() binds the secret as both
        // ANTHROPIC_API_KEY.value() AND process.env.ANTHROPIC_API_KEY.
        // We try both paths so the diagnostic is unambiguous.
        const apiKey = ANTHROPIC_API_KEY.value() || process.env.ANTHROPIC_API_KEY || "";
        console.log(`categorizeprovider: secret via .value()=${!!ANTHROPIC_API_KEY.value()} via env=${!!process.env.ANTHROPIC_API_KEY} finalLength=${apiKey.length}`);

        if (!apiKey) {
            // Return a clear sentinel instead of a generic internal error.
            throw new HttpsError(
                "internal",
                "SECRET_MISSING: ANTHROPIC_API_KEY is not bound to this function. " +
                "Run: firebase functions:secrets:set ANTHROPIC_API_KEY " +
                "then redeploy: firebase deploy --only functions:categorizeprovider",
            );
        }

        let parsed;
        try {
            // Anthropic is required at top level (CJS) — do NOT use dynamic import here
            const anthropic = new Anthropic({ apiKey });

            const msg = await anthropic.messages.create({
                model:      "claude-haiku-4-5-20251001",
                max_tokens: 512,
                system:     _CATEGORY_SYSTEM_PROMPT,
                messages:   [{ role: "user", content: userMessage }],
            });

            _trackApiCost(admin.firestore(), msg.usage?.input_tokens || 0, msg.usage?.output_tokens || 0).catch(() => {});
            const raw = (msg.content[0]?.text ?? "{}").replace(/```(?:json)?\s*/gi, "").replace(/```/g, "").trim();
            parsed = JSON.parse(raw);
        } catch (err) {
            // Surface the REAL error — class name + message — so it shows in
            // the Flutter snackbar instead of a generic "internal" string.
            const realMessage = err?.message || err?.toString() || "unknown";
            const errType     = err?.constructor?.name || "Error";
            console.error("categorizeprovider: AI call failed:", err);
            throw new HttpsError("internal", `[${errType}] ${realMessage}`);
        }

        const {
            action, confidence,
            matched_category_id, matched_category_name,
            suggested_category_name, suggested_subcategory_name,
            image_prompt, keywords = [], reasoning,
        } = parsed;

        // subCategoryName is always populated by the prompt (for both match and new)
        const subName = suggested_subcategory_name || null;

        // ── 3a. High-confidence match ────────────────────────────────────────
        // Pure classification — no DB writes. Client calls finalizecategorysetup on submit.
        if (action === "match" && matched_category_id && (confidence ?? 0) >= 0.90) {
            console.log(`categorizeprovider: match uid=${uid ?? "anon"} → "${matched_category_name}" / "${subName}" (${Math.round((confidence ?? 0) * 100)}%)`);
            return {
                action:          "match",
                categoryId:      matched_category_id,
                categoryName:    matched_category_name,
                subCategoryName: subName,
                confidence,
                reasoning,
            };
        }

        // ── 3b. New / low-confidence — return AI-generated names only ────────
        const normalizedName = suggested_category_name || serviceDescription.trim();

        console.log(`categorizeprovider: new uid=${uid ?? "anon"} → "${normalizedName}" / "${subName}" (${Math.round((confidence ?? 0) * 100)}%)`);
        return {
            action:          "new",
            categoryName:    normalizedName,
            subCategoryName: subName,
            confidence,
            reasoning,
        };
    }
);

// ── finalizecategorysetup — called from Flutter on 'Create Profile' ───────────
// Creates / finds the category + subcategory in Firestore, updates the user doc,
// writes admin_log, and sends email. Separated from classify so that DB writes
// only happen when the user actually submits — not on every AI preview.
exports.finalizecategorysetup = onCall(
    { maxInstances: 10, region: "us-central1" },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Authentication required");
        }

        const uid = request.auth.uid;
        const {
            categoryName, subCategoryName,
            matchedCategoryId,           // present when AI found an existing category
            serviceDescription = "",
            confidence = 0, reasoning = "",
        } = request.data;

        if (!categoryName) {
            throw new HttpsError("invalid-argument", "categoryName is required");
        }

        const db  = admin.firestore();
        const now = admin.firestore.FieldValue.serverTimestamp();

        // ── 1. Resolve or create the parent category ─────────────────────────
        let catId = matchedCategoryId || null;
        if (!catId) {
            const q = await db.collection("categories")
                .where("name",     "==", categoryName)
                .where("parentId", "==", "")
                .limit(1).get();
            if (!q.empty) {
                catId = q.docs[0].id;
            } else {
                const ref = db.collection("categories").doc();
                await ref.set({
                    name:        categoryName,
                    parentId:    "",
                    isActive:    true,
                    autoCreated: true,
                    createdAt:   now,
                });
                catId = ref.id;
            }
        }

        // ── 2. Resolve or create the subcategory ─────────────────────────────
        let subCatId = null;
        if (subCategoryName) {
            const q2 = await db.collection("categories")
                .where("name",     "==", subCategoryName)
                .where("parentId", "==", catId)
                .limit(1).get();
            if (!q2.empty) {
                subCatId = q2.docs[0].id;
            } else {
                const subRef = db.collection("categories").doc();
                await subRef.set({
                    name:        subCategoryName,
                    parentId:    catId,
                    isActive:    true,
                    autoCreated: true,
                    createdAt:   now,
                });
                subCatId = subRef.id;
            }
        }

        // ── 3. Update user doc with resolved IDs ─────────────────────────────
        const userUpdate = { categoryId: catId, categoryStatus: "approved" };
        if (subCatId)        userUpdate.subCategoryId   = subCatId;
        if (subCategoryName) userUpdate.subCategoryName = subCategoryName;
        try {
            // update() requires the doc to exist. Use set+merge as fallback in case
            // Firestore propagation hasn't completed by the time we reach this step.
            await db.collection("users").doc(uid).update(userUpdate);
        } catch (_) {
            await db.collection("users").doc(uid).set(userUpdate, { merge: true });
        }

        // ── 4. Admin log + email — run in parallel to cut latency ────────────
        const isNew = !matchedCategoryId;
        const logEntry = {
            type:               isNew ? "new_category" : "matched_category",
            categoryId:         catId,
            categoryName,
            subCategoryName:    subCategoryName || null,
            subCategoryId:      subCatId,
            triggerDescription: serviceDescription,
            triggerUid:         uid,
            confidence,
            reasoning,
            isNew,
            isReviewed:         false,
            createdAt:          now,
        };
        const subject = isNew
            ? `🤖 [AnySkill] קטגוריה חדשה נוצרה: ${categoryName}`
            : `✅ [AnySkill] ספק חדש בקטגוריה: ${categoryName} / ${subCategoryName || "—"}`;
        const mailEntry = {
            to: ADMIN_EMAIL,
            message: {
                subject,
                html: buildPendingCategoryEmail({
                    uid, serviceDescription,
                    suggestedCategoryName:    categoryName,
                    suggestedSubCategoryName: subCategoryName,
                    imagePrompt:              null,
                    confidence, reasoning,
                    pendingId: catId,
                }),
            },
        };
        await Promise.all([
            db.collection("admin_logs").add(logEntry),
            db.collection("mail").add(mailEntry).catch(e =>
                console.warn("finalizecategorysetup: mail failed:", e)),
        ]);

        console.log(`finalizecategorysetup: uid=${uid} cat="${categoryName}"(${catId}) sub="${subCategoryName}"(${subCatId}) isNew=${isNew}`);
        return { categoryId: catId, subCategoryId: subCatId };
    }
);

// ── approvecategory — admin-only callable ─────────────────────────────────────
exports.approvecategory = onCall(
    { maxInstances: 5, region: "us-central1" },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Authentication required");
        }

        // Guard: caller must be admin
        const callerSnap = await admin.firestore()
            .collection("users").doc(request.auth.uid).get();
        if (!callerSnap.exists || callerSnap.data()?.isAdmin !== true) {
            throw new HttpsError("permission-denied", "Admin only");
        }

        const { pendingId, action } = request.data; // action: "approve" | "reject"
        if (!pendingId || !["approve", "reject"].includes(action)) {
            throw new HttpsError("invalid-argument", "pendingId and action ('approve'|'reject') required");
        }

        const db          = admin.firestore();
        const pendingRef  = db.collection("categories_pending").doc(pendingId);
        const pendingSnap = await pendingRef.get();

        if (!pendingSnap.exists) {
            throw new HttpsError("not-found", "Pending category not found");
        }
        const pending = pendingSnap.data();
        const now     = admin.firestore.FieldValue.serverTimestamp();

        // ── Reject ───────────────────────────────────────────────────────────
        if (action === "reject") {
            await Promise.all([
                pendingRef.update({ status: "rejected", reviewedAt: now, reviewedBy: request.auth.uid }),
                db.collection("users").doc(pending.uid).update({ categoryStatus: "rejected" }),
            ]);
            return { success: true, action: "rejected" };
        }

        // ── Approve: create the live category (and optional sub-category) ────
        const orderSnap = await db.collection("categories")
            .orderBy("order", "desc").limit(1).get();
        const nextOrder = (orderSnap.docs[0]?.data()?.order ?? 0) + 1;

        const newCatRef = await db.collection("categories").add({
            name:         pending.suggestedCategoryName,
            parentId:     "",
            iconName:     "stars",
            img:          "",            // admin pastes Midjourney URL here later
            imagePrompt:  pending.imagePrompt  || null,
            keywords:     pending.keywords     || [],
            order:        nextOrder,
            bookingCount: 0,
            isActive:     true,
            createdBy:    "ai",
            createdAt:    now,
        });

        const ops = [
            pendingRef.update({
                status:             "approved",
                approvedCategoryId: newCatRef.id,
                reviewedAt:         now,
                reviewedBy:         request.auth.uid,
            }),
            db.collection("users").doc(pending.uid).update({
                categoryId:     newCatRef.id,
                serviceType:    pending.suggestedCategoryName,
                categoryStatus: "approved",
            }),
        ];

        if (pending.suggestedSubCategoryName) {
            ops.push(
                db.collection("categories").add({
                    name:         pending.suggestedSubCategoryName,
                    parentId:     newCatRef.id,
                    iconName:     "stars",
                    img:          "",
                    keywords:     [],
                    order:        1,
                    bookingCount: 0,
                    isActive:     true,
                    createdBy:    "ai",
                    createdAt:    now,
                })
            );
        }

        await Promise.all(ops);

        console.log(`approvecategory: approved pendingId=${pendingId} → newCategoryId=${newCatRef.id}`);
        return { success: true, action: "approved", newCategoryId: newCatRef.id };
    }
);

// ── Market Opportunity Monitor ─────────────────────────────────────────────────
// Triggers on every new search_log document.
// When a zero-result keyword exceeds the admin-configured threshold within 24h,
// sends a high-priority FCM push to all admin devices and records the alert.

exports.marketopportunitymonitor = onDocumentCreated(
    "search_logs/{logId}",
    async (event) => {
        const data = event.data?.data();
        if (!data || !data.zeroResults) return null;

        const query = (data.query || "").trim().toLowerCase();
        if (query.length < 2) return null;

        const db = admin.firestore();

        // ── 0. Always track zero-result searches for Business AI analysis ─────
        // Upserts a market_opportunities doc so the AI dashboard can surface gaps.
        try {
            const oppId  = query.replace(/[/.]/g, "_").substring(0, 100);
            await db.collection("market_opportunities").doc(oppId).set({
                query,
                searchCount:    admin.firestore.FieldValue.increment(1),
                lastSearchedAt: admin.firestore.FieldValue.serverTimestamp(),
                analyzed:       false,
            }, { merge: true });
        } catch (e) {
            console.warn(`marketopportunitymonitor: market_opportunities write failed — ${e.message}`);
        }

        // ── 1. Read alert threshold from admin settings ──────────────────────
        const settingsSnap = await db
            .collection("admin").doc("admin")
            .collection("settings").doc("settings")
            .get();
        const threshold = Number((settingsSnap.data() || {}).marketAlertThreshold) || 5;

        // ── 2. Count zero-result occurrences of this keyword in last 24h ─────
        const since = new Date(Date.now() - 24 * 60 * 60 * 1000);
        const countSnap = await db
            .collection("search_logs")
            .where("query",       "==", query)
            .where("zeroResults", "==", true)
            .where("timestamp",   ">=", admin.firestore.Timestamp.fromDate(since))
            .limit(threshold + 1) // fetch one extra to confirm threshold crossed
            .get();

        if (countSnap.size < threshold) return null;

        // ── 3. Deduplicate — only one alert per keyword per calendar day ──────
        const alertId  = query.replace(/[/.]/g, "_").substring(0, 100);
        const alertRef = db.collection("market_alerts").doc(alertId);
        const alertDoc = await alertRef.get();
        const alertData = alertDoc.data() || {};

        if (alertData.lastAlertedAt) {
            const lastAlerted = alertData.lastAlertedAt.toDate();
            const todayStart  = new Date();
            todayStart.setHours(0, 0, 0, 0);
            if (lastAlerted >= todayStart) {
                console.log(`marketopportunitymonitor: already alerted today for "${query}"`);
                return null;
            }
        }

        // ── 4. Record the alert ───────────────────────────────────────────────
        await alertRef.set({
            keyword:       query,
            searchCount:   countSnap.size,
            threshold:     threshold,
            lastAlertedAt: admin.firestore.FieldValue.serverTimestamp(),
            totalAlerts:   admin.firestore.FieldValue.increment(1),
        }, { merge: true });

        // ── 5. Collect admin FCM tokens ───────────────────────────────────────
        const adminSnap = await db
            .collection("users")
            .where("isAdmin", "==", true)
            .limit(5)
            .get();

        const tokens = adminSnap.docs
            .map(d => d.data().fcmToken)
            .filter(t => typeof t === "string" && t.length > 10);

        if (tokens.length === 0) {
            console.log(`marketopportunitymonitor: no admin FCM tokens — alert recorded but not pushed`);
            return null;
        }

        // ── 6. Send high-priority FCM push to all admin devices ───────────────
        const response = await admin.messaging().sendEachForMulticast({
            notification: {
                title: "🚀 הזדמנות שוק זוהתה!",
                body:  `${countSnap.size} משתמשים חיפשו "${query}" היום ולא קיבלו תוצאות — הגיע הזמן לגייס ספקים!`,
            },
            data: {
                type:        "market_opportunity",
                keyword:     query,
                searchCount: String(countSnap.size),
                screen:      "business_ai",
            },
            tokens,
            android: {
                priority: "high",
                notification: { channelId: "market_alerts" },
            },
            apns: {
                payload: { aps: { sound: "default", badge: 1 } },
            },
        });

        console.log(
            `marketopportunitymonitor: keyword="${query}" count=${countSnap.size}/${threshold} ` +
            `→ ${response.successCount} delivered, ${response.failureCount} failed`
        );
        return null;
    }
);

// ── updateUserXP (Callable) ────────────────────────────────────────────────
// Awards or deducts XP from a user based on a named event.
// Reads the points value from settings_gamification/{eventId} so admins can
// tune every event without a code deploy.
// After updating XP the function recalculates the user's level using the
// thresholds stored in settings_gamification/app_levels.
//
// Call from Flutter:
//   await FirebaseFunctions.instance
//       .httpsCallable('updateUserXP')
//       .call({'userId': uid, 'eventId': 'finish_job'});
//
exports.updateUserXP = onCall(
    { maxInstances: 50 },
    async (request) => {
        // ── 1. Auth guard ─────────────────────────────────────────────────
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Authentication required.");
        }

        const { userId, eventId } = request.data;
        if (!userId || !eventId) {
            throw new HttpsError("invalid-argument", "userId and eventId are required.");
        }

        const db = admin.firestore();

        // ── 2. Read event definition ──────────────────────────────────────
        const eventSnap = await db
            .collection("settings_gamification")
            .doc(eventId)
            .get();

        if (!eventSnap.exists) {
            throw new HttpsError("not-found", `XP event '${eventId}' not found in settings_gamification.`);
        }

        const eventData = eventSnap.data();
        const points    = typeof eventData.points === "number" ? eventData.points : 0;

        // ── 3. Read level thresholds (with sensible defaults) ─────────────
        const levelsSnap = await db
            .collection("settings_gamification")
            .doc("app_levels")
            .get();

        const levels          = levelsSnap.data() || {};
        const silverThreshold = typeof levels.silver === "number" ? levels.silver : 500;
        const goldThreshold   = typeof levels.gold   === "number" ? levels.gold   : 2000;

        // ── 4. Atomic transaction: increment XP + recalculate level ───────
        let finalXp    = 0;
        let finalLevel = "bronze";
        let oldLevel   = "bronze";

        await db.runTransaction(async (t) => {
            const userRef  = db.collection("users").doc(userId);
            const userSnap = await t.get(userRef);

            if (!userSnap.exists) {
                throw new HttpsError("not-found", `User ${userId} not found.`);
            }

            const userData  = userSnap.data();
            const currentXp =
                typeof userData.current_xp === "number" ? userData.current_xp :
                typeof userData.xp          === "number" ? userData.xp          : 0;

            oldLevel = userData.level || "bronze";

            // XP floor is 0 — providers cannot go into negative
            finalXp = Math.max(0, currentXp + points);

            if      (finalXp >= goldThreshold)   finalLevel = "gold";
            else if (finalXp >= silverThreshold) finalLevel = "silver";
            else                                 finalLevel = "bronze";

            t.update(userRef, {
                current_xp: finalXp,
                xp:         finalXp,   // keep legacy xp field in sync
                level:      finalLevel,
            });
        });

        const levelChanged = finalLevel !== oldLevel;

        console.log(
            `[updateUserXP] user=${userId} event=${eventId} ` +
            `Δ${points >= 0 ? "+" : ""}${points} → xp=${finalXp} level=${finalLevel}` +
            (levelChanged ? ` 🎉 LEVEL UP: ${oldLevel} → ${finalLevel}` : "")
        );

        // ── 5. Send level-up push notification if level improved ──────────
        if (levelChanged && finalLevel !== "bronze") {
            try {
                const userSnap = await db.collection("users").doc(userId).get();
                const token    = (userSnap.data() || {}).fcmToken;
                const levelNames = { silver: "כסף 🥈", gold: "זהב 🥇" };

                if (token) {
                    await admin.messaging().send({
                        token,
                        notification: {
                            title: "🎉 עלית רמה!",
                            body:  `כל הכבוד! הגעת לרמת ${levelNames[finalLevel] || finalLevel}!`,
                        },
                        data: { type: "level_up", newLevel: finalLevel },
                        android: { priority: "high" },
                        apns:    { payload: { aps: { sound: "default" } } },
                    });
                }
            } catch (notifErr) {
                // Non-fatal — XP was already updated
                console.warn(`[updateUserXP] level-up notification failed: ${notifErr.message}`);
            }
        }

        return { success: true, points, newXp: finalXp, newLevel: finalLevel, levelChanged };
    }
);

// ── expireStories (Scheduled) ──────────────────────────────────────────────
// Runs every 30 minutes.
// Scans the `stories` collection for documents where expiresAt < now.
// For each expired story:
//   1. Sets stories/{uid}.hasActive = false  (removes it from the discovery feed)
//   2. Sets users/{uid}.hasActiveStory = false  (removes the ranking boost)
//
// The story document is intentionally kept for analytics / history.
// A provider's next upload simply overwrites it.
exports.expireStories = onSchedule(
    { schedule: "every 30 minutes", timeZone: "Asia/Jerusalem" },
    async () => {
        const db  = admin.firestore();
        const now = admin.firestore.Timestamp.now();

        const expiredSnap = await db
            .collection("stories")
            .where("hasActive",  "==",       true)
            .where("expiresAt",  "<=",       now)
            .limit(200)
            .get();

        if (expiredSnap.empty) {
            console.log("[expireStories] No expired stories found.");
            return;
        }

        const batch = db.batch();
        const uids  = [];

        for (const doc of expiredSnap.docs) {
            // Mark story as inactive
            batch.update(doc.ref, { hasActive: false });
            uids.push(doc.id); // doc.id === uid
        }

        // Flip hasActiveStory = false on every affected user profile
        for (const uid of uids) {
            batch.update(db.collection("users").doc(uid), {
                hasActiveStory: false,
            });
        }

        await batch.commit();
        console.log(`[expireStories] Expired ${uids.length} stories: ${uids.join(", ")}`);
    }
);

// ── onStoryPublished (Firestore trigger) ──────────────────────────────────
// Fires when a provider writes / overwrites their stories/{uid} document.
// Awards XP for the story_upload event via the updateUserXP callable logic
// (duplicated inline here to avoid a cross-function call, which would add
// latency and an extra billing unit).
exports.onStoryPublished = onDocumentCreated(
    { document: "stories/{uid}" },
    async (event) => {
        const uid  = event.params.uid;
        const data = event.data?.data();
        if (!data || !data.hasActive) return null;

        const db = admin.firestore();

        // Read story_upload event points from settings_gamification
        const eventSnap = await db
            .collection("settings_gamification")
            .doc("story_upload")
            .get();

        if (!eventSnap.exists) {
            console.log("[onStoryPublished] story_upload event not found in settings — XP skipped.");
            return null;
        }

        const points = typeof eventSnap.data().points === "number"
            ? eventSnap.data().points
            : 5;

        // Read level thresholds
        const levelsSnap = await db
            .collection("settings_gamification")
            .doc("app_levels")
            .get();
        const levels          = levelsSnap.data() || {};
        const silverThreshold = levels.silver ?? 500;
        const goldThreshold   = levels.gold   ?? 2000;

        let finalXp = 0; let finalLevel = "bronze";

        await db.runTransaction(async (t) => {
            const userRef  = db.collection("users").doc(uid);
            const userSnap = await t.get(userRef);
            if (!userSnap.exists) return;

            const currentXp = typeof userSnap.data().current_xp === "number"
                ? userSnap.data().current_xp
                : (userSnap.data().xp || 0);

            finalXp = Math.max(0, currentXp + points);
            if      (finalXp >= goldThreshold)   finalLevel = "gold";
            else if (finalXp >= silverThreshold) finalLevel = "silver";
            else                                 finalLevel = "bronze";

            t.update(userRef, { current_xp: finalXp, xp: finalXp, level: finalLevel });
        });

        console.log(`[onStoryPublished] uid=${uid} story XP +${points} → xp=${finalXp} level=${finalLevel}`);
        return null;
    }
);

// ── resolveDisputeAdmin — Admin-only: arbitrate a disputed job ─────────────────
// Callable from DisputeResolutionScreen (Flutter admin panel only).
// resolution: 'refund' | 'release' | 'split'
// refund     → full totalAmount back to customer; expert gets 0.
// release    → expert gets totalAmount×(1−fee); platform earns fee.
// split      → customer gets 50%; expert gets 50%×(1−fee); platform earns 50%×fee.
exports.resolveDisputeAdmin = onCall(
    { maxInstances: 10 },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Authentication required.");
        }

        const db       = admin.firestore();
        const callerId = request.auth.uid;

        // ── Admin guard ────────────────────────────────────────────────────────
        const callerSnap = await db.collection("users").doc(callerId).get();
        const isAdminUser =
            callerSnap.exists &&
            (callerSnap.data().isAdmin === true ||
             request.auth.token.email === "adawiavihai@gmail.com");
        if (!isAdminUser) {
            throw new HttpsError("permission-denied", "Admin access required.");
        }

        const { jobId, resolution, adminNote } = request.data;
        if (!jobId || !["refund", "release", "split"].includes(resolution)) {
            throw new HttpsError("invalid-argument", "jobId and valid resolution are required.");
        }

        const jobRef  = db.collection("jobs").doc(jobId);

        // All balance mutations inside a transaction to prevent race conditions
        let customerId, expertId, totalAmount, newStatus;
        let customerCredit = 0, expertCredit = 0, platformFee = 0;

        await db.runTransaction(async (t) => {
            const jobSnap = await t.get(jobRef);
            if (!jobSnap.exists) throw new HttpsError("not-found", "Job not found.");

            const job = jobSnap.data();
            if (job.status !== "disputed") {
                throw new HttpsError("failed-precondition", `Job is not disputed (status: ${job.status}).`);
            }

            customerId  = job.customerId;
            expertId    = job.expertId;
            totalAmount = typeof job.totalAmount === "number" ? job.totalAmount : 0;

            // Read fee from admin settings inside the transaction
            const settingsRef  = db.collection("admin").doc("admin")
                                   .collection("settings").doc("settings");
            const settingsSnap = await t.get(settingsRef);
            const feePct       = typeof settingsSnap.data()?.feePercentage === "number"
                ? settingsSnap.data().feePercentage
                : 0.10;

            const customerRef = db.collection("users").doc(customerId);
            const expertRef   = db.collection("users").doc(expertId);

            if (resolution === "refund") {
                // Full refund to customer — expert loses all
                customerCredit = totalAmount;
                expertCredit   = 0;
                platformFee    = 0;
                newStatus      = "refunded";

                t.update(customerRef, { balance: admin.firestore.FieldValue.increment(customerCredit) });

            } else if (resolution === "release") {
                // Release escrow to expert (minus platform fee)
                platformFee    = roundNIS(totalAmount * feePct);
                expertCredit   = roundNIS(totalAmount - platformFee);
                customerCredit = 0;
                newStatus      = "completed";

                t.update(expertRef, { balance: admin.firestore.FieldValue.increment(expertCredit) });

                // Record platform earning
                t.set(db.collection("platform_earnings").doc(), {
                    jobId,
                    amount:    platformFee,
                    type:      "dispute_release_fee",
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                });

            } else {
                // Split 50 / 50
                const half     = roundNIS(totalAmount * 0.5);
                customerCredit = half;
                platformFee    = roundNIS(half * feePct);
                expertCredit   = roundNIS(half - platformFee);
                newStatus      = "split_resolved";

                t.update(customerRef, { balance: admin.firestore.FieldValue.increment(customerCredit) });
                t.update(expertRef,   { balance: admin.firestore.FieldValue.increment(expertCredit)   });

                // Record platform earning
                t.set(db.collection("platform_earnings").doc(), {
                    jobId,
                    amount:    platformFee,
                    type:      "dispute_split_fee",
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                });
            }

            // Update job status
            t.update(jobRef, {
                status:          newStatus,
                resolvedAt:      admin.firestore.FieldValue.serverTimestamp(),
                resolvedBy:      callerId,
                resolutionType:  resolution,
                adminNote:       adminNote || "",
            });

            // Transaction history — customer
            if (customerCredit > 0) {
                t.set(db.collection("transactions").doc(), {
                    userId:    customerId,
                    amount:    customerCredit,
                    title:     resolution === "refund" ? "החזר כספי — מחלוקת" : "פשרה — מחלוקת (50%)",
                    type:      "credit",
                    jobId,
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                });
            }

            // Transaction history — expert
            if (expertCredit > 0) {
                t.set(db.collection("transactions").doc(), {
                    userId:    expertId,
                    amount:    expertCredit,
                    title:     resolution === "release" ? "שחרור נאמנות — החלטת מנהל" : "פשרה — מחלוקת (50%)",
                    type:      "credit",
                    jobId,
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                });
            }
        });

        // ── FCM Notifications (best-effort, outside transaction) ──────────────
        const notifTitle = {
            refund:  "החזר כספי אושר",
            release: "תשלום שוחרר",
            split:   "מחלוקת נפתרה",
        }[resolution];

        const customerMsg = resolution === "refund"
            ? `קיבלת החזר מלא של ₪${totalAmount.toFixed(0)} לאחר ביקורת המנהל`
            : resolution === "split"
            ? `קיבלת ₪${customerCredit.toFixed(0)} (50%) כפשרה בין הצדדים`
            : `המחלוקת נסגרה — הסכום שוחרר לספק`;

        const expertMsg = resolution === "refund"
            ? `המחלוקת נסגרה — הסכום הוחזר ללקוח`
            : resolution === "release"
            ? `קיבלת ₪${expertCredit.toFixed(0)} לאחר ביקורת המנהל`
            : `קיבלת ₪${expertCredit.toFixed(0)} (50% בניכוי עמלה) כפשרה`;

        const sendNotif = async (userId, body) => {
            try {
                const userSnap = await admin.firestore().collection("users").doc(userId).get();
                const token    = userSnap.data()?.fcmToken || userSnap.data()?.deviceToken;

                // Write to notifications collection
                await admin.firestore().collection("notifications").add({
                    userId,
                    title:     notifTitle,
                    body,
                    type:      "dispute_resolved",
                    jobId,
                    isRead:    false,
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                });

                if (!token) return;
                await admin.messaging().send({
                    token,
                    notification: { title: notifTitle, body },
                    data:         { type: "dispute_resolved", jobId },
                });
            } catch (err) {
                console.warn(`[resolveDisputeAdmin] FCM to ${userId} failed:`, err.message);
            }
        };

        await Promise.all([
            sendNotif(customerId, customerMsg),
            sendNotif(expertId,   expertMsg),
        ]);

        console.log(`[resolveDisputeAdmin] jobId=${jobId} resolution=${resolution} by admin=${callerId}`);
        return {
            success:       true,
            resolution,
            newStatus,
            customerCredit: parseFloat(customerCredit.toFixed(2)),
            expertCredit:   parseFloat(expertCredit.toFixed(2)),
            platformFee:    parseFloat(platformFee.toFixed(2)),
        };
    }
);

// ── processCancellation — Customer or Provider cancels a paid_escrow job ──────
// cancelledBy: 'customer' | 'provider'
// Customer before deadline  → full refund
// Customer after deadline   → partial refund + penalty to provider (minus fee)
// Provider cancels          → full refund to customer + XP penalty for provider
exports.processCancellation = onCall(
    { maxInstances: 20 },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Authentication required.");
        }

        const db       = admin.firestore();
        const callerId = request.auth.uid;
        const { jobId, cancelledBy } = request.data;

        if (!jobId) {
            throw new HttpsError("invalid-argument", "jobId is required.");
        }

        const jobRef = db.collection("jobs").doc(jobId);

        let customerId, expertId, totalAmount, chatRoomId, policy;
        let customerCredit = 0, expertCredit = 0, platformFee = 0;
        let newStatus   = "cancelled";
        let isPenalty   = false;
        let isProviderCancelling = false;

        await db.runTransaction(async (t) => {
            const jobSnap = await t.get(jobRef);
            if (!jobSnap.exists) throw new HttpsError("not-found", "Job not found.");

            const job = jobSnap.data();
            if (job.status !== "paid_escrow") {
                throw new HttpsError("failed-precondition", `Job is not cancellable (status: ${job.status}).`);
            }

            // Only the involved parties can cancel
            if (callerId !== job.customerId && callerId !== job.expertId) {
                throw new HttpsError("permission-denied", "Not your booking.");
            }

            customerId  = job.customerId;
            expertId    = job.expertId;
            totalAmount = typeof job.totalAmount === "number" ? job.totalAmount : 0;
            chatRoomId  = job.chatRoomId || "";
            policy      = job.cancellationPolicy || "flexible";
            isProviderCancelling = (cancelledBy === "provider") || (callerId === expertId && cancelledBy !== "customer");

            // Read fee from admin settings inside the transaction
            const settingsSnap = await t.get(
                db.collection("admin").doc("admin").collection("settings").doc("settings")
            );
            const feePct = settingsSnap.data()?.feePercentage || 0.10;

            if (isProviderCancelling) {
                // Provider cancels: full refund to customer, expert gets nothing
                customerCredit = totalAmount;
                newStatus      = "cancelled";
                t.update(db.collection("users").doc(customerId), {
                    balance: admin.firestore.FieldValue.increment(customerCredit),
                });

            } else {
                // Customer cancels: check deadline
                const deadlineTs = job.cancellationDeadline;
                const deadline   = deadlineTs?.toDate ? deadlineTs.toDate() : null;
                const now        = new Date();

                if (!deadline || now <= deadline) {
                    // Before deadline → full refund
                    customerCredit = totalAmount;
                    newStatus      = "cancelled";
                    t.update(db.collection("users").doc(customerId), {
                        balance: admin.firestore.FieldValue.increment(customerCredit),
                    });
                } else {
                    // After deadline → penalty split
                    isPenalty = true;
                    const penaltyPct    = policy === "strict" ? 1.0 : 0.5;
                    const penaltyAmount = roundNIS(totalAmount * penaltyPct);
                    customerCredit = roundNIS(totalAmount - penaltyAmount);
                    expertCredit   = roundNIS(penaltyAmount * (1 - feePct));
                    platformFee    = roundNIS(penaltyAmount * feePct);
                    newStatus      = "cancelled_with_penalty";

                    if (customerCredit > 0) {
                        t.update(db.collection("users").doc(customerId), {
                            balance: admin.firestore.FieldValue.increment(customerCredit),
                        });
                    }
                    t.update(db.collection("users").doc(expertId), {
                        balance: admin.firestore.FieldValue.increment(expertCredit),
                    });
                    t.set(db.collection("platform_earnings").doc(), {
                        jobId,
                        amount:    platformFee,
                        type:      "cancellation_penalty_fee",
                        timestamp: admin.firestore.FieldValue.serverTimestamp(),
                    });
                }
            }

            // Update job
            t.update(jobRef, {
                status:              newStatus,
                cancelledAt:         admin.firestore.FieldValue.serverTimestamp(),
                cancelledBy:         isProviderCancelling ? "provider" : "customer",
                customerRefund:      customerCredit,
                expertPenaltyCredit: expertCredit,
            });

            // Customer transaction record
            if (customerCredit > 0) {
                t.set(db.collection("transactions").doc(), {
                    userId:    customerId,
                    amount:    customerCredit,
                    title:     customerCredit === totalAmount
                        ? "ביטול הזמנה — החזר מלא"
                        : `ביטול הזמנה — החזר חלקי ₪${customerCredit.toFixed(0)}`,
                    type:      "refund",
                    jobId,
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                });
            }

            // Expert transaction record (penalty payout)
            if (expertCredit > 0) {
                t.set(db.collection("transactions").doc(), {
                    userId:    expertId,
                    amount:    expertCredit,
                    title:     "פיצוי ביטול מלקוח",
                    type:      "credit",
                    jobId,
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                });
            }
        });

        // XP penalty for provider cancellation (best-effort, outside transaction)
        if (isProviderCancelling) {
            try {
                const eventSnap = await db.collection("settings_gamification").doc("provider_cancel").get();
                const points    = eventSnap.exists
                    ? (typeof eventSnap.data().points === "number" ? eventSnap.data().points : -100)
                    : -100;
                const levelsSnap      = await db.collection("settings_gamification").doc("app_levels").get();
                const levels          = levelsSnap.data() || {};
                const silverThreshold = levels.silver ?? 500;
                const goldThreshold   = levels.gold   ?? 2000;

                await db.runTransaction(async (t) => {
                    const userRef  = db.collection("users").doc(expertId);
                    const userSnap = await t.get(userRef);
                    if (!userSnap.exists) return;
                    const curXp  = typeof userSnap.data().current_xp === "number"
                        ? userSnap.data().current_xp
                        : (userSnap.data().xp || 0);
                    const newXp  = Math.max(0, curXp + points);
                    let newLevel = "bronze";
                    if      (newXp >= goldThreshold)   newLevel = "gold";
                    else if (newXp >= silverThreshold) newLevel = "silver";
                    t.update(userRef, { current_xp: newXp, xp: newXp, level: newLevel });
                });
                console.log(`[processCancellation] XP penalty ${points} applied to provider ${expertId}`);
            } catch (err) {
                console.warn("[processCancellation] XP penalty failed:", err.message);
            }
        }

        // Chat notification (best-effort)
        if (chatRoomId) {
            try {
                let msg;
                if (isProviderCancelling) {
                    msg = "❌ המומחה ביטל את ההזמנה. הסכום המלא הוחזר לארנקך.";
                } else if (isPenalty) {
                    msg = `❌ ההזמנה בוטלה. ₪${customerCredit.toFixed(0)} הוחזרו ללקוח. ₪${expertCredit.toFixed(0)} זוכו לספק (פיצוי ביטול).`;
                } else {
                    msg = "❌ ההזמנה בוטלה. הסכום המלא הוחזר לארנק הלקוח.";
                }
                await db.collection("chats").doc(chatRoomId)
                    .collection("messages").add({
                        senderId:  "system",
                        message:   msg,
                        type:      "text",
                        timestamp: admin.firestore.FieldValue.serverTimestamp(),
                    });
            } catch (err) {
                console.warn("[processCancellation] chat message failed:", err.message);
            }
        }

        console.log(`[processCancellation] jobId=${jobId} by=${callerId} status=${newStatus} customerCredit=${customerCredit} expertCredit=${expertCredit}`);
        return {
            success:       true,
            newStatus,
            isPenalty,
            customerCredit: parseFloat(customerCredit.toFixed(2)),
            expertCredit:   parseFloat(expertCredit.toFixed(2)),
        };
    }
);

// =============================================================================
// AUTOMATION ENGINE — Scheduled Cleanup, Withdrawal System, Security
// =============================================================================

// ── scheduledCleanup — Unified hourly maintenance task ────────────────────────
// Consolidates all expiry tasks into one function:
//   1. Expire Stories:    stories.hasActive=true + expiresAt <= now
//   2. Expire Boosts:     users.boostedUntil <= now
//   3. Expire VIP subs:   users.isPromoted=true + promotionExpiryDate <= now
// (The standalone expireStories + expireVipSubscriptions also remain for their
//  original schedules; this hourly sweep catches anything they might miss.)

exports.scheduledCleanup = onSchedule(
    { schedule: 'every 1 hours', timeZone: 'Asia/Jerusalem' },
    async () => {
        const db  = admin.firestore();
        const now = admin.firestore.Timestamp.now();
        let totalCleaned = 0;

        // ── 1. Expire Stories ─────────────────────────────────────────────────
        try {
            const expiredStories = await db
                .collection('stories')
                .where('hasActive', '==', true)
                .where('expiresAt', '<=', now)
                .limit(200)
                .get();

            if (!expiredStories.empty) {
                const batch = db.batch();
                for (const doc of expiredStories.docs) {
                    batch.update(doc.ref, { hasActive: false });
                    batch.update(db.collection('users').doc(doc.id), { hasActiveStory: false });
                }
                await batch.commit();
                console.log(`[scheduledCleanup] Expired ${expiredStories.size} story/stories`);
                totalCleaned += expiredStories.size;
            }
        } catch (e) {
            console.error('[scheduledCleanup] stories error:', e.message);
        }

        // ── 2. Expire Boosts (boostedUntil <= now) ────────────────────────────
        try {
            const expiredBoosts = await db
                .collection('users')
                .where('boostedUntil', '<=', now)
                .limit(200)
                .get();

            if (!expiredBoosts.empty) {
                const batch = db.batch();
                for (const doc of expiredBoosts.docs) {
                    if (doc.data().boostedUntil) { // guard: field must exist
                        batch.update(doc.ref, {
                            boostedUntil:        admin.firestore.FieldValue.delete(),
                            urgentJobsCompleted: 0,
                        });
                    }
                }
                await batch.commit();
                console.log(`[scheduledCleanup] Expired ${expiredBoosts.size} boost(s)`);
                totalCleaned += expiredBoosts.size;
            }
        } catch (e) {
            console.error('[scheduledCleanup] boosts error:', e.message);
        }

        // ── 3. Expire VIP Subscriptions ───────────────────────────────────────
        try {
            const expiredVips = await db
                .collection('users')
                .where('isPromoted',          '==', true)
                .where('promotionExpiryDate', '<=', now)
                .limit(200)
                .get();

            if (!expiredVips.empty) {
                const batch = db.batch();
                for (const doc of expiredVips.docs) {
                    batch.update(doc.ref, { isPromoted: false });
                }
                await batch.commit();
                console.log(`[scheduledCleanup] Expired ${expiredVips.size} VIP subscription(s)`);
                totalCleaned += expiredVips.size;
            }
        } catch (e) {
            console.error('[scheduledCleanup] VIP error:', e.message);
        }

        console.log(`[scheduledCleanup] Run complete. Total records cleaned: ${totalCleaned}`);
    }
);

// ── requestWithdrawal — Provider requests a payout ────────────────────────────
// Enforces:
//   • isVerifiedProvider must be true (compliance requirement)
//   • balance must be >= amount
//   • minimum withdrawal: ₪100
// On success:
//   • Debits provider balance atomically (FieldValue.increment)
//   • Creates withdrawals/{id} doc (status: 'pending')
//   • Creates transactions/{id} record
//   • Sends FCM + inbox notification to all admin users

exports.requestWithdrawal = onCall(
    { maxInstances: 20 },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError('unauthenticated', 'Authentication required.');
        }

        const uid    = request.auth.uid;
        const amount = request.data?.amount;

        if (typeof amount !== 'number' || isNaN(amount) || amount < 100) {
            throw new HttpsError('invalid-argument', 'סכום המשיכה המינימלי הוא ₪100.');
        }

        const db      = admin.firestore();
        const userRef = db.collection('users').doc(uid);

        // Load user data (outside transaction — for pre-checks)
        const userSnap = await userRef.get();
        if (!userSnap.exists) throw new HttpsError('not-found', 'User not found.');

        const userData           = userSnap.data();
        const isProvider         = userData.isProvider === true;
        const isVerifiedProvider = userData.isVerifiedProvider !== false; // legacy users default to true

        if (isProvider && !isVerifiedProvider) {
            throw new HttpsError(
                'failed-precondition',
                'חשבון הספק שלך טרם אושר. יש להמתין לאישור מנהל לפני משיכת כספים.'
            );
        }

        const withdrawalRef = db.collection('withdrawals').doc();
        const txRef         = db.collection('transactions').doc();

        // Atomic transaction: re-read balance, debit, create records
        await db.runTransaction(async (t) => {
            const freshSnap    = await t.get(userRef);
            const freshBalance = typeof freshSnap.data()?.balance === 'number'
                ? freshSnap.data().balance : 0;

            if (freshBalance < amount) {
                throw new HttpsError(
                    'failed-precondition',
                    `יתרה לא מספיקה. יתרה זמינה: ₪${freshBalance.toFixed(2)}`
                );
            }

            t.update(userRef, {
                balance: admin.firestore.FieldValue.increment(-amount),
            });

            t.set(withdrawalRef, {
                userId:    uid,
                userName:  userData.name  || '',
                userEmail: userData.email || '',
                amount,
                status:    'pending',
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            t.set(txRef, {
                userId:    uid,
                amount:    -amount,
                title:     `בקשת משיכה — ₪${amount.toFixed(0)}`,
                type:      'withdrawal_pending',
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
            });
        });

        // ── Notify all admins (best-effort, outside transaction) ──────────────
        try {
            const adminSnap = await db.collection('users')
                .where('isAdmin', '==', true)
                .limit(5)
                .get();

            const adminTokens = adminSnap.docs
                .map(d => d.data().fcmToken)
                .filter(t => typeof t === 'string' && t.length > 10);

            const notifTitle = '💸 בקשת משיכה חדשה';
            const notifBody  = `${userData.name || 'ספק'} ביקש/ה למשוך ₪${amount.toFixed(0)}`;

            if (adminTokens.length > 0) {
                await admin.messaging().sendEachForMulticast({
                    notification: { title: notifTitle, body: notifBody },
                    data: {
                        type:         'withdrawal_request',
                        withdrawalId: withdrawalRef.id,
                        userId:       uid,
                    },
                    tokens:  adminTokens,
                    android: { priority: 'high', notification: { channelId: 'anyskill_default' } },
                    apns:    { payload: { aps: { sound: 'default' } } },
                });
            }

            // Write a notification doc for each admin user
            const batch = db.batch();
            for (const adminDoc of adminSnap.docs) {
                batch.set(db.collection('notifications').doc(), {
                    userId:    adminDoc.id,
                    title:     notifTitle,
                    body:      notifBody,
                    type:      'withdrawal_request',
                    data:      { withdrawalId: withdrawalRef.id, userId: uid, amount },
                    isRead:    false,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
            }
            await batch.commit();
        } catch (notifErr) {
            console.warn('[requestWithdrawal] admin notification failed:', notifErr.message);
        }

        console.log(`[requestWithdrawal] uid=${uid} amount=₪${amount} withdrawalId=${withdrawalRef.id}`);
        return { success: true, withdrawalId: withdrawalRef.id };
    }
);

// ── approveUserVerification ───────────────────────────────────────────────────
// Admin-only callable. Updates the user's isVerified / idVerificationStatus
// and sends an approval or rejection email via the Trigger Email extension.
// Payload: { uid, action: 'approve'|'reject', email, name }
exports.approveUserVerification = onCall(
    { region: "us-central1", maxInstances: 10 },
    async (request) => {
        // Only allow admin callers
        const callerEmail = request.auth?.token?.email ?? "";
        const callerUid   = request.auth?.uid ?? "";
        if (!callerEmail && !callerUid) {
            throw new HttpsError("unauthenticated", "Authentication required.");
        }
        // Check isAdmin flag on calling user's Firestore doc
        const callerDoc = await admin.firestore().collection("users").doc(callerUid).get();
        const isAdmin   = callerDoc.exists && (callerDoc.data().isAdmin === true || callerEmail === "adawiavihai@gmail.com");
        if (!isAdmin) {
            throw new HttpsError("permission-denied", "Admin only.");
        }

        const { uid, action, email, name } = request.data || {};
        if (!uid || !action) {
            throw new HttpsError("invalid-argument", "uid and action are required.");
        }
        if (action !== "approve" && action !== "reject") {
            throw new HttpsError("invalid-argument", "action must be 'approve' or 'reject'.");
        }

        const isApproved = action === "approve";
        const db         = admin.firestore();

        // 1. Update user document
        await db.collection("users").doc(uid).update({
            isVerified:            isApproved,
            idVerificationStatus:  isApproved ? "verified" : "rejected",
            idVerifiedAt:          isApproved ? admin.firestore.FieldValue.serverTimestamp() : null,
        });

        // 2. Send email via Trigger Email extension (mail collection)
        if (email) {
            const subject = isApproved
                ? "AnySkill — הפרופיל שלך אושר! 🎉"
                : "AnySkill — עדכון בנוגע לאימות הפרופיל שלך";

            const htmlApproved = `
                <div dir="rtl" style="font-family: Arial, sans-serif; max-width: 560px; margin: auto;">
                  <h2 style="color: #4F46E5;">שלום ${name || ""}!</h2>
                  <p>אנחנו שמחים לבשר לך שהפרופיל שלך <strong>אושר</strong> ב-AnySkill 🎉</p>
                  <p>כעת תוכל/י להתחבר לאפליקציה ולהתחיל לקבל הזמנות.</p>
                  <a href="https://anyskill-6fdf3.web.app" style="display:inline-block;margin-top:16px;padding:12px 24px;background:#4F46E5;color:#fff;border-radius:8px;text-decoration:none;font-weight:bold;">כניסה ל-AnySkill</a>
                  <p style="margin-top:24px;color:#888;font-size:12px;">צוות AnySkill</p>
                </div>`;

            const htmlRejected = `
                <div dir="rtl" style="font-family: Arial, sans-serif; max-width: 560px; margin: auto;">
                  <h2 style="color: #4F46E5;">שלום ${name || ""}!</h2>
                  <p>לצערנו, לא הצלחנו לאמת את תעודת הזהות שסיפקת.</p>
                  <p>ייתכן שהתמונה לא ברורה מספיק. אנא נסה/י להעלות תמונה חדשה ונבדוק מחדש.</p>
                  <p>לעזרה, צור/י קשר עם התמיכה שלנו.</p>
                  <p style="margin-top:24px;color:#888;font-size:12px;">צוות AnySkill</p>
                </div>`;

            await db.collection("mail").add({
                to:      email,
                message: {
                    subject,
                    html: isApproved ? htmlApproved : htmlRejected,
                },
            });
        }

        console.log(`[approveUserVerification] uid=${uid} action=${action} by ${callerUid}`);
        return { success: true };
    }
);


// ── Re-engagement: abandoned registration leads ───────────────────────────────
// Runs every 60 minutes. Finds sessions in `incomplete_registrations` that:
//   • are incomplete (isRegistrationComplete !== true)
//   • have been idle for at least 1 hour (lastUpdatedAt <= 1h ago)
//   • have an email or phone (so we can contact the user)
//   • have NOT been re-engaged already (reengaged !== true)
//
// For each matched lead it:
//   1. Marks the doc as reengaged (prevents double-trigger)
//   2. Writes to `reengagement_log` for admin visibility
//   3. If the user provided an email, sends a branded HTML email via the
//      `mail` collection (requires the Firebase Trigger Email Extension).
//      Replace this with your SendGrid / Twilio integration as needed.
exports.reengageAbandonedLeads = onSchedule(
  {
    schedule:  'every 60 minutes',
    timeZone:  'Asia/Jerusalem',
    region:    'us-central1',
    memory:    '256MiB',
  },
  async () => {
    const db  = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    const oneHourAgo = new Date(now.toMillis() - 60 * 60 * 1000);

    const snap = await db
      .collection('incomplete_registrations')
      .where('isRegistrationComplete', '==', false)
      .where('lastUpdatedAt', '<=', admin.firestore.Timestamp.fromDate(oneHourAgo))
      .limit(100)   // process max 100 per run to stay within function timeout
      .get();

    if (snap.empty) {
      console.log('[reengageAbandonedLeads] No abandoned leads found.');
      return;
    }

    const batch = db.batch();
    let processed = 0;

    for (const doc of snap.docs) {
      const data  = doc.data();
      const email = data.email || '';
      const phone = data.phone || '';

      // Skip: already re-engaged or no contact details
      if (data.reengaged || (!email && !phone)) continue;

      // 1. Mark as re-engaged so this run (and subsequent runs) skip it
      batch.update(doc.ref, {
        reengaged:   true,
        reengagedAt: admin.firestore.FieldValue.serverTimestamp(),
        reengagedBy: 'scheduled_function',
      });

      // 2. Audit log
      batch.set(db.collection('reengagement_log').doc(), {
        sessionId:   doc.id,
        email:       email || null,
        phone:       phone || null,
        lastField:   data.lastField || 'unknown',
        role:        data.role    || 'customer',
        triggeredAt: admin.firestore.FieldValue.serverTimestamp(),
        channel:     email ? 'email' : 'sms',
      });

      // 3. Send re-engagement email (requires Firebase Trigger Email Extension)
      //    Install at: https://firebase.google.com/products/extensions/firebase-firestore-send-email
      if (email) {
        const name = data.name || '';
        const fieldLabels = { name: 'שם', email: 'אימייל', phone: 'טלפון' };
        const stoppedAt = fieldLabels[data.lastField] || data.lastField || 'טופס ההרשמה';

        db.collection('mail').add({
          to: email,
          message: {
            subject: '💡 AnySkill — לא סיימת את ההרשמה!',
            html: `
              <div dir="rtl" style="font-family:Arial,sans-serif;max-width:560px;margin:auto;">
                <h2 style="color:#6366F1;">שלום${name ? ' ' + name : ''}!</h2>
                <p>שמנו לב שהתחלת להירשם ל-AnySkill אך לא סיימת (עצרת בשלב: <strong>${stoppedAt}</strong>).</p>
                <p>ההרשמה לוקחת פחות מ-2 דקות — ואנחנו ממש רוצים שתצטרף 🙏</p>
                <a href="https://anyskill-6fdf3.web.app/signup"
                   style="display:inline-block;margin-top:16px;padding:12px 28px;
                          background:#6366F1;color:#fff;border-radius:8px;
                          text-decoration:none;font-weight:bold;">
                  השלם את ההרשמה →
                </a>
                <p style="margin-top:24px;color:#888;font-size:12px;">צוות AnySkill</p>
              </div>
            `,
          },
        }).catch(err => console.error('[reengageAbandonedLeads] mail error:', err));
      }

      // 3b. SMS placeholder (integrate Twilio / Vonage here)
      if (!email && phone) {
        console.log(`[reengageAbandonedLeads] SMS needed for ${phone} — integrate Twilio here.`);
        // Example Twilio call (requires twilio npm package + secrets):
        // const twilio = require('twilio')(TWILIO_SID.value(), TWILIO_TOKEN.value());
        // await twilio.messages.create({
        //   body: `היי! שכחת להשלים את ההרשמה ל-AnySkill. לחץ כאן: https://anyskill-6fdf3.web.app/signup`,
        //   from: '+1xxxxxxxxxx',
        //   to:   phone,
        // });
      }

      processed++;
    }

    await batch.commit();
    console.log(`[reengageAbandonedLeads] Processed ${processed} leads.`);
  }
);

// ═══════════════════════════════════════════════════════════════════════════════
// ── Activity Log Triggers — write to `activity_log` for Live Admin Feed ───────
// ═══════════════════════════════════════════════════════════════════════════════

/** Helper: write a single activity_log entry */
async function _logActivity(type, title, detail) {
  await admin.firestore().collection('activity_log').add({
    type,
    title,
    detail,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/** New job_request created → log "בקשת עבודה חדשה" */
exports.logJobRequestCreated = onDocumentCreated(
  { document: 'job_requests/{id}', maxInstances: 10 },
  async (event) => {
    const d = event.data?.data() ?? {};
    const category = d.category ?? 'לא ידוע';
    const clientId = d.clientId ?? '';
    let clientName = clientId;
    try {
      const u = await admin.firestore().collection('users').doc(clientId).get();
      if (u.exists) clientName = u.data().name || u.data().displayName || clientId;
    } catch (_) {}
    await _logActivity(
      'job_request',
      `בקשת עבודה חדשה — ${category}`,
      `לקוח: ${clientName}`,
    );
  }
);

/** Job status moves to paid_escrow → log "עבודה אושרה (אסקרו)" */
exports.logJobAccepted = onDocumentUpdated(
  { document: 'jobs/{id}', maxInstances: 10 },
  async (event) => {
    const before = event.data?.before?.data() ?? {};
    const after  = event.data?.after?.data()  ?? {};
    if (before.status === after.status) return null;
    if (after.status !== 'paid_escrow') return null;

    const expertName   = after.expertName   || after.expertId   || '?';
    const customerName = after.customerName || after.customerId || '?';
    const amount       = after.totalAmount ?? 0;
    await _logActivity(
      'job_accepted',
      `עבודה אושרה — ₪${amount}`,
      `${expertName} ↔ ${customerName}`,
    );
    return null;
  }
);

/** New volunteer_request created → log "בקשת התנדבות חדשה" */
exports.logVolunteerRequest = onDocumentCreated(
  { document: 'volunteer_requests/{id}', maxInstances: 10 },
  async (event) => {
    const d        = event.data?.data() ?? {};
    const category = d.category    ?? 'לא ידוע';
    const name     = d.requesterName || d.forName || 'אנונימי';
    await _logActivity(
      'volunteer_request',
      `בקשת התנדבות — ${category}`,
      `עבור: ${name}`,
    );
  }
);

/** New user registered → log "משתמש חדש נרשם" */
exports.logNewRegistration = onDocumentCreated(
  { document: 'users/{uid}', maxInstances: 10 },
  async (event) => {
    const d    = event.data?.data() ?? {};
    const name = d.name || d.displayName || 'משתמש חדש';
    const role = d.isProvider ? 'ספק' : 'לקוח';
    await _logActivity(
      'registration',
      `הצטרף משתמש חדש — ${role}`,
      name,
    );
  }
);

// ═══════════════════════════════════════════════════════════════════════════════
// ── sendGlobalBroadcast — Callable: pushes FCM to every user with a token ─────
// ═══════════════════════════════════════════════════════════════════════════════
exports.sendGlobalBroadcast = onCall(
  { maxInstances: 1 },
  async (request) => {
    // Only callable by admin (verified client-side; server check here for safety)
    const message = (request.data?.message ?? '').trim();
    if (!message) throw new HttpsError('invalid-argument', 'message is required');

    // Collect all FCM tokens (query in pages of 500)
    const tokens = [];
    let lastDoc   = null;
    let done      = false;

    while (!done) {
      let q = admin.firestore().collection('users')
        .where('fcmToken', '!=', null)
        .select('fcmToken')
        .limit(500);
      if (lastDoc) q = q.startAfter(lastDoc);

      const snap = await q.get();
      if (snap.empty) { done = true; break; }

      for (const doc of snap.docs) {
        const token = doc.data().fcmToken;
        if (token) tokens.push(token);
      }
      lastDoc = snap.docs[snap.docs.length - 1];
      if (snap.size < 500) done = true;
    }

    if (tokens.length === 0) {
      console.log('[sendGlobalBroadcast] No tokens found.');
      return { sent: 0 };
    }

    // Send in batches of 500 (FCM multicast limit)
    const BATCH = 500;
    let sent = 0;
    for (let i = 0; i < tokens.length; i += BATCH) {
      const chunk = tokens.slice(i, i + BATCH);
      const multicast = {
        tokens: chunk,
        notification: {
          title: '📢 AnySkill',
          body:  message,
        },
        data: {
          type:    'broadcast',
          message: message,
        },
        webpush: {
          notification: {
            icon: '/icons/Icon-192.png',
          },
        },
      };
      try {
        const resp = await admin.messaging().sendEachForMulticast(multicast);
        sent += resp.successCount;
        console.log(`[sendGlobalBroadcast] Batch ${i / BATCH + 1}: ${resp.successCount}/${chunk.length} sent`);
      } catch (err) {
        console.error('[sendGlobalBroadcast] Batch error:', err);
      }
    }

    // Log to broadcast_history (the Flutter client also writes here — this is the server copy)
    await admin.firestore().collection('broadcast_history').add({
      message,
      sentAt:     admin.firestore.FieldValue.serverTimestamp(),
      sentBy:     request.auth?.uid ?? 'admin',
      platform:   'fcm-push',
      totalTokens: tokens.length,
      sent,
    });

    console.log(`[sendGlobalBroadcast] Done. Sent ${sent}/${tokens.length}.`);
    return { sent, total: tokens.length };
  }
);

// ── AI Re-Engagement Engine ─────────────────────────────────────────────────
// Runs daily at 08:00 Israel time.
// Scans completed jobs whose re-booking cycle has elapsed and creates
// entries in scheduled_reminders (customer-facing) + activity_log (admin feed).
exports.reengagementEngine = onSchedule(
  { schedule: '0 8 * * *', timeZone: 'Asia/Jerusalem' },
  async () => {
    const db  = admin.firestore();
    const now = Date.now();

    // Category → typical re-booking cycle in days.
    // Any category not in this map falls back to DEFAULT_CYCLE.
    const SERVICE_CYCLES = {
      'ניקיון בית':       14,
      'ניקיון משרד':       7,
      'גיהוץ':             7,
      'גינון':            30,
      'טיפול בעלי חיים':  30,
      'מאמן כושר':        30,
      'שיעורים פרטיים':   30,
      'ניקיון מזגן':     180,
      'מזגנים':          180,
      'הדברה':           365,
      'שיפוצים':         365,
      'אינסטלציה':       365,
      'חשמלאי':          365,
      'צביעה':          1825,
      'ריצוף':          1825,
      'נגרות':           730,
    };
    const DEFAULT_CYCLE = 365; // days

    // Seasonal "why now" reason string — changes monthly
    const WHY_NOW_BY_MONTH = [
      'החורף בשיאו',        // Jan
      'לקראת הפורים',       // Feb
      'לקראת הפסח',         // Mar
      'חג הפסח מתקרב',      // Apr
      'הקיץ מגיע',          // May
      'הקיץ כבר כאן',       // Jun
      'שיא הקיץ',           // Jul
      'לפני חזרה לשגרה',    // Aug
      'לקראת החגים',        // Sep
      'ראש השנה החדש',      // Oct
      'אחרי החגים',         // Nov
      'לקראת החנוכה',       // Dec
    ];
    const whyNow = WHY_NOW_BY_MONTH[new Date().getMonth()];

    // ------------------------------------------------------------------
    // 1. Pre-load all existing reminder originJobIds to avoid per-job
    //    dedup queries (single read instead of N reads).
    // ------------------------------------------------------------------
    const existingSnap = await db.collection('scheduled_reminders')
      .select('originalJobId')
      .limit(5000)
      .get();
    const existingJobIds = new Set(
      existingSnap.docs.map(d => d.data().originalJobId).filter(Boolean)
    );

    // ------------------------------------------------------------------
    // 2. Fetch completed jobs from the last 3 years.
    // ------------------------------------------------------------------
    const cutoff = new Date(now - 3 * 365 * 24 * 3600 * 1000);
    const jobsSnap = await db.collection('jobs')
      .where('status', '==', 'completed')
      .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(cutoff))
      .limit(200)
      .get();

    // ------------------------------------------------------------------
    // 3. Pass 1 — qualify jobs without any extra Firestore reads.
    //    Collect the unique user IDs we'll need for name resolution.
    // ------------------------------------------------------------------
    const qualifyingJobs = [];
    let skipped = 0;

    for (const jobDoc of jobsSnap.docs) {
      const job         = jobDoc.data();
      const customerId  = job.customerId;
      const expertId    = job.expertId;
      const category    = job.category || job.serviceType || '';
      const completedTs = job.completedAt || job.createdAt;
      const completedAt = completedTs?.toDate?.() || null;

      if (!customerId || !expertId || !completedAt) { skipped++; continue; }
      if (existingJobIds.has(jobDoc.id))             { skipped++; continue; }

      const cycleDays = SERVICE_CYCLES[category] ?? DEFAULT_CYCLE;
      const remindMs  = completedAt.getTime() + cycleDays * 24 * 3600 * 1000;
      if (remindMs > now) { skipped++; continue; }

      qualifyingJobs.push({ jobDoc, job, customerId, expertId, category, cycleDays });
    }

    // ------------------------------------------------------------------
    // 4. Pass 2 — batch-fetch all user names in parallel (Promise.all).
    //    Only fetch IDs not already embedded in the job doc.
    //    Dedup across jobs so we never fetch the same user twice.
    // ------------------------------------------------------------------
    const idsToFetch = [...new Set(
      qualifyingJobs.flatMap(({ job, customerId, expertId }) => {
        const needed = [];
        if (!job.customerName) needed.push(customerId);
        if (!job.expertName)   needed.push(expertId);
        return needed;
      })
    )];

    // Concurrent fetches — scales to hundreds of unique users in one round-trip
    const userSnaps = await Promise.all(
      idsToFetch.map(uid => db.collection('users').doc(uid).get())
    );
    const userNameById = {};
    for (const snap of userSnaps) {
      userNameById[snap.id] = snap.exists ? (snap.data().name || '') : '';
    }

    // ------------------------------------------------------------------
    // 5. Pass 3 — build batched Firestore writes synchronously (no more awaits).
    // ------------------------------------------------------------------
    const reminderBatch = db.batch();
    const activityBatch = db.batch();
    let created = 0;

    for (const { jobDoc, job, customerId, expertId, category, cycleDays } of qualifyingJobs) {
      const customerName = job.customerName || userNameById[customerId] || 'לקוח';
      const expertName   = job.expertName   || userNameById[expertId]   || 'המומחה';
      const message      = `מוכן ל${category} עם ${expertName}? ${whyNow} — לחץ להזמנה!`;

      // Reminder doc — ID = job ID for idempotency
      reminderBatch.set(db.collection('scheduled_reminders').doc(jobDoc.id), {
        userId:        customerId,
        customerId,
        expertId,
        customerName,
        expertName,
        category,
        originalJobId: jobDoc.id,
        cycleDays,
        whyNow,
        message,
        isActive:      true,
        isDismissed:   false,
        createdAt:     admin.firestore.FieldValue.serverTimestamp(),
      });

      // Activity log entry for admin Live Feed
      activityBatch.set(db.collection('activity_log').doc(), {
        type:         'ai_reengagement_sent',
        userId:       customerId,
        expertId,
        customerName,
        expertName,
        category,
        jobId:        jobDoc.id,
        whyNow,
        priority:     'normal',
        timestamp:    admin.firestore.FieldValue.serverTimestamp(),
        message:      `AI Reminder: ${customerName} → ${category} עם ${expertName} (${whyNow})`,
      });

      existingJobIds.add(jobDoc.id);
      created++;
    }

    if (created > 0) {
      await Promise.all([reminderBatch.commit(), activityBatch.commit()]);
    }

    console.log(`[reengagementEngine] created=${created} skipped=${skipped} userFetches=${idsToFetch.length}`);
    return null;
  }
);

// =============================================================================
// ─── AI Matchmaker Agent ─────────────────────────────────────────────────────
// =============================================================================
// Triggered by Flutter immediately after a Quick Request is submitted.
//
// Flow:
//   1. Query verified providers in the requested category (limit 30)
//   2. Rank them — mirrors Flutter SearchRankingService formula:
//        score = (xp/2000)*100 × 0.6  +  distance_score × 0.2  +  story_bonus × 0.2
//              + 100 (if online) + 200 (if promoted)
//   3. Call Claude Haiku with the top-3 summary → generate a personalised
//      Hebrew pitch that recommends the #1 match and invites the client to connect
//   4. Falls back to a template pitch if ANTHROPIC_API_KEY is absent (dev mode)
//
// Returns: { pitch, topProvider: { uid, name, rating, distKm, profileImage,
//            category, aboutMe, pricePerHour, isOnline }, totalMatches }
// =============================================================================

const _MATCHMAKER_SYSTEM_PROMPT =
  "אתה סוכן AI של AnySkill — הפלטפורמה הישראלית הגדולה למציאת ספקי שירות. " +
  "תפקידך: לייצר מסר קצר, חם ואישי בעברית שמחבר בין לקוח לספק המתאים ביותר. " +
  "הסגנון: ישיר, אנושי, מקצועי — כמו חבר שמכיר את השוק. " +
  "כתוב 2-3 משפטים בלבד. ללא כוכביות. ללא רשימות. ללא פתיח כמו 'בהחלט' או 'כמובן'. " +
  "פשוט המלצה אישית וחמה.";

exports.matchmakerpitch = onCall(
  {
    secrets:      [ANTHROPIC_API_KEY],
    maxInstances: 10,
    region:       "us-central1",
    memory:       "512MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const { requestText, category, clientName, clientLat, clientLng } =
      request.data;

    if (!requestText || requestText.trim().length < 3) {
      throw new HttpsError("invalid-argument", "requestText is required.");
    }

    const db = admin.firestore();

    // ── 1. Query providers ─────────────────────────────────────────────────
    let snap;
    if (category && category.trim().length > 0) {
      snap = await db.collection("users")
        .where("isProvider",  "==", true)
        .where("isVerified",  "==", true)
        .where("serviceType", "==", category.trim())
        .limit(30)
        .get();
    } else {
      snap = await db.collection("users")
        .where("isProvider", "==", true)
        .where("isVerified", "==", true)
        .limit(30)
        .get();
    }

    if (snap.empty) {
      console.log(`matchmakerpitch: no providers found for category="${category}"`);
      return { pitch: null, topProvider: null, totalMatches: 0 };
    }

    // ── 2. Rank — mirrors Flutter SearchRankingService ─────────────────────
    const GOLD_THRESHOLD = 2000;
    const MAX_DIST_KM    = 50;
    const now            = Date.now();

    function haversineKm(lat1, lng1, lat2, lng2) {
      if (lat1 == null || lng1 == null || lat2 == null || lng2 == null) return null;
      const R    = 6371;
      const dLat = (lat2 - lat1) * Math.PI / 180;
      const dLng = (lng2 - lng1) * Math.PI / 180;
      const a    = Math.sin(dLat / 2) ** 2
                 + Math.cos(lat1 * Math.PI / 180)
                 * Math.cos(lat2 * Math.PI / 180)
                 * Math.sin(dLng / 2) ** 2;
      return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }

    const scored = snap.docs
      .map(doc => ({ _uid: doc.id, ...doc.data() }))
      .filter(p => !p.isHidden && !p.isBanned)
      .map(p => {
        const xpScore    = Math.min((p.xp || 0) / GOLD_THRESHOLD, 1.0) * 100;
        const distKm     = haversineKm(clientLat, clientLng, p.latitude, p.longitude);
        const distScore  = distKm === null
          ? 50
          : Math.max(0, (MAX_DIST_KM - Math.min(distKm, MAX_DIST_KM)) / MAX_DIST_KM * 100);
        const storyMs    = p.lastStoryAt
          ? (typeof p.lastStoryAt.toMillis === "function" ? p.lastStoryAt.toMillis() : 0)
          : 0;
        const storyBonus  = (storyMs > 0 && (now - storyMs) < 86400000) ? 100 : 0;
        const finalScore  = xpScore * 0.6 + distScore * 0.2 + storyBonus * 0.2
                          + (p.isOnline   ? 100 : 0)
                          + (p.isPromoted ? 200 : 0);
        return { ...p, _score: finalScore, _distKm: distKm };
      })
      .sort((a, b) => b._score - a._score)
      .slice(0, 3);

    if (scored.length === 0) {
      return { pitch: null, topProvider: null, totalMatches: 0 };
    }

    const top       = scored[0];
    const topName   = top.name || "ספק";
    const topRating = ((top.rating || 4.5)).toFixed(1);
    const topDistKm = top._distKm;
    const topDist   = topDistKm !== null ? `${topDistKm.toFixed(1)} ק"מ` : null;
    const topPrice  = top.pricePerHour ? `₪${top.pricePerHour} לשעה` : null;

    const topProvider = {
      uid:          top._uid,
      name:         topName,
      rating:       top.rating  || 4.5,
      distKm:       topDistKm,
      profileImage: top.profileImage || "",
      category:     top.serviceType  || category || "",
      aboutMe:      (top.aboutMe || "").substring(0, 80),
      pricePerHour: top.pricePerHour || 0,
      isOnline:     top.isOnline     || false,
    };

    // ── 3. Template fallback (no API key in dev) ───────────────────────────
    function templatePitch() {
      const distPart  = topDist  ? `נמצא/ת רק ${topDist} ממך`  : "זמין/ה באזורך";
      const pricePart = topPrice ? ` ב-${topPrice}` : "";
      const morePart  = scored.length > 1
        ? ` ויש עוד ${scored.length - 1} ספקים מתאימים.`
        : ".";
      return `מצאתי בשבילך! ${topName} ${distPart} עם דירוג ${topRating}⭐${pricePart}${morePart} רוצה שאשלח לו/ה את הבקשה שלך?`;
    }

    // ── 4. Claude Haiku pitch ──────────────────────────────────────────────
    const apiKey = ANTHROPIC_API_KEY.value() || process.env.ANTHROPIC_API_KEY || "";
    if (!apiKey) {
      console.warn("matchmakerpitch: ANTHROPIC_API_KEY missing — using template");
      return { pitch: templatePitch(), topProvider, totalMatches: scored.length };
    }
    if (!await _isAiEnabled(admin.firestore())) {
      console.warn("matchmakerpitch: kill-switch active — basic mode");
      return { pitch: templatePitch(), topProvider, totalMatches: scored.length, basicMode: true };
    }

    const providerLines = scored.map((p, i) => {
      const d     = p._distKm !== null ? `${p._distKm.toFixed(1)} ק"מ` : "מרחק לא ידוע";
      const price = p.pricePerHour ? `₪${p.pricePerHour}/שעה` : "";
      const bio   = (p.aboutMe || "").substring(0, 60);
      return `${i + 1}. ${p.name || "ספק"} | ${(p.rating || 4.5).toFixed(1)}⭐ | ${d}${price ? " | " + price : ""}${bio ? " | " + bio : ""}`;
    }).join("\n");

    const moreCount = scored.length - 1;
    const userMsg = [
      `לקוח בשם ${clientName || "לקוח"} ביקש: "${requestText.trim()}"`,
      ``,
      `מצאתי ${scored.length} ספקים מתאימים:`,
      providerLines,
      ``,
      `כתוב מסר קצר ואישי (2-3 משפטים) שממליץ על הספק הראשון כהמלצה הטובה ביותר.`,
      moreCount > 0 ? `ציין שיש עוד ${moreCount} ספקים מתאימים.` : "",
      topDist  ? `ציין שהספק נמצא ${topDist} מהלקוח.`  : "",
      topPrice ? `ציין את המחיר: ${topPrice}.` : "",
      `סיים עם שאלה ישירה: האם הלקוח רוצה לשלוח לו/ה את הבקשה.`,
    ].filter(Boolean).join("\n");

    try {
      const anthropic = new Anthropic({ apiKey });
      const msg = await anthropic.messages.create({
        model:      "claude-haiku-4-5-20251001",
        max_tokens: 200,
        system:     _MATCHMAKER_SYSTEM_PROMPT,
        messages:   [{ role: "user", content: userMsg }],
      });
      const pitch = (msg.content[0]?.text || "").trim();
      _trackApiCost(admin.firestore(), msg.usage?.input_tokens || 0, msg.usage?.output_tokens || 0).catch(() => {});
      console.log(`matchmakerpitch: uid=${request.auth.uid} cat="${category}" matches=${scored.length} pitch_len=${pitch.length}`);
      return { pitch: pitch || templatePitch(), topProvider, totalMatches: scored.length };
    } catch (err) {
      console.error("matchmakerpitch: Claude call failed:", err);
      // Graceful fallback — never throw so the user still gets a response
      return { pitch: templatePitch(), topProvider, totalMatches: scored.length };
    }
  }
);

// =============================================================================
// ─── AI Business Coach ───────────────────────────────────────────────────────
// =============================================================================
// Reads a verified provider's full profile from Firestore, computes the
// category-average pricePerHour, and asks Claude Haiku to produce a 3-point
// Hebrew coaching plan stored as:
//   users/{uid}.aiCoachingTips: { summary, scorePct, tips[], updatedAt }
//
// 24-hour server-side TTL: if cached data is fresh, the function returns it
// immediately without calling Claude again.
//
// Graceful fallback: if ANTHROPIC_API_KEY is absent, a deterministic template-
// based coaching plan is generated from the profile audit instead.
// =============================================================================

// ── Template fallback (no API key or Claude failure) ─────────────────────────
function _buildTemplateCoaching(
  name, aboutMeLen, price, categoryAvgPrice, galleryLen, certifiedCats, hasPhoto
) {
  const tips = [];

  if (!hasPhoto) {
    tips.push({ icon: "📸", text: "הוסף תמונת פרופיל מקצועית — פרופילים עם תמונה מקבלים 3× יותר פניות", priority: "high" });
  } else if (galleryLen < 3) {
    tips.push({ icon: "🖼️", text: `הגלריה שלך ריקה כמעט (${galleryLen} תמונות). הוסף לפחות 3 תמונות של עבודות אמיתיות`, priority: "high" });
  }

  if (aboutMeLen < 100) {
    tips.push({ icon: "📝", text: `התיאור שלך קצר (${aboutMeLen} תווים). כתוב לפחות 150 תווים שכוללים ניסיון, התמחות ומה מייחד אותך`, priority: "high" });
  }

  if (categoryAvgPrice && Math.abs(price - categoryAvgPrice) / categoryAvgPrice > 0.2) {
    const pct = Math.abs(Math.round((price - categoryAvgPrice) / categoryAvgPrice * 100));
    const dir = price > categoryAvgPrice ? "גבוה" : "נמוך";
    tips.push({ icon: "💰", text: `המחיר שלך ₪${price} ${dir} ב-${pct}% מממוצע הקטגוריה (₪${Math.round(categoryAvgPrice)}). שקול להתאים להגדיל פניות`, priority: "medium" });
  }

  if (certifiedCats === 0) {
    tips.push({ icon: "🎓", text: "השלם קורס באקדמיית AnySkill וקבל תג 'מומחה מאומת' — מדרג אותך גבוה יותר בחיפוש", priority: "medium" });
  }

  while (tips.length < 3) {
    tips.push({ icon: "⭐", text: "בקש מ-3 לקוחות מרוצים להשאיר ביקורת — ביקורות מכפילות את שיעור הפניות", priority: "low" });
  }

  let score = 30;
  if (hasPhoto)                                         score += 15;
  if (aboutMeLen >= 150)                               score += 15;
  if (galleryLen >= 3)                                 score += 10;
  if (certifiedCats > 0)                               score += 10;
  if (categoryAvgPrice && Math.abs(price - categoryAvgPrice) / categoryAvgPrice < 0.15) score += 10;
  score = Math.min(score, 95);

  return {
    summary:  score >= 70
      ? "פרופיל חזק! כמה שיפורים קטנים יכפילו את הפניות"
      : "פרופיל עם פוטנציאל גבוה — 3 שיפורים יקפיצו אותך",
    scorePct: score,
    tips:     tips.slice(0, 3),
  };
}

exports.analyzeProviderProfile = onCall(
  {
    secrets:      [ANTHROPIC_API_KEY],
    maxInstances: 5,
    region:       "us-central1",
    memory:       "512MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Login required.");
    }
    const uid = request.auth.uid;
    const db  = admin.firestore();

    // ── 1. Read provider profile ───────────────────────────────────────────
    const userDoc = await db.collection("users").doc(uid).get();
    if (!userDoc.exists) throw new HttpsError("not-found", "User not found.");
    const profile = userDoc.data();

    if (!profile.isProvider || !profile.isVerified) {
      throw new HttpsError("permission-denied", "Only verified providers can use this feature.");
    }

    // ── 2. 24-hour server-side cache check ────────────────────────────────
    const cached = profile.aiCoachingTips;
    if (cached && cached.updatedAt) {
      const ageH = (Date.now() - cached.updatedAt.toMillis()) / 3600000;
      if (ageH < 24) {
        console.log(`analyzeProviderProfile: cache hit uid=${uid} ageH=${ageH.toFixed(1)}`);
        return cached;
      }
    }

    // ── 3. Category-average price ─────────────────────────────────────────
    const category = profile.serviceType || "";
    let categoryAvgPrice = null;
    if (category) {
      const peersSnap = await db.collection("users")
        .where("isProvider",  "==", true)
        .where("isVerified",  "==", true)
        .where("serviceType", "==", category)
        .limit(50)
        .get();
      const prices = peersSnap.docs
        .map(d => d.data().pricePerHour)
        .filter(p => p && p > 0);
      if (prices.length > 1) {
        categoryAvgPrice = prices.reduce((a, b) => a + b, 0) / prices.length;
      }
    }

    // ── 4. Build audit snapshot ───────────────────────────────────────────
    const name           = profile.name           || "ספק";
    const aboutMeLen     = (profile.aboutMe || "").trim().length;
    const price          = profile.pricePerHour   || 0;
    const rating         = ((profile.rating || 0)).toFixed(1);
    const reviewsCount   = profile.reviewsCount   || 0;
    const hasPhoto       = !!(profile.profileImage);
    const galleryLen     = (profile.gallery        || []).length;
    const certifiedCats  = (profile.certifiedCategories || []).length;
    const xp             = profile.xp             || 0;
    const isOnline       = profile.isOnline        || false;
    const updatedAt      = profile.updatedAt;
    const daysSinceUpdate = updatedAt
      ? Math.floor((Date.now() - updatedAt.toMillis()) / 86400000)
      : 60;
    const priceVsAvg = categoryAvgPrice
      ? ((price - categoryAvgPrice) / categoryAvgPrice * 100).toFixed(0)
      : null;

    const audit = [
      `שם: ${name}`,
      `קטגוריה: ${category || "לא מוגדר"}`,
      `תיאור (aboutMe): ${aboutMeLen} תווים${aboutMeLen < 80 ? " — קצר מאוד" : aboutMeLen < 200 ? " — בינוני" : " — טוב"}`,
      `מחיר לשעה: ₪${price}${categoryAvgPrice ? ` (ממוצע קטגוריה ₪${Math.round(categoryAvgPrice)}, ${priceVsAvg > 0 ? "+" : ""}${priceVsAvg}%)` : ""}`,
      `דירוג: ${rating}⭐ מתוך ${reviewsCount} ביקורות`,
      `תמונת פרופיל: ${hasPhoto ? "יש" : "חסרה"}`,
      `גלריה: ${galleryLen} תמונות${galleryLen === 0 ? " — ריקה!" : galleryLen < 3 ? " — מעטות" : " — טוב"}`,
      `קורסים מוסמכים: ${certifiedCats}`,
      `XP: ${xp}`,
      `מחובר: ${isOnline ? "כן" : "לא"}`,
      `עדכון פרופיל: לפני ${daysSinceUpdate} ימים`,
    ].join("\n");

    // ── 5. Claude Haiku ───────────────────────────────────────────────────
    const systemPrompt =
      "אתה יועץ עסקי של AnySkill — פלטפורמת שירותים ישראלית. " +
      "תפקידך: לנתח פרופיל ספק ולתת 3 עצות ספציפיות ומעשיות להגדלת הכנסות. " +
      "הסגנון: ישיר, חם, מעשי — כמו מנטור שמכיר את השוק. " +
      "פלט JSON בלבד, ללא כוכביות, ללא הסברים.";

    const userMsg =
      `נתוני פרופיל:\n${audit}\n\n` +
      `החזר JSON בפורמט הבא בלבד:\n` +
      `{\n` +
      `  "summary": "משפט אחד שמסכם מצב הפרופיל",\n` +
      `  "scorePct": <ציון 0-100>,\n` +
      `  "tips": [\n` +
      `    { "icon": "<אמוג'י>", "text": "<עצה ספציפית עם מספרים מהנתונים>", "priority": "high" },\n` +
      `    { "icon": "<אמוג'י>", "text": "<עצה ספציפית עם מספרים מהנתונים>", "priority": "medium" },\n` +
      `    { "icon": "<אמוג'י>", "text": "<עצה ספציפית עם מספרים מהנתונים>", "priority": "low" }\n` +
      `  ]\n` +
      `}\n` +
      `כל tip חייב לכלול פעולה ספציפית ומדידה.`;

    const apiKey = ANTHROPIC_API_KEY.value() || process.env.ANTHROPIC_API_KEY || "";
    let result;

    const _coachAiEnabled = await _isAiEnabled(admin.firestore());
    if (!apiKey || !_coachAiEnabled) {
      console.warn("analyzeProviderProfile: using template (no key or kill-switch active)");
      result = _buildTemplateCoaching(name, aboutMeLen, price, categoryAvgPrice, galleryLen, certifiedCats, hasPhoto);
    } else {
      try {
        const anthropic = new Anthropic({ apiKey });
        const msg = await anthropic.messages.create({
          model:      "claude-haiku-4-5-20251001",
          max_tokens: 512,
          system:     systemPrompt,
          messages:   [{ role: "user", content: userMsg }],
        });
        _trackApiCost(admin.firestore(), msg.usage?.input_tokens || 0, msg.usage?.output_tokens || 0).catch(() => {});
        const raw = (msg.content[0]?.text || "{}")
          .replace(/```(?:json)?\s*/gi, "").replace(/```/g, "").trim();
        result = JSON.parse(raw);
      } catch (err) {
        console.error("analyzeProviderProfile: Claude failed:", err);
        result = _buildTemplateCoaching(name, aboutMeLen, price, categoryAvgPrice, galleryLen, certifiedCats, hasPhoto);
      }
    }

    // ── 6. Cache in Firestore ─────────────────────────────────────────────
    result.updatedAt = admin.firestore.FieldValue.serverTimestamp();
    await db.collection("users").doc(uid).update({ aiCoachingTips: result });

    console.log(`analyzeProviderProfile: uid=${uid} score=${result.scorePct} tips=${result.tips?.length}`);
    return result;
  }
);

// =============================================================================
// ─── Smart Nudge: notify stale providers ─────────────────────────────────────
// =============================================================================
// Runs daily at 10:00 Israel time.
// Sends an in-app notification to providers whose profile hasn't been updated
// in 30+ days, at most once every 7 days per provider.
// =============================================================================

exports.notifyStaleProviders = onSchedule(
  { schedule: "0 10 * * *", timeZone: "Asia/Jerusalem", region: "us-central1" },
  async () => {
    const db          = admin.firestore();
    const staleCutoff = new Date(Date.now() - 30 * 86400000); // 30 days ago
    const nudgeCutoff = new Date(Date.now() -  7 * 86400000); //  7 days ago

    const snap = await db.collection("users")
      .where("isProvider", "==", true)
      .where("isVerified", "==", true)
      .limit(300)
      .get();

    const notifBatch  = db.batch();
    const updateBatch = db.batch();
    let sent = 0;

    for (const doc of snap.docs) {
      if (sent >= 100) break; // safety cap

      const d           = doc.data();
      const updatedAt   = d.updatedAt?.toDate()          || new Date(0);
      const lastNudge   = d.lastCoachingNudge?.toDate()  || new Date(0);

      if (updatedAt >= staleCutoff || lastNudge >= nudgeCutoff) continue;

      notifBatch.set(db.collection("notifications").doc(), {
        userId:    doc.id,
        title:     "💡 ה-AI שלנו מצא דרך לשפר אותך!",
        body:      "ה-AI שלנו מצא דרך לשפר את החשיפה שלך! כנס לבדוק.",
        type:      "ai_coaching",
        isRead:    false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      updateBatch.update(doc.ref, {
        lastCoachingNudge: admin.firestore.FieldValue.serverTimestamp(),
      });
      sent++;
    }

    if (sent > 0) {
      await Promise.all([notifBatch.commit(), updateBatch.commit()]);
    }
    console.log(`notifyStaleProviders: sent=${sent}`);
    return null;
  }
);

// =============================================================================
// ─── AI Opportunity Hunter — daily deal + dormant-client nudges ───────────────
// =============================================================================
// Runs every morning at 08:00 IST.
// 1. Reads optional market_alerts and the current season.
// 2. Calls Claude Haiku to craft a Hebrew "Deal of the Day" headline.
// 3. Stores it in daily_opportunities/{YYYY-MM-DD} for the in-app banner.
// 4. Finds dormant clients (lastActiveAt < 14 days, throttled 3 days/user).
// 5. Sends personalised FCM push + in-app notification to each dormant user.
//
// Firestore written:
//   daily_opportunities/{dateKey} — headline, emoji, category, validDate
//   notifications/{id}            — per dormant user
//   users/{uid}.lastDealNotifyAt  — throttle stamp
// =============================================================================

exports.generateDailyOpportunity = onSchedule(
  {
    schedule:    "0 8 * * *",
    timeZone:    "Asia/Jerusalem",
    region:      "us-central1",
    secrets:     [ANTHROPIC_API_KEY],
    maxInstances: 1,
  },
  async () => {
    const db  = admin.firestore();
    const now = new Date();

    // Date key in Israel time (UTC+3)
    const dateKey = new Date(now.getTime() + 3 * 3600000)
      .toISOString().slice(0, 10); // YYYY-MM-DD

    // ── 1. Check if already generated today ──────────────────────────────
    const dealRef  = db.collection("daily_opportunities").doc(dateKey);
    const existing = await dealRef.get();

    let headline = "";
    let emoji    = "✨";
    let category = "";

    if (!existing.exists) {
      // ── 2. Read optional market alerts ─────────────────────────────────
      let marketContext = "";
      try {
        const alertsSnap = await db.collection("market_alerts")
          .where("isActive", "==", true)
          .limit(3)
          .get();
        if (!alertsSnap.empty) {
          marketContext = alertsSnap.docs
            .map(d => (d.data().text || "")).join(" | ");
        }
      } catch (_) { /* market_alerts is optional */ }

      // ── 3. Season context ───────────────────────────────────────────────
      const month = now.getMonth() + 1; // 1–12
      const seasonMap = {
        12: "חורף — גשמים וקור, מניעת נזקי מים ואיטום",
        1:  "חורף — גשמים וקור, מניעת נזקי מים ואיטום",
        2:  "סוף חורף — תיקוני נזקי חורף ורענון",
        3:  "אביב — ניקיון כללי, גינון, רענון הבית",
        4:  "פסח מתקרב — ניקיון, סדר ועיצוב",
        5:  "קיץ מתקרב — מזגנים, בריכות, שיפוצים",
        6:  "קיץ — גל חום, מזגנים, ריצוף קריר",
        7:  "שיא הקיץ — מזגנים, מים, שיפוצים מהירים",
        8:  "סוף קיץ — תיקונים, צביעה, גינון",
        9:  "ראש השנה — ניקיון כבד, עיצוב הבית לחג",
        10: "סתיו — חימום, אינסטלציה, חשמל",
        11: "לפני חורף — בידוד, ניקוי גגות, הכנות",
      };
      const seasonContext = seasonMap[month] || "עונה שוטפת";

      // ── 4. Call Claude Haiku ────────────────────────────────────────────
      const apiKey = ANTHROPIC_API_KEY.value() || process.env.ANTHROPIC_API_KEY || "";
      const prompt =
        `אתה מנהל שיווק של פלטפורמת שירותים ביתיים בישראל.\n` +
        `כתוב הודעת "הזדמנות היום" קצרה ומשכנעת בעברית (עד 80 תווים).\n` +
        `עונה: ${seasonContext}.\n` +
        (marketContext ? `התראות שוק: ${marketContext}.\n` : "") +
        `ההודעה צריכה להניע לקוחות להזמין שירות עכשיו.\n` +
        `ענה ב-JSON בלבד:\n` +
        `{"headline":"...","emoji":"...","category":"שם קטגוריה"}\n` +
        `קטגוריות: אינסטלציה, חשמלאי, מזגנים, ניקיון, גינון, שיפוצים, צביעה, ריצוף, מנעולן`;

      const _dealAiEnabled = await _isAiEnabled(db);
      if (apiKey && _dealAiEnabled) {
        try {
          const anthropic = new Anthropic({ apiKey });
          const msg = await anthropic.messages.create({
            model:      "claude-haiku-4-5-20251001",
            max_tokens: 150,
            messages:   [{ role: "user", content: prompt }],
          });
          _trackApiCost(db, msg.usage?.input_tokens || 0, msg.usage?.output_tokens || 0).catch(() => {});
          const raw = (msg.content[0]?.text || "{}")
            .replace(/```(?:json)?\s*/gi, "").replace(/```/g, "").trim();
          const parsed = JSON.parse(raw);
          headline = parsed.headline || "";
          emoji    = parsed.emoji    || "✨";
          category = parsed.category || "";
        } catch (err) {
          console.error("generateDailyOpportunity: Claude error:", err);
        }
      } else if (!_dealAiEnabled) {
        console.warn("generateDailyOpportunity: kill-switch active — skipping Claude");
      }

      // Fallback templates if Claude unavailable or parse fails
      if (!headline) {
        const templates = [
          { headline: "הגשם בדרך! בדוק את הגג שלך לפני שיהיה מאוחר מדי.", emoji: "🌧️", category: "אינסטלציה" },
          { headline: "החג מתקרב! הזמן ניקיון מקצועי לפני שהיומנים מתמלאים.", emoji: "✨", category: "ניקיון" },
          { headline: "המזגן שלך מוכן לקיץ? קבל בדיקה עוד היום.", emoji: "❄️", category: "מזגנים" },
          { headline: "3 מומחי שיפוצים זמינים השבוע — מחירים מיוחדים!", emoji: "🔨", category: "שיפוצים" },
        ];
        const t = templates[month % templates.length];
        headline = t.headline;
        emoji    = t.emoji;
        category = t.category;
      }

      await dealRef.set({
        headline, emoji, category,
        seasonContext,
        validDate: dateKey,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`generateDailyOpportunity: stored deal for ${dateKey}: ${headline}`);
    } else {
      const d  = existing.data();
      headline = d.headline || "";
      emoji    = d.emoji    || "✨";
      category = d.category || "";
    }

    // ── 5. Notify dormant clients ─────────────────────────────────────────
    const dormantCutoff  = new Date(now.getTime() - 14 * 86400000); // 14d ago
    const throttleCutoff = new Date(now.getTime() -  3 * 86400000); //  3d ago

    const dormantSnap = await db.collection("users")
      .where("isProvider", "==", false)
      .where("lastActiveAt", "<", admin.firestore.Timestamp.fromDate(dormantCutoff))
      .limit(150)
      .get();

    if (dormantSnap.empty) {
      console.log("generateDailyOpportunity: no dormant clients");
      return null;
    }

    const notifBatch  = db.batch();
    const updateBatch = db.batch();
    let sent = 0;

    for (const doc of dormantSnap.docs) {
      if (sent >= 100) break; // safety cap

      const d = doc.data();
      const lastDealNotify = d.lastDealNotifyAt?.toDate() || new Date(0);
      if (lastDealNotify >= throttleCutoff) continue;

      const name    = d.name || "יקר/ה";
      const lastCat = d.lastSearchedCategory || category;
      const title   = `${emoji} ${name}, הזדמנות ב${lastCat} ממתינה לך!`;
      const body    = headline;
      const token   = d.fcmToken || d.deviceToken;

      if (token) {
        try {
          await admin.messaging().send({
            token,
            notification: { title, body },
            android: {
              priority: "high",
              notification: { channelId: "anyskill_default" },
            },
            apns: {
              headers: { "apns-priority": "10" },
              payload: { aps: { sound: "default", contentAvailable: 1 } },
            },
            webpush: {
              notification: { icon: "/icons/Icon-192.png" },
              fcm_options: { link: "https://anyskill-6fdf3.web.app" },
            },
            data: { type: "daily_deal", category: lastCat, dateKey },
          });
        } catch (e) {
          console.error(`DailyDeal FCM error for ${doc.id}:`, e.message);
        }
      }

      notifBatch.set(db.collection("notifications").doc(), {
        userId: doc.id,
        title,
        body,
        type:      "daily_deal",
        data:      { category: lastCat, dateKey },
        isRead:    false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      updateBatch.update(doc.ref, {
        lastDealNotifyAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      sent++;
    }

    if (sent > 0) {
      await Promise.all([notifBatch.commit(), updateBatch.commit()]);
    }
    console.log(`generateDailyOpportunity: nudged ${sent} dormant client(s)`);
    return null;
  }
);

// =============================================================================
// ─── Financial Health: daily infra cost snapshot ─────────────────────────────
// =============================================================================
// Runs daily at 03:00 Israel time.
// Estimates Firestore usage cost for the past 24 hours and increments
// system_stats/billing.current_month_infra_cost.
//
// Pricing approximations (Firebase Spark → Blaze):
//   Reads:   $0.06  / 100,000 reads
//   Writes:  $0.18  / 100,000 writes
//   Storage: $0.108 / GiB / month  (amortised ~$0.0036/GiB/day)
// =============================================================================
exports.calculateInfraCosts = onSchedule(
  { schedule: "0 3 * * *", timeZone: "Asia/Jerusalem", region: "us-central1" },
  async () => {
    const db       = admin.firestore();
    const today    = new Date().toISOString().slice(0, 10);   // "YYYY-MM-DD"
    const monthKey = today.slice(0, 7);                       // "YYYY-MM"

    // ── 1. Count recent activity as a proxy for daily read/write volume ──
    const since24h = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 86400 * 1000)
    );
    const [activitySnap, chatSnap] = await Promise.all([
      db.collection("activity_log")
        .where("timestamp", ">=", since24h)
        .count().get(),
      db.collection("notifications")
        .where("createdAt", ">=", since24h)
        .count().get(),
    ]);
    const activityCount = activitySnap.data().count || 0;
    const notifCount    = chatSnap.data().count     || 0;

    // Each activity event ≈ 30 reads + 5 writes; each notification ≈ 5 reads
    const estReads  = activityCount * 30 + notifCount * 5 + 5000;  // 5K baseline
    const estWrites = activityCount *  5 + notifCount * 1 + 1000;  // 1K baseline
    const dailyCost = (estReads  / 100000 * 0.06)
                    + (estWrites / 100000 * 0.18);

    // ── 2. Write to system_stats/billing ─────────────────────────────────
    const ref = db.collection("system_stats").doc("billing");
    await ref.set({
      month_key:                monthKey,
      current_month_infra_cost: admin.firestore.FieldValue.increment(dailyCost),
      last_updated:             admin.firestore.FieldValue.serverTimestamp(),
      [`daily_snapshots.${today}`]: {
        infra_cost:   dailyCost,
        est_reads:    estReads,
        est_writes:   estWrites,
        recorded_at:  admin.firestore.FieldValue.serverTimestamp(),
      },
    }, { merge: true });

    console.log(`calculateInfraCosts: ${today} estReads=${estReads} estWrites=${estWrites} cost=$${dailyCost.toFixed(6)}`);
    return null;
  }
);

// =============================================================================
// ─── Financial Health: admin budget settings ─────────────────────────────────
// =============================================================================
// Callable by admin only — updates budget_limit, kill_switch_limit,
// and can manually toggle ai_kill_switch_active.
// =============================================================================
exports.setBillingSettings = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required");

    // Admin guard — only adawiavihai@gmail.com
    const callerSnap = await admin.firestore()
      .collection("users").doc(request.auth.uid).get();
    if (!callerSnap.exists || !callerSnap.data().isAdmin) {
      throw new HttpsError("permission-denied", "Admins only");
    }

    const { budgetLimit, killSwitchLimit, killSwitchActive } = request.data;
    const update = { last_updated: admin.firestore.FieldValue.serverTimestamp() };

    if (typeof budgetLimit      === "number") update.budget_limit       = budgetLimit;
    if (typeof killSwitchLimit  === "number") update.kill_switch_limit  = killSwitchLimit;
    if (typeof killSwitchActive === "boolean") update.ai_kill_switch_active = killSwitchActive;

    await admin.firestore()
      .collection("system_stats").doc("billing")
      .set(update, { merge: true });

    console.log(`setBillingSettings: uid=${request.auth.uid}`, update);
    return { success: true };
  }
);

// =============================================================================
// ─── Account Deletion ─────────────────────────────────────────────────────────
// =============================================================================
// Deletes the user's data across Firestore + Firebase Auth.
//
// Security:
//   - Caller must be the same UID being deleted, OR an admin.
//
// Steps:
//   1. Validate caller identity.
//   2. Flag any in-progress jobs (paid_escrow / expert_completed) so the
//      admin can handle pending funds.
//   3. Batch-delete users/{uid} + userPrivateData/{uid}.
//   4. Write an activity_log entry for admin audit trail.
//   5. Delete the Firebase Auth user (must be last — irreversible).
// =============================================================================
exports.deleteUserAccount = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Login required");
    }

    const callerUid = request.auth.uid;
    const targetUid = (request.data.uid || "").trim();

    if (!targetUid) {
      throw new HttpsError("invalid-argument", "uid is required");
    }

    // ── 1. Authorisation: self-deletion or admin ────────────────────────
    if (callerUid !== targetUid) {
      const callerSnap = await admin.firestore()
          .collection("users").doc(callerUid).get();
      if (!callerSnap.exists || !callerSnap.data().isAdmin) {
        throw new HttpsError("permission-denied",
            "You can only delete your own account");
      }
    }

    const db = admin.firestore();

    // ── 2. Flag in-progress jobs ────────────────────────────────────────
    const activeStatuses = ["paid_escrow", "expert_completed"];
    const [asCustomer, asProvider] = await Promise.all([
      db.collection("jobs")
        .where("customerId", "==", targetUid)
        .where("status", "in", activeStatuses)
        .limit(50).get(),
      db.collection("jobs")
        .where("expertId", "==", targetUid)
        .where("status", "in", activeStatuses)
        .limit(50).get(),
    ]);

    if (!asCustomer.empty || !asProvider.empty) {
      const jobBatch = db.batch();
      for (const doc of [...asCustomer.docs, ...asProvider.docs]) {
        jobBatch.update(doc.ref, {
          status:            "account_deleted",
          deletedAccountUid: targetUid,
          deletedAt:         admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      await jobBatch.commit();
      console.log(`deleteUserAccount: flagged ${asCustomer.size + asProvider.size} active jobs`);
    }

    // ── 3. Delete Firestore docs ────────────────────────────────────────
    const cleanupBatch = db.batch();
    cleanupBatch.delete(db.collection("users").doc(targetUid));
    cleanupBatch.delete(db.collection("userPrivateData").doc(targetUid));

    // ── 4. Activity log ─────────────────────────────────────────────────
    cleanupBatch.set(db.collection("activity_log").doc(), {
      type:      "account_deleted",
      userId:    targetUid,
      deletedBy: callerUid,
      priority:  "medium",
      message:   `חשבון נמחק: ${targetUid}`,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    await cleanupBatch.commit();

    // ── 5. Delete Firebase Auth user (irreversible — must be last) ──────
    await admin.auth().deleteUser(targetUid);

    console.log(`deleteUserAccount: uid=${targetUid} deleted by uid=${callerUid}`);
    return { success: true };
  }
);

// =============================================================================
// ─── Phone Number Sync (admin one-time backfill) ──────────────────────────────
// =============================================================================
// Reads Firebase Auth users in pages of 100, and for any user whose Firestore
// doc is missing the 'phone' field, writes it from auth.phoneNumber.
// Admin-only callable — run once from the admin panel.
// =============================================================================
exports.syncUserPhones = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required");

    const callerSnap = await admin.firestore()
        .collection("users").doc(request.auth.uid).get();
    if (!callerSnap.exists || !callerSnap.data().isAdmin) {
      throw new HttpsError("permission-denied", "Admins only");
    }

    const db = admin.firestore();
    let updated = 0;
    let pageToken;

    do {
      const listResult = await admin.auth().listUsers(100, pageToken);
      const batch = db.batch();
      let writes = 0;

      for (const authUser of listResult.users) {
        const phone = authUser.phoneNumber;
        if (!phone) continue;

        const userSnap = await db.collection("users").doc(authUser.uid).get();
        if (!userSnap.exists) continue;

        const d = userSnap.data();
        const stored = ((d.phone || d.phoneNumber || "")).trim();
        if (!stored) {
          batch.update(db.collection("users").doc(authUser.uid), {
            phone:       phone,
            phoneNumber: phone,
          });
          writes++;
        }
      }

      if (writes > 0) {
        await batch.commit();
        updated += writes;
      }

      pageToken = listResult.pageToken;
    } while (pageToken);

    console.log(`syncUserPhones: updated ${updated} user docs`);
    return { updated };
  }
);

// =============================================================================
// adminApproveProvider — Admin-only callable.
// Approves a provider application using Admin SDK (bypasses all security rules).
// Writes:
//   1. users/{uid}: isProvider, isApprovedProvider, isPendingExpert, isVerified, etc.
//   2. notifications/{id}: push notification to the approved user
//   3. activity_log/{id}: admin audit entry
// =============================================================================
exports.adminApproveProvider = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required");

    // Verify caller is admin (email shortcut OR Firestore flag)
    const callerEmail = request.auth.token.email || "";
    const callerSnap  = await admin.firestore()
        .collection("users").doc(request.auth.uid).get();
    const isAdmin =
        callerEmail === "adawiavihai@gmail.com" ||
        (callerSnap.exists && callerSnap.data().isAdmin === true);

    if (!isAdmin) throw new HttpsError("permission-denied", "Admins only");

    const { uid, name, category } = request.data;
    if (!uid) throw new HttpsError("invalid-argument", "uid is required");

    const db    = admin.firestore();
    const batch = db.batch();

    // 1. Approve the provider
    batch.update(db.collection("users").doc(uid), {
      isProvider:              true,
      isPendingExpert:         false,
      isApprovedProvider:      true,
      isVerifiedProvider:      true,
      isVerified:              true,
      categoryReviewedByAdmin: true,
      ...(category ? { serviceType: category } : {}),
      approvedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 2. Push notification
    batch.set(db.collection("notifications").doc(), {
      userId:    uid,
      title:     "מזל טוב! 🎉",
      body:      "הפרופיל שלך אושר ואתה מופיע עכשיו בחיפוש.",
      type:      "provider_approved",
      isRead:    false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 3. Activity log
    batch.set(db.collection("activity_log").doc(), {
      type:      "provider_approved",
      userId:    uid,
      name:      name || "ספק",
      category:  category || "",
      priority:  "normal",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      message:   `${name || "ספק"} אושר/ה כספק מומחה ב${category || ""}`,
    });

    await batch.commit();

    console.log(`adminApproveProvider: approved uid=${uid}, name=${name}`);
    return { success: true };
  }
);


// ═══════════════════════════════════════════════════════════════════════════════
// AI SERVICE SCHEMA GENERATOR
//
// Takes a Hebrew category name and returns a JSON serviceSchema array with
// category-specific fields (pricing units, boolean features, dropdowns).
// Called from the admin panel when creating or editing a category.
// ═══════════════════════════════════════════════════════════════════════════════

const _SCHEMA_SYSTEM_PROMPT = `\
You are AnySkill's service schema generator for an Israeli marketplace app.
Given a category name in Hebrew, generate a serviceSchema JSON array that
defines the custom fields providers in this category should fill in.

RULES:
1. ALWAYS include a primary price field as the FIRST item (type: "number",
   unit containing "₪" and the appropriate Hebrew pricing unit).
2. Include 2-4 additional fields that are specific to this service category.
3. Field types: "number", "text", "bool", "dropdown".
4. ALL labels and option values MUST be in Hebrew.
5. Each dropdown field MUST include an "options" array with 3-5 Hebrew options.
6. Keep IDs in camelCase English (e.g., "pricePerNight", "hasFencedYard").
7. RESPOND WITH ONLY A VALID JSON ARRAY — no markdown fences, no explanation.

EXAMPLES:

Category: "פנסיון לחיות מחמד"
[
  {"id":"pricePerNight","label":"מחיר ללילה","type":"number","unit":"₪/ללילה"},
  {"id":"hasFencedYard","label":"חצר מגודרת?","type":"bool"},
  {"id":"maxPetWeight","label":"משקל מקסימלי לחיה (ק\"ג)","type":"number","unit":"ק\"ג"},
  {"id":"petTypes","label":"סוגי חיות","type":"dropdown","options":["כלבים","חתולים","כלבים וחתולים","כל סוג"]}
]

Category: "הובלות"
[
  {"id":"pricePerHour","label":"מחיר לשעה","type":"number","unit":"₪/לשעה"},
  {"id":"truckSize","label":"גודל משאית","type":"dropdown","options":["קטנה (1.5 טון)","בינונית (3.5 טון)","גדולה (7+ טון)"]},
  {"id":"includesPacking","label":"כולל אריזה?","type":"bool"},
  {"id":"maxFloors","label":"עד כמה קומות (ללא מעלית)","type":"number","unit":"קומות"}
]`;

exports.generateServiceSchema = onCall(
    {
      secrets:      [ANTHROPIC_API_KEY],
      maxInstances: 5,
      region:       "us-central1",
      memory:       "256MiB",
    },
    async (request) => {
      // ── Auth check ──────────────────────────────────────────────────────
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Login required.");
      }

      // ── Admin check ─────────────────────────────────────────────────────
      const callerSnap = await admin.firestore()
          .collection("users").doc(request.auth.uid).get();
      const isAdminUser =
          callerSnap.exists &&
          (callerSnap.data().isAdmin === true ||
           request.auth.token.email === "adawiavihai@gmail.com");
      if (!isAdminUser) {
        throw new HttpsError("permission-denied", "Admin access required.");
      }

      // ── Input ───────────────────────────────────────────────────────────
      const categoryName = (request.data.categoryName || "").trim();
      if (!categoryName || categoryName.length < 2) {
        throw new HttpsError("invalid-argument",
            "שם קטגוריה חייב להכיל לפחות 2 תווים.");
      }

      // ── Call Claude ─────────────────────────────────────────────────────
      const apiKey = ANTHROPIC_API_KEY.value() ||
          process.env.ANTHROPIC_API_KEY || "";
      if (!apiKey) {
        throw new HttpsError("internal",
            "SECRET_MISSING: ANTHROPIC_API_KEY not configured.");
      }

      const anthropic = new Anthropic({ apiKey });

      const msg = await anthropic.messages.create({
        model:      "claude-haiku-4-5-20251001",
        max_tokens: 1024,
        system:     _SCHEMA_SYSTEM_PROMPT,
        messages:   [{
          role: "user",
          content: `Generate a serviceSchema for the category: "${categoryName}"`,
        }],
      });

      // ── Track cost ──────────────────────────────────────────────────────
      _trackApiCost(
        admin.firestore(),
        msg.usage?.input_tokens || 0,
        msg.usage?.output_tokens || 0,
      ).catch(() => {});

      // ── Parse response ──────────────────────────────────────────────────
      const raw = (msg.content[0]?.text ?? "[]")
          .replace(/```(?:json)?\s*/gi, "")
          .replace(/```/g, "")
          .trim();

      let schema;
      try {
        schema = JSON.parse(raw);
      } catch (e) {
        console.error("generateServiceSchema: JSON parse failed:", raw);
        throw new HttpsError("internal",
            "AI returned invalid JSON. Try again.");
      }

      if (!Array.isArray(schema)) {
        throw new HttpsError("internal",
            "AI returned non-array. Try again.");
      }

      // Validate each field has required properties
      const validated = schema.filter((f) =>
          f && typeof f.id === "string" &&
          typeof f.label === "string" &&
          typeof f.type === "string"
      ).map((f) => ({
        id:      f.id,
        label:   f.label,
        type:    f.type,
        unit:    f.unit || "",
        ...(Array.isArray(f.options) ? { options: f.options } : {}),
      }));

      console.log(`generateServiceSchema: "${categoryName}" → ${validated.length} fields`);
      return { schema: validated };
    }
);


// ═══════════════════════════════════════════════════════════════════════════════
// AI CEO STRATEGIC AGENT
//
// Receives a platform metrics snapshot and returns a strategic analysis:
//   - Morning Brief (Hebrew, concise)
//   - 3 Strategic Recommendations
//   - Red Flags (fraud patterns, drops, anomalies)
// ═══════════════════════════════════════════════════════════════════════════════

const _CEO_SYSTEM_PROMPT = `\
You are the AI CEO of AnySkill, an Israeli service marketplace.
Your goal is to maximize user retention, trust, and platform growth.

You receive a JSON snapshot of current platform metrics.
Analyze the data and respond with ONLY VALID JSON (no markdown, no fences):

{
  "morningBrief": "<2-3 paragraph Hebrew summary of what happened in the last 24h. Include key numbers. Be concise and executive-level.>",
  "recommendations": [
    "<Actionable Hebrew recommendation #1 — be specific with numbers>",
    "<Actionable Hebrew recommendation #2>",
    "<Actionable Hebrew recommendation #3>"
  ],
  "redFlags": [
    "<Hebrew alert about any concerning pattern — fraud, drops, anomalies>"
  ]
}

RULES:
1. ALL text MUST be in Hebrew.
2. morningBrief: Start with a headline, then 2-3 sentences with specific numbers.
3. recommendations: Exactly 3 items. Each must be actionable ("הגדל...", "בדוק...", "שנה...").
4. redFlags: 0-5 items. Include BOTH business AND technical red flags. Empty array [] is fine.
5. If openDisputes > 0 or openTickets > 3, flag it.
6. If pendingVerifications > 5, recommend faster review.
7. If weeklyRevenue is low relative to activeJobs, analyze why.
8. Look at ticketCategories distribution for systemic issues.
9. Look at recentCategoryRequests for market demand signals.

TECHNICAL MONITORING (crashesByErrorCode):
10. The metrics include "crashesByErrorCode" — a map of error codes to {count, severity, platforms, sample}.
11. CRITICAL RULE: If ANY errorCode has count >= 3, it MUST appear as a RED FLAG with prefix "🔧 תקלה טכנית:".
12. Include the error code name, count of affected users, and affected platforms in the red flag text.
13. For fatal crashes (severity="fatal"), always flag even if count is 1.
14. If totalCrashes24h > 10, include a recommendation to investigate via Firebase Crashlytics.
15. If crashes are concentrated on one platform, note it ("רוב הקריסות ב-web/android/ios").`;

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

exports.generateCeoInsight = onCall(
    {
      secrets:      [GEMINI_API_KEY],
      maxInstances: 3,
      region:       "us-central1",
      memory:       "512MiB",
      timeoutSeconds: 120,
    },
    async (request) => {
      // ── Auth: admin only ──────────────────────────────────────────────
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Login required.");
      }
      const callerSnap = await admin.firestore()
          .collection("users").doc(request.auth.uid).get();
      const isAdminUser =
          callerSnap.exists &&
          (callerSnap.data().isAdmin === true ||
           request.auth.token.email === "adawiavihai@gmail.com");
      if (!isAdminUser) {
        throw new HttpsError("permission-denied", "Admin access required.");
      }

      // ── Collect metrics SERVER-SIDE (Admin SDK — bypasses all rules) ──
      const db = admin.firestore();
      const now = new Date();
      const yesterday = new Date(now.getTime() - 24 * 60 * 60 * 1000);
      const lastWeek  = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

      // Helper: safe count — returns 0 on any error
      async function safeSize(query) {
        try { return (await query.limit(500).get()).size; }
        catch { return 0; }
      }
      async function safeDocs(query, limit = 100) {
        try { return (await query.limit(limit).get()).docs; }
        catch { return []; }
      }

      const [
        totalUsers,
        totalProviders,
        pendingVerifications,
        activeJobs,
        completedJobs24h,
        openDisputes,
        openTickets,
        pendingCategories,
        openBroadcasts,
      ] = await Promise.all([
        safeSize(db.collection("users")),
        safeSize(db.collection("users").where("isProvider", "==", true)),
        safeSize(db.collection("users").where("isPendingExpert", "==", true)),
        safeSize(db.collection("jobs").where("status", "in", ["paid_escrow", "expert_completed"])),
        safeSize(db.collection("jobs").where("status", "==", "completed").where("completedAt", ">", yesterday)),
        safeSize(db.collection("jobs").where("status", "==", "disputed")),
        safeSize(db.collection("support_tickets").where("status", "==", "open")),
        safeSize(db.collection("category_requests").where("status", "==", "pending")),
        safeSize(db.collection("job_broadcasts").where("status", "==", "open")),
      ]);

      // Revenue (7 days)
      const earningsDocs = await safeDocs(
        db.collection("platform_earnings").where("timestamp", ">", lastWeek), 200
      );
      let weeklyRevenue = 0;
      earningsDocs.forEach(d => { weeklyRevenue += (d.data().amount || 0); });

      // Ticket categories (24h)
      const ticketDocs = await safeDocs(
        db.collection("support_tickets").where("createdAt", ">", yesterday), 50
      );
      const ticketCategories = {};
      ticketDocs.forEach(d => {
        const cat = d.data().category || "other";
        ticketCategories[cat] = (ticketCategories[cat] || 0) + 1;
      });

      // Category requests (7d)
      const catReqDocs = await safeDocs(
        db.collection("category_requests").where("createdAt", ">", lastWeek), 30
      );
      const recentCategoryRequests = catReqDocs
        .map(d => d.data().description || "")
        .filter(d => d.length > 0);

      // Crash reports (24h)
      const crashDocs = await safeDocs(
        db.collection("crash_reports_summary").where("timestamp", ">", yesterday), 100
      );
      const crashesByErrorCode = {};
      crashDocs.forEach(d => {
        const data = d.data();
        const code = data.errorCode || "unknown";
        if (!crashesByErrorCode[code]) {
          crashesByErrorCode[code] = {
            count: 0, severity: data.severity || "non-fatal",
            platforms: new Set(), sample: data.message || "",
          };
        }
        crashesByErrorCode[code].count++;
        crashesByErrorCode[code].platforms.add(data.platform || "unknown");
      });
      // Convert Sets to arrays for JSON
      Object.values(crashesByErrorCode).forEach(v => {
        v.platforms = [...v.platforms];
      });

      const metrics = {
        totalUsers, totalProviders,
        totalCustomers: totalUsers - totalProviders,
        pendingVerifications, activeJobs, completedJobs24h,
        openDisputes, openTickets, pendingCategories, openBroadcasts,
        weeklyRevenue: weeklyRevenue.toFixed(0),
        ticketCategories, recentCategoryRequests,
        totalCrashes24h: crashDocs.length,
        crashesByErrorCode,
        snapshotTime: now.toISOString(),
      };

      console.log("generateCeoInsight: metrics collected:", JSON.stringify({
        totalUsers, totalProviders, activeJobs, openDisputes,
        openTickets, weeklyRevenue: weeklyRevenue.toFixed(0),
        totalCrashes24h: crashDocs.length,
      }));

      // ── Call Google AI (Gemini) via raw HTTPS — no SDK dependency issues ──
      // Direct REST call to generativelanguage.googleapis.com/v1beta.
      // This bypasses ALL SDK version/model/parameter compatibility problems.
      const geminiKey = GEMINI_API_KEY.value() || process.env.GEMINI_API_KEY || "";
      if (!geminiKey) {
        throw new HttpsError("internal",
          "GEMINI_API_KEY not set. Run: firebase functions:secrets:set GEMINI_API_KEY\n" +
          "Get a free key at: https://aistudio.google.com/apikey");
      }

      const geminiUrl =
        `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${geminiKey}`;

      const geminiBody = {
        contents: [{
          parts: [{
            text: _CEO_SYSTEM_PROMPT +
              "\n\n--- PLATFORM METRICS ---\n\n" +
              JSON.stringify(metrics, null, 2),
          }],
        }],
        generationConfig: {
          temperature: 0.7,
          maxOutputTokens: 2048,
        },
      };

      let parsed;
      try {
        const resp = await fetch(geminiUrl, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(geminiBody),
        });

        if (!resp.ok) {
          const errText = await resp.text();
          console.error("generateCeoInsight: Gemini HTTP error:", resp.status, errText.substring(0, 300));
          throw new HttpsError("internal",
            `Gemini API returned ${resp.status}: ${errText.substring(0, 150)}`);
        }

        const geminiResult = await resp.json();
        const raw = (geminiResult.candidates?.[0]?.content?.parts?.[0]?.text ?? "{}")
            .replace(/```(?:json)?\s*/gi, "")
            .replace(/```/g, "")
            .trim();

        console.log("generateCeoInsight: raw AI response length:", raw.length);

        try {
          parsed = JSON.parse(raw);
        } catch (parseErr) {
          console.error("generateCeoInsight: JSON parse failed:", raw.substring(0, 300));
          throw new HttpsError("internal",
            "AI returned invalid JSON. Snippet: " + raw.substring(0, 150));
        }
      } catch (aiErr) {
        if (aiErr.code) throw aiErr;
        console.error("generateCeoInsight: Gemini call failed:", aiErr.message || aiErr);
        throw new HttpsError("internal",
          "Gemini failed: " + (aiErr.message || "unknown").substring(0, 200));
      }

      console.log("generateCeoInsight: generated successfully");
      return {
        morningBrief:    parsed.morningBrief || "",
        recommendations: Array.isArray(parsed.recommendations) ? parsed.recommendations : [],
        redFlags:        Array.isArray(parsed.redFlags) ? parsed.redFlags : [],
      };
    }
);
