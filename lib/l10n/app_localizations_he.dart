// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hebrew (`he`).
class AppLocalizationsHe extends AppLocalizations {
  AppLocalizationsHe([String locale = 'he']) : super(locale);

  @override
  String get appName => 'AnySkill';

  @override
  String get appSlogan => 'המקצוענים שלך, במרחק נגיעה';

  @override
  String get greetingMorning => 'בוקר טוב';

  @override
  String get greetingAfternoon => 'אחה\"צ טובות';

  @override
  String get greetingEvening => 'ערב טוב';

  @override
  String get greetingNight => 'לילה טוב';

  @override
  String get greetingSubMorning => 'מה תרצה לעשות היום?';

  @override
  String get greetingSubAfternoon => 'צריך עזרה עם משהו?';

  @override
  String get greetingSubEvening => 'עדיין מחפש שירות?';

  @override
  String get greetingSubNight => 'נתראה מחר!';

  @override
  String get tabHome => 'בית';

  @override
  String get tabBookings => 'הזמנות';

  @override
  String get tabChat => 'צ\'אט';

  @override
  String get tabWallet => 'ארנק';

  @override
  String get bookNow => 'הזמן עכשיו';

  @override
  String get bookingCompleted => 'ההזמנה הושלמה בהצלחה';

  @override
  String get close => 'סגור';

  @override
  String get retryButton => 'נסה שוב';

  @override
  String get saveChanges => 'שמור שינויים';

  @override
  String get saveSuccess => 'נשמר בהצלחה';

  @override
  String saveError(String error) {
    return 'שגיאה בשמירה: $error';
  }

  @override
  String get defaultUserName => 'משתמש';

  @override
  String get notLoggedIn => 'לא מחובר';

  @override
  String get linkCopied => 'הקישור הועתק';

  @override
  String get errorEmptyFields => 'יש למלא את כל השדות';

  @override
  String get errorGeneric => 'אירעה שגיאה. נסה שוב';

  @override
  String get errorInvalidEmail => 'כתובת אימייל לא תקינה';

  @override
  String get whatsappError => 'לא ניתן לפתוח WhatsApp';

  @override
  String get markAllReadTooltip => 'סמן הכל כנקרא';

  @override
  String get onlineStatus => 'זמין';

  @override
  String get offlineStatus => 'לא זמין';

  @override
  String get onlineToggleOn => 'אתה עכשיו זמין';

  @override
  String get onlineToggleOff => 'אתה עכשיו לא זמין';

  @override
  String get roleCustomer => 'לקוח';

  @override
  String get roleProvider => 'ספק שירות';

  @override
  String get loginAccountTitle => 'כניסה לחשבון';

  @override
  String get loginButton => 'התחבר';

  @override
  String get loginEmail => 'כתובת אימייל';

  @override
  String get loginForgotPassword => 'שכחת סיסמה?';

  @override
  String get loginNoAccount => 'אין לך חשבון? ';

  @override
  String get loginPassword => 'סיסמה';

  @override
  String get loginRememberMe => 'זכור אותי';

  @override
  String get loginSignUpFree => 'הירשם בחינם';

  @override
  String get loginStats10k => '10K+';

  @override
  String get loginStats50 => '50+';

  @override
  String get loginStats49 => '4.9★';

  @override
  String get loginWelcomeBack => 'ברוך שובך!';

  @override
  String get signupAccountCreated => 'החשבון נוצר בהצלחה!';

  @override
  String get signupEmailInUse => 'כתובת האימייל כבר בשימוש';

  @override
  String get signupGenericError => 'אירעה שגיאה בהרשמה';

  @override
  String get signupGoogleError => 'שגיאה בהתחברות עם Google';

  @override
  String get signupNetworkError => 'שגיאת רשת. בדוק את החיבור';

  @override
  String get signupNewCustomerBio => 'לקוח חדש ב-AnySkill';

  @override
  String get signupNewProviderBio => 'ספק שירות חדש ב-AnySkill';

  @override
  String get signupTosMustAgree => 'יש לאשר את תנאי השימוש';

  @override
  String get signupWeakPassword => 'הסיסמה חלשה מדי';

  @override
  String get forgotPasswordEmail => 'כתובת אימייל';

  @override
  String get forgotPasswordError => 'שגיאה בשליחת קישור איפוס';

  @override
  String get forgotPasswordSubmit => 'שלח קישור איפוס';

  @override
  String get forgotPasswordSubtitle => 'הזן את כתובת האימייל שלך ונשלח לך קישור לאיפוס הסיסמה';

  @override
  String get forgotPasswordSuccess => 'קישור איפוס נשלח לאימייל שלך';

  @override
  String get forgotPasswordTitle => 'שכחתי סיסמה';

  @override
  String authError(String code) {
    return 'שגיאת אימות: $code';
  }

  @override
  String get profileTitle => 'הפרופיל שלי';

  @override
  String get profileFieldName => 'שם מלא';

  @override
  String get profileFieldNameHint => 'הזן את שמך המלא';

  @override
  String get profileFieldRole => 'סוג משתמש';

  @override
  String get profileFieldCategoryMain => 'תחום עיסוק';

  @override
  String get profileFieldCategoryMainHint => 'בחר את תחום העיסוק שלך';

  @override
  String get profileFieldCategorySub => 'תת-קטגוריה';

  @override
  String get profileFieldCategorySubHint => 'בחר התמחות ספציפית';

  @override
  String get profileFieldPrice => 'מחיר לשעה (₪)';

  @override
  String get profileFieldPriceHint => 'הזן מחיר לשעה';

  @override
  String get profileFieldResponseTime => 'זמן תגובה (דקות)';

  @override
  String get profileFieldResponseTimeHint => 'זמן תגובה ממוצע';

  @override
  String get profileFieldTaxId => 'מספר עוסק מורשה / ח.פ.';

  @override
  String get profileFieldTaxIdHint => 'הזן מספר עוסק מורשה';

