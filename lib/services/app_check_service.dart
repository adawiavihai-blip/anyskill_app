import 'package:firebase_app_check/firebase_app_check.dart';

/// Initialises Firebase App Check so that only genuine installs of this
/// app can call Firestore / Storage / Cloud Functions.
///
/// Platform behaviour:
///   • Web (localhost) — FIREBASE_APPCHECK_DEBUG_TOKEN is set in index.html
///     before Flutter loads, so the Firebase JS SDK bypasses reCAPTCHA and
///     uses the hard-coded debug token instead.  Register that UUID once at:
///       Firebase Console → App Check → anyskill_app (web) → Debug tokens
///   • Web (production) — ReCaptchaV3Provider runs normally on the deployed
///     domain (anyskill-6fdf3.web.app).
///   • Android / iOS   — AndroidDebugProvider / AppleDebugProvider send the
///     hard-coded debug token directly (register in the same Debug tokens UI).
///
/// To switch to production (mobile):
///   • Android → change androidProvider to AndroidPlayIntegrityProvider()
///   • iOS     → change appleProvider  to AppleDeviceCheckProvider()
///   • Then flip "Enforce" in Firebase Console → App Check.
class AppCheckService {
  AppCheckService._();

  // reCAPTCHA v3 site key — registered at console.firebase.google.com → App Check → Web.
  // Public value; safe to commit. Do NOT confuse with the secret key.
  static const _webRecaptchaSiteKey = '6LetZJYsAAAAAHW8tB-sALx_vYSC5i8SC7d5Xqoj';

  // Debug token registered in Firebase Console → App Check → Debug tokens.
  // Used by Android and Apple providers during development.
  // For web localhost the token lives in index.html (FIREBASE_APPCHECK_DEBUG_TOKEN).
  static const _debugToken = '9B00B4FB-D810-4092-9039-A8C6127E1A0D';

  static Future<void> init() async {
    await FirebaseAppCheck.instance.activate(
      providerWeb:     ReCaptchaV3Provider(_webRecaptchaSiteKey),
      providerAndroid: AndroidDebugProvider(debugToken: _debugToken),
      providerApple:   AppleDebugProvider(debugToken: _debugToken),
    );

    // Enable automatic token refresh so App Check tokens never silently expire.
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);

    // Log every token refresh so you can copy it into Firebase Console.
    FirebaseAppCheck.instance.onTokenChange.listen((token) {
      if (token != null) {
        // ignore: avoid_print
        print('🔐 App Check token refreshed — register in Firebase Console → App Check → Debug tokens:\n$token');
      }
    });

    // Trigger one eager token fetch and log the result so we can confirm
    // the debug token is being accepted by Firebase.
    try {
      final token = await FirebaseAppCheck.instance.getToken(true);
      if (token != null) {
        // ignore: avoid_print
        print('✅ App Check token OBTAINED — Firestore requests will pass:\n$token');
      } else {
        // ignore: avoid_print
        print('⚠️  App Check getToken() returned null — '
            'check that the debug token is registered in '
            'Firebase Console → App Check → anyskill_app (web) → Debug tokens');
      }
    } catch (e) {
      // ignore: avoid_print
      print('❌ App Check getToken() threw: $e\n'
          'On localhost this means FIREBASE_APPCHECK_DEBUG_TOKEN is not set '
          'or the token is not registered in Firebase Console.');
    }
  }
}
