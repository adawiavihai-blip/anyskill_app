import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'stripe_service_base.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
export 'stripe_service_base.dart';

class StripeService {
  StripeService._();
  static final _fn = FirebaseFunctions.instance;

  static Future<void> init() async {
    debugPrint('ℹ️ Stripe: web mode — Custom Onboarding');
  }

  static Future<String?> addPaymentMethod() async {
    try {
      final result = await _fn
          .httpsCallable('createStripeSetupSession')
          .call({});
      final url = result.data['url'] as String?;
      if (url == null || url.isEmpty) return 'שגיאה: לא התקבל URL.';
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return 'web_redirect';
    } catch (e) {
      return 'שגיאה בלתי צפויה.';
    }
  }

  static Future<PayQuoteResult> payQuote({required String quoteId}) async {
    try {
      final result = await _fn.httpsCallable('createStripePaymentSession').call(
        {'quoteId': quoteId},
      );
      final url = result.data['url'] as String?;
      if (url == null || url.isEmpty)
        return PayQuoteResult.failure('שגיאה ב-URL');
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return PayQuoteResult.webRedirect();
    } catch (e) {
      return PayQuoteResult.failure('שגיאה בתשלום');
    }
  }

  static Future<String?> releaseEscrow(String jobId) async {
    try {
      await _fn.httpsCallable('releaseEscrow').call({'jobId': jobId});
      return null;
    } catch (e) {
      return 'שגיאה בשחרור תשלום';
    }
  }

  // --- הפונקציה המשודרגת למניעת תקיעה בטעינה ---
  static Future<String?> startProviderOnboarding({
    required String firstName,
    required String lastName,
    required int dobDay,
    required int dobMonth,
    required int dobYear,
    required String idNumber,
    required String bankName,
    required String bankNumber,
    required String branchNumber,
    required String accountNumber,
  }) async {
    try {
      final onboardingUrl = 'https://onboardprovider-cj73alnlua-uc.a.run.app';
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();

      // 1. יצירת חשבון Custom בסטריפ (במידה ולא קיים)
      final response = await http.post(
        Uri.parse(onboardingUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'returnUrl': 'https://anyskill-6fdf3.web.app/stripe-return',
          'refreshUrl': 'https://anyskill-6fdf3.web.app/stripe-refresh',
        }),
      );

      // בדיקה אם השרת החזיר URL ישירות ב-Step 1 (קורה לפעמים לפי ה-Network שצילמת)
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['url'] != null) return data['url'] as String;
      }

      // 2. עדכון פרטים עם שמות שדות שסטריפ והשרת מבינים
      final result = await _fn.httpsCallable('updateStripeAccount').call({
        'firstName': firstName,
        'lastName': lastName,
        'day': dobDay,
        'month': dobMonth,
        'year': dobYear,
        'idNumber': idNumber,
        'bank_name': bankName,
        // בישראל ה-Routing Number הוא חיבור של קוד בנק (2 ספרות) וסניף (3 ספרות)
        'routing_number': '$bankNumber$branchNumber',
        'account_number': accountNumber,
        'ipAddress': '127.0.0.1',
      });

      // בדיקה אם קיבלנו URL מה-Cloud Function
      if (result.data['url'] != null) return result.data['url'] as String;

      if (result.data['success'] == true) return "success";
      return result.data['error'] ?? "שגיאה בעדכון הפרטים";
    } catch (e) {
      debugPrint('Stripe Onboarding Error: $e');
      return "שגיאה בתהליך: $e";
    }
  }

  static Future<String?> requestRefund({
    required String jobId,
    double? amountShekel,
    String reason = '',
  }) async {
    try {
      await _fn.httpsCallable('processRefund').call({
        'jobId': jobId,
        if (amountShekel != null) 'amountShekel': amountShekel,
        'reason': reason,
      });
      return null;
    } catch (e) {
      return 'שגיאה בהחזר';
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
      return [];
    }
  }
}