  @override
  String get profileFieldTaxIdHelp => 'מספר זה ישמש להפקת חשבוניות';

  @override
  String get editProfileAbout => 'קצת עליי';

  @override
  String get editProfileAboutHint => 'ספר ללקוחות על הניסיון שלך...';

  @override
  String get editProfileCancellationPolicy => 'מדיניות ביטול';

  @override
  String get editProfileCancellationHint => 'בחר מדיניות ביטול';

  @override
  String get editProfileGallery => 'גלריה';

  @override
  String get editProfileQuickTags => 'תגיות מהירות';

  @override
  String get editProfileTagsHint => 'הוסף תגיות לפרופיל שלך';

  @override
  String editProfileTagsSelected(int count) {
    return '$count נבחרו';
  }

  @override
  String get editCategoryTitle => 'ערוך קטגוריה';

  @override
  String get editCategoryNameLabel => 'שם הקטגוריה';

  @override
  String get editCategoryChangePic => 'שנה תמונה';

  @override
  String get shareProfileTitle => 'שתף פרופיל';

  @override
  String get shareProfileTooltip => 'שתף את הפרופיל שלך';

  @override
  String get shareProfileCopyLink => 'העתק קישור';

  @override
  String get shareProfileWhatsapp => 'שתף בוואטסאפ';

  @override
  String get statBalance => 'יתרה';

  @override
  String get searchHintExperts => 'חפש מקצוענים...';

  @override
  String get searchDefaultTitle => 'חיפוש';

  @override
  String get searchDefaultCity => 'ישראל';

  @override
  String get searchDefaultExpert => 'מקצוען';

  @override
  String get searchSectionCategories => 'קטגוריות';

  @override
  String searchSectionResultsFor(String query) {
    return 'תוצאות עבור \"$query\"';
  }

  @override
  String searchNoResultsFor(String query) {
    return 'אין תוצאות עבור \"$query\"';
  }

  @override
  String get searchNoCategoriesBody => 'לא נמצאו קטגוריות';

  @override
  String get searchPerHour => '₪/שעה';

  @override
  String get searchRecommendedBadge => 'מומלץ';

  @override
  String get searchChipHomeVisit => 'ביקור בית';

  @override
  String get searchChipWeekend => 'זמין בסופ\"ש';

  @override
  String get searchDatePickerHint => 'בחר תאריך';

  @override
  String get searchTourSearchTitle => 'חיפוש מקצוענים';

  @override
  String get searchTourSearchDesc => 'חפש לפי שם, שירות או קטגוריה';

  @override
  String get searchTourSuggestionsTitle => 'הצעות חכמות';

  @override
  String get searchTourSuggestionsDesc => 'הצעות מותאמות אישית על בסיס חיפושים קודמים';

  @override
  String get searchUrgencyMorning => 'בוקר';

  @override
  String get searchUrgencyAfternoon => 'צהריים';

  @override
  String get searchUrgencyEvening => 'ערב';

  @override
  String get catResultsSearchHint => 'חפש בתוך הקטגוריה...';

  @override
  String catResultsNoExperts(String category) {
    return 'אין מקצוענים בקטגוריה $category';
  }

  @override
  String get catResultsNoResults => 'אין תוצאות';

  @override
  String get catResultsNoResultsHint => 'נסה לשנות את החיפוש שלך';

  @override
  String get catResultsPerHour => '₪/שעה';

  @override
  String catResultsOrderCount(int count) {
    return '$count הזמנות';
  }

  @override
  String catResultsResponseTime(int minutes) {
    return 'תגובה תוך $minutes דק\'';
  }

  @override
  String get catResultsRecommended => 'מומלץ';

  @override
  String get catResultsTopRated => 'דירוג גבוה';

  @override
  String get catResultsUnder100 => 'עד ₪100';

  @override
  String get catResultsClearFilters => 'נקה מסננים';

  @override
  String get catResultsBeFirst => 'היה הראשון!';

  @override
  String get catResultsExpertDefault => 'מקצוען';

  @override
  String get catResultsLoadMore => 'טען עוד';

  @override
  String get catResultsAvailableSlots => 'משבצות פנויות';

  @override
  String get catResultsNoAvailability => 'אין זמינות';

  @override
  String get catResultsFullBooking => 'תפוס';

  @override
  String get catResultsWhenFree => 'מתי פנוי?';

  @override
  String get chatListTitle => 'הודעות';

  @override
  String get expertSectionAbout => 'אודות';

  @override
  String get expertSectionService => 'השירות';

  @override
  String get expertSectionSchedule => 'זמינות';

  @override
  String get expertBioPlaceholder => 'אין ביוגרפיה עדיין';

  @override
  String get expertBioReadMore => 'קרא עוד';

  @override
  String get expertBioShowLess => 'הצג פחות';

  @override
  String get expertNoReviews => 'אין ביקורות עדיין';

  @override
  String get expertDefaultReviewer => 'משתמש';

  @override
  String get expertProviderResponse => 'תגובת הספק';

  @override
  String get expertAddReply => 'הוסף תגובה';

  @override
  String get expertAddReplyTitle => 'הוסף תגובה לביקורת';

  @override
  String get expertReplyHint => 'כתוב תגובה...';

  @override
  String get expertPublishReply => 'פרסם תגובה';

  @override
  String get expertReplyError => 'שגיאה בפרסום תגובה';

  @override
  String get expertSelectDateTime => 'בחר תאריך ושעה';

  @override
  String get expertSelectTime => 'בחר שעה';

  @override
  String expertBookForTime(String time) {
    return 'הזמן ל-$time';
  }

  @override
  String expertStartingFrom(String price) {
    return 'החל מ-₪$price';
  }

  @override
  String get expertBookingSummaryTitle => 'סיכום הזמנה';

  @override
  String get expertSummaryRowService => 'שירות';

  @override
  String get expertSummaryRowDate => 'תאריך';

