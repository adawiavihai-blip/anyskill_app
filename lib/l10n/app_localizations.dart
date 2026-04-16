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
  /// **'התשלום אושר ומאובטח עד לסיום העסקה'**
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

  /// No description provided for @phoneLoginHeader.
  ///
  /// In he, this message translates to:
  /// **'כניסה / הרשמה'**
  String get phoneLoginHeader;

  /// No description provided for @phoneLoginSubtitleSimple.
  ///
  /// In he, this message translates to:
  /// **'הזן את מספר הטלפון שלך ונשלח קוד אימות'**
  String get phoneLoginSubtitleSimple;

  /// No description provided for @phoneLoginSubtitleSocial.
  ///
  /// In he, this message translates to:
  /// **'התחבר/י עם Google, Apple או מספר טלפון'**
  String get phoneLoginSubtitleSocial;

  /// No description provided for @phoneLoginOrDivider.
  ///
  /// In he, this message translates to:
  /// **'או'**
  String get phoneLoginOrDivider;

  /// No description provided for @phoneLoginPhoneHint.
  ///
  /// In he, this message translates to:
  /// **'מספר טלפון'**
  String get phoneLoginPhoneHint;

  /// No description provided for @phoneLoginSendCode.
  ///
  /// In he, this message translates to:
  /// **'שלח קוד אימות'**
  String get phoneLoginSendCode;

  /// No description provided for @phoneLoginHeroSubtitle.
  ///
  /// In he, this message translates to:
  /// **'כניסה מהירה עם מספר טלפון'**
  String get phoneLoginHeroSubtitle;

  /// No description provided for @phoneLoginChipSecure.
  ///
  /// In he, this message translates to:
  /// **'מאובטח'**
  String get phoneLoginChipSecure;

  /// No description provided for @phoneLoginChipFast.
  ///
  /// In he, this message translates to:
  /// **'מהיר'**
  String get phoneLoginChipFast;

  /// No description provided for @phoneLoginChipReliable.
  ///
  /// In he, this message translates to:
  /// **'אמין'**
  String get phoneLoginChipReliable;

  /// No description provided for @phoneLoginSelectCountry.
  ///
  /// In he, this message translates to:
  /// **'בחר מדינה'**
  String get phoneLoginSelectCountry;

  /// No description provided for @otpEnter6Digits.
  ///
  /// In he, this message translates to:
  /// **'הזן את 6 הספרות'**
  String get otpEnter6Digits;

  /// No description provided for @otpVerifyError.
  ///
  /// In he, this message translates to:
  /// **'שגיאת אימות. נסה שוב.'**
  String get otpVerifyError;

  /// No description provided for @otpErrorInvalidCode.
  ///
  /// In he, this message translates to:
  /// **'קוד שגוי. נסה שוב.'**
  String get otpErrorInvalidCode;

  /// No description provided for @otpErrorSessionExpired.
  ///
  /// In he, this message translates to:
  /// **'הקוד פג תוקף. בקש קוד חדש.'**
  String get otpErrorSessionExpired;

  /// No description provided for @otpErrorTooManyRequests.
  ///
  /// In he, this message translates to:
  /// **'יותר מדי ניסיונות. נסה מאוחר יותר.'**
  String get otpErrorTooManyRequests;

  /// No description provided for @otpErrorPrefix.
  ///
  /// In he, this message translates to:
  /// **'שגיאה: {code}'**
  String otpErrorPrefix(String code);

  /// No description provided for @otpTitle.
  ///
  /// In he, this message translates to:
  /// **'הזן קוד אימות'**
  String get otpTitle;

  /// No description provided for @otpSubtitle.
  ///
  /// In he, this message translates to:
  /// **'שלחנו קוד SMS ל-{phone}'**
  String otpSubtitle(String phone);

  /// No description provided for @otpAutoFilled.
  ///
  /// In he, this message translates to:
  /// **'מולא אוטומטית'**
  String get otpAutoFilled;

  /// No description provided for @otpResendIn.
  ///
  /// In he, this message translates to:
  /// **'שלח קוד חדש בעוד '**
  String get otpResendIn;

  /// No description provided for @otpResendNow.
  ///
  /// In he, this message translates to:
  /// **'שלח קוד חדש'**
  String get otpResendNow;

  /// No description provided for @otpVerifyButton.
  ///
  /// In he, this message translates to:
  /// **'אמת ועבור'**
  String get otpVerifyButton;

  /// No description provided for @otpExistingAccountTitle.
  ///
  /// In he, this message translates to:
  /// **'נמצא חשבון קיים'**
  String get otpExistingAccountTitle;

  /// No description provided for @otpExistingAccountBody.
  ///
  /// In he, this message translates to:
  /// **'למספר הטלפון הזה כבר יש חשבון במערכת שנוצר דרך מייל/סיסמה.\n\nכדי לחבר אותו לכניסה בטלפון, יש צורך בפעולה חד-פעמית של המנהל.\n\nאנא פנה/י לתמיכה ונחבר את החשבון עבורך.'**
  String get otpExistingAccountBody;

  /// No description provided for @otpUnderstood.
  ///
  /// In he, this message translates to:
  /// **'הבנתי'**
  String get otpUnderstood;

  /// No description provided for @otpCreateProfileError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה ביצירת פרופיל: {error}'**
  String otpCreateProfileError(String error);

  /// No description provided for @otpWelcomeTitle.
  ///
  /// In he, this message translates to:
  /// **'ברוך הבא ל-AnySkill! 👋'**
  String get otpWelcomeTitle;

  /// No description provided for @otpWelcomeSubtitle.
  ///
  /// In he, this message translates to:
  /// **'בחר כיצד תרצה להשתמש באפליקציה'**
  String get otpWelcomeSubtitle;

  /// No description provided for @otpTermsPrefix.
  ///
  /// In he, this message translates to:
  /// **'אני מאשר/ת שקראתי והסכמתי ל-'**
  String get otpTermsPrefix;

  /// No description provided for @otpTermsOfService.
  ///
  /// In he, this message translates to:
  /// **'תנאי השימוש'**
  String get otpTermsOfService;

  /// No description provided for @otpPrivacyPolicy.
  ///
  /// In he, this message translates to:
  /// **'מדיניות הפרטיות'**
  String get otpPrivacyPolicy;

  /// No description provided for @otpRoleCustomer.
  ///
  /// In he, this message translates to:
  /// **'לקוח'**
  String get otpRoleCustomer;

  /// No description provided for @otpRoleCustomerDesc.
  ///
  /// In he, this message translates to:
  /// **'מחפש שירותים מקצועיים\nומזמין ספקים'**
  String get otpRoleCustomerDesc;

  /// No description provided for @otpRoleProvider.
  ///
  /// In he, this message translates to:
  /// **'נותן שירות'**
  String get otpRoleProvider;

  /// No description provided for @otpRoleProviderDesc.
  ///
  /// In he, this message translates to:
  /// **'מציע שירותים מקצועיים\nומרוויח דרך AnySkill'**
  String get otpRoleProviderDesc;

  /// No description provided for @otpRoleProviderBadge.
  ///
  /// In he, this message translates to:
  /// **'ממתין לאישור מנהל'**
  String get otpRoleProviderBadge;

  /// No description provided for @onbValEnterName.
  ///
  /// In he, this message translates to:
  /// **'נא להזין שם מלא'**
  String get onbValEnterName;

  /// No description provided for @onbValEnterPhone.
  ///
  /// In he, this message translates to:
  /// **'נא להזין מספר טלפון'**
  String get onbValEnterPhone;

  /// No description provided for @onbValEnterEmail.
  ///
  /// In he, this message translates to:
  /// **'נא להזין כתובת אימייל'**
  String get onbValEnterEmail;

  /// No description provided for @onbValUploadProfile.
  ///
  /// In he, this message translates to:
  /// **'נא להעלות תמונת פרופיל'**
  String get onbValUploadProfile;

  /// No description provided for @onbValChooseBusiness.
  ///
  /// In he, this message translates to:
  /// **'נא לבחור סוג עסק'**
  String get onbValChooseBusiness;

  /// No description provided for @onbValEnterId.
  ///
  /// In he, this message translates to:
  /// **'נא להזין מספר ת.ז. / ח.פ.'**
  String get onbValEnterId;

  /// No description provided for @onbValUploadId.
  ///
  /// In he, this message translates to:
  /// **'נא להעלות צילום תעודת זהות או דרכון'**
  String get onbValUploadId;

  /// No description provided for @onbValChooseCategory.
  ///
  /// In he, this message translates to:
  /// **'נא לבחור קטגוריה מקצועית'**
  String get onbValChooseCategory;

  /// No description provided for @onbValExpertise.
  ///
  /// In he, this message translates to:
  /// **'נא לפרט את תחום המומחיות שלך'**
  String get onbValExpertise;

  /// No description provided for @onbValAcceptTerms.
  ///
  /// In he, this message translates to:
  /// **'יש לקרוא ולאשר את תנאי השימוש'**
  String get onbValAcceptTerms;

  /// No description provided for @onbSaveError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בשמירה: {error}'**
  String onbSaveError(String error);

  /// No description provided for @onbUploadError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בהעלאה: {error}'**
  String onbUploadError(String error);

  /// No description provided for @onbCameraError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בצילום: {error}'**
  String onbCameraError(String error);

  /// No description provided for @onbToastProvider.
  ///
  /// In he, this message translates to:
  /// **'איזה כיף שהצטרפת לנבחרת אנשי המקצוע של AnySkill! 🚀 המסמכים שלך התקבלו ובביקורת. תקבל עדכון ברגע שהחשבון יאושר.'**
  String get onbToastProvider;

  /// No description provided for @onbToastCustomer.
  ///
  /// In he, this message translates to:
  /// **'ברוכים הבאים ל-AnySkill! 🌟 צריכים עזרה במשהו? הגעתם למקום הנכון. אלפי אנשי מקצוע זמינים עבורכם עכשיו.'**
  String get onbToastCustomer;

  /// No description provided for @onbStepRole.
  ///
  /// In he, this message translates to:
  /// **'בחר תפקיד'**
  String get onbStepRole;

  /// No description provided for @onbStepBusiness.
  ///
  /// In he, this message translates to:
  /// **'פרטים עסקיים'**
  String get onbStepBusiness;

  /// No description provided for @onbStepService.
  ///
  /// In he, this message translates to:
  /// **'תחום שירות'**
  String get onbStepService;

  /// No description provided for @onbStepContact.
  ///
  /// In he, this message translates to:
  /// **'פרטי קשר'**
  String get onbStepContact;

  /// No description provided for @onbStepProfile.
  ///
  /// In he, this message translates to:
  /// **'הפרופיל שלך'**
  String get onbStepProfile;

  /// No description provided for @onbProgressComplete.
  ///
  /// In he, this message translates to:
  /// **'הכל מוכן!'**
  String get onbProgressComplete;

  /// No description provided for @onbProgressIncomplete.
  ///
  /// In he, this message translates to:
  /// **'השלם את הפרטים'**
  String get onbProgressIncomplete;

  /// No description provided for @onbGreeting.
  ///
  /// In he, this message translates to:
  /// **'היי {name},'**
  String onbGreeting(String name);

  /// No description provided for @onbGreetingFallback.
  ///
  /// In he, this message translates to:
  /// **'היי,'**
  String get onbGreetingFallback;

  /// No description provided for @onbIntroLine.
  ///
  /// In he, this message translates to:
  /// **'עוד רגע מתחילים. ספר לנו קצת על עצמך.'**
  String get onbIntroLine;

  /// No description provided for @onbSocialProof.
  ///
  /// In he, this message translates to:
  /// **'מעל 250 אנשי מקצוע הצטרפו החודש'**
  String get onbSocialProof;

  /// No description provided for @onbRoleCustomerTitle.
  ///
  /// In he, this message translates to:
  /// **'אני מחפש שירות'**
  String get onbRoleCustomerTitle;

  /// No description provided for @onbRoleCustomerSubtitle.
  ///
  /// In he, this message translates to:
  /// **'אני רוצה למצוא איש מקצוע'**
  String get onbRoleCustomerSubtitle;

  /// No description provided for @onbRoleProviderTitle.
  ///
  /// In he, this message translates to:
  /// **'אני רוצה לתת שירות'**
  String get onbRoleProviderTitle;

  /// No description provided for @onbRoleProviderSubtitle.
  ///
  /// In he, this message translates to:
  /// **'ברצוני לעבוד דרך AnySkill'**
  String get onbRoleProviderSubtitle;

  /// No description provided for @onbBusinessTypeHint.
  ///
  /// In he, this message translates to:
  /// **'סוג עסק'**
  String get onbBusinessTypeHint;

  /// No description provided for @onbUploadBusinessDocLabel.
  ///
  /// In he, this message translates to:
  /// **'העלה צילום תעודת עוסק (פטור/מורשה/חברה)'**
  String get onbUploadBusinessDocLabel;

  /// No description provided for @onbIdLabel.
  ///
  /// In he, this message translates to:
  /// **'מספר תעודת זהות / ח.פ.'**
  String get onbIdLabel;

  /// No description provided for @onbIdHint.
  ///
  /// In he, this message translates to:
  /// **'הזן מספר ת.ז. או ח.פ.'**
  String get onbIdHint;

  /// No description provided for @onbUploadIdLabel.
  ///
  /// In he, this message translates to:
  /// **'העלה צילום תעודת זהות או דרכון'**
  String get onbUploadIdLabel;

  /// No description provided for @onbSelfieTitle.
  ///
  /// In he, this message translates to:
  /// **'סלפי לאימות זהות'**
  String get onbSelfieTitle;

  /// No description provided for @onbSelfieSuccess.
  ///
  /// In he, this message translates to:
  /// **'תמונה צולמה בהצלחה ✓'**
  String get onbSelfieSuccess;

  /// No description provided for @onbSelfiePrompt.
  ///
  /// In he, this message translates to:
  /// **'צלם תמונה חיה של הפנים שלך'**
  String get onbSelfiePrompt;

  /// No description provided for @onbSelfieRetake.
  ///
  /// In he, this message translates to:
  /// **'צלם שוב'**
  String get onbSelfieRetake;

  /// No description provided for @onbSelfieTake.
  ///
  /// In he, this message translates to:
  /// **'צלם סלפי'**
  String get onbSelfieTake;

  /// No description provided for @onbCategoryOther.
  ///
  /// In he, this message translates to:
  /// **'אחר / לא מצאתי'**
  String get onbCategoryOther;

  /// No description provided for @onbCategoryHint.
  ///
  /// In he, this message translates to:
  /// **'בחר קטגוריה ראשית'**
  String get onbCategoryHint;

  /// No description provided for @onbSubCategoryHint.
  ///
  /// In he, this message translates to:
  /// **'בחר תת-קטגוריה'**
  String get onbSubCategoryHint;

  /// No description provided for @onbExpertiseLabel.
  ///
  /// In he, this message translates to:
  /// **'פרט את תחום המומחיות שלך'**
  String get onbExpertiseLabel;

  /// No description provided for @onbExpertiseHint.
  ///
  /// In he, this message translates to:
  /// **'עד 30 תווים'**
  String get onbExpertiseHint;

  /// No description provided for @onbOtherCategoryNote.
  ///
  /// In he, this message translates to:
  /// **'צוות AnySkill יבחן את הפרטים וישייך אותך לקטגוריה המתאימה'**
  String get onbOtherCategoryNote;

  /// No description provided for @onbFullNameLabel.
  ///
  /// In he, this message translates to:
  /// **'שם מלא *'**
  String get onbFullNameLabel;

  /// No description provided for @onbFullNameHint.
  ///
  /// In he, this message translates to:
  /// **'השם שיוצג בפרופיל'**
  String get onbFullNameHint;

  /// No description provided for @onbPhoneLabel.
  ///
  /// In he, this message translates to:
  /// **'מספר טלפון *'**
  String get onbPhoneLabel;

  /// No description provided for @onbEmailLabel.
  ///
  /// In he, this message translates to:
  /// **'אימייל *'**
  String get onbEmailLabel;

  /// No description provided for @onbReplacePhoto.
  ///
  /// In he, this message translates to:
  /// **'לחץ להחלפה'**
  String get onbReplacePhoto;

  /// No description provided for @onbAddPhoto.
  ///
  /// In he, this message translates to:
  /// **'הוסף תמונת פרופיל'**
  String get onbAddPhoto;

  /// No description provided for @onbAboutLabel.
  ///
  /// In he, this message translates to:
  /// **'ספר על עצמך'**
  String get onbAboutLabel;

  /// No description provided for @onbAboutHintProvider.
  ///
  /// In he, this message translates to:
  /// **'ניסיון, כישורים, התמחויות...'**
  String get onbAboutHintProvider;

  /// No description provided for @onbAboutHintCustomer.
  ///
  /// In he, this message translates to:
  /// **'מה תרצה שנדע עליך?'**
  String get onbAboutHintCustomer;

  /// No description provided for @onbTermsTitle.
  ///
  /// In he, this message translates to:
  /// **'קרא את תנאי השימוש ומדיניות הפרטיות'**
  String get onbTermsTitle;

  /// No description provided for @onbTermsRead.
  ///
  /// In he, this message translates to:
  /// **'נקרא'**
  String get onbTermsRead;

  /// No description provided for @onbTermsAccept.
  ///
  /// In he, this message translates to:
  /// **'אני מאשר/ת שקראתי והסכמתי לתנאי השימוש ולמדיניות הפרטיות של AnySkill'**
  String get onbTermsAccept;

  /// No description provided for @onbFinish.
  ///
  /// In he, this message translates to:
  /// **'סיום הרשמה'**
  String get onbFinish;

  /// No description provided for @onbRequiredField.
  ///
  /// In he, this message translates to:
  /// **'שדה חובה *'**
  String get onbRequiredField;

  /// No description provided for @onbNotSpecified.
  ///
  /// In he, this message translates to:
  /// **'לא צוין'**
  String get onbNotSpecified;

  /// No description provided for @onbUserTypeProvider.
  ///
  /// In he, this message translates to:
  /// **'נותן שירות (ספק)'**
  String get onbUserTypeProvider;

  /// No description provided for @onbUserTypeCustomer.
  ///
  /// In he, this message translates to:
  /// **'לקוח'**
  String get onbUserTypeCustomer;

  /// No description provided for @onbBizExempt.
  ///
  /// In he, this message translates to:
  /// **'עוסק פטור'**
  String get onbBizExempt;

  /// No description provided for @onbBizAuthorized.
  ///
  /// In he, this message translates to:
  /// **'עוסק מורשה'**
  String get onbBizAuthorized;

  /// No description provided for @onbBizCompany.
  ///
  /// In he, this message translates to:
  /// **'חברה בע\"מ'**
  String get onbBizCompany;

  /// No description provided for @onbBizExternal.
  ///
  /// In he, this message translates to:
  /// **'שכיר המוציא חשבונית דרך חברה חיצונית'**
  String get onbBizExternal;

  /// No description provided for @profNoGooglePhoto.
  ///
  /// In he, this message translates to:
  /// **'לא נמצאה תמונת פרופיל בחשבון Google'**
  String get profNoGooglePhoto;

  /// No description provided for @profPhotoUpdatedFromGoogle.
  ///
  /// In he, this message translates to:
  /// **'תמונת פרופיל עודכנה מ-Google'**
  String get profPhotoUpdatedFromGoogle;

  /// No description provided for @profInvoiceEmailOn.
  ///
  /// In he, this message translates to:
  /// **'חשבוניות יישלחו אליך במייל'**
  String get profInvoiceEmailOn;

  /// No description provided for @profInvoiceEmailOff.
  ///
  /// In he, this message translates to:
  /// **'החשבוניות לא יישלחו יותר למייל שלך'**
  String get profInvoiceEmailOff;

  /// No description provided for @profSaveError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בשמירה: {error}'**
  String profSaveError(String error);

  /// No description provided for @profInvoiceEmailTitle.
  ///
  /// In he, this message translates to:
  /// **'קבלת חשבוניות במייל'**
  String get profInvoiceEmailTitle;

  /// No description provided for @profInvoiceEmailSubOn.
  ///
  /// In he, this message translates to:
  /// **'תקבל חשבונית במייל אחרי כל עסקה'**
  String get profInvoiceEmailSubOn;

  /// No description provided for @profInvoiceEmailSubOff.
  ///
  /// In he, this message translates to:
  /// **'לא תקבל חשבוניות במייל'**
  String get profInvoiceEmailSubOff;

  /// No description provided for @profSyncGooglePhoto.
  ///
  /// In he, this message translates to:
  /// **'סנכרן תמונה מ-Google'**
  String get profSyncGooglePhoto;

  /// No description provided for @profProviderRole.
  ///
  /// In he, this message translates to:
  /// **'נותן שירות'**
  String get profProviderRole;

  /// No description provided for @profJobsStat.
  ///
  /// In he, this message translates to:
  /// **'עבודות'**
  String get profJobsStat;

  /// No description provided for @profRatingStat.
  ///
  /// In he, this message translates to:
  /// **'דירוג'**
  String get profRatingStat;

  /// No description provided for @profReviewsStat.
  ///
  /// In he, this message translates to:
  /// **'ביקורות'**
  String get profReviewsStat;

  /// No description provided for @profAngelBadge.
  ///
  /// In he, this message translates to:
  /// **'מלאך הקהילה'**
  String get profAngelBadge;

  /// No description provided for @profPillarBadge.
  ///
  /// In he, this message translates to:
  /// **'עמוד תווך'**
  String get profPillarBadge;

  /// No description provided for @profStarterBadge.
  ///
  /// In he, this message translates to:
  /// **'מתנדב פעיל'**
  String get profStarterBadge;

  /// No description provided for @profWorkGallery.
  ///
  /// In he, this message translates to:
  /// **'גלריית עבודות'**
  String get profWorkGallery;

  /// No description provided for @profVipActive.
  ///
  /// In he, this message translates to:
  /// **'VIP פעיל'**
  String get profVipActive;

  /// No description provided for @profJoinVip.
  ///
  /// In he, this message translates to:
  /// **'הצטרף ל-VIP'**
  String get profJoinVip;

  /// No description provided for @profVideoIntro.
  ///
  /// In he, this message translates to:
  /// **'היכרות בווידאו'**
  String get profVideoIntro;

  /// No description provided for @profMyDogs.
  ///
  /// In he, this message translates to:
  /// **'הכלבים שלי'**
  String get profMyDogs;

  /// No description provided for @profMyDogsSubtitle.
  ///
  /// In he, this message translates to:
  /// **'פרופיל אחד → כל ההזמנות'**
  String get profMyDogsSubtitle;

  /// No description provided for @profJoinAsProvider.
  ///
  /// In he, this message translates to:
  /// **'להצטרפות ל-AnySkill כנותן שירות'**
  String get profJoinAsProvider;

  /// No description provided for @profRequestInReview.
  ///
  /// In he, this message translates to:
  /// **'הבקשה שלך בבדיקה — נעדכן בהקדם'**
  String get profRequestInReview;

  /// No description provided for @profTermsOfService.
  ///
  /// In he, this message translates to:
  /// **'תנאי שימוש'**
  String get profTermsOfService;

  /// No description provided for @profPrivacyPolicy.
  ///
  /// In he, this message translates to:
  /// **'מדיניות פרטיות'**
  String get profPrivacyPolicy;

  /// No description provided for @profSwitchRole.
  ///
  /// In he, this message translates to:
  /// **'החלף תפקיד'**
  String get profSwitchRole;

  /// No description provided for @profLogout.
  ///
  /// In he, this message translates to:
  /// **'התנתקות'**
  String get profLogout;

  /// No description provided for @profDeleteAccount.
  ///
  /// In he, this message translates to:
  /// **'מחיקת חשבון'**
  String get profDeleteAccount;

  /// No description provided for @profTitle.
  ///
  /// In he, this message translates to:
  /// **'פרופיל'**
  String get profTitle;

  /// No description provided for @profCustomerRole.
  ///
  /// In he, this message translates to:
  /// **'לקוח/ה'**
  String get profCustomerRole;

  /// No description provided for @profStatServicesTaken.
  ///
  /// In he, this message translates to:
  /// **'שירותים שנלקחו'**
  String get profStatServicesTaken;

  /// No description provided for @profStatReviews.
  ///
  /// In he, this message translates to:
  /// **'ביקורות'**
  String get profStatReviews;

  /// No description provided for @profStatYears.
  ///
  /// In he, this message translates to:
  /// **'שנים ב-AnySkill'**
  String get profStatYears;

  /// No description provided for @profReceivedService.
  ///
  /// In he, this message translates to:
  /// **'שירות שהתקבל'**
  String get profReceivedService;

  /// No description provided for @profFavorites.
  ///
  /// In he, this message translates to:
  /// **'מועדפים'**
  String get profFavorites;

  /// No description provided for @profDeleteConfirmBody.
  ///
  /// In he, this message translates to:
  /// **'האם אתה בטוח שברצונך למחוק את חשבונך?\n\nכל הנתונים — ההיסטוריה, הארנק, הצ׳אטים — ימחקו לצמיתות.\n\nפעולה זו אינה הפיכה.'**
  String get profDeleteConfirmBody;

  /// No description provided for @profCancel.
  ///
  /// In he, this message translates to:
  /// **'ביטול'**
  String get profCancel;

  /// No description provided for @profContinue.
  ///
  /// In he, this message translates to:
  /// **'המשך'**
  String get profContinue;

  /// No description provided for @profFinalConfirm.
  ///
  /// In he, this message translates to:
  /// **'אישור סופי'**
  String get profFinalConfirm;

  /// No description provided for @profDeleteFinalBody.
  ///
  /// In he, this message translates to:
  /// **'לאחר האישור, חשבונך ימחק לצמיתות ולא ניתן יהיה לשחזרו.'**
  String get profDeleteFinalBody;

  /// No description provided for @profDeletePermanent.
  ///
  /// In he, this message translates to:
  /// **'מחק לצמיתות'**
  String get profDeletePermanent;

  /// No description provided for @profReauthNeeded.
  ///
  /// In he, this message translates to:
  /// **'נדרשת כניסה מחדש'**
  String get profReauthNeeded;

  /// No description provided for @profReauthBody.
  ///
  /// In he, this message translates to:
  /// **'לצורך מחיקת חשבון, Firebase דורש שנכנסת לאחרונה.\n\nאנא התנתק, היכנס מחדש ונסה שוב.'**
  String get profReauthBody;

  /// No description provided for @profLogoutAndReauth.
  ///
  /// In he, this message translates to:
  /// **'התנתק והיכנס מחדש'**
  String get profLogoutAndReauth;

  /// No description provided for @profDeleteError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה במחיקת החשבון: {error}'**
  String profDeleteError(String error);

  /// No description provided for @profNoWorksYet.
  ///
  /// In he, this message translates to:
  /// **'עדיין לא העלית עבודות.\nלחץ על העיפרון כדי לעדכן!'**
  String get profNoWorksYet;

  /// No description provided for @homeTestEmailSent.
  ///
  /// In he, this message translates to:
  /// **'מייל בדיקה נשלח! בדוק את תיבת הדואר.'**
  String get homeTestEmailSent;

  /// No description provided for @homeGenericError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה: {error}'**
  String homeGenericError(String error);

  /// No description provided for @homeShowAll.
  ///
  /// In he, this message translates to:
  /// **'הצג הכל'**
  String get homeShowAll;

  /// No description provided for @homeMicroTasks.
  ///
  /// In he, this message translates to:
  /// **'משימות מיקרו — הרווח מהיר'**
  String get homeMicroTasks;

  /// No description provided for @homeCommunityTitle.
  ///
  /// In he, this message translates to:
  /// **'נתינה מהלב'**
  String get homeCommunityTitle;

  /// No description provided for @homeCommunitySlogan.
  ///
  /// In he, this message translates to:
  /// **'כישרון אחד, לב אחד'**
  String get homeCommunitySlogan;

  /// No description provided for @homeDefaultExpert.
  ///
  /// In he, this message translates to:
  /// **'המומחה'**
  String get homeDefaultExpert;

  /// No description provided for @homeDefaultReengageMsg.
  ///
  /// In he, this message translates to:
  /// **'מוכן להזמין שוב?'**
  String get homeDefaultReengageMsg;

  /// No description provided for @homeSmartOffer.
  ///
  /// In he, this message translates to:
  /// **'הצעה חכמה'**
  String get homeSmartOffer;

  /// No description provided for @homeBookNow.
  ///
  /// In he, this message translates to:
  /// **'הזמן עכשיו'**
  String get homeBookNow;

  /// No description provided for @homeWelcomeTitle.
  ///
  /// In he, this message translates to:
  /// **'ברוכים הבאים ל-AnySkill'**
  String get homeWelcomeTitle;

  /// No description provided for @homeWelcomeSubtitle.
  ///
  /// In he, this message translates to:
  /// **'מצא מומחים מהשכונה שלך'**
  String get homeWelcomeSubtitle;

  /// No description provided for @homeServiceTitle.
  ///
  /// In he, this message translates to:
  /// **'שירות מקצועי בלחיצה אחת'**
  String get homeServiceTitle;

  /// No description provided for @homeServiceSubtitle.
  ///
  /// In he, this message translates to:
  /// **'שיפוצים • ניקיון • צילום ועוד'**
  String get homeServiceSubtitle;

  /// No description provided for @homeBecomeExpertTitle.
  ///
  /// In he, this message translates to:
  /// **'הפוך למומחה היום'**
  String get homeBecomeExpertTitle;

  /// No description provided for @homeBecomeExpertSubtitle.
  ///
  /// In he, this message translates to:
  /// **'פרסם את השירות שלך והתחל להרוויח'**
  String get homeBecomeExpertSubtitle;

  /// No description provided for @notifGenericError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה: {error}'**
  String notifGenericError(String error);

  /// No description provided for @notifDefaultClient.
  ///
  /// In he, this message translates to:
  /// **'לקוח'**
  String get notifDefaultClient;

  /// No description provided for @notifUrgentJobAvailable.
  ///
  /// In he, this message translates to:
  /// **'משרה דחופה זמינה!'**
  String get notifUrgentJobAvailable;

  /// No description provided for @notifJobTaken.
  ///
  /// In he, this message translates to:
  /// **'המשרה נתפסה'**
  String get notifJobTaken;

  /// No description provided for @notifJobExpired.
  ///
  /// In he, this message translates to:
  /// **'המשרה פגה תוקף'**
  String get notifJobExpired;

  /// No description provided for @notifGrabNow.
  ///
  /// In he, this message translates to:
  /// **'תפוס עכשיו!'**
  String get notifGrabNow;

  /// No description provided for @notifTakenBy.
  ///
  /// In he, this message translates to:
  /// **'המשרה נתפסה ע\"י {name}'**
  String notifTakenBy(String name);

  /// No description provided for @notifCommunityHelpTitle.
  ///
  /// In he, this message translates to:
  /// **'בקשת עזרה מהקהילה'**
  String get notifCommunityHelpTitle;

  /// No description provided for @notifNotNow.
  ///
  /// In he, this message translates to:
  /// **'לא עכשיו'**
  String get notifNotNow;

  /// No description provided for @notifWantToHelp.
  ///
  /// In he, this message translates to:
  /// **'אני רוצה לעזור!'**
  String get notifWantToHelp;

  /// No description provided for @notifCantAccept.
  ///
  /// In he, this message translates to:
  /// **'לא ניתן לקבל בקשה זו'**
  String get notifCantAccept;

  /// No description provided for @notifAccepted.
  ///
  /// In he, this message translates to:
  /// **'✓ קיבלת את הבקשה! נפתח צ\'אט עם הלקוח'**
  String get notifAccepted;

  /// No description provided for @notifLoadError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בטעינת ההתראות'**
  String get notifLoadError;

  /// No description provided for @notifEmptyNow.
  ///
  /// In he, this message translates to:
  /// **'אין כרגע התראות'**
  String get notifEmptyNow;

  /// No description provided for @chatUnknown.
  ///
  /// In he, this message translates to:
  /// **'לא ידוע'**
  String get chatUnknown;

  /// No description provided for @chatSafetyWarning.
  ///
  /// In he, this message translates to:
  /// **'שימו לב: למען ביטחונכם, אין להחליף מספרי טלפון או לסגור עסקאות מחוץ לאפליקציה.'**
  String get chatSafetyWarning;

  /// No description provided for @chatNoInternet.
  ///
  /// In he, this message translates to:
  /// **'אין חיבור לאינטרנט.'**
  String get chatNoInternet;

  /// No description provided for @chatDefaultCustomer.
  ///
  /// In he, this message translates to:
  /// **'לקוח'**
  String get chatDefaultCustomer;

  /// No description provided for @chatPaymentRequest.
  ///
  /// In he, this message translates to:
  /// **'בקשת תשלום'**
  String get chatPaymentRequest;

  /// No description provided for @chatAmountLabel.
  ///
  /// In he, this message translates to:
  /// **'סכום'**
  String get chatAmountLabel;

  /// No description provided for @chatServiceDescLabel.
  ///
  /// In he, this message translates to:
  /// **'תיאור השירות'**
  String get chatServiceDescLabel;

  /// No description provided for @chatSend.
  ///
  /// In he, this message translates to:
  /// **'שלח'**
  String get chatSend;

  /// No description provided for @chatQuoteSent.
  ///
  /// In he, this message translates to:
  /// **'הצעת המחיר נשלחה בהצלחה ✅'**
  String get chatQuoteSent;

  /// No description provided for @chatQuoteError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בשליחת ההצעה. נסה שוב.'**
  String get chatQuoteError;

  /// No description provided for @chatOfficialQuote.
  ///
  /// In he, this message translates to:
  /// **'הצעת מחיר רשמית'**
  String get chatOfficialQuote;

  /// No description provided for @chatQuoteDescHint.
  ///
  /// In he, this message translates to:
  /// **'פרט את השירות הכלול במחיר...'**
  String get chatQuoteDescHint;

  /// No description provided for @chatEscrowNote.
  ///
  /// In he, this message translates to:
  /// **'הסכום ינעל בנאמנות AnySkill עם אישור הלקוח'**
  String get chatEscrowNote;

  /// No description provided for @chatSendQuote.
  ///
  /// In he, this message translates to:
  /// **'שלח הצעה'**
  String get chatSendQuote;

  /// No description provided for @chatQuoteLabel.
  ///
  /// In he, this message translates to:
  /// **'הצעת מחיר'**
  String get chatQuoteLabel;

  /// No description provided for @chatOnMyWay.
  ///
  /// In he, this message translates to:
  /// **'אני בדרך! 🚗 אגיע בקרוב.'**
  String get chatOnMyWay;

  /// No description provided for @chatWorkDone.
  ///
  /// In he, this message translates to:
  /// **'סיימתי את העבודה! ✅'**
  String get chatWorkDone;

  /// No description provided for @expCantBookSelf.
  ///
  /// In he, this message translates to:
  /// **'לא ניתן להזמין שירות מעצמך'**
  String get expCantBookSelf;

  /// No description provided for @expSlotTakenTitle.
  ///
  /// In he, this message translates to:
  /// **'המועד תפוס'**
  String get expSlotTakenTitle;

  /// No description provided for @expSlotTakenBody.
  ///
  /// In he, this message translates to:
  /// **'מישהו כבר הזמין את המומחה לאותו מועד.\nאנא בחר תאריך או שעה אחרים.'**
  String get expSlotTakenBody;

  /// No description provided for @expUnderstood.
  ///
  /// In he, this message translates to:
  /// **'הבנתי'**
  String get expUnderstood;

  /// No description provided for @expBookingError.
  ///
  /// In he, this message translates to:
  /// **'חלה שגיאה בתהליך ההזמנה, אנא נסה שנית.'**
  String get expBookingError;

  /// No description provided for @expDefaultCustomer.
  ///
  /// In he, this message translates to:
  /// **'לקוח'**
  String get expDefaultCustomer;

  /// No description provided for @expDemoBookingMsg.
  ///
  /// In he, this message translates to:
  /// **'הזמנת את {name}. אנחנו מעדכנים אותך כשנותן השירות פנוי.'**
  String expDemoBookingMsg(String name);

  /// No description provided for @expOptionalAddons.
  ///
  /// In he, this message translates to:
  /// **'תוספות אופציונליות'**
  String get expOptionalAddons;

  /// No description provided for @expProviderDayOff.
  ///
  /// In he, this message translates to:
  /// **'הספק לא עובד ביום הזה'**
  String get expProviderDayOff;

  /// No description provided for @expAnonymous.
  ///
  /// In he, this message translates to:
  /// **'אנונימי'**
  String get expAnonymous;

  /// No description provided for @expRatingProfessional.
  ///
  /// In he, this message translates to:
  /// **'מקצועיות'**
  String get expRatingProfessional;

  /// No description provided for @expRatingTiming.
  ///
  /// In he, this message translates to:
  /// **'עמידה בזמנים'**
  String get expRatingTiming;

  /// No description provided for @expRatingCommunication.
  ///
  /// In he, this message translates to:
  /// **'תקשורת'**
  String get expRatingCommunication;

  /// No description provided for @expSearchReviewsHint.
  ///
  /// In he, this message translates to:
  /// **'חפש בביקורות...'**
  String get expSearchReviewsHint;

  /// No description provided for @expReviewsTitle.
  ///
  /// In he, this message translates to:
  /// **'ביקורות'**
  String get expReviewsTitle;

  /// No description provided for @expNoReviewsMatch.
  ///
  /// In he, this message translates to:
  /// **'לא נמצאו ביקורות עבור \"{query}\"'**
  String expNoReviewsMatch(String query);

  /// No description provided for @expShowAllReviews.
  ///
  /// In he, this message translates to:
  /// **'הצג את כל {count} הביקורות'**
  String expShowAllReviews(int count);

  /// No description provided for @expCommunityVolunteerBadge.
  ///
  /// In he, this message translates to:
  /// **'התנדבות בקהילה'**
  String get expCommunityVolunteerBadge;

  /// No description provided for @expPriceAfterPhotos.
  ///
  /// In he, this message translates to:
  /// **'מובטח אחרי אישור התמונות'**
  String get expPriceAfterPhotos;

  /// No description provided for @expDeposit.
  ///
  /// In he, this message translates to:
  /// **'פיקדון מקדים'**
  String get expDeposit;

  /// No description provided for @expNights.
  ///
  /// In he, this message translates to:
  /// **'לילות'**
  String get expNights;

  /// No description provided for @expNightsCount.
  ///
  /// In he, this message translates to:
  /// **'מספר לילות'**
  String get expNightsCount;

  /// No description provided for @expEndDate.
  ///
  /// In he, this message translates to:
  /// **'תאריך סיום השהות'**
  String get expEndDate;

  /// No description provided for @expSelectDate.
  ///
  /// In he, this message translates to:
  /// **'יש לבחור תאריך'**
  String get expSelectDate;

  /// No description provided for @expMustFillAll.
  ///
  /// In he, this message translates to:
  /// **'יש למלא את כל השדות הנדרשים למעלה כדי להמשיך'**
  String get expMustFillAll;

  /// No description provided for @expBookingReceivedDemo.
  ///
  /// In he, this message translates to:
  /// **'ההזמנה התקבלה!'**
  String get expBookingReceivedDemo;

  /// No description provided for @expBookingSuccess.
  ///
  /// In he, this message translates to:
  /// **'ההזמנה בוצעה בהצלחה! 🎉'**
  String get expBookingSuccess;

  /// No description provided for @expBookingDemoBody.
  ///
  /// In he, this message translates to:
  /// **'הזמנת את השירות. אנחנו כבר מעדכנים אותך אם נותן השירות פנוי.\nתקבל הודעה ברגע שיש תשובה.'**
  String get expBookingDemoBody;

  /// No description provided for @expWillNotify.
  ///
  /// In he, this message translates to:
  /// **'נשלח לך עדכון בקרוב'**
  String get expWillNotify;

  /// No description provided for @expGotIt.
  ///
  /// In he, this message translates to:
  /// **'הבנתי ✓'**
  String get expGotIt;

  /// No description provided for @expProviderRole.
  ///
  /// In he, this message translates to:
  /// **'נותן שירות'**
  String get expProviderRole;

  /// No description provided for @expJobsLabel.
  ///
  /// In he, this message translates to:
  /// **'עבודות'**
  String get expJobsLabel;

  /// No description provided for @expRatingLabel.
  ///
  /// In he, this message translates to:
  /// **'דירוג'**
  String get expRatingLabel;

  /// No description provided for @expReviewsLabel.
  ///
  /// In he, this message translates to:
  /// **'ביקורות'**
  String get expReviewsLabel;

  /// No description provided for @expVolunteersLabel.
  ///
  /// In he, this message translates to:
  /// **'התנדבויות בקהילה'**
  String get expVolunteersLabel;

  /// No description provided for @expVideoIntro.
  ///
  /// In he, this message translates to:
  /// **'וידאו היכרות'**
  String get expVideoIntro;

  /// No description provided for @expGallery.
  ///
  /// In he, this message translates to:
  /// **'גלריית עבודות'**
  String get expGallery;

  /// No description provided for @expVerifiedCertificate.
  ///
  /// In he, this message translates to:
  /// **'תעודת הסמכה מאומתת'**
  String get expVerifiedCertificate;

  /// No description provided for @expView.
  ///
  /// In he, this message translates to:
  /// **'לצפייה'**
  String get expView;

  /// No description provided for @expCertificateTitle.
  ///
  /// In he, this message translates to:
  /// **'תעודת הסמכה'**
  String get expCertificateTitle;

  /// No description provided for @expImageLoadError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בטעינת התמונה'**
  String get expImageLoadError;

  /// No description provided for @catBadgeAngel.
  ///
  /// In he, this message translates to:
  /// **'מלאך'**
  String get catBadgeAngel;

  /// No description provided for @catBadgePillar.
  ///
  /// In he, this message translates to:
  /// **'עמוד תווך'**
  String get catBadgePillar;

  /// No description provided for @catBadgeVolunteer.
  ///
  /// In he, this message translates to:
  /// **'מתנדב'**
  String get catBadgeVolunteer;

  /// No description provided for @catDayOffline.
  ///
  /// In he, this message translates to:
  /// **'לא זמין כעת'**
  String get catDayOffline;

  /// No description provided for @catStartLesson.
  ///
  /// In he, this message translates to:
  /// **'התחל שיעור'**
  String get catStartLesson;

  /// No description provided for @catYourProfile.
  ///
  /// In he, this message translates to:
  /// **'הפרופיל שלך'**
  String get catYourProfile;

  /// No description provided for @catMapView.
  ///
  /// In he, this message translates to:
  /// **'תצוגת מפה'**
  String get catMapView;

  /// No description provided for @catListView.
  ///
  /// In he, this message translates to:
  /// **'תצוגת רשימה'**
  String get catListView;

  /// No description provided for @catInstantBookingSoon.
  ///
  /// In he, this message translates to:
  /// **'הזמנה מיידית — בקרוב 🎉'**
  String get catInstantBookingSoon;

  /// No description provided for @catFreeCommunityBadge.
  ///
  /// In he, this message translates to:
  /// **'שירות קהילתי ללא עלות — 100% חינם ❤️'**
  String get catFreeCommunityBadge;

  /// No description provided for @catNeedHelp.
  ///
  /// In he, this message translates to:
  /// **'אני צריך עזרה'**
  String get catNeedHelp;

  /// No description provided for @catHelpForOther.
  ///
  /// In he, this message translates to:
  /// **'עזרה עבור מישהו אחר'**
  String get catHelpForOther;

  /// No description provided for @catRespectTime.
  ///
  /// In he, this message translates to:
  /// **'אנא כבדו את זמנם והשתמשו בשירות לצרכים אמיתיים בלבד.'**
  String get catRespectTime;

  /// No description provided for @catFilterRating.
  ///
  /// In he, this message translates to:
  /// **'דירוג'**
  String get catFilterRating;

  /// No description provided for @catFilterDistance.
  ///
  /// In he, this message translates to:
  /// **'מרחק'**
  String get catFilterDistance;

  /// No description provided for @catFilterKm.
  ///
  /// In he, this message translates to:
  /// **'ק\"מ'**
  String get catFilterKm;

  /// No description provided for @catFilterMore.
  ///
  /// In he, this message translates to:
  /// **'עוד'**
  String get catFilterMore;

  /// No description provided for @catFilterRatingTitle.
  ///
  /// In he, this message translates to:
  /// **'סינון לפי דירוג'**
  String get catFilterRatingTitle;

  /// No description provided for @catFilterAll.
  ///
  /// In he, this message translates to:
  /// **'הכל'**
  String get catFilterAll;

  /// No description provided for @catFilterApply.
  ///
  /// In he, this message translates to:
  /// **'החל'**
  String get catFilterApply;

  /// No description provided for @catFilterDistanceTitle.
  ///
  /// In he, this message translates to:
  /// **'סינון לפי מרחק'**
  String get catFilterDistanceTitle;

  /// No description provided for @catFilterNeedLocation.
  ///
  /// In he, this message translates to:
  /// **'יש לאשר גישה למיקום כדי לסנן לפי מרחק'**
  String get catFilterNeedLocation;

  /// No description provided for @catFilterClear.
  ///
  /// In he, this message translates to:
  /// **'נקה'**
  String get catFilterClear;

  /// No description provided for @catMaxDistance.
  ///
  /// In he, this message translates to:
  /// **'מרחק מקסימלי'**
  String get catMaxDistance;

  /// No description provided for @catNoLimit.
  ///
  /// In he, this message translates to:
  /// **'ללא הגבלה'**
  String get catNoLimit;

  /// No description provided for @catUpToKm.
  ///
  /// In he, this message translates to:
  /// **'עד {km} ק״מ'**
  String catUpToKm(int km);

  /// No description provided for @catMinRating.
  ///
  /// In he, this message translates to:
  /// **'דירוג מינימלי'**
  String get catMinRating;

  /// No description provided for @catSupport.
  ///
  /// In he, this message translates to:
  /// **'תמיכה'**
  String get catSupport;

  /// No description provided for @catFillFields.
  ///
  /// In he, this message translates to:
  /// **'נא למלא קטגוריה, תיאור ומספר טלפון'**
  String get catFillFields;

  /// No description provided for @catRequestSent.
  ///
  /// In he, this message translates to:
  /// **'הבקשה נשלחה! מתנדבים מתאימים יקבלו התראה.'**
  String get catRequestSent;

  /// No description provided for @catRequestError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה: {error}'**
  String catRequestError(String error);

  /// No description provided for @catCategory.
  ///
  /// In he, this message translates to:
  /// **'קטגוריה'**
  String get catCategory;

  /// No description provided for @catChooseCategory.
  ///
  /// In he, this message translates to:
  /// **'בחר תחום עזרה'**
  String get catChooseCategory;

  /// No description provided for @catRequestDescription.
  ///
  /// In he, this message translates to:
  /// **'תיאור הבקשה'**
  String get catRequestDescription;

  /// No description provided for @catDescHint.
  ///
  /// In he, this message translates to:
  /// **'תאר/י מה צריך לעשות...'**
  String get catDescHint;

  /// No description provided for @catLocation.
  ///
  /// In he, this message translates to:
  /// **'מיקום'**
  String get catLocation;

  /// No description provided for @catLocationHint.
  ///
  /// In he, this message translates to:
  /// **'עיר / שכונה'**
  String get catLocationHint;

  /// No description provided for @catContactPhone.
  ///
  /// In he, this message translates to:
  /// **'טלפון ליצירת קשר'**
  String get catContactPhone;

  /// No description provided for @catBeneficiaryName.
  ///
  /// In he, this message translates to:
  /// **'שם המוטב'**
  String get catBeneficiaryName;

  /// No description provided for @catBeneficiaryHint.
  ///
  /// In he, this message translates to:
  /// **'שם האדם שצריך עזרה'**
  String get catBeneficiaryHint;

  /// No description provided for @catIAmContact.
  ///
  /// In he, this message translates to:
  /// **'אני איש הקשר'**
  String get catIAmContact;

  /// No description provided for @catIAmCoordinator.
  ///
  /// In he, this message translates to:
  /// **'אני זה שיתואם מול המתנדב'**
  String get catIAmCoordinator;

  /// No description provided for @catSendRequest.
  ///
  /// In he, this message translates to:
  /// **'שלח בקשת עזרה'**
  String get catSendRequest;

  /// No description provided for @catBack.
  ///
  /// In he, this message translates to:
  /// **'חזור'**
  String get catBack;

  /// No description provided for @catSearchInCategory.
  ///
  /// In he, this message translates to:
  /// **'חפש בתוך הקטגוריה...'**
  String get catSearchInCategory;

  /// No description provided for @catUnder100.
  ///
  /// In he, this message translates to:
  /// **'עד ₪100'**
  String get catUnder100;

  /// No description provided for @catAvailableNow.
  ///
  /// In he, this message translates to:
  /// **'זמינים עכשיו'**
  String get catAvailableNow;

  /// No description provided for @catInstantBook.
  ///
  /// In he, this message translates to:
  /// **'הזמנה מיידית'**
  String get catInstantBook;

  /// No description provided for @catInNeighborhood.
  ///
  /// In he, this message translates to:
  /// **'בשכונה שלך'**
  String get catInNeighborhood;

  /// No description provided for @catAvailableNowUser.
  ///
  /// In he, this message translates to:
  /// **'זמין/ה עכשיו'**
  String get catAvailableNowUser;

  /// No description provided for @catRecommended.
  ///
  /// In he, this message translates to:
  /// **'מומלץ'**
  String get catRecommended;

  /// No description provided for @catWhenAvailable.
  ///
  /// In he, this message translates to:
  /// **'מתי פנוי?'**
  String get catWhenAvailable;

  /// No description provided for @catBookNow.
  ///
  /// In he, this message translates to:
  /// **'הזמן עכשיו'**
  String get catBookNow;

  /// No description provided for @editVideoUploadError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בהעלאת הסרטון: {error}'**
  String editVideoUploadError(String error);

  /// No description provided for @editAddSecondIdentity.
  ///
  /// In he, this message translates to:
  /// **'הוסף זהות מקצועית שנייה'**
  String get editAddSecondIdentity;

  /// No description provided for @editSecondIdentitySubtitle.
  ///
  /// In he, this message translates to:
  /// **'הרוויחו יותר — הציעו שירות נוסף תחת אותו חשבון'**
  String get editSecondIdentitySubtitle;

  /// No description provided for @editPrimaryIdentity.
  ///
  /// In he, this message translates to:
  /// **'זהות ראשית'**
  String get editPrimaryIdentity;

  /// No description provided for @editSecondaryIdentity.
  ///
  /// In he, this message translates to:
  /// **'זהות שנייה'**
  String get editSecondaryIdentity;

  /// No description provided for @editEditingNow.
  ///
  /// In he, this message translates to:
  /// **'עורך כעת'**
  String get editEditingNow;

  /// No description provided for @editPhoneLabel.
  ///
  /// In he, this message translates to:
  /// **'מספר טלפון'**
  String get editPhoneLabel;

  /// No description provided for @editPhoneVerified.
  ///
  /// In he, this message translates to:
  /// **'מספר הטלפון מאומת ולא ניתן לשינוי'**
  String get editPhoneVerified;

  /// No description provided for @editAppPending.
  ///
  /// In he, this message translates to:
  /// **'הבקשה שלך בבדיקה 🕐'**
  String get editAppPending;

  /// No description provided for @editAppPendingDesc.
  ///
  /// In he, this message translates to:
  /// **'הצוות שלנו בודק את הפרטים ויחזור אליך בקרוב.'**
  String get editAppPendingDesc;

  /// No description provided for @editBecomeProvider.
  ///
  /// In he, this message translates to:
  /// **'רוצה לעבוד ולהרוויח כסף? לחץ כאן'**
  String get editBecomeProvider;

  /// No description provided for @editApplicationMessage.
  ///
  /// In he, this message translates to:
  /// **'בקשה להצטרפות כמומחה: {name}'**
  String editApplicationMessage(String name);

  /// No description provided for @editGenericError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה: {error}'**
  String editGenericError(String error);

  /// No description provided for @editUploadClearPhoto.
  ///
  /// In he, this message translates to:
  /// **'העלה תמונת פנים ברורה'**
  String get editUploadClearPhoto;

  /// No description provided for @editClearPhotoDesc.
  ///
  /// In he, this message translates to:
  /// **'פרופילים עם תמונה ברורה נהנים מפי 3 יותר פניות'**
  String get editClearPhotoDesc;

  /// No description provided for @editAccountTypeChange.
  ///
  /// In he, this message translates to:
  /// **'שינוי סוג חשבון מתבצע מול שירות הלקוחות בלבד'**
  String get editAccountTypeChange;

  /// No description provided for @editVolunteerToggleTitle.
  ///
  /// In he, this message translates to:
  /// **'אני מעוניין להתנדב'**
  String get editVolunteerToggleTitle;

  /// No description provided for @editVolunteerToggleDesc.
  ///
  /// In he, this message translates to:
  /// **'הצע את כישוריך ללא עלות לאנשים הזקוקים לעזרה'**
  String get editVolunteerToggleDesc;

  /// No description provided for @editIdentitiesTitle.
  ///
  /// In he, this message translates to:
  /// **'הזהויות המקצועיות שלך'**
  String get editIdentitiesTitle;

  /// No description provided for @editPaymentSettings.
  ///
  /// In he, this message translates to:
  /// **'הגדרות תשלום בקרוב'**
  String get editPaymentSettings;

  /// No description provided for @editPaymentSettingsDesc.
  ///
  /// In he, this message translates to:
  /// **'אנו עוברים לספק תשלומים ישראלי. בינתיים בקשות משיכה מטופלות ידנית על ידי הצוות.'**
  String get editPaymentSettingsDesc;

  /// No description provided for @editAdvancedSettings.
  ///
  /// In he, this message translates to:
  /// **'הגדרות מתקדמות'**
  String get editAdvancedSettings;

  /// No description provided for @editPricingSettings.
  ///
  /// In he, this message translates to:
  /// **'הגדרות תמחור'**
  String get editPricingSettings;

  /// No description provided for @editWorkingHours.
  ///
  /// In he, this message translates to:
  /// **'שעות עבודה'**
  String get editWorkingHours;

  /// No description provided for @editWorkingHoursHint.
  ///
  /// In he, this message translates to:
  /// **'סמן את הימים ושעות העבודה שלך'**
  String get editWorkingHoursHint;

  /// No description provided for @editDayOff.
  ///
  /// In he, this message translates to:
  /// **'לא עובד'**
  String get editDayOff;

  /// No description provided for @editCertificate.
  ///
  /// In he, this message translates to:
  /// **'תעודת הסמכה'**
  String get editCertificate;

  /// No description provided for @editCertificateDesc.
  ///
  /// In he, this message translates to:
  /// **'העלה תעודה / תעודת הסמכה מקצועית (אופציונלי)'**
  String get editCertificateDesc;

  /// No description provided for @editReplaceCertificate.
  ///
  /// In he, this message translates to:
  /// **'החלף תעודה'**
  String get editReplaceCertificate;

  /// No description provided for @editUploadCertificate.
  ///
  /// In he, this message translates to:
  /// **'העלה תעודת הסמכה'**
  String get editUploadCertificate;

  /// No description provided for @editIntroVideo.
  ///
  /// In he, this message translates to:
  /// **'סרטון היכרות'**
  String get editIntroVideo;

  /// No description provided for @editIntroVideoDesc.
  ///
  /// In he, this message translates to:
  /// **'הוסף סרטון קצר (עד 60 שניות) שמציג אותך ואת כישוריך. הסרטון יופיע בפרופיל שלך לאחר אישור מנהל.'**
  String get editIntroVideoDesc;

  /// No description provided for @editUploading.
  ///
  /// In he, this message translates to:
  /// **'מעלה... {percent}%'**
  String editUploading(int percent);

  /// No description provided for @editVideoUploaded.
  ///
  /// In he, this message translates to:
  /// **'סרטון הועלה — לחץ להחלפה'**
  String get editVideoUploaded;

  /// No description provided for @editUploadVideo.
  ///
  /// In he, this message translates to:
  /// **'העלה סרטון היכרות (עד 60 שניות)'**
  String get editUploadVideo;

  /// No description provided for @editPendingAdmin.
  ///
  /// In he, this message translates to:
  /// **'ממתין לאישור מנהל — יופיע בפרופיל לאחר האישור'**
  String get editPendingAdmin;

  /// No description provided for @editManagement.
  ///
  /// In he, this message translates to:
  /// **'ניהול'**
  String get editManagement;

  /// No description provided for @editServiceProvider.
  ///
  /// In he, this message translates to:
  /// **'נותן שירות'**
  String get editServiceProvider;

  /// No description provided for @editCustomer.
  ///
  /// In he, this message translates to:
  /// **'לקוח'**
  String get editCustomer;

  /// No description provided for @editAdminModeActive.
  ///
  /// In he, this message translates to:
  /// **'מצב ניהול פעיל'**
  String get editAdminModeActive;

  /// No description provided for @editProviderModeActive.
  ///
  /// In he, this message translates to:
  /// **'מצב נותן שירות פעיל'**
  String get editProviderModeActive;

  /// No description provided for @editCustomerModeActive.
  ///
  /// In he, this message translates to:
  /// **'מצב לקוח פעיל'**
  String get editCustomerModeActive;

  /// No description provided for @editViewMode.
  ///
  /// In he, this message translates to:
  /// **'מצב תצוגה'**
  String get editViewMode;

  /// No description provided for @editMyDogs.
  ///
  /// In he, this message translates to:
  /// **'הכלבים שלי'**
  String get editMyDogs;

  /// No description provided for @editShowAll.
  ///
  /// In he, this message translates to:
  /// **'הצג הכל'**
  String get editShowAll;

  /// No description provided for @editAddDogProfile.
  ///
  /// In he, this message translates to:
  /// **'הוסף פרופיל כלב'**
  String get editAddDogProfile;

  /// No description provided for @editNewDog.
  ///
  /// In he, this message translates to:
  /// **'כלב חדש'**
  String get editNewDog;

  /// No description provided for @editUnnamedDog.
  ///
  /// In he, this message translates to:
  /// **'ללא שם'**
  String get editUnnamedDog;

  /// No description provided for @editApplyAsProvider.
  ///
  /// In he, this message translates to:
  /// **'הגש מועמדות כמומחה'**
  String get editApplyAsProvider;

  /// No description provided for @editApplyDesc.
  ///
  /// In he, this message translates to:
  /// **'מלא את הפרטים ואנחנו נבדוק את הבקשה שלך'**
  String get editApplyDesc;

  /// No description provided for @editServiceFieldLabel.
  ///
  /// In he, this message translates to:
  /// **'תחום עיסוק *'**
  String get editServiceFieldLabel;

  /// No description provided for @editChooseField.
  ///
  /// In he, this message translates to:
  /// **'בחר תחום'**
  String get editChooseField;

  /// No description provided for @editIdNumberLabel.
  ///
  /// In he, this message translates to:
  /// **'מספר ת.ז. / ח.פ. *'**
  String get editIdNumberLabel;

  /// No description provided for @editIdNumberHint.
  ///
  /// In he, this message translates to:
  /// **'הכנס מספר זהות'**
  String get editIdNumberHint;

  /// No description provided for @editAboutYouLabel.
  ///
  /// In he, this message translates to:
  /// **'ספר על עצמך *'**
  String get editAboutYouLabel;

  /// No description provided for @editAboutYouHint.
  ///
  /// In he, this message translates to:
  /// **'תאר את הניסיון שלך, השירותים שאתה מציע...'**
  String get editAboutYouHint;

  /// No description provided for @editSubmitApplication.
  ///
  /// In he, this message translates to:
  /// **'שלח בקשה'**
  String get editSubmitApplication;

  /// No description provided for @editChooseFieldError.
  ///
  /// In he, this message translates to:
  /// **'בחר תחום עיסוק'**
  String get editChooseFieldError;

  /// No description provided for @editEnterIdError.
  ///
  /// In he, this message translates to:
  /// **'הכנס מספר זהות'**
  String get editEnterIdError;

  /// No description provided for @editDaySunday.
  ///
  /// In he, this message translates to:
  /// **'ראשון'**
  String get editDaySunday;

  /// No description provided for @editDayMonday.
  ///
  /// In he, this message translates to:
  /// **'שני'**
  String get editDayMonday;

  /// No description provided for @editDayTuesday.
  ///
  /// In he, this message translates to:
  /// **'שלישי'**
  String get editDayTuesday;

  /// No description provided for @editDayWednesday.
  ///
  /// In he, this message translates to:
  /// **'רביעי'**
  String get editDayWednesday;

  /// No description provided for @editDayThursday.
  ///
  /// In he, this message translates to:
  /// **'חמישי'**
  String get editDayThursday;

  /// No description provided for @editDayFriday.
  ///
  /// In he, this message translates to:
  /// **'שישי'**
  String get editDayFriday;

  /// No description provided for @editDaySaturday.
  ///
  /// In he, this message translates to:
  /// **'שבת'**
  String get editDaySaturday;

  /// No description provided for @phoneInvalidNumber.
  ///
  /// In he, this message translates to:
  /// **'מספר טלפון לא תקין'**
  String get phoneInvalidNumber;

  /// No description provided for @phoneTooManyCodes.
  ///
  /// In he, this message translates to:
  /// **'שלחת יותר מדי קודים. המתן {mins} דקות ונסה שוב.'**
  String phoneTooManyCodes(int mins);

  /// No description provided for @phoneSendCodeError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בשליחת הקוד. נסה שוב.'**
  String get phoneSendCodeError;

  /// No description provided for @phoneErrorTooManyRequests.
  ///
  /// In he, this message translates to:
  /// **'יותר מדי ניסיונות. נסה מאוחר יותר.'**
  String get phoneErrorTooManyRequests;

  /// No description provided for @phoneErrorQuotaExceeded.
  ///
  /// In he, this message translates to:
  /// **'מכסת SMS חרגה. נסה מחר.'**
  String get phoneErrorQuotaExceeded;

  /// No description provided for @phoneErrorNoNetwork.
  ///
  /// In he, this message translates to:
  /// **'אין חיבור לאינטרנט'**
  String get phoneErrorNoNetwork;

  /// No description provided for @phoneErrorGeneric.
  ///
  /// In he, this message translates to:
  /// **'שגיאה: {code}'**
  String phoneErrorGeneric(String code);

  /// No description provided for @phoneRateLimitInfo.
  ///
  /// In he, this message translates to:
  /// **'ניתן לשלוח עד {max} קודים בכל {mins} דקות'**
  String phoneRateLimitInfo(int max, int mins);

  /// No description provided for @phoneLoginError.
  ///
  /// In he, this message translates to:
  /// **'שגיאת התחברות: {code}'**
  String phoneLoginError(String code);

  /// No description provided for @countryIsrael.
  ///
  /// In he, this message translates to:
  /// **'ישראל'**
  String get countryIsrael;

  /// No description provided for @otpLegacyUserDialogTitle.
  ///
  /// In he, this message translates to:
  /// **'חשבון קיים'**
  String get otpLegacyUserDialogTitle;

  /// No description provided for @otpLegacyUserDialogBody.
  ///
  /// In he, this message translates to:
  /// **'למספר הזה יש חשבון קיים. נא לפנות לתמיכה.'**
  String get otpLegacyUserDialogBody;

  /// No description provided for @notifMuted.
  ///
  /// In he, this message translates to:
  /// **'השתקה'**
  String get notifMuted;

  /// No description provided for @notifMuteAll.
  ///
  /// In he, this message translates to:
  /// **'השתק הכל'**
  String get notifMuteAll;

  /// No description provided for @chatTyping.
  ///
  /// In he, this message translates to:
  /// **'מקליד...'**
  String get chatTyping;

  /// No description provided for @chatOnline.
  ///
  /// In he, this message translates to:
  /// **'מחובר'**
  String get chatOnline;

  /// No description provided for @expertPhotoGalleryEmpty.
  ///
  /// In he, this message translates to:
  /// **'אין עדיין תמונות'**
  String get expertPhotoGalleryEmpty;

  /// No description provided for @catMapResultsCount.
  ///
  /// In he, this message translates to:
  /// **'{count} תוצאות באזור שלך'**
  String catMapResultsCount(int count);

  /// No description provided for @catSearchResultsTitle.
  ///
  /// In he, this message translates to:
  /// **'נותני שירות ב-{category}'**
  String catSearchResultsTitle(String category);

  /// No description provided for @catAnyExpert.
  ///
  /// In he, this message translates to:
  /// **'כל נותני השירות'**
  String get catAnyExpert;

  /// No description provided for @catSortBy.
  ///
  /// In he, this message translates to:
  /// **'מיון לפי'**
  String get catSortBy;

  /// No description provided for @catSortRelevance.
  ///
  /// In he, this message translates to:
  /// **'רלוונטיות'**
  String get catSortRelevance;

  /// No description provided for @catSortDistance.
  ///
  /// In he, this message translates to:
  /// **'מרחק'**
  String get catSortDistance;

  /// No description provided for @catSortRating.
  ///
  /// In he, this message translates to:
  /// **'דירוג'**
  String get catSortRating;

  /// No description provided for @catSortPrice.
  ///
  /// In he, this message translates to:
  /// **'מחיר'**
  String get catSortPrice;

  /// No description provided for @catNoResults.
  ///
  /// In he, this message translates to:
  /// **'לא נמצאו תוצאות'**
  String get catNoResults;

  /// No description provided for @catNoResultsDesc.
  ///
  /// In he, this message translates to:
  /// **'נסה לשנות את הפילטרים או לחפש באזור אחר'**
  String get catNoResultsDesc;

  /// No description provided for @catUrgent.
  ///
  /// In he, this message translates to:
  /// **'דחוף'**
  String get catUrgent;

  /// No description provided for @catExpressDelivery.
  ///
  /// In he, this message translates to:
  /// **'משלוח מהיר'**
  String get catExpressDelivery;

  /// No description provided for @editVerifiedBadge.
  ///
  /// In he, this message translates to:
  /// **'מאומת'**
  String get editVerifiedBadge;

  /// No description provided for @editAdminOnlyChange.
  ///
  /// In he, this message translates to:
  /// **'שינוי זה זמין רק למנהל המערכת'**
  String get editAdminOnlyChange;

  /// No description provided for @editProfileSaved.
  ///
  /// In he, this message translates to:
  /// **'הפרופיל נשמר בהצלחה'**
  String get editProfileSaved;

  /// No description provided for @editPriceLabel.
  ///
  /// In he, this message translates to:
  /// **'מחיר לשעה (₪)'**
  String get editPriceLabel;

  /// No description provided for @editPriceHint.
  ///
  /// In he, this message translates to:
  /// **'הכנס מחיר בשקלים'**
  String get editPriceHint;

  /// No description provided for @editAboutMeLabel.
  ///
  /// In he, this message translates to:
  /// **'ספר על עצמך'**
  String get editAboutMeLabel;

  /// No description provided for @editAboutMeHint.
  ///
  /// In he, this message translates to:
  /// **'תאר את הניסיון שלך, השירותים שאתה מציע...'**
  String get editAboutMeHint;

  /// No description provided for @editCategoryLabel.
  ///
  /// In he, this message translates to:
  /// **'קטגוריה מקצועית'**
  String get editCategoryLabel;

  /// No description provided for @editSubCategoryLabel.
  ///
  /// In he, this message translates to:
  /// **'תת-קטגוריה'**
  String get editSubCategoryLabel;

  /// No description provided for @editDogNameLabel.
  ///
  /// In he, this message translates to:
  /// **'שם הכלב'**
  String get editDogNameLabel;

  /// No description provided for @editDogBreedLabel.
  ///
  /// In he, this message translates to:
  /// **'גזע'**
  String get editDogBreedLabel;

  /// No description provided for @editDogAgeLabel.
  ///
  /// In he, this message translates to:
  /// **'גיל'**
  String get editDogAgeLabel;

  /// No description provided for @editDogWeightLabel.
  ///
  /// In he, this message translates to:
  /// **'משקל (ק\"ג)'**
  String get editDogWeightLabel;

  /// No description provided for @editDogSizeLabel.
  ///
  /// In he, this message translates to:
  /// **'גודל'**
  String get editDogSizeLabel;

  /// No description provided for @editDogDescLabel.
  ///
  /// In he, this message translates to:
  /// **'תיאור'**
  String get editDogDescLabel;

  /// No description provided for @editDogSaveBtn.
  ///
  /// In he, this message translates to:
  /// **'שמור פרופיל כלב'**
  String get editDogSaveBtn;

  /// No description provided for @editDogPickPhoto.
  ///
  /// In he, this message translates to:
  /// **'בחר תמונה'**
  String get editDogPickPhoto;

  /// No description provided for @editDogNameHint.
  ///
  /// In he, this message translates to:
  /// **'איך קוראים לכלב?'**
  String get editDogNameHint;

  /// No description provided for @editDogBreedHint.
  ///
  /// In he, this message translates to:
  /// **'למשל: גולדן רטריבר'**
  String get editDogBreedHint;

  /// No description provided for @editDogSizeSmall.
  ///
  /// In he, this message translates to:
  /// **'קטן'**
  String get editDogSizeSmall;

  /// No description provided for @editDogSizeMedium.
  ///
  /// In he, this message translates to:
  /// **'בינוני'**
  String get editDogSizeMedium;

  /// No description provided for @editDogSizeLarge.
  ///
  /// In he, this message translates to:
  /// **'גדול'**
  String get editDogSizeLarge;

  /// No description provided for @editDogYears.
  ///
  /// In he, this message translates to:
  /// **'שנים'**
  String get editDogYears;

  /// No description provided for @editDogDescHint.
  ///
  /// In he, this message translates to:
  /// **'אופי, תחביבים, דברים חשובים לדעת...'**
  String get editDogDescHint;

  /// No description provided for @editCancellationPolicyTitle.
  ///
  /// In he, this message translates to:
  /// **'מדיניות ביטול'**
  String get editCancellationPolicyTitle;

  /// No description provided for @editCancellationFlexible.
  ///
  /// In he, this message translates to:
  /// **'גמיש'**
  String get editCancellationFlexible;

  /// No description provided for @editCancellationModerate.
  ///
  /// In he, this message translates to:
  /// **'בינוני'**
  String get editCancellationModerate;

  /// No description provided for @editCancellationStrict.
  ///
  /// In he, this message translates to:
  /// **'מחמיר'**
  String get editCancellationStrict;

  /// No description provided for @editCancellationFlexibleDesc.
  ///
  /// In he, this message translates to:
  /// **'החזר מלא עד 4 שעות לפני'**
  String get editCancellationFlexibleDesc;

  /// No description provided for @editCancellationModerateDesc.
  ///
  /// In he, this message translates to:
  /// **'החזר מלא עד 24 שעות לפני'**
  String get editCancellationModerateDesc;

  /// No description provided for @editCancellationStrictDesc.
  ///
  /// In he, this message translates to:
  /// **'החזר מלא עד 48 שעות לפני'**
  String get editCancellationStrictDesc;

  /// No description provided for @editResponseTimeLabel.
  ///
  /// In he, this message translates to:
  /// **'זמן תגובה ממוצע'**
  String get editResponseTimeLabel;

  /// No description provided for @editResponseImmediate.
  ///
  /// In he, this message translates to:
  /// **'מיידי'**
  String get editResponseImmediate;

  /// No description provided for @editResponse30min.
  ///
  /// In he, this message translates to:
  /// **'תוך 30 דקות'**
  String get editResponse30min;

  /// No description provided for @editResponse1h.
  ///
  /// In he, this message translates to:
  /// **'תוך שעה'**
  String get editResponse1h;

  /// No description provided for @editResponseDay.
  ///
  /// In he, this message translates to:
  /// **'תוך יום'**
  String get editResponseDay;

  /// No description provided for @editQuickTagsTitle.
  ///
  /// In he, this message translates to:
  /// **'תגיות מהירות'**
  String get editQuickTagsTitle;

  /// No description provided for @editQuickTagsDesc.
  ///
  /// In he, this message translates to:
  /// **'בחר עד 5 תגיות שמתארות את השירות שלך'**
  String get editQuickTagsDesc;

  /// No description provided for @editSave.
  ///
  /// In he, this message translates to:
  /// **'שמור'**
  String get editSave;

  /// No description provided for @editSaving.
  ///
  /// In he, this message translates to:
  /// **'שומר...'**
  String get editSaving;

  /// No description provided for @editDiscardChanges.
  ///
  /// In he, this message translates to:
  /// **'לבטל שינויים?'**
  String get editDiscardChanges;

  /// No description provided for @editDiscardConfirm.
  ///
  /// In he, this message translates to:
  /// **'יש לך שינויים שלא נשמרו. לבטל אותם?'**
  String get editDiscardConfirm;

  /// No description provided for @editDiscard.
  ///
  /// In he, this message translates to:
  /// **'ביטול שינויים'**
  String get editDiscard;

  /// No description provided for @editContinueEditing.
  ///
  /// In he, this message translates to:
  /// **'המשך עריכה'**
  String get editContinueEditing;

  /// No description provided for @editFieldRequired.
  ///
  /// In he, this message translates to:
  /// **'שדה חובה'**
  String get editFieldRequired;

  /// No description provided for @editInvalidPrice.
  ///
  /// In he, this message translates to:
  /// **'מחיר לא תקין'**
  String get editInvalidPrice;

  /// No description provided for @editMinPrice.
  ///
  /// In he, this message translates to:
  /// **'המחיר המינימלי הוא ₪{min}'**
  String editMinPrice(int min);

  /// No description provided for @editCustomerServiceType.
  ///
  /// In he, this message translates to:
  /// **'לקוח'**
  String get editCustomerServiceType;

  /// No description provided for @editAboutMinChars.
  ///
  /// In he, this message translates to:
  /// **'כתוב לפחות 20 תווים על עצמך'**
  String get editAboutMinChars;

  /// No description provided for @editSecondIdentityCreated.
  ///
  /// In he, this message translates to:
  /// **'זהות מקצועית שנייה נוצרה בהצלחה! 🎉'**
  String get editSecondIdentityCreated;

  /// No description provided for @editAddSecondIdentityTitle.
  ///
  /// In he, this message translates to:
  /// **'הוספת זהות מקצועית שנייה'**
  String get editAddSecondIdentityTitle;

  /// No description provided for @editAddSecondIdentityDesc.
  ///
  /// In he, this message translates to:
  /// **'בחר קטגוריה חדשה, מחיר ותיאור — הפרופיל השני יוצג בנפרד בחיפוש'**
  String get editAddSecondIdentityDesc;

  /// No description provided for @editSecondServiceDesc.
  ///
  /// In he, this message translates to:
  /// **'ספרו ללקוחות על השירות השני שלכם...'**
  String get editSecondServiceDesc;

  /// No description provided for @editCreateIdentity.
  ///
  /// In he, this message translates to:
  /// **'צור זהות מקצועית'**
  String get editCreateIdentity;

  /// No description provided for @editIdentityUpdated.
  ///
  /// In he, this message translates to:
  /// **'הזהות המקצועית עודכנה בהצלחה'**
  String get editIdentityUpdated;

  /// No description provided for @editDeleteIdentityTitle.
  ///
  /// In he, this message translates to:
  /// **'מחיקת זהות מקצועית'**
  String get editDeleteIdentityTitle;

  /// No description provided for @editDeleteIdentityConfirm.
  ///
  /// In he, this message translates to:
  /// **'האם למחוק את הזהות המקצועית השנייה? הפעולה לא ניתנת לביטול.'**
  String get editDeleteIdentityConfirm;

  /// No description provided for @editDelete.
  ///
  /// In he, this message translates to:
  /// **'מחק'**
  String get editDelete;

  /// No description provided for @editIdentityDeleted.
  ///
  /// In he, this message translates to:
  /// **'הזהות המקצועית נמחקה'**
  String get editIdentityDeleted;

  /// No description provided for @editSaveChanges.
  ///
  /// In he, this message translates to:
  /// **'שמור שינויים'**
  String get editSaveChanges;

  /// No description provided for @editDeleteIdentity.
  ///
  /// In he, this message translates to:
  /// **'מחק זהות מקצועית'**
  String get editDeleteIdentity;

  /// No description provided for @editEditingIdentity.
  ///
  /// In he, this message translates to:
  /// **'עריכת {type}'**
  String editEditingIdentity(String type);

  /// No description provided for @phoneLoginContinueGoogle.
  ///
  /// In he, this message translates to:
  /// **'המשך עם Google'**
  String get phoneLoginContinueGoogle;

  /// No description provided for @phoneLoginContinueApple.
  ///
  /// In he, this message translates to:
  /// **'המשך עם Apple'**
  String get phoneLoginContinueApple;

  /// No description provided for @phoneLoginOrPhone.
  ///
  /// In he, this message translates to:
  /// **'או עם מספר טלפון'**
  String get phoneLoginOrPhone;

  /// No description provided for @phoneLoginCtaLogin.
  ///
  /// In he, this message translates to:
  /// **'להתחברות'**
  String get phoneLoginCtaLogin;

  /// No description provided for @phoneLoginTermsPrefix.
  ///
  /// In he, this message translates to:
  /// **'בהמשך אני מאשר את'**
  String get phoneLoginTermsPrefix;

  /// No description provided for @phoneLoginTermsOfUse.
  ///
  /// In he, this message translates to:
  /// **'תנאי השימוש'**
  String get phoneLoginTermsOfUse;

  /// No description provided for @phoneLoginAnd.
  ///
  /// In he, this message translates to:
  /// **'ו'**
  String get phoneLoginAnd;

  /// No description provided for @phoneLoginPrivacyPolicy.
  ///
  /// In he, this message translates to:
  /// **'מדיניות הפרטיות'**
  String get phoneLoginPrivacyPolicy;

  /// No description provided for @phoneLoginOfferingService.
  ///
  /// In he, this message translates to:
  /// **'מציע שירות?'**
  String get phoneLoginOfferingService;

  /// No description provided for @phoneLoginBecomeProvider.
  ///
  /// In he, this message translates to:
  /// **'הרוויח עם AnySkill ←'**
  String get phoneLoginBecomeProvider;
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
