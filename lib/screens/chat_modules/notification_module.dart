import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/permission_service.dart';

class NotificationModule {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  static Future<bool> requestPermissions() async {
    // Never re-prompt if we already have a stored answer.
    final stored = await PermissionService.getNotificationStatus();
    if (stored == PermissionService.granted) return true;
    if (stored == PermissionService.denied)  return false;

    try {
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final ok = settings.authorizationStatus == AuthorizationStatus.authorized;
      await PermissionService.saveNotificationStatus(
        ok ? PermissionService.granted : PermissionService.denied,
      );
      return ok;
    } catch (e) {
      debugPrint("QA Error - Permissions: $e");
      return false;
    }
  }

  static Future<void> saveDeviceToken(String userId) async {
    if (userId.isEmpty) return;

    try {
      // שליפת הטוקן עם ה-VAPID Key שלך
      String? token = await _fcm.getToken(
        vapidKey: "BMps6y9pYxVgpcL6BI6iieleDICi-coUHasv6KjzYzdawU", 
      );

      // שימוש ב-Set עם Merge כדי לוודא יצירה/עדכון בטוחים
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'deviceToken': token,
        'fcmToken': token,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
        'platform': 'web',
      }, SetOptions(merge: true));
      
      debugPrint("QA Success: FCM token saved to Firestore");
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