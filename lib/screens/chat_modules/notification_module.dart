import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'dart:js_interop';

class NotificationModule {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  static Future<bool> requestPermissions() async {
    try {
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (e) {
      debugPrint("QA Error - Permissions: $e");
      return false;
    }
  }

  static Future<void> saveDeviceToken(String userId) async {
    if (userId.isEmpty) return;

    try {
      // QA Fix: רישום ידני של ה-Service Worker כדי למנוע את שגיאת pushManager
      if (kIsWeb) {
        final registration = await web.window.navigator.serviceWorker
            .register('/firebase-messaging-sw.js'.toJS)
            .toDart;
        debugPrint("QA: Service Worker registered: ${registration.scope}");
      }

      // שליפת הטוקן עם ה-VAPID Key שלך
      String? token = await _fcm.getToken(
        vapidKey: "BMps6y9pYxVgpcL6BI6iieleDICi-coUHasv6KjzYzdawU", 
      );

      if (token != null) {
        // שימוש ב-Set עם Merge כדי לוודא יצירה/עדכון בטוחים
        await FirebaseFirestore.instance.collection('users').doc(userId).set({
          'deviceToken': token,
          'fcmToken': token,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
          'platform': 'web',
        }, SetOptions(merge: true));
        
        debugPrint("QA Success: Token saved to Firestore: $token");
      }
    } catch (e) {
      debugPrint("QA Error - Save Token: $e");
    }
  }

  static void listenToForegroundMessages(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Directionality(
              textDirection: TextDirection.rtl,
              child: Text("${message.notification!.title}: ${message.notification!.body}"),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF007AFF),
          ),
        );
      }
    });
  }
}