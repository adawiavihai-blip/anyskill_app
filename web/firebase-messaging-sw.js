// Firebase Messaging Service Worker
// חייב להיות בתיקיית web/ כדי שהדפדפן יוכל לרשום אותו

importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey:            "AIzaSyDybWlbmpqTG-cvqxTQrirtDsqv17LBHzk",
  projectId:         "anyskill-6fdf3",
  messagingSenderId: "1056580918501",
  appId:             "1:1056580918501:web:4f0d36c57f7396c4d35eb7",
});

const messaging = firebase.messaging();

// טיפול בהתראות ברקע (כשהאפליקציה סגורה / לא פתוחה בפועל)
messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title ?? 'AnySkill';
  const body  = payload.notification?.body  ?? '';
  self.registration.showNotification(title, {
    body,
    icon: '/icons/Icon-192.png',
  });
});