  @override
  String get expertSummaryRowTime => 'שעה';

  @override
  String get expertSummaryRowPrice => 'מחיר';

  @override
  String get expertSummaryRowIncluded => 'כולל';

  @override
  String get expertSummaryRowProtection => 'הגנת קונה';

  @override
  String get expertSummaryRowTotal => 'סה\"כ';

  @override
  String get expertConfirmPaymentButton => 'אשר ושלם';

  @override
  String get expertVerifiedBooking => 'הזמנה מאומתת';

  @override
  String get expertInsufficientBalance => 'אין מספיק יתרה';

  @override
  String get expertEscrowSuccess => 'התשלום אושר! הכסף נעול באסקרו';

  @override
  String expertTransactionTitle(String name) {
    return 'תשלום ל-$name';
  }

  @override
  String expertSystemMessage(String date, String time, String amount) {
    return 'הזמנה אושרה ל-$date בשעה $time. ₪$amount נעולים באסקרו.';
  }

  @override
  String expertCancellationNotice(String policy, String deadline, String penalty) {
    return 'מדיניות $policy: ביטול חינם עד $deadline. לאחר מכן $penalty% קנס.';
  }

  @override
  String expertCancellationNoDeadline(String policy, String description) {
    return 'מדיניות $policy: $description';
  }

  @override
  String get financeTitle => 'כספים';

  @override
  String get financeAvailableBalance => 'יתרה זמינה';

  @override
  String get financePending => 'בהמתנה';

  @override
  String get financeProcessing => 'בעיבוד';

  @override
  String get financeRecentActivity => 'פעילות אחרונה';

  @override
  String get financeNoTransactions => 'אין עסקאות';

  @override
  String get financeWithdrawButton => 'משוך כספים';

  @override
  String get financeMinWithdraw => 'מינימום למשיכה: ₪50';

  @override
  String get financeTrustBadge => 'כספך מוגן';

  @override
  String financeReceivedFrom(String name) {
    return 'התקבל מ-$name';
  }

  @override
  String financePaidTo(String name) {
    return 'שולם ל-$name';
  }

  @override
  String financeError(String error) {
    return 'שגיאה: $error';
  }

  @override
  String get disputeConfirmRefund => 'אישור החזר כספי';

  @override
  String get disputeConfirmRelease => 'אישור שחרור תשלום';

  @override
  String get disputeConfirmSplit => 'אישור חלוקה';

  @override
  String get disputePartyCustomer => 'הלקוח';

  @override
  String disputeRefundBody(String amount, String customerName) {
    return '₪$amount יוחזרו ל-$customerName';
  }

  @override
  String disputeReleaseBody(String netAmount, String expertName, String feePercent) {
    return '₪$netAmount ישוחררו ל-$expertName (עמלה $feePercent%)';
  }

  @override
  String disputeSplitBody(String halfAmount, String halfNet, String platformFee) {
    return 'חלוקה: ₪$halfAmount לכל צד. ספק מקבל ₪$halfNet, פלטפורמה ₪$platformFee';
  }

  @override
  String get disputeResolvedRefund => 'המחלוקת נפתרה — בוצע החזר כספי';

  @override
  String get disputeResolvedRelease => 'המחלוקת נפתרה — התשלום שוחרר';

  @override
  String get disputeResolvedSplit => 'המחלוקת נפתרה — הסכום חולק';

  @override
  String get disputeTypeAudio => 'הקלטה';

  @override
  String get disputeTypeImage => 'תמונה';

  @override
  String get disputeTypeLocation => 'מיקום';

  @override
  String get releasePaymentError => 'שגיאה בשחרור התשלום';

  @override
  String get oppTitle => 'הזדמנויות';

  @override
  String get oppAllCategories => 'כל הקטגוריות';

  @override
  String get oppEmptyAll => 'אין הזדמנויות כרגע';

  @override
  String get oppEmptyAllSubtitle => 'בדוק שוב מאוחר יותר';

  @override
  String get oppEmptyCategory => 'אין הזדמנויות בקטגוריה זו';

  @override
  String get oppEmptyCategorySubtitle => 'נסה קטגוריה אחרת';

  @override
  String get oppTakeOpportunity => 'תפוס הזדמנות';

  @override
  String get oppInterested => 'מעוניין';

  @override
  String get oppAlreadyInterested => 'כבר הבעת עניין';

  @override
  String get oppAlreadyExpressed => 'כבר הבעת עניין בבקשה זו';

  @override
  String get oppAlready3Interested => 'כבר יש 3 מתעניינים';

  @override
  String get oppInterestSuccess => 'עניינך נרשם בהצלחה!';

  @override
  String get oppRequestClosed3 => 'הבקשה נסגרה — 3 מתעניינים';

  @override
  String get oppRequestClosedBtn => 'הבקשה נסגרה';

  @override
  String get oppRequestUnavailable => 'הבקשה אינה זמינה יותר';

  @override
  String get oppDefaultClient => 'לקוח';

  @override
  String get oppHighDemand => 'ביקוש גבוה';

  @override
  String get oppQuickBid => 'הצעה מהירה';

  @override
  String oppQuickBidMessage(String clientName, String providerName) {
    return 'שלום $clientName, אני $providerName ואשמח לעזור!';
  }

  @override
  String get oppEstimatedEarnings => 'הכנסה משוערת';

  @override
  String get oppAfterFee => 'לאחר עמלה';

  @override
  String get oppWalletHint => 'הכנסות נכנסות לארנק שלך';

  @override
  String oppXpToNextLevel(int xpNeeded, String levelName) {
    return 'עוד $xpNeeded XP לרמת $levelName';
  }

  @override
  String get oppMaxLevel => 'רמה מקסימלית!';

  @override
  String get oppBoostEarned => 'בוסט פרופיל הושג!';

  @override
  String oppBoostProgress(int count) {
    return '$count/3 הזדמנויות לבוסט';
  }

