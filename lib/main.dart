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
import 'services/offline_message_queue.dart';
import 'services/private_data_service.dart';
import 'services/auth_duplicate_guard.dart';
import 'services/view_mode_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'repositories/logger_repository.dart';
import 'models/app_log.dart';
import 'theme/app_theme.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/phone_login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/support/support_dashboard_screen.dart';
import 'constants.dart' show appVersion;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
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
    chatRoomId = message.data['chatRoomId'] as String?
              ?? message.data['roomId'] as String?;
    switch (type) {
      case 'chat':
        tabIndex = 2; // Messages tab
        break;
      case 'booking':
      case 'new_booking':
      case 'booking_confirmed':
      case 'job_status':
        tabIndex = 1; // Orders tab
        break;
      case 'job_request':
      case 'broadcast_urgent':
      case 'broadcast_claimed':
        tabIndex = 5; // Opportunities
        break;
      case 'support_ticket':
        tabIndex = 2; // Messages tab (support is pinned at top)
        break;
      case 'market_alert':
      case 'admin_payment_alert':
        tabIndex = 6; // Admin panel
        break;
      case 'request_declined':
        tabIndex = 0; // Home — customer sees it as a notification
        break;
      case 'anytask_claimed':
      case 'anytask_proof_submitted':
      case 'anytask_auto_released':
      case 'anytask_payment_released':
      case 'anytask_disputed':
      case 'anytask_cancelled':
      case 'anytask_expired':
      case 'anytask_sla_reminder':
      case 'anytask_sla_returned':
      case 'anytask_reminder_24h':
      case 'anytask_reminder_2h':
        tabIndex = 0; // Home tab — user navigates to AnyTasks from there
        break;
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
    // 5s cap so a stalled WebChannel can't freeze the splash (Law 15).
    final snap = await docRef.get().timeout(const Duration(seconds: 5));
    if (snap.exists) {
      // Backfill profileImage from Auth if Firestore field is empty.
      // Early accounts were created before profileImage was added to the schema.
      final data = snap.data() ?? {};
      final firestoreImg = data['profileImage'] as String? ?? '';
      final authImg = user.photoURL ?? '';
      if (firestoreImg.isEmpty && authImg.isNotEmpty) {
        unawaited(docRef.update({'profileImage': authImg}));
        // ignore: avoid_print
        print('🔧 [Profile] Backfilled profileImage from Auth photoURL for ${user.uid}');
      }
      return;
    }
    // PR-A Anti-Duplicate Guard — silent variant (no UI context here).
    // If the email is already used by a different uid, sign out and abort
    // the create. AuthWrapper will route the user back to login.
    final conflictUid = await AuthDuplicateGuard.findConflict(
      currentUid: user.uid,
      email: user.email ?? '',
    );
    if (conflictUid != null) {
      // ignore: avoid_print
      print('🚫 [Profile] Duplicate email blocked: existing uid=$conflictUid');
      try { await FirebaseAuth.instance.signOut(); } catch (_) {}
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
    // PR 2a: mirror contact fields into private/identity
    await PrivateDataService.writeContactData(
      user.uid,
      phone: user.phoneNumber ?? '',
      email: user.email ?? '',
    );
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


  // ── Steps 1+2: PackageInfo + Locale (parallel — saves ~100ms) ─────────────
  await Future.wait([
    // Step 1: PackageInfo
    PackageInfo.fromPlatform().then((info) {
      if (info.version.isNotEmpty) currentAppVersion = info.version;
      debugPrint('✅ PackageInfo: $currentAppVersion');
    }).catchError((e) { debugPrint('⚠️ PackageInfo failed: $e'); }),
    // Step 2: Locale
    LocaleProvider.init()
        .then((_) => debugPrint('✅ LocaleProvider ready'))
        .catchError((e) { debugPrint('⚠️ Locale failed: $e'); }),
  ]);

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

  // ── Step 3a: Firestore web — PERSISTENCE DISABLED ──────────────────────
  // v9.1.1 DECISION: IndexedDB persistence on web is PERMANENTLY DISABLED.
  //
  // History of persistence-related crashes:
  //   - v8.9.4: "INTERNAL ASSERTION FAILED: Unexpected state" on multi-tab
  //   - v9.0.0: Corrupted cache after nuclear purge caused blank screens
  //   - v9.1.0: Double Settings call → assertion crash froze admin panel
  //   - v9.1.1: clearPersistence() on partially-initialized instance → crash
  //
  // The cost of disabling persistence: Firestore re-fetches from server on
  // each page load (~200ms extra). This is acceptable because:
  //   1. The nuclear purge already forces fresh data on every version bump
  //   2. StreamBuilder listeners get real-time updates after initial fetch
  //   3. CacheService (in-memory TTL) handles short-lived caching
  //
  // This single Settings call is the ONLY Firestore configuration.
  // It runs BEFORE any Firestore read/write, and is NEVER called again.
  if (kIsWeb) {
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
        // CRITICAL: Do NOT set experimentalForceLongPolling: true.
        // Long-polling causes AsyncQueue deadlocks on Chrome when a
        // snapshot listener and a write hit the same document simultaneously.
        // The default (auto-detect) uses WebChannel/WebSockets which is stable.
        // experimentalAutoDetectLongPolling is true by default — we leave it.
      );
      debugPrint('✅ Firestore Web: persistence OFF, standard WebChannel');
    } catch (e) {
      debugPrint('⚠️ Firestore settings failed: $e — using SDK defaults');
    }

    // Version tracking (uses localStorage, not Firestore)
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_app_version', currentAppVersion);
    } catch (_) {}
  }

  // ── Step 3b: Web Auth persistence ──────────────────────────────────────
  // MUST be the very first call on FirebaseAuth.instance — before
  // getRedirectResult(), before anything that could trigger an implicit
  // auth state read.
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
  // async initialisation (AudioService, etc.) that could delay it.
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

  // ── Step 5: Payment provider init ──────────────────────────────────────
  // Stripe Connect was removed in v11.9.x pending Israeli payment provider
  // integration. Booking escrow runs on the legacy internal-credits ledger
  // (EscrowService.payQuote / processPaymentRelease CF). The new provider
  // SDK init will go here once selected.

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  unawaited(AudioService.instance.init());
  unawaited(OfflineMessageQueue.instance.init());

  Timer.periodic(
    const Duration(minutes: 5),
    (_) => CacheService.purgeExpired(),
  );

  Watchtower.init();

  // ── Step 8: Disable bfcache (web only) ────────────────────────────────
  // Prevents the browser from storing a frozen page snapshot that gets
  // restored when the user presses Back — which shows an ancient layout.
  if (kIsWeb) disableBfcache();

  // ── Error handlers (Crashlytics + Watchtower) — must be set BEFORE runApp ──
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

  // ── Step 7: Sentry — fire-and-forget, NEVER blocks app startup ────────
  // Previous version used `await SentryFlutter.init(appRunner: () => runApp())`
  // which caused Admin login to hang when the Sentry DSN was unreachable.
  // Now: runApp() fires immediately, Sentry initializes in the background.
  unawaited(SentryFlutter.init(
    (options) {
      options.dsn = 'https://f0336dd5546c11cf23d925ee7ed14784@o4511156845019136.ingest.us.sentry.io/4511156856029184';
      options.tracesSampleRate = 1.0;
      options.environment = kDebugMode ? 'development' : 'production';
      options.release = 'anyskill@$currentAppVersion';
    },
  ));

  // Prevent "Could not find a set of Noto fonts" warning on web.
  // When Google Fonts can't download Assistant, it falls back to NotoSansHebrew
  // which is bundled in assets/fonts/. This config ensures the fallback works.
  GoogleFonts.config.allowRuntimeFetching = true;

  runApp(ProviderScope(child: _ErrorBoundary(child: const AnySkillApp())));

  // Signal the JS watchdog that the Dart app has booted successfully.
  // If this doesn't fire within 7s, app_init.js forces a full reload.
  if (kIsWeb) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      sessionSet('app_ready', '1');
    });
  }
}

