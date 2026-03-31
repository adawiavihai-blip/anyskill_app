import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;

/// Initialises Firebase App Check so that only genuine installs of this
/// app can call Firestore / Storage / Cloud Functions.
///
/// App Check does NOT interfere with blob: URLs — those are local browser
/// fetches that never reach Firebase servers. App Check only attaches tokens
/// to outbound Firebase SDK requests (Firestore, Storage, Functions).
class AppCheckService {
  AppCheckService._();

  static const _webRecaptchaSiteKey = '6LetZJYsAAAAAHW8tB-sALx_vYSC5i8SC7d5Xqoj';
  static const _debugToken = '9B00B4FB-D810-4092-9039-A8C6127E1A0D';

  static Future<void> init() async {
    try {
      final bool useDebug = kDebugMode;

      await FirebaseAppCheck.instance.activate(
        // Web: debug → null (JS SDK uses debug token from index.html);
        //       release → reCAPTCHA v3.
        providerWeb: useDebug
            ? null
            : ReCaptchaV3Provider(_webRecaptchaSiteKey),
        providerAndroid: useDebug
            ? AndroidDebugProvider(debugToken: _debugToken)
            : const AndroidPlayIntegrityProvider(),
        providerApple: useDebug
            ? AppleDebugProvider(debugToken: _debugToken)
            : const AppleDeviceCheckProvider(),
      );
      await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
      debugPrint('✅ App Check ready (web=$kIsWeb, debug=$useDebug)');
    } catch (e) {
      debugPrint('⚠️ App Check init failed (app will continue): $e');
    }
  }
}