  @override
  String oppProfileBoosted(String timeLabel) {
    return 'פרופיל מקודם! נותרו $timeLabel';
  }

  @override
  String oppError(String error) {
    return 'שגיאה: $error';
  }

  @override
  String get oppTimeJustNow => 'הרגע';

  @override
  String oppTimeMinAgo(int minutes) {
    return 'לפני $minutes דק\'';
  }

  @override
  String oppTimeHourAgo(int hours) {
    return 'לפני $hours שעות';
  }

  @override
  String oppTimeDayAgo(int days) {
    return 'לפני $days ימים';
  }

  @override
  String oppTimeHours(int hours) {
    return '$hours שעות';
  }

  @override
  String oppTimeMinutes(int minutes) {
    return '$minutes דקות';
  }

  @override
  String get oppUnderReviewTitle => 'הפרופיל שלך בבדיקה';

  @override
  String get oppUnderReviewSubtitle => 'צוות AnySkill בודק את הפרופיל שלך';

  @override
  String get oppUnderReviewBody => 'נעדכן אותך ברגע שהאימות יושלם';

  @override
  String get oppUnderReviewContact => 'צור קשר עם התמיכה';

  @override
  String get oppUnderReviewStep1 => 'פרופיל נשלח';

  @override
  String get oppUnderReviewStep2 => 'בבדיקה';

  @override
  String get oppUnderReviewStep3 => 'אישור סופי';

  @override
  String get requestsEmpty => 'אין בקשות';

  @override
  String get requestsEmptySubtitle => 'עדיין לא פורסמו בקשות';

  @override
  String get requestsChatNow => 'שלח הודעה';

  @override
  String get requestsClosed => 'סגור';

  @override
  String get requestsConfirmPay => 'אשר ושלם';

  @override
  String get requestsDefaultExpert => 'מקצוען';

  @override
  String get requestsEscrowTooltip => 'הכסף נשמר באסקרו עד להשלמת העבודה';

  @override
  String get requestsMatchLabel => 'התאמה';

  @override
  String get requestsTopMatch => 'התאמה מובילה';

  @override
  String get requestsVerifiedBadge => 'מאומת';

  @override
  String get requestsMoneyProtected => 'כספך מוגן';

  @override
  String get requestsWaiting => 'ממתין';

  @override
  String get requestsWaitingProviders => 'ממתין לספקים...';

  @override
  String get requestsJustNow => 'הרגע';

  @override
  String requestsMinutesAgo(int minutes) {
    return 'לפני $minutes דק\'';
  }

  @override
  String requestsHoursAgo(int hours) {
    return 'לפני $hours שעות';
  }

  @override
  String requestsDaysAgo(int days) {
    return 'לפני $days ימים';
  }

  @override
  String requestsInterested(int count) {
    return '$count מתעניינים';
  }

  @override
  String requestsViewInterested(int count) {
    return 'צפה ב-$count מתעניינים';
  }

  @override
  String requestsOrderCount(int count) {
    return '$count הזמנות';
  }

  @override
  String requestsHiredAgo(String label) {
    return 'נשכר $label';
  }

  @override
  String requestsPricePerHour(String price) {
    return '₪$price/שעה';
  }

  @override
  String get timeNow => 'עכשיו';

  @override
  String get timeOneHour => 'שעה';

  @override
  String timeMinutesAgo(int minutes) {
    return 'לפני $minutes דק\'';
  }

  @override
  String timeHoursAgo(int hours) {
    return 'לפני $hours שעות';
  }

  @override
  String get urgentBannerRequests => 'בקשות דחופות';

  @override
  String get urgentBannerPending => 'ממתינות';

  @override
  String get urgentBannerServiceNeeded => 'דרוש שירות';

  @override
  String get urgentBannerCustomerWaiting => 'לקוח ממתין';

  @override
  String get calendarTitle => 'לוח שנה';

  @override
  String get calendarRefresh => 'רענן';

  @override
  String get calendarNoEvents => 'אין אירועים';

  @override
  String get calendarStatusCompleted => 'הושלם';

  @override
  String get calendarStatusPending => 'ממתין';

  @override
  String get calendarStatusWaiting => 'בהמתנה';

  @override
  String get creditsLabel => 'קרדיטים';

  @override
  String creditsDiscountAvailable(int discount) {
    return 'הנחה של $discount% זמינה!';
  }

  @override
  String creditsToNextDiscount(int remaining) {
    return 'עוד $remaining קרדיטים להנחה הבאה';
  }

  @override
  String get serviceFullSession => 'שיעור מלא';

  @override
  String get serviceSingleLesson => 'שיעור בודד';

  @override
  String get serviceExtendedLesson => 'שיעור מורחב';

  @override
  String get validationNameRequired => 'שם הוא שדה חובה';

  @override
  String get validationNameLength => 'שם חייב להכיל לפחות 2 תווים';

  @override
  String get validationNameTooLong => 'שם ארוך מדי';

  @override
  String get validationNameForbidden => 'השם מכיל תווים אסורים';

  @override
  String get validationCategoryRequired => 'יש לבחור קטגוריה';

  @override
  String get validationRoleRequired => 'יש לבחור סוג משתמש';

  @override
  String get validationPriceInvalid => 'מחיר לא תקין';

  @override
  String get validationPricePositive => 'המחיר חייב להיות חיובי';

  @override
  String get validationAboutTooLong => 'התיאור ארוך מדי';

  @override
  String get validationAboutForbidden => 'התיאור מכיל תווים אסורים';

  @override
  String get validationFieldForbidden => 'השדה מכיל תווים אסורים';

  @override
  String get validationUrlHttps => 'הקישור חייב להתחיל ב-https://';

  @override
  String get vipSheetHeader => 'AnySkill VIP';

  @override
  String get vipPriceMonthly => '₪99/חודש';

  @override
  String get vipActivateButton => 'הפעל VIP';

