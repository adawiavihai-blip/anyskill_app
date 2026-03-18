import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'utils/web_utils.dart';
import 'services/permission_service.dart';
import 'services/locale_provider.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/pending_verification_screen.dart';
import 'l10n/app_localizations.dart';

// The running app version — populated from pubspec.yaml via PackageInfo in main().
// Admins auto-push this value to admin/settings.latestVersion on login,
// triggering the update banner for all other users.
String currentAppVersion = '2.1.6'; // fallback; overwritten before runApp()

// ── Global navigator key ──────────────────────────────────────────────────────
// Used by notification handlers to navigate without a BuildContext.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

// ── Pending notification intent ───────────────────────────────────────────────
// Set when the user taps a notification. HomeScreen reads this in initState
// and calls setState(() => _selectedIndex = PendingNotification.tabIndex!).
class PendingNotification {
  static int?    tabIndex;    // tab to activate in HomeScreen
  static String? chatRoomId;  // optional: open a specific chat room

  static void fromMessage(RemoteMessage message) {
    final type = message.data['type'] as String?;
    chatRoomId = message.data['chatRoomId'] as String?;
    switch (type) {
      case 'chat':         tabIndex = 2; break;
      case 'booking':      tabIndex = 1; break;
      case 'job_request':  tabIndex = 5; break; // הזדמנויות (index 5 — calendar tab removed)
      case 'market_alert': tabIndex = 6; break; // ניהול (index 6 for admin+provider)
      default:             tabIndex = 0;
    }
  }

  static void clear() {
    tabIndex   = null;
    chatRoomId = null;
  }
}

// ── Background isolate handler ────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Must re-initialise Firebase in the background isolate.
  // The OS displays the notification automatically from the FCM payload.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

// ── Entry point ───────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Read real version from pubspec.yaml — no more manual constant updates.
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.isNotEmpty) currentAppVersion = info.version;
  } catch (_) {}

  // Load saved locale BEFORE first frame so there's no flash of wrong language.
  await LocaleProvider.init();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (kIsWeb) {
    try {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,   // IndexedDB cache — serves cold reads from cache (<20ms)
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      debugPrint("AnySkill Web: Auth LOCAL persistence set, Firestore cache ENABLED");
    } catch (e) {
      debugPrint("Firestore/Auth Web Config Error: $e");
    }
  }

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // ── Global Flutter error logger ───────────────────────────────────────────
  // Writes every unhandled Flutter rendering/framework error to Firestore
  // `error_logs` so the admin SystemPerformanceTab can surface it in real-time.
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    originalOnError?.call(details);        // keep default behaviour (prints to console)
    try {
      FirebaseFirestore.instance.collection('error_logs').add({
        'type':      'flutter',
        'message':   details.exceptionAsString(),
        'screen':    details.library ?? '',
        'userId':    FirebaseAuth.instance.currentUser?.uid ?? '',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {}                         // never let logging crash the app
  };

  runApp(const AnySkillApp());
}

// ── Root widget ───────────────────────────────────────────────────────────────
class AnySkillApp extends StatelessWidget {
  const AnySkillApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ListenableBuilder rebuilds MaterialApp whenever the user switches language.
    return ListenableBuilder(
      listenable: LocaleProvider.instance,
      builder: (context, _) {
        final locale = LocaleProvider.instance.locale;
        return MaterialApp(
          navigatorKey: rootNavigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'AnySkill',
          // ── i18n: persisted locale (default: Hebrew RTL) ─────────────────
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales:       AppLocalizations.supportedLocales,
          locale:                 locale,
          // Auto-resolve RTL/LTR: GlobalMaterialLocalizations handles directionality
          // for Hebrew (RTL) and English/Spanish (LTR) automatically.
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF007AFF)),
            scaffoldBackgroundColor: Colors.white,
            textTheme: GoogleFonts.heeboTextTheme(Theme.of(context).textTheme).apply(
              fontFamilyFallback: ['NotoSansHebrew'],
            ),
          ),
          home: const AuthWrapper(),
        );
      },
    );
  }
}

