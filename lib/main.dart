import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'utils/web_utils.dart';
import 'services/permission_service.dart';
import 'services/locale_provider.dart';
import 'services/cache_service.dart';
import 'services/audio_service.dart';
import 'repositories/logger_repository.dart';
import 'models/app_log.dart';
import 'theme/app_theme.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/phone_login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'constants.dart' show appVersion;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/stripe_service.dart';
import 'screens/pending_verification_screen.dart';
import 'screens/permission_request_screen.dart';
import 'l10n/app_localizations.dart';

// The running app version — populated from pubspec.yaml via PackageInfo in main().
// Admins auto-push this value to admin/settings.latestVersion on login,
// triggering the update banner for all other users.
String currentAppVersion =
    appVersion; // fallback from constants.dart; overwritten by PackageInfo before runApp()


// ── Global navigator key ──────────────────────────────────────────────────────
// Used by notification handlers to navigate without a BuildContext.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

// ── Pending notification intent ───────────────────────────────────────────────
// Set when the user taps a notification. HomeScreen reads this in initState
// and calls setState(() => _selectedIndex = PendingNotification.tabIndex!).
class PendingNotification {
  static int? tabIndex; // tab to activate in HomeScreen
  static String? chatRoomId; // optional: open a specific chat room

  static void fromMessage(RemoteMessage message) {
    final type = message.data['type'] as String?;
    chatRoomId = message.data['chatRoomId'] as String?;
    switch (type) {
      case 'chat':
        tabIndex = 2;
        break;
      case 'booking':
        tabIndex = 1;
        break;
      case 'job_request':
        tabIndex = 5;
        break; // הזדמנויות (index 5 — calendar tab removed)
      case 'market_alert':
        tabIndex = 6;
        break; // ניהול (index 6 for admin+provider)
      default:
        tabIndex = 0;
    }
  }

  static void clear() {
    tabIndex = null;
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

// ── Create Firestore profile for a social-login user (if new) ────────────────
Future<void> _ensureProfileExists(User user) async {
  try {
    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await docRef.get();
    if (snap.exists) {
      // Backfill profileImage from Auth if Firestore field is empty.
      // Early accounts were created before profileImage was added to the schema.
      final data = snap.data() ?? {};
      final firestoreImg = data['profileImage'] as String? ?? '';
      final authImg = user.photoURL ?? '';
      if (firestoreImg.isEmpty && authImg.isNotEmpty) {
        await docRef.update({'profileImage': authImg});
        // ignore: avoid_print
        print('🔧 [Profile] Backfilled profileImage from Auth photoURL for ${user.uid}');
      }
      return;
    }
    await docRef.set({
      'uid':            user.uid,
      'name':           user.displayName ?? '',
      'email':          user.email ?? '',
      'phone':          user.phoneNumber ?? '',
      'rating':         5.0,
      'reviewsCount':   0,
      'pricePerHour':   0.0,
      'serviceType':    '',
      'aboutMe':        '',
      'profileImage':   user.photoURL ?? '',
      'gallery':        [],
      'quickTags':      [],
      'isOnline':       true,
      'isCustomer':     true,
      'isProvider':     false,
      'termsAccepted':  true,
      'onboardingComplete': false,
      'tourComplete':   false,
      'createdAt':      FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    // ignore: avoid_print
    print('✅ [Profile] Created for ${user.uid}');
  } catch (e) {
    // ignore: avoid_print
    print('⚠️ [Profile] Creation failed: $e');
  }
}

// ── Web auth session check ───────────────────────────────────────────────────
// On web startup, check if Firebase Auth already has a signed-in user
// (restored from IndexedDB persistence). If so, ensure their profile exists.
// No redirect handling needed — we use signInWithPopup exclusively.
Future<void> _handleWebRedirectResult() async {
  final existingUser = FirebaseAuth.instance.currentUser;
  if (existingUser != null) {
    // ignore: avoid_print
    print('✅ [Auth] Session restored: uid=${existingUser.uid}');
    await _ensureProfileExists(existingUser);
  } else {
    // ignore: avoid_print
    print('ℹ️ [Auth] No existing session — showing login screen');
  }
}

// ── Entry point ───────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();


  // ── Step 1: PackageInfo ────────────────────────────────────────────────────
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.isNotEmpty) currentAppVersion = info.version;
    debugPrint('✅ PackageInfo: $currentAppVersion');
  } catch (e) {
    debugPrint('⚠️ PackageInfo failed (using constants fallback): $e');
  }

  // ── Step 2: Locale ────────────────────────────────────────────────────────
  try {
    await LocaleProvider.init();
    debugPrint('✅ LocaleProvider ready');
  } catch (e) {
    debugPrint('⚠️ LocaleProvider failed (using default locale): $e');
  }

  // ── Step 3: Firebase core ─────────────────────────────────────────────────
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ Firebase initialized');
  } catch (e) {
    debugPrint('⚠️ Firebase.initializeApp failed: $e');
    // Firebase is required — but still call runApp() so we show an error UI
    // rather than a permanent white screen.
  }

