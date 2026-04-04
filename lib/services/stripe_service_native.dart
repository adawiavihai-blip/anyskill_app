// NATIVE IMPLEMENTATION (iOS / Android) — uses flutter_stripe Payment Sheet.
//
// This file is selected by the conditional export in stripe_service.dart
// only when dart.library.io IS available (i.e. on iOS / Android).
// It is NEVER compiled into the web bundle, so Platform._operatingSystem
// is only called on platforms where dart:io is fully supported.

// ignore_for_file: use_build_context_synchronously
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color, ThemeMode;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_stripe/flutter_stripe.dart';
import 'stripe_service_base.dart';

export 'stripe_service_base.dart'; // callers get SavedCard + PayQuoteResult

class StripeService {
  StripeService._();

  static final _fn = FirebaseFunctions.instance;

  static const _publishableKey = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
    defaultValue: 'pk_test_REPLACE_WITH_YOUR_PUBLISHABLE_KEY',
  );

  // ───────────────────────────────────────────────────────────────────────────
  // init
  // ───────────────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    Stripe.publishableKey  = _publishableKey;
    Stripe.merchantIdentifier = 'merchant.com.anyskill';
    Stripe.urlScheme       = 'anyskill';
    await Stripe.instance.applySettings();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // addPaymentMethod
  // ───────────────────────────────────────────────────────────────────────────

  static Future<String?> addPaymentMethod() async {
    try {
      final result = await _fn.httpsCallable('createSetupIntent').call({});
      final clientSecret = result.data['clientSecret'] as String?;
      if (clientSecret == null || clientSecret.isEmpty) {
        return 'שגיאה: לא התקבל client_secret מהשרת.';
      }

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          setupIntentClientSecret: clientSecret,
          merchantDisplayName: 'AnySkill',
          style: ThemeMode.system,
          appearance: const PaymentSheetAppearance(
            colors: PaymentSheetAppearanceColors(
              primary: Color(0xFF6366F1),
            ),
          ),
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      return null; // success
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) return 'canceled';
      debugPrint('Stripe setup error: ${e.error.localizedMessage}');
      return e.error.localizedMessage ?? 'שגיאה בשמירת אמצעי התשלום.';
    } on FirebaseFunctionsException catch (e) {
      debugPrint('CF createSetupIntent error: ${e.code} — ${e.message}');
      return e.message ?? 'שגיאת שרת. נסה שוב.';
    } on PlatformException catch (e) {
      debugPrint('Stripe PlatformException: ${e.code} — ${e.message}');
      if (e.code == 'Canceled' ||
          (e.message?.toLowerCase().contains('cancel') ?? false)) {
        return 'canceled';
      }
      return e.message ?? 'שגיאה בשמירת אמצעי התשלום.';
    } catch (e) {
      debugPrint('addPaymentMethod unexpected: $e');
      return 'שגיאה בלתי צפויה. נסה שוב.';
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // payQuote
  // ───────────────────────────────────────────────────────────────────────────

  static Future<PayQuoteResult> payQuote({required String quoteId}) async {
    try {
      final result = await _fn
          .httpsCallable('createPaymentIntent')
          .call({'quoteId': quoteId});

      final clientSecret = result.data['clientSecret'] as String?;
      final jobId        = result.data['jobId']        as String?;

      if (clientSecret == null || clientSecret.isEmpty) {
        return PayQuoteResult.failure('שגיאה: לא התקבל client_secret מהשרת.');
      }

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'AnySkill',
          style: ThemeMode.system,
          appearance: const PaymentSheetAppearance(
            colors: PaymentSheetAppearanceColors(
              primary: Color(0xFF6366F1),
            ),
          ),
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      return PayQuoteResult.success(jobId ?? '');
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        return PayQuoteResult.failure('התשלום בוטל.');
      }
      debugPrint('Stripe error: ${e.error.localizedMessage}');
      return PayQuoteResult.failure(
          e.error.localizedMessage ?? 'שגיאת תשלום. נסה שוב.');
    } on FirebaseFunctionsException catch (e) {
      debugPrint('CF createPaymentIntent error: ${e.code} — ${e.message}');
      return PayQuoteResult.failure(e.message ?? 'שגיאת שרת. נסה שוב.');
    } catch (e) {
      debugPrint('payQuote unexpected: $e');
      return PayQuoteResult.failure('שגיאה בלתי צפויה. נסה שוב.');
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Shared CF-backed operations
  // ───────────────────────────────────────────────────────────────────────────

  static Future<String?> releaseEscrow(String jobId) async {
    try {
      await _fn.httpsCallable('releaseEscrow').call({'jobId': jobId});
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? 'שגיאה בשחרור התשלום.';
    } catch (_) {
      return 'שגיאה בלתי צפויה בשחרור תשלום.';
    }
  }

  static Future<String?> startProviderOnboarding() async {
    try {
      final result = await _fn.httpsCallable('onboardProvider').call({
        'returnUrl':  'https://anyskill-6fdf3.web.app/stripe-return',
        'refreshUrl': 'https://anyskill-6fdf3.web.app/stripe-refresh',
      });
      return result.data['url'] as String?;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('onboardProvider error: ${e.message}');
      return null;
    }
  }

  static Future<String?> requestRefund({
    required String jobId,
    double? amountShekel,
    String reason = '',
  }) async {
    try {
      await _fn.httpsCallable('processRefund').call({
        'jobId':  jobId,
        if (amountShekel != null) 'amountShekel': amountShekel,
        'reason': reason,
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? 'שגיאה בהגשת בקשת החזר.';
    } catch (_) {
      return 'שגיאה בלתי צפויה.';
    }
  }

  /// Detaches a saved payment method from the customer's Stripe account.
  /// Returns null on success, error string on failure.
  static Future<String?> removeCard(String paymentMethodId) async {
    try {
      await _fn.httpsCallable('detachPaymentMethod').call({
        'paymentMethodId': paymentMethodId,
      });
      return null;
    } catch (e) {
      debugPrint('removeCard error: $e');
      return 'שגיאה בהסרת הכרטיס';
    }
  }

  static Future<List<SavedCard>> listSavedCards() async {
    try {
      final result = await _fn.httpsCallable('listPaymentMethods').call({});
      final raw = (result.data['cards'] as List?) ?? [];
      return raw
          .whereType<Map>()
          .map((m) => SavedCard.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    } catch (e) {
      debugPrint('listSavedCards error: $e');
      return [];
    }
  }
}