  @override
  String get vipActivationSuccess => 'VIP הופעל בהצלחה!';

  @override
  String get vipInsufficientBalance => 'אין מספיק יתרה להפעלת VIP';

  @override
  String get vipInsufficientTooltip => 'טען את הארנק שלך כדי להפעיל VIP';

  @override
  String get vipBenefit1 => 'קידום בתוצאות חיפוש';

  @override
  String get vipBenefit2 => 'תג VIP בפרופיל';

  @override
  String get vipBenefit3 => 'עדיפות בהזדמנויות';

  @override
  String get vipBenefit4 => 'תמיכה מועדפת';

  @override
  String withdrawMinBalance(int amount) {
    return 'הסכום המינימלי למשיכה הוא $amount ₪';
  }

  @override
  String get withdrawAvailableBalance => 'יתרה זמינה למשיכה';

  @override
  String get withdrawBankSection => 'פרטי בנק';

  @override
  String get withdrawBankName => 'שם הבנק';

  @override
  String get withdrawBankBranch => 'סניף';

  @override
  String get withdrawBankAccount => 'מספר חשבון';

  @override
  String get withdrawBankRequired => 'יש להזין שם בנק';

  @override
  String get withdrawBranchRequired => 'יש להזין סניף';

  @override
  String get withdrawAccountMinDigits => 'מספר חשבון חייב להכיל לפחות 5 ספרות';

  @override
  String get withdrawBankEncryptedNotice => 'הפרטים מוצפנים ומאובטחים';

  @override
  String get withdrawEncryptedNotice => 'המידע מוצפן ומאובטח';

  @override
  String get withdrawBankTransferPending => 'העברה בנקאית בטיפול';

  @override
  String get withdrawCertSection => 'אישורים';

  @override
  String get withdrawCertHint => 'העלה תעודת עוסק מורשה/פטור';

  @override
  String get withdrawCertUploadBtn => 'העלה אישור';

  @override
  String get withdrawCertReplace => 'החלף אישור';

  @override
  String get withdrawDeclarationSection => 'הצהרה';

  @override
  String get withdrawDeclarationText => 'אני מצהיר/ה על אחריותי הבלעדית לדיווח מס כחוק';

  @override
  String get withdrawDeclarationSuffix => '(סעיף 6 בתקנון)';

  @override
  String get withdrawTaxStatusTitle => 'סוג עוסק';

  @override
  String get withdrawTaxStatusSubtitle => 'בחר את סוג העוסק שלך';

  @override
  String get withdrawTaxIndividual => 'עוסק פטור';

  @override
  String get withdrawTaxIndividualSub => 'פטור מגביית מע\"מ';

  @override
  String get withdrawTaxIndividualBadge => 'פטור';

  @override
  String get withdrawTaxBusiness => 'עוסק מורשה';

  @override
  String get withdrawTaxBusinessSub => 'מחויב בגביית מע\"מ';

  @override
  String get withdrawIndividualTitle => 'פרטי עוסק פטור';

  @override
  String get withdrawIndividualDesc => 'הזן את פרטי העוסק הפטור שלך';

  @override
  String get withdrawIndividualFormTitle => 'טופס עוסק פטור';

  @override
  String get withdrawBusinessFormTitle => 'טופס עוסק מורשה';

  @override
  String get withdrawNoCertError => 'יש להעלות אישור עוסק';

  @override
  String get withdrawNoDeclarationError => 'יש לאשר את ההצהרה';

  @override
  String get withdrawSelectBankError => 'יש לבחור בנק';

  @override
  String withdrawSubmitButton(String amount) {
    return 'משוך $amount';
  }

  @override
  String get withdrawSubmitError => 'שגיאה בשליחת הבקשה';

  @override
  String get withdrawSuccessTitle => 'הבקשה נשלחה!';

  @override
  String withdrawSuccessSubtitle(String amount) {
    return 'בקשת המשיכה על סך $amount נשלחה בהצלחה';
  }

  @override
  String get withdrawSuccessNotice => 'העברה בנקאית תתבצע תוך 3-5 ימי עסקים';

  @override
  String get withdrawTimeline1Title => 'בקשה נשלחה';

  @override
  String get withdrawTimeline1Sub => 'הבקשה התקבלה במערכת';

  @override
  String get withdrawTimeline2Title => 'בטיפול';

  @override
  String get withdrawTimeline2Sub => 'הצוות מעבד את הבקשה';

  @override
  String get withdrawTimeline3Title => 'הושלם';

  @override
  String get withdrawTimeline3Sub => 'הכסף הועבר לחשבונך';

  @override
  String get pendingCatsApproved => 'הקטגוריה אושרה';

  @override
  String get pendingCatsRejected => 'הקטגוריה נדחתה';

  @override
  String get helpCenterTitle => 'מרכז עזרה';

  @override
  String get helpCenterTooltip => 'עזרה';

  @override
  String get helpCenterCustomerWelcome => 'ברוך הבא למרכז העזרה';

  @override
  String get helpCenterCustomerFaq => 'שאלות נפוצות ללקוחות';

  @override
  String get helpCenterCustomerSupport => 'תמיכת לקוחות';

  @override
  String get helpCenterProviderWelcome => 'ברוך הבא למרכז העזרה לספקים';

  @override
  String get helpCenterProviderFaq => 'שאלות נפוצות לספקים';

  @override
  String get helpCenterProviderSupport => 'תמיכת ספקים';

  @override
  String get languageTitle => 'שפה';

  @override
  String get languageSectionLabel => 'בחר שפה';

  @override
  String get languageHe => 'עברית';

  @override
  String get languageEn => 'English';

  @override
  String get languageEs => 'Español';

  @override
  String get languageAr => 'العربية';

  @override
  String get systemWalletEnterNumber => 'הזן מספר תקין';

  @override
  String get updateBannerText => 'גרסה חדשה זמינה';

  @override
  String get updateNowButton => 'עדכן עכשיו';