  // ── Step 3a: Firestore web settings ──────────────────────────────────────
  // On web, the default IndexedDB multi-tab persistence can hit
  // "INTERNAL ASSERTION FAILED: Unexpected state" when tabs conflict
  // or the cache is corrupted. We configure a 40 MB cache and catch
  // any persistence init errors gracefully.
  if (kIsWeb) {
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 40 * 1024 * 1024, // 40 MB
      );
      debugPrint('✅ Firestore Web: persistence configured (40 MB)');
    } catch (e) {
      debugPrint('⚠️ Firestore Web persistence config failed: $e');
      // Fallback: disable persistence entirely to avoid assertion errors
      try {
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: false,
        );
        debugPrint('ℹ️ Firestore Web: persistence DISABLED (fallback)');
      } catch (_) {}
    }
  }

  // ── Step 3b: Web Auth persistence ──────────────────────────────────────
  // MUST be the very first call on FirebaseAuth.instance — before
  // getRedirectResult(), before Stripe, before anything that could
  // trigger an implicit auth state read.
  if (kIsWeb) {
    try {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      debugPrint('✅ Web: Auth LOCAL persistence set');
    } catch (e) {
      debugPrint('⚠️ Web Auth persistence failed: $e');
    }
  }

  // ── Step 3c: Handle returning redirect (Google/Apple on mobile Safari) ─
  // This MUST run immediately after setPersistence and BEFORE any other
  // async initialisation (Stripe, AudioService, etc.) that could delay it.
  // The OAuth credential is only available on the first getRedirectResult()
  // call after a redirect — if anything consumes it first, it's lost.
  if (kIsWeb) {
    await _handleWebRedirectResult();
  }

  // ── Step 3d: Crashlytics ─────────────────────────────────────────────────
  if (!kIsWeb) {
    try {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
      debugPrint('✅ Crashlytics ready');
    } catch (e) {
      debugPrint('⚠️ Crashlytics init failed (continuing): $e');
    }
  }

  // ── Step 4: App Check — DISABLED ───────────────────────────────────────
  debugPrint('ℹ️ App Check: DISABLED (social auth compatibility)');

  // ── Step 5: Stripe ────────────────────────────────────────────────────────
  try {
    await StripeService.init().timeout(
      const Duration(seconds: 10),
      onTimeout: () => debugPrint('⚠️ StripeService.init() timed out — skipping'),
    );
    debugPrint('✅ Stripe ready');
  } catch (e) {
    debugPrint('⚠️ Stripe init failed (payments unavailable until reload): $e');
  }

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  unawaited(AudioService.instance.init());

  Timer.periodic(
    const Duration(minutes: 5),
    (_) => CacheService.purgeExpired(),
  );

  Watchtower.init();

  FlutterError.onError = (FlutterErrorDetails details) {
    if (!kIsWeb) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    }
    Watchtower.instance.error(
      details.exception,
      screen: details.library,
      severity: LogSeverity.fatal,
    );
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    if (!kIsWeb) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
    }
    Watchtower.instance.error(error, stack: stack, severity: LogSeverity.warning);
    return true;
  };

  runApp(const ProviderScope(child: AnySkillApp()));
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
        // Listener wraps the entire app to capture the very first tap.
        // On iOS Safari, audio is blocked until the user has interacted with
        // the page. unlockAudioOnGesture() plays a silent clip inside this
        // gesture handler, which permanently unlocks the Web Audio Context
        // for the session — all subsequent plays work without any gesture.
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => AudioService.instance.unlockAudioOnGesture(),
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            debugShowCheckedModeBanner: false,
            title: 'AnySkill',
            // ── i18n: persisted locale (default: Hebrew RTL) ─────────────────
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: locale,
            // Auto-resolve RTL/LTR: GlobalMaterialLocalizations handles directionality
            // for Hebrew (RTL) and English/Spanish (LTR) automatically.
            theme:     AppTheme.light(context),
            darkTheme: AppTheme.dark(context),
            themeMode: ThemeMode.light, // switch to ThemeMode.system to follow OS
            home: const AuthWrapper(),
          ), // closes MaterialApp
        ); // closes Listener
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
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot>? _versionSub;
  SharedPreferences? _prefs;

  bool _updateNotified = false;
  bool _bannerVisible = false;
  bool _startupGrace  = true; // suppress banner for 3s after app start
  // The version string from Firestore that triggered the current banner.
  // Stored so we can persist "dismissed for this version" when user taps × or Update.
  String? _latestVersion;

  @override
  void initState() {
    super.initState();
    // Suppress update banner for 3 seconds after startup to avoid
    // interrupting auth redirects (Google/Apple sign-in on mobile web).
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _startupGrace = false);
    });
    _handleWebUpdates();
    _setupPushNotifications();

    // Load SharedPreferences FIRST, then start the auth listener.
    // This eliminates the race condition where the Firestore version
    // snapshot arrives before _prefs is assigned, causing the
    // "already dismissed" check to return null (= banner always shown).
    SharedPreferences.getInstance().then((p) {
      _prefs = p;
      _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null) {
          _startVersionListener();
          _saveAndRefreshToken(user.uid);
          PermissionService.recoverFromFirestore();
        } else {
          _versionSub?.cancel();
          _versionSub = null;
        }
      });
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
    // Do NOT reset _updateNotified here. Auth state changes can re-call this
    // method, and resetting the flag would re-trigger the banner for users who
    // already dismissed it in the same session.
    _versionSub = FirebaseFirestore.instance
        .collection('admin')
        .doc('settings')
        .snapshots()
        .listen((doc) {
          if (!doc.exists || !mounted || _updateNotified) return;
          if (_startupGrace) return; // don't flash banner during auth redirect

          // Never show update banner in debug/development builds.
          if (kDebugMode) return;

          final latest =
              (doc.data()?['latestVersion'] as String?) ?? currentAppVersion;

          // Only show the banner when the server version is strictly newer.
          if (!_isNewerVersion(latest, currentAppVersion)) return;

          // Check if the user has already dismissed THIS specific version.
          // SharedPreferences persists across reloads/restarts on both web and native.
          final dismissed = _prefs?.getString('banner_dismissed_v');
          if (dismissed == latest) return;

          _updateNotified = true;
          _latestVersion = latest;
          _showUpdateBanner();
        }, onError: (_) {}); // silently ignore permission-denied for non-admins
  }

  /// Returns true only if [candidate] is STRICTLY greater than [base].
  /// Compares "MAJOR.MINOR.PATCH" version strings segment by segment.
  /// Strips build number suffix ("+N") before comparison to avoid
  /// "8.9.3+1" being treated as newer than "8.9.3".
  bool _isNewerVersion(String candidate, String base) {
    // Strip "+buildNumber" suffix (e.g., "8.9.3+1" → "8.9.3")
    final cleanCandidate = candidate.split('+').first;
    final cleanBase = base.split('+').first;
    final c = cleanCandidate.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final b = cleanBase.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final len = c.length > b.length ? c.length : b.length;
    while (c.length < len) {
      c.add(0);
    }
    while (b.length < len) {
      b.add(0);
    }
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
            child: Builder(
              builder: (ctx) {
                final l10n = AppLocalizations.of(ctx);
                return Directionality(
                  textDirection:
                      l10n.isCurrentRtl == 'true' ? TextDirection.rtl : TextDirection.ltr,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.system_update_alt_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
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
                            await _prefs?.setString(
                              'banner_dismissed_v',
                              _latestVersion!,
                            );
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
                            horizontal: 14,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          l10n.updateNowButton,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      // ── Dismiss (×) ────────────────────────────────────────────
                      GestureDetector(
                        onTap: () async {
                          // Remember this version was dismissed so it won't resurface.
                          if (_latestVersion != null) {
                            await _prefs?.setString(
                              'banner_dismissed_v',
                              _latestVersion!,
                            );
                          }
                          if (!mounted) return;
                          setState(() => _bannerVisible = false);
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(right: 4, left: 8),
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withValues(alpha: 0.55),
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ), // Row
                ); // Directionality
              },
            ), // Builder
          ),
        ),
      ),
    );
  }

  // ── Web service-worker update bridge ─────────────────────────────────────
  //
  // Flow:
  //   1. app_init.js detects a new SW entering 'installed' state.
  //   2. It posts 'SKIP_WAITING' to activate the SW immediately.
  //   3. It writes sessionStorage['sw_update_pending'] = '1'.
  //   4. This method reads and clears that flag on app startup.
  //   5. If the flag is present, the glassmorphism update banner is shown.
  //      The user then taps "Update now" which calls pageReload(), loading
  //      the fresh assets the newly-active SW now serves.
  //
  // This path is independent of the Firestore version check in
  // _startVersionListener() — either can trigger the banner, _updateNotified
  // ensures only one banner per session.
  void _handleWebUpdates() {
    if (!kIsWeb) return;
    // sessionGet returns null on native (stub) — safe to call unconditionally.
    if (sessionGet('sw_update_pending') != '1') return;

    // Consume the flag immediately so a hard-refresh after updating doesn't
    // re-show the banner.
    sessionSet('sw_update_pending', '');

    // Defer to the first frame so the widget tree is fully mounted before
    // setState is called inside _showUpdateBanner.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_bannerVisible && !_updateNotified) {
        _updateNotified = true;
        _showUpdateBanner();
      }
    });
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
            (_) => _navigateFromMessage(initial),
          );
        }
        return;
      }

      if (storedNotif != PermissionService.granted) {
        // Never asked (or status unknown) — ask the OS exactly once.
        final settings = await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
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
                if (notification.body != null) Text(notification.body!),
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
                body: Center(child: _SplashLogo()),
              );
            }
            if (snapshot.hasData && snapshot.data != null) {
              return const OnboardingGate();
            }
            return const PhoneLoginScreen();
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
// Public so LoginScreen / OtpScreen can navigate here directly after login
// instead of relying on AuthWrapper's StreamBuilder race condition.
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key});

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  late final Future<({Map<String, dynamic> data, bool hasSeenPerms})> _future;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _future = _load(uid);
  }

  static Future<({Map<String, dynamic> data, bool hasSeenPerms})> _load(
    String uid,
  ) async {
    final results = await Future.wait([
      // Force server read to get fresh isAdmin flag (not stale cache)
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(
            const Duration(seconds: 8),
            // On timeout, fall back to cache — better than showing error
            onTimeout: () => FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .get(const GetOptions(source: Source.cache)),
          ),
      PermissionService.hasSeenPermissions(),
    ]);
    final snap = results[0] as DocumentSnapshot;
    final data = snap.data() as Map<String, dynamic>? ?? {};
    // ignore: avoid_print
    print('🔍 [OnboardingGate] uid=$uid, exists=${snap.exists}, '
        'isAdmin=${data['isAdmin']}, onboardingComplete=${data['onboardingComplete']}, '
        'isProvider=${data['isProvider']}, isPendingExpert=${data['isPendingExpert']}');
    final hasSeenPerms = results[1] as bool;
    return (data: data, hasSeenPerms: hasSeenPerms);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({Map<String, dynamic> data, bool hasSeenPerms})>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: _SplashLogo()),
          );
        }
        // On error (Firestore crash, timeout, no network):
        // If user is authenticated, let them into HomeScreen (safe: screens
        // handle missing data gracefully). If NOT authenticated, show login.
        if (snapshot.hasError) {
          debugPrint('_OnboardingGate error: ${snapshot.error}');
          if (FirebaseAuth.instance.currentUser != null) {
            return const HomeScreen();
          }
          return const PhoneLoginScreen();
        }
        final (:data, :hasSeenPerms) = snapshot.data!;

        // ── ADMIN PRIORITY: bypass ALL gates ──────────────────────────────
        // Admins go straight to HomeScreen regardless of onboarding state,
        // pending verification, or permission screens.
        if (data['isAdmin'] == true) {
          // ignore: avoid_print
          print('✅ [OnboardingGate] Admin detected — bypassing all gates');
          return const HomeScreen();
        }

        // Anyone pending admin approval lands on the waiting screen —
        // covers both new signups (isProvider=false, isPendingExpert=true)
        // and provider accounts not yet verified (isProvider=true, isVerified=false).
        final isProvider = data['isProvider'] == true;
        final isVerified = data['isVerified'] == true;
        final isPendingExpert = data['isPendingExpert'] == true;
        if ((isProvider && !isVerified) || isPendingExpert) {
          return const PendingVerificationScreen();
        }

        // New users who haven't completed onboarding.
        // Default FALSE for empty/missing data — ensures new social login
        // users don't skip onboarding when profile creation was delayed.
        // Existing users created before this field was added will have the
        // field missing, but they'll also have isProvider/isCustomer set,
        // so they'll have data['onboardingComplete'] == true from the
        // OnboardingScreen._finish() or ProviderRegistrationScreen._submit().
        final complete = data['onboardingComplete'] ?? data.isNotEmpty;
        if (!complete) return const OnboardingScreen();

        // Enforce mandatory phone — redirect back to onboarding if missing.
        // This catches legacy users who completed onboarding before phone
        // was mandatory.
        final phone = (data['phone'] as String? ?? '').trim();
        if (phone.isEmpty) {
          debugPrint('[OnboardingGate] Phone missing — redirecting to onboarding');
          return const OnboardingScreen();
        }

        // First launch after sign-up — ask for permissions once
        if (!hasSeenPerms) return const PermissionRequestScreen();

        return const HomeScreen();
      },
    );
  }
}

// ── Splash logo — fade-in logo shown during auth/onboarding loading ───────────
class _SplashLogo extends StatefulWidget {
  const _SplashLogo();

  @override
  State<_SplashLogo> createState() => _SplashLogoState();
}

class _SplashLogoState extends State<_SplashLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: Image.asset(
      'assets/images/NEW_LOGO1.png.png',
      height: 120,
      fit: BoxFit.contain,
    ),
  );
}
