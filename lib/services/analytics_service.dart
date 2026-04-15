import 'package:firebase_analytics/firebase_analytics.dart';

import '../repositories/logger_repository.dart';

/// Centralized analytics service — wraps Firebase Analytics + Watchtower.
///
/// Every major user action goes through here. This ensures:
///   1. Firebase Analytics captures the event (funnels, cohorts, retention)
///   2. Watchtower logs it to Firestore activity_log (admin live feed)
///
/// Usage:
///   AnalyticsService.logSignUp(method: 'google');
///   AnalyticsService.logBookingCreated(category: 'ניקיון', amount: 150);
class AnalyticsService {
  AnalyticsService._();

  static final _fa = FirebaseAnalytics.instance;

  // ── Auth events ───────────────────────────────────────────────────────

  static void logSignUpStart({required String method}) {
    _fa.logEvent(name: 'sign_up_start', parameters: {'method': method});
    Watchtower.instance.activity('sign_up_start', detail: method);
  }

  static void logSignUpComplete({required String method, required String role}) {
    _fa.logSignUp(signUpMethod: method);
    _fa.logEvent(name: 'sign_up_complete', parameters: {
      'method': method, 'role': role,
    });
    Watchtower.instance.activity('sign_up_complete',
        detail: '$method / $role');
  }

  static void logLogin({required String method}) {
    _fa.logLogin(loginMethod: method);
    Watchtower.instance.authEvent('login', detail: method);
  }

  static void logLoginFailed({required String method, required String error}) {
    _fa.logEvent(name: 'login_failed', parameters: {
      'method': method, 'error': error,
    });
    Watchtower.instance.authEvent('login_failed', detail: '$method: $error');
  }

  static void logLogout() {
    _fa.logEvent(name: 'logout');
    Watchtower.instance.authEvent('logout');
  }

  // ── Registration funnel ───────────────────────────────────────────────

  static void logFunnelStep(int step, {String? role}) {
    _fa.logEvent(name: 'reg_step_$step', parameters: {
      if (role != null) 'role': role,
    });
  }

  // ── Discovery & search ────────────────────────────────────────────────

  static void logSearch({required String query}) {
    _fa.logSearch(searchTerm: query);
  }

  static void logCategoryViewed({required String category}) {
    _fa.logEvent(name: 'category_viewed', parameters: {
      'category': category,
    });
  }

  static void logProviderViewed({
    required String providerId,
    required String category,
  }) {
    _fa.logEvent(name: 'provider_viewed', parameters: {
      'provider_id': providerId,
      'category': category,
    });
  }

  // ── Booking & payment funnel ──────────────────────────────────────────

  static void logQuoteSent({
    required double amount,
    required String category,
  }) {
    _fa.logEvent(name: 'quote_sent', parameters: {
      'amount': amount,
      'category': category,
    });
    Watchtower.instance.activity('quote_sent',
        extra: {'amount': amount, 'category': category});
  }

  static void logBookingCreated({
    required String jobId,
    required double amount,
    required String category,
  }) {
    _fa.logEvent(name: 'booking_created', parameters: {
      'value': amount,
      'currency': 'ILS',
      'category': category,
    });
    Watchtower.instance.activity('💳 הזמנה חדשה',
        detail: '₪$amount — $category',
        extra: {'jobId': jobId, 'amount': amount});
  }

  static void logPaymentCompleted({
    required String jobId,
    required double amount,
    required String method, // 'credits' (Stripe removed pending Israeli provider)
  }) {
    _fa.logPurchase(
      value: amount,
      currency: 'ILS',
      transactionId: jobId,
    );
    _fa.logEvent(name: 'payment_completed', parameters: {
      'value': amount,
      'method': method,
    });
    Watchtower.instance.activity('✅ תשלום הושלם',
        detail: '₪$amount ($method)',
        extra: {'jobId': jobId, 'amount': amount, 'method': method});
  }

  static void logPaymentFailed({
    required String error,
    required double amount,
  }) {
    _fa.logEvent(name: 'payment_failed', parameters: {
      'error': error,
      'amount': amount,
    });
    Watchtower.instance.activity('❌ תשלום נכשל',
        detail: '₪$amount — $error');
  }

  static void logJobCompleted({
    required String jobId,
    required double amount,
  }) {
    _fa.logEvent(name: 'job_completed', parameters: {
      'value': amount,
      'currency': 'ILS',
    });
    Watchtower.instance.activity('🏁 עבודה הושלמה',
        detail: '₪$amount',
        extra: {'jobId': jobId});
  }

  // ── Review ────────────────────────────────────────────────────────────

  static void logReviewSubmitted({
    required double rating,
    required bool isClientReview,
  }) {
    _fa.logEvent(name: 'review_submitted', parameters: {
      'rating': rating,
      'reviewer_type': isClientReview ? 'client' : 'provider',
    });
    Watchtower.instance.activity('⭐ ביקורת חדשה',
        detail: 'דירוג: $rating');
  }

  // ── Cancellation & disputes ───────────────────────────────────────────

  static void logCancellation({
    required String cancelledBy,
    required bool hasPenalty,
    required double amount,
  }) {
    _fa.logEvent(name: 'booking_cancelled', parameters: {
      'cancelled_by': cancelledBy,
      'has_penalty': hasPenalty.toString(),
      'amount': amount,
    });
    Watchtower.instance.activity('🚫 ביטול הזמנה',
        detail: '$cancelledBy — ₪$amount${hasPenalty ? " (קנס)" : ""}');
  }

  static void logDisputeOpened({required String jobId}) {
    _fa.logEvent(name: 'dispute_opened', parameters: {
      'job_id': jobId,
    });
  }

  // ── Provider lifecycle ────────────────────────────────────────────────

  static void logProviderRegistration({required String category}) {
    _fa.logEvent(name: 'provider_registration', parameters: {
      'category': category,
    });
    Watchtower.instance.activity('📋 בקשת הרשמת ספק',
        detail: category);
  }

  static void logProviderVerified({required String providerId}) {
    _fa.logEvent(name: 'provider_verified', parameters: {
      'provider_id': providerId,
    });
    Watchtower.instance.activity('✅ ספק אושר',
        detail: providerId);
  }

  static void logProviderRejected({required String providerId}) {
    _fa.logEvent(name: 'provider_rejected', parameters: {
      'provider_id': providerId,
    });
    Watchtower.instance.activity('❌ ספק נדחה',
        detail: providerId);
  }

  // ── Stories ────────────────────────────────────────────────────────────

  static void logStoryUploaded({required String category}) {
    _fa.logEvent(name: 'story_uploaded', parameters: {
      'category': category,
    });
  }

  static void logStoryViewed({required String storyOwnerId}) {
    _fa.logEvent(name: 'story_viewed', parameters: {
      'owner_id': storyOwnerId,
    });
  }

  // ── VIP / monetization ────────────────────────────────────────────────

  static void logVipPurchased() {
    _fa.logEvent(name: 'vip_purchased', parameters: {
      'value': 99,
      'currency': 'ILS',
    });
    Watchtower.instance.activity('👑 VIP הופעל', detail: '₪99');
  }

  // ── Screen tracking ───────────────────────────────────────────────────

  static void logScreenView({required String screenName}) {
    _fa.logScreenView(screenName: screenName);
  }

  // ── Custom / generic ──────────────────────────────────────────────────

  static void logCustomEvent(String name, {Map<String, Object>? params}) {
    _fa.logEvent(name: name, parameters: params);
  }
}