  @override
  String get xpLevelBronze => 'טירון';

  @override
  String get xpLevelSilver => 'מקצוען';

  @override
  String get xpLevelGold => 'זהב';

  @override
  String get bizAiTitle => 'בינה עסקית';

  @override
  String get bizAiSubtitle => 'ניתוח וחיזוי מבוסס AI';

  @override
  String get bizAiLoading => 'טוען נתונים...';

  @override
  String get bizAiRefreshData => 'רענן נתונים';

  @override
  String get bizAiNoData => 'אין נתונים זמינים';

  @override
  String bizAiError(String error) {
    return 'שגיאה: $error';
  }

  @override
  String get bizAiSectionFinancial => 'כספים';

  @override
  String get bizAiSectionMarket => 'שוק';

  @override
  String get bizAiSectionAlerts => 'התראות';

  @override
  String get bizAiSectionAiOps => 'פעולות AI';

  @override
  String get bizAiDailyCommission => 'עמלה יומית';

  @override
  String get bizAiWeeklyProjection => 'תחזית שבועית';

  @override
  String get bizAiWeeklyForecast => 'תחזית שבועית';

  @override
  String get bizAiExpectedRevenue => 'הכנסה צפויה';

  @override
  String get bizAiForecastBadge => 'תחזית';

  @override
  String get bizAiActualToDate => 'בפועל עד כה';

  @override
  String get bizAiAccuracy => 'דיוק';

  @override
  String get bizAiModelAccuracy => 'דיוק המודל';

  @override
  String get bizAiModelAccuracyDetail => 'דיוק חיזוי ההכנסות';

  @override
  String get bizAiNoChartData => 'אין נתונים לגרף';

  @override
  String get bizAiNoOrderData => 'אין נתוני הזמנות';

  @override
  String get bizAiSevenDays => '7 ימים';

  @override
  String get bizAiLast7Days => '7 ימים אחרונים';

  @override
  String get bizAiExecSummary => 'סיכום מנהלים';

  @override
  String get bizAiActivityToday => 'פעילות היום';

  @override
  String get bizAiApprovalQueue => 'תור אישורים';

  @override
  String bizAiPending(int count) {
    return '$count ממתינים';
  }

  @override
  String get bizAiPendingLabel => 'ממתינים';

  @override
  String get bizAiApproved => 'מאושר';

  @override
  String get bizAiRejected => 'נדחה';

  @override
  String get bizAiApprovedTotal => 'סה\"כ אושרו';

  @override
  String get bizAiTapToReview => 'לחץ לבדיקה';

  @override
  String get bizAiCategoriesApproved => 'קטגוריות שאושרו';

  @override
  String get bizAiNewCategories => 'קטגוריות חדשות';

  @override
  String get bizAiMarketOpportunities => 'הזדמנויות שוק';

  @override
  String get bizAiMarketOppsCard => 'הזדמנויות שוק';

  @override
  String get bizAiHighValueCategories => 'קטגוריות בעלות ערך גבוה';

  @override
  String get bizAiHighValueHint => 'קטגוריות עם פוטנציאל הכנסה גבוה';

  @override
  String bizAiProviders(int count) {
    return '$count ספקים';
  }

  @override
  String get bizAiPopularSearches => 'חיפושים פופולריים';

  @override
  String get bizAiNoSearchData => 'אין נתוני חיפוש';

  @override
  String get bizAiNichesNoProviders => 'נישות ללא ספקים';

  @override
  String get bizAiNoOpportunities => 'אין הזדמנויות כרגע';

  @override
  String bizAiRecruitForQuery(String query) {
    return 'גייס ספקים עבור \"$query\"';
  }

  @override
  String get bizAiZeroResultsHint => 'חיפושים ללא תוצאות — הזדמנות לגיוס';

  @override
  String bizAiSearches(int count) {
    return 'חיפושים: $count+';
  }

  @override
  String bizAiSearchCount(int count) {
    return '$count חיפושים';
  }

  @override
  String get bizAiAlertHistory => 'היסטוריית התראות';

  @override
  String get bizAiAlertThreshold => 'סף התראה';

  @override
  String get bizAiAlertThresholdHint => 'מספר חיפושים מינימלי להתראה';

  @override
  String get bizAiSaveThreshold => 'שמור סף';

  @override
  String get bizAiReset => 'אפס';

  @override
  String get bizAiNoAlerts => 'אין התראות';

  @override
  String bizAiAlertCount(int count) {
    return '$count התראות';
  }

  @override
  String bizAiMinutesAgo(int minutes) {
    return 'לפני $minutes דק\'';
  }

  @override
  String bizAiHoursAgo(int hours) {
    return 'לפני $hours שעות';
  }

  @override
  String bizAiDaysAgo(int days) {
    return 'לפני $days ימים';
  }

  @override
  String get tabProfile => 'פרופיל';

  @override
  String get searchPlaceholder => 'חפש מקצוען, שירות...';

  @override
  String get searchTitle => 'חיפוש';

  @override
  String get discoverCategories => 'גלה קטגוריות';

  @override
  String get confirm => 'אישור';

  @override
  String get cancel => 'ביטול';

  @override
  String get save => 'שמור';

  @override
  String get submit => 'שלח';

  @override
  String get next => 'הבא';

  @override
  String get back => 'חזור';

  @override
  String get delete => 'מחק';

  @override
  String get currencySymbol => '₪';

  @override
  String get statusPaidEscrow => 'ממתין לאישור';

  @override
  String get statusExpertCompleted => 'הושלם — ממתין לאישורך';

  @override
  String get statusCompleted => 'הושלם';

  @override
  String get statusCancelled => 'בוטל';

  @override
  String get statusDispute => 'במחלוקת';

  @override
  String get statusPendingPayment => 'ממתין לתשלום';

  @override
  String get profileCustomer => 'לקוח';

  @override
  String get profileProvider => 'ספק שירות';

