import 'package:cloud_firestore/cloud_firestore.dart';

/// Content Management Service
/// Manages application text overrides stored in Firestore.
/// Firestore schema: application_content/{locale} → {key: override_value, ...}
///
/// Only overrides are stored; absent keys fall back to static AppLocalizations strings.
class ContentManagementService {
  static const String _collection = 'application_content';
  static final _db = FirebaseFirestore.instance;

  // ─────────────────────────────────────────────────────────────────────────
  // Screen Groups: Maps screen/feature IDs to their l10n keys
  // Used by AdminDesignTab to organize the tree view.
  // ─────────────────────────────────────────────────────────────────────────

  static const Map<String, List<String>> screenGroups = {
    'ניווט': [
      'tabHome',
      'tabBookings',
      'tabChat',
      'tabWallet',
      'tabProfile',
    ],
    'כניסה': [
      'loginTitle',
      'loginSubtitle',
      'loginButton',
      'loginWelcomeBack',
      'loginForgotPassword',
      'loginSignupLink',
    ],
    'הרשמה': [
      'signupTitle',
      'signupSubtitle',
      'signupIAmProvider',
      'signupIAmCustomer',
      'signupCreateButton',
      'signupTermsCheckbox',
      'signupNameField',
      'signupEmailField',
      'signupPasswordField',
      'signupConfirmPasswordField',
      'signupPhoneField',
    ],
    'מסך הבית': [
      'onlineStatus',
      'onlineStatusOnline',
      'onlineStatusOffline',
      'greetingMorning',
      'greetingEvening',
      'greetingAfternoon',
      'quickRequest',
      'urgentJobBanner',
      'urgentJobUrgent',
      'yourRatingOnlineNow',
      'yourBalance',
      'seeMore',
    ],
    'חיפוש': [
      'searchPlaceholder',
      'searchSectionCategories',
      'searchUrgencyFilter',
      'searchUrgencyMorning',
      'searchUrgencyToday',
      'searchUrgencyThisWeek',
      'searchUrgencyFlexible',
      'searchNoResults',
      'searchFilterButton',
    ],
    'הזמנות': [
      'bookingsTitle',
      'bookingsUpcomingTitle',
      'bookingsCompleted',
      'bookingsCancelled',
      'jobStatusPaidEscrow',
      'jobStatusExpertCompleted',
      'jobStatusCompleted',
      'jobStatusCancelled',
      'cancelBookingTitle',
      'cancelBookingConfirm',
      'jobDetails',
    ],
    'צ\'אט': [
      'chatTitle',
      'chatPlaceholder',
      'chatNoChatSelected',
      'chatUnreadCount',
      'chatIsTyping',
      'chatFiles',
      'chatSendButton',
    ],
    'ארנק וכספים': [
      'financeTitle',
      'financeBalance',
      'financePendingBalance',
      'financeRecentTransactions',
      'withdrawTitle',
      'withdrawSubmitButton',
      'withdrawSuccessTitle',
      'withdrawFailureTitle',
      'withdrawMethodLabel',
      'withdrawAmountLabel',
      'transactionTypeReceived',
      'transactionTypeSent',
      'transactionTypeWithdrawal',
    ],
    'פרופיל': [
      'profileTitle',
      'editProfileTitle',
      'aboutMeTitle',
      'galleryTitle',
      'uploadPhoto',
      'changePhoto',
      'removePhoto',
      'saveBio',
      'saveProfile',
      'profileCategory',
      'profileRating',
      'profileReviewsCount',
      'profileHourlyRate',
    ],
    'פרופיל ספק': [
      'expertStatRating',
      'expertStatReviews',
      'expertSectionSchedule',
      'expertSectionBio',
      'expertSectionGallery',
      'expertBookingSummaryTitle',
      'expertAvailability',
      'expertResponseTime',
      'expertCertifications',
    ],
    'אקדמיה': [
      'academyTitle',
      'academyDescription',
      'academyGetStarted',
      'academyCourseCount',
      'courseTitle',
      'courseDescription',
      'courseDuration',
      'courseEnroll',
      'coursePlay',
      'courseComplete',
      'courseCompleteTitle',
      'courseCertification',
      'courseXpReward',
      'quizTitle',
      'quizPassThreshold',
      'quizPassSuccess',
      'quizPassFailed',
      'quizRetake',
    ],
    'XP ומשחוק': [
      'xpManagerTitle',
      'xpEventsSection',
      'xpLevelBronze',
      'xpLevelSilver',
      'xpLevelGold',
      'xpToNextLevel',
      'xpTotalPoints',
      'xpLeaderboard',
      'xpAchievements',
    ],
    'הצטרפות': [
      'onboardingWelcome',
      'onboardingStep',
      'onboardingStepComplete',
      'onboardingTaxTitle',
      'onboardingTaxId',
      'onboardingAgreements',
      'onboardingVerification',
      'onboardingStartProviding',
    ],
    'כלל היישום': [
      'appName',
      'appSlogan',
      'appVersion',
      'cancel',
      'confirm',
      'submit',
      'save',
      'close',
      'delete',
      'edit',
      'back',
      'next',
      'loading',
      'error',
      'errorUnknown',
      'success',
      'warning',
      'info',
      'noData',
      'retry',
      'dismiss',
    ],
  };

  // ─────────────────────────────────────────────────────────────────────────
  // Stream and Fetch Methods
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns a live stream of override strings for a given locale.
  /// Returns an empty map if the document doesn't exist.
  static Stream<Map<String, String>> streamOverrides(String locale) {
    return _db
        .collection(_collection)
        .doc(locale)
        .snapshots()
        .map((snap) {
          final data = snap.data();
          if (data == null) return <String, String>{};
          return data.map((k, v) => MapEntry(k, v.toString()));
        });
  }

  /// Fetches overrides once (non-streaming).
  static Future<Map<String, String>> fetchOverrides(String locale) async {
    final snap = await _db.collection(_collection).doc(locale).get();
    final data = snap.data();
    if (data == null) return <String, String>{};
    return data.map((k, v) => MapEntry(k, v.toString()));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Write Methods
  // ─────────────────────────────────────────────────────────────────────────

  /// Sets an override for a single key in a locale.
  /// Uses SetOptions(merge: true) to avoid overwriting other keys.
  static Future<void> setOverride(String locale, String key, String value) {
    return _db.collection(_collection).doc(locale).set(
      {key: value},
      SetOptions(merge: true),
    );
  }

  /// Deletes an override for a key (reverts to app default).
  static Future<void> resetOverride(String locale, String key) {
    return _db
        .collection(_collection)
        .doc(locale)
        .update({key: FieldValue.delete()});
  }

  /// Deletes all overrides for a locale by deleting the entire document.
  static Future<void> resetAll(String locale) {
    return _db.collection(_collection).doc(locale).delete();
  }

  /// Batch sets multiple overrides.
  static Future<void> setOverridesBatch(
    String locale,
    Map<String, String> overrides,
  ) {
    return _db.collection(_collection).doc(locale).set(
      overrides,
      SetOptions(merge: true),
    );
  }
}
