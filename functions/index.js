const { onDocumentCreated } = require("firebase-functions/v2/firestore");
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
        console.log(`QA: Notification sent to ${receiverId} from ${senderName}`);

    } catch (error) {
        console.error('QA Error - sending notification:', error);
    }
    return null;
});

// השורה הבאה היא ה"שינוי" שיכריח את Firebase לעשות Deploy:
// QA_UPDATE_TIMESTAMP: 2026-03-11_12:00