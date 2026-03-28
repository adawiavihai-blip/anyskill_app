import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart' show debugPrint;

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
    // App Check failure must NEVER crash the app.
    // If reCAPTCHA is misconfigured the app still loads; only "Enforced"
    // Firestore / CF rules will start rejecting requests, which is a
    // better outcome than a permanent white screen for all users.
    try {
      await FirebaseAppCheck.instance.activate(
        providerWeb:     ReCaptchaV3Provider(_webRecaptchaSiteKey),
        providerAndroid: AndroidDebugProvider(debugToken: _debugToken),
        providerApple:   AppleDebugProvider(debugToken: _debugToken),
      );
      await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
    } catch (e) {
      // Log but swallow — runApp() will still be called.
      debugPrint('⚠️ App Check init failed (app will continue): $e');
    }
    // NOTE: We intentionally do NOT call getToken() here.
    // The eager fetch was the direct cause of the white screen:
    // ReCaptchaV3Provider.getToken() throws [app-check/recaptcha-error]
    // if the domain is not registered in the reCAPTCHA Console, and that
    // exception was propagating up through main() before runApp() ran.
    // App Check obtains tokens lazily on the first Firestore / CF request.
  }
}
