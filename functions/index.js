const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
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

// ── Callable: מחיקת משתמש (Admin SDK — דורש הרשאת admin) ────────────────────
exports.deleteUser = onCall(async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }

    // אימות שהמשתמש הקורא הוא מנהל
    const callerSnap = await admin.firestore().collection('users').doc(request.auth.uid).get();
    if (!callerSnap.exists || !callerSnap.data().isAdmin) {
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