// ── Auth wrapper ──────────────────────────────────────────────────────────────
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  StreamSubscription<User?>?           _authSub;
  StreamSubscription<DocumentSnapshot>? _versionSub;
  SharedPreferences?                    _prefs;

  bool    _updateNotified = false;
  bool    _bannerVisible  = false;
  // The version string from Firestore that triggered the current banner.
  // Stored so we can persist "dismissed for this version" when user taps × or Update.
  String? _latestVersion;

  @override
  void initState() {
    super.initState();
    // Load persistent storage early — will be ready well before any version banner fires.
    SharedPreferences.getInstance().then((p) => _prefs = p);
    _handleWebUpdates();
    _setupPushNotifications();

    // FIX: previously _checkVersionUpdate() ran before auth was ready,
    // so currentUser was always null. Now we wait for a confirmed login.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _startVersionListener();
        _saveAndRefreshToken(user.uid);
        // After login: recover permission state from Firestore so a reinstall
        // doesn't re-prompt a user who had already granted permissions before.
        PermissionService.recoverFromFirestore();
      } else {
        _versionSub?.cancel();
        _versionSub = null;
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _versionSub?.cancel();
    super.dispose();
  }

  // ── Version check (real-time) ──────────────────────────────────────────────
  // Subscribes to admin/settings. Shows the update banner ONLY when Firestore
  // has a STRICTLY HIGHER version than the running build.
  // No auto-reload — the user controls when to reload via the banner button.
  void _startVersionListener() {
    _versionSub?.cancel();
    _updateNotified = false;
    _versionSub = FirebaseFirestore.instance
        .collection('admin')
        .doc('settings')
        .snapshots()
        .listen((doc) {
      if (!doc.exists || !mounted || _updateNotified) return;
      final latest =
          (doc.data()?['latestVersion'] as String?) ?? currentAppVersion;

      // Only show the banner when the server version is strictly newer.
      if (!_isNewerVersion(latest, currentAppVersion)) return;

      // Check if the user has already dismissed THIS specific version.
      // SharedPreferences persists across reloads/restarts on both web and native.
      final dismissed = _prefs?.getString('banner_dismissed_v');
      if (dismissed == latest) return;

      _updateNotified = true;
      _latestVersion  = latest;
      _showUpdateBanner();
    }, onError: (_) {}); // silently ignore permission-denied for non-admins
  }

  /// Returns true only if [candidate] is STRICTLY greater than [base].
  /// Compares "MAJOR.MINOR.PATCH" version strings segment by segment.
  bool _isNewerVersion(String candidate, String base) {
    final c = candidate.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final b = base.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final len = c.length > b.length ? c.length : b.length;
    while (c.length < len) { c.add(0); }
    while (b.length < len) { b.add(0); }
    for (int i = 0; i < len; i++) {
      if (c[i] > b[i]) return true;
      if (c[i] < b[i]) return false;
    }
    return false;
  }

  // ── Update banner: state-driven ───────────────────────────────────────────
  // Sets a flag that causes build() to overlay the glassmorphism banner.
  // No ScaffoldMessenger involved — the banner floats above the entire tree
  // and is dismissed only by explicit user action, which iOS always respects.
  void _showUpdateBanner() {
    if (!mounted) return;
    setState(() => _bannerVisible = true);
  }

  // ── Glassmorphism floating banner widget ───────────────────────────────────
  Widget _buildUpdateBanner() {
    return Positioned(
      bottom: 90, // sits above the bottom navigation bar
      left: 16,
      right: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1B4B).withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Builder(builder: (ctx) {
              final l10n = AppLocalizations.of(ctx);
              return Directionality(
                textDirection: l10n.isCurrentRtl
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: Row(
                children: [
                  const Icon(Icons.system_update_alt_rounded,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.updateBannerText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // ── Update now button ──────────────────────────────────────
                  ElevatedButton(
                    onPressed: () async {
                      // Persist dismissed version BEFORE reload so the banner
                      // doesn't reappear on the fresh page (fixes the loop).
                      if (_latestVersion != null) {
                        await _prefs?.setString('banner_dismissed_v', _latestVersion!);
                      }
                      if (!mounted) return;
                      setState(() => _bannerVisible = false);
                      if (kIsWeb) pageReload();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(l10n.updateNowButton,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                  // ── Dismiss (×) ────────────────────────────────────────────
                  GestureDetector(
                    onTap: () async {
                      // Remember this version was dismissed so it won't resurface.
                      if (_latestVersion != null) {
                        await _prefs?.setString('banner_dismissed_v', _latestVersion!);
                      }
                      if (!mounted) return;
                      setState(() => _bannerVisible = false);
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4, left: 8),
                      child: Icon(Icons.close_rounded,
                          color: Colors.white.withValues(alpha: 0.55), size: 18),
                    ),
                  ),
                ],
              ), // Row
            ); // Directionality
            }), // Builder
          ),
        ),
      ),
    );
  }

  // ── Web service-worker auto-refresh ───────────────────────────────────────
  // FIX 3: Removed the duplicate controllerchange → reload listener.
  // app_init.js already handles this with a proper _isReloading guard.
  // Having two callers of window.location.reload() on the same event
  // doubled every SW-triggered reload and could race with the version listener.
  void _handleWebUpdates() {
    // intentionally left empty — SW reload is handled by app_init.js
  }

  // ── Push Notifications ─────────────────────────────────────────────────────
  void _setupPushNotifications() async {
    try {
      final messaging = FirebaseMessaging.instance;

      // ── Step 1: Check stored permission answer ─────────────────────────────
      final storedNotif = await PermissionService.getNotificationStatus();

      if (storedNotif == PermissionService.denied) {
        // User already refused — only wire background-tap navigation, no token.
        FirebaseMessaging.onMessageOpenedApp.listen(_navigateFromMessage);
        final initial = await messaging.getInitialMessage();
        if (initial != null) {
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => _navigateFromMessage(initial));
        }
        return;
      }

      if (storedNotif != PermissionService.granted) {
        // Never asked (or status unknown) — ask the OS exactly once.
        final settings = await messaging.requestPermission(
          alert: true, badge: true, sound: true,
        );
        final authorized =
            settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
        await PermissionService.saveNotificationStatus(
          authorized ? PermissionService.granted : PermissionService.denied,
        );
        if (!authorized) return;
      }
      // If storedNotif == 'granted' we skip requestPermission() entirely —
      // no OS dialog on every restart.

      // ── Step 2: Get / refresh FCM token ───────────────────────────────────
      // Web: getToken() needs the VAPID key; handled by the service worker on
      // web, so we skip here. Mobile always proceeds.
      if (!kIsWeb) {
        final token = await messaging.getToken();
        if (token != null) _saveTokenToDatabase(token);
        messaging.onTokenRefresh.listen(_saveTokenToDatabase);
      }

      // ── 1. Foreground: show in-app SnackBar banner ─────────────────────────
      // When the app is open, FCM does NOT auto-display a system notification.
      // We show our own banner so the user is still informed.
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final notification = message.notification;
        if (notification == null) return;

        final ctx = rootNavigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;

        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (notification.title != null)
                  Text(
                    notification.title!,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                if (notification.body != null)
                  Text(notification.body!),
              ],
            ),
            backgroundColor: const Color(0xFF6366F1),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: AppLocalizations.of(ctx).notifOpen,
              textColor: Colors.white,
              onPressed: () => _navigateFromMessage(message),
            ),
          ),
        );
      });

      // ── 2. Background tap: app was running in background ──────────────────
      FirebaseMessaging.onMessageOpenedApp.listen(_navigateFromMessage);

      // ── 3. Cold-start tap: app was fully terminated ────────────────────────
      // getInitialMessage() returns the notification that launched the app.
      // We defer navigation until after the first frame so HomeScreen is mounted.
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _navigateFromMessage(initialMessage),
        );
      }
    } catch (e) {
      debugPrint("Messaging Error: $e");
    }
  }

  /// Stores the navigation intent and pops any routes on top of HomeScreen.
  /// HomeScreen reads [PendingNotification.tabIndex] in initState and applies it.
  void _navigateFromMessage(RemoteMessage message) {
    PendingNotification.fromMessage(message);
    // If a dialog / sub-page is open, close it first.
    final nav = rootNavigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.popUntil((route) => route.isFirst);
    }
    // HomeScreen picks up PendingNotification in its initState / next build.
  }

  /// Called on every confirmed login — fetches the current FCM token and writes
  /// it to the user's Firestore doc. Fixes the case where the token was not
  /// saved on first install because [currentUser] was null at call time.
  Future<void> _saveAndRefreshToken(String uid) async {
    if (kIsWeb) return; // FCM tokens on web are handled by the service worker
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fcmToken': token,
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Token refresh error: $e');
    }
  }

  void _saveTokenToDatabase(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'fcmToken': token,
      'lastActive': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Colors.white,
                body: Center(
                  child: Image(
                    image: AssetImage('assets/images/LOGO.gif'),
                    width: 200,
                  ),
                ),
              );
            }
            if (snapshot.hasData && snapshot.data != null) {
              return const _OnboardingGate();
            }
            return const LoginScreen();
          },
        ),
        // Glassmorphism update banner — floats above all screens, iOS-safe.
        // Only shown when Firestore reports a strictly newer version.
        if (_bannerVisible) _buildUpdateBanner(),
      ],
    );
  }
}

// ── Onboarding gate ───────────────────────────────────────────────────────────
// One-time Firestore fetch (8 s timeout) to check onboardingComplete.
// Uses FutureBuilder so a Firestore error or slow connection never leaves the
// user staring at a spinner; on any failure we default to HomeScreen.
class _OnboardingGate extends StatefulWidget {
  const _OnboardingGate();

  @override
  State<_OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<_OnboardingGate> {
  late final Future<DocumentSnapshot> _future;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _future = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get()
        .timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw Exception('timeout'),
        );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        // On error (Firestore crash, timeout, no network) default to HomeScreen.
        if (snapshot.hasError) {
          debugPrint('_OnboardingGate error: ${snapshot.error}');
          return const HomeScreen();
        }
        final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};

        // Providers who haven't been verified yet land on the waiting screen
        final isProvider  = data['isProvider']  == true;
        final isVerified  = data['isVerified']   == true;
        if (isProvider && !isVerified) {
          return const PendingVerificationScreen();
        }

        final complete = data['onboardingComplete'] ?? true; // existing users skip
        return complete ? const HomeScreen() : const OnboardingScreen();
      },
    );
  }
}