  @override
  String get profileOrders => 'הזמנות';

  @override
  String get profileRating => 'דירוג';

  @override
  String get profileReviews => 'ביקורות';

  @override
  String get reviewsPlaceholder => 'ספר לנו על החוויה שלך...';

  @override
  String get reviewSubmit => 'שלח ביקורת';

  @override
  String get ratingLabel => 'דרג את השירות';

  @override
  String get walletBalance => 'יתרה';

  @override
  String get openChat => 'פתח צ\'אט';

  @override
  String get quickRequest => 'בקשה מהירה';

  @override
  String get trendingBadge => 'טרנדי';

  @override
  String get isCurrentRtl => 'true';

  @override
  String get taxDeclarationText => 'אני מצהיר/ה על אחריותי הבלעדית לדיווח מס כחוק. ידוע לי כי AnySkill אינה מעסיקתי ואינה מנכה מס במקור.';

  @override
  String get loginTitle => 'כניסה';

  @override
  String get loginSubtitle => 'התחבר לחשבון שלך';

  @override
  String get errorGenericLogin => 'שגיאה בהתחברות';

  @override
  String get subCategoryPrompt => 'בחר תת-קטגוריה';

  @override
  String get emptyActivityTitle => 'אין פעילות';

  @override
  String get emptyActivityCta => 'התחל עכשיו';

  @override
  String get errorNetworkTitle => 'שגיאת רשת';

  @override
  String get errorNetworkBody => 'בדוק את חיבור האינטרנט שלך';

  @override
  String get errorProfileLoad => 'שגיאה בטעינת הפרופיל';

  @override
  String get forgotPassword => 'שכחת סיסמה?';

  @override
  String get signupButton => 'הירשם';

  @override
  String get tosAgree => 'אני מסכים/ה לתנאי השימוש';

  @override
  String get tosTitle => 'תנאי שימוש';

  @override
  String get tosVersion => 'גרסה 1.0';

  @override
  String get urgentCustomerLabel => 'שירות דחוף';

  @override
  String get urgentProviderLabel => 'הזדמנויות דחופות';

  @override
  String get urgentOpenButton => 'פתח';

  @override
  String get walletMinWithdraw => 'מינימום למשיכה';

  @override
  String get withdrawalPending => 'משיכה בטיפול';

  @override
  String get withdrawFunds => 'משוך כספים';

  @override
  String onboardingError(String error) {
    return 'שגיאה: $error';
  }

  @override
  String onboardingUploadError(String error) {
    return 'שגיאה בהעלאה: $error';
  }

  @override
  String get onboardingWelcome => 'ברוכים הבאים!';

  @override
  String get availabilityUpdated => 'הזמינות עודכנה';

  @override
  String get bizAiRecruitNow => 'גייס עכשיו';

  @override
  String get chatEmptyState => 'אין הודעות עדיין';

  @override
  String get chatLastMessageDefault => 'אין הודעה אחרונה';

  @override
  String get chatSearchHint => 'חפש בצ\'אטים...';

  @override
  String get chatUserDefault => 'משתמש';

  @override
  String get deleteChatConfirm => 'אישור';

  @override
  String get deleteChatContent => 'האם אתה בטוח שברצונך למחוק את השיחה?';

  @override
  String get deleteChatSuccess => 'השיחה נמחקה בהצלחה';

  @override
  String get deleteChatTitle => 'מחיקת שיחה';

  @override
  String get disputeActionsSection => 'פעולות';

  @override
  String get disputeAdminNote => 'הערת מנהל';

  @override
  String get disputeAdminNoteHint => 'הוסף הערה (אופציונלי)';

  @override
  String get disputeArbitrationCenter => 'מרכז בוררות';

  @override
  String get disputeChatHistory => 'היסטוריית צ\'אט';

  @override
  String get disputeDescription => 'תיאור';

  @override
  String get disputeEmptySubtitle => 'אין מחלוקות פתוחות כרגע';

  @override
  String get disputeEmptyTitle => 'אין מחלוקות';

  @override
  String get disputeHint => 'תאר את הבעיה בפירוט';

  @override
  String get disputeIdPrefix => 'מחלוקת #';

  @override
  String get disputeIrreversible => 'פעולה זו אינה ניתנת לביטול';

  @override
  String get disputeLockedEscrow => 'נעול באסקרו';

  @override
  String get disputeLockedSuffix => '₪';

  @override
  String get disputeNoChatId => 'אין מזהה צ\'אט';

  @override
  String get disputeNoMessages => 'אין הודעות';

  @override
  String get disputeNoReason => 'לא צוינה סיבה';

  @override
  String get disputeOpenDisputes => 'מחלוקות פתוחות';

  @override
  String get disputePartiesSection => 'הצדדים';

  @override
  String get disputePartyProvider => 'הספק';

  @override
  String get disputeReasonSection => 'סיבת המחלוקת';

  @override
  String get disputeRefundLabel => 'החזר כספי';

  @override
  String get disputeReleaseLabel => 'שחרור תשלום';

  @override
  String get disputeResolving => 'מעבד...';

  @override
  String get disputeSplitLabel => 'חלוקה';

  @override
  String get disputeSystemSender => 'מערכת';

  @override
  String get disputeTapForDetails => 'לחץ לפרטים';

  @override
  String get disputeTitle => 'מחלוקת';

  @override
  String get editProfileTitle => 'עריכת פרופיל';

  @override
  String get helpCenterInputHint => 'כתוב את שאלתך כאן...';

  @override
  String get logoutButton => 'התנתק';

  @override
  String get markAllReadSuccess => 'כל ההתראות סומנו כנקראו';

  @override
  String get markedDoneSuccess => 'סומן כבוצע בהצלחה';

  @override
  String get noCategoriesYet => 'אין קטגוריות עדיין';

  @override
  String get notifClearAll => 'נקה הכל';

  @override
  String get notifEmptySubtitle => 'אין לך התראות חדשות';

