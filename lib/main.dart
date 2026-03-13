import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; 
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';

// גרסה 1.0.4 - שחרור תקיעה וייצוב סופי
const String currentAppVersion = "1.0.4"; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. אתחול Firebase בצורה נקייה
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  // 2. פתרון ל-Web בלי פקודות terminate שתוקעות את המערכת
  if (kIsWeb) {
    try {
      // ביטול ה-Persistence מונע את השגיאה של אבי מהשורש
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
      );
      
      // ניקוי זיכרון תקוע ברקע בלי await כדי לא לעצור את עליית האפליקציה
      FirebaseFirestore.instance.clearPersistence().catchError((e) => debugPrint("Persistence clear info: $e"));
      
      debugPrint("AnySkill Web: Optimized & Persistence Disabled");
    } catch (e) {
      debugPrint("Firestore Web Config Error: $e");
    }
  }

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const AnySkillApp());
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

class AnySkillApp extends StatelessWidget {
  const AnySkillApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AnySkill Elite',
      theme: ThemeData(
        useMaterial3: true, 
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF007AFF)),
        scaffoldBackgroundColor: Colors.white,
        textTheme: GoogleFonts.heeboTextTheme(Theme.of(context).textTheme),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  DateTime? _lastVersionCheck;

  @override
  void initState() {
    super.initState();
    _handleWebUpdates();
    _setupPushNotifications();
    _checkVersionUpdate();
  }

  // בדיקת גרסה — רק כשהמשתמש מחובר, מוגבלת פעם אחת לשעה
  void _checkVersionUpdate() async {
    // דילוג כשאין משתמש מחובר — admin/settings דורש אימות
    if (FirebaseAuth.instance.currentUser == null) return;

    final now = DateTime.now();
    if (_lastVersionCheck != null &&
        now.difference(_lastVersionCheck!).inMinutes < 60) {
      return;
    }
    _lastVersionCheck = now;

    try {
      final settings = await FirebaseFirestore.instance
          .collection('admin')
          .doc('settings')
          .get();

      if (settings.exists) {
        final latestVersion =
            (settings.data()?['latestVersion'] as String?) ?? currentAppVersion;
        if (latestVersion != currentAppVersion && mounted) {
          _showUpdateBanner();
        }
      }
    } on FirebaseException catch (e) {
      // permission-denied אינה שגיאה אמיתית — הכלל עשוי לדרוש הרשאה גבוהה יותר
      if (e.code != 'permission-denied') {
        debugPrint("Version check failed: ${e.code} — ${e.message}");
      }
    } catch (e) {
      debugPrint("Version check failed: $e");
    }
  }

  void _showUpdateBanner() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("עדכון מערכת זמין לשיפור היציבות."),
        backgroundColor: Colors.blueAccent,
        duration: const Duration(seconds: 10),
        behavior: SnackBarBehavior.fixed,
        action: SnackBarAction(
          label: "עדכן כעת",
          textColor: Colors.white,
          onPressed: () {
            if (kIsWeb) {
              // רענון שמנקה Cache
              web.window.location.reload();
            }
          },
        ),
      ),
    );
  }

  void _handleWebUpdates() {
    if (kIsWeb) {
      web.window.navigator.serviceWorker.addEventListener(
        'controllerchange',
        (JSAny? _) { web.window.location.reload(); }.toJS,
      );
    }
  }

  void _setupPushNotifications() async {
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      NotificationSettings settings = await messaging.requestPermission(alert: true, badge: true, sound: true);

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        String? token = await messaging.getToken();
        if (token != null) _saveTokenToDatabase(token);
      }
    } catch (e) {
      debugPrint("Messaging Error: $e");
    }
  }

  void _saveTokenToDatabase(String? token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && token != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData && snapshot.data != null) {
          return const _OnboardingGate();
        }
        return const LoginScreen();
      },
    );
  }
}

// Checks onboardingComplete for the logged-in user and routes accordingly.
class _OnboardingGate extends StatelessWidget {
  const _OnboardingGate();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final complete = data['onboardingComplete'] ?? true; // existing users skip
        return complete ? const HomeScreen() : const OnboardingScreen();
      },
    );
  }
}