// ── Global error boundary ─────────────────────────────────────────────────────
// Catches uncaught errors in the widget tree (e.g. broken StreamBuilder,
// null-ref in build()) and shows a recovery screen instead of a red error page.
// The user can tap to reset to the login screen.
class _ErrorBoundary extends StatefulWidget {
  final Widget child;
  const _ErrorBoundary({required this.child});

  @override
  State<_ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<_ErrorBoundary> {
  bool _hasError = false;
  int _errorCount = 0;

  /// Only show the crash screen for truly fatal errors that break rendering.
  /// Network errors (Firestore 500, timeout), CSP blocks, and non-fatal
  /// FlutterErrors are logged but do NOT trigger the crash screen — individual
  /// screens handle those via try/catch and StreamBuilder error states.
  static bool _isFatalError(FlutterErrorDetails details) {
    final msg = details.toString().toLowerCase();
    // Non-fatal: network, Firestore, permission, CSP, timeout, assertion in
    // third-party code — these are recoverable and handled per-screen.
    const nonFatalPatterns = [
      'firestore',
      'firebase',
      'network',
      'timeout',
      'permission',
      'csp',
      'content security policy',
      'xmlhttprequest',
      'failed to load',
      'socket',
      'connection',
      'unexpected state',    // Firestore AsyncQueue — non-fatal
      'async',
      'stream',
    ];
    for (final p in nonFatalPatterns) {
      if (msg.contains(p)) return false;
    }
    // Fatal: only if the framework itself considers it fatal
    return details.silent != true;
  }

  @override
  void initState() {
    super.initState();
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      // Always forward to the original handler (Crashlytics / Sentry)
      original?.call(details);
      // Only show crash screen for genuinely fatal rendering errors
      if (mounted && !_hasError && _isFatalError(details)) {
        _errorCount++;
        // Allow up to 3 non-consecutive errors before showing crash screen.
        // This prevents a single transient build error from killing the app.
        if (_errorCount >= 3) {
          setState(() => _hasError = true);
        } else {
          debugPrint('[ErrorBoundary] Non-fatal error #$_errorCount suppressed');
        }
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 64, color: Color(0xFFF59E0B)),
                  const SizedBox(height: 16),
                  const Text('משהו השתבש',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('האפליקציה נתקלה בשגיאה. לחץ כדי להתחיל מחדש.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                    label: const Text('התחל מחדש', style: TextStyle(color: Colors.white)),
                    onPressed: () => setState(() {
                      _hasError = false;
                      _errorCount = 0;
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return widget.child;
  }
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
        // Audio unlock moved to HomeScreen (after login) instead of here.
        // The root Listener was intercepting touch events on iOS PWA standalone
        // mode — the audio unlock process stole focus from button taps,
        // making Google/Apple/Email buttons completely unresponsive.
        return MaterialApp(
            navigatorKey: rootNavigatorKey,
            debugShowCheckedModeBanner: false,
            navigatorObservers: [SentryNavigatorObserver()],
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
          ); // closes MaterialApp
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
  bool _authTimedOut  = false; // iOS supervisor: force past auth wait
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
    // iOS Connection Supervisor: if auth hasn't resolved in 3 seconds,
    // force past the waiting state so the user sees login or home screen
    // instead of an infinite splash logo.  Reduced from 5s — users were
    // still seeing the splash for too long on iPhone.
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_authTimedOut) setState(() => _authTimedOut = true);
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
          // Load per-uid view-mode (provider ↔ customer toggle).
          unawaited(ViewModeService.initForUid(user.uid));
          // ── Sentry: tag all future events with the user identity ───────
          Sentry.configureScope((scope) {
            scope.setUser(SentryUser(
              id: user.uid,
              email: user.email,
              username: user.displayName,
            ));
          });
        } else {
          _versionSub?.cancel();
          _versionSub = null;
          unawaited(ViewModeService.instance.reset());
          // Clear Sentry user on logout
          Sentry.configureScope((scope) => scope.setUser(null));
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
                          if (kIsWeb) await forceHardRefresh();
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

    // Defence-in-depth: if the running version already matches the latest
    // known version (i.e., the user just completed the update and reloaded),
    // do NOT show the banner again.  The Firestore version listener will
    // catch genuinely new versions later.
    final dismissed = _prefs?.getString('banner_dismissed_v');
    if (dismissed == currentAppVersion) return;

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

      // ── Always wire background-tap navigation (once) ─────────────────────
      // This must run regardless of permission status — tapping a notification
      // that the OS already displayed should navigate even if user later denied.
      FirebaseMessaging.onMessageOpenedApp.listen(_navigateFromMessage);
      final initialMessage0 = await messaging.getInitialMessage();
      if (initialMessage0 != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _navigateFromMessage(initialMessage0),
        );
      }

      // ── Step 1: Check stored permission answer ─────────────────────────────
      final storedNotif = await PermissionService.getNotificationStatus();

      if (storedNotif == PermissionService.denied) {
        // User already refused — background-tap navigation is wired above,
        // so we only skip token registration and foreground listener.
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

      // ── Step 2: Get / refresh FCM token (ALL platforms including web) ────
      // CRITICAL: Web PWA (especially iOS) needs the VAPID key to get a token.
      // Previous bug: `if (!kIsWeb)` skipped token fetch on web entirely,
      // so the fcmToken was never saved → push notifications never delivered.
      try {
        final token = kIsWeb
            ? await messaging.getToken(
                vapidKey: 'BMps6y9pYxVgpcL6BI6iieleDICi-coUHasv6KjzYzdawU',
              )
            : await messaging.getToken();
        if (token != null) {
          _saveTokenToDatabase(token);
          debugPrint('[FCM] Token saved (${kIsWeb ? "web" : "native"}): ${token.substring(0, 20)}...');
        } else {
          debugPrint('[FCM] Token is null — notifications will not work');
        }
      } catch (e) {
        debugPrint('[FCM] getToken failed: $e');
      }
      messaging.onTokenRefresh.listen(_saveTokenToDatabase);

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

      // Background-tap + cold-start navigation already wired above (once).
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
    // Force a rebuild so HomeScreen picks up the PendingNotification.
    // Without setState, a foreground tap on a notification wouldn't navigate
    // because HomeScreen's initState already ran.
    if (mounted) setState(() {});
  }

  /// Called on every confirmed login — fetches the current FCM token and writes
  /// it to the user's Firestore doc. Fixes the case where the token was not
  /// saved on first install because [currentUser] was null at call time.
  Future<void> _saveAndRefreshToken(String uid) async {
    try {
      // Web needs VAPID key; native uses default
      final token = kIsWeb
          ? await FirebaseMessaging.instance.getToken(
              vapidKey: 'BMps6y9pYxVgpcL6BI6iieleDICi-coUHasv6KjzYzdawU',
            )
          : await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fcmToken': token,
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('[FCM] Token refreshed for uid=$uid');
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
            // Show splash only while waiting AND the 3s supervisor hasn't fired.
            // On iOS, Firebase Auth can stall indefinitely — this ensures
            // the user always gets past the splash within 3 seconds.
            if (snapshot.connectionState == ConnectionState.waiting && !_authTimedOut) {
              return const Scaffold(
                backgroundColor: Colors.white,
                body: Center(child: _SplashLogo()),
              );
            }
            // Auth stream error (rare but possible on corrupted state):
            // show login screen instead of red error widget.
            if (snapshot.hasError) {
              debugPrint('[AuthWrapper] Auth stream error: ${snapshot.error}');
              return const PhoneLoginScreen();
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
  late Future<({Map<String, dynamic> data, bool hasSeenPerms})> _future;
  bool _gateTimedOut = false;
  bool _resolved = false; // true once FutureBuilder exits waiting state

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _future = _load(uid);

    // iOS Safari fix: if still loading after 3s, retry the fetch.
    // iOS Safari aggressively manages network connections — the initial
    // Firestore WebChannel can stall in a "connected but not receiving"
    // zombie state. A fresh fetch forces a new connection attempt.
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_resolved && !_gateTimedOut) {
        debugPrint('[OnboardingGate] 3s retry — still loading, retrying fetch');
        setState(() => _future = _load(uid));
      }
    });

    // Second retry at 6s with a completely fresh approach
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted && !_resolved && !_gateTimedOut) {
        debugPrint('[OnboardingGate] 6s retry — forcing fresh server fetch');
        setState(() => _future = _load(uid));
      }
    });

