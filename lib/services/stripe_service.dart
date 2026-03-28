// Stripe service — platform-adaptive entry point.
//
// Callers import THIS file only. Never import the _web or _native variants
// directly so that tree-shaking works correctly.
//
// How the conditional export works:
//   • dart.library.io is TRUE  on iOS / Android  → stripe_service_native.dart
//   • dart.library.io is FALSE on Flutter Web      → stripe_service_web.dart
//
// stripe_service_native.dart is the ONLY file that imports flutter_stripe.
// On a web build it is never compiled, so Platform._operatingSystem is
// never reached and the yellow ⚠️ warning disappears completely.

// Default (web): stripe_service_web.dart
// Override (native — dart.library.io available): stripe_service_native.dart
export 'stripe_service_web.dart'
    if (dart.library.io) 'stripe_service_native.dart';
