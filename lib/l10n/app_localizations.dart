import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_he.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('he'),
    Locale('en'),
    Locale('es'),
    Locale('ar')
  ];

  /// No description provided for @appName.
  ///
  /// In he, this message translates to:
  /// **'AnySkill'**
  String get appName;

  /// No description provided for @appSlogan.
  ///
  /// In he, this message translates to:
  /// **'המקצוענים שלך, במרחק נגיעה'**
  String get appSlogan;

  /// No description provided for @greetingMorning.
  ///
  /// In he, this message translates to:
  /// **'בוקר טוב'**
  String get greetingMorning;

  /// No description provided for @greetingAfternoon.
  ///
  /// In he, this message translates to:
  /// **'אחה\"צ טובות'**
  String get greetingAfternoon;

  /// No description provided for @greetingEvening.
  ///
  /// In he, this message translates to:
  /// **'ערב טוב'**
  String get greetingEvening;

  /// No description provided for @greetingNight.
  ///
  /// In he, this message translates to:
  /// **'לילה טוב'**
  String get greetingNight;

  /// No description provided for @greetingSubMorning.
  ///
  /// In he, this message translates to:
  /// **'מה תרצה לעשות היום?'**
  String get greetingSubMorning;

  /// No description provided for @greetingSubAfternoon.
  ///
  /// In he, this message translates to:
  /// **'צריך עזרה עם משהו?'**
  String get greetingSubAfternoon;

  /// No description provided for @greetingSubEvening.
  ///
  /// In he, this message translates to:
  /// **'עדיין מחפש שירות?'**
  String get greetingSubEvening;

  /// No description provided for @greetingSubNight.
  ///
  /// In he, this message translates to:
  /// **'נתראה מחר!'**
  String get greetingSubNight;

  /// No description provided for @tabHome.
  ///
  /// In he, this message translates to:
  /// **'בית'**
  String get tabHome;

  /// No description provided for @tabBookings.
  ///
  /// In he, this message translates to:
  /// **'הזמנות'**
  String get tabBookings;

  /// No description provided for @tabChat.
  ///
  /// In he, this message translates to:
  /// **'הודעות'**
  String get tabChat;

  /// No description provided for @tabWallet.
  ///
  /// In he, this message translates to:
  /// **'ארנק'**
  String get tabWallet;

  /// No description provided for @bookNow.
  ///
  /// In he, this message translates to:
  /// **'הזמן עכשיו'**
  String get bookNow;

  /// No description provided for @bookingCompleted.
  ///
  /// In he, this message translates to:
  /// **'ההזמנה הושלמה בהצלחה'**
  String get bookingCompleted;

  /// No description provided for @close.
  ///
  /// In he, this message translates to:
  /// **'סגור'**
  String get close;

  /// No description provided for @retryButton.
  ///
  /// In he, this message translates to:
  /// **'נסה שוב'**
  String get retryButton;

  /// No description provided for @saveChanges.
  ///
  /// In he, this message translates to:
  /// **'שמור שינויים'**
  String get saveChanges;

  /// No description provided for @saveSuccess.
  ///
  /// In he, this message translates to:
  /// **'נשמר בהצלחה'**
  String get saveSuccess;

  /// No description provided for @saveError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בשמירה: {error}'**
  String saveError(String error);

  /// No description provided for @defaultUserName.
  ///
  /// In he, this message translates to:
  /// **'משתמש'**
  String get defaultUserName;

  /// No description provided for @notLoggedIn.
  ///
  /// In he, this message translates to:
  /// **'לא מחובר'**
  String get notLoggedIn;

  /// No description provided for @linkCopied.
  ///
  /// In he, this message translates to:
  /// **'הקישור הועתק'**
  String get linkCopied;

  /// No description provided for @errorEmptyFields.
  ///
  /// In he, this message translates to:
  /// **'יש למלא את כל השדות'**
  String get errorEmptyFields;

  /// No description provided for @errorGeneric.
  ///
  /// In he, this message translates to:
  /// **'אירעה שגיאה. נסה שוב'**
  String get errorGeneric;

  /// No description provided for @errorInvalidEmail.
  ///
  /// In he, this message translates to:
  /// **'כתובת אימייל לא תקינה'**
  String get errorInvalidEmail;

  /// No description provided for @whatsappError.
  ///
  /// In he, this message translates to:
  /// **'לא ניתן לפתוח WhatsApp'**
  String get whatsappError;

  /// No description provided for @markAllReadTooltip.
  ///
  /// In he, this message translates to:
  /// **'סמן הכל כנקרא'**
  String get markAllReadTooltip;

  /// No description provided for @onlineStatus.
  ///
  /// In he, this message translates to:
  /// **'זמין'**
  String get onlineStatus;

  /// No description provided for @offlineStatus.
  ///
  /// In he, this message translates to:
  /// **'לא זמין'**
  String get offlineStatus;

  /// No description provided for @onlineToggleOn.
  ///
  /// In he, this message translates to:
  /// **'אתה עכשיו זמין'**
  String get onlineToggleOn;

  /// No description provided for @onlineToggleOff.
  ///
  /// In he, this message translates to:
  /// **'אתה עכשיו לא זמין'**
  String get onlineToggleOff;

  /// No description provided for @roleCustomer.
  ///
  /// In he, this message translates to:
  /// **'לקוח'**
  String get roleCustomer;

  /// No description provided for @roleProvider.
  ///
  /// In he, this message translates to:
  /// **'ספק שירות'**
  String get roleProvider;

  /// No description provided for @loginAccountTitle.
  ///
  /// In he, this message translates to:
  /// **'כניסה לחשבון'**
  String get loginAccountTitle;

  /// No description provided for @loginButton.
  ///
  /// In he, this message translates to:
  /// **'התחבר'**
  String get loginButton;

  /// No description provided for @loginEmail.
  ///
  /// In he, this message translates to:
  /// **'כתובת אימייל'**
  String get loginEmail;

  /// No description provided for @loginForgotPassword.
  ///
  /// In he, this message translates to:
  /// **'שכחת סיסמה?'**
  String get loginForgotPassword;

  /// No description provided for @loginNoAccount.
  ///
  /// In he, this message translates to:
  /// **'אין לך חשבון? '**
  String get loginNoAccount;

  /// No description provided for @loginPassword.
  ///
  /// In he, this message translates to:
  /// **'סיסמה'**
  String get loginPassword;

  /// No description provided for @loginRememberMe.
  ///
  /// In he, this message translates to:
  /// **'זכור אותי'**
  String get loginRememberMe;

  /// No description provided for @loginSignUpFree.
  ///
  /// In he, this message translates to:
  /// **'הירשם בחינם'**
  String get loginSignUpFree;

  /// No description provided for @loginStats10k.
  ///
  /// In he, this message translates to:
  /// **'10K+'**
  String get loginStats10k;

  /// No description provided for @loginStats50.
  ///
  /// In he, this message translates to:
  /// **'50+'**
  String get loginStats50;

  /// No description provided for @loginStats49.
  ///
  /// In he, this message translates to:
  /// **'4.9★'**
  String get loginStats49;

  /// No description provided for @loginWelcomeBack.
  ///
  /// In he, this message translates to:
  /// **'ברוך שובך!'**
  String get loginWelcomeBack;

  /// No description provided for @signupAccountCreated.
  ///
  /// In he, this message translates to:
  /// **'החשבון נוצר בהצלחה!'**
  String get signupAccountCreated;

  /// No description provided for @signupEmailInUse.
  ///
  /// In he, this message translates to:
  /// **'כתובת האימייל כבר בשימוש'**
  String get signupEmailInUse;

  /// No description provided for @signupGenericError.
  ///
  /// In he, this message translates to:
  /// **'אירעה שגיאה בהרשמה'**
  String get signupGenericError;

  /// No description provided for @signupGoogleError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בהתחברות עם Google'**
  String get signupGoogleError;

  /// No description provided for @signupNetworkError.
  ///
  /// In he, this message translates to:
  /// **'שגיאת רשת. בדוק את החיבור'**
  String get signupNetworkError;

  /// No description provided for @signupNewCustomerBio.
  ///
  /// In he, this message translates to:
  /// **'לקוח חדש ב-AnySkill'**
  String get signupNewCustomerBio;

  /// No description provided for @signupNewProviderBio.
  ///
  /// In he, this message translates to:
  /// **'ספק שירות חדש ב-AnySkill'**
  String get signupNewProviderBio;

  /// No description provided for @signupTosMustAgree.
  ///
  /// In he, this message translates to:
  /// **'יש לאשר את תנאי השימוש'**
  String get signupTosMustAgree;

  /// No description provided for @signupWeakPassword.
  ///
  /// In he, this message translates to:
  /// **'הסיסמה חלשה מדי'**
  String get signupWeakPassword;

  /// No description provided for @forgotPasswordEmail.
  ///
  /// In he, this message translates to:
  /// **'כתובת אימייל'**
  String get forgotPasswordEmail;

  /// No description provided for @forgotPasswordError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בשליחת קישור איפוס'**
  String get forgotPasswordError;

  /// No description provided for @forgotPasswordSubmit.
  ///
  /// In he, this message translates to:
  /// **'שלח קישור איפוס'**
  String get forgotPasswordSubmit;

  /// No description provided for @forgotPasswordSubtitle.
  ///
  /// In he, this message translates to:
  /// **'הזן את כתובת האימייל שלך ונשלח לך קישור לאיפוס הסיסמה'**
  String get forgotPasswordSubtitle;

  /// No description provided for @forgotPasswordSuccess.
  ///
  /// In he, this message translates to:
  /// **'קישור איפוס נשלח לאימייל שלך'**
  String get forgotPasswordSuccess;

  /// No description provided for @forgotPasswordTitle.
  ///
  /// In he, this message translates to:
  /// **'שכחתי סיסמה'**
  String get forgotPasswordTitle;

  /// No description provided for @authError.
  ///
  /// In he, this message translates to:
  /// **'שגיאת אימות: {code}'**
  String authError(String code);

  /// No description provided for @profileTitle.
  ///
  /// In he, this message translates to:
  /// **'הפרופיל שלי'**
  String get profileTitle;

  /// No description provided for @profileFieldName.
  ///
  /// In he, this message translates to:
  /// **'שם מלא'**
  String get profileFieldName;

  /// No description provided for @profileFieldNameHint.
  ///
  /// In he, this message translates to:
  /// **'הזן את שמך המלא'**
  String get profileFieldNameHint;

  /// No description provided for @profileFieldRole.
  ///
  /// In he, this message translates to:
  /// **'סוג משתמש'**
  String get profileFieldRole;

  /// No description provided for @profileFieldCategoryMain.
  ///
  /// In he, this message translates to:
  /// **'תחום עיסוק'**
  String get profileFieldCategoryMain;

  /// No description provided for @profileFieldCategoryMainHint.
  ///
  /// In he, this message translates to:
  /// **'בחר את תחום העיסוק שלך'**
  String get profileFieldCategoryMainHint;

  /// No description provided for @profileFieldCategorySub.
  ///
  /// In he, this message translates to:
  /// **'תת-קטגוריה'**
  String get profileFieldCategorySub;

  /// No description provided for @profileFieldCategorySubHint.
  ///
  /// In he, this message translates to:
  /// **'בחר התמחות ספציפית'**
  String get profileFieldCategorySubHint;

  /// No description provided for @profileFieldPrice.
  ///
  /// In he, this message translates to:
  /// **'מחיר לשעה (₪)'**
  String get profileFieldPrice;

  /// No description provided for @profileFieldPriceHint.
  ///
  /// In he, this message translates to:
  /// **'הזן מחיר לשעה'**
  String get profileFieldPriceHint;

  /// No description provided for @profileFieldResponseTime.
  ///
  /// In he, this message translates to:
  /// **'זמן תגובה (דקות)'**
  String get profileFieldResponseTime;

  /// No description provided for @profileFieldResponseTimeHint.
  ///
  /// In he, this message translates to:
  /// **'זמן תגובה ממוצע'**
  String get profileFieldResponseTimeHint;

  /// No description provided for @profileFieldTaxId.
  ///
  /// In he, this message translates to:
  /// **'מספר עוסק מורשה / ח.פ.'**
  String get profileFieldTaxId;

  /// No description provided for @profileFieldTaxIdHint.
  ///
  /// In he, this message translates to:
  /// **'הזן מספר עוסק מורשה'**
  String get profileFieldTaxIdHint;

  /// No description provided for @profileFieldTaxIdHelp.
  ///
  /// In he, this message translates to:
  /// **'מספר זה ישמש להפקת חשבוניות'**
  String get profileFieldTaxIdHelp;

  /// No description provided for @editProfileAbout.
  ///
  /// In he, this message translates to:
  /// **'קצת עליי'**
  String get editProfileAbout;

  /// No description provided for @editProfileAboutHint.
  ///
  /// In he, this message translates to:
  /// **'ספר ללקוחות על הניסיון שלך...'**
  String get editProfileAboutHint;

  /// No description provided for @editProfileCancellationPolicy.
  ///
  /// In he, this message translates to:
  /// **'מדיניות ביטול'**
  String get editProfileCancellationPolicy;

  /// No description provided for @editProfileCancellationHint.
  ///
  /// In he, this message translates to:
  /// **'בחר מדיניות ביטול'**
  String get editProfileCancellationHint;

  /// No description provided for @editProfileGallery.
  ///
  /// In he, this message translates to:
  /// **'גלריה'**
  String get editProfileGallery;

  /// No description provided for @editProfileQuickTags.
  ///
  /// In he, this message translates to:
  /// **'תגיות מהירות'**
  String get editProfileQuickTags;

  /// No description provided for @editProfileTagsHint.
  ///
  /// In he, this message translates to:
  /// **'הוסף תגיות לפרופיל שלך'**
  String get editProfileTagsHint;

  /// No description provided for @editProfileTagsSelected.
  ///
  /// In he, this message translates to:
  /// **'{count} נבחרו'**
  String editProfileTagsSelected(int count);

  /// No description provided for @editCategoryTitle.
  ///
  /// In he, this message translates to:
  /// **'ערוך קטגוריה'**
  String get editCategoryTitle;

  /// No description provided for @editCategoryNameLabel.
  ///
  /// In he, this message translates to:
  /// **'שם הקטגוריה'**
  String get editCategoryNameLabel;

  /// No description provided for @editCategoryChangePic.
  ///
  /// In he, this message translates to:
  /// **'שנה תמונה'**
  String get editCategoryChangePic;

  /// No description provided for @shareProfileTitle.
  ///
  /// In he, this message translates to:
  /// **'שתף פרופיל'**
  String get shareProfileTitle;

  /// No description provided for @shareProfileTooltip.
  ///
  /// In he, this message translates to:
  /// **'שתף את הפרופיל שלך'**
  String get shareProfileTooltip;

  /// No description provided for @shareProfileCopyLink.
  ///
  /// In he, this message translates to:
  /// **'העתק קישור'**
  String get shareProfileCopyLink;

  /// No description provided for @shareProfileWhatsapp.
  ///
  /// In he, this message translates to:
  /// **'שתף בוואטסאפ'**
  String get shareProfileWhatsapp;

  /// No description provided for @statBalance.
  ///
  /// In he, this message translates to:
  /// **'יתרה'**
  String get statBalance;

  /// No description provided for @searchHintExperts.
  ///
  /// In he, this message translates to:
  /// **'חפש מקצוענים...'**
  String get searchHintExperts;

  /// No description provided for @searchDefaultTitle.
  ///
  /// In he, this message translates to:
  /// **'חיפוש'**
  String get searchDefaultTitle;

  /// No description provided for @searchDefaultCity.
  ///
  /// In he, this message translates to:
  /// **'ישראל'**
  String get searchDefaultCity;

  /// No description provided for @searchDefaultExpert.
  ///
  /// In he, this message translates to:
  /// **'מקצוען'**
  String get searchDefaultExpert;

  /// No description provided for @searchSectionCategories.
  ///
  /// In he, this message translates to:
  /// **'קטגוריות'**
  String get searchSectionCategories;

  /// No description provided for @searchSectionResultsFor.
  ///
  /// In he, this message translates to:
  /// **'תוצאות עבור \"{query}\"'**
  String searchSectionResultsFor(String query);

  /// No description provided for @searchNoResultsFor.
  ///
  /// In he, this message translates to:
  /// **'אין תוצאות עבור \"{query}\"'**
  String searchNoResultsFor(String query);

  /// No description provided for @searchNoCategoriesBody.
  ///
  /// In he, this message translates to:
  /// **'לא נמצאו קטגוריות'**
  String get searchNoCategoriesBody;

  /// No description provided for @searchPerHour.
  ///
  /// In he, this message translates to:
  /// **'₪/שעה'**
  String get searchPerHour;

  /// No description provided for @searchRecommendedBadge.
  ///
  /// In he, this message translates to:
  /// **'מומלץ'**
  String get searchRecommendedBadge;

  /// No description provided for @searchChipHomeVisit.
  ///
  /// In he, this message translates to:
  /// **'ביקור בית'**
  String get searchChipHomeVisit;

  /// No description provided for @searchChipWeekend.
  ///
  /// In he, this message translates to:
  /// **'זמין בסופ\"ש'**
  String get searchChipWeekend;

  /// No description provided for @searchDatePickerHint.
  ///
  /// In he, this message translates to:
  /// **'בחר תאריך'**
  String get searchDatePickerHint;

  /// No description provided for @searchTourSearchTitle.
  ///
  /// In he, this message translates to:
  /// **'חיפוש מקצוענים'**
  String get searchTourSearchTitle;

  /// No description provided for @searchTourSearchDesc.
  ///
  /// In he, this message translates to:
  /// **'חפש לפי שם, שירות או קטגוריה'**
  String get searchTourSearchDesc;

  /// No description provided for @searchTourSuggestionsTitle.
  ///
  /// In he, this message translates to:
  /// **'הצעות חכמות'**
  String get searchTourSuggestionsTitle;

  /// No description provided for @searchTourSuggestionsDesc.
  ///
  /// In he, this message translates to:
  /// **'הצעות מותאמות אישית על בסיס חיפושים קודמים'**
  String get searchTourSuggestionsDesc;

  /// No description provided for @searchUrgencyMorning.
  ///
  /// In he, this message translates to:
  /// **'בוקר'**
  String get searchUrgencyMorning;

  /// No description provided for @searchUrgencyAfternoon.
  ///
  /// In he, this message translates to:
  /// **'צהריים'**
  String get searchUrgencyAfternoon;

  /// No description provided for @searchUrgencyEvening.
  ///
  /// In he, this message translates to:
  /// **'ערב'**
  String get searchUrgencyEvening;

  /// No description provided for @catResultsSearchHint.
  ///
  /// In he, this message translates to:
  /// **'חפש בתוך הקטגוריה...'**
  String get catResultsSearchHint;

  /// No description provided for @catResultsNoExperts.
  ///
  /// In he, this message translates to:
  /// **'אין מקצוענים בקטגוריה {category}'**
  String catResultsNoExperts(String category);

  /// No description provided for @catResultsNoResults.
  ///
  /// In he, this message translates to:
  /// **'אין תוצאות'**
  String get catResultsNoResults;

  /// No description provided for @catResultsNoResultsHint.
  ///
  /// In he, this message translates to:
  /// **'נסה לשנות את החיפוש שלך'**
  String get catResultsNoResultsHint;

  /// No description provided for @catResultsPerHour.
  ///
  /// In he, this message translates to:
  /// **'₪/שעה'**
  String get catResultsPerHour;

  /// No description provided for @catResultsOrderCount.
  ///
  /// In he, this message translates to:
  /// **'{count} הזמנות'**
  String catResultsOrderCount(int count);

  /// No description provided for @catResultsResponseTime.
  ///
  /// In he, this message translates to:
  /// **'תגובה תוך {minutes} דק\''**
  String catResultsResponseTime(int minutes);

  /// No description provided for @catResultsRecommended.
  ///
  /// In he, this message translates to:
  /// **'מומלץ'**
  String get catResultsRecommended;

  /// No description provided for @catResultsTopRated.
  ///
  /// In he, this message translates to:
  /// **'דירוג גבוה'**
  String get catResultsTopRated;

  /// No description provided for @catResultsUnder100.
  ///
  /// In he, this message translates to:
  /// **'עד ₪100'**
  String get catResultsUnder100;

  /// No description provided for @catResultsClearFilters.
  ///
  /// In he, this message translates to:
  /// **'נקה מסננים'**
  String get catResultsClearFilters;

  /// No description provided for @catResultsBeFirst.
  ///
  /// In he, this message translates to:
  /// **'היה הראשון!'**
  String get catResultsBeFirst;

  /// No description provided for @catResultsExpertDefault.
  ///
  /// In he, this message translates to:
  /// **'מקצוען'**
  String get catResultsExpertDefault;

  /// No description provided for @catResultsLoadMore.
  ///
  /// In he, this message translates to:
  /// **'טען עוד'**
  String get catResultsLoadMore;

  /// No description provided for @catResultsAvailableSlots.
  ///
  /// In he, this message translates to:
  /// **'משבצות פנויות'**
  String get catResultsAvailableSlots;

  /// No description provided for @catResultsNoAvailability.
  ///
  /// In he, this message translates to:
  /// **'אין זמינות'**
  String get catResultsNoAvailability;

  /// No description provided for @catResultsFullBooking.
  ///
  /// In he, this message translates to:
  /// **'תפוס'**
  String get catResultsFullBooking;

  /// No description provided for @catResultsWhenFree.
  ///
  /// In he, this message translates to:
  /// **'מתי פנוי?'**
  String get catResultsWhenFree;

  /// No description provided for @chatListTitle.
  ///
  /// In he, this message translates to:
  /// **'הודעות'**
  String get chatListTitle;

  /// No description provided for @expertSectionAbout.
  ///
  /// In he, this message translates to:
  /// **'אודות'**
  String get expertSectionAbout;

  /// No description provided for @expertSectionService.
  ///
  /// In he, this message translates to:
  /// **'השירות'**
  String get expertSectionService;

  /// No description provided for @expertSectionSchedule.
  ///
  /// In he, this message translates to:
  /// **'זמינות'**
  String get expertSectionSchedule;

  /// No description provided for @expertBioPlaceholder.
  ///
  /// In he, this message translates to:
  /// **'אין ביוגרפיה עדיין'**
  String get expertBioPlaceholder;

  /// No description provided for @expertBioReadMore.
  ///
  /// In he, this message translates to:
  /// **'קרא עוד'**
  String get expertBioReadMore;

  /// No description provided for @expertBioShowLess.
  ///
  /// In he, this message translates to:
  /// **'הצג פחות'**
  String get expertBioShowLess;

  /// No description provided for @expertNoReviews.
  ///
  /// In he, this message translates to:
  /// **'אין ביקורות עדיין'**
  String get expertNoReviews;

  /// No description provided for @expertDefaultReviewer.
  ///
  /// In he, this message translates to:
  /// **'משתמש'**
  String get expertDefaultReviewer;

  /// No description provided for @expertProviderResponse.
  ///
  /// In he, this message translates to:
  /// **'תגובת הספק'**
  String get expertProviderResponse;

  /// No description provided for @expertAddReply.
  ///
  /// In he, this message translates to:
  /// **'הוסף תגובה'**
  String get expertAddReply;

  /// No description provided for @expertAddReplyTitle.
  ///
  /// In he, this message translates to:
  /// **'הוסף תגובה לביקורת'**
  String get expertAddReplyTitle;

  /// No description provided for @expertReplyHint.
  ///
  /// In he, this message translates to:
  /// **'כתוב תגובה...'**
  String get expertReplyHint;

  /// No description provided for @expertPublishReply.
  ///
  /// In he, this message translates to:
  /// **'פרסם תגובה'**
  String get expertPublishReply;

  /// No description provided for @expertReplyError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בפרסום תגובה'**
  String get expertReplyError;

  /// No description provided for @expertSelectDateTime.
  ///
  /// In he, this message translates to:
  /// **'בחר תאריך ושעה'**
  String get expertSelectDateTime;

  /// No description provided for @expertSelectTime.
  ///
  /// In he, this message translates to:
  /// **'בחר שעה'**
  String get expertSelectTime;

  /// No description provided for @expertBookForTime.
  ///
  /// In he, this message translates to:
  /// **'הזמן ל-{time}'**
  String expertBookForTime(String time);

  /// No description provided for @expertStartingFrom.
  ///
  /// In he, this message translates to:
  /// **'החל מ-₪{price}'**
  String expertStartingFrom(String price);

  /// No description provided for @expertBookingSummaryTitle.
  ///
  /// In he, this message translates to:
  /// **'סיכום הזמנה'**
  String get expertBookingSummaryTitle;

  /// No description provided for @expertSummaryRowService.
  ///
  /// In he, this message translates to:
  /// **'שירות'**
  String get expertSummaryRowService;

  /// No description provided for @expertSummaryRowDate.
  ///
  /// In he, this message translates to:
  /// **'תאריך'**
  String get expertSummaryRowDate;

  /// No description provided for @expertSummaryRowTime.
  ///
  /// In he, this message translates to:
  /// **'שעה'**
  String get expertSummaryRowTime;

  /// No description provided for @expertSummaryRowPrice.
  ///
  /// In he, this message translates to:
  /// **'מחיר'**
  String get expertSummaryRowPrice;

  /// No description provided for @expertSummaryRowIncluded.
  ///
  /// In he, this message translates to:
  /// **'כולל'**
  String get expertSummaryRowIncluded;

  /// No description provided for @expertSummaryRowProtection.
  ///
  /// In he, this message translates to:
  /// **'הגנת קונה'**
  String get expertSummaryRowProtection;

  /// No description provided for @expertSummaryRowTotal.
  ///
  /// In he, this message translates to:
  /// **'סה\"כ'**
  String get expertSummaryRowTotal;

  /// No description provided for @expertConfirmPaymentButton.
  ///
  /// In he, this message translates to:
  /// **'אשר ושלם'**
  String get expertConfirmPaymentButton;

  /// No description provided for @expertVerifiedBooking.
  ///
  /// In he, this message translates to:
  /// **'הזמנה מאומתת'**
  String get expertVerifiedBooking;

  /// No description provided for @expertInsufficientBalance.
  ///
  /// In he, this message translates to:
  /// **'אין מספיק יתרה'**
  String get expertInsufficientBalance;

  /// No description provided for @expertEscrowSuccess.
  ///
  /// In he, this message translates to:
  /// **'התשלום אושר! הכסף נעול באסקרו'**
  String get expertEscrowSuccess;

  /// No description provided for @expertTransactionTitle.
  ///
  /// In he, this message translates to:
  /// **'תשלום ל-{name}'**
  String expertTransactionTitle(String name);

  /// No description provided for @expertSystemMessage.
  ///
  /// In he, this message translates to:
  /// **'הזמנה אושרה ל-{date} בשעה {time}. ₪{amount} נעולים באסקרו.'**
  String expertSystemMessage(String date, String time, String amount);

  /// No description provided for @expertCancellationNotice.
  ///
  /// In he, this message translates to:
  /// **'מדיניות {policy}: ביטול חינם עד {deadline}. לאחר מכן {penalty}% קנס.'**
  String expertCancellationNotice(String policy, String deadline, String penalty);

  /// No description provided for @expertCancellationNoDeadline.
  ///
  /// In he, this message translates to:
  /// **'מדיניות {policy}: {description}'**
  String expertCancellationNoDeadline(String policy, String description);

  /// No description provided for @financeTitle.
  ///
  /// In he, this message translates to:
  /// **'כספים'**
  String get financeTitle;

  /// No description provided for @financeAvailableBalance.
  ///
  /// In he, this message translates to:
  /// **'יתרה זמינה'**
  String get financeAvailableBalance;

  /// No description provided for @financePending.
  ///
  /// In he, this message translates to:
  /// **'בהמתנה'**
  String get financePending;

  /// No description provided for @financeProcessing.
  ///
  /// In he, this message translates to:
  /// **'בעיבוד'**
  String get financeProcessing;

  /// No description provided for @financeRecentActivity.
  ///
  /// In he, this message translates to:
  /// **'פעילות אחרונה'**
  String get financeRecentActivity;

  /// No description provided for @financeNoTransactions.
  ///
  /// In he, this message translates to:
  /// **'אין עסקאות'**
  String get financeNoTransactions;

  /// No description provided for @financeWithdrawButton.
  ///
  /// In he, this message translates to:
  /// **'משוך כספים'**
  String get financeWithdrawButton;

  /// No description provided for @financeMinWithdraw.
  ///
  /// In he, this message translates to:
  /// **'מינימום למשיכה: ₪50'**
  String get financeMinWithdraw;

  /// No description provided for @financeTrustBadge.
  ///
  /// In he, this message translates to:
  /// **'כספך מוגן'**
  String get financeTrustBadge;

  /// No description provided for @financeReceivedFrom.
  ///
  /// In he, this message translates to:
  /// **'התקבל מ-{name}'**
  String financeReceivedFrom(String name);

  /// No description provided for @financePaidTo.
  ///
  /// In he, this message translates to:
  /// **'שולם ל-{name}'**
  String financePaidTo(String name);

  /// No description provided for @financeError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה: {error}'**
  String financeError(String error);

  /// No description provided for @disputeConfirmRefund.
  ///
  /// In he, this message translates to:
  /// **'אישור החזר כספי'**
  String get disputeConfirmRefund;

  /// No description provided for @disputeConfirmRelease.
  ///
  /// In he, this message translates to:
  /// **'אישור שחרור תשלום'**
  String get disputeConfirmRelease;

  /// No description provided for @disputeConfirmSplit.
  ///
  /// In he, this message translates to:
  /// **'אישור חלוקה'**
  String get disputeConfirmSplit;

  /// No description provided for @disputePartyCustomer.
  ///
  /// In he, this message translates to:
  /// **'הלקוח'**
  String get disputePartyCustomer;

  /// No description provided for @disputeRefundBody.
  ///
  /// In he, this message translates to:
  /// **'₪{amount} יוחזרו ל-{customerName}'**
  String disputeRefundBody(String amount, String customerName);

  /// No description provided for @disputeReleaseBody.
  ///
  /// In he, this message translates to:
  /// **'₪{netAmount} ישוחררו ל-{expertName} (עמלה {feePercent}%)'**
  String disputeReleaseBody(String netAmount, String expertName, String feePercent);

  /// No description provided for @disputeSplitBody.
  ///
  /// In he, this message translates to:
  /// **'חלוקה: ₪{halfAmount} לכל צד. ספק מקבל ₪{halfNet}, פלטפורמה ₪{platformFee}'**
  String disputeSplitBody(String halfAmount, String halfNet, String platformFee);

  /// No description provided for @disputeResolvedRefund.
  ///
  /// In he, this message translates to:
  /// **'המחלוקת נפתרה — בוצע החזר כספי'**
  String get disputeResolvedRefund;

  /// No description provided for @disputeResolvedRelease.
  ///
  /// In he, this message translates to:
  /// **'המחלוקת נפתרה — התשלום שוחרר'**
  String get disputeResolvedRelease;

  /// No description provided for @disputeResolvedSplit.
  ///
  /// In he, this message translates to:
  /// **'המחלוקת נפתרה — הסכום חולק'**
  String get disputeResolvedSplit;

  /// No description provided for @disputeTypeAudio.
  ///
  /// In he, this message translates to:
  /// **'הקלטה'**
  String get disputeTypeAudio;

  /// No description provided for @disputeTypeImage.
  ///
  /// In he, this message translates to:
  /// **'תמונה'**
  String get disputeTypeImage;

  /// No description provided for @disputeTypeLocation.
  ///
  /// In he, this message translates to:
  /// **'מיקום'**
  String get disputeTypeLocation;

  /// No description provided for @releasePaymentError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בשחרור התשלום'**
  String get releasePaymentError;

  /// No description provided for @oppTitle.
  ///
  /// In he, this message translates to:
  /// **'הזדמנויות'**
  String get oppTitle;

  /// No description provided for @oppAllCategories.
  ///
  /// In he, this message translates to:
  /// **'כל הקטגוריות'**
  String get oppAllCategories;

  /// No description provided for @oppEmptyAll.
  ///
  /// In he, this message translates to:
  /// **'אין הזדמנויות כרגע'**
  String get oppEmptyAll;

  /// No description provided for @oppEmptyAllSubtitle.
  ///
  /// In he, this message translates to:
  /// **'בדוק שוב מאוחר יותר'**
  String get oppEmptyAllSubtitle;

  /// No description provided for @oppEmptyCategory.
  ///
  /// In he, this message translates to:
  /// **'אין הזדמנויות בקטגוריה זו'**
  String get oppEmptyCategory;

  /// No description provided for @oppEmptyCategorySubtitle.
  ///
  /// In he, this message translates to:
  /// **'נסה קטגוריה אחרת'**
  String get oppEmptyCategorySubtitle;

  /// No description provided for @oppTakeOpportunity.
  ///
  /// In he, this message translates to:
  /// **'תפוס הזדמנות'**
  String get oppTakeOpportunity;

  /// No description provided for @oppInterested.
  ///
  /// In he, this message translates to:
  /// **'מעוניין'**
  String get oppInterested;

  /// No description provided for @oppAlreadyInterested.
  ///
  /// In he, this message translates to:
  /// **'כבר הבעת עניין'**
  String get oppAlreadyInterested;

  /// No description provided for @oppAlreadyExpressed.
  ///
  /// In he, this message translates to:
  /// **'כבר הבעת עניין בבקשה זו'**
  String get oppAlreadyExpressed;

  /// No description provided for @oppAlready3Interested.
  ///
  /// In he, this message translates to:
  /// **'כבר יש 3 מתעניינים'**
  String get oppAlready3Interested;

  /// No description provided for @oppInterestSuccess.
  ///
  /// In he, this message translates to:
  /// **'עניינך נרשם בהצלחה!'**
  String get oppInterestSuccess;

  /// No description provided for @oppRequestClosed3.
  ///
  /// In he, this message translates to:
  /// **'הבקשה נסגרה — 3 מתעניינים'**
  String get oppRequestClosed3;

  /// No description provided for @oppRequestClosedBtn.
  ///
  /// In he, this message translates to:
  /// **'הבקשה נסגרה'**
  String get oppRequestClosedBtn;

  /// No description provided for @oppRequestUnavailable.
  ///
  /// In he, this message translates to:
  /// **'הבקשה אינה זמינה יותר'**
  String get oppRequestUnavailable;

  /// No description provided for @oppDefaultClient.
  ///
  /// In he, this message translates to:
  /// **'לקוח'**
  String get oppDefaultClient;

  /// No description provided for @oppHighDemand.
  ///
  /// In he, this message translates to:
  /// **'ביקוש גבוה'**
  String get oppHighDemand;

  /// No description provided for @oppQuickBid.
  ///
  /// In he, this message translates to:
  /// **'הצעה מהירה'**
  String get oppQuickBid;

  /// No description provided for @oppQuickBidMessage.
  ///
  /// In he, this message translates to:
  /// **'שלום {clientName}, אני {providerName} ואשמח לעזור!'**
  String oppQuickBidMessage(String clientName, String providerName);

  /// No description provided for @oppEstimatedEarnings.
  ///
  /// In he, this message translates to:
  /// **'הכנסה משוערת'**
  String get oppEstimatedEarnings;

  /// No description provided for @oppAfterFee.
  ///
  /// In he, this message translates to:
  /// **'לאחר עמלה'**
  String get oppAfterFee;

  /// No description provided for @oppWalletHint.
  ///
  /// In he, this message translates to:
  /// **'הכנסות נכנסות לארנק שלך'**
  String get oppWalletHint;

  /// No description provided for @oppXpToNextLevel.
  ///
  /// In he, this message translates to:
  /// **'עוד {xpNeeded} XP לרמת {levelName}'**
  String oppXpToNextLevel(int xpNeeded, String levelName);

  /// No description provided for @oppMaxLevel.
  ///
  /// In he, this message translates to:
  /// **'רמה מקסימלית!'**
  String get oppMaxLevel;

  /// No description provided for @oppBoostEarned.
  ///
  /// In he, this message translates to:
  /// **'בוסט פרופיל הושג!'**
  String get oppBoostEarned;

  /// No description provided for @oppBoostProgress.
  ///
  /// In he, this message translates to:
  /// **'{count}/3 הזדמנויות לבוסט'**
  String oppBoostProgress(int count);

  /// No description provided for @oppProfileBoosted.
  ///
  /// In he, this message translates to:
  /// **'פרופיל מקודם! נותרו {timeLabel}'**
  String oppProfileBoosted(String timeLabel);

  /// No description provided for @oppError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה: {error}'**
  String oppError(String error);

  /// No description provided for @oppTimeJustNow.
  ///
  /// In he, this message translates to:
  /// **'הרגע'**
  String get oppTimeJustNow;

  /// No description provided for @oppTimeMinAgo.
  ///
  /// In he, this message translates to:
  /// **'לפני {minutes} דק\''**
  String oppTimeMinAgo(int minutes);

  /// No description provided for @oppTimeHourAgo.
  ///
  /// In he, this message translates to:
  /// **'לפני {hours} שעות'**
  String oppTimeHourAgo(int hours);

  /// No description provided for @oppTimeDayAgo.
  ///
  /// In he, this message translates to:
  /// **'לפני {days} ימים'**
  String oppTimeDayAgo(int days);

  /// No description provided for @oppTimeHours.
  ///
  /// In he, this message translates to:
  /// **'{hours} שעות'**
  String oppTimeHours(int hours);

  /// No description provided for @oppTimeMinutes.
  ///
  /// In he, this message translates to:
  /// **'{minutes} דקות'**
  String oppTimeMinutes(int minutes);

  /// No description provided for @oppUnderReviewTitle.
  ///
  /// In he, this message translates to:
  /// **'הפרופיל שלך בבדיקה'**
  String get oppUnderReviewTitle;

  /// No description provided for @oppUnderReviewSubtitle.
  ///
  /// In he, this message translates to:
  /// **'צוות AnySkill בודק את הפרופיל שלך'**
  String get oppUnderReviewSubtitle;

  /// No description provided for @oppUnderReviewBody.
  ///
  /// In he, this message translates to:
  /// **'נעדכן אותך ברגע שהאימות יושלם'**
  String get oppUnderReviewBody;

  /// No description provided for @oppUnderReviewContact.
  ///
  /// In he, this message translates to:
  /// **'צור קשר עם התמיכה'**
  String get oppUnderReviewContact;

  /// No description provided for @oppUnderReviewStep1.
  ///
  /// In he, this message translates to:
  /// **'פרופיל נשלח'**
  String get oppUnderReviewStep1;

  /// No description provided for @oppUnderReviewStep2.
  ///
  /// In he, this message translates to:
  /// **'בבדיקה'**
  String get oppUnderReviewStep2;

  /// No description provided for @oppUnderReviewStep3.
  ///
  /// In he, this message translates to:
  /// **'אישור סופי'**
  String get oppUnderReviewStep3;

  /// No description provided for @requestsEmpty.
  ///
  /// In he, this message translates to:
  /// **'אין בקשות'**
  String get requestsEmpty;

  /// No description provided for @requestsEmptySubtitle.
  ///
  /// In he, this message translates to:
  /// **'עדיין לא פורסמו בקשות'**
  String get requestsEmptySubtitle;

  /// No description provided for @requestsChatNow.
  ///
  /// In he, this message translates to:
  /// **'שלח הודעה'**
  String get requestsChatNow;

  /// No description provided for @requestsClosed.
  ///
  /// In he, this message translates to:
  /// **'סגור'**
  String get requestsClosed;

  /// No description provided for @requestsConfirmPay.
  ///
  /// In he, this message translates to:
  /// **'אשר ושלם'**
  String get requestsConfirmPay;

  /// No description provided for @requestsDefaultExpert.
  ///
  /// In he, this message translates to:
  /// **'מקצוען'**
  String get requestsDefaultExpert;

  /// No description provided for @requestsEscrowTooltip.
  ///
  /// In he, this message translates to:
  /// **'הכסף נשמר באסקרו עד להשלמת העבודה'**
  String get requestsEscrowTooltip;

  /// No description provided for @requestsMatchLabel.
  ///
  /// In he, this message translates to:
  /// **'התאמה'**
  String get requestsMatchLabel;

  /// No description provided for @requestsTopMatch.
  ///
  /// In he, this message translates to:
  /// **'התאמה מובילה'**
  String get requestsTopMatch;

  /// No description provided for @requestsVerifiedBadge.
  ///
  /// In he, this message translates to:
  /// **'מאומת'**
  String get requestsVerifiedBadge;

  /// No description provided for @requestsMoneyProtected.
  ///
  /// In he, this message translates to:
  /// **'כספך מוגן'**
  String get requestsMoneyProtected;

  /// No description provided for @requestsWaiting.
  ///
  /// In he, this message translates to:
  /// **'ממתין'**
  String get requestsWaiting;

  /// No description provided for @requestsWaitingProviders.
  ///
  /// In he, this message translates to:
  /// **'ממתין לספקים...'**
  String get requestsWaitingProviders;

  /// No description provided for @requestsJustNow.
  ///
  /// In he, this message translates to:
  /// **'הרגע'**
  String get requestsJustNow;

  /// No description provided for @requestsMinutesAgo.
  ///
  /// In he, this message translates to:
  /// **'לפני {minutes} דק\''**
  String requestsMinutesAgo(int minutes);

  /// No description provided for @requestsHoursAgo.
  ///
  /// In he, this message translates to:
  /// **'לפני {hours} שעות'**
  String requestsHoursAgo(int hours);

  /// No description provided for @requestsDaysAgo.
  ///
  /// In he, this message translates to:
  /// **'לפני {days} ימים'**
  String requestsDaysAgo(int days);

  /// No description provided for @requestsInterested.
  ///
  /// In he, this message translates to:
  /// **'{count} מתעניינים'**
  String requestsInterested(int count);

  /// No description provided for @requestsViewInterested.
  ///
  /// In he, this message translates to:
  /// **'צפה ב-{count} מתעניינים'**
  String requestsViewInterested(int count);

  /// No description provided for @requestsOrderCount.
  ///
  /// In he, this message translates to:
  /// **'{count} הזמנות'**
  String requestsOrderCount(int count);

  /// No description provided for @requestsHiredAgo.
  ///
  /// In he, this message translates to:
  /// **'נשכר {label}'**
  String requestsHiredAgo(String label);

  /// No description provided for @requestsPricePerHour.
  ///
  /// In he, this message translates to:
  /// **'₪{price}/שעה'**
  String requestsPricePerHour(String price);

  /// No description provided for @timeNow.
  ///
  /// In he, this message translates to:
  /// **'עכשיו'**
  String get timeNow;

  /// No description provided for @timeOneHour.
  ///
  /// In he, this message translates to:
  /// **'שעה'**
  String get timeOneHour;

  /// No description provided for @timeMinutesAgo.
  ///
  /// In he, this message translates to:
  /// **'לפני {minutes} דק\''**
  String timeMinutesAgo(int minutes);

  /// No description provided for @timeHoursAgo.
  ///
  /// In he, this message translates to:
  /// **'לפני {hours} שעות'**
  String timeHoursAgo(int hours);

  /// No description provided for @urgentBannerRequests.
  ///
  /// In he, this message translates to:
  /// **'בקשות דחופות'**
  String get urgentBannerRequests;

  /// No description provided for @urgentBannerPending.
  ///
  /// In he, this message translates to:
  /// **'ממתינות'**
  String get urgentBannerPending;

  /// No description provided for @urgentBannerServiceNeeded.
  ///
  /// In he, this message translates to:
  /// **'דרוש שירות'**
  String get urgentBannerServiceNeeded;

  /// No description provided for @urgentBannerCustomerWaiting.
  ///
  /// In he, this message translates to:
  /// **'לקוח ממתין'**
  String get urgentBannerCustomerWaiting;

  /// No description provided for @calendarTitle.
  ///
  /// In he, this message translates to:
  /// **'לוח שנה'**
  String get calendarTitle;

  /// No description provided for @calendarRefresh.
  ///
  /// In he, this message translates to:
  /// **'רענן'**
  String get calendarRefresh;

  /// No description provided for @calendarNoEvents.
  ///
  /// In he, this message translates to:
  /// **'אין אירועים'**
  String get calendarNoEvents;

  /// No description provided for @calendarStatusCompleted.
  ///
  /// In he, this message translates to:
  /// **'הושלם'**
  String get calendarStatusCompleted;

  /// No description provided for @calendarStatusPending.
  ///
  /// In he, this message translates to:
  /// **'ממתין'**
  String get calendarStatusPending;

  /// No description provided for @calendarStatusWaiting.
  ///
  /// In he, this message translates to:
  /// **'בהמתנה'**
  String get calendarStatusWaiting;

  /// No description provided for @creditsLabel.
  ///
  /// In he, this message translates to:
  /// **'קרדיטים'**
  String get creditsLabel;

  /// No description provided for @creditsDiscountAvailable.
  ///
  /// In he, this message translates to:
  /// **'הנחה של {discount}% זמינה!'**
  String creditsDiscountAvailable(int discount);

  /// No description provided for @creditsToNextDiscount.
  ///
  /// In he, this message translates to:
  /// **'עוד {remaining} קרדיטים להנחה הבאה'**
  String creditsToNextDiscount(int remaining);

  /// No description provided for @serviceFullSession.
  ///
  /// In he, this message translates to:
  /// **'שיעור מלא'**
  String get serviceFullSession;

  /// No description provided for @serviceSingleLesson.
  ///
  /// In he, this message translates to:
  /// **'שיעור בודד'**
  String get serviceSingleLesson;

  /// No description provided for @serviceExtendedLesson.
  ///
  /// In he, this message translates to:
  /// **'שיעור מורחב'**
  String get serviceExtendedLesson;

  /// No description provided for @validationNameRequired.
  ///
  /// In he, this message translates to:
  /// **'שם הוא שדה חובה'**
  String get validationNameRequired;

  /// No description provided for @validationNameLength.
  ///
  /// In he, this message translates to:
  /// **'שם חייב להכיל לפחות 2 תווים'**
  String get validationNameLength;

  /// No description provided for @validationNameTooLong.
  ///
  /// In he, this message translates to:
  /// **'שם ארוך מדי'**
  String get validationNameTooLong;

  /// No description provided for @validationNameForbidden.
  ///
  /// In he, this message translates to:
  /// **'השם מכיל תווים אסורים'**
  String get validationNameForbidden;

  /// No description provided for @validationCategoryRequired.
  ///
  /// In he, this message translates to:
  /// **'יש לבחור קטגוריה'**
  String get validationCategoryRequired;

  /// No description provided for @validationRoleRequired.
  ///
  /// In he, this message translates to:
  /// **'יש לבחור סוג משתמש'**
  String get validationRoleRequired;

  /// No description provided for @validationPriceInvalid.
  ///
  /// In he, this message translates to:
  /// **'מחיר לא תקין'**
  String get validationPriceInvalid;

  /// No description provided for @validationPricePositive.
  ///
  /// In he, this message translates to:
  /// **'המחיר חייב להיות חיובי'**
  String get validationPricePositive;

  /// No description provided for @validationAboutTooLong.
  ///
  /// In he, this message translates to:
  /// **'התיאור ארוך מדי'**
  String get validationAboutTooLong;

  /// No description provided for @validationAboutForbidden.
  ///
  /// In he, this message translates to:
  /// **'התיאור מכיל תווים אסורים'**
  String get validationAboutForbidden;

  /// No description provided for @validationFieldForbidden.
  ///
  /// In he, this message translates to:
  /// **'השדה מכיל תווים אסורים'**
  String get validationFieldForbidden;

  /// No description provided for @validationUrlHttps.
  ///
  /// In he, this message translates to:
  /// **'הקישור חייב להתחיל ב-https://'**
  String get validationUrlHttps;

  /// No description provided for @vipSheetHeader.
  ///
  /// In he, this message translates to:
  /// **'AnySkill VIP'**
  String get vipSheetHeader;

  /// No description provided for @vipPriceMonthly.
  ///
  /// In he, this message translates to:
  /// **'₪99/חודש'**
  String get vipPriceMonthly;

  /// No description provided for @vipActivateButton.
  ///
  /// In he, this message translates to:
  /// **'הפעל VIP'**
  String get vipActivateButton;

  /// No description provided for @vipActivationSuccess.
  ///
  /// In he, this message translates to:
  /// **'VIP הופעל בהצלחה!'**
  String get vipActivationSuccess;

  /// No description provided for @vipInsufficientBalance.
  ///
  /// In he, this message translates to:
  /// **'אין מספיק יתרה להפעלת VIP'**
  String get vipInsufficientBalance;

  /// No description provided for @vipInsufficientTooltip.
  ///
  /// In he, this message translates to:
  /// **'טען את הארנק שלך כדי להפעיל VIP'**
  String get vipInsufficientTooltip;

  /// No description provided for @vipBenefit1.
  ///
  /// In he, this message translates to:
  /// **'קידום בתוצאות חיפוש'**
  String get vipBenefit1;

  /// No description provided for @vipBenefit2.
  ///
  /// In he, this message translates to:
  /// **'תג VIP בפרופיל'**
  String get vipBenefit2;

  /// No description provided for @vipBenefit3.
  ///
  /// In he, this message translates to:
  /// **'עדיפות בהזדמנויות'**
  String get vipBenefit3;

  /// No description provided for @vipBenefit4.
  ///
  /// In he, this message translates to:
  /// **'תמיכה מועדפת'**
  String get vipBenefit4;

  /// No description provided for @withdrawMinBalance.
  ///
  /// In he, this message translates to:
  /// **'הסכום המינימלי למשיכה הוא {amount} ₪'**
  String withdrawMinBalance(int amount);

  /// No description provided for @withdrawAvailableBalance.
  ///
  /// In he, this message translates to:
  /// **'יתרה זמינה למשיכה'**
  String get withdrawAvailableBalance;

  /// No description provided for @withdrawBankSection.
  ///
  /// In he, this message translates to:
  /// **'פרטי בנק'**
  String get withdrawBankSection;

  /// No description provided for @withdrawBankName.
  ///
  /// In he, this message translates to:
  /// **'שם הבנק'**
  String get withdrawBankName;

  /// No description provided for @withdrawBankBranch.
  ///
  /// In he, this message translates to:
  /// **'סניף'**
  String get withdrawBankBranch;

  /// No description provided for @withdrawBankAccount.
  ///
  /// In he, this message translates to:
  /// **'מספר חשבון'**
  String get withdrawBankAccount;

  /// No description provided for @withdrawBankRequired.
  ///
  /// In he, this message translates to:
  /// **'יש להזין שם בנק'**
  String get withdrawBankRequired;

  /// No description provided for @withdrawBranchRequired.
  ///
  /// In he, this message translates to:
  /// **'יש להזין סניף'**
  String get withdrawBranchRequired;

  /// No description provided for @withdrawAccountMinDigits.
  ///
  /// In he, this message translates to:
  /// **'מספר חשבון חייב להכיל לפחות 5 ספרות'**
  String get withdrawAccountMinDigits;

  /// No description provided for @withdrawBankEncryptedNotice.
  ///
  /// In he, this message translates to:
  /// **'הפרטים מוצפנים ומאובטחים'**
  String get withdrawBankEncryptedNotice;

  /// No description provided for @withdrawEncryptedNotice.
  ///
  /// In he, this message translates to:
  /// **'המידע מוצפן ומאובטח'**
  String get withdrawEncryptedNotice;

  /// No description provided for @withdrawBankTransferPending.
  ///
  /// In he, this message translates to:
  /// **'העברה בנקאית בטיפול'**
  String get withdrawBankTransferPending;

  /// No description provided for @withdrawCertSection.
  ///
  /// In he, this message translates to:
  /// **'אישורים'**
  String get withdrawCertSection;

  /// No description provided for @withdrawCertHint.
  ///
  /// In he, this message translates to:
  /// **'העלה תעודת עוסק מורשה/פטור'**
  String get withdrawCertHint;

  /// No description provided for @withdrawCertUploadBtn.
  ///
  /// In he, this message translates to:
  /// **'העלה אישור'**
  String get withdrawCertUploadBtn;

  /// No description provided for @withdrawCertReplace.
  ///
  /// In he, this message translates to:
  /// **'החלף אישור'**
  String get withdrawCertReplace;

  /// No description provided for @withdrawDeclarationSection.
  ///
  /// In he, this message translates to:
  /// **'הצהרה'**
  String get withdrawDeclarationSection;

  /// No description provided for @withdrawDeclarationText.
  ///
  /// In he, this message translates to:
  /// **'אני מצהיר/ה על אחריותי הבלעדית לדיווח מס כחוק'**
  String get withdrawDeclarationText;

  /// No description provided for @withdrawDeclarationSuffix.
  ///
  /// In he, this message translates to:
  /// **'(סעיף 6 בתקנון)'**
  String get withdrawDeclarationSuffix;

  /// No description provided for @withdrawTaxStatusTitle.
  ///
  /// In he, this message translates to:
  /// **'סוג עוסק'**
  String get withdrawTaxStatusTitle;

  /// No description provided for @withdrawTaxStatusSubtitle.
  ///
  /// In he, this message translates to:
  /// **'בחר את סוג העוסק שלך'**
  String get withdrawTaxStatusSubtitle;

  /// No description provided for @withdrawTaxIndividual.
  ///
  /// In he, this message translates to:
  /// **'עוסק פטור'**
  String get withdrawTaxIndividual;

  /// No description provided for @withdrawTaxIndividualSub.
  ///
  /// In he, this message translates to:
  /// **'פטור מגביית מע\"מ'**
  String get withdrawTaxIndividualSub;

  /// No description provided for @withdrawTaxIndividualBadge.
  ///
  /// In he, this message translates to:
  /// **'פטור'**
  String get withdrawTaxIndividualBadge;

  /// No description provided for @withdrawTaxBusiness.
  ///
  /// In he, this message translates to:
  /// **'עוסק מורשה'**
  String get withdrawTaxBusiness;

  /// No description provided for @withdrawTaxBusinessSub.
  ///
  /// In he, this message translates to:
  /// **'מחויב בגביית מע\"מ'**
  String get withdrawTaxBusinessSub;

  /// No description provided for @withdrawIndividualTitle.
  ///
  /// In he, this message translates to:
  /// **'פרטי עוסק פטור'**
  String get withdrawIndividualTitle;

  /// No description provided for @withdrawIndividualDesc.
  ///
  /// In he, this message translates to:
  /// **'הזן את פרטי העוסק הפטור שלך'**
  String get withdrawIndividualDesc;

  /// No description provided for @withdrawIndividualFormTitle.
  ///
  /// In he, this message translates to:
  /// **'טופס עוסק פטור'**
  String get withdrawIndividualFormTitle;

  /// No description provided for @withdrawBusinessFormTitle.
  ///
  /// In he, this message translates to:
  /// **'טופס עוסק מורשה'**
  String get withdrawBusinessFormTitle;

  /// No description provided for @withdrawNoCertError.
  ///
  /// In he, this message translates to:
  /// **'יש להעלות אישור עוסק'**
  String get withdrawNoCertError;

  /// No description provided for @withdrawNoDeclarationError.
  ///
  /// In he, this message translates to:
  /// **'יש לאשר את ההצהרה'**
  String get withdrawNoDeclarationError;

  /// No description provided for @withdrawSelectBankError.
  ///
  /// In he, this message translates to:
  /// **'יש לבחור בנק'**
  String get withdrawSelectBankError;

  /// No description provided for @withdrawSubmitButton.
  ///
  /// In he, this message translates to:
  /// **'משוך {amount}'**
  String withdrawSubmitButton(String amount);

  /// No description provided for @withdrawSubmitError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בשליחת הבקשה'**
  String get withdrawSubmitError;

  /// No description provided for @withdrawSuccessTitle.
  ///
  /// In he, this message translates to:
  /// **'הבקשה נשלחה!'**
  String get withdrawSuccessTitle;

  /// No description provided for @withdrawSuccessSubtitle.
  ///
  /// In he, this message translates to:
  /// **'בקשת המשיכה על סך {amount} נשלחה בהצלחה'**
  String withdrawSuccessSubtitle(String amount);

  /// No description provided for @withdrawSuccessNotice.
  ///
  /// In he, this message translates to:
  /// **'העברה בנקאית תתבצע תוך 3-5 ימי עסקים'**
  String get withdrawSuccessNotice;

  /// No description provided for @withdrawTimeline1Title.
  ///
  /// In he, this message translates to:
  /// **'בקשה נשלחה'**
  String get withdrawTimeline1Title;

  /// No description provided for @withdrawTimeline1Sub.
  ///
  /// In he, this message translates to:
  /// **'הבקשה התקבלה במערכת'**
  String get withdrawTimeline1Sub;

  /// No description provided for @withdrawTimeline2Title.
  ///
  /// In he, this message translates to:
  /// **'בטיפול'**
  String get withdrawTimeline2Title;

  /// No description provided for @withdrawTimeline2Sub.
  ///
  /// In he, this message translates to:
  /// **'הצוות מעבד את הבקשה'**
  String get withdrawTimeline2Sub;

  /// No description provided for @withdrawTimeline3Title.
  ///
  /// In he, this message translates to:
  /// **'הושלם'**
  String get withdrawTimeline3Title;

  /// No description provided for @withdrawTimeline3Sub.
  ///
  /// In he, this message translates to:
  /// **'הכסף הועבר לחשבונך'**
  String get withdrawTimeline3Sub;

  /// No description provided for @pendingCatsApproved.
  ///
  /// In he, this message translates to:
  /// **'הקטגוריה אושרה'**
  String get pendingCatsApproved;

  /// No description provided for @pendingCatsRejected.
  ///
  /// In he, this message translates to:
  /// **'הקטגוריה נדחתה'**
  String get pendingCatsRejected;

  /// No description provided for @helpCenterTitle.
  ///
  /// In he, this message translates to:
  /// **'מרכז עזרה'**
  String get helpCenterTitle;

  /// No description provided for @helpCenterTooltip.
  ///
  /// In he, this message translates to:
  /// **'עזרה'**
  String get helpCenterTooltip;

  /// No description provided for @helpCenterCustomerWelcome.
  ///
  /// In he, this message translates to:
  /// **'ברוך הבא למרכז העזרה'**
  String get helpCenterCustomerWelcome;

  /// No description provided for @helpCenterCustomerFaq.
  ///
  /// In he, this message translates to:
  /// **'שאלות נפוצות ללקוחות'**
  String get helpCenterCustomerFaq;

  /// No description provided for @helpCenterCustomerSupport.
  ///
  /// In he, this message translates to:
  /// **'תמיכת לקוחות'**
  String get helpCenterCustomerSupport;

  /// No description provided for @helpCenterProviderWelcome.
  ///
  /// In he, this message translates to:
  /// **'ברוך הבא למרכז העזרה לספקים'**
  String get helpCenterProviderWelcome;

  /// No description provided for @helpCenterProviderFaq.
  ///
  /// In he, this message translates to:
  /// **'שאלות נפוצות לספקים'**
  String get helpCenterProviderFaq;

  /// No description provided for @helpCenterProviderSupport.
  ///
  /// In he, this message translates to:
  /// **'תמיכת ספקים'**
  String get helpCenterProviderSupport;

  /// No description provided for @languageTitle.
  ///
  /// In he, this message translates to:
  /// **'שפה'**
  String get languageTitle;

  /// No description provided for @languageSectionLabel.
  ///
  /// In he, this message translates to:
  /// **'בחר שפה'**
  String get languageSectionLabel;

  /// No description provided for @languageHe.
  ///
  /// In he, this message translates to:
  /// **'עברית'**
  String get languageHe;

  /// No description provided for @languageEn.
  ///
  /// In he, this message translates to:
  /// **'English'**
  String get languageEn;

  /// No description provided for @languageEs.
  ///
  /// In he, this message translates to:
  /// **'Español'**
  String get languageEs;

  /// No description provided for @languageAr.
  ///
  /// In he, this message translates to:
  /// **'العربية'**
  String get languageAr;

  /// No description provided for @systemWalletEnterNumber.
  ///
  /// In he, this message translates to:
  /// **'הזן מספר תקין'**
  String get systemWalletEnterNumber;

  /// No description provided for @updateBannerText.
  ///
  /// In he, this message translates to:
  /// **'גרסה חדשה זמינה'**
  String get updateBannerText;

  /// No description provided for @updateNowButton.
  ///
  /// In he, this message translates to:
  /// **'עדכן עכשיו'**
  String get updateNowButton;

  /// No description provided for @xpLevelBronze.
  ///
  /// In he, this message translates to:
  /// **'טירון'**
  String get xpLevelBronze;

  /// No description provided for @xpLevelSilver.
  ///
  /// In he, this message translates to:
  /// **'מקצוען'**
  String get xpLevelSilver;

  /// No description provided for @xpLevelGold.
  ///
  /// In he, this message translates to:
  /// **'זהב'**
  String get xpLevelGold;

  /// No description provided for @bizAiTitle.
  ///
  /// In he, this message translates to:
  /// **'בינה עסקית'**
  String get bizAiTitle;

  /// No description provided for @bizAiSubtitle.
  ///
  /// In he, this message translates to:
  /// **'ניתוח וחיזוי מבוסס AI'**
  String get bizAiSubtitle;

  /// No description provided for @bizAiLoading.
  ///
  /// In he, this message translates to:
  /// **'טוען נתונים...'**
  String get bizAiLoading;

  /// No description provided for @bizAiRefreshData.
  ///
  /// In he, this message translates to:
  /// **'רענן נתונים'**
  String get bizAiRefreshData;

  /// No description provided for @bizAiNoData.
  ///
  /// In he, this message translates to:
  /// **'אין נתונים זמינים'**
  String get bizAiNoData;

  /// No description provided for @bizAiError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה: {error}'**
  String bizAiError(String error);

  /// No description provided for @bizAiSectionFinancial.
  ///
  /// In he, this message translates to:
  /// **'כספים'**
  String get bizAiSectionFinancial;

  /// No description provided for @bizAiSectionMarket.
  ///
  /// In he, this message translates to:
  /// **'שוק'**
  String get bizAiSectionMarket;

  /// No description provided for @bizAiSectionAlerts.
  ///
  /// In he, this message translates to:
  /// **'התראות'**
  String get bizAiSectionAlerts;

  /// No description provided for @bizAiSectionAiOps.
  ///
  /// In he, this message translates to:
  /// **'פעולות AI'**
  String get bizAiSectionAiOps;

  /// No description provided for @bizAiDailyCommission.
  ///
  /// In he, this message translates to:
  /// **'עמלה יומית'**
  String get bizAiDailyCommission;

  /// No description provided for @bizAiWeeklyProjection.
  ///
  /// In he, this message translates to:
  /// **'תחזית שבועית'**
  String get bizAiWeeklyProjection;

  /// No description provided for @bizAiWeeklyForecast.
  ///
  /// In he, this message translates to:
  /// **'תחזית שבועית'**
  String get bizAiWeeklyForecast;

  /// No description provided for @bizAiExpectedRevenue.
  ///
  /// In he, this message translates to:
  /// **'הכנסה צפויה'**
  String get bizAiExpectedRevenue;

  /// No description provided for @bizAiForecastBadge.
  ///
  /// In he, this message translates to:
  /// **'תחזית'**
  String get bizAiForecastBadge;

  /// No description provided for @bizAiActualToDate.
  ///
  /// In he, this message translates to:
  /// **'בפועל עד כה'**
  String get bizAiActualToDate;

  /// No description provided for @bizAiAccuracy.
  ///
  /// In he, this message translates to:
  /// **'דיוק'**
  String get bizAiAccuracy;

  /// No description provided for @bizAiModelAccuracy.
  ///
  /// In he, this message translates to:
  /// **'דיוק המודל'**
  String get bizAiModelAccuracy;

  /// No description provided for @bizAiModelAccuracyDetail.
  ///
  /// In he, this message translates to:
  /// **'דיוק חיזוי ההכנסות'**
  String get bizAiModelAccuracyDetail;

  /// No description provided for @bizAiNoChartData.
  ///
  /// In he, this message translates to:
  /// **'אין נתונים לגרף'**
  String get bizAiNoChartData;

  /// No description provided for @bizAiNoOrderData.
  ///
  /// In he, this message translates to:
  /// **'אין נתוני הזמנות'**
  String get bizAiNoOrderData;

  /// No description provided for @bizAiSevenDays.
  ///
  /// In he, this message translates to:
  /// **'7 ימים'**
  String get bizAiSevenDays;

  /// No description provided for @bizAiLast7Days.
  ///
  /// In he, this message translates to:
  /// **'7 ימים אחרונים'**
  String get bizAiLast7Days;

  /// No description provided for @bizAiExecSummary.
  ///
  /// In he, this message translates to:
  /// **'סיכום מנהלים'**
  String get bizAiExecSummary;

  /// No description provided for @bizAiActivityToday.
  ///
  /// In he, this message translates to:
  /// **'פעילות היום'**
  String get bizAiActivityToday;

  /// No description provided for @bizAiApprovalQueue.
  ///
  /// In he, this message translates to:
  /// **'תור אישורים'**
  String get bizAiApprovalQueue;

  /// No description provided for @bizAiPending.
  ///
  /// In he, this message translates to:
  /// **'{count} ממתינים'**
  String bizAiPending(int count);

  /// No description provided for @bizAiPendingLabel.
  ///
  /// In he, this message translates to:
  /// **'ממתינים'**
  String get bizAiPendingLabel;

  /// No description provided for @bizAiApproved.
  ///
  /// In he, this message translates to:
  /// **'מאושר'**
  String get bizAiApproved;

  /// No description provided for @bizAiRejected.
  ///
  /// In he, this message translates to:
  /// **'נדחה'**
  String get bizAiRejected;

  /// No description provided for @bizAiApprovedTotal.
  ///
  /// In he, this message translates to:
  /// **'סה\"כ אושרו'**
  String get bizAiApprovedTotal;

  /// No description provided for @bizAiTapToReview.
  ///
  /// In he, this message translates to:
  /// **'לחץ לבדיקה'**
  String get bizAiTapToReview;

  /// No description provided for @bizAiCategoriesApproved.
  ///
  /// In he, this message translates to:
  /// **'קטגוריות שאושרו'**
  String get bizAiCategoriesApproved;

  /// No description provided for @bizAiNewCategories.
  ///
  /// In he, this message translates to:
  /// **'קטגוריות חדשות'**
  String get bizAiNewCategories;

  /// No description provided for @bizAiMarketOpportunities.
  ///
  /// In he, this message translates to:
  /// **'הזדמנויות שוק'**
  String get bizAiMarketOpportunities;

  /// No description provided for @bizAiMarketOppsCard.
  ///
  /// In he, this message translates to:
  /// **'הזדמנויות שוק'**
  String get bizAiMarketOppsCard;

  /// No description provided for @bizAiHighValueCategories.
  ///
  /// In he, this message translates to:
  /// **'קטגוריות בעלות ערך גבוה'**
  String get bizAiHighValueCategories;

  /// No description provided for @bizAiHighValueHint.
  ///
  /// In he, this message translates to:
  /// **'קטגוריות עם פוטנציאל הכנסה גבוה'**
  String get bizAiHighValueHint;

  /// No description provided for @bizAiProviders.
  ///
  /// In he, this message translates to:
  /// **'{count} ספקים'**
  String bizAiProviders(int count);

  /// No description provided for @bizAiPopularSearches.
  ///
  /// In he, this message translates to:
  /// **'חיפושים פופולריים'**
  String get bizAiPopularSearches;

  /// No description provided for @bizAiNoSearchData.
  ///
  /// In he, this message translates to:
  /// **'אין נתוני חיפוש'**
  String get bizAiNoSearchData;

  /// No description provided for @bizAiNichesNoProviders.
  ///
  /// In he, this message translates to:
  /// **'נישות ללא ספקים'**
  String get bizAiNichesNoProviders;

  /// No description provided for @bizAiNoOpportunities.
  ///
  /// In he, this message translates to:
  /// **'אין הזדמנויות כרגע'**
  String get bizAiNoOpportunities;

  /// No description provided for @bizAiRecruitForQuery.
  ///
  /// In he, this message translates to:
  /// **'גייס ספקים עבור \"{query}\"'**
  String bizAiRecruitForQuery(String query);

  /// No description provided for @bizAiZeroResultsHint.
  ///
  /// In he, this message translates to:
  /// **'חיפושים ללא תוצאות — הזדמנות לגיוס'**
  String get bizAiZeroResultsHint;

  /// No description provided for @bizAiSearches.
  ///
  /// In he, this message translates to:
  /// **'חיפושים: {count}+'**
  String bizAiSearches(int count);

  /// No description provided for @bizAiSearchCount.
  ///
  /// In he, this message translates to:
  /// **'{count} חיפושים'**
  String bizAiSearchCount(int count);

  /// No description provided for @bizAiAlertHistory.
  ///
  /// In he, this message translates to:
  /// **'היסטוריית התראות'**
  String get bizAiAlertHistory;

  /// No description provided for @bizAiAlertThreshold.
  ///
  /// In he, this message translates to:
  /// **'סף התראה'**
  String get bizAiAlertThreshold;

  /// No description provided for @bizAiAlertThresholdHint.
  ///
  /// In he, this message translates to:
  /// **'מספר חיפושים מינימלי להתראה'**
  String get bizAiAlertThresholdHint;

  /// No description provided for @bizAiSaveThreshold.
  ///
  /// In he, this message translates to:
  /// **'שמור סף'**
  String get bizAiSaveThreshold;

  /// No description provided for @bizAiReset.
  ///
  /// In he, this message translates to:
  /// **'אפס'**
  String get bizAiReset;

  /// No description provided for @bizAiNoAlerts.
  ///
  /// In he, this message translates to:
  /// **'אין התראות'**
  String get bizAiNoAlerts;

  /// No description provided for @bizAiAlertCount.
  ///
  /// In he, this message translates to:
  /// **'{count} התראות'**
  String bizAiAlertCount(int count);

  /// No description provided for @bizAiMinutesAgo.
  ///
  /// In he, this message translates to:
  /// **'לפני {minutes} דק\''**
  String bizAiMinutesAgo(int minutes);

  /// No description provided for @bizAiHoursAgo.
  ///
  /// In he, this message translates to:
  /// **'לפני {hours} שעות'**
  String bizAiHoursAgo(int hours);

  /// No description provided for @bizAiDaysAgo.
  ///
  /// In he, this message translates to:
  /// **'לפני {days} ימים'**
  String bizAiDaysAgo(int days);

  /// No description provided for @tabProfile.
  ///
  /// In he, this message translates to:
  /// **'פרופיל'**
  String get tabProfile;

  /// No description provided for @searchPlaceholder.
  ///
  /// In he, this message translates to:
  /// **'חפש מקצוען, שירות...'**
  String get searchPlaceholder;

  /// No description provided for @searchTitle.
  ///
  /// In he, this message translates to:
  /// **'חיפוש'**
  String get searchTitle;

  /// No description provided for @discoverCategories.
  ///
  /// In he, this message translates to:
  /// **'גלה קטגוריות'**
  String get discoverCategories;

  /// No description provided for @confirm.
  ///
  /// In he, this message translates to:
  /// **'אישור'**
  String get confirm;

  /// No description provided for @cancel.
  ///
  /// In he, this message translates to:
  /// **'ביטול'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In he, this message translates to:
  /// **'שמור'**
  String get save;

  /// No description provided for @submit.
  ///
  /// In he, this message translates to:
  /// **'שלח'**
  String get submit;

  /// No description provided for @next.
  ///
  /// In he, this message translates to:
  /// **'הבא'**
  String get next;

  /// No description provided for @back.
  ///
  /// In he, this message translates to:
  /// **'חזור'**
  String get back;

  /// No description provided for @delete.
  ///
  /// In he, this message translates to:
  /// **'מחק'**
  String get delete;

  /// No description provided for @currencySymbol.
  ///
  /// In he, this message translates to:
  /// **'₪'**
  String get currencySymbol;

  /// No description provided for @statusPaidEscrow.
  ///
  /// In he, this message translates to:
  /// **'ממתין לאישור'**
  String get statusPaidEscrow;

  /// No description provided for @statusExpertCompleted.
  ///
  /// In he, this message translates to:
  /// **'הושלם — ממתין לאישורך'**
  String get statusExpertCompleted;

  /// No description provided for @statusCompleted.
  ///
  /// In he, this message translates to:
  /// **'הושלם'**
  String get statusCompleted;

  /// No description provided for @statusCancelled.
  ///
  /// In he, this message translates to:
  /// **'בוטל'**
  String get statusCancelled;

  /// No description provided for @statusDispute.
  ///
  /// In he, this message translates to:
  /// **'במחלוקת'**
  String get statusDispute;

  /// No description provided for @statusPendingPayment.
  ///
  /// In he, this message translates to:
  /// **'ממתין לתשלום'**
  String get statusPendingPayment;

  /// No description provided for @profileCustomer.
  ///
  /// In he, this message translates to:
  /// **'לקוח'**
  String get profileCustomer;

  /// No description provided for @profileProvider.
  ///
  /// In he, this message translates to:
  /// **'ספק שירות'**
  String get profileProvider;

  /// No description provided for @profileOrders.
  ///
  /// In he, this message translates to:
  /// **'הזמנות'**
  String get profileOrders;

  /// No description provided for @profileRating.
  ///
  /// In he, this message translates to:
  /// **'דירוג'**
  String get profileRating;

  /// No description provided for @profileReviews.
  ///
  /// In he, this message translates to:
  /// **'ביקורות'**
  String get profileReviews;

  /// No description provided for @reviewsPlaceholder.
  ///
  /// In he, this message translates to:
  /// **'ספר לנו על החוויה שלך...'**
  String get reviewsPlaceholder;

  /// No description provided for @reviewSubmit.
  ///
  /// In he, this message translates to:
  /// **'שלח ביקורת'**
  String get reviewSubmit;

  /// No description provided for @ratingLabel.
  ///
  /// In he, this message translates to:
  /// **'דרג את השירות'**
  String get ratingLabel;

  /// No description provided for @walletBalance.
  ///
  /// In he, this message translates to:
  /// **'יתרה'**
  String get walletBalance;

  /// No description provided for @openChat.
  ///
  /// In he, this message translates to:
  /// **'פתח צ\'אט'**
  String get openChat;

  /// No description provided for @quickRequest.
  ///
  /// In he, this message translates to:
  /// **'בקשה מהירה'**
  String get quickRequest;

  /// No description provided for @trendingBadge.
  ///
  /// In he, this message translates to:
  /// **'טרנדי'**
  String get trendingBadge;

  /// No description provided for @isCurrentRtl.
  ///
  /// In he, this message translates to:
  /// **'true'**
  String get isCurrentRtl;

  /// No description provided for @taxDeclarationText.
  ///
  /// In he, this message translates to:
  /// **'אני מצהיר/ה על אחריותי הבלעדית לדיווח מס כחוק. ידוע לי כי AnySkill אינה מעסיקתי ואינה מנכה מס במקור.'**
  String get taxDeclarationText;

  /// No description provided for @loginTitle.
  ///
  /// In he, this message translates to:
  /// **'כניסה'**
  String get loginTitle;

  /// No description provided for @loginSubtitle.
  ///
  /// In he, this message translates to:
  /// **'התחבר לחשבון שלך'**
  String get loginSubtitle;

  /// No description provided for @errorGenericLogin.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בהתחברות'**
  String get errorGenericLogin;

  /// No description provided for @subCategoryPrompt.
  ///
  /// In he, this message translates to:
  /// **'בחר תת-קטגוריה'**
  String get subCategoryPrompt;

  /// No description provided for @emptyActivityTitle.
  ///
  /// In he, this message translates to:
  /// **'אין פעילות'**
  String get emptyActivityTitle;

  /// No description provided for @emptyActivityCta.
  ///
  /// In he, this message translates to:
  /// **'התחל עכשיו'**
  String get emptyActivityCta;

  /// No description provided for @errorNetworkTitle.
  ///
  /// In he, this message translates to:
  /// **'שגיאת רשת'**
  String get errorNetworkTitle;

  /// No description provided for @errorNetworkBody.
  ///
  /// In he, this message translates to:
  /// **'בדוק את חיבור האינטרנט שלך'**
  String get errorNetworkBody;

  /// No description provided for @errorProfileLoad.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בטעינת הפרופיל'**
  String get errorProfileLoad;

  /// No description provided for @forgotPassword.
  ///
  /// In he, this message translates to:
  /// **'שכחת סיסמה?'**
  String get forgotPassword;

  /// No description provided for @signupButton.
  ///
  /// In he, this message translates to:
  /// **'הירשם'**
  String get signupButton;

  /// No description provided for @tosAgree.
  ///
  /// In he, this message translates to:
  /// **'אני מסכים/ה לתנאי השימוש'**
  String get tosAgree;

  /// No description provided for @tosTitle.
  ///
  /// In he, this message translates to:
  /// **'תנאי שימוש'**
  String get tosTitle;

  /// No description provided for @tosVersion.
  ///
  /// In he, this message translates to:
  /// **'גרסה 1.0'**
  String get tosVersion;

  /// No description provided for @urgentCustomerLabel.
  ///
  /// In he, this message translates to:
  /// **'שירות דחוף'**
  String get urgentCustomerLabel;

  /// No description provided for @urgentProviderLabel.
  ///
  /// In he, this message translates to:
  /// **'הזדמנויות דחופות'**
  String get urgentProviderLabel;

  /// No description provided for @urgentOpenButton.
  ///
  /// In he, this message translates to:
  /// **'פתח'**
  String get urgentOpenButton;

  /// No description provided for @walletMinWithdraw.
  ///
  /// In he, this message translates to:
  /// **'מינימום למשיכה'**
  String get walletMinWithdraw;

  /// No description provided for @withdrawalPending.
  ///
  /// In he, this message translates to:
  /// **'משיכה בטיפול'**
  String get withdrawalPending;

  /// No description provided for @withdrawFunds.
  ///
  /// In he, this message translates to:
  /// **'משוך כספים'**
  String get withdrawFunds;

  /// No description provided for @onboardingError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה: {error}'**
  String onboardingError(String error);

  /// No description provided for @onboardingUploadError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בהעלאה: {error}'**
  String onboardingUploadError(String error);

  /// No description provided for @onboardingWelcome.
  ///
  /// In he, this message translates to:
  /// **'ברוכים הבאים!'**
  String get onboardingWelcome;

  /// No description provided for @availabilityUpdated.
  ///
  /// In he, this message translates to:
  /// **'הזמינות עודכנה'**
  String get availabilityUpdated;

  /// No description provided for @bizAiRecruitNow.
  ///
  /// In he, this message translates to:
  /// **'גייס עכשיו'**
  String get bizAiRecruitNow;

  /// No description provided for @chatEmptyState.
  ///
  /// In he, this message translates to:
  /// **'אין הודעות עדיין'**
  String get chatEmptyState;

  /// No description provided for @chatLastMessageDefault.
  ///
  /// In he, this message translates to:
  /// **'אין הודעה אחרונה'**
  String get chatLastMessageDefault;

  /// No description provided for @chatSearchHint.
  ///
  /// In he, this message translates to:
  /// **'חפש בצ\'אטים...'**
  String get chatSearchHint;

  /// No description provided for @chatUserDefault.
  ///
  /// In he, this message translates to:
  /// **'משתמש'**
  String get chatUserDefault;

  /// No description provided for @deleteChatConfirm.
  ///
  /// In he, this message translates to:
  /// **'אישור'**
  String get deleteChatConfirm;

  /// No description provided for @deleteChatContent.
  ///
  /// In he, this message translates to:
  /// **'האם אתה בטוח שברצונך למחוק את השיחה?'**
  String get deleteChatContent;

  /// No description provided for @deleteChatSuccess.
  ///
  /// In he, this message translates to:
  /// **'השיחה נמחקה בהצלחה'**
  String get deleteChatSuccess;

  /// No description provided for @deleteChatTitle.
  ///
  /// In he, this message translates to:
  /// **'מחיקת שיחה'**
  String get deleteChatTitle;

  /// No description provided for @disputeActionsSection.
  ///
  /// In he, this message translates to:
  /// **'פעולות'**
  String get disputeActionsSection;

  /// No description provided for @disputeAdminNote.
  ///
  /// In he, this message translates to:
  /// **'הערת מנהל'**
  String get disputeAdminNote;

  /// No description provided for @disputeAdminNoteHint.
  ///
  /// In he, this message translates to:
  /// **'הוסף הערה (אופציונלי)'**
  String get disputeAdminNoteHint;

  /// No description provided for @disputeArbitrationCenter.
  ///
  /// In he, this message translates to:
  /// **'מרכז בוררות'**
  String get disputeArbitrationCenter;

  /// No description provided for @disputeChatHistory.
  ///
  /// In he, this message translates to:
  /// **'היסטוריית צ\'אט'**
  String get disputeChatHistory;

  /// No description provided for @disputeDescription.
  ///
  /// In he, this message translates to:
  /// **'תיאור'**
  String get disputeDescription;

  /// No description provided for @disputeEmptySubtitle.
  ///
  /// In he, this message translates to:
  /// **'אין מחלוקות פתוחות כרגע'**
  String get disputeEmptySubtitle;

  /// No description provided for @disputeEmptyTitle.
  ///
  /// In he, this message translates to:
  /// **'אין מחלוקות'**
  String get disputeEmptyTitle;

  /// No description provided for @disputeHint.
  ///
  /// In he, this message translates to:
  /// **'תאר את הבעיה בפירוט'**
  String get disputeHint;

  /// No description provided for @disputeIdPrefix.
  ///
  /// In he, this message translates to:
  /// **'מחלוקת #'**
  String get disputeIdPrefix;

  /// No description provided for @disputeIrreversible.
  ///
  /// In he, this message translates to:
  /// **'פעולה זו אינה ניתנת לביטול'**
  String get disputeIrreversible;

  /// No description provided for @disputeLockedEscrow.
  ///
  /// In he, this message translates to:
  /// **'נעול באסקרו'**
  String get disputeLockedEscrow;

  /// No description provided for @disputeLockedSuffix.
  ///
  /// In he, this message translates to:
  /// **'₪'**
  String get disputeLockedSuffix;

  /// No description provided for @disputeNoChatId.
  ///
  /// In he, this message translates to:
  /// **'אין מזהה צ\'אט'**
  String get disputeNoChatId;

  /// No description provided for @disputeNoMessages.
  ///
  /// In he, this message translates to:
  /// **'אין הודעות'**
  String get disputeNoMessages;

  /// No description provided for @disputeNoReason.
  ///
  /// In he, this message translates to:
  /// **'לא צוינה סיבה'**
  String get disputeNoReason;

  /// No description provided for @disputeOpenDisputes.
  ///
  /// In he, this message translates to:
  /// **'מחלוקות פתוחות'**
  String get disputeOpenDisputes;

  /// No description provided for @disputePartiesSection.
  ///
  /// In he, this message translates to:
  /// **'הצדדים'**
  String get disputePartiesSection;

  /// No description provided for @disputePartyProvider.
  ///
  /// In he, this message translates to:
  /// **'הספק'**
  String get disputePartyProvider;

  /// No description provided for @disputeReasonSection.
  ///
  /// In he, this message translates to:
  /// **'סיבת המחלוקת'**
  String get disputeReasonSection;

  /// No description provided for @disputeRefundLabel.
  ///
  /// In he, this message translates to:
  /// **'החזר כספי'**
  String get disputeRefundLabel;

  /// No description provided for @disputeReleaseLabel.
  ///
  /// In he, this message translates to:
  /// **'שחרור תשלום'**
  String get disputeReleaseLabel;

  /// No description provided for @disputeResolving.
  ///
  /// In he, this message translates to:
  /// **'מעבד...'**
  String get disputeResolving;

  /// No description provided for @disputeSplitLabel.
  ///
  /// In he, this message translates to:
  /// **'חלוקה'**
  String get disputeSplitLabel;

  /// No description provided for @disputeSystemSender.
  ///
  /// In he, this message translates to:
  /// **'מערכת'**
  String get disputeSystemSender;

  /// No description provided for @disputeTapForDetails.
  ///
  /// In he, this message translates to:
  /// **'לחץ לפרטים'**
  String get disputeTapForDetails;

  /// No description provided for @disputeTitle.
  ///
  /// In he, this message translates to:
  /// **'מחלוקת'**
  String get disputeTitle;

  /// No description provided for @editProfileTitle.
  ///
  /// In he, this message translates to:
  /// **'עריכת פרופיל'**
  String get editProfileTitle;

  /// No description provided for @helpCenterInputHint.
  ///
  /// In he, this message translates to:
  /// **'כתוב את שאלתך כאן...'**
  String get helpCenterInputHint;

  /// No description provided for @logoutButton.
  ///
  /// In he, this message translates to:
  /// **'התנתק'**
  String get logoutButton;

  /// No description provided for @markAllReadSuccess.
  ///
  /// In he, this message translates to:
  /// **'כל ההתראות סומנו כנקראו'**
  String get markAllReadSuccess;

  /// No description provided for @markedDoneSuccess.
  ///
  /// In he, this message translates to:
  /// **'סומן כבוצע בהצלחה'**
  String get markedDoneSuccess;

  /// No description provided for @noCategoriesYet.
  ///
  /// In he, this message translates to:
  /// **'אין קטגוריות עדיין'**
  String get noCategoriesYet;

  /// No description provided for @notifClearAll.
  ///
  /// In he, this message translates to:
  /// **'נקה הכל'**
  String get notifClearAll;

  /// No description provided for @notifEmptySubtitle.
  ///
  /// In he, this message translates to:
  /// **'אין לך התראות חדשות'**
  String get notifEmptySubtitle;

  /// No description provided for @notifEmptyTitle.
  ///
  /// In he, this message translates to:
  /// **'אין התראות'**
  String get notifEmptyTitle;

  /// No description provided for @notifOpen.
  ///
  /// In he, this message translates to:
  /// **'פתח'**
  String get notifOpen;

  /// No description provided for @notificationsTitle.
  ///
  /// In he, this message translates to:
  /// **'התראות'**
  String get notificationsTitle;

  /// No description provided for @oppNotifTitle.
  ///
  /// In he, this message translates to:
  /// **'התעניינות חדשה'**
  String get oppNotifTitle;

  /// No description provided for @pendingCatsApprove.
  ///
  /// In he, this message translates to:
  /// **'אשר'**
  String get pendingCatsApprove;

  /// No description provided for @pendingCatsEmptySubtitle.
  ///
  /// In he, this message translates to:
  /// **'אין בקשות קטגוריה ממתינות'**
  String get pendingCatsEmptySubtitle;

  /// No description provided for @pendingCatsEmptyTitle.
  ///
  /// In he, this message translates to:
  /// **'אין בקשות'**
  String get pendingCatsEmptyTitle;

  /// No description provided for @pendingCatsImagePrompt.
  ///
  /// In he, this message translates to:
  /// **'העלה תמונה לקטגוריה'**
  String get pendingCatsImagePrompt;

  /// No description provided for @pendingCatsProviderDesc.
  ///
  /// In he, this message translates to:
  /// **'תיאור הספק'**
  String get pendingCatsProviderDesc;

  /// No description provided for @pendingCatsReject.
  ///
  /// In he, this message translates to:
  /// **'דחה'**
  String get pendingCatsReject;

  /// No description provided for @pendingCatsSectionPending.
  ///
  /// In he, this message translates to:
  /// **'ממתינות'**
  String get pendingCatsSectionPending;

  /// No description provided for @pendingCatsSectionReviewed.
  ///
  /// In he, this message translates to:
  /// **'נבדקו'**
  String get pendingCatsSectionReviewed;

  /// No description provided for @pendingCatsStatusApproved.
  ///
  /// In he, this message translates to:
  /// **'אושר'**
  String get pendingCatsStatusApproved;

  /// No description provided for @pendingCatsStatusRejected.
  ///
  /// In he, this message translates to:
  /// **'נדחה'**
  String get pendingCatsStatusRejected;

  /// No description provided for @pendingCatsTitle.
  ///
  /// In he, this message translates to:
  /// **'בקשות קטגוריה'**
  String get pendingCatsTitle;

  /// No description provided for @pendingCatsAiReason.
  ///
  /// In he, this message translates to:
  /// **'נימוק AI'**
  String get pendingCatsAiReason;

  /// No description provided for @profileLoadError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בטעינת הפרופיל'**
  String get profileLoadError;

  /// No description provided for @requestsBestValue.
  ///
  /// In he, this message translates to:
  /// **'תמורה הכי טובה'**
  String get requestsBestValue;

  /// No description provided for @requestsFastResponse.
  ///
  /// In he, this message translates to:
  /// **'תגובה מהירה'**
  String get requestsFastResponse;

  /// No description provided for @requestsInterestedTitle.
  ///
  /// In he, this message translates to:
  /// **'מתעניינים'**
  String get requestsInterestedTitle;

  /// No description provided for @requestsNoInterested.
  ///
  /// In he, this message translates to:
  /// **'אין מתעניינים עדיין'**
  String get requestsNoInterested;

  /// No description provided for @requestsTitle.
  ///
  /// In he, this message translates to:
  /// **'בקשות'**
  String get requestsTitle;

  /// No description provided for @submitDispute.
  ///
  /// In he, this message translates to:
  /// **'שלח מחלוקת'**
  String get submitDispute;

  /// No description provided for @systemWalletFeePanel.
  ///
  /// In he, this message translates to:
  /// **'עמלת פלטפורמה'**
  String get systemWalletFeePanel;

  /// No description provided for @systemWalletInvalidNumber.
  ///
  /// In he, this message translates to:
  /// **'מספר לא תקין'**
  String get systemWalletInvalidNumber;

  /// No description provided for @systemWalletUpdateFee.
  ///
  /// In he, this message translates to:
  /// **'עדכן עמלה'**
  String get systemWalletUpdateFee;

  /// No description provided for @tosAcceptButton.
  ///
  /// In he, this message translates to:
  /// **'אני מסכים/ה'**
  String get tosAcceptButton;

  /// No description provided for @tosBindingNotice.
  ///
  /// In he, this message translates to:
  /// **'בלחיצה על אישור, אתה מסכים לתנאי השימוש'**
  String get tosBindingNotice;

  /// No description provided for @tosFullTitle.
  ///
  /// In he, this message translates to:
  /// **'תנאי שימוש מלאים'**
  String get tosFullTitle;

  /// No description provided for @tosLastUpdated.
  ///
  /// In he, this message translates to:
  /// **'עדכון אחרון'**
  String get tosLastUpdated;

  /// No description provided for @withdrawExistingCert.
  ///
  /// In he, this message translates to:
  /// **'תעודה קיימת'**
  String get withdrawExistingCert;

  /// No description provided for @withdrawUploadError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בהעלאת הקובץ'**
  String get withdrawUploadError;

  /// No description provided for @xpAddAction.
  ///
  /// In he, this message translates to:
  /// **'הוסף'**
  String get xpAddAction;

  /// No description provided for @xpAddEventButton.
  ///
  /// In he, this message translates to:
  /// **'הוסף אירוע'**
  String get xpAddEventButton;

  /// No description provided for @xpAddEventTitle.
  ///
  /// In he, this message translates to:
  /// **'הוספת אירוע XP'**
  String get xpAddEventTitle;

  /// No description provided for @xpDeleteEventTitle.
  ///
  /// In he, this message translates to:
  /// **'מחיקת אירוע'**
  String get xpDeleteEventTitle;

  /// No description provided for @xpEditEventTitle.
  ///
  /// In he, this message translates to:
  /// **'עריכת אירוע XP'**
  String get xpEditEventTitle;

  /// No description provided for @xpEventAdded.
  ///
  /// In he, this message translates to:
  /// **'האירוע נוסף בהצלחה'**
  String get xpEventAdded;

  /// No description provided for @xpEventDeleted.
  ///
  /// In he, this message translates to:
  /// **'האירוע נמחק בהצלחה'**
  String get xpEventDeleted;

  /// No description provided for @xpEventUpdated.
  ///
  /// In he, this message translates to:
  /// **'האירוע עודכן בהצלחה'**
  String get xpEventUpdated;

  /// No description provided for @xpEventsEmpty.
  ///
  /// In he, this message translates to:
  /// **'אין אירועי XP'**
  String get xpEventsEmpty;

  /// No description provided for @xpEventsSection.
  ///
  /// In he, this message translates to:
  /// **'אירועי XP'**
  String get xpEventsSection;

  /// No description provided for @xpFieldDesc.
  ///
  /// In he, this message translates to:
  /// **'תיאור'**
  String get xpFieldDesc;

  /// No description provided for @xpFieldId.
  ///
  /// In he, this message translates to:
  /// **'מזהה'**
  String get xpFieldId;

  /// No description provided for @xpFieldIdHint.
  ///
  /// In he, this message translates to:
  /// **'הזן מזהה ייחודי'**
  String get xpFieldIdHint;

  /// No description provided for @xpFieldName.
  ///
  /// In he, this message translates to:
  /// **'שם'**
  String get xpFieldName;

  /// No description provided for @xpFieldPoints.
  ///
  /// In he, this message translates to:
  /// **'נקודות'**
  String get xpFieldPoints;

  /// No description provided for @xpLevelsError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בשמירת הרמות'**
  String get xpLevelsError;

  /// No description provided for @xpLevelsSaved.
  ///
  /// In he, this message translates to:
  /// **'הרמות נשמרו בהצלחה'**
  String get xpLevelsSaved;

  /// No description provided for @xpLevelsSubtitle.
  ///
  /// In he, this message translates to:
  /// **'הגדר את ספי ה-XP לכל רמה'**
  String get xpLevelsSubtitle;

  /// No description provided for @xpLevelsTitle.
  ///
  /// In he, this message translates to:
  /// **'רמות XP'**
  String get xpLevelsTitle;

  /// No description provided for @xpManagerSubtitle.
  ///
  /// In he, this message translates to:
  /// **'ניהול אירועים ורמות XP'**
  String get xpManagerSubtitle;

  /// No description provided for @xpManagerTitle.
  ///
  /// In he, this message translates to:
  /// **'מנהל XP'**
  String get xpManagerTitle;

  /// No description provided for @xpReservedId.
  ///
  /// In he, this message translates to:
  /// **'מזהה שמור'**
  String get xpReservedId;

  /// No description provided for @xpSaveAction.
  ///
  /// In he, this message translates to:
  /// **'שמור'**
  String get xpSaveAction;

  /// No description provided for @xpSaveLevels.
  ///
  /// In he, this message translates to:
  /// **'שמור רמות'**
  String get xpSaveLevels;

  /// No description provided for @xpTooltipDelete.
  ///
  /// In he, this message translates to:
  /// **'מחק'**
  String get xpTooltipDelete;

  /// No description provided for @xpTooltipEdit.
  ///
  /// In he, this message translates to:
  /// **'ערוך'**
  String get xpTooltipEdit;

  /// No description provided for @bizAiThresholdUpdated.
  ///
  /// In he, this message translates to:
  /// **'הסף עודכן ל-{value}'**
  String bizAiThresholdUpdated(int value);

  /// No description provided for @disputeErrorPrefix.
  ///
  /// In he, this message translates to:
  /// **'שגיאה: {error}'**
  String disputeErrorPrefix(String error);

  /// No description provided for @disputeExistingNote.
  ///
  /// In he, this message translates to:
  /// **'הערת מנהל: {note}'**
  String disputeExistingNote(String note);

  /// No description provided for @disputeOpenedAt.
  ///
  /// In he, this message translates to:
  /// **'נפתח ב-{date}'**
  String disputeOpenedAt(String date);

  /// No description provided for @disputeRefundSublabel.
  ///
  /// In he, this message translates to:
  /// **'החזר מלא — {amount} ₪ ללקוח'**
  String disputeRefundSublabel(String amount);

  /// No description provided for @disputeReleaseSublabel.
  ///
  /// In he, this message translates to:
  /// **'שחרור — {amount} ₪ לספק'**
  String disputeReleaseSublabel(String amount);

  /// No description provided for @disputeSplitSublabel.
  ///
  /// In he, this message translates to:
  /// **'חלוקה — {amount} ₪ לכל צד'**
  String disputeSplitSublabel(String amount);

  /// No description provided for @editCategorySaveError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בשמירה: {error}'**
  String editCategorySaveError(String error);

  /// No description provided for @oppInterestChatMessage.
  ///
  /// In he, this message translates to:
  /// **'שלום, אני {providerName} ואשמח לעזור: {description}'**
  String oppInterestChatMessage(String providerName, String description);

  /// No description provided for @oppNotifBody.
  ///
  /// In he, this message translates to:
  /// **'{providerName} מעוניין בהזדמנות שלך'**
  String oppNotifBody(String providerName);

  /// No description provided for @pendingCatsErrorPrefix.
  ///
  /// In he, this message translates to:
  /// **'שגיאה: {error}'**
  String pendingCatsErrorPrefix(String error);

  /// No description provided for @pendingCatsSubCategory.
  ///
  /// In he, this message translates to:
  /// **'תת-קטגוריה: {name}'**
  String pendingCatsSubCategory(String name);

  /// No description provided for @xpDeleteEventConfirm.
  ///
  /// In he, this message translates to:
  /// **'למחוק את {name}?'**
  String xpDeleteEventConfirm(String name);

  /// No description provided for @xpErrorPrefix.
  ///
  /// In he, this message translates to:
  /// **'שגיאה: {error}'**
  String xpErrorPrefix(String error);

  /// No description provided for @xpEventsCount.
  ///
  /// In he, this message translates to:
  /// **'{count} אירועים'**
  String xpEventsCount(int count);
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['ar', 'en', 'es', 'he'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar': return AppLocalizationsAr();
    case 'en': return AppLocalizationsEn();
    case 'es': return AppLocalizationsEs();
    case 'he': return AppLocalizationsHe();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
