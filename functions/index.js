const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

admin.initializeApp();

// מספר ה-shards לכל מונה unreadCount — מפיץ כתיבות ומונע write contention
const NUM_SHARDS = 5;

// QA: הפונקציה מאזינה ליצירת הודעה חדשה בתוך הצא'טים
// maxInstances + concurrency מאפשרים עד 100 * 500 = 50,000 בקשות במקביל ללא cold starts
exports.sendchatnotification = onDocumentCreated(
    { document: "chats/{roomId}/messages/{messageId}", maxInstances: 100, concurrency: 500 },
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

        // 4. בניית ה-Payload ל-FCM
        const messagePayload = {
            token: targetToken,
            notification: {
                title: senderName,
                body: notificationBody,
            },
            data: {
                senderId: senderId,
                roomId: event.params.roomId,
                click_action: "FLUTTER_NOTIFICATION_CLICK",
                type: "chat"
            },
            webpush: {
                notification: {
                    icon: "/icons/Icon-192.png",
                    badge: "/icons/Icon-192.png",
                    click_action: "https://anyskill-6fdf3.web.app"
                },
                fcm_options: {
                    link: "https://anyskill-6fdf3.web.app"
                }
            }
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
            console.log('[PPR] STEP6 TX: reading adminSettings...');
            const adminSnap = await tx.get(adminSettingsRef);
            const feePercentage = adminSnap.exists ? (adminSnap.data().feePercentage ?? 0.10) : 0.10;
            const feeAmount   = totalAmount * feePercentage;
            const netToExpert = totalAmount - feeAmount;
            console.log(`[PPR] STEP6 TX: feePercentage=${feePercentage}, feeAmount=${feeAmount}, netToExpert=${netToExpert}`);

            console.log('[PPR] STEP6 TX: updating job...');
            tx.update(jobRef, {
                status: 'completed',
                completedAt: admin.firestore.FieldValue.serverTimestamp(),
                feeAmount,
                netAmountForExpert: netToExpert,
            });

            console.log('[PPR] STEP6 TX: updating expert balance + orderCount...');
            tx.update(expertRef, {
                balance:     admin.firestore.FieldValue.increment(netToExpert),
                orderCount:  admin.firestore.FieldValue.increment(1),
            });

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
function _computeLevel(xp) {
    if (xp >= 1500) return 'gold';
    if (xp >= 500)  return 'silver';
    return 'bronze';
}

async function _awardXp(uid, amount, reason) {
    const db = admin.firestore();
    const userRef = db.collection('users').doc(uid);
    await db.runTransaction(async (tx) => {
        const snap = await tx.get(userRef);
        if (!snap.exists) return;
        const currentXp = (snap.data().xp || 0) + amount;
        tx.update(userRef, {
            xp: admin.firestore.FieldValue.increment(amount),
            level: _computeLevel(currentXp),
        });
    });
    console.log(`XP: +${amount} to ${uid} for ${reason}`);
}

// ── Job completed → +100 XP to expert ────────────────────────────────────────
exports.awardXpJobCompleted = onDocumentUpdated("jobs/{jobId}", async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();
    if (before.status === after.status) return null;
    if (after.status !== 'completed')   return null;
    const expertId = after.expertId;
    if (!expertId) return null;
    try {
        await _awardXp(expertId, 100, 'job_completed');
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
        await _awardXp(expertId, 50, 'five_star_review');
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
    <div class="row"><span class="label">לקוח</span><span><strong>${after.customerName || '—'}</strong></span></div>
    <div class="row"><span class="label">נותן שירות</span><span><strong>${after.expertName || '—'}</strong></span></div>
    <div class="row"><span class="label">תאריך שירות</span><span>${dateLabel}</span></div>
    ${expertTaxId ? `<div class="row"><span class="label">ח.פ / ת.ז ספק</span><span>${expertTaxId}</span></div>` : ''}
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
                    subject: `קבלה על שירות מ-${after.expertName} — AnySkill #${receiptNum}`,
                    html:    receiptHtml('customer'),
                },
            });
        }

        // Email to expert (shows net amount)
        if (expertEmail) {
            batch.set(db.collection('mail').doc(), {
                to:      [expertEmail],
                message: {
                    subject: `סיכום עסקה עם ${after.customerName} — AnySkill #${receiptNum}`,
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