    // Hard ceiling at 8s — force to HomeScreen regardless.
    // Reduced from 10s: no user should stare at a spinner for 10 seconds.
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && !_gateTimedOut) setState(() => _gateTimedOut = true);
    });
  }

  /// Resilient user fetch — NEVER throws.
  /// Web (persistence OFF): server(2s) → default(2s).
  /// Native: cache → server(2s) → default(2s).
  /// Timeouts reduced from 3s to 2s — iOS Safari zombie connections must
  /// fail fast so the retry timers in initState can kick in.
  static Future<DocumentSnapshot> _resilientUserFetch(String uid) async {
    final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
    // Tier 1: cache (skip on web — persistence is OFF, cache is always empty)
    if (!kIsWeb) {
      try {
        final cached = await docRef.get(const GetOptions(source: Source.cache));
        if (cached.exists) {
          debugPrint('[OnboardingGate] Cache hit — instant load');
          return cached;
        }
      } catch (_) {}
    }
    // Tier 2: server with 2s timeout
    try {
      return await docRef
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
    // Tier 3: default get with 2s timeout
    try {
      return await docRef.get().timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('[OnboardingGate] All tiers failed: $e');
      // Last-resort fallback — MUST resolve within 3s so the splash never hangs.
      // Both fallback calls are timeout-wrapped; if everything fails we rethrow
      // a SocketException-like error the FutureBuilder can surface.
      try {
        return await docRef
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        return await docRef
            .get()
            .timeout(const Duration(seconds: 3));
      }
    }
  }

  static Future<({Map<String, dynamic> data, bool hasSeenPerms})> _load(
    String uid,
  ) async {
    try {
      final results = await Future.wait([
        _resilientUserFetch(uid),
        PermissionService.hasSeenPermissions(),
      ]).timeout(const Duration(seconds: 7));
      final snap = results[0] as DocumentSnapshot;
      final data = snap.data() as Map<String, dynamic>? ?? {};
      // ignore: avoid_print
      print('🔍 [OnboardingGate] uid=$uid, exists=${snap.exists}, '
          'isAdmin=${data['isAdmin']}, onboardingComplete=${data['onboardingComplete']}, '
          'isProvider=${data['isProvider']}, isVerified=${data['isVerified']}, '
          'isPendingExpert=${data['isPendingExpert']}, isCustomer=${data['isCustomer']}');
      final hasSeenPerms = results[1] as bool;

      // Cache the user's role so we can route correctly even when offline.
      // This prevents the "Choose Role" screen from appearing when Firestore
      // is slow to respond on subsequent app opens.
      if (data.isNotEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          if (data['isProvider'] == true) await prefs.setBool('cached_isProvider', true);
          if (data['isCustomer'] == true) await prefs.setBool('cached_isCustomer', true);
          if (data['onboardingComplete'] == true) await prefs.setBool('cached_onboardingComplete', true);
        } catch (_) {}
      }

      return (data: data, hasSeenPerms: hasSeenPerms);
    } catch (e) {
      debugPrint('[OnboardingGate] _load failed: $e — trying cached role');
      // Fallback: use cached role from SharedPreferences to avoid showing
      // OnboardingScreen to existing users when Firestore is unreachable.
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedProvider = prefs.getBool('cached_isProvider') ?? false;
        final cachedCustomer = prefs.getBool('cached_isCustomer') ?? false;
        final cachedComplete = prefs.getBool('cached_onboardingComplete') ?? false;
        if (cachedProvider || cachedCustomer || cachedComplete) {
          debugPrint('[OnboardingGate] Using cached role: provider=$cachedProvider customer=$cachedCustomer');
          return (
            data: <String, dynamic>{
              'isProvider': cachedProvider,
              'isCustomer': cachedCustomer,
              'onboardingComplete': true, // cached user = definitely completed onboarding
              'isVerified': true, // assume verified for cached users
            },
            hasSeenPerms: true,
          );
        }
      } catch (_) {}
      return (data: <String, dynamic>{}, hasSeenPerms: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Hard timeout: if the future hasn't resolved in 10s, go to HomeScreen.
    // v9.4.9: Was showing PhoneLoginScreen on timeout, but AuthWrapper still
    // detects the authenticated user → re-creates OnboardingGate → timeout →
    // login → auth fires → infinite loop. HomeScreen is safe because it uses
    // StreamBuilder (real-time, no one-shot fetch) and handles missing data.
    if (_gateTimedOut) {
      debugPrint('[OnboardingGate] Hard timeout — authenticated user, going to HomeScreen');
      return const HomeScreen();
    }

    return FutureBuilder<({Map<String, dynamic> data, bool hasSeenPerms})>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: _SplashLogo()),
          );
        }
        _resolved = true;
        // On error: go to HomeScreen (not login).
        // v9.4.9: The user IS authenticated (AuthWrapper checked).
        // Showing PhoneLoginScreen triggers a loop because AuthWrapper
        // immediately detects the user → re-creates OnboardingGate → error.
        // HomeScreen's StreamBuilder will show data when the server recovers.
        if (snapshot.hasError) {
          debugPrint('[OnboardingGate] FutureBuilder error: ${snapshot.error}');
          return const HomeScreen();
        }
        final (:data, :hasSeenPerms) = snapshot.data!;

        // ── EMPTY DATA GUARD ─────────────────────────────────────────────
        // If _load returned empty data (all Firestore tiers failed), the
        // user is authenticated but we have no profile info. Go to
        // HomeScreen — its StreamBuilder will load data when available.
        // NEVER show OnboardingScreen for empty data — that's the bug
        // that sent existing providers like Sigalit to "Choose Role".
        if (data.isEmpty) {
          debugPrint('[OnboardingGate] Empty data for authenticated user — going to HomeScreen');
          return const HomeScreen();
        }

        final isAdmin    = data['isAdmin'] == true;
        final role       = data['role'] as String? ?? '';
        final isProvider = data['isProvider'] == true;
        final isCustomer = data['isCustomer'] == true;
        final isVerified = data['isVerified'] == true;
        final isPendingExpert = data['isPendingExpert'] == true;

        // ── PRIORITY 1: ADMIN — bypass ALL gates ─────────────────────────
        if (isAdmin) {
          // ignore: avoid_print
          print('✅ [OnboardingGate] Admin detected — bypassing all gates');
          return const HomeScreen();
        }

        // ── PRIORITY 1b: SUPPORT AGENT — route to dedicated workspace ────
        // Support agents bypass the entire customer/provider flow and land
        // directly in the SupportDashboardScreen. They cannot access the
        // regular HomeScreen with their work account — that's by design.
        // To use AnySkill as a customer, agents sign in with a separate
        // account.
        if (role == 'support_agent') {
          // ignore: avoid_print
          print('✅ [OnboardingGate] Support agent detected — routing to SupportDashboardScreen');
          return const SupportDashboardScreen();
        }

        // ── PRIORITY 2: EXISTING USER — skip role selection ──────────────
        // If isProvider OR isCustomer is true, the user has already chosen
        // a role. NEVER show the "Choose Role" (OnboardingScreen) again.
        // This fixes the Sigalit bug: she has isProvider:true + isCustomer:true
        // and the old code sent her to onboarding when onboardingComplete was
        // missing or when data was partially loaded.
        final hasRole = isProvider || isCustomer;

        // ── PRIORITY 3: PENDING APPROVAL ─────────────────────────────────
        // isPendingExpert is set during registration BEFORE admin approval.
        // isProvider && !isVerified: only if isVerified is EXPLICITLY false.
        // Missing isVerified (null) on an existing provider = assume verified
        // (legacy accounts didn't have this field).
        if (isPendingExpert) {
          return const PendingVerificationScreen();
        }
        if (isProvider && data.containsKey('isVerified') && !isVerified) {
          return const PendingVerificationScreen();
        }

        // ── PRIORITY 4: ONBOARDING CHECK ─────────────────────────────────
        // Only show OnboardingScreen if the user has NO role assigned AND
        // onboardingComplete is not true. An existing user (hasRole = true)
        // NEVER sees the role selection screen, even if onboardingComplete
        // is missing or false.
        if (!hasRole) {
          final complete = data['onboardingComplete'] == true;
          if (!complete) return const OnboardingScreen();
        }

        // ── PRIORITY 5: MANDATORY PHONE ──────────────────────────────────
        // Legacy users who completed onboarding before phone was mandatory,
        // or social-login users who signed up via Google/Apple.
        // v12.5.0: respects `phonePromptSkippedAt` — 7-day cooldown.
        final phone = (data['phone'] as String? ?? '').trim();
        final phoneSkip = data['phonePromptSkippedAt'] as Timestamp?;
        final phoneRecentlySkipped = phoneSkip != null &&
            DateTime.now().difference(phoneSkip.toDate()).inDays < 7;
        if (phone.isEmpty && !phoneRecentlySkipped) {
          if (isProvider || isVerified) {
            debugPrint('[OnboardingGate] Provider/verified missing phone — '
                'showing phone-only screen');
            return _PhoneCollectionScreen(existingData: data);
          }
          if (hasRole) {
            debugPrint('[OnboardingGate] Customer missing phone — phone-only screen');
            return _PhoneCollectionScreen(existingData: data);
          }
          debugPrint('[OnboardingGate] New user missing phone — onboarding');
          return const OnboardingScreen();
        }

        // ── PRIORITY 5.5: EMAIL GAP (v12.5.0) ────────────────────────────
        // Phone-OTP users typically have no email. Required for invoices.
        // Shown only if phone IS set, email is empty, and the user hasn't
        // skipped within the last 7 days.
        final email = (data['email'] as String? ?? '').trim();
        final emailSkip = data['emailPromptSkippedAt'] as Timestamp?;
        final emailRecentlySkipped = emailSkip != null &&
            DateTime.now().difference(emailSkip.toDate()).inDays < 7;
        if (email.isEmpty && phone.isNotEmpty && hasRole
            && !emailRecentlySkipped) {
          debugPrint('[OnboardingGate] Phone user missing email — email-collection screen');
          return _EmailCollectionScreen(existingData: data);
        }

        // ── PRIORITY 6: PERMISSIONS ──────────────────────────────────────
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

// ── Phone-only collection screen for existing verified providers ─────────
// Shown when a legacy provider (isVerified/isProvider) is missing the
// mandatory phone field. Does NOT touch any server-only fields.
/// PR-D (v12.5.0): Post-login phone collection with SMS OTP verification
/// and link-with-credential. Triggered by OnboardingGate when a user
/// signed in via Google/Apple and lacks a phone number.
///
/// Flow:
///   1. User enters phone → "שלח קוד" → Firebase sends SMS
///   2. UI switches to OTP step → user enters 6 digits
///   3. On mobile: `PhoneAuthProvider.credential` → `user.linkWithCredential`
///      On web:    `user.linkWithPhoneNumber` → `ConfirmationResult.confirm`
///   4. On success: writes phone + phoneVerifiedAt to users/{uid} +
///      private/identity.
///
/// "Skip for now" writes `phonePromptSkippedAt` so OnboardingGate honors
/// a 7-day cooldown before re-prompting.
class _PhoneCollectionScreen extends StatefulWidget {
  final Map<String, dynamic> existingData;
  const _PhoneCollectionScreen({required this.existingData});

  @override
  State<_PhoneCollectionScreen> createState() => _PhoneCollectionScreenState();
}

class _PhoneCollectionScreenState extends State<_PhoneCollectionScreen> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _sending = false;
  bool _verifying = false;
  bool _codeSent = false;
  String? _verificationId;          // mobile path
  ConfirmationResult? _webConfirm;  // web path
  String _fullPhone = '';

  static const _indigo = Color(0xFF6366F1);

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  // ── Step 1: Send OTP ─────────────────────────────────────────────────────
  Future<void> _sendCode() async {
    final raw = _phoneCtrl.text.trim().replaceAll(RegExp(r'[^\d]'), '');
    if (raw.length < 7) {
      _snack('מספר לא תקין');
      return;
    }
    // Normalize: Israeli 05XXXXXXXX → +9725XXXXXXXX. Anything with a leading
    // '+' or already E.164 passes through.
    String e164 = raw;
    if (raw.startsWith('0')) {
      e164 = '+972${raw.substring(1)}';
    } else if (!_phoneCtrl.text.trim().startsWith('+')) {
      e164 = '+$raw';
    } else {
      e164 = _phoneCtrl.text.trim();
    }
    _fullPhone = e164;

    setState(() => _sending = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _snack('המשתמש אינו מחובר');
        return;
      }

      if (kIsWeb) {
        // Web: use linkWithPhoneNumber — returns ConfirmationResult.
        // Flutter firebase_auth handles invisible reCAPTCHA automatically.
        final conf = await user.linkWithPhoneNumber(e164);
        _webConfirm = conf;
        if (mounted) setState(() => _codeSent = true);
      } else {
        // Mobile: verifyPhoneNumber with callbacks. We store verificationId
        // and link via PhoneAuthProvider.credential in step 2.
        final completer = Completer<void>();
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: e164,
          timeout: const Duration(seconds: 60),
          verificationCompleted: (cred) async {
            // Android instant verification — link right away.
            try {
              await user.linkWithCredential(cred);
              await _persistAndExit(e164);
            } catch (e) {
              _handleLinkError(e);
            }
          },
          verificationFailed: (e) {
            if (!completer.isCompleted) completer.completeError(e);
          },
          codeSent: (verId, _) {
            _verificationId = verId;
            if (mounted) setState(() => _codeSent = true);
            if (!completer.isCompleted) completer.complete();
          },
          codeAutoRetrievalTimeout: (_) {},
        );
        await completer.future;
      }
    } on FirebaseAuthException catch (e) {
      _handleLinkError(e);
    } catch (e) {
      _snack('שגיאה: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Step 2: Verify OTP + Link ────────────────────────────────────────────
  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length < 4) {
      _snack('קוד לא תקין');
      return;
    }
    setState(() => _verifying = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _snack('המשתמש אינו מחובר');
        return;
      }

      if (kIsWeb) {
        if (_webConfirm == null) {
          _snack('לא נשלח קוד — נסה/י שוב');
          return;
        }
        await _webConfirm!.confirm(code);
      } else {
        if (_verificationId == null) {
          _snack('לא נשלח קוד — נסה/י שוב');
          return;
        }
        final cred = PhoneAuthProvider.credential(
          verificationId: _verificationId!,
          smsCode: code,
        );
        await user.linkWithCredential(cred);
      }
      await _persistAndExit(_fullPhone);
    } on FirebaseAuthException catch (e) {
      _handleLinkError(e);
    } catch (e) {
      _snack('שגיאה: $e');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _persistAndExit(String phone) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'phone': phone,
        'phoneVerifiedAt': FieldValue.serverTimestamp(),
      });
      await PrivateDataService.writeContactData(uid, phone: phone);
    } catch (e) {
      debugPrint('[PhoneCollection] Persist failed: $e');
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  Future<void> _skipForNow() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'phonePromptSkippedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  void _handleLinkError(Object e) {
    String msg = 'שגיאה לא ידועה';
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'credential-already-in-use':
        case 'provider-already-linked':
          msg = 'מספר זה כבר משויך לחשבון אחר. אנא השתמש במספר אחר.';
          break;
        case 'invalid-verification-code':
          msg = 'קוד שגוי — נסה/י שוב';
          break;
        case 'invalid-phone-number':
          msg = 'מספר לא תקין';
          break;
        case 'too-many-requests':
          msg = 'יותר מדי ניסיונות — נסה/י שוב בעוד כמה דקות';
          break;
        default:
          msg = 'שגיאת אימות: ${e.code}';
      }
    } else {
      msg = e.toString();
    }
    _snack(msg);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.existingData['name'] as String? ?? '';
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/NEW_LOGO1.png.png',
                height: 80,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 32),
              Text(
                name.isNotEmpty ? 'היי $name! 👋' : 'היי! 👋',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _codeSent
                    ? 'שלחנו קוד ל$_fullPhone\nהזן/י את 6 הספרות כדי לאמת'
                    : 'כדי להשלים את ההרשמה ולקבל חשבוניות,\nנצטרך לאמת את מספר הטלפון שלך',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              if (!_codeSent) _buildPhoneInput() else _buildCodeInput(),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: (_sending || _verifying)
                      ? null
                      : (_codeSent ? _verifyCode : _sendCode),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _indigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: (_sending || _verifying)
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white,
                          ),
                        )
                      : Text(
                          _codeSent ? 'אמת/י' : 'שלח קוד',
                          style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: (_sending || _verifying) ? null : _skipForNow,
                child: Text(
                  'מאוחר יותר',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneInput() => TextField(
        controller: _phoneCtrl,
        keyboardType: TextInputType.phone,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, letterSpacing: 1.5),
        decoration: InputDecoration(
          hintText: '05X-XXXXXXX',
          hintStyle: TextStyle(color: Colors.grey[400]),
          prefixIcon: const Icon(Icons.phone_outlined),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _indigo, width: 2),
          ),
        ),
      );

  Widget _buildCodeInput() => TextField(
        controller: _codeCtrl,
        keyboardType: TextInputType.number,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLength: 6,
        style: const TextStyle(fontSize: 24, letterSpacing: 8),
        decoration: InputDecoration(
          hintText: '• • • • • •',
          counterText: '',
          hintStyle: TextStyle(color: Colors.grey[400], letterSpacing: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _indigo, width: 2),
          ),
        ),
      );
}

/// PR-C (v12.5.0): Post-login email collection with 6-digit code.
/// Triggered by OnboardingGate when a phone-OTP user lacks an email.
///
/// Flow:
///   1. User enters email → "שלח קוד" → calls `sendEmailVerificationCode` CF
///      which writes the code to the `mail` collection (Trigger Email).
///   2. UI switches to code step.
///   3. User enters 6 digits → calls `verifyEmailCode` CF which writes
///      email + emailVerifiedAt to users/{uid} AND private/identity.
///
/// "מאוחר יותר" writes `emailPromptSkippedAt` so OnboardingGate honors a
/// 7-day cooldown before re-prompting.
class _EmailCollectionScreen extends StatefulWidget {
  final Map<String, dynamic> existingData;
  const _EmailCollectionScreen({required this.existingData});

  @override
  State<_EmailCollectionScreen> createState() => _EmailCollectionScreenState();
}

class _EmailCollectionScreenState extends State<_EmailCollectionScreen> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _sending = false;
  bool _verifying = false;
  bool _codeSent = false;
  String _sentEmail = '';

  static const _indigo = Color(0xFF6366F1);
  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (!_emailRe.hasMatch(email)) {
      _snack('כתובת מייל לא תקינה');
      return;
    }
    setState(() => _sending = true);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('sendEmailVerificationCode')
          .call({'email': email});
      _sentEmail = email;
      if (mounted) setState(() => _codeSent = true);
    } on FirebaseFunctionsException catch (e) {
      _snack(e.message ?? 'שגיאה: ${e.code}');
    } catch (e) {
      _snack('שגיאה: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      _snack('הזן/י את 6 הספרות');
      return;
    }
    setState(() => _verifying = true);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('verifyEmailCode')
          .call({'code': code});
      // Success — the CF wrote users/{uid}.email + emailVerifiedAt already.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('המייל אומת ✓'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } on FirebaseFunctionsException catch (e) {
      _snack(e.message ?? 'שגיאה: ${e.code}');
    } catch (e) {
      _snack('שגיאה: $e');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _skipForNow() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'emailPromptSkippedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.existingData['name'] as String? ?? '';
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/NEW_LOGO1.png.png',
                height: 80,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 32),
              Text(
                name.isNotEmpty ? 'היי $name! 👋' : 'היי! 👋',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _codeSent
                    ? 'שלחנו קוד ל-$_sentEmail\nבדוק/בדקי את תיבת הדואר והזן/י את 6 הספרות'
                    : 'כדי לקבל חשבוניות ולשלוח הודעות חשובות,\nנצטרך גם את כתובת המייל שלך',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              if (!_codeSent) _buildEmailInput() else _buildCodeInput(),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: (_sending || _verifying)
                      ? null
                      : (_codeSent ? _verifyCode : _sendCode),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _indigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: (_sending || _verifying)
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white,
                          ),
                        )
                      : Text(
                          _codeSent ? 'אמת/י' : 'שלח קוד',
                          style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: (_sending || _verifying) ? null : _skipForNow,
                child: Text(
                  'מאוחר יותר',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmailInput() => TextField(
        controller: _emailCtrl,
        keyboardType: TextInputType.emailAddress,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          hintText: 'name@example.com',
          hintStyle: TextStyle(color: Colors.grey[400]),
          prefixIcon: const Icon(Icons.email_outlined),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _indigo, width: 2),
          ),
        ),
      );

  Widget _buildCodeInput() => TextField(
        controller: _codeCtrl,
        keyboardType: TextInputType.number,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLength: 6,
        style: const TextStyle(fontSize: 24, letterSpacing: 8),
        decoration: InputDecoration(
          hintText: '• • • • • •',
          counterText: '',
          hintStyle: TextStyle(color: Colors.grey[400], letterSpacing: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _indigo, width: 2),
          ),
        ),
      );
}
