const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

// QA: הפונקציה מאזינה ליצירת הודעה חדשה בתוך הצא'טים
exports.sendchatnotification = onDocumentCreated("chats/{roomId}/messages/{messageId}", async (event) => {
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