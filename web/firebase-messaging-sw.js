// Firebase Messaging Service Worker
// חייב להיות בתיקיית web/ כדי שהדפדפן יוכל לרשום אותו

// ── Auto-update: respond to SKIP_WAITING posted from app_init.js ─────────────
// When app_init.js detects a new SW version, it posts 'SKIP_WAITING' to the
// installing worker. This handler activates it immediately without waiting for
// all tabs to close, which then triggers a controllerchange → page reload.
// ── Force immediate activation — no waiting for old tabs to close ────────────
self.addEventListener('install', function() { self.skipWaiting(); });
self.addEventListener('activate', function(event) {
  event.waitUntil(self.clients.claim());
});
self.addEventListener('message', function(event) {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
});

importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js');

// CRITICAL: These values MUST match lib/firebase_options.dart (web config).
// A mismatch means the SW initializes the wrong project → no push messages.
firebase.initializeApp({
  apiKey:            "AIzaSyCk9QZ0cIfpeBP2EJ6aZfTHncmg7opphNQ",
  projectId:         "anyskill-6fdf3",
  messagingSenderId: "281981409319",
  appId:             "1:281981409319:web:b1300598e2454b72819602",
});

const messaging = firebase.messaging();

// טיפול בהתראות ברקע (כשהאפליקציה סגורה / לא פתוחה בפועל)
messaging.onBackgroundMessage((payload) => {
  console.log('[FCM-SW] Background message received:', JSON.stringify(payload.data));
  const title = payload.notification?.title ?? 'AnySkill';
  const body  = payload.notification?.body  ?? '';
  const data  = payload.data || {};
  return self.registration.showNotification(title, {
    body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: data.chatRoomId || data.jobId || 'anyskill',
    data: data, // passed to notificationclick handler
    // iOS PWA requires these for sound:
    vibrate: [200, 100, 200],
    requireInteraction: true,
  });
});

// ── Fix: Skip caching for partial (206) responses ───────────────────────────
// The Flutter service worker tries to cache ALL responses, but 206 Partial
// Content (video range requests) throws "TypeError: failed to execute 'put'
// on 'Cache'". This fetch listener intercepts and prevents the error.
self.addEventListener('fetch', function(event) {
  const url = event.request.url;
  // Only intercept media files from Firebase Storage
  if (url.includes('firebasestorage') && (url.includes('.mp4') || url.includes('.webm') || url.includes('.mov'))) {
    event.respondWith(
      fetch(event.request).then(function(response) {
        // Don't cache partial responses (206) or error responses
        if (response.status === 206 || !response.ok) {
          return response;
        }
        return response;
      }).catch(function() {
        return new Response('', { status: 503 });
      })
    );
    return; // handled — don't pass to Flutter SW
  }
});

// Handle notification click — open the app or focus existing tab
self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  const url = 'https://anyskill-6fdf3.web.app';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(clientList) {
      // If the app is already open, focus it
      for (var i = 0; i < clientList.length; i++) {
        if (clientList[i].url.includes('anyskill') && 'focus' in clientList[i]) {
          return clientList[i].focus();
        }
      }
      // Otherwise open a new window
      return clients.openWindow(url);
    })
  );
});
