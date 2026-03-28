// Web stub — replaces flutter_stripe on web builds.
//
// flutter_stripe v11 calls dart:io Platform._operatingSystem at static
// class initialisation, which throws on Flutter Web.  By conditionally
// importing this stub instead of flutter_stripe, the Stripe class and all
// its Platform-dependent code are tree-shaken out of the web bundle
// entirely.  All payment operations on web use Stripe Checkout redirects
// (CF-backed) which do not require the flutter_stripe SDK.
library;

// Minimal stubs so that stripe_service.dart compiles on web without
// referencing flutter_stripe types that would drag in dart:io.

// ignore_for_file: avoid_classes_with_only_static_members, constant_identifier_names

class Stripe {
  static String publishableKey = '';
  static String merchantIdentifier = '';
  static String urlScheme = '';
  static Stripe get instance => _inst;
  static final Stripe _inst = Stripe._();
  Stripe._();
  Future<void> applySettings() async {}
  Future<void> initPaymentSheet({required dynamic paymentSheetParameters}) async {}
  Future<void> presentPaymentSheet() async {}
}

class StripePlatform {
  static StripePlatform get instance => _inst;
  static final StripePlatform _inst = StripePlatform._();
  StripePlatform._();
}

class SetupPaymentSheetParameters {
  const SetupPaymentSheetParameters({
    String? paymentIntentClientSecret,
    String? setupIntentClientSecret,
    String? merchantDisplayName,
    dynamic style,
    dynamic appearance,
  });
}

class PaymentSheetAppearance {
  const PaymentSheetAppearance({dynamic colors});
}

class PaymentSheetAppearanceColors {
  const PaymentSheetAppearanceColors({dynamic primary});
}

class StripeException implements Exception {
  final StripeError error;
  const StripeException(this.error);
}

class StripeError {
  final FailureCode code;
  final String? localizedMessage;
  const StripeError({required this.code, this.localizedMessage});
}

enum FailureCode { Canceled, Failed, Timeout, Unknown }