  @override
  String get notifEmptyTitle => 'אין התראות';

  @override
  String get notifOpen => 'פתח';

  @override
  String get notificationsTitle => 'התראות';

  @override
  String get oppNotifTitle => 'התעניינות חדשה';

  @override
  String get pendingCatsApprove => 'אשר';

  @override
  String get pendingCatsEmptySubtitle => 'אין בקשות קטגוריה ממתינות';

  @override
  String get pendingCatsEmptyTitle => 'אין בקשות';

  @override
  String get pendingCatsImagePrompt => 'העלה תמונה לקטגוריה';

  @override
  String get pendingCatsProviderDesc => 'תיאור הספק';

  @override
  String get pendingCatsReject => 'דחה';

  @override
  String get pendingCatsSectionPending => 'ממתינות';

  @override
  String get pendingCatsSectionReviewed => 'נבדקו';

  @override
  String get pendingCatsStatusApproved => 'אושר';

  @override
  String get pendingCatsStatusRejected => 'נדחה';

  @override
  String get pendingCatsTitle => 'בקשות קטגוריה';

  @override
  String get pendingCatsAiReason => 'נימוק AI';

  @override
  String get profileLoadError => 'שגיאה בטעינת הפרופיל';

  @override
  String get requestsBestValue => 'תמורה הכי טובה';

  @override
  String get requestsFastResponse => 'תגובה מהירה';

  @override
  String get requestsInterestedTitle => 'מתעניינים';

  @override
  String get requestsNoInterested => 'אין מתעניינים עדיין';

  @override
  String get requestsTitle => 'בקשות';

  @override
  String get submitDispute => 'שלח מחלוקת';

  @override
  String get systemWalletFeePanel => 'עמלת פלטפורמה';

  @override
  String get systemWalletInvalidNumber => 'מספר לא תקין';

  @override
  String get systemWalletUpdateFee => 'עדכן עמלה';

  @override
  String get tosAcceptButton => 'אני מסכים/ה';

  @override
  String get tosBindingNotice => 'בלחיצה על אישור, אתה מסכים לתנאי השימוש';

  @override
  String get tosFullTitle => 'תנאי שימוש מלאים';

  @override
  String get tosLastUpdated => 'עדכון אחרון';

  @override
  String get withdrawExistingCert => 'תעודה קיימת';

  @override
  String get withdrawUploadError => 'שגיאה בהעלאת הקובץ';

  @override
  String get xpAddAction => 'הוסף';

  @override
  String get xpAddEventButton => 'הוסף אירוע';

  @override
  String get xpAddEventTitle => 'הוספת אירוע XP';

  @override
  String get xpDeleteEventTitle => 'מחיקת אירוע';

  @override
  String get xpEditEventTitle => 'עריכת אירוע XP';

  @override
  String get xpEventAdded => 'האירוע נוסף בהצלחה';

  @override
  String get xpEventDeleted => 'האירוע נמחק בהצלחה';

  @override
  String get xpEventUpdated => 'האירוע עודכן בהצלחה';

  @override
  String get xpEventsEmpty => 'אין אירועי XP';

  @override
  String get xpEventsSection => 'אירועי XP';

  @override
  String get xpFieldDesc => 'תיאור';

  @override
  String get xpFieldId => 'מזהה';

  @override
  String get xpFieldIdHint => 'הזן מזהה ייחודי';

  @override
  String get xpFieldName => 'שם';

  @override
  String get xpFieldPoints => 'נקודות';

  @override
  String get xpLevelsError => 'שגיאה בשמירת הרמות';

  @override
  String get xpLevelsSaved => 'הרמות נשמרו בהצלחה';

  @override
  String get xpLevelsSubtitle => 'הגדר את ספי ה-XP לכל רמה';

  @override
  String get xpLevelsTitle => 'רמות XP';

  @override
  String get xpManagerSubtitle => 'ניהול אירועים ורמות XP';

  @override
  String get xpManagerTitle => 'מנהל XP';

  @override
  String get xpReservedId => 'מזהה שמור';

  @override
  String get xpSaveAction => 'שמור';

  @override
  String get xpSaveLevels => 'שמור רמות';

  @override
  String get xpTooltipDelete => 'מחק';

  @override
  String get xpTooltipEdit => 'ערוך';

  @override
  String bizAiThresholdUpdated(int value) {
    return 'הסף עודכן ל-$value';
  }

  @override
  String disputeErrorPrefix(String error) {
    return 'שגיאה: $error';
  }

  @override
  String disputeExistingNote(String note) {
    return 'הערת מנהל: $note';
  }

  @override
  String disputeOpenedAt(String date) {
    return 'נפתח ב-$date';
  }

  @override
  String disputeRefundSublabel(String amount) {
    return 'החזר מלא — $amount ₪ ללקוח';
  }

  @override
  String disputeReleaseSublabel(String amount) {
    return 'שחרור — $amount ₪ לספק';
  }

  @override
  String disputeSplitSublabel(String amount) {
    return 'חלוקה — $amount ₪ לכל צד';
  }

  @override
  String editCategorySaveError(String error) {
    return 'שגיאה בשמירה: $error';
  }

  @override
  String oppInterestChatMessage(String providerName, String description) {
    return 'שלום, אני $providerName ואשמח לעזור: $description';
  }

  @override
  String oppNotifBody(String providerName) {
    return '$providerName מעוניין בהזדמנות שלך';
  }

  @override
  String pendingCatsErrorPrefix(String error) {
    return 'שגיאה: $error';
  }

  @override
  String pendingCatsSubCategory(String name) {
    return 'תת-קטגוריה: $name';
  }

  @override
  String xpDeleteEventConfirm(String name) {
    return 'למחוק את $name?';
  }

  @override
  String xpErrorPrefix(String error) {
    return 'שגיאה: $error';
  }

  @override
  String xpEventsCount(int count) {
    return '$count אירועים';
  }
}
