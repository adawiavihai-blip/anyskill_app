// Hand-written AppLocalizations — source of truth until flutter gen-l10n is run.
//
// All user-visible strings are defined here in three languages.
// Hebrew (he) is the fallback for any missing key.
//
// To add a string:
//   1. Add the key+value to _translations for all three locales
//   2. Add a typed getter below
//   3. (Optional) Add the same key to lib/l10n/app_XX.arb for future gen-l10n
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// ── Supported locales ─────────────────────────────────────────────────────────
const _he = Locale('he');
const _en = Locale('en');
const _es = Locale('es');

// ── Translation map ───────────────────────────────────────────────────────────
final Map<String, Map<String, String>> _translations = {
  // ─────────────────────────────────────────────── HEBREW ───────────────────
  'he': {
    // App
    'appName':                'AnySkill',
    'appSlogan':              'AnySkill — הכישרון שלך, השירות שלהם',

    // Navigation
    'tabHome':                'בית',
    'tabBookings':            'הזמנות',
    'tabChat':                "צ'אט",
    'tabWallet':              'ארנק',
    'tabProfile':             'פרופיל',

    // Common actions
    'cancel':                 'ביטול',
    'confirm':                'אישור',
    'submit':                 'שלח',
    'save':                   'שמור',
    'close':                  'סגור',
    'delete':                 'מחק',
    'open':                   'פתח',
    'back':                   'חזור',

    // Common errors
    'errorGeneric':           'אירעה שגיאה. נסה שוב',

    // Currency
    'currencySymbol':         '₪',

    // ── App-level banners ─────────────────────────────────────────────────
    'updateBannerText':       'שדרגנו את AnySkill עבורך!\nגרסה חדשה זמינה לשיפור הביצועים 🚀',
    'updateNowButton':        'עדכן עכשיו',
    'notifOpen':              'פתח',

    // ── Auth / Login ──────────────────────────────────────────────────────
    'loginTitle':             'ברוכים הבאים ל-AnySkill',
    'loginAccountTitle':      'כניסה לחשבון',
    'loginWelcomeBack':       'ברוכים השבים! המומחים מחכים לכם',
    'loginEmail':             'כתובת אימייל',
    'loginPassword':          'סיסמה',
    'loginButton':            'כניסה לחשבון →',
    'loginRememberMe':        'זכור אותי',
    'loginForgotPassword':    'שכחתי סיסמה',
    'loginNoAccount':         'אין לך חשבון? ',
    'loginSignUpFree':        'הירשם בחינם עכשיו',
    'loginOrWith':            'או היכנסו עם',
    'loginAppleComingSoon':   'התחברות עם Apple תהיה זמינה בקרוב',
    'loginStats10k':          'מקצוענים',
    'loginStats50':           'קטגוריות',
    'loginStats49':           'דירוג',

    // Auth errors
    'errorUserNotFound':      'לא נמצא משתמש עם האימייל הזה',
    'errorWrongPassword':     'הסיסמה שגויה — נסו שנית',
    'errorInvalidCredential': 'אימייל או סיסמה שגויים',
    'errorInvalidEmail':      'כתובת האימייל אינה תקינה',
    'errorUserDisabled':      'חשבון זה הושבת',
    'errorTooManyRequests':   'יותר מדי ניסיונות — נסו שוב עוד כמה דקות',
    'errorNetworkFailed':     'שגיאת רשת — בדקו חיבור',
    'errorGenericLogin':      'שגיאה בהתחברות, נסו שנית',
    'errorEmptyFields':       'נא למלא אימייל וסיסמה',
    'errorGoogleLogin':       'שגיאה בהתחברות עם Google',

    // Forgot password
    'forgotPasswordTitle':    'איפוס סיסמה',
    'forgotPasswordSubtitle': 'הזינו את האימייל שלכם ונשלח לינק לאיפוס',
    'forgotPasswordEmail':    'כתובת אימייל',
    'forgotPasswordSubmit':   'שלח לינק לאיפוס',
    'forgotPasswordSuccess':  'לינק לאיפוס נשלח לאימייל שלך ✉️',
    'forgotPasswordError':    'שגיאה — בדקו שהאימייל רשום במערכת',

    // Sign-up
    'signupButton':           'הרשמה',
    'signupTitle':            'הצטרפות ל-AnySkill',
    'googleNewUserBio':       'לקוח חדש ב-AnySkill',

    // Validation
    'validationNameRequired': 'נא להזין שם',
    'validationNameLength':   'השם חייב להכיל לפחות 2 תווים',
    'validationRoleRequired': 'יש לבחור לפחות תפקיד אחד',
    'validationCategoryRequired': 'נא לבחור תחום התמחות',
    'validationPriceInvalid': 'המחיר חייב להיות מספר תקין',
    'validationPricePositive':'המחיר חייב להיות גדול מ-0',

    // ── Profile ────────────────────────────────────────────────────────────
    'profileTitle':           'הפרופיל שלי',
    'shareProfileTitle':      'שתף פרופיל להגדלת מכירות',
    'shareProfileWhatsapp':   'שלח ישירות לוואטסאפ',
    'shareProfileCopyLink':   'העתק לינק לפרופיל',
    'shareProfileTooltip':    'שתף פרופיל',
    'linkCopied':             'הלינק הועתק! הדבק אותו היכן שתרצה.',
    'whatsappError':          'לא ניתן לפתוח את וואטסאפ בדפדפן זה',
    'defaultUserName':        'משתמש אנונימי',
    'logoutTooltip':          'התנתק',
    'logoutTitle':            'התנתקות',
    'logoutContent':          'האם אתה בטוח שברצונך להתנתק?',
    'logoutConfirm':          'התנתק',
    'logoutButton':           'התנתק מהמערכת',
    'aboutMeTitle':           'על עצמי',
    'aboutMePlaceholder':     'עדיין לא נכתב תיאור.',
    'galleryTitle':           'גלריית עבודות',
    'galleryEmpty':           'אין תמונות בגלריה',
    'statRating':             'דירוג',
    'statBalance':            'יתרה',
    'statWorks':              'עבודות',
    'bookingsTrackerButton':  'למעקב אחרי ההזמנות שלי',
    'bookingsTrackerSnackbar':"מעבר לצ'אטים למעקב אחרי עסקאות...",

    // VIP
    'vipActiveLabel':         'VIP פעיל',
    'vipExpiredLabel':        'פג תוקף',
    'vipHighlight':           'הפרופיל שלך מוצג ראשון בחיפוש עם זוהר זהוב ✨',
    'vipUpsellTitle':         'חשיפה מוגברת VIP',
    'vipBenefit1':            'מופיע ראשון בכל תוצאות חיפוש',
    'vipBenefit2':            "זוהר זהוב ותג 'מומלץ' על הכרטיס",
    'vipBenefit3':            'עד 5× יותר צפיות בפרופיל',
    'vipBenefit4':            'עדיפות בבקשות דחופות',
    'vipCtaButton':           'הצטרף ל-VIP — ₪99/חודש',
    'vipSheetHeader':         'הצטרף ל-VIP',
    'vipPriceMonthly':        '/חודש',
    'vipActivateButton':      '⭐ הפעל VIP — ₪99 מהיתרה',
    'vipInsufficientBalance': 'יתרה לא מספיקה (נדרש ₪99)',
    'vipInsufficientTooltip': 'טען את הארנק שלך כדי להפעיל VIP',
    'vipActivationSuccess':   '🎉 ברוך הבא ל-VIP! הפרופיל שלך מוצג ראשון מעכשיו',

    // ── Language settings ─────────────────────────────────────────────────
    'languageTitle':          'שפה',
    'languageHe':             'עברית',
    'languageEn':             'אנגלית',
    'languageEs':             'ספרדית',
    'languageSectionLabel':   'שפת הממשק',

    // ── Chat list ─────────────────────────────────────────────────────────
    'chatListTitle':          'הודעות',
    'chatSearchHint':         'חפש שיחה...',
    'chatEmptyState':         'אין שיחות עדיין',
    'chatUserDefault':        'משתמש',
    'chatLastMessageDefault': 'הודעה חדשה',
    'markAllReadTooltip':     'סמן הכל כנקרא',
    'markAllReadSuccess':     'כל ההודעות סומנו כנקראו',
    'deleteChatTitle':        'מחיקת שיחה',
    'deleteChatContent':      'האם אתה בטוח שברצונך למחוק את כל היסטוריית השיחה?',
    'deleteChatConfirm':      'מחק',
    'deleteChatSuccess':      'השיחה נמחקה',
    'notLoggedIn':            'נא להתחבר מחדש',

    // ── Search ────────────────────────────────────────────────────────────
    'searchPlaceholder':      'חפש מקצוען, שירות...',
    'searchTitle':            'חיפוש',
    'discoverCategories':     'גלה קטגוריות',
    'searchHintExperts':      'מה תרצה ללמוד היום?',
    'greetingMorning':        'בוקר טוב',
    'greetingAfternoon':      'אחה"צ טובות',
    'greetingEvening':        'ערב טוב',
    'greetingNight':          'לילה טוב',
    'greetingSubMorning':     'מה צריך לסדר הבוקר?',
    'greetingSubAfternoon':   'מחפש מקצוען? זה הזמן',
    'greetingSubEvening':     'פינוק בערב? מגיע לך!',
    'greetingSubNight':       'גלה מומחים מובילים',

    // ── Home tab ──────────────────────────────────────────────────────────
    'onlineStatus':           'זמין',
    'offlineStatus':          'לא זמין',
    'quickRequest':           'בקשה מהירה',
    'urgentJobBanner':        'יש עבודה חדשה!',

    // ── Bookings ─────────────────────────────────────────────────────────
    'bookNow':                'הזמן עכשיו',

    // ── Wallet ────────────────────────────────────────────────────────────
    'walletBalance':          'יתרה ניתנת למשיכה',
    'walletMinWithdraw':      'מינימום למשיכה: ₪50',
    'withdrawFunds':          'משוך כספים',

    // ── ToS ──────────────────────────────────────────────────────────────
    'tosTitle':               'תנאי שימוש',
    'tosAgree':               'קראתי ומסכים/ה לתנאים',

    // ── Misc ──────────────────────────────────────────────────────────────
    'trendingBadge':          'טרנד',
    'subCategoryPrompt':      'בחר התמחות',
    'reviewSubmit':           'שלח ביקורת',
    'urgentOpenButton':       'פתח',

    // ── Edit profile ──────────────────────────────────────────────────────
    'editProfileTitle':       'עריכת פרופיל Elite',
    'saveSuccess':            'הפרופיל עודכן בהצלחה!',
    'profileFieldName':       'שם מלא',
    'profileFieldNameHint':   'איך יקראו לך באפליקציה?',
    'profileFieldRole':       'הגדרת תפקיד',
    'roleProvider':           'נותן שירות',
    'roleCustomer':           'לקוח',
    'profileFieldCategoryMain':     'תחום התמחות (ראשי)',
    'profileFieldCategoryMainHint': 'בחר תחום',
    'profileFieldCategorySub':      'התמחות ספציפית (תת-קטגוריה)',
    'profileFieldCategorySubHint':  'בחר התמחות',
    'profileFieldPrice':      'מחיר לשעה (₪)',
    'profileFieldPriceHint':  'כמה תרצה להרוויח?',
    'profileFieldResponseTime':     'זמן תגובה ממוצע',
    'profileFieldTaxId':      'ח.פ / ת.ז (לחשבוניות)',
    'profileFieldTaxIdHint':  'לדוגמה: 123456789',
    'profileFieldTaxIdHelp':  'יופיע בקבלות הדיגיטליות שנשלחות ללקוחות',
    'saveChanges':            'שמור שינויים',
    'saveError':              'שגיאה בשמירה: {error}',
    'profileFieldResponseTimeHint': 'כמה מהר אתה בדרך כלל מגיב להודעות?',
    'editProfileQuickTags':   'תגיות מהירות (Quick Tags)',
    'editProfileTagsSelected':'{count}/3 נבחרו',
    'editProfileTagsHint':    'בחר עד 3 תגיות שיוצגו על הכרטיס שלך',
    'editProfileCancellationPolicy': 'מדיניות ביטול',
    'editProfileCancellationHint':   'לקוחות יראו מדיניות זו לפני ביצוע ההזמנה',
    'editProfileAbout':       'תיאור אישי (About)',
    'editProfileAboutHint':   'ספר קצת על הניסיון שלך...',
    'editProfileGallery':     'גלריית עבודות (הוכחת יכולת)',

    // ── Home tab ─────────────────────────────────────────────────────────────
    'homeProviderGreetingSub': 'מה יש בצנרת היום?',
    'homeCustomerGreetingSub': 'מה צריך לסדר?',
    'noCategoriesYet':        'אין קטגוריות עדיין',
    'urgentBannerRequests':   'בקשות',
    'urgentBannerPending':    'ממתינות',
    'urgentBannerCustomerWaiting': 'הלקוח מחכה לאישורך',
    'urgentBannerServiceNeeded':   'שירות נדרש',
    'timeOneHour':            'שעה',

    // ── Notifications ─────────────────────────────────────────────────────────
    'notificationsTitle':     'התראות',
    'notifClearAll':          'נקה הכל',
    'notifEmptyTitle':        'אין התראות עדיין',
    'notifEmptySubtitle':     'פעולות בחשבון שלך יופיעו כאן',
    'timeNow':                'עכשיו',
    'timeMinutesAgo':         'לפני {minutes} דק\'',
    'timeHoursAgo':           'לפני {hours} שעות',

    // ── Sign Up ───────────────────────────────────────────────────────────────
    'signupTosMustAgree':     'יש לאשר את תנאי השימוש כדי להמשיך',
    'signupAccountCreated':   'החשבון נוצר! ברוכים הבאים ל-AnySkill 🎉',
    'signupEmailInUse':       'כתובת האימייל כבר רשומה במערכת',
    'signupWeakPassword':     'הסיסמה חלשה מדי — נסו סיסמה חזקה יותר',
    'signupNetworkError':     'שגיאת רשת — בדקו חיבור לאינטרנט',
    'signupGenericError':     'שגיאה ברישום',
    'signupNewProviderBio':   'מומחה חדש בקהילת AnySkill 🚀',
    'signupNewCustomerBio':   'לקוח חדש ב-AnySkill',
    'signupIAmCustomer':      'אני לקוח',
    'signupIAmProvider':      'אני נותן שירות',
    'signupCustomerDesc':     'מחפש מקצוענים לעזרה',
    'signupProviderDesc':     'מציע שירותים ומרוויח',
    'signupName':             'שם מלא',
    'signupNameHint':         'השם שיופיע בפרופיל',
    'signupEmail':            'כתובת אימייל',
    'signupEmailHint':        'example@email.com',
    'signupPassword':         'סיסמה',
    'signupPasswordHint':     'לפחות 8 תווים',
    'signupPhone':            'טלפון (אופציונלי)',
    'signupPhoneHint':        '050-1234567',
    'signupCategory':         'תחום התמחות',
    'signupTosPrefix':        'קראתי ומסכים/ה ל',
    'signupTosLink':          'תנאי השימוש',
    'signupHaveAccount':      'כבר יש לך חשבון? ',
    'signupLogin':            'כניסה',
    'signupOrWith':           'או הירשם עם',
    'signupGoogleError':      'שגיאה בהרשמה עם Google',
    'signupPasswordStrength0':'חולשה גבוהה',
    'signupPasswordStrength1':'חלשה',
    'signupPasswordStrength2':'בינונית',
    'signupPasswordStrength3':'חזקה',
    'signupPasswordStrength4':'חזקה מאוד',
    'signupNameValidation':   'שם חובה (לפחות 2 תווים)',
    'signupEmailValidation':  'כתובת אימייל לא תקינה',
    'signupPasswordValidation':'לפחות 6 תווים',
    'signupCategoryRequired': 'בחר תחום',

    // ── Bookings ──────────────────────────────────────────────────────────────
    'availabilityUpdated':    'הזמינות עודכנה בהצלחה',
    'bookingCompleted':       'העבודה הושלמה והתשלום שוחרר!',
    'releasePaymentError':    'שגיאה בשחרור התשלום',
    'markedDoneSuccess':      'סומן כהושלם! הלקוח יאשר את שחרור התשלום.',
    'cancelBookingTitle':     'ביטול הזמנה',
    'cancelPenaltyWarning':   'אזהרה: חלון הביטול החינמי עבר.\nלפי מדיניות {policy}, ביטול כעת יגרור קנס של ₪{penalty}.',
    'cancelRefundBreakdown':  'תקבל בחזרה: ₪{refund}\nישולם למומחה: ₪{penalty} (בניכוי עמלה)',
    'cancelSimpleConfirm':    'האם לבטל את ההזמנה?\n₪{amount} יוחזרו לארנק שלך.',
    'noGoBack':               'לא, חזור',
    'yesCancelWithPenalty':   'כן, בטל (קנס ₪{penalty})',
    'yesCancel':              'כן, בטל',
    'bookingCancelledRefund': 'ההזמנה בוטלה — ₪{amount} הוחזרו לארנק',
    'cancelError':            'שגיאה בביטול: {error}',
    'providerCancelTitle':    'ביטול מצד הספק',
    'providerCancelContent':  'ביטול מצד הספק מחזיר ללקוח 100% מהסכום\nויפחית XP מהפרופיל שלך.\n\nהאם להמשיך?',
    'providerCancelledSuccess':'ההזמנה בוטלה — הלקוח יקבל החזר מלא',
    'disputeTitle':           'פתיחת מחלוקת',
    'disputeDescription':     'תאר מה הבעיה עם השירות שניתן. הצוות שלנו יבדוק ויחליט תוך 48 שעות.',
    'disputeHint':            'תאר את הבעיה...',
    'submitDispute':          'שלח מחלוקת',
    'jobTabActive':           'פעילות',
    'jobTabHistory':          'היסטוריה',
    'jobTabCalendar':         'לוח זמינות',
    'bookingsTitle':          'ההזמנות שלי',
    'bookingsEmptyActive':    'אין הזמנות פעילות כרגע',
    'bookingsEmptyHistory':   'אין הזמנות בהיסטוריה',
    'jobStatusPaidEscrow':    'בתהליך',
    'jobStatusExpertCompleted':'ממתין לאישורך',
    'jobStatusCompleted':     'הושלם',
    'jobStatusCancelled':     'בוטל',
    'jobStatusDisputed':      'במחלוקת',
    'saveAvailability':       'שמור זמינות',
    'releasePayment':         'אשר ושחרר תשלום',
    'markDone':               'סמן כהושלם',
    'openChat':               'פתח צ\'אט',
    'openDispute':            'פתח מחלוקת',
    'cancelBooking':          'בטל הזמנה',
    'ratingTitle':            'דרג את השירות',
    'ratingSubmit':           'שלח דירוג',

    // ── Opportunities screen ───────────────────────────────────────────────────
    'oppTitle':               'לוח הזדמנויות',
    'oppAllCategories':       'כל הקטגוריות',
    'oppError':               'שגיאה: {error}',
    'oppDefaultClient':       'לקוח',
    'oppRequestUnavailable':  'הבקשה כבר לא זמינה',
    'oppRequestClosed3':      'הבקשה סגורה — כבר נמצאו 3 מתעניינים',
    'oppAlreadyExpressed':    'כבר הבעת עניין בבקשה זו',
    'oppAlready3Interested':  'הבקשה כבר קיבלה 3 מתעניינים',
    'oppInterestChatMessage': '💡 {providerName} הביע עניין בבקשת השירות שלך:\n"{description}"',
    'oppNotifTitle':          'מתעניין חדש בבקשתך!',
    'oppNotifBody':           '{providerName} מעוניין לבצע את השירות שביקשת',
    'oppBoostEarned':         '🚀 הפרופיל שלך זינק לראש תוצאות החיפוש ל-24 שעות!',
    'oppInterestSuccess':     "הבעת עניין! הצ'אט עם הלקוח נפתח",
    'oppQuickBidMessage':     'שלום {clientName}! 👋\nאני {providerName} ואני זמין לבצע את השירות שביקשת מוקדם ככל האפשר.\nמה הזמינות שלך?',
    'oppXpToNextLevel':       'עוד {xp} XP לרמת {name}',
    'oppMaxLevel':            'הגעת לרמה הגבוהה ביותר! 🏆',
    'oppProfileBoosted':      '🚀 פרופיל מוגבר! עד {time}',
    'oppBoostProgress':       'AnySkill Boost: {count}/3 — השלם 3 משימות דחופות',
    'oppTimeHours':           "{hours} שע'",
    'oppTimeMinutes':         "{minutes} ד'",
    'oppTimeJustNow':         'הרגע',
    'oppTimeMinAgo':          "לפני {minutes} דק'",
    'oppTimeHourAgo':         "לפני {hours} שע'",
    'oppTimeDayAgo':          'לפני {days} ימים',
    'oppEmptyCategory':       'אין הזדמנויות בתחום שלך כרגע',
    'oppEmptyAll':            'אין בקשות פתוחות כרגע',
    'oppEmptyCategorySubtitle': 'אין כרגע הזדמנויות חדשות בתחום שלך,\nנעדכן אותך כשיהיו 🔔',
    'oppEmptyAllSubtitle':    'בקשות חדשות מלקוחות יופיעו כאן בזמן אמת\nהישאר ערני!',
    'oppHighDemand':          'ביקוש גבוה',
    'oppViewersNow':          '{viewers} מקצוענים צופים בהזדמנות זו כרגע',
    'oppEstimatedEarnings':   'רווח נקי משוער',
    'oppAfterFee':            'אחרי עמלת AnySkill',
    'oppAlreadyInterested':   'הבעת עניין ✓',
    'oppRequestClosedBtn':    'הבקשה סגורה',
    'oppTakeOpportunity':     'קח את ההזדמנות!',
    'oppInterested':          'אני מעוניין!',
    'oppQuickBid':            'מענה מהיר — שלח הצעה אוטומטית',
    'oppWalletHint':          'לאחר סיום העבודה — רווחך יועבר לארנק AnySkill שלך',

    // ── Search page ───────────────────────────────────────────────────────────
    'helpCenterTooltip':          'מרכז עזרה',
    'searchTourSearchTitle':      '🔍 חיפוש מומחים',
    'searchTourSearchDesc':       'הקלידו שם, קטגוריה, או סוג שירות — AnySkill ימצא את הספק המתאים לכם',
    'searchTourSuggestionsTitle': '⚡ קטגוריות מומלצות',
    'searchTourSuggestionsDesc':  'AnySkill מציע שירותים בהתאם לשעה ביום — בוקר לתיקונים, ערב לספא ורווחה',
    'searchTourFeedTitle':        '✨ פיד ההשראה',
    'searchTourFeedDesc':         'עבודות אמיתיות מהאפליקציה — לחצו על כרטיס לפרופיל הספד המלא',
    'searchNoCategoriesBody':     'לא נמצאו קטגוריות.\nבצע אתחול מלוח הניהול.',
    'searchNoResultsFor':         'לא נמצאו תוצאות עבור "{query}"',
    'searchSectionCategories':    'קטגוריות',
    'searchSectionResultsFor':    'תוצאות עבור "{query}"',
    'searchRecommendedBadge':     '⭐ מומלץ',
    'searchPerHour':              ' / שעה',
    'searchDatePickerHint':       'מתי פנוי?',
    'searchChipWeekend':          'זמין בסופ"ש',
    'searchChipHomeVisit':        'ביקור בית',
    'searchUrgencyMorning':       '🔴 נותר מקום 1 בלבד להיום!',
    'searchUrgencyAfternoon':     '⚡ נותרו 2 מקומות לשבוע זה',
    'searchUrgencyEvening':       '⏰ בדרך כלל מוזמן 3 ימים מראש',
    'searchDefaultExpert':        'מומחה',
    'searchDefaultCity':          'שכונתך',
    'searchDefaultTitle':         'מומחה מוסמך',
    'editCategoryTitle':          'עריכת קטגוריה',
    'editCategoryChangePic':      'לחץ להחלפת תמונה',
    'editCategoryNameLabel':      'שם קטגוריה',
    'editCategorySaveError':      'שגיאה בשמירה: {error}',
    'creditsLabel':               'קרדיטים',
    'creditsDiscountAvailable':   '{discount}% הנחה זמינה!',
    'creditsToNextDiscount':      'עוד {remaining} להנחה הבאה',
    'inspirationFeedTitle':       'השראה — עבודות שהושלמו',
    'inspirationFeedNewBadge':    'חדש',
    'inspirationCompletedBadge':  'הושלם ✓',
    'onlineToggleOn':             'לחץ להיות זמין',
    'onlineToggleOff':            'לחץ להיות לא זמין',

    // ── Shared actions ────────────────────────────────────────────────────────
    'retryButton':                'נסה שוב',

    // ── Business AI screen ────────────────────────────────────────────────────
    'bizAiLoading':               'טוען בינה עסקית...',
    'bizAiError':                 'שגיאה: {error}',
    'bizAiTitle':                 'בינה עסקית',
    'bizAiSubtitle':              'מגמות שוק • AI • תחזיות הכנסה',
    'bizAiPending':               '{count} ממתין',
    'bizAiSectionAiOps':          'מרכז AI',
    'bizAiActivityToday':         'פעילות AI היום',
    'bizAiNewCategories':         'קטגוריות חדשות',
    'bizAiApprovalQueue':         'תור אישורים',
    'bizAiTapToReview':           'לחץ לבדיקה ›',
    'bizAiModelAccuracy':         'דיוק מודל',
    'bizAiApprovedTotal':         'אושרו / סה"כ',
    'bizAiModelAccuracyDetail':   'פירוט דיוק מודל AI',
    'bizAiApproved':              'אושרו',
    'bizAiRejected':              'נדחו',
    'bizAiPendingLabel':          'ממתין',
    'bizAiNoData':                'אין עדיין נתוני AI\nאחרי שספקים יירשמו, הסטטיסטיקה תופיע כאן',
    'bizAiSectionMarket':         'ביקוש שוק',
    'bizAiPopularSearches':       '🔥 חיפושים פופולריים',
    'bizAiNoSearchData':          'אין עדיין נתוני חיפוש — לוג יופיע אחרי שמשתמשים יחפשו',
    'bizAiMarketOpportunities':   '🎯 הזדמנויות שוק (אפס תוצאות)',
    'bizAiZeroResultsHint':       'חיפושים שלא מצאו ספקים — גייס ספקים לנישות אלו',
    'bizAiNoOpportunities':       'אין הזדמנויות ממתינות — כל החיפושים מוצאים ספקים 🎉',
    'bizAiSectionFinancial':      'תובנות פיננסיות',
    'bizAiWeeklyForecast':        'תחזית עמלות שבועית',
    'bizAiSevenDays':             '7 ימים',
    'bizAiActualToDate':          'בפועל עד היום',
    'bizAiWeeklyProjection':      'תחזית שבועית',
    'bizAiLast7Days':             'הכנסות 7 ימים אחרונים',
    'bizAiDailyCommission':       'עמלת הפלטפורמה יום אחר יום',
    'bizAiHighValueCategories':   'קטגוריות עם הכנסה גבוהה',
    'bizAiHighValueHint':         'מחיר/שעה × מספר הזמנות לפי קטגוריה',
    'bizAiNoOrderData':           'אין עדיין נתוני הזמנות',
    'bizAiProviders':             '{count} ספקים',
    'bizAiRefreshData':           'רענן נתונים',
    'bizAiThresholdUpdated':      'סף ההתראות עודכן ל-{count} חיפושים',
    'bizAiSectionAlerts':         'התראות חכמות',
    'bizAiSearches':              '{count} חיפושים',
    'bizAiAlertThreshold':        '🔔 סף התראת ביקוש',
    'bizAiAlertThresholdHint':    'שלח התראה כשמילת מפתח חסרה תחרוג X פעמים ב-24 שעות',
    'bizAiReset':                 'איפוס (5)',
    'bizAiSaveThreshold':         'שמור סף',
    'bizAiAlertHistory':          '📋 היסטוריית התראות',
    'bizAiNoAlerts':              'אין התראות עדיין — יופיעו כשמילות מפתח יחרגו מהסף',
    'bizAiAlertCount':            '{count}× התראות',
    'bizAiSearchCount':           '{count} חיפושים',
    'bizAiMinutesAgo':            "לפני {count} דק'",
    'bizAiHoursAgo':              "לפני {count} שע'",
    'bizAiDaysAgo':               'לפני {count} ימים',
    'bizAiExecSummary':           'סיכום מנהלים',
    'bizAiAccuracy':              'דיוק AI',
    'bizAiCategoriesApproved':    'קטגוריות אושרו',
    'bizAiMarketOppsCard':        'הזדמנויות שוק',
    'bizAiNichesNoProviders':     'נישות ללא ספקים',
    'bizAiExpectedRevenue':       'הכנסה צפויה',
    'bizAiForecastBadge':         'תחזית',
    'bizAiNoChartData':           'עדיין אין נתוני עמלות לגרף\nיופיע אחרי העסקה הראשונה',
    'bizAiRecruitForQuery':       'גייס ספקים עבור: "{query}"',
    'bizAiRecruitNow':            'גייס עכשיו',

    // ── Category Results screen ───────────────────────────────────────────────
    'catResultsExpertDefault':    'מומחה',
    'catResultsAvailableSlots':   'הסלוטים הפנויים הקרובים',
    'catResultsNoAvailability':   'אין זמינות ב-14 הימים הקרובים',
    'catResultsFullBooking':      'להזמנה מלאה',
    'catResultsOrderCount':       '🔥 {count} הזמנות',
    'catResultsResponseTime':     '⚡ מגיב תוך {minutes} ד׳',
    'catResultsTopRated':         '⭐ מוביל',
    'catResultsAddPhoto':         'הוסף\nתמונת\nפרופיל',
    'catResultsPerHour':          ' / שע',
    'catResultsRecommended':      'מומלץ',
    'catResultsWhenFree':         'מתי פנוי?',
    'catResultsPageTitle':        'מומחי {category}',
    'catResultsSearchHint':       'חפש לפי שם...',
    'catResultsUnder100':         'עד 100 ₪',
    'catResultsLoadError':        'שגיאה בטעינת המומחים',
    'catResultsNoResults':        'לא נמצאו תוצאות',
    'catResultsNoExperts':        'אין מומחים ב{category} עדיין',
    'catResultsNoResultsHint':    'נסה לשנות את החיפוש או לבטל את הפילטר',
    'catResultsBeFirst':          'היה הראשון להצטרף לקטגוריה זו!',
    'catResultsClearFilters':     'נקה פילטרים',

    // ── Expert Profile Screen ─────────────────────────────────────────────────
    'traitPunctual':             'תמיד בזמן',
    'traitProfessional':         'מקצועי/ת',
    'traitCommunicative':        'תקשורת מעולה',
    'traitPatient':              'סבלני/ת',
    'traitKnowledgeable':        'בעל/ת ידע',
    'traitFriendly':             'ידידותי/ת',
    'traitCreative':             'יצירתי/ת',
    'traitFlexible':             'גמיש/ה',
    'serviceSingleLesson':       'שיעור בודד',
    'serviceSingleSubtitle':     'מפגש אישי אחד',
    'serviceSingle60min':        "60 דק'",
    'serviceExtendedLesson':     'שיעור מורחב',
    'serviceExtendedSubtitle':   'כולל סיכום ומשימות',
    'serviceExtended90min':      "90 דק'",
    'serviceFullSession':        'סשן מלא',
    'serviceFullSubtitle':       'עבודה מעמיקה + תכנית אישית',
    'serviceFullSession120min':  "120 דק'",
    'expertInsufficientBalance': 'אין מספיק יתרה בארנק לביצוע ההזמנה',
    'expertEscrowSuccess':       'התור שוריין והתשלום הופקד בנאמנות!',
    'expertTransactionTitle':    'תשלום מאובטח: {name}',
    'expertSystemMessage':       '🔒 הזמנה חדשה לתאריך {date} בשעה {time}!\nסכום שיעבור אליך: ₪{amount}',
    'expertRecommendedBadge':    'מומלץ',
    'expertStatRating':          'דירוג',
    'expertStatReviews':         'ביקורות',
    'expertStatRepeatClients':   'לקוחות חוזרים',
    'expertStatResponseTime':    'זמן תגובה',
    'expertStatOrders':          'הזמנות',
    'expertStatXp':              'נקודות',
    'expertResponseTimeFormat':  "{minutes}ד'",
    'expertBioPlaceholder':      'מומחה מוסמך בקהילת AnySkill.',
    'expertBioShowLess':         'הצג פחות ▲',
    'expertBioReadMore':         'קרא עוד ▼',
    'expertSelectTime':          'בחר שעה',
    'expertReviewsCount':        '{count} ביקורות',
    'expertReviewsHeader':       'ביקורות',
    'expertNoReviews':           'אין ביקורות עדיין',
    'expertDefaultReviewer':     'לקוח',
    'expertVerifiedBooking':     'הזמנה מאובטחת',
    'expertProviderResponse':    'תגובת הספק',
    'expertAddReply':            'הוסף תגובה',
    'expertAddReplyTitle':       'הוסף תגובה לביקורת',
    'expertReplyHint':           'תודה על הביקורת...',
    'expertReplyError':          'שגיאה בשמירת התגובה: {error}',
    'expertPublishReply':        'פרסם תגובה',
    'expertBookForTime':         'הזמן ל-{time}',
    'expertStartingFrom':        'החל מ-₪{price}',
    'expertSelectDateTime':      'בחר תאריך וזמן',
    'expertBookingSummaryTitle':   'סיכום הזמנה מאובטחת',
    'expertSummaryRowService':     'שירות',
    'expertSummaryRowDate':        'תאריך',
    'expertSummaryRowTime':        'שעה',
    'expertSummaryRowPrice':       'מחיר השירות',
    'expertSummaryRowProtection':  'הגנת AnySkill',
    'expertSummaryRowIncluded':    'כלול ✓',
    'expertSummaryRowTotal':       'סה"כ לתשלום',
    'expertCancellationNotice':    'מדיניות ביטול: {policy} — ביטול חינם עד {deadline}. ביטול לאחר מכן: קנס {penalty}%.',
    'expertCancellationNoDeadline':'מדיניות ביטול: {policy} — {description}.',
    'expertConfirmPaymentButton':  'אשר תשלום ושריין מועד',
    'expertSectionAbout':         'על המומחה',
    'expertSectionService':       'בחר שירות',
    'expertSectionGallery':       'גלריה',
    'expertSectionSchedule':      'בחר מועד לשירות',

    // ── ToS screen ────────────────────────────────────────────────────────
    'tosFullTitle':           'תנאי שימוש ופרטיות',
    'tosLastUpdated':         'עדכון אחרון: מרץ 2026  |  גרסה 2.0',
    'tosBindingNotice':       'הסכם זה מחייב. אנא קרא/י בעיון לפני אישור.',
    'tosAcceptButton':        'קראתי, הבנתי ומסכים/ה לתנאים',

    // ── Finance screen ────────────────────────────────────────────────────
    'financeTitle':           'החשבון שלי',
    'financeTrustBadge':      'נאמנות AnySkill',
    'financeAvailableBalance': 'יתרה ניתנת למשיכה',
    'financeMinWithdraw':     'מינימום למשיכה: ₪50',
    'financeWithdrawButton':  'משוך כספים',
    'financeRecentActivity':  'פעולות אחרונות',
    'financeError':           'שגיאה: {error}',
    'financeNoTransactions':  'אין עדיין פעולות בחשבונך',
    'financePaidTo':          'שילמת ל-{name}',
    'financeReceivedFrom':    'קיבלת מ-{name}',
    'financeProcessing':      'מעבד...',

    // ── Withdrawal modal ──────────────────────────────────────────────────
    'withdrawMinBalance':     'יתרה מינימלית למשיכה: ₪{amount}',
    'withdrawAvailableBalance': 'יתרה זמינה למשיכה',
    'withdrawTaxStatusTitle': 'בחר את סטטוס המס שלך',
    'withdrawTaxStatusSubtitle': 'נדרש לעיבוד התשלום בהתאם לחוק',
    'withdrawTaxBusiness':    'בעל עסק רשום',
    'withdrawTaxBusinessSub': 'עוסק פטור / עוסק מורשה / חברה',
    'withdrawTaxIndividual':  'פרטי (ללא רישיון עסק)',
    'withdrawTaxIndividualSub': 'שכיר / עצמאי ללא תיק במס הכנסה',
    'withdrawTaxIndividualBadge': 'קל ומהיר',
    'withdrawEncryptedNotice': 'הפרטים שלך מאובטחים ומוצפנים',
    'withdrawBankEncryptedNotice': 'הפרטים הבנקאיים שלך מוצפנים ומאובטחים',
    'withdrawCertSection':    'אישור עוסק',
    'withdrawBankSection':    'פרטי חשבון בנק',
    'withdrawBankName':       'שם הבנק',
    'withdrawBankBranch':     'מספר סניף',
    'withdrawBankAccount':    'מספר חשבון',
    'withdrawBankRequired':   'חובה לבחור בנק',
    'withdrawBranchRequired': 'חובה',
    'withdrawAccountMinDigits': "מינ' 4 ספרות",
    'withdrawSelectBankError': 'בחר שם בנק',
    'withdrawNoCertError':    'יש להעלות אישור עוסק לפני המשך',
    'withdrawNoDeclarationError': 'יש לאשר את הצהרת האחריות למס לפני המשך',
    'withdrawUploadError':    'שגיאה בהעלאת הקובץ — נסה שוב',
    'withdrawSubmitError':    'שגיאה בשליחת הבקשה — נסה שוב',
    'withdrawSubmitButton':   'שלח בקשת משיכה — {amount}',
    'withdrawSuccessTitle':   'הבקשה התקבלה! 🎉',
    'withdrawSuccessSubtitle': 'בקשת משיכה של {amount} נשלחה לעיבוד',
    'withdrawSuccessNotice':  'יתרתך תעודכן לאחר עיבוד הבקשה על ידי הצוות. לשאלות: support@anyskill.co.il',
    'withdrawTimeline1Title': 'הבקשה התקבלה',
    'withdrawTimeline1Sub':   'מספר אסמכתא נשלח למייל',
    'withdrawTimeline2Title': 'בדיקה ואימות',
    'withdrawTimeline2Sub':   'צוות AnySkill מאמת את הפרטים',
    'withdrawTimeline3Title': 'כסף בחשבון',
    'withdrawTimeline3Sub':   'עד 3-5 ימי עסקים',
    'withdrawDeclarationText': 'אני מצהיר/ה על אחריותי הבלעדית לדיווח מס כחוק ',
    'withdrawDeclarationSection': '(סעיף 6 בתקנון)',
    'withdrawDeclarationSuffix': '. ידוע לי כי AnySkill אינה מעסיקתי ואינה מנכה מס במקור.',
    'withdrawExistingCert':   'אישור קיים',
    'withdrawCertUploadBtn':  'העלה אישור עוסק',
    'withdrawCertReplace':    'לחץ להחלפה',
    'withdrawCertHint':       'JPG / PNG — אישור עוסק פטור/מורשה',
    'withdrawIndividualTitle': 'חשבונית לשכיר — שירות השותף שלנו',
    'withdrawIndividualDesc': 'אין לך עוסק? אין בעיה! דרך שירות "חשבונית לשכיר" נוכל לבצע את התשלום בצורה חוקית לחלוטין. תחול עמלת שירות קטנה.',
    'withdrawBankTransferPending': 'משיכה לחשבון בנק — בטיפול',
    'withdrawBusinessFormTitle': 'בעל עסק רשום',
    'withdrawIndividualFormTitle': 'פרטי (ללא רישיון)',

    // ── Onboarding screen ─────────────────────────────────────────────────
    'onboardingStep':         'שלב {step} מתוך {total}',
    'onboardingWelcome':      'ברוך הבא ל-AnySkill! 👋',
    'onboardingWelcomeSub':   'ספר לנו מי אתה כדי שנוכל להתאים את החוויה',
    'onboardingRoleCustomerTitle': 'אני מחפש שירות',
    'onboardingRoleCustomerSub': 'אני רוצה להזמין מומחים לצרכים שלי',
    'onboardingRoleProviderTitle': 'אני נותן שירות',
    'onboardingRoleProviderSub': 'יש לי מיומנות ואני רוצה לעבוד דרך AnySkill',
    'onboardingBothRoles':    'מעולה! תוכל גם להזמין וגם לתת שירות.',
    'onboardingServiceTitle': 'פרטי השירות שלך',
    'onboardingServiceSub':   'מה תחום ההתמחות שלך ומה המחיר שלך לשעה?',
    'onboardingCategory':     'תחום התמחות',
    'onboardingCategoryHint': 'בחר תחום...',
    'onboardingPriceLabel':   'מחיר לשעה (₪)',
    'onboardingPriceHint':    'למשל: 150',
    'onboardingPriceTip':     'המחיר הממוצע בקטגוריה זו הוא ₪100–₪200 לשעה.',
    'onboardingProfileTitle': 'הפרופיל שלך',
    'onboardingProfileSub':   'תמונה ותיאור קצר עוזרים לאנשים לסמוך עליך',
    'onboardingAddPhoto':     'הוסף תמונת פרופיל',
    'onboardingBioLabel':     'כמה מילים עליך (אופציונלי)',
    'onboardingBioHint':      'ספר קצת על עצמך...',
    'onboardingSkipFinish':   'דלג ולחץ לסיום',
    'onboardingNext':         'המשך',
    'onboardingStart':        'התחל להשתמש ב-AnySkill',
    'onboardingError':        'שגיאה: {error}',
    'onboardingUploadError':  'שגיאה בהעלאה: {error}',

    // ── Onboarding — Tax Compliance step ─────────────────────────────────
    'onboardingTaxTitle':         'אימות מס ורישוי',
    'onboardingTaxSubtitle':      'נדרש לפני קבלת עבודות בפלטפורמה',
    'onboardingTaxNotice':        'AnySkill היא פלטפורמה מקצועית בלבד. אנו מחויבים לאמת את תיעוד המס שלך לפני שתוכל לקבל הזמנות — לבטיחות שלך ושל הלקוחות.',
    'onboardingTaxStatusLabel':   'סטטוס מס',
    'onboardingTaxStatusRequired':'יש לבחור סטטוס מס לפני ההמשך',
    'onboardingDocRequired':      'יש להעלות מסמך לפני ההמשך',
    'onboardingTaxBusiness':      'עוסק רשום (עוסק פטור / מורשה)',
    'onboardingTaxBusinessSub':   'בעל עסק רשום עם תיק במע"מ',
    'onboardingTaxIndividual':    'חשבונית דרך צד שלישי',
    'onboardingTaxIndividualSub': 'שכיר — נפיק חשבונית בשמך דרך שותף',
    'onboardingDocLabelBusiness': 'אישור ניהול ספרים / פתיחת תיק',
    'onboardingDocLabelIndividual':'צילום תעודת זהות',
    'onboardingDocHintBusiness':  'צלם את האישור שקיבלת ממע"מ (JPG / PNG)',
    'onboardingDocHintIndividual':'צלם את שני צדי תעודת הזהות (JPG / PNG)',
    'onboardingDocUploadPrompt':  'לחץ לבחירת קובץ מהגלריה',
    'onboardingDocUploadSub':     'JPG · PNG · PDF · מקסימום 10MB',
    'onboardingUploading':        'מעלה...',
    'onboardingDocUploaded':      'הועלה בהצלחה ✓',
    'onboardingDocReplace':       'החלף',

    // ── Opportunities lock screen ─────────────────────────────────────────
    'oppUnderReviewTitle':    'החשבון בבדיקה',
    'oppUnderReviewSubtitle': 'אנו מאמתים את מסמכי המס שלך',
    'oppUnderReviewBody':     'AnySkill היא פלטפורמה מקצועית בלבד. הצוות שלנו בודק את המסמכים שהגשת ויאשר את חשבונך תוך 24–48 שעות.\n\nתקבל התראה ברגע שהחשבון יאושר ותוכל להתחיל לקבל הזמנות.',
    'oppUnderReviewStep1':    'מסמכים התקבלו',
    'oppUnderReviewStep2':    'ביקורת מנהל',
    'oppUnderReviewStep3':    'חשבון פעיל',
    'oppUnderReviewContact':  'לשאלות: support@anyskill.co.il',

    // ── Admin — Compliance verification ───────────────────────────────────
    'adminVerifyProvider':    'אמת ספק',
    'adminUnverifyProvider':  'בטל אימות ספק',
    'adminVerifiedSuccess':   '{name} אומת — הגישה לעבודות אופשרה ✓',
    'adminUnverifiedSuccess': 'אימות {name} בוטל',
    'adminViewDoc':           'צפה במסמך',
    'adminComplianceSection': 'ציות ומיסוי',
    'adminComplianceTaxStatus': 'סטטוס מס',
    'adminCompliancePending': 'ממתין לאימות',
    'adminComplianceApproved':'מאושר',

    // ── Help Center screen ────────────────────────────────────────────────
    'helpCenterProviderSupport': 'תמיכת ספקים',
    'helpCenterCustomerSupport': 'תמיכת לקוחות',
    'helpCenterProviderWelcome': 'שלום! אני עוזר המומחים של AnySkill 👋\nכאן תמצאו טיפים לניהול הפרופיל, השגת הזמנות, ועוד.\n\nבמה אוכל לעזור היום?',
    'helpCenterCustomerWelcome': 'שלום! אני עוזר הלקוחות של AnySkill 👋\nיש לי תשובות לכל שאלה — בחרו מהרשימה או כתבו בחופשיות.\n\nבמה אוכל לעזור?',
    'helpCenterProviderFaq':  'שאלות נפוצות לספקים',
    'helpCenterCustomerFaq':  'שאלות נפוצות ללקוחות',
    'helpCenterInputHint':    'כתוב שאלה חופשית...',
    'helpCenterTitle':        'מרכז העזרה',

    // ── Dispute Resolution ────────────────────────────────────────────────────
    'disputeOpenDisputes':    'מחלוקות פתוחות',
    'disputeLockedEscrow':    'נעול בנאמנות',
    'disputeTapForDetails':   'לחץ לפרטים ופעולות',
    'disputePartyCustomer':   'לקוח',
    'disputePartyProvider':   'ספק',
    'disputeArbitrationCenter': 'מרכז בוררות',
    'disputeIdPrefix':        'מזהה:',
    'disputeLockedSuffix':    'נעול',
    'disputePartiesSection':  'צדדים',
    'disputeReasonSection':   'סיבת המחלוקת',
    'disputeNoReason':        'לא הוזנה סיבה.',
    'disputeChatHistory':     'היסטוריית שיחה (10 הודעות אחרונות)',
    'disputeAdminNote':       'הערת מנהל (אופציונלי)',
    'disputeAdminNoteHint':   'הוסף הערה שתישמר ברשומת ההחלטה...',
    'disputeExistingNote':    'הערה קיימת: {note}',
    'disputeActionsSection':  'פעולות בוררות',
    'disputeResolving':       'מבצע פעולה...',
    'disputeRefundLabel':     'החזר ללקוח',
    'disputeRefundSublabel':  'החזר מלא ₪{amount}',
    'disputeReleaseLabel':    'שחרר למומחה',
    'disputeReleaseSublabel': 'לאחר עמלה (≈₪{amount})',
    'disputeSplitLabel':      'פשרה 50/50',
    'disputeSplitSublabel':   '₪{amount} לכל צד',
    'disputeConfirmRefund':   'החזר מלא ללקוח',
    'disputeConfirmRelease':  'שחרור למומחה',
    'disputeConfirmSplit':    'פשרה 50/50',
    'disputeRefundBody':      '₪{amount} יוחזרו ל{name}.\nהמומחה לא יקבל תשלום.',
    'disputeReleaseBody':     '₪{amount} יועברו ל{name}\n(לאחר עמלת {fee}%).',
    'disputeSplitBody':       '₪{half} → לקוח\n₪{halfNet} → מומחה (לאחר עמלה)\n₪{platform} → הפלטפורמה',
    'disputeIrreversible':    'פעולה זו אינה הפיכה. ההחלטה תישמר ו-FCM יישלח לשני הצדדים.',
    'disputeResolvedRefund':  '✅ הסכום הוחזר ללקוח. הודעה נשלחה לשני הצדדים.',
    'disputeResolvedRelease': '✅ הסכום שוחרר למומחה. הודעה נשלחה לשני הצדדים.',
    'disputeResolvedSplit':   '⚖️ פשרה בוצעה. הודעה נשלחה לשני הצדדים.',
    'disputeErrorPrefix':     'שגיאה: {error}',
    'disputeNoChatId':        'אין מזהה שיחה.',
    'disputeNoMessages':      'אין הודעות בשיחה.',
    'disputeSystemSender':    'מערכת',
    'disputeTypeImage':       '📷 תמונה',
    'disputeTypeLocation':    '📍 מיקום',
    'disputeTypeAudio':       '🎤 הקלטה',
    'disputeOpenedAt':        'נפתח ב-{date}',
    'disputeEmptyTitle':      'אין מחלוקות פתוחות',
    'disputeEmptySubtitle':   'כל הפעולות מסודרות 🎉',
    // ── My Calendar ───────────────────────────────────────────────────────────
    'calendarTitle':          'היומן שלי',
    'calendarRefresh':        'רענן',
    'calendarNoEvents':       'אין הזמנות ביום זה',
    'calendarStatusPending':  'ממתין לביצוע',
    'calendarStatusWaiting':  'ממתין לאישור',
    'calendarStatusCompleted': 'הושלם',
    // ── My Requests ───────────────────────────────────────────────────────────
    'requestsTitle':          'הבקשות שלי',
    'requestsEmpty':          'אין בקשות פעילות',
    'requestsEmptySubtitle':  'שדר בקשה מהירה ותוך שניות\nספקים מקצועיים יפנו אליך!',
    'requestsInterested':     '{count} מתעניינים',
    'requestsWaiting':        'ממתין למתעניינים...',
    'requestsWaitingProviders': 'ממתין לספקים מתעניינים...',
    'requestsClosed':         'הבקשה נסגרה',
    'requestsViewInterested': 'צפה ב-{count} מתעניינים',
    'requestsInterestedTitle': 'מתעניינים בבקשתך',
    'requestsNoInterested':   'אין מתעניינים עדיין',
    'requestsJustNow':        'הרגע',
    'requestsMinutesAgo':     "לפני {minutes} דק'",
    'requestsHoursAgo':       "לפני {hours} שע'",
    'requestsDaysAgo':        'לפני {days} ימים',
    'requestsDefaultExpert':  'מומחה',
    'requestsHiredAgo':       'נשכר {ago}',
    'requestsOrderCount':     '🔥 {count} הזמנות',
    'requestsTopMatch':       'התאמה הטובה ביותר',
    'requestsMatchLabel':     'התאמה',
    'requestsChatNow':        'שוחח עכשיו',
    'requestsConfirmPay':     'אשר ושלם',
    'requestsMoneyProtected': 'הכסף מוגן עד סיום העבודה',
    'requestsEscrowTooltip':  'הכסף מוחזק בנאמנות על ידי AnySkill ומועבר למומחה רק לאחר אישורך בסיום העבודה.',
    'requestsVerifiedBadge':  'AnySkill Verified — תשלום מאובטח בנאמנות',
    'requestsPricePerHour':   '₪{price} / שעה',
    'requestsBestValue':      'הכי משתלם',
    'requestsFastResponse':   'תגובה מהירה',
    // ── XP Manager ────────────────────────────────────────────────────────────
    'xpManagerTitle':         'XP & מערכת רמות',
    'xpManagerSubtitle':      'הגדרת אירועים, נקודות וסף עליית רמה',
    'xpEventsSection':        'אירועי XP',
    'xpEventsCount':          '{count} אירועים',
    'xpEventsEmpty':          'אין אירועים עדיין.\nלחץ "הוסף אירוע" להתחלה.',
    'xpAddEventButton':       'הוסף אירוע',
    'xpEditEventTitle':       'עריכת אירוע XP',
    'xpAddEventTitle':        'הוספת אירוע XP חדש',
    'xpFieldId':              'מזהה אירוע (באנגלית, ללא רווחים)',
    'xpFieldIdHint':          'e.g. late_delivery',
    'xpFieldName':            'שם האירוע בעברית',
    'xpFieldPoints':          'נקודות XP (שלילי = עונש)',
    'xpFieldDesc':            'תיאור קצר',
    'xpEventUpdated':         'האירוע עודכן ✓',
    'xpEventAdded':           'האירוע נוסף ✓',
    'xpEventDeleted':         'האירוע נמחק',
    'xpDeleteEventTitle':     'מחיקת אירוע',
    'xpDeleteEventConfirm':   'למחוק את האירוע "{name}"?\nפעולה זו אינה הפיכה.',
    'xpReservedId':           'המזהה "app_levels" שמור למערכת',
    'xpTooltipEdit':          'ערוך',
    'xpTooltipDelete':        'מחק',
    'xpLevelsTitle':          'סף עליית רמה',
    'xpLevelsSubtitle':       'הגדר את מינימום ה-XP הנדרש לכל רמה.',
    'xpSaveLevels':           'שמור סף רמות',
    'xpLevelsSaved':          'סף הרמות עודכן ✓',
    'xpLevelsError':          'כסף חייב להיות > 0 וזהב חייב להיות > כסף',
    'xpLevelBronze':          'ברונזה',
    'xpLevelSilver':          'כסף',
    'xpLevelGold':            'זהב',
    'xpSaveAction':           'שמור',
    'xpAddAction':            'הוסף',
    'xpErrorPrefix':          'שגיאה: {error}',
    // ── System Wallet ─────────────────────────────────────────────────────────
    'systemWalletTitle':      'ניהול כספי מערכת',
    'systemWalletBalance':    'יתרה נזילה בארנק המערכת',
    'systemWalletPendingFees': 'עמלות בהמתנה',
    'systemWalletActiveJobs': '{count} עסקאות פעילות (escrow / ממתין לאישור)',
    'systemWalletFeePanel':   'קביעת אחוז עמלה גלובלי',
    'systemWalletUpdateFee':  'עדכן',
    'systemWalletFeeUpdated': 'העמלה עודכנה ל-{value}%!',
    'systemWalletEnterNumber': 'נא להזין מספר',
    'systemWalletInvalidNumber': 'נא להזין מספר תקין',
    'systemWalletEarningsTitle': 'פירוט הכנסות מעמלות (זמן אמת)',
    'systemWalletExportCsv':  'ייצוא CSV',
    'systemWalletExported':   'יוצאו {count} רשומות ל-CSV',
    'systemWalletExportError': 'שגיאה בייצוא: {error}',
    'systemWalletNoEarnings': 'אין עמלות רשומות במערכת',
    'systemWalletTxStatus':   'סטטוס: התקבל בהצלחה',
    // ── Pending Categories ────────────────────────────────────────────────────
    'pendingCatsTitle':       'קטגוריות ממתינות לאישור',
    'pendingCatsSectionPending': 'ממתינות לאישור',
    'pendingCatsSectionReviewed': 'טופלו',
    'pendingCatsApproved':    '✅ קטגוריה אושרה ופורסמה!',
    'pendingCatsRejected':    '🗑 קטגוריה נדחתה',
    'pendingCatsErrorPrefix': 'שגיאה: {error}',
    'pendingCatsSubCategory': 'תת-קטגוריה: {name}',
    'pendingCatsProviderDesc': 'תיאור הספק',
    'pendingCatsAiReason':    'הנמקת AI',
    'pendingCatsImagePrompt': 'פרומפט לתמונה (Midjourney/DALL-E)',
    'pendingCatsReject':      'דחה',
    'pendingCatsApprove':     'אשר ופרסם',
    'pendingCatsStatusApproved': 'אושר',
    'pendingCatsStatusRejected': 'נדחה',
    'pendingCatsEmptyTitle':  'אין קטגוריות ממתינות',
    'pendingCatsEmptySubtitle': 'כל הקטגוריות אושרו או שעדיין לא נוצרו',
    'pendingCatsOpenedAt':    'נפתח ב-{date}',
  },

  // ───────────────────────────────────────────────── ENGLISH ────────────────
  'en': {
    // App
    'appName':                'AnySkill',
    'appSlogan':              'AnySkill — Your Skills, Their Service',

    // Navigation
    'tabHome':                'Home',
    'tabBookings':            'Bookings',
    'tabChat':                'Chat',
    'tabWallet':              'Wallet',
    'tabProfile':             'Profile',

    // Common
    'cancel':                 'Cancel',
    'confirm':                'Confirm',
    'submit':                 'Submit',
    'save':                   'Save',
    'close':                  'Close',
    'delete':                 'Delete',
    'open':                   'Open',
    'back':                   'Back',

    'errorGeneric':           'An error occurred. Please try again',
    'currencySymbol':         '₪',

    // App-level
    'updateBannerText':       "We've upgraded AnySkill for you!\nA new version is available with performance improvements 🚀",
    'updateNowButton':        'Update Now',
    'notifOpen':              'Open',

    // Auth
    'loginTitle':             'Welcome to AnySkill',
    'loginAccountTitle':      'Sign In',
    'loginWelcomeBack':       'Welcome back! Your experts are waiting',
    'loginEmail':             'Email Address',
    'loginPassword':          'Password',
    'loginButton':            'Sign In →',
    'loginRememberMe':        'Remember me',
    'loginForgotPassword':    'Forgot password',
    'loginNoAccount':         "Don't have an account? ",
    'loginSignUpFree':        'Sign up for free',
    'loginOrWith':            'Or sign in with',
    'loginAppleComingSoon':   'Apple Sign-In coming soon',
    'loginStats10k':          'Professionals',
    'loginStats50':           'Categories',
    'loginStats49':           'Rating',

    // Auth errors
    'errorUserNotFound':      'No account found with this email',
    'errorWrongPassword':     'Incorrect password — please try again',
    'errorInvalidCredential': 'Invalid email or password',
    'errorInvalidEmail':      'Invalid email address',
    'errorUserDisabled':      'This account has been disabled',
    'errorTooManyRequests':   'Too many attempts — please try again in a few minutes',
    'errorNetworkFailed':     'Network error — check your connection',
    'errorGenericLogin':      'Sign-in error, please try again',
    'errorEmptyFields':       'Please enter your email and password',
    'errorGoogleLogin':       'Error signing in with Google',

    // Forgot password
    'forgotPasswordTitle':    'Reset Password',
    'forgotPasswordSubtitle': 'Enter your email and we\'ll send you a reset link',
    'forgotPasswordEmail':    'Email Address',
    'forgotPasswordSubmit':   'Send Reset Link',
    'forgotPasswordSuccess':  'Reset link sent to your email ✉️',
    'forgotPasswordError':    'Error — make sure the email is registered',

    // Sign-up
    'signupButton':           'Sign Up',
    'signupTitle':            'Join AnySkill',
    'googleNewUserBio':       'New AnySkill customer',

    // Validation
    'validationNameRequired': 'Please enter your name',
    'validationNameLength':   'Name must be at least 2 characters',
    'validationRoleRequired': 'Please select at least one role',
    'validationCategoryRequired': 'Please select a service category',
    'validationPriceInvalid': 'Price must be a valid number',
    'validationPricePositive':'Price must be greater than 0',

    // Profile
    'profileTitle':           'My Profile',
    'shareProfileTitle':      'Share Profile to Boost Sales',
    'shareProfileWhatsapp':   'Send via WhatsApp',
    'shareProfileCopyLink':   'Copy Profile Link',
    'shareProfileTooltip':    'Share Profile',
    'linkCopied':             'Link copied! Paste it anywhere.',
    'whatsappError':          'Cannot open WhatsApp in this browser',
    'defaultUserName':        'Anonymous User',
    'logoutTooltip':          'Sign Out',
    'logoutTitle':            'Sign Out',
    'logoutContent':          'Are you sure you want to sign out?',
    'logoutConfirm':          'Sign Out',
    'logoutButton':           'Sign Out',
    'aboutMeTitle':           'About Me',
    'aboutMePlaceholder':     'No description yet.',
    'galleryTitle':           'Work Gallery',
    'galleryEmpty':           'No photos in gallery',
    'statRating':             'Rating',
    'statBalance':            'Balance',
    'statWorks':              'Jobs',
    'bookingsTrackerButton':  'Track My Bookings',
    'bookingsTrackerSnackbar':'Going to chats to track transactions...',

    // VIP
    'vipActiveLabel':         'VIP Active',
    'vipExpiredLabel':        'Expired',
    'vipHighlight':           'Your profile appears first in search with a golden glow ✨',
    'vipUpsellTitle':         'VIP Boosted Visibility',
    'vipBenefit1':            'Listed first in all search results',
    'vipBenefit2':            "Golden glow + 'Recommended' badge",
    'vipBenefit3':            'Up to 5× more profile views',
    'vipBenefit4':            'Priority for urgent requests',
    'vipCtaButton':           'Join VIP — ₪99/month',
    'vipSheetHeader':         'Join VIP',
    'vipPriceMonthly':        '/month',
    'vipActivateButton':      '⭐ Activate VIP — ₪99 from balance',
    'vipInsufficientBalance': 'Insufficient balance (₪99 required)',
    'vipInsufficientTooltip': 'Top up your wallet to activate VIP',
    'vipActivationSuccess':   '🎉 Welcome to VIP! Your profile is now listed first',

    // Language
    'languageTitle':          'Language',
    'languageHe':             'Hebrew',
    'languageEn':             'English',
    'languageEs':             'Spanish',
    'languageSectionLabel':   'Interface Language',

    // Chat list
    'chatListTitle':          'Messages',
    'chatSearchHint':         'Search conversations...',
    'chatEmptyState':         'No conversations yet',
    'chatUserDefault':        'User',
    'chatLastMessageDefault': 'New message',
    'markAllReadTooltip':     'Mark all as read',
    'markAllReadSuccess':     'All messages marked as read',
    'deleteChatTitle':        'Delete Conversation',
    'deleteChatContent':      'Are you sure you want to delete this entire conversation history?',
    'deleteChatConfirm':      'Delete',
    'deleteChatSuccess':      'Conversation deleted',
    'notLoggedIn':            'Please sign in again',

    // Search
    'searchPlaceholder':      'Search for a professional, service...',
    'searchTitle':            'Search',
    'discoverCategories':     'Discover Categories',
    'searchHintExperts':      'What do you need today?',
    'greetingMorning':        'Good Morning',
    'greetingAfternoon':      'Good Afternoon',
    'greetingEvening':        'Good Evening',
    'greetingNight':          'Good Night',
    'greetingSubMorning':     'What needs fixing this morning?',
    'greetingSubAfternoon':   'Looking for a pro? Now is the time',
    'greetingSubEvening':     'Treat yourself tonight!',
    'greetingSubNight':       'Discover top experts',

    // Home
    'onlineStatus':           'Available',
    'offlineStatus':          'Unavailable',
    'quickRequest':           'Quick Request',
    'urgentJobBanner':        'New job available!',

    // Bookings
    'bookNow':                'Book Now',

    // Wallet
    'walletBalance':          'Available Balance',
    'walletMinWithdraw':      'Minimum withdrawal: ₪50',
    'withdrawFunds':          'Withdraw Funds',

    // ToS
    'tosTitle':               'Terms of Service',
    'tosAgree':               'I have read and agree to the Terms',

    // Misc
    'trendingBadge':          'Trending',
    'subCategoryPrompt':      'Choose Specialty',
    'reviewSubmit':           'Submit Review',
    'urgentOpenButton':       'Open',

    // Edit profile
    'editProfileTitle':       'Edit Profile',
    'saveSuccess':            'Profile updated successfully!',
    'profileFieldName':       'Full Name',
    'profileFieldNameHint':   'How should people know you?',
    'profileFieldRole':       'Role Settings',
    'roleProvider':           'Service Provider',
    'roleCustomer':           'Customer',
    'profileFieldCategoryMain':     'Main Service Area',
    'profileFieldCategoryMainHint': 'Choose category',
    'profileFieldCategorySub':      'Specific Specialty (Sub-category)',
    'profileFieldCategorySubHint':  'Choose specialty',
    'profileFieldPrice':      'Hourly Rate (₪)',
    'profileFieldPriceHint':  'How much do you want to earn?',
    'profileFieldResponseTime':     'Average Response Time',
    'profileFieldTaxId':      'ID / Business Number (for invoices)',
    'profileFieldTaxIdHint':  'e.g. 123456789',
    'profileFieldTaxIdHelp':  'Shown on digital receipts sent to clients',
    'saveChanges':            'Save Changes',
    'saveError':              'Error saving: {error}',
    'profileFieldResponseTimeHint': 'How quickly do you usually respond to messages?',
    'editProfileQuickTags':   'Quick Tags',
    'editProfileTagsSelected':'{count}/3 selected',
    'editProfileTagsHint':    'Choose up to 3 tags to display on your card',
    'editProfileCancellationPolicy': 'Cancellation Policy',
    'editProfileCancellationHint':   'Customers will see this policy before booking',
    'editProfileAbout':       'Personal Description (About)',
    'editProfileAboutHint':   'Tell us a bit about your experience...',
    'editProfileGallery':     'Work Gallery (Portfolio)',

    // ── Home tab ─────────────────────────────────────────────────────────────
    'homeProviderGreetingSub': 'What\'s in the pipeline today?',
    'homeCustomerGreetingSub': 'What do you need?',
    'noCategoriesYet':        'No categories yet',
    'urgentBannerRequests':   'requests',
    'urgentBannerPending':    'pending',
    'urgentBannerCustomerWaiting': 'Customer is waiting for your approval',
    'urgentBannerServiceNeeded':   'Service needed',
    'timeOneHour':            '1 hour',

    // ── Notifications ─────────────────────────────────────────────────────────
    'notificationsTitle':     'Notifications',
    'notifClearAll':          'Clear All',
    'notifEmptyTitle':        'No notifications yet',
    'notifEmptySubtitle':     'Account activity will appear here',
    'timeNow':                'Now',
    'timeMinutesAgo':         '{minutes} min ago',
    'timeHoursAgo':           '{hours} hours ago',

    // ── Sign Up ───────────────────────────────────────────────────────────────
    'signupTosMustAgree':     'Please agree to the Terms of Service to continue',
    'signupAccountCreated':   'Account created! Welcome to AnySkill 🎉',
    'signupEmailInUse':       'Email address is already registered',
    'signupWeakPassword':     'Password is too weak — try a stronger one',
    'signupNetworkError':     'Network error — check your internet connection',
    'signupGenericError':     'Registration error',
    'signupNewProviderBio':   'New expert in the AnySkill community 🚀',
    'signupNewCustomerBio':   'New AnySkill customer',
    'signupIAmCustomer':      'I\'m a Customer',
    'signupIAmProvider':      'I\'m a Provider',
    'signupCustomerDesc':     'Looking for professionals to help',
    'signupProviderDesc':     'Offering services and earning',
    'signupName':             'Full Name',
    'signupNameHint':         'Name shown on your profile',
    'signupEmail':            'Email Address',
    'signupEmailHint':        'example@email.com',
    'signupPassword':         'Password',
    'signupPasswordHint':     'At least 8 characters',
    'signupPhone':            'Phone (optional)',
    'signupPhoneHint':        '050-1234567',
    'signupCategory':         'Service Area',
    'signupTosPrefix':        'I have read and agree to the ',
    'signupTosLink':          'Terms of Service',
    'signupHaveAccount':      'Already have an account? ',
    'signupLogin':            'Sign In',
    'signupOrWith':           'Or sign up with',
    'signupGoogleError':      'Error signing up with Google',
    'signupPasswordStrength0':'Very Weak',
    'signupPasswordStrength1':'Weak',
    'signupPasswordStrength2':'Fair',
    'signupPasswordStrength3':'Strong',
    'signupPasswordStrength4':'Very Strong',
    'signupNameValidation':   'Name required (at least 2 chars)',
    'signupEmailValidation':  'Invalid email address',
    'signupPasswordValidation':'At least 6 characters',
    'signupCategoryRequired': 'Choose a category',

    // ── Bookings ──────────────────────────────────────────────────────────────
    'availabilityUpdated':    'Availability updated successfully',
    'bookingCompleted':       'Job completed and payment released!',
    'releasePaymentError':    'Error releasing payment',
    'markedDoneSuccess':      'Marked as done! Customer will confirm payment release.',
    'cancelBookingTitle':     'Cancel Booking',
    'cancelPenaltyWarning':   'Warning: Free cancellation window has passed.\nPer {policy} policy, cancelling now will incur a ₪{penalty} fee.',
    'cancelRefundBreakdown':  'You\'ll receive: ₪{refund}\nExpert will receive: ₪{penalty} (minus commission)',
    'cancelSimpleConfirm':    'Cancel this booking?\n₪{amount} will be returned to your wallet.',
    'noGoBack':               'No, Go Back',
    'yesCancelWithPenalty':   'Yes, Cancel (₪{penalty} fee)',
    'yesCancel':              'Yes, Cancel',
    'bookingCancelledRefund': 'Booking cancelled — ₪{amount} returned to wallet',
    'cancelError':            'Cancellation error: {error}',
    'providerCancelTitle':    'Provider Cancellation',
    'providerCancelContent':  'Provider cancellation gives the customer 100% refund\nand reduces XP from your profile.\n\nProceed?',
    'providerCancelledSuccess':'Booking cancelled — customer will receive full refund',
    'disputeTitle':           'Open Dispute',
    'disputeDescription':     'Describe the issue with the service. Our team will review and decide within 48 hours.',
    'disputeHint':            'Describe the issue...',
    'submitDispute':          'Submit Dispute',
    'jobTabActive':           'Active',
    'jobTabHistory':          'History',
    'jobTabCalendar':         'Availability',
    'bookingsTitle':          'My Bookings',
    'bookingsEmptyActive':    'No active bookings right now',
    'bookingsEmptyHistory':   'No bookings in history',
    'jobStatusPaidEscrow':    'In Progress',
    'jobStatusExpertCompleted':'Awaiting Your Approval',
    'jobStatusCompleted':     'Completed',
    'jobStatusCancelled':     'Cancelled',
    'jobStatusDisputed':      'Disputed',
    'saveAvailability':       'Save Availability',
    'releasePayment':         'Confirm & Release Payment',
    'markDone':               'Mark as Done',
    'openChat':               'Open Chat',
    'openDispute':            'Open Dispute',
    'cancelBooking':          'Cancel Booking',
    'ratingTitle':            'Rate the Service',
    'ratingSubmit':           'Submit Rating',

    // ── Opportunities screen ───────────────────────────────────────────────────
    'oppTitle':               'Opportunities Board',
    'oppAllCategories':       'All Categories',
    'oppError':               'Error: {error}',
    'oppDefaultClient':       'Client',
    'oppRequestUnavailable':  'This request is no longer available',
    'oppRequestClosed3':      'Request closed — 3 interested providers found',
    'oppAlreadyExpressed':    'You have already expressed interest in this request',
    'oppAlready3Interested':  'This request already has 3 interested providers',
    'oppInterestChatMessage': '💡 {providerName} expressed interest in your service request:\n"{description}"',
    'oppNotifTitle':          'New interest in your request!',
    'oppNotifBody':           '{providerName} wants to fulfil your service request',
    'oppBoostEarned':         '🚀 Your profile jumped to the top of search results for 24 hours!',
    'oppInterestSuccess':     'Interest expressed! Chat with the client is open',
    'oppQuickBidMessage':     'Hello {clientName}! 👋\nI\'m {providerName} and I\'m available to fulfil your service request as soon as possible.\nWhat\'s your availability?',
    'oppXpToNextLevel':       '{xp} more XP to reach {name} level',
    'oppMaxLevel':            'You\'ve reached the highest level! 🏆',
    'oppProfileBoosted':      '🚀 Profile boosted! Until {time}',
    'oppBoostProgress':       'AnySkill Boost: {count}/3 — Complete 3 urgent tasks',
    'oppTimeHours':           '{hours}h',
    'oppTimeMinutes':         '{minutes}m',
    'oppTimeJustNow':         'Just now',
    'oppTimeMinAgo':          '{minutes} min ago',
    'oppTimeHourAgo':         '{hours}h ago',
    'oppTimeDayAgo':          '{days} days ago',
    'oppEmptyCategory':       'No opportunities in your field right now',
    'oppEmptyAll':            'No open requests right now',
    'oppEmptyCategorySubtitle': 'No new opportunities in your field yet,\nwe\'ll notify you when there are 🔔',
    'oppEmptyAllSubtitle':    'New client requests will appear here in real time\nStay alert!',
    'oppHighDemand':          'High Demand',
    'oppViewersNow':          '{viewers} providers viewing this opportunity now',
    'oppEstimatedEarnings':   'Estimated net earnings',
    'oppAfterFee':            'After AnySkill fee',
    'oppAlreadyInterested':   'Interest expressed ✓',
    'oppRequestClosedBtn':    'Request closed',
    'oppTakeOpportunity':     'Take the opportunity!',
    'oppInterested':          'I\'m interested!',
    'oppQuickBid':            'Quick reply — send auto proposal',
    'oppWalletHint':          'After completing the job — your earnings will be transferred to your AnySkill wallet',

    // ── Search page ───────────────────────────────────────────────────────────
    'helpCenterTooltip':          'Help Center',
    'searchTourSearchTitle':      '🔍 Search Experts',
    'searchTourSearchDesc':       'Type a name, category, or service type — AnySkill will find the right provider for you',
    'searchTourSuggestionsTitle': '⚡ Recommended Categories',
    'searchTourSuggestionsDesc':  'AnySkill suggests services based on the time of day — mornings for repairs, evenings for spa & wellness',
    'searchTourFeedTitle':        '✨ Inspiration Feed',
    'searchTourFeedDesc':         'Real work from the app — tap a card to see the full provider profile',
    'searchNoCategoriesBody':     'No categories found.\nInitialize from the admin panel.',
    'searchNoResultsFor':         'No results found for "{query}"',
    'searchSectionCategories':    'Categories',
    'searchSectionResultsFor':    'Results for "{query}"',
    'searchRecommendedBadge':     '⭐ Recommended',
    'searchPerHour':              ' / hr',
    'searchDatePickerHint':       'When available?',
    'searchChipWeekend':          'Available weekends',
    'searchChipHomeVisit':        'Home visit',
    'searchUrgencyMorning':       '🔴 Only 1 spot left today!',
    'searchUrgencyAfternoon':     '⚡ 2 spots left this week',
    'searchUrgencyEvening':       '⏰ Usually booked 3 days ahead',
    'searchDefaultExpert':        'Expert',
    'searchDefaultCity':          'Your area',
    'searchDefaultTitle':         'Certified Expert',
    'editCategoryTitle':          'Edit Category',
    'editCategoryChangePic':      'Tap to change photo',
    'editCategoryNameLabel':      'Category name',
    'editCategorySaveError':      'Save error: {error}',
    'creditsLabel':               'Credits',
    'creditsDiscountAvailable':   '{discount}% discount available!',
    'creditsToNextDiscount':      '{remaining} more to next discount',
    'inspirationFeedTitle':       'Inspiration — Completed Works',
    'inspirationFeedNewBadge':    'New',
    'inspirationCompletedBadge':  'Done ✓',
    'onlineToggleOn':             'Tap to go online',
    'onlineToggleOff':            'Tap to go offline',

    // ── Shared actions ────────────────────────────────────────────────────────
    'retryButton':                'Try Again',

    // ── Business AI screen ────────────────────────────────────────────────────
    'bizAiLoading':               'Loading business intelligence...',
    'bizAiError':                 'Error: {error}',
    'bizAiTitle':                 'Business Intelligence',
    'bizAiSubtitle':              'Market Trends • AI • Revenue Forecasts',
    'bizAiPending':               '{count} pending',
    'bizAiSectionAiOps':          'AI Center',
    'bizAiActivityToday':         'AI Activity Today',
    'bizAiNewCategories':         'New Categories',
    'bizAiApprovalQueue':         'Approval Queue',
    'bizAiTapToReview':           'Tap to review ›',
    'bizAiModelAccuracy':         'Model Accuracy',
    'bizAiApprovedTotal':         'Approved / Total',
    'bizAiModelAccuracyDetail':   'AI Model Accuracy Breakdown',
    'bizAiApproved':              'Approved',
    'bizAiRejected':              'Rejected',
    'bizAiPendingLabel':          'Pending',
    'bizAiNoData':                'No AI data yet\nAfter providers register, stats will appear here',
    'bizAiSectionMarket':         'Market Demand',
    'bizAiPopularSearches':       '🔥 Popular Searches',
    'bizAiNoSearchData':          'No search data yet — log will appear after users search',
    'bizAiMarketOpportunities':   '🎯 Market Opportunities (Zero Results)',
    'bizAiZeroResultsHint':       'Searches that found no providers — recruit providers for these niches',
    'bizAiNoOpportunities':       'No pending opportunities — all searches find providers 🎉',
    'bizAiSectionFinancial':      'Financial Insights',
    'bizAiWeeklyForecast':        'Weekly Commission Forecast',
    'bizAiSevenDays':             '7 days',
    'bizAiActualToDate':          'Actual to Date',
    'bizAiWeeklyProjection':      'Weekly Projection',
    'bizAiLast7Days':             'Last 7 Days Revenue',
    'bizAiDailyCommission':       'Platform commission day by day',
    'bizAiHighValueCategories':   'High Revenue Categories',
    'bizAiHighValueHint':         'Price/hr × Order count by category',
    'bizAiNoOrderData':           'No order data yet',
    'bizAiProviders':             '{count} providers',
    'bizAiRefreshData':           'Refresh Data',
    'bizAiThresholdUpdated':      'Alert threshold updated to {count} searches',
    'bizAiSectionAlerts':         'Smart Alerts',
    'bizAiSearches':              '{count} searches',
    'bizAiAlertThreshold':        '🔔 Demand Alert Threshold',
    'bizAiAlertThresholdHint':    'Send alert when a missing keyword exceeds X searches in 24 hours',
    'bizAiReset':                 'Reset (5)',
    'bizAiSaveThreshold':         'Save Threshold',
    'bizAiAlertHistory':          '📋 Alert History',
    'bizAiNoAlerts':              'No alerts yet — will appear when keywords exceed the threshold',
    'bizAiAlertCount':            '{count}× alerts',
    'bizAiSearchCount':           '{count} searches',
    'bizAiMinutesAgo':            '{count} min ago',
    'bizAiHoursAgo':              '{count} hr ago',
    'bizAiDaysAgo':               '{count} days ago',
    'bizAiExecSummary':           'Executive Summary',
    'bizAiAccuracy':              'AI Accuracy',
    'bizAiCategoriesApproved':    'Categories Approved',
    'bizAiMarketOppsCard':        'Market Opportunities',
    'bizAiNichesNoProviders':     'Niches Without Providers',
    'bizAiExpectedRevenue':       'Expected Revenue',
    'bizAiForecastBadge':         'Forecast',
    'bizAiNoChartData':           'No commission data for chart yet\nWill appear after the first transaction',
    'bizAiRecruitForQuery':       'Recruit providers for: "{query}"',
    'bizAiRecruitNow':            'Recruit Now',

    // ── Category Results screen ───────────────────────────────────────────────
    'catResultsExpertDefault':    'Expert',
    'catResultsAvailableSlots':   'Upcoming Available Slots',
    'catResultsNoAvailability':   'No availability in the next 14 days',
    'catResultsFullBooking':      'Full Booking',
    'catResultsOrderCount':       '🔥 {count} orders',
    'catResultsResponseTime':     '⚡ Responds within {minutes} min',
    'catResultsTopRated':         '⭐ Top Rated',
    'catResultsAddPhoto':         'Add\nProfile\nPhoto',
    'catResultsPerHour':          ' / hr',
    'catResultsRecommended':      'Recommended',
    'catResultsWhenFree':         'When available?',
    'catResultsPageTitle':        '{category} Experts',
    'catResultsSearchHint':       'Search by name...',
    'catResultsUnder100':         'Under ₪100',
    'catResultsLoadError':        'Error loading experts',
    'catResultsNoResults':        'No results found',
    'catResultsNoExperts':        'No experts in {category} yet',
    'catResultsNoResultsHint':    'Try changing the search or clearing the filter',
    'catResultsBeFirst':          'Be the first to join this category!',
    'catResultsClearFilters':     'Clear Filters',

    // ── Expert Profile Screen ─────────────────────────────────────────────────
    'traitPunctual':             'Always on time',
    'traitProfessional':         'Professional',
    'traitCommunicative':        'Great communication',
    'traitPatient':              'Patient',
    'traitKnowledgeable':        'Knowledgeable',
    'traitFriendly':             'Friendly',
    'traitCreative':             'Creative',
    'traitFlexible':             'Flexible',
    'serviceSingleLesson':       'Single Lesson',
    'serviceSingleSubtitle':     'One personal session',
    'serviceSingle60min':        '60 min',
    'serviceExtendedLesson':     'Extended Lesson',
    'serviceExtendedSubtitle':   'Includes summary & homework',
    'serviceExtended90min':      '90 min',
    'serviceFullSession':        'Full Session',
    'serviceFullSubtitle':       'Deep work + personal plan',
    'serviceFullSession120min':  '120 min',
    'expertInsufficientBalance': 'Insufficient wallet balance to complete booking',
    'expertEscrowSuccess':       'Slot reserved and payment held in escrow!',
    'expertTransactionTitle':    'Secure payment: {name}',
    'expertSystemMessage':       '🔒 New booking for {date} at {time}!\nAmount coming to you: ₪{amount}',
    'expertRecommendedBadge':    'Featured',
    'expertStatRating':          'Rating',
    'expertStatReviews':         'Reviews',
    'expertStatRepeatClients':   'Repeat clients',
    'expertStatResponseTime':    'Response time',
    'expertStatOrders':          'Orders',
    'expertStatXp':              'Points',
    'expertResponseTimeFormat':  '{minutes}m',
    'expertBioPlaceholder':      'Certified expert in the AnySkill community.',
    'expertBioShowLess':         'Show less ▲',
    'expertBioReadMore':         'Read more ▼',
    'expertSelectTime':          'Select a time',
    'expertReviewsCount':        '{count} reviews',
    'expertReviewsHeader':       'Reviews',
    'expertNoReviews':           'No reviews yet',
    'expertDefaultReviewer':     'Customer',
    'expertVerifiedBooking':     'Verified booking',
    'expertProviderResponse':    'Provider reply',
    'expertAddReply':            'Add reply',
    'expertAddReplyTitle':       'Add a reply to this review',
    'expertReplyHint':           'Thank you for your review...',
    'expertReplyError':          'Error saving reply: {error}',
    'expertPublishReply':        'Publish reply',
    'expertBookForTime':         'Book for {time}',
    'expertStartingFrom':        'From ₪{price}',
    'expertSelectDateTime':      'Select date & time',
    'expertBookingSummaryTitle':   'Secure Booking Summary',
    'expertSummaryRowService':     'Service',
    'expertSummaryRowDate':        'Date',
    'expertSummaryRowTime':        'Time',
    'expertSummaryRowPrice':       'Service price',
    'expertSummaryRowProtection':  'AnySkill protection',
    'expertSummaryRowIncluded':    'Included ✓',
    'expertSummaryRowTotal':       'Total to pay',
    'expertCancellationNotice':    'Cancellation policy: {policy} — free cancellation until {deadline}. After that: {penalty}% fee.',
    'expertCancellationNoDeadline':'Cancellation policy: {policy} — {description}.',
    'expertConfirmPaymentButton':  'Confirm payment & reserve slot',
    'expertSectionAbout':         'About the Expert',
    'expertSectionService':       'Choose a service',
    'expertSectionGallery':       'Gallery',
    'expertSectionSchedule':      'Choose a date & time',

    // ── ToS screen ────────────────────────────────────────────────────────
    'tosFullTitle':           'Terms of Service & Privacy',
    'tosLastUpdated':         'Last updated: March 2026  |  Version 2.0',
    'tosBindingNotice':       'This agreement is binding. Please read carefully before accepting.',
    'tosAcceptButton':        'I have read, understood and agree to the Terms',

    // ── Finance screen ────────────────────────────────────────────────────
    'financeTitle':           'My Account',
    'financeTrustBadge':      'AnySkill Trust',
    'financeAvailableBalance': 'Available Balance',
    'financeMinWithdraw':     'Minimum withdrawal: ₪50',
    'financeWithdrawButton':  'Withdraw Funds',
    'financeRecentActivity':  'Recent Activity',
    'financeError':           'Error: {error}',
    'financeNoTransactions':  'No transactions yet',
    'financePaidTo':          'Paid to {name}',
    'financeReceivedFrom':    'Received from {name}',
    'financeProcessing':      'Processing...',

    // ── Withdrawal modal ──────────────────────────────────────────────────
    'withdrawMinBalance':     'Minimum withdrawal balance: ₪{amount}',
    'withdrawAvailableBalance': 'Available balance for withdrawal',
    'withdrawTaxStatusTitle': 'Choose your tax status',
    'withdrawTaxStatusSubtitle': 'Required for payment processing per law',
    'withdrawTaxBusiness':    'Registered Business',
    'withdrawTaxBusinessSub': 'Exempt / Licensed dealer / Company',
    'withdrawTaxIndividual':  'Individual (no business license)',
    'withdrawTaxIndividualSub': 'Employee / freelancer without tax file',
    'withdrawTaxIndividualBadge': 'Easy & fast',
    'withdrawEncryptedNotice': 'Your details are secured and encrypted',
    'withdrawBankEncryptedNotice': 'Your banking details are encrypted and secured',
    'withdrawCertSection':    'Business Certificate',
    'withdrawBankSection':    'Bank Account Details',
    'withdrawBankName':       'Bank Name',
    'withdrawBankBranch':     'Branch Number',
    'withdrawBankAccount':    'Account Number',
    'withdrawBankRequired':   'Bank selection required',
    'withdrawBranchRequired': 'Required',
    'withdrawAccountMinDigits': 'Min 4 digits',
    'withdrawSelectBankError': 'Please select a bank',
    'withdrawNoCertError':    'Please upload a business certificate before continuing',
    'withdrawNoDeclarationError': 'Please confirm the tax declaration before continuing',
    'withdrawUploadError':    'Upload error — please try again',
    'withdrawSubmitError':    'Submission error — please try again',
    'withdrawSubmitButton':   'Submit Withdrawal Request — {amount}',
    'withdrawSuccessTitle':   'Request Received! 🎉',
    'withdrawSuccessSubtitle': 'Withdrawal request of {amount} sent for processing',
    'withdrawSuccessNotice':  'Your balance will update after the team processes your request. Questions: support@anyskill.co.il',
    'withdrawTimeline1Title': 'Request Received',
    'withdrawTimeline1Sub':   'Reference number sent to email',
    'withdrawTimeline2Title': 'Review & Verification',
    'withdrawTimeline2Sub':   'AnySkill team verifies details',
    'withdrawTimeline3Title': 'Money in Account',
    'withdrawTimeline3Sub':   'Within 3–5 business days',
    'withdrawDeclarationText': 'I declare sole responsibility for tax reporting as required by law ',
    'withdrawDeclarationSection': '(Section 6 of the Terms)',
    'withdrawDeclarationSuffix': '. I understand that AnySkill is not my employer and does not withhold taxes.',
    'withdrawExistingCert':   'Existing certificate',
    'withdrawCertUploadBtn':  'Upload business certificate',
    'withdrawCertReplace':    'Tap to replace',
    'withdrawCertHint':       'JPG / PNG — exempt or licensed dealer certificate',
    'withdrawIndividualTitle': 'Payslip Service — Our Partner Service',
    'withdrawIndividualDesc': 'No business? No problem! Via our payslip partner service, we can process your payment legally. A small service fee applies.',
    'withdrawBankTransferPending': 'Bank transfer — pending',
    'withdrawBusinessFormTitle': 'Registered Business',
    'withdrawIndividualFormTitle': 'Individual (no license)',

    // ── Onboarding screen ─────────────────────────────────────────────────
    'onboardingStep':         'Step {step} of {total}',
    'onboardingWelcome':      'Welcome to AnySkill! 👋',
    'onboardingWelcomeSub':   'Tell us who you are so we can personalise your experience',
    'onboardingRoleCustomerTitle': "I'm looking for a service",
    'onboardingRoleCustomerSub': "I want to hire experts for my needs",
    'onboardingRoleProviderTitle': "I'm a service provider",
    'onboardingRoleProviderSub': 'I have skills and want to work through AnySkill',
    'onboardingBothRoles':    'Great! You can both hire and offer services.',
    'onboardingServiceTitle': 'Your Service Details',
    'onboardingServiceSub':   'What is your area of expertise and hourly rate?',
    'onboardingCategory':     'Area of Expertise',
    'onboardingCategoryHint': 'Choose a category...',
    'onboardingPriceLabel':   'Hourly Rate (₪)',
    'onboardingPriceHint':    'e.g. 150',
    'onboardingPriceTip':     'The average price in this category is ₪100–₪200 per hour.',
    'onboardingProfileTitle': 'Your Profile',
    'onboardingProfileSub':   'A photo and short bio help people trust you',
    'onboardingAddPhoto':     'Add profile photo',
    'onboardingBioLabel':     'A few words about you (optional)',
    'onboardingBioHint':      'Tell us a bit about yourself...',
    'onboardingSkipFinish':   'Skip and finish',
    'onboardingNext':         'Continue',
    'onboardingStart':        'Start using AnySkill',
    'onboardingError':        'Error: {error}',
    'onboardingUploadError':  'Upload error: {error}',

    // ── Onboarding — Tax Compliance step ─────────────────────────────────
    'onboardingTaxTitle':         'Tax & Licensing Verification',
    'onboardingTaxSubtitle':      'Required before receiving jobs on the platform',
    'onboardingTaxNotice':        'AnySkill is a professional-only platform. We are required to verify your tax documentation before you can accept bookings — for your protection and that of customers.',
    'onboardingTaxStatusLabel':   'Tax Status',
    'onboardingTaxStatusRequired':'Please select a tax status before continuing',
    'onboardingDocRequired':      'Please upload a document before continuing',
    'onboardingTaxBusiness':      'Registered Business (VAT Exempt / Authorized)',
    'onboardingTaxBusinessSub':   'Business registered with VAT authorities',
    'onboardingTaxIndividual':    'Invoice via 3rd Party',
    'onboardingTaxIndividualSub': 'Employee — we issue an invoice on your behalf',
    'onboardingDocLabelBusiness': 'Business License / Tax Certificate',
    'onboardingDocLabelIndividual':'ID Card Photo',
    'onboardingDocHintBusiness':  'Photo of your VAT registration certificate (JPG / PNG)',
    'onboardingDocHintIndividual':'Photo of both sides of your ID card (JPG / PNG)',
    'onboardingDocUploadPrompt':  'Tap to select a file from your gallery',
    'onboardingDocUploadSub':     'JPG · PNG · PDF · Max 10MB',
    'onboardingUploading':        'Uploading...',
    'onboardingDocUploaded':      'Uploaded successfully ✓',
    'onboardingDocReplace':       'Replace',

    // ── Opportunities lock screen ─────────────────────────────────────────
    'oppUnderReviewTitle':    'Account Under Review',
    'oppUnderReviewSubtitle': 'We are verifying your tax documents',
    'oppUnderReviewBody':     'AnySkill is a professional-only platform. Our team is reviewing the documents you submitted and will approve your account within 24–48 hours.\n\nYou will receive a notification as soon as your account is approved and you can start accepting bookings.',
    'oppUnderReviewStep1':    'Documents Received',
    'oppUnderReviewStep2':    'Admin Review',
    'oppUnderReviewStep3':    'Account Active',
    'oppUnderReviewContact':  'Questions? support@anyskill.co.il',

    // ── Admin — Compliance verification ───────────────────────────────────
    'adminVerifyProvider':    'Verify Provider',
    'adminUnverifyProvider':  'Revoke Provider Verification',
    'adminVerifiedSuccess':   '{name} verified — access to jobs enabled ✓',
    'adminUnverifiedSuccess': '{name} verification revoked',
    'adminViewDoc':           'View Document',
    'adminComplianceSection': 'Compliance & Tax',
    'adminComplianceTaxStatus': 'Tax Status',
    'adminCompliancePending': 'Pending Verification',
    'adminComplianceApproved':'Approved',

    // ── Help Center screen ────────────────────────────────────────────────
    'helpCenterProviderSupport': 'Provider Support',
    'helpCenterCustomerSupport': 'Customer Support',
    'helpCenterProviderWelcome': 'Hello! I am AnySkill\'s expert assistant 👋\nHere you\'ll find tips for managing your profile, getting bookings, and more.\n\nHow can I help you today?',
    'helpCenterCustomerWelcome': 'Hello! I am AnySkill\'s customer assistant 👋\nI have answers for every question — choose from the list or type freely.\n\nHow can I help?',
    'helpCenterProviderFaq':  'FAQs for Providers',
    'helpCenterCustomerFaq':  'FAQs for Customers',
    'helpCenterInputHint':    'Type a free question...',
    'helpCenterTitle':        'Help Center',

    // ── Dispute Resolution ────────────────────────────────────────────────────
    'disputeOpenDisputes':    'Open Disputes',
    'disputeLockedEscrow':    'Locked in Escrow',
    'disputeTapForDetails':   'Tap for details and actions',
    'disputePartyCustomer':   'Customer',
    'disputePartyProvider':   'Provider',
    'disputeArbitrationCenter': 'Arbitration Center',
    'disputeIdPrefix':        'ID:',
    'disputeLockedSuffix':    'locked',
    'disputePartiesSection':  'Parties',
    'disputeReasonSection':   'Dispute Reason',
    'disputeNoReason':        'No reason provided.',
    'disputeChatHistory':     'Chat History (last 10 messages)',
    'disputeAdminNote':       'Admin Note (optional)',
    'disputeAdminNoteHint':   'Add a note to be saved with the decision...',
    'disputeExistingNote':    'Existing note: {note}',
    'disputeActionsSection':  'Arbitration Actions',
    'disputeResolving':       'Processing...',
    'disputeRefundLabel':     'Refund to Customer',
    'disputeRefundSublabel':  'Full refund ₪{amount}',
    'disputeReleaseLabel':    'Release to Expert',
    'disputeReleaseSublabel': 'After fee (≈₪{amount})',
    'disputeSplitLabel':      '50/50 Split',
    'disputeSplitSublabel':   '₪{amount} each side',
    'disputeConfirmRefund':   'Full Refund to Customer',
    'disputeConfirmRelease':  'Release to Expert',
    'disputeConfirmSplit':    '50/50 Split',
    'disputeRefundBody':      '₪{amount} will be refunded to {name}.\nThe expert will not receive payment.',
    'disputeReleaseBody':     '₪{amount} will be transferred to {name}\n(after {fee}% fee).',
    'disputeSplitBody':       '₪{half} → Customer\n₪{halfNet} → Expert (after fee)\n₪{platform} → Platform',
    'disputeIrreversible':    'This action is irreversible. The decision will be saved and FCM notifications sent to both parties.',
    'disputeResolvedRefund':  '✅ Amount refunded to customer. Notification sent to both parties.',
    'disputeResolvedRelease': '✅ Amount released to expert. Notification sent to both parties.',
    'disputeResolvedSplit':   '⚖️ Settlement executed. Notification sent to both parties.',
    'disputeErrorPrefix':     'Error: {error}',
    'disputeNoChatId':        'No chat ID found.',
    'disputeNoMessages':      'No messages in this chat.',
    'disputeSystemSender':    'System',
    'disputeTypeImage':       '📷 Image',
    'disputeTypeLocation':    '📍 Location',
    'disputeTypeAudio':       '🎤 Recording',
    'disputeOpenedAt':        'Opened at {date}',
    'disputeEmptyTitle':      'No open disputes',
    'disputeEmptySubtitle':   'All operations are in order 🎉',
    // ── My Calendar ───────────────────────────────────────────────────────────
    'calendarTitle':          'My Calendar',
    'calendarRefresh':        'Refresh',
    'calendarNoEvents':       'No bookings on this day',
    'calendarStatusPending':  'Pending Execution',
    'calendarStatusWaiting':  'Awaiting Approval',
    'calendarStatusCompleted': 'Completed',
    // ── My Requests ───────────────────────────────────────────────────────────
    'requestsTitle':          'My Requests',
    'requestsEmpty':          'No active requests',
    'requestsEmptySubtitle':  'Broadcast a quick request and within seconds\nprofessional providers will contact you!',
    'requestsInterested':     '{count} interested',
    'requestsWaiting':        'Waiting for interested...',
    'requestsWaitingProviders': 'Waiting for interested providers...',
    'requestsClosed':         'Request closed',
    'requestsViewInterested': 'View {count} interested',
    'requestsInterestedTitle': 'Interested in your request',
    'requestsNoInterested':   'No interested providers yet',
    'requestsJustNow':        'Just now',
    'requestsMinutesAgo':     '{minutes} min ago',
    'requestsHoursAgo':       '{hours} hrs ago',
    'requestsDaysAgo':        '{days} days ago',
    'requestsDefaultExpert':  'Expert',
    'requestsHiredAgo':       'Hired {ago}',
    'requestsOrderCount':     '🔥 {count} jobs',
    'requestsTopMatch':       'Best Match',
    'requestsMatchLabel':     'Match',
    'requestsChatNow':        'Chat Now',
    'requestsConfirmPay':     'Confirm & Pay',
    'requestsMoneyProtected': 'Money protected until job is done',
    'requestsEscrowTooltip':  'Funds are held in escrow by AnySkill and transferred to the expert only after your approval upon job completion.',
    'requestsVerifiedBadge':  'AnySkill Verified — Secure escrow payment',
    'requestsPricePerHour':   '₪{price} / hr',
    'requestsBestValue':      'Best Value',
    'requestsFastResponse':   'Fast Response',
    // ── XP Manager ────────────────────────────────────────────────────────────
    'xpManagerTitle':         'XP & Levels System',
    'xpManagerSubtitle':      'Configure events, points and level thresholds',
    'xpEventsSection':        'XP Events',
    'xpEventsCount':          '{count} events',
    'xpEventsEmpty':          'No events yet.\nClick "Add Event" to get started.',
    'xpAddEventButton':       'Add Event',
    'xpEditEventTitle':       'Edit XP Event',
    'xpAddEventTitle':        'Add New XP Event',
    'xpFieldId':              'Event ID (English, no spaces)',
    'xpFieldIdHint':          'e.g. late_delivery',
    'xpFieldName':            'Event Name',
    'xpFieldPoints':          'XP Points (negative = penalty)',
    'xpFieldDesc':            'Short description',
    'xpEventUpdated':         'Event updated ✓',
    'xpEventAdded':           'Event added ✓',
    'xpEventDeleted':         'Event deleted',
    'xpDeleteEventTitle':     'Delete Event',
    'xpDeleteEventConfirm':   'Delete event "{name}"?\nThis action is irreversible.',
    'xpReservedId':           'The ID "app_levels" is reserved by the system',
    'xpTooltipEdit':          'Edit',
    'xpTooltipDelete':        'Delete',
    'xpLevelsTitle':          'Level Threshold',
    'xpLevelsSubtitle':       'Set the minimum XP required for each level.',
    'xpSaveLevels':           'Save Level Thresholds',
    'xpLevelsSaved':          'Level thresholds updated ✓',
    'xpLevelsError':          'Silver must be > 0 and Gold must be > Silver',
    'xpLevelBronze':          'Bronze',
    'xpLevelSilver':          'Silver',
    'xpLevelGold':            'Gold',
    'xpSaveAction':           'Save',
    'xpAddAction':            'Add',
    'xpErrorPrefix':          'Error: {error}',
    // ── System Wallet ─────────────────────────────────────────────────────────
    'systemWalletTitle':      'System Finance Management',
    'systemWalletBalance':    'Liquid Balance in System Wallet',
    'systemWalletPendingFees': 'Pending Fees',
    'systemWalletActiveJobs': '{count} active transactions (escrow / awaiting approval)',
    'systemWalletFeePanel':   'Set Global Fee Percentage',
    'systemWalletUpdateFee':  'Update',
    'systemWalletFeeUpdated': 'Fee updated to {value}%!',
    'systemWalletEnterNumber': 'Please enter a number',
    'systemWalletInvalidNumber': 'Please enter a valid number',
    'systemWalletEarningsTitle': 'Commission Revenue Breakdown (real-time)',
    'systemWalletExportCsv':  'Export CSV',
    'systemWalletExported':   'Exported {count} records to CSV',
    'systemWalletExportError': 'Export error: {error}',
    'systemWalletNoEarnings': 'No commissions recorded in system',
    'systemWalletTxStatus':   'Status: Received successfully',
    // ── Pending Categories ────────────────────────────────────────────────────
    'pendingCatsTitle':       'Categories Pending Approval',
    'pendingCatsSectionPending': 'Pending Approval',
    'pendingCatsSectionReviewed': 'Reviewed',
    'pendingCatsApproved':    '✅ Category approved and published!',
    'pendingCatsRejected':    '🗑 Category rejected',
    'pendingCatsErrorPrefix': 'Error: {error}',
    'pendingCatsSubCategory': 'Sub-category: {name}',
    'pendingCatsProviderDesc': 'Provider Description',
    'pendingCatsAiReason':    'AI Reasoning',
    'pendingCatsImagePrompt': 'Image Prompt (Midjourney/DALL-E)',
    'pendingCatsReject':      'Reject',
    'pendingCatsApprove':     'Approve & Publish',
    'pendingCatsStatusApproved': 'Approved',
    'pendingCatsStatusRejected': 'Rejected',
    'pendingCatsEmptyTitle':  'No pending categories',
    'pendingCatsEmptySubtitle': 'All categories have been reviewed or none created yet',
    'pendingCatsOpenedAt':    'Opened at {date}',
  },

  // ───────────────────────────────────────────────── SPANISH ────────────────
  'es': {
    // App
    'appName':                'AnySkill',
    'appSlogan':              'AnySkill — Tu Habilidad, Su Servicio',

    // Navigation
    'tabHome':                'Inicio',
    'tabBookings':            'Reservas',
    'tabChat':                'Chat',
    'tabWallet':              'Cartera',
    'tabProfile':             'Perfil',

    // Common
    'cancel':                 'Cancelar',
    'confirm':                'Confirmar',
    'submit':                 'Enviar',
    'save':                   'Guardar',
    'close':                  'Cerrar',
    'delete':                 'Eliminar',
    'open':                   'Abrir',
    'back':                   'Volver',

    'errorGeneric':           'Ocurrió un error. Inténtalo de nuevo',
    'currencySymbol':         '₪',

    // App-level
    'updateBannerText':       '¡Hemos actualizado AnySkill para ti!\nNueva versión disponible con mejoras de rendimiento 🚀',
    'updateNowButton':        'Actualizar',
    'notifOpen':              'Abrir',

    // Auth
    'loginTitle':             'Bienvenido a AnySkill',
    'loginAccountTitle':      'Iniciar Sesión',
    'loginWelcomeBack':       '¡Bienvenido de nuevo! Tus expertos te esperan',
    'loginEmail':             'Correo Electrónico',
    'loginPassword':          'Contraseña',
    'loginButton':            'Iniciar Sesión →',
    'loginRememberMe':        'Recordarme',
    'loginForgotPassword':    'Olvidé mi contraseña',
    'loginNoAccount':         '¿No tienes cuenta? ',
    'loginSignUpFree':        'Regístrate gratis',
    'loginOrWith':            'O inicia sesión con',
    'loginAppleComingSoon':   'Inicio con Apple disponible pronto',
    'loginStats10k':          'Profesionales',
    'loginStats50':           'Categorías',
    'loginStats49':           'Calificación',

    // Auth errors
    'errorUserNotFound':      'No se encontró una cuenta con este correo',
    'errorWrongPassword':     'Contraseña incorrecta — inténtalo de nuevo',
    'errorInvalidCredential': 'Correo o contraseña inválidos',
    'errorInvalidEmail':      'Dirección de correo inválida',
    'errorUserDisabled':      'Esta cuenta ha sido desactivada',
    'errorTooManyRequests':   'Demasiados intentos — inténtalo en unos minutos',
    'errorNetworkFailed':     'Error de red — verifica tu conexión',
    'errorGenericLogin':      'Error al iniciar sesión, inténtalo de nuevo',
    'errorEmptyFields':       'Por favor ingresa tu correo y contraseña',
    'errorGoogleLogin':       'Error al iniciar sesión con Google',

    // Forgot password
    'forgotPasswordTitle':    'Restablecer Contraseña',
    'forgotPasswordSubtitle': 'Ingresa tu correo y te enviaremos un enlace',
    'forgotPasswordEmail':    'Correo Electrónico',
    'forgotPasswordSubmit':   'Enviar Enlace',
    'forgotPasswordSuccess':  'Enlace de restablecimiento enviado ✉️',
    'forgotPasswordError':    'Error — verifica que el correo esté registrado',

    // Sign-up
    'signupButton':           'Registrarse',
    'signupTitle':            'Únete a AnySkill',
    'googleNewUserBio':       'Nuevo cliente de AnySkill',

    // Validation
    'validationNameRequired': 'Por favor ingresa tu nombre',
    'validationNameLength':   'El nombre debe tener al menos 2 caracteres',
    'validationRoleRequired': 'Selecciona al menos un rol',
    'validationCategoryRequired': 'Por favor selecciona una categoría',
    'validationPriceInvalid': 'El precio debe ser un número válido',
    'validationPricePositive':'El precio debe ser mayor que 0',

    // Profile
    'profileTitle':           'Mi Perfil',
    'shareProfileTitle':      'Compartir Perfil para Aumentar Ventas',
    'shareProfileWhatsapp':   'Enviar por WhatsApp',
    'shareProfileCopyLink':   'Copiar Enlace del Perfil',
    'shareProfileTooltip':    'Compartir Perfil',
    'linkCopied':             '¡Enlace copiado! Pégalo donde quieras.',
    'whatsappError':          'No se puede abrir WhatsApp en este navegador',
    'defaultUserName':        'Usuario Anónimo',
    'logoutTooltip':          'Cerrar Sesión',
    'logoutTitle':            'Cerrar Sesión',
    'logoutContent':          '¿Estás seguro de que quieres cerrar sesión?',
    'logoutConfirm':          'Cerrar Sesión',
    'logoutButton':           'Cerrar Sesión',
    'aboutMeTitle':           'Sobre Mí',
    'aboutMePlaceholder':     'Sin descripción aún.',
    'galleryTitle':           'Galería de Trabajos',
    'galleryEmpty':           'No hay fotos en la galería',
    'statRating':             'Calificación',
    'statBalance':            'Saldo',
    'statWorks':              'Trabajos',
    'bookingsTrackerButton':  'Ver Mis Reservas',
    'bookingsTrackerSnackbar':'Ir a chats para seguir transacciones...',

    // VIP
    'vipActiveLabel':         'VIP Activo',
    'vipExpiredLabel':        'Expirado',
    'vipHighlight':           'Tu perfil aparece primero en las búsquedas con brillo dorado ✨',
    'vipUpsellTitle':         'Visibilidad VIP Aumentada',
    'vipBenefit1':            'Listado primero en todos los resultados',
    'vipBenefit2':            "Brillo dorado + insignia 'Recomendado'",
    'vipBenefit3':            'Hasta 5× más visitas al perfil',
    'vipBenefit4':            'Prioridad en solicitudes urgentes',
    'vipCtaButton':           'Unirse al VIP — ₪99/mes',
    'vipSheetHeader':         'Unirse al VIP',
    'vipPriceMonthly':        '/mes',
    'vipActivateButton':      '⭐ Activar VIP — ₪99 del saldo',
    'vipInsufficientBalance': 'Saldo insuficiente (se requieren ₪99)',
    'vipInsufficientTooltip': 'Recarga tu cartera para activar VIP',
    'vipActivationSuccess':   '🎉 ¡Bienvenido al VIP! Tu perfil aparece primero',

    // Language
    'languageTitle':          'Idioma',
    'languageHe':             'Hebreo',
    'languageEn':             'Inglés',
    'languageEs':             'Español',
    'languageSectionLabel':   'Idioma de la Interfaz',

    // Chat list
    'chatListTitle':          'Mensajes',
    'chatSearchHint':         'Buscar conversaciones...',
    'chatEmptyState':         'Sin conversaciones aún',
    'chatUserDefault':        'Usuario',
    'chatLastMessageDefault': 'Nuevo mensaje',
    'markAllReadTooltip':     'Marcar todo como leído',
    'markAllReadSuccess':     'Todos los mensajes marcados como leídos',
    'deleteChatTitle':        'Eliminar Conversación',
    'deleteChatContent':      '¿Estás seguro de que quieres eliminar todo el historial?',
    'deleteChatConfirm':      'Eliminar',
    'deleteChatSuccess':      'Conversación eliminada',
    'notLoggedIn':            'Por favor inicia sesión de nuevo',

    // Search
    'searchPlaceholder':      'Busca un profesional, servicio...',
    'searchTitle':            'Buscar',
    'discoverCategories':     'Descubrir Categorías',
    'searchHintExperts':      '¿Qué necesitas hoy?',
    'greetingMorning':        'Buenos Días',
    'greetingAfternoon':      'Buenas Tardes',
    'greetingEvening':        'Buenas Noches',
    'greetingNight':          'Buenas Noches',
    'greetingSubMorning':     '¿Qué necesitas arreglar esta mañana?',
    'greetingSubAfternoon':   '¿Buscas un profesional? Es el momento',
    'greetingSubEvening':     '¡Date un gusto esta noche!',
    'greetingSubNight':       'Descubre los mejores expertos',

    // Home
    'onlineStatus':           'Disponible',
    'offlineStatus':          'No Disponible',
    'quickRequest':           'Solicitud Rápida',
    'urgentJobBanner':        '¡Nuevo trabajo disponible!',

    // Bookings
    'bookNow':                'Reservar Ahora',

    // Wallet
    'walletBalance':          'Saldo Disponible',
    'walletMinWithdraw':      'Retiro mínimo: ₪50',
    'withdrawFunds':          'Retirar Fondos',

    // ToS
    'tosTitle':               'Términos de Servicio',
    'tosAgree':               'He leído y acepto los Términos',

    // Misc
    'trendingBadge':          'Tendencia',
    'subCategoryPrompt':      'Elegir Especialidad',
    'reviewSubmit':           'Enviar Reseña',
    'urgentOpenButton':       'Abrir',

    // Edit profile
    'editProfileTitle':       'Editar Perfil',
    'saveSuccess':            '¡Perfil actualizado correctamente!',
    'profileFieldName':       'Nombre Completo',
    'profileFieldNameHint':   '¿Cómo quieres que te conozcan?',
    'profileFieldRole':       'Configuración de Rol',
    'roleProvider':           'Proveedor de Servicios',
    'roleCustomer':           'Cliente',
    'profileFieldCategoryMain':     'Área de Servicio Principal',
    'profileFieldCategoryMainHint': 'Elegir categoría',
    'profileFieldCategorySub':      'Especialidad Específica',
    'profileFieldCategorySubHint':  'Elegir especialidad',
    'profileFieldPrice':      'Tarifa por Hora (₪)',
    'profileFieldPriceHint':  '¿Cuánto quieres ganar?',
    'profileFieldResponseTime':     'Tiempo de Respuesta Promedio',
    'profileFieldTaxId':      'ID / Número de Empresa',
    'profileFieldTaxIdHint':  'ej. 123456789',
    'profileFieldTaxIdHelp':  'Aparece en los recibos digitales enviados a clientes',
    'saveChanges':            'Guardar Cambios',
    'saveError':              'Error al guardar: {error}',
    'profileFieldResponseTimeHint': '¿Qué tan rápido respondes normalmente a los mensajes?',
    'editProfileQuickTags':   'Etiquetas Rápidas',
    'editProfileTagsSelected':'{count}/3 seleccionadas',
    'editProfileTagsHint':    'Elige hasta 3 etiquetas para mostrar en tu tarjeta',
    'editProfileCancellationPolicy': 'Política de Cancelación',
    'editProfileCancellationHint':   'Los clientes verán esta política antes de reservar',
    'editProfileAbout':       'Descripción Personal',
    'editProfileAboutHint':   'Cuéntanos sobre tu experiencia...',
    'editProfileGallery':     'Galería de Trabajos',

    // ── Home tab ─────────────────────────────────────────────────────────────
    'homeProviderGreetingSub': '¿Qué tienes en marcha hoy?',
    'homeCustomerGreetingSub': '¿Qué necesitas?',
    'noCategoriesYet':        'Sin categorías aún',
    'urgentBannerRequests':   'solicitudes',
    'urgentBannerPending':    'pendientes',
    'urgentBannerCustomerWaiting': 'El cliente espera tu aprobación',
    'urgentBannerServiceNeeded':   'Servicio requerido',
    'timeOneHour':            '1 hora',

    // ── Notifications ─────────────────────────────────────────────────────────
    'notificationsTitle':     'Notificaciones',
    'notifClearAll':          'Limpiar Todo',
    'notifEmptyTitle':        'Sin notificaciones aún',
    'notifEmptySubtitle':     'La actividad de tu cuenta aparecerá aquí',
    'timeNow':                'Ahora',
    'timeMinutesAgo':         'hace {minutes} min',
    'timeHoursAgo':           'hace {hours} horas',

    // ── Sign Up ───────────────────────────────────────────────────────────────
    'signupTosMustAgree':     'Por favor acepta los Términos de Servicio para continuar',
    'signupAccountCreated':   '¡Cuenta creada! Bienvenido a AnySkill 🎉',
    'signupEmailInUse':       'Esta dirección de correo ya está registrada',
    'signupWeakPassword':     'Contraseña demasiado débil — intenta una más fuerte',
    'signupNetworkError':     'Error de red — verifica tu conexión a internet',
    'signupGenericError':     'Error de registro',
    'signupNewProviderBio':   'Nuevo experto en la comunidad AnySkill 🚀',
    'signupNewCustomerBio':   'Nuevo cliente de AnySkill',
    'signupIAmCustomer':      'Soy Cliente',
    'signupIAmProvider':      'Soy Proveedor',
    'signupCustomerDesc':     'Busco profesionales para ayudarme',
    'signupProviderDesc':     'Ofrezco servicios y gano dinero',
    'signupName':             'Nombre Completo',
    'signupNameHint':         'Nombre que se mostrará en tu perfil',
    'signupEmail':            'Correo Electrónico',
    'signupEmailHint':        'ejemplo@correo.com',
    'signupPassword':         'Contraseña',
    'signupPasswordHint':     'Al menos 8 caracteres',
    'signupPhone':            'Teléfono (opcional)',
    'signupPhoneHint':        '050-1234567',
    'signupCategory':         'Área de Servicio',
    'signupTosPrefix':        'He leído y acepto los ',
    'signupTosLink':          'Términos de Servicio',
    'signupHaveAccount':      '¿Ya tienes cuenta? ',
    'signupLogin':            'Iniciar Sesión',
    'signupOrWith':           'O regístrate con',
    'signupGoogleError':      'Error al registrarse con Google',
    'signupPasswordStrength0':'Muy Débil',
    'signupPasswordStrength1':'Débil',
    'signupPasswordStrength2':'Regular',
    'signupPasswordStrength3':'Fuerte',
    'signupPasswordStrength4':'Muy Fuerte',
    'signupNameValidation':   'Nombre requerido (al menos 2 caracteres)',
    'signupEmailValidation':  'Dirección de correo inválida',
    'signupPasswordValidation':'Al menos 6 caracteres',
    'signupCategoryRequired': 'Elige una categoría',

    // ── Bookings ──────────────────────────────────────────────────────────────
    'availabilityUpdated':    'Disponibilidad actualizada correctamente',
    'bookingCompleted':       '¡Trabajo completado y pago liberado!',
    'releasePaymentError':    'Error al liberar el pago',
    'markedDoneSuccess':      '¡Marcado como completado! El cliente confirmará la liberación del pago.',
    'cancelBookingTitle':     'Cancelar Reserva',
    'cancelPenaltyWarning':   'Advertencia: La ventana de cancelación gratuita ha expirado.\nSegún la política {policy}, cancelar ahora generará una penalización de ₪{penalty}.',
    'cancelRefundBreakdown':  'Recibirás: ₪{refund}\nEl experto recibirá: ₪{penalty} (menos comisión)',
    'cancelSimpleConfirm':    '¿Cancelar esta reserva?\n₪{amount} serán devueltos a tu cartera.',
    'noGoBack':               'No, Volver',
    'yesCancelWithPenalty':   'Sí, Cancelar (₪{penalty} de penalización)',
    'yesCancel':              'Sí, Cancelar',
    'bookingCancelledRefund': 'Reserva cancelada — ₪{amount} devueltos a la cartera',
    'cancelError':            'Error al cancelar: {error}',
    'providerCancelTitle':    'Cancelación del Proveedor',
    'providerCancelContent':  'La cancelación del proveedor da al cliente un reembolso del 100%\ny reduce XP de tu perfil.\n\n¿Continuar?',
    'providerCancelledSuccess':'Reserva cancelada — el cliente recibirá el reembolso completo',
    'disputeTitle':           'Abrir Disputa',
    'disputeDescription':     'Describe el problema con el servicio. Nuestro equipo revisará y decidirá en 48 horas.',
    'disputeHint':            'Describe el problema...',
    'submitDispute':          'Enviar Disputa',
    'jobTabActive':           'Activas',
    'jobTabHistory':          'Historial',
    'jobTabCalendar':         'Disponibilidad',
    'bookingsTitle':          'Mis Reservas',
    'bookingsEmptyActive':    'Sin reservas activas por ahora',
    'bookingsEmptyHistory':   'Sin historial de reservas',
    'jobStatusPaidEscrow':    'En Progreso',
    'jobStatusExpertCompleted':'Esperando tu Aprobación',
    'jobStatusCompleted':     'Completado',
    'jobStatusCancelled':     'Cancelado',
    'jobStatusDisputed':      'En Disputa',
    'saveAvailability':       'Guardar Disponibilidad',
    'releasePayment':         'Confirmar y Liberar Pago',
    'markDone':               'Marcar como Completado',
    'openChat':               'Abrir Chat',
    'openDispute':            'Abrir Disputa',
    'cancelBooking':          'Cancelar Reserva',
    'ratingTitle':            'Calificar el Servicio',
    'ratingSubmit':           'Enviar Calificación',

    // ── Opportunities screen ───────────────────────────────────────────────────
    'oppTitle':               'Tablero de Oportunidades',
    'oppAllCategories':       'Todas las Categorías',
    'oppError':               'Error: {error}',
    'oppDefaultClient':       'Cliente',
    'oppRequestUnavailable':  'Esta solicitud ya no está disponible',
    'oppRequestClosed3':      'Solicitud cerrada — ya se encontraron 3 proveedores interesados',
    'oppAlreadyExpressed':    'Ya expresaste interés en esta solicitud',
    'oppAlready3Interested':  'Esta solicitud ya tiene 3 proveedores interesados',
    'oppInterestChatMessage': '💡 {providerName} expresó interés en tu solicitud de servicio:\n"{description}"',
    'oppNotifTitle':          '¡Nuevo interesado en tu solicitud!',
    'oppNotifBody':           '{providerName} quiere realizar el servicio que solicitaste',
    'oppBoostEarned':         '🚀 ¡Tu perfil subió al tope de los resultados de búsqueda por 24 horas!',
    'oppInterestSuccess':     '¡Interés expresado! El chat con el cliente está abierto',
    'oppQuickBidMessage':     '¡Hola {clientName}! 👋\nSoy {providerName} y estoy disponible para realizar tu solicitud lo antes posible.\n¿Cuál es tu disponibilidad?',
    'oppXpToNextLevel':       '{xp} XP más para alcanzar el nivel {name}',
    'oppMaxLevel':            '¡Alcanzaste el nivel más alto! 🏆',
    'oppProfileBoosted':      '🚀 ¡Perfil potenciado! Hasta {time}',
    'oppBoostProgress':       'AnySkill Boost: {count}/3 — Completa 3 tareas urgentes',
    'oppTimeHours':           '{hours}h',
    'oppTimeMinutes':         '{minutes}m',
    'oppTimeJustNow':         'Ahora mismo',
    'oppTimeMinAgo':          'hace {minutes} min',
    'oppTimeHourAgo':         'hace {hours}h',
    'oppTimeDayAgo':          'hace {days} días',
    'oppEmptyCategory':       'No hay oportunidades en tu área ahora mismo',
    'oppEmptyAll':            'No hay solicitudes abiertas ahora mismo',
    'oppEmptyCategorySubtitle': 'Aún no hay nuevas oportunidades en tu área,\nte notificaremos cuando haya 🔔',
    'oppEmptyAllSubtitle':    'Las nuevas solicitudes de clientes aparecerán aquí en tiempo real\n¡Mantente alerta!',
    'oppHighDemand':          'Alta Demanda',
    'oppViewersNow':          '{viewers} proveedores ven esta oportunidad ahora',
    'oppEstimatedEarnings':   'Ganancias netas estimadas',
    'oppAfterFee':            'Después de la comisión AnySkill',
    'oppAlreadyInterested':   'Interés expresado ✓',
    'oppRequestClosedBtn':    'Solicitud cerrada',
    'oppTakeOpportunity':     '¡Toma la oportunidad!',
    'oppInterested':          '¡Me interesa!',
    'oppQuickBid':            'Respuesta rápida — enviar propuesta automática',
    'oppWalletHint':          'Al finalizar el trabajo — tus ganancias serán transferidas a tu cartera AnySkill',

    // ── Search page ───────────────────────────────────────────────────────────
    'helpCenterTooltip':          'Centro de Ayuda',
    'searchTourSearchTitle':      '🔍 Buscar Expertos',
    'searchTourSearchDesc':       'Escribe un nombre, categoría o tipo de servicio — AnySkill encontrará al proveedor adecuado',
    'searchTourSuggestionsTitle': '⚡ Categorías Recomendadas',
    'searchTourSuggestionsDesc':  'AnySkill sugiere servicios según la hora del día — mañanas para reparaciones, noches para spa y bienestar',
    'searchTourFeedTitle':        '✨ Feed de Inspiración',
    'searchTourFeedDesc':         'Trabajos reales de la app — toca una tarjeta para ver el perfil completo del proveedor',
    'searchNoCategoriesBody':     'No se encontraron categorías.\nInicializa desde el panel de administración.',
    'searchNoResultsFor':         'No se encontraron resultados para "{query}"',
    'searchSectionCategories':    'Categorías',
    'searchSectionResultsFor':    'Resultados para "{query}"',
    'searchRecommendedBadge':     '⭐ Recomendado',
    'searchPerHour':              ' / hora',
    'searchDatePickerHint':       '¿Cuándo disponible?',
    'searchChipWeekend':          'Disponible fines de semana',
    'searchChipHomeVisit':        'Visita a domicilio',
    'searchUrgencyMorning':       '🔴 ¡Solo 1 lugar disponible hoy!',
    'searchUrgencyAfternoon':     '⚡ 2 lugares disponibles esta semana',
    'searchUrgencyEvening':       '⏰ Normalmente se reserva con 3 días de antelación',
    'searchDefaultExpert':        'Experto',
    'searchDefaultCity':          'Tu área',
    'searchDefaultTitle':         'Experto Certificado',
    'editCategoryTitle':          'Editar Categoría',
    'editCategoryChangePic':      'Toca para cambiar la foto',
    'editCategoryNameLabel':      'Nombre de categoría',
    'editCategorySaveError':      'Error al guardar: {error}',
    'creditsLabel':               'Créditos',
    'creditsDiscountAvailable':   '¡{discount}% de descuento disponible!',
    'creditsToNextDiscount':      '{remaining} más para el próximo descuento',
    'inspirationFeedTitle':       'Inspiración — Trabajos Completados',
    'inspirationFeedNewBadge':    'Nuevo',
    'inspirationCompletedBadge':  'Hecho ✓',
    'onlineToggleOn':             'Toca para estar disponible',
    'onlineToggleOff':            'Toca para estar no disponible',

    // ── Shared actions ────────────────────────────────────────────────────────
    'retryButton':                'Reintentar',

    // ── Business AI screen ────────────────────────────────────────────────────
    'bizAiLoading':               'Cargando inteligencia empresarial...',
    'bizAiError':                 'Error: {error}',
    'bizAiTitle':                 'Inteligencia Empresarial',
    'bizAiSubtitle':              'Tendencias de Mercado • AI • Proyecciones de Ingresos',
    'bizAiPending':               '{count} pendiente',
    'bizAiSectionAiOps':          'Centro AI',
    'bizAiActivityToday':         'Actividad AI Hoy',
    'bizAiNewCategories':         'Nuevas Categorías',
    'bizAiApprovalQueue':         'Cola de Aprobaciones',
    'bizAiTapToReview':           'Toca para revisar ›',
    'bizAiModelAccuracy':         'Precisión del Modelo',
    'bizAiApprovedTotal':         'Aprobados / Total',
    'bizAiModelAccuracyDetail':   'Desglose de Precisión del Modelo AI',
    'bizAiApproved':              'Aprobados',
    'bizAiRejected':              'Rechazados',
    'bizAiPendingLabel':          'Pendiente',
    'bizAiNoData':                'Sin datos de AI aún\nDespués de que los proveedores se registren, aparecerán las estadísticas',
    'bizAiSectionMarket':         'Demanda del Mercado',
    'bizAiPopularSearches':       '🔥 Búsquedas Populares',
    'bizAiNoSearchData':          'Sin datos de búsqueda aún — el registro aparecerá después de que los usuarios busquen',
    'bizAiMarketOpportunities':   '🎯 Oportunidades de Mercado (Sin Resultados)',
    'bizAiZeroResultsHint':       'Búsquedas que no encontraron proveedores — recluta proveedores para estos nichos',
    'bizAiNoOpportunities':       'Sin oportunidades pendientes — todas las búsquedas encuentran proveedores 🎉',
    'bizAiSectionFinancial':      'Perspectivas Financieras',
    'bizAiWeeklyForecast':        'Previsión de Comisiones Semanales',
    'bizAiSevenDays':             '7 días',
    'bizAiActualToDate':          'Real hasta Hoy',
    'bizAiWeeklyProjection':      'Proyección Semanal',
    'bizAiLast7Days':             'Ingresos de los últimos 7 días',
    'bizAiDailyCommission':       'Comisión de la plataforma día a día',
    'bizAiHighValueCategories':   'Categorías de Alto Ingreso',
    'bizAiHighValueHint':         'Precio/hr × Número de pedidos por categoría',
    'bizAiNoOrderData':           'Sin datos de pedidos aún',
    'bizAiProviders':             '{count} proveedores',
    'bizAiRefreshData':           'Actualizar Datos',
    'bizAiThresholdUpdated':      'Umbral de alertas actualizado a {count} búsquedas',
    'bizAiSectionAlerts':         'Alertas Inteligentes',
    'bizAiSearches':              '{count} búsquedas',
    'bizAiAlertThreshold':        '🔔 Umbral de Alerta de Demanda',
    'bizAiAlertThresholdHint':    'Enviar alerta cuando una palabra clave faltante supere X búsquedas en 24 horas',
    'bizAiReset':                 'Restablecer (5)',
    'bizAiSaveThreshold':         'Guardar Umbral',
    'bizAiAlertHistory':          '📋 Historial de Alertas',
    'bizAiNoAlerts':              'Sin alertas aún — aparecerán cuando las palabras clave superen el umbral',
    'bizAiAlertCount':            '{count}× alertas',
    'bizAiSearchCount':           '{count} búsquedas',
    'bizAiMinutesAgo':            'hace {count} min',
    'bizAiHoursAgo':              'hace {count} hr',
    'bizAiDaysAgo':               'hace {count} días',
    'bizAiExecSummary':           'Resumen Ejecutivo',
    'bizAiAccuracy':              'Precisión AI',
    'bizAiCategoriesApproved':    'Categorías Aprobadas',
    'bizAiMarketOppsCard':        'Oportunidades de Mercado',
    'bizAiNichesNoProviders':     'Nichos Sin Proveedores',
    'bizAiExpectedRevenue':       'Ingresos Esperados',
    'bizAiForecastBadge':         'Previsión',
    'bizAiNoChartData':           'Sin datos de comisión para el gráfico aún\nAparecerá después de la primera transacción',
    'bizAiRecruitForQuery':       'Reclutar proveedores para: "{query}"',
    'bizAiRecruitNow':            'Reclutar Ahora',

    // ── Category Results screen ───────────────────────────────────────────────
    'catResultsExpertDefault':    'Experto',
    'catResultsAvailableSlots':   'Próximos Espacios Disponibles',
    'catResultsNoAvailability':   'Sin disponibilidad en los próximos 14 días',
    'catResultsFullBooking':      'Reserva Completa',
    'catResultsOrderCount':       '🔥 {count} pedidos',
    'catResultsResponseTime':     '⚡ Responde en {minutes} min',
    'catResultsTopRated':         '⭐ Mejor Valorado',
    'catResultsAddPhoto':         'Agregar\nFoto de\nPerfil',
    'catResultsPerHour':          ' / hr',
    'catResultsRecommended':      'Recomendado',
    'catResultsWhenFree':         '¿Cuándo disponible?',
    'catResultsPageTitle':        'Expertos en {category}',
    'catResultsSearchHint':       'Buscar por nombre...',
    'catResultsUnder100':         'Menos de ₪100',
    'catResultsLoadError':        'Error al cargar expertos',
    'catResultsNoResults':        'Sin resultados',
    'catResultsNoExperts':        'Sin expertos en {category} aún',
    'catResultsNoResultsHint':    'Intenta cambiar la búsqueda o quitar el filtro',
    'catResultsBeFirst':          '¡Sé el primero en unirte a esta categoría!',
    'catResultsClearFilters':     'Limpiar Filtros',

    // ── Expert Profile Screen ─────────────────────────────────────────────────
    'traitPunctual':             'Siempre puntual',
    'traitProfessional':         'Profesional',
    'traitCommunicative':        'Gran comunicación',
    'traitPatient':              'Paciente',
    'traitKnowledgeable':        'Con conocimiento',
    'traitFriendly':             'Amigable',
    'traitCreative':             'Creativo/a',
    'traitFlexible':             'Flexible',
    'serviceSingleLesson':       'Lección Individual',
    'serviceSingleSubtitle':     'Una sesión personal',
    'serviceSingle60min':        '60 min',
    'serviceExtendedLesson':     'Lección Extendida',
    'serviceExtendedSubtitle':   'Incluye resumen y tareas',
    'serviceExtended90min':      '90 min',
    'serviceFullSession':        'Sesión Completa',
    'serviceFullSubtitle':       'Trabajo profundo + plan personal',
    'serviceFullSession120min':  '120 min',
    'expertInsufficientBalance': 'Saldo insuficiente en la cartera para completar la reserva',
    'expertEscrowSuccess':       '¡Horario reservado y pago en custodia!',
    'expertTransactionTitle':    'Pago seguro: {name}',
    'expertSystemMessage':       '🔒 Nueva reserva para {date} a las {time}!\nMonto para ti: ₪{amount}',
    'expertRecommendedBadge':    'Destacado',
    'expertStatRating':          'Calificación',
    'expertStatReviews':         'Reseñas',
    'expertStatRepeatClients':   'Clientes habituales',
    'expertStatResponseTime':    'Tiempo de respuesta',
    'expertStatOrders':          'Pedidos',
    'expertStatXp':              'Puntos',
    'expertResponseTimeFormat':  '{minutes}m',
    'expertBioPlaceholder':      'Experto certificado en la comunidad AnySkill.',
    'expertBioShowLess':         'Mostrar menos ▲',
    'expertBioReadMore':         'Leer más ▼',
    'expertSelectTime':          'Selecciona una hora',
    'expertReviewsCount':        '{count} reseñas',
    'expertReviewsHeader':       'Reseñas',
    'expertNoReviews':           'Sin reseñas aún',
    'expertDefaultReviewer':     'Cliente',
    'expertVerifiedBooking':     'Reserva verificada',
    'expertProviderResponse':    'Respuesta del proveedor',
    'expertAddReply':            'Agregar respuesta',
    'expertAddReplyTitle':       'Agregar una respuesta a esta reseña',
    'expertReplyHint':           'Gracias por tu reseña...',
    'expertReplyError':          'Error al guardar la respuesta: {error}',
    'expertPublishReply':        'Publicar respuesta',
    'expertBookForTime':         'Reservar para las {time}',
    'expertStartingFrom':        'Desde ₪{price}',
    'expertSelectDateTime':      'Selecciona fecha y hora',
    'expertBookingSummaryTitle':   'Resumen de Reserva Segura',
    'expertSummaryRowService':     'Servicio',
    'expertSummaryRowDate':        'Fecha',
    'expertSummaryRowTime':        'Hora',
    'expertSummaryRowPrice':       'Precio del servicio',
    'expertSummaryRowProtection':  'Protección AnySkill',
    'expertSummaryRowIncluded':    'Incluido ✓',
    'expertSummaryRowTotal':       'Total a pagar',
    'expertCancellationNotice':    'Política de cancelación: {policy} — cancelación gratuita hasta {deadline}. Después: {penalty}% de penalización.',
    'expertCancellationNoDeadline':'Política de cancelación: {policy} — {description}.',
    'expertConfirmPaymentButton':  'Confirmar pago y reservar horario',
    'expertSectionAbout':         'Sobre el Experto',
    'expertSectionService':       'Elige un servicio',
    'expertSectionGallery':       'Galería',
    'expertSectionSchedule':      'Elige fecha y hora',

    // ── ToS screen ────────────────────────────────────────────────────────
    'tosFullTitle':           'Términos de Servicio y Privacidad',
    'tosLastUpdated':         'Última actualización: marzo 2026  |  Versión 2.0',
    'tosBindingNotice':       'Este acuerdo es vinculante. Por favor léelo antes de aceptar.',
    'tosAcceptButton':        'He leído, entendido y acepto los Términos',

    // ── Finance screen ────────────────────────────────────────────────────
    'financeTitle':           'Mi Cuenta',
    'financeTrustBadge':      'Confianza AnySkill',
    'financeAvailableBalance': 'Saldo Disponible',
    'financeMinWithdraw':     'Retiro mínimo: ₪50',
    'financeWithdrawButton':  'Retirar Fondos',
    'financeRecentActivity':  'Actividad Reciente',
    'financeError':           'Error: {error}',
    'financeNoTransactions':  'Sin transacciones aún',
    'financePaidTo':          'Pagado a {name}',
    'financeReceivedFrom':    'Recibido de {name}',
    'financeProcessing':      'Procesando...',

    // ── Withdrawal modal ──────────────────────────────────────────────────
    'withdrawMinBalance':     'Saldo mínimo para retiro: ₪{amount}',
    'withdrawAvailableBalance': 'Saldo disponible para retiro',
    'withdrawTaxStatusTitle': 'Elige tu estado fiscal',
    'withdrawTaxStatusSubtitle': 'Requerido para procesar el pago según la ley',
    'withdrawTaxBusiness':    'Empresa Registrada',
    'withdrawTaxBusinessSub': 'Exento / Distribuidor licenciado / Empresa',
    'withdrawTaxIndividual':  'Individual (sin licencia empresarial)',
    'withdrawTaxIndividualSub': 'Empleado / freelancer sin expediente fiscal',
    'withdrawTaxIndividualBadge': 'Fácil y rápido',
    'withdrawEncryptedNotice': 'Tus datos están protegidos y cifrados',
    'withdrawBankEncryptedNotice': 'Tus datos bancarios están cifrados y protegidos',
    'withdrawCertSection':    'Certificado Empresarial',
    'withdrawBankSection':    'Datos de Cuenta Bancaria',
    'withdrawBankName':       'Nombre del Banco',
    'withdrawBankBranch':     'Número de Sucursal',
    'withdrawBankAccount':    'Número de Cuenta',
    'withdrawBankRequired':   'Selección de banco requerida',
    'withdrawBranchRequired': 'Requerido',
    'withdrawAccountMinDigits': 'Mín 4 dígitos',
    'withdrawSelectBankError': 'Por favor selecciona un banco',
    'withdrawNoCertError':    'Por favor sube el certificado empresarial antes de continuar',
    'withdrawNoDeclarationError': 'Por favor confirma la declaración fiscal antes de continuar',
    'withdrawUploadError':    'Error al subir — inténtalo de nuevo',
    'withdrawSubmitError':    'Error al enviar — inténtalo de nuevo',
    'withdrawSubmitButton':   'Enviar Solicitud de Retiro — {amount}',
    'withdrawSuccessTitle':   '¡Solicitud Recibida! 🎉',
    'withdrawSuccessSubtitle': 'Solicitud de retiro de {amount} enviada para procesamiento',
    'withdrawSuccessNotice':  'Tu saldo se actualizará después de que el equipo procese tu solicitud. Preguntas: support@anyskill.co.il',
    'withdrawTimeline1Title': 'Solicitud Recibida',
    'withdrawTimeline1Sub':   'Número de referencia enviado al correo',
    'withdrawTimeline2Title': 'Revisión y Verificación',
    'withdrawTimeline2Sub':   'El equipo AnySkill verifica los detalles',
    'withdrawTimeline3Title': 'Dinero en Cuenta',
    'withdrawTimeline3Sub':   'En 3–5 días hábiles',
    'withdrawDeclarationText': 'Declaro responsabilidad exclusiva de reportar impuestos según la ley ',
    'withdrawDeclarationSection': '(Sección 6 de los Términos)',
    'withdrawDeclarationSuffix': '. Entiendo que AnySkill no es mi empleador y no retiene impuestos.',
    'withdrawExistingCert':   'Certificado existente',
    'withdrawCertUploadBtn':  'Subir certificado empresarial',
    'withdrawCertReplace':    'Toca para reemplazar',
    'withdrawCertHint':       'JPG / PNG — certificado de dealer exento o licenciado',
    'withdrawIndividualTitle': 'Servicio de Nómina — Nuestro Servicio Asociado',
    'withdrawIndividualDesc': '¿Sin empresa? ¡No hay problema! A través de nuestro servicio asociado, podemos procesar tu pago legalmente. Se aplica una pequeña tarifa.',
    'withdrawBankTransferPending': 'Transferencia bancaria — pendiente',
    'withdrawBusinessFormTitle': 'Empresa Registrada',
    'withdrawIndividualFormTitle': 'Individual (sin licencia)',

    // ── Onboarding screen ─────────────────────────────────────────────────
    'onboardingStep':         'Paso {step} de {total}',
    'onboardingWelcome':      '¡Bienvenido a AnySkill! 👋',
    'onboardingWelcomeSub':   'Cuéntanos quién eres para personalizar tu experiencia',
    'onboardingRoleCustomerTitle': 'Busco un servicio',
    'onboardingRoleCustomerSub': 'Quiero contratar expertos para mis necesidades',
    'onboardingRoleProviderTitle': 'Soy proveedor de servicios',
    'onboardingRoleProviderSub': 'Tengo habilidades y quiero trabajar a través de AnySkill',
    'onboardingBothRoles':    '¡Genial! Puedes tanto contratar como ofrecer servicios.',
    'onboardingServiceTitle': 'Detalles de tu Servicio',
    'onboardingServiceSub':   '¿Cuál es tu área de especialización y tarifa por hora?',
    'onboardingCategory':     'Área de Especialización',
    'onboardingCategoryHint': 'Elige una categoría...',
    'onboardingPriceLabel':   'Tarifa por Hora (₪)',
    'onboardingPriceHint':    'ej. 150',
    'onboardingPriceTip':     'El precio promedio en esta categoría es ₪100–₪200 por hora.',
    'onboardingProfileTitle': 'Tu Perfil',
    'onboardingProfileSub':   'Una foto y bio corta ayudan a que la gente confíe en ti',
    'onboardingAddPhoto':     'Agregar foto de perfil',
    'onboardingBioLabel':     'Unas palabras sobre ti (opcional)',
    'onboardingBioHint':      'Cuéntanos un poco sobre ti...',
    'onboardingSkipFinish':   'Omitir y finalizar',
    'onboardingNext':         'Continuar',
    'onboardingStart':        'Empezar a usar AnySkill',
    'onboardingError':        'Error: {error}',
    'onboardingUploadError':  'Error de carga: {error}',

    // ── Onboarding — Tax Compliance step ─────────────────────────────────
    'onboardingTaxTitle':         'Verificación Fiscal y de Licencia',
    'onboardingTaxSubtitle':      'Requerido antes de recibir trabajos en la plataforma',
    'onboardingTaxNotice':        'AnySkill es una plataforma exclusiva para profesionales. Debemos verificar su documentación fiscal antes de que pueda aceptar reservas.',
    'onboardingTaxStatusLabel':   'Estado Fiscal',
    'onboardingTaxStatusRequired':'Por favor seleccione un estado fiscal antes de continuar',
    'onboardingDocRequired':      'Por favor suba un documento antes de continuar',
    'onboardingTaxBusiness':      'Negocio Registrado (Exento de IVA / Autorizado)',
    'onboardingTaxBusinessSub':   'Negocio registrado ante las autoridades fiscales',
    'onboardingTaxIndividual':    'Factura a través de Terceros',
    'onboardingTaxIndividualSub': 'Empleado — emitimos factura en su nombre',
    'onboardingDocLabelBusiness': 'Licencia Comercial / Certificado Fiscal',
    'onboardingDocLabelIndividual':'Foto del Documento de Identidad',
    'onboardingDocHintBusiness':  'Foto de su certificado de registro IVA (JPG / PNG)',
    'onboardingDocHintIndividual':'Foto de ambos lados de su documento (JPG / PNG)',
    'onboardingDocUploadPrompt':  'Toque para seleccionar un archivo de su galería',
    'onboardingDocUploadSub':     'JPG · PNG · PDF · Máximo 10MB',
    'onboardingUploading':        'Subiendo...',
    'onboardingDocUploaded':      'Subido exitosamente ✓',
    'onboardingDocReplace':       'Reemplazar',

    // ── Opportunities lock screen ─────────────────────────────────────────
    'oppUnderReviewTitle':    'Cuenta en Revisión',
    'oppUnderReviewSubtitle': 'Estamos verificando sus documentos fiscales',
    'oppUnderReviewBody':     'AnySkill es una plataforma exclusiva para profesionales. Nuestro equipo está revisando los documentos enviados y aprobará su cuenta en 24–48 horas.\n\nRecibirá una notificación cuando su cuenta sea aprobada.',
    'oppUnderReviewStep1':    'Documentos Recibidos',
    'oppUnderReviewStep2':    'Revisión del Admin',
    'oppUnderReviewStep3':    'Cuenta Activa',
    'oppUnderReviewContact':  '¿Preguntas? support@anyskill.co.il',

    // ── Admin — Compliance verification ───────────────────────────────────
    'adminVerifyProvider':    'Verificar Proveedor',
    'adminUnverifyProvider':  'Revocar Verificación',
    'adminVerifiedSuccess':   '{name} verificado — acceso a trabajos habilitado ✓',
    'adminUnverifiedSuccess': 'Verificación de {name} revocada',
    'adminViewDoc':           'Ver Documento',
    'adminComplianceSection': 'Cumplimiento y Fiscalidad',
    'adminComplianceTaxStatus': 'Estado Fiscal',
    'adminCompliancePending': 'Pendiente de Verificación',
    'adminComplianceApproved':'Aprobado',

    // ── Help Center screen ────────────────────────────────────────────────
    'helpCenterProviderSupport': 'Soporte para Proveedores',
    'helpCenterCustomerSupport': 'Soporte para Clientes',
    'helpCenterProviderWelcome': '¡Hola! Soy el asistente de expertos de AnySkill 👋\nAquí encontrarás consejos para gestionar tu perfil, conseguir reservas y más.\n\n¿En qué puedo ayudarte hoy?',
    'helpCenterCustomerWelcome': '¡Hola! Soy el asistente de clientes de AnySkill 👋\nTengo respuestas para cada pregunta — elige de la lista o escribe libremente.\n\n¿En qué puedo ayudarte?',
    'helpCenterProviderFaq':  'Preguntas frecuentes para proveedores',
    'helpCenterCustomerFaq':  'Preguntas frecuentes para clientes',
    'helpCenterInputHint':    'Escribe una pregunta libre...',
    'helpCenterTitle':        'Centro de Ayuda',

    // ── Dispute Resolution ────────────────────────────────────────────────────
    'disputeOpenDisputes':    'Disputas Abiertas',
    'disputeLockedEscrow':    'Bloqueado en Fideicomiso',
    'disputeTapForDetails':   'Toca para detalles y acciones',
    'disputePartyCustomer':   'Cliente',
    'disputePartyProvider':   'Proveedor',
    'disputeArbitrationCenter': 'Centro de Arbitraje',
    'disputeIdPrefix':        'ID:',
    'disputeLockedSuffix':    'bloqueado',
    'disputePartiesSection':  'Partes',
    'disputeReasonSection':   'Motivo de la Disputa',
    'disputeNoReason':        'No se proporcionó motivo.',
    'disputeChatHistory':     'Historial de Chat (últimos 10 mensajes)',
    'disputeAdminNote':       'Nota del Admin (opcional)',
    'disputeAdminNoteHint':   'Agrega una nota que se guardará con la decisión...',
    'disputeExistingNote':    'Nota existente: {note}',
    'disputeActionsSection':  'Acciones de Arbitraje',
    'disputeResolving':       'Procesando...',
    'disputeRefundLabel':     'Reembolso al Cliente',
    'disputeRefundSublabel':  'Reembolso completo ₪{amount}',
    'disputeReleaseLabel':    'Liberar al Experto',
    'disputeReleaseSublabel': 'Después de comisión (≈₪{amount})',
    'disputeSplitLabel':      'División 50/50',
    'disputeSplitSublabel':   '₪{amount} por cada parte',
    'disputeConfirmRefund':   'Reembolso Completo al Cliente',
    'disputeConfirmRelease':  'Liberar al Experto',
    'disputeConfirmSplit':    'División 50/50',
    'disputeRefundBody':      '₪{amount} serán reembolsados a {name}.\nEl experto no recibirá pago.',
    'disputeReleaseBody':     '₪{amount} serán transferidos a {name}\n(después de comisión del {fee}%).',
    'disputeSplitBody':       '₪{half} → Cliente\n₪{halfNet} → Experto (después de comisión)\n₪{platform} → Plataforma',
    'disputeIrreversible':    'Esta acción es irreversible. La decisión se guardará y se enviarán notificaciones FCM a ambas partes.',
    'disputeResolvedRefund':  '✅ Monto reembolsado al cliente. Notificación enviada a ambas partes.',
    'disputeResolvedRelease': '✅ Monto liberado al experto. Notificación enviada a ambas partes.',
    'disputeResolvedSplit':   '⚖️ Acuerdo ejecutado. Notificación enviada a ambas partes.',
    'disputeErrorPrefix':     'Error: {error}',
    'disputeNoChatId':        'No se encontró ID de chat.',
    'disputeNoMessages':      'No hay mensajes en este chat.',
    'disputeSystemSender':    'Sistema',
    'disputeTypeImage':       '📷 Imagen',
    'disputeTypeLocation':    '📍 Ubicación',
    'disputeTypeAudio':       '🎤 Grabación',
    'disputeOpenedAt':        'Abierto el {date}',
    'disputeEmptyTitle':      'No hay disputas abiertas',
    'disputeEmptySubtitle':   'Todo está en orden 🎉',
    // ── My Calendar ───────────────────────────────────────────────────────────
    'calendarTitle':          'Mi Calendario',
    'calendarRefresh':        'Actualizar',
    'calendarNoEvents':       'Sin reservas este día',
    'calendarStatusPending':  'Pendiente de Ejecución',
    'calendarStatusWaiting':  'Esperando Aprobación',
    'calendarStatusCompleted': 'Completado',
    // ── My Requests ───────────────────────────────────────────────────────────
    'requestsTitle':          'Mis Solicitudes',
    'requestsEmpty':          'Sin solicitudes activas',
    'requestsEmptySubtitle':  'Transmite una solicitud rápida y en segundos\n¡proveedores profesionales se pondrán en contacto!',
    'requestsInterested':     '{count} interesados',
    'requestsWaiting':        'Esperando interesados...',
    'requestsWaitingProviders': 'Esperando proveedores interesados...',
    'requestsClosed':         'Solicitud cerrada',
    'requestsViewInterested': 'Ver {count} interesados',
    'requestsInterestedTitle': 'Interesados en tu solicitud',
    'requestsNoInterested':   'Sin proveedores interesados aún',
    'requestsJustNow':        'Ahora mismo',
    'requestsMinutesAgo':     'Hace {minutes} min',
    'requestsHoursAgo':       'Hace {hours} hrs',
    'requestsDaysAgo':        'Hace {days} días',
    'requestsDefaultExpert':  'Experto',
    'requestsHiredAgo':       'Contratado {ago}',
    'requestsOrderCount':     '🔥 {count} trabajos',
    'requestsTopMatch':       'Mejor Coincidencia',
    'requestsMatchLabel':     'Coincidencia',
    'requestsChatNow':        'Chatear Ahora',
    'requestsConfirmPay':     'Confirmar y Pagar',
    'requestsMoneyProtected': 'Dinero protegido hasta finalizar el trabajo',
    'requestsEscrowTooltip':  'Los fondos son retenidos en fideicomiso por AnySkill y transferidos al experto solo tras tu aprobación al finalizar el trabajo.',
    'requestsVerifiedBadge':  'AnySkill Verificado — Pago seguro en fideicomiso',
    'requestsPricePerHour':   '₪{price} / hr',
    'requestsBestValue':      'Mejor Valor',
    'requestsFastResponse':   'Respuesta Rápida',
    // ── XP Manager ────────────────────────────────────────────────────────────
    'xpManagerTitle':         'Sistema XP y Niveles',
    'xpManagerSubtitle':      'Configura eventos, puntos y umbrales de nivel',
    'xpEventsSection':        'Eventos XP',
    'xpEventsCount':          '{count} eventos',
    'xpEventsEmpty':          'Sin eventos aún.\nHaz clic en "Agregar Evento" para comenzar.',
    'xpAddEventButton':       'Agregar Evento',
    'xpEditEventTitle':       'Editar Evento XP',
    'xpAddEventTitle':        'Agregar Nuevo Evento XP',
    'xpFieldId':              'ID del Evento (en inglés, sin espacios)',
    'xpFieldIdHint':          'e.g. late_delivery',
    'xpFieldName':            'Nombre del Evento',
    'xpFieldPoints':          'Puntos XP (negativo = penalización)',
    'xpFieldDesc':            'Descripción corta',
    'xpEventUpdated':         'Evento actualizado ✓',
    'xpEventAdded':           'Evento agregado ✓',
    'xpEventDeleted':         'Evento eliminado',
    'xpDeleteEventTitle':     'Eliminar Evento',
    'xpDeleteEventConfirm':   '¿Eliminar el evento "{name}"?\nEsta acción es irreversible.',
    'xpReservedId':           'El ID "app_levels" está reservado por el sistema',
    'xpTooltipEdit':          'Editar',
    'xpTooltipDelete':        'Eliminar',
    'xpLevelsTitle':          'Umbral de Nivel',
    'xpLevelsSubtitle':       'Establece el XP mínimo requerido para cada nivel.',
    'xpSaveLevels':           'Guardar Umbrales de Nivel',
    'xpLevelsSaved':          'Umbrales de nivel actualizados ✓',
    'xpLevelsError':          'Plata debe ser > 0 y Oro debe ser > Plata',
    'xpLevelBronze':          'Bronce',
    'xpLevelSilver':          'Plata',
    'xpLevelGold':            'Oro',
    'xpSaveAction':           'Guardar',
    'xpAddAction':            'Agregar',
    'xpErrorPrefix':          'Error: {error}',
    // ── System Wallet ─────────────────────────────────────────────────────────
    'systemWalletTitle':      'Gestión Financiera del Sistema',
    'systemWalletBalance':    'Saldo Líquido en Billetera del Sistema',
    'systemWalletPendingFees': 'Comisiones Pendientes',
    'systemWalletActiveJobs': '{count} transacciones activas (fideicomiso / esperando aprobación)',
    'systemWalletFeePanel':   'Establecer Porcentaje de Comisión Global',
    'systemWalletUpdateFee':  'Actualizar',
    'systemWalletFeeUpdated': '¡Comisión actualizada a {value}%!',
    'systemWalletEnterNumber': 'Por favor ingresa un número',
    'systemWalletInvalidNumber': 'Por favor ingresa un número válido',
    'systemWalletEarningsTitle': 'Desglose de Ingresos por Comisiones (tiempo real)',
    'systemWalletExportCsv':  'Exportar CSV',
    'systemWalletExported':   'Exportados {count} registros a CSV',
    'systemWalletExportError': 'Error de exportación: {error}',
    'systemWalletNoEarnings': 'Sin comisiones registradas en el sistema',
    'systemWalletTxStatus':   'Estado: Recibido exitosamente',
    // ── Pending Categories ────────────────────────────────────────────────────
    'pendingCatsTitle':       'Categorías Pendientes de Aprobación',
    'pendingCatsSectionPending': 'Pendientes de Aprobación',
    'pendingCatsSectionReviewed': 'Revisadas',
    'pendingCatsApproved':    '✅ ¡Categoría aprobada y publicada!',
    'pendingCatsRejected':    '🗑 Categoría rechazada',
    'pendingCatsErrorPrefix': 'Error: {error}',
    'pendingCatsSubCategory': 'Sub-categoría: {name}',
    'pendingCatsProviderDesc': 'Descripción del Proveedor',
    'pendingCatsAiReason':    'Razonamiento IA',
    'pendingCatsImagePrompt': 'Prompt de Imagen (Midjourney/DALL-E)',
    'pendingCatsReject':      'Rechazar',
    'pendingCatsApprove':     'Aprobar y Publicar',
    'pendingCatsStatusApproved': 'Aprobado',
    'pendingCatsStatusRejected': 'Rechazado',
    'pendingCatsEmptyTitle':  'No hay categorías pendientes',
    'pendingCatsEmptySubtitle': 'Todas las categorías han sido revisadas o aún no se han creado',
    'pendingCatsOpenedAt':    'Abierto el {date}',
  },
};

// ── AppLocalizations class ────────────────────────────────────────────────────

class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)
        ?? AppLocalizations(const Locale('he'));
  }

  // ── Core lookup with Hebrew fallback ────────────────────────────────────────
  String _t(String key) {
    final lang = locale.languageCode;
    return _translations[lang]?[key]
        ?? _translations['he']?[key]
        ?? key;
  }

  /// Parameterized lookup — replaces {placeholder} tokens.
  String _tp(String key, Map<String, String> params) {
    var s = _t(key);
    params.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }

  // ── App ──────────────────────────────────────────────────────────────────────
  String get appName              => _t('appName');
  String get appSlogan            => _t('appSlogan');

  // ── Navigation ───────────────────────────────────────────────────────────────
  String get tabHome              => _t('tabHome');
  String get tabBookings          => _t('tabBookings');
  String get tabChat              => _t('tabChat');
  String get tabWallet            => _t('tabWallet');
  String get tabProfile           => _t('tabProfile');

  // ── Common actions ───────────────────────────────────────────────────────────
  String get cancel               => _t('cancel');
  String get confirm              => _t('confirm');
  String get submit               => _t('submit');
  String get save                 => _t('save');
  String get close                => _t('close');
  String get delete               => _t('delete');
  String get open                 => _t('open');
  String get back                 => _t('back');
  String get errorGeneric         => _t('errorGeneric');
  String get currencySymbol       => _t('currencySymbol');

  // ── App-level ─────────────────────────────────────────────────────────────────
  String get updateBannerText     => _t('updateBannerText');
  String get updateNowButton      => _t('updateNowButton');
  String get notifOpen            => _t('notifOpen');

  // ── Auth / Login ─────────────────────────────────────────────────────────────
  String get loginTitle           => _t('loginTitle');
  String get loginAccountTitle    => _t('loginAccountTitle');
  String get loginWelcomeBack     => _t('loginWelcomeBack');
  String get loginEmail           => _t('loginEmail');
  String get loginPassword        => _t('loginPassword');
  String get loginButton          => _t('loginButton');
  String get loginRememberMe      => _t('loginRememberMe');
  String get loginForgotPassword  => _t('loginForgotPassword');
  String get loginNoAccount       => _t('loginNoAccount');
  String get loginSignUpFree      => _t('loginSignUpFree');
  String get loginOrWith          => _t('loginOrWith');
  String get loginAppleComingSoon => _t('loginAppleComingSoon');
  String get loginStats10k        => _t('loginStats10k');
  String get loginStats50         => _t('loginStats50');
  String get loginStats49         => _t('loginStats49');

  // Auth errors
  String get errorUserNotFound      => _t('errorUserNotFound');
  String get errorWrongPassword     => _t('errorWrongPassword');
  String get errorInvalidCredential => _t('errorInvalidCredential');
  String get errorInvalidEmail      => _t('errorInvalidEmail');
  String get errorUserDisabled      => _t('errorUserDisabled');
  String get errorTooManyRequests   => _t('errorTooManyRequests');
  String get errorNetworkFailed     => _t('errorNetworkFailed');
  String get errorGenericLogin      => _t('errorGenericLogin');
  String get errorEmptyFields       => _t('errorEmptyFields');
  String get errorGoogleLogin       => _t('errorGoogleLogin');

  // Forgot password
  String get forgotPasswordTitle    => _t('forgotPasswordTitle');
  String get forgotPasswordSubtitle => _t('forgotPasswordSubtitle');
  String get forgotPasswordEmail    => _t('forgotPasswordEmail');
  String get forgotPasswordSubmit   => _t('forgotPasswordSubmit');
  String get forgotPasswordSuccess  => _t('forgotPasswordSuccess');
  String get forgotPasswordError    => _t('forgotPasswordError');

  // Sign-up
  String get signupButton           => _t('signupButton');
  String get signupTitle            => _t('signupTitle');
  String get googleNewUserBio       => _t('googleNewUserBio');

  // Validation
  String get validationNameRequired   => _t('validationNameRequired');
  String get validationNameLength     => _t('validationNameLength');
  String get validationRoleRequired   => _t('validationRoleRequired');
  String get validationCategoryRequired => _t('validationCategoryRequired');
  String get validationPriceInvalid   => _t('validationPriceInvalid');
  String get validationPricePositive  => _t('validationPricePositive');

  // ── Profile ──────────────────────────────────────────────────────────────────
  String get profileTitle             => _t('profileTitle');
  String get shareProfileTitle        => _t('shareProfileTitle');
  String get shareProfileWhatsapp     => _t('shareProfileWhatsapp');
  String get shareProfileCopyLink     => _t('shareProfileCopyLink');
  String get shareProfileTooltip      => _t('shareProfileTooltip');
  String get linkCopied               => _t('linkCopied');
  String get whatsappError            => _t('whatsappError');
  String get defaultUserName          => _t('defaultUserName');
  String get logoutTooltip            => _t('logoutTooltip');
  String get logoutTitle              => _t('logoutTitle');
  String get logoutContent            => _t('logoutContent');
  String get logoutConfirm            => _t('logoutConfirm');
  String get logoutButton             => _t('logoutButton');
  String get aboutMeTitle             => _t('aboutMeTitle');
  String get aboutMePlaceholder       => _t('aboutMePlaceholder');
  String get galleryTitle             => _t('galleryTitle');
  String get galleryEmpty             => _t('galleryEmpty');
  String get statRating               => _t('statRating');
  String get statBalance              => _t('statBalance');
  String get statWorks                => _t('statWorks');
  String get bookingsTrackerButton    => _t('bookingsTrackerButton');
  String get bookingsTrackerSnackbar  => _t('bookingsTrackerSnackbar');

  // VIP
  String get vipActiveLabel           => _t('vipActiveLabel');
  String get vipExpiredLabel          => _t('vipExpiredLabel');
  String get vipHighlight             => _t('vipHighlight');
  String get vipUpsellTitle           => _t('vipUpsellTitle');
  String get vipBenefit1              => _t('vipBenefit1');
  String get vipBenefit2              => _t('vipBenefit2');
  String get vipBenefit3              => _t('vipBenefit3');
  String get vipBenefit4              => _t('vipBenefit4');
  String get vipCtaButton             => _t('vipCtaButton');
  String get vipSheetHeader           => _t('vipSheetHeader');
  String get vipPriceMonthly          => _t('vipPriceMonthly');
  String get vipActivateButton        => _t('vipActivateButton');
  String get vipInsufficientBalance   => _t('vipInsufficientBalance');
  String get vipInsufficientTooltip   => _t('vipInsufficientTooltip');
  String get vipActivationSuccess     => _t('vipActivationSuccess');
  String vipDaysLeft(int days)        => _tp('vipDaysLeft', {'days': '$days'});
  String vipCurrentBalance(String amt)=> _tp('vipCurrentBalance', {'amount': amt});

  // ── Language selector ─────────────────────────────────────────────────────────
  String get languageTitle            => _t('languageTitle');
  String get languageHe               => _t('languageHe');
  String get languageEn               => _t('languageEn');
  String get languageEs               => _t('languageEs');
  String get languageSectionLabel     => _t('languageSectionLabel');

  // ── Chat list ────────────────────────────────────────────────────────────────
  String get chatListTitle            => _t('chatListTitle');
  String get chatSearchHint           => _t('chatSearchHint');
  String get chatEmptyState           => _t('chatEmptyState');
  String get chatUserDefault          => _t('chatUserDefault');
  String get chatLastMessageDefault   => _t('chatLastMessageDefault');
  String get markAllReadTooltip       => _t('markAllReadTooltip');
  String get markAllReadSuccess       => _t('markAllReadSuccess');
  String get deleteChatTitle          => _t('deleteChatTitle');
  String get deleteChatContent        => _t('deleteChatContent');
  String get deleteChatConfirm        => _t('deleteChatConfirm');
  String get deleteChatSuccess        => _t('deleteChatSuccess');
  String get notLoggedIn              => _t('notLoggedIn');

  // ── Search / Home ─────────────────────────────────────────────────────────────
  String get searchPlaceholder        => _t('searchPlaceholder');
  String get searchTitle              => _t('searchTitle');
  String get discoverCategories       => _t('discoverCategories');
  String get searchHintExperts        => _t('searchHintExperts');
  String get greetingMorning          => _t('greetingMorning');
  String get greetingAfternoon        => _t('greetingAfternoon');
  String get greetingEvening          => _t('greetingEvening');
  String get greetingNight            => _t('greetingNight');
  String get greetingSubMorning       => _t('greetingSubMorning');
  String get greetingSubAfternoon     => _t('greetingSubAfternoon');
  String get greetingSubEvening       => _t('greetingSubEvening');
  String get greetingSubNight         => _t('greetingSubNight');
  String get onlineStatus             => _t('onlineStatus');
  String get offlineStatus            => _t('offlineStatus');
  String get quickRequest             => _t('quickRequest');
  String get urgentJobBanner          => _t('urgentJobBanner');
  String get bookNow                  => _t('bookNow');

  // ── Wallet ────────────────────────────────────────────────────────────────────
  String get walletBalance            => _t('walletBalance');
  String get walletMinWithdraw        => _t('walletMinWithdraw');
  String get withdrawFunds            => _t('withdrawFunds');

  // ── ToS ───────────────────────────────────────────────────────────────────────
  String get tosTitle                 => _t('tosTitle');
  String get tosAgree                 => _t('tosAgree');

  // ── Misc ──────────────────────────────────────────────────────────────────────
  String get trendingBadge            => _t('trendingBadge');
  String get subCategoryPrompt        => _t('subCategoryPrompt');
  String get reviewSubmit             => _t('reviewSubmit');
  String get urgentOpenButton         => _t('urgentOpenButton');

  // ── Edit Profile ──────────────────────────────────────────────────────────────
  String get editProfileTitle         => _t('editProfileTitle');
  String get saveSuccess              => _t('saveSuccess');
  String get saveChanges              => _t('saveChanges');
  String saveError(String error)      => _tp('saveError', {'error': error});
  String get profileFieldName         => _t('profileFieldName');
  String get profileFieldNameHint     => _t('profileFieldNameHint');
  String get profileFieldRole         => _t('profileFieldRole');
  String get roleProvider             => _t('roleProvider');
  String get roleCustomer             => _t('roleCustomer');
  String get profileFieldCategoryMain => _t('profileFieldCategoryMain');
  String get profileFieldCategoryMainHint => _t('profileFieldCategoryMainHint');
  String get profileFieldCategorySub  => _t('profileFieldCategorySub');
  String get profileFieldCategorySubHint  => _t('profileFieldCategorySubHint');
  String get profileFieldPrice        => _t('profileFieldPrice');
  String get profileFieldPriceHint    => _t('profileFieldPriceHint');
  String get profileFieldResponseTime => _t('profileFieldResponseTime');
  String get profileFieldResponseTimeHint => _t('profileFieldResponseTimeHint');
  String get profileFieldTaxId        => _t('profileFieldTaxId');
  String get profileFieldTaxIdHint    => _t('profileFieldTaxIdHint');
  String get profileFieldTaxIdHelp    => _t('profileFieldTaxIdHelp');
  String get editProfileQuickTags     => _t('editProfileQuickTags');
  String editProfileTagsSelected(int count) => _tp('editProfileTagsSelected', {'count': '$count'});
  String get editProfileTagsHint      => _t('editProfileTagsHint');
  String get editProfileCancellationPolicy => _t('editProfileCancellationPolicy');
  String get editProfileCancellationHint   => _t('editProfileCancellationHint');
  String get editProfileAbout         => _t('editProfileAbout');
  String get editProfileAboutHint     => _t('editProfileAboutHint');
  String get editProfileGallery       => _t('editProfileGallery');

  // ── Home tab ──────────────────────────────────────────────────────────────────
  String get homeProviderGreetingSub  => _t('homeProviderGreetingSub');
  String get homeCustomerGreetingSub  => _t('homeCustomerGreetingSub');
  String get noCategoriesYet          => _t('noCategoriesYet');
  String get urgentBannerRequests     => _t('urgentBannerRequests');
  String get urgentBannerPending      => _t('urgentBannerPending');
  String get urgentBannerCustomerWaiting => _t('urgentBannerCustomerWaiting');
  String get urgentBannerServiceNeeded   => _t('urgentBannerServiceNeeded');
  String get timeOneHour              => _t('timeOneHour');

  // ── Notifications ──────────────────────────────────────────────────────────────
  String get notificationsTitle       => _t('notificationsTitle');
  String get notifClearAll            => _t('notifClearAll');
  String get notifEmptyTitle          => _t('notifEmptyTitle');
  String get notifEmptySubtitle       => _t('notifEmptySubtitle');
  String get timeNow                  => _t('timeNow');
  String timeMinutesAgo(int m)        => _tp('timeMinutesAgo', {'minutes': '$m'});
  String timeHoursAgo(int h)          => _tp('timeHoursAgo', {'hours': '$h'});

  // ── Sign Up ──────────────────────────────────────────────────────────────────
  String get signupTosMustAgree       => _t('signupTosMustAgree');
  String get signupAccountCreated     => _t('signupAccountCreated');
  String get signupEmailInUse         => _t('signupEmailInUse');
  String get signupWeakPassword       => _t('signupWeakPassword');
  String get signupNetworkError       => _t('signupNetworkError');
  String get signupGenericError       => _t('signupGenericError');
  String get signupNewProviderBio     => _t('signupNewProviderBio');
  String get signupNewCustomerBio     => _t('signupNewCustomerBio');
  String get signupIAmCustomer        => _t('signupIAmCustomer');
  String get signupIAmProvider        => _t('signupIAmProvider');
  String get signupCustomerDesc       => _t('signupCustomerDesc');
  String get signupProviderDesc       => _t('signupProviderDesc');
  String get signupName               => _t('signupName');
  String get signupNameHint           => _t('signupNameHint');
  String get signupEmail              => _t('signupEmail');
  String get signupEmailHint          => _t('signupEmailHint');
  String get signupPassword           => _t('signupPassword');
  String get signupPasswordHint       => _t('signupPasswordHint');
  String get signupPhone              => _t('signupPhone');
  String get signupPhoneHint          => _t('signupPhoneHint');
  String get signupCategory           => _t('signupCategory');
  String get signupTosPrefix          => _t('signupTosPrefix');
  String get signupTosLink            => _t('signupTosLink');
  String get signupHaveAccount        => _t('signupHaveAccount');
  String get signupLogin              => _t('signupLogin');
  String get signupOrWith             => _t('signupOrWith');
  String get signupGoogleError        => _t('signupGoogleError');
  String signupPasswordStrength(int s) {
    switch (s) {
      case 0: return _t('signupPasswordStrength0');
      case 1: return _t('signupPasswordStrength1');
      case 2: return _t('signupPasswordStrength2');
      case 3: return _t('signupPasswordStrength3');
      default: return _t('signupPasswordStrength4');
    }
  }
  String get signupNameValidation     => _t('signupNameValidation');
  String get signupEmailValidation    => _t('signupEmailValidation');
  String get signupPasswordValidation => _t('signupPasswordValidation');
  String get signupCategoryRequired   => _t('signupCategoryRequired');

  // ── Bookings ──────────────────────────────────────────────────────────────────
  String get availabilityUpdated      => _t('availabilityUpdated');
  String get bookingCompleted         => _t('bookingCompleted');
  String get releasePaymentError      => _t('releasePaymentError');
  String get markedDoneSuccess        => _t('markedDoneSuccess');
  String get cancelBookingTitle       => _t('cancelBookingTitle');
  String cancelPenaltyWarning(String policy, String penalty) => _tp('cancelPenaltyWarning', {'policy': policy, 'penalty': penalty});
  String cancelRefundBreakdown(String refund, String penalty) => _tp('cancelRefundBreakdown', {'refund': refund, 'penalty': penalty});
  String cancelSimpleConfirm(String amount) => _tp('cancelSimpleConfirm', {'amount': amount});
  String get noGoBack                 => _t('noGoBack');
  String yesCancelWithPenalty(String penalty) => _tp('yesCancelWithPenalty', {'penalty': penalty});
  String get yesCancel                => _t('yesCancel');
  String bookingCancelledRefund(String amount) => _tp('bookingCancelledRefund', {'amount': amount});
  String cancelError(String error)    => _tp('cancelError', {'error': error});
  String get providerCancelTitle      => _t('providerCancelTitle');
  String get providerCancelContent    => _t('providerCancelContent');
  String get providerCancelledSuccess => _t('providerCancelledSuccess');
  String get disputeTitle             => _t('disputeTitle');
  String get disputeDescription       => _t('disputeDescription');
  String get disputeHint              => _t('disputeHint');
  String get submitDispute            => _t('submitDispute');
  String get jobTabActive             => _t('jobTabActive');
  String get jobTabHistory            => _t('jobTabHistory');
  String get jobTabCalendar           => _t('jobTabCalendar');
  String get bookingsTitle            => _t('bookingsTitle');
  String get bookingsEmptyActive      => _t('bookingsEmptyActive');
  String get bookingsEmptyHistory     => _t('bookingsEmptyHistory');
  String get jobStatusPaidEscrow      => _t('jobStatusPaidEscrow');
  String get jobStatusExpertCompleted => _t('jobStatusExpertCompleted');
  String get jobStatusCompleted       => _t('jobStatusCompleted');
  String get jobStatusCancelled       => _t('jobStatusCancelled');
  String get jobStatusDisputed        => _t('jobStatusDisputed');
  String get saveAvailability         => _t('saveAvailability');
  String get releasePayment           => _t('releasePayment');
  String get markDone                 => _t('markDone');
  String get openChat                 => _t('openChat');
  String get openDispute              => _t('openDispute');
  String get cancelBooking            => _t('cancelBooking');
  String get ratingTitle              => _t('ratingTitle');
  String get ratingSubmit             => _t('ratingSubmit');

  // ── Opportunities screen ──────────────────────────────────────────────────────
  String get oppTitle                 => _t('oppTitle');
  String get oppAllCategories         => _t('oppAllCategories');
  String oppError(String error)       => _tp('oppError', {'error': error});
  String get oppDefaultClient         => _t('oppDefaultClient');
  String get oppRequestUnavailable    => _t('oppRequestUnavailable');
  String get oppRequestClosed3        => _t('oppRequestClosed3');
  String get oppAlreadyExpressed      => _t('oppAlreadyExpressed');
  String get oppAlready3Interested    => _t('oppAlready3Interested');
  String oppInterestChatMessage(String providerName, String description) =>
      _tp('oppInterestChatMessage', {'providerName': providerName, 'description': description});
  String get oppNotifTitle            => _t('oppNotifTitle');
  String oppNotifBody(String providerName) => _tp('oppNotifBody', {'providerName': providerName});
  String get oppBoostEarned           => _t('oppBoostEarned');
  String get oppInterestSuccess       => _t('oppInterestSuccess');
  String oppQuickBidMessage(String clientName, String providerName) =>
      _tp('oppQuickBidMessage', {'clientName': clientName, 'providerName': providerName});
  String oppXpToNextLevel(int xp, String name) =>
      _tp('oppXpToNextLevel', {'xp': '$xp', 'name': name});
  String get oppMaxLevel              => _t('oppMaxLevel');
  String oppProfileBoosted(String time) => _tp('oppProfileBoosted', {'time': time});
  String oppBoostProgress(int count)  => _tp('oppBoostProgress', {'count': '$count'});
  String oppTimeHours(int hours)      => _tp('oppTimeHours', {'hours': '$hours'});
  String oppTimeMinutes(int minutes)  => _tp('oppTimeMinutes', {'minutes': '$minutes'});
  String get oppTimeJustNow           => _t('oppTimeJustNow');
  String oppTimeMinAgo(int minutes)   => _tp('oppTimeMinAgo', {'minutes': '$minutes'});
  String oppTimeHourAgo(int hours)    => _tp('oppTimeHourAgo', {'hours': '$hours'});
  String oppTimeDayAgo(int days)      => _tp('oppTimeDayAgo', {'days': '$days'});
  String get oppEmptyCategory         => _t('oppEmptyCategory');
  String get oppEmptyAll              => _t('oppEmptyAll');
  String get oppEmptyCategorySubtitle => _t('oppEmptyCategorySubtitle');
  String get oppEmptyAllSubtitle      => _t('oppEmptyAllSubtitle');
  String get oppHighDemand            => _t('oppHighDemand');
  String oppViewersNow(int viewers)   => _tp('oppViewersNow', {'viewers': '$viewers'});
  String get oppEstimatedEarnings     => _t('oppEstimatedEarnings');
  String get oppAfterFee              => _t('oppAfterFee');
  String get oppAlreadyInterested     => _t('oppAlreadyInterested');
  String get oppRequestClosedBtn      => _t('oppRequestClosedBtn');
  String get oppTakeOpportunity       => _t('oppTakeOpportunity');
  String get oppInterested            => _t('oppInterested');
  String get oppQuickBid              => _t('oppQuickBid');
  String get oppWalletHint            => _t('oppWalletHint');

  // ── Search page ───────────────────────────────────────────────────────────────
  String get helpCenterTooltip          => _t('helpCenterTooltip');
  String get searchTourSearchTitle      => _t('searchTourSearchTitle');
  String get searchTourSearchDesc       => _t('searchTourSearchDesc');
  String get searchTourSuggestionsTitle => _t('searchTourSuggestionsTitle');
  String get searchTourSuggestionsDesc  => _t('searchTourSuggestionsDesc');
  String get searchTourFeedTitle        => _t('searchTourFeedTitle');
  String get searchTourFeedDesc         => _t('searchTourFeedDesc');
  String get searchNoCategoriesBody     => _t('searchNoCategoriesBody');
  String searchNoResultsFor(String query)     => _tp('searchNoResultsFor', {'query': query});
  String get searchSectionCategories    => _t('searchSectionCategories');
  String searchSectionResultsFor(String query) => _tp('searchSectionResultsFor', {'query': query});
  String get searchRecommendedBadge     => _t('searchRecommendedBadge');
  String get searchPerHour              => _t('searchPerHour');
  String get searchDatePickerHint       => _t('searchDatePickerHint');
  String get searchChipWeekend          => _t('searchChipWeekend');
  String get searchChipHomeVisit        => _t('searchChipHomeVisit');
  String get searchUrgencyMorning       => _t('searchUrgencyMorning');
  String get searchUrgencyAfternoon     => _t('searchUrgencyAfternoon');
  String get searchUrgencyEvening       => _t('searchUrgencyEvening');
  String get searchDefaultExpert        => _t('searchDefaultExpert');
  String get searchDefaultCity          => _t('searchDefaultCity');
  String get searchDefaultTitle         => _t('searchDefaultTitle');
  String get editCategoryTitle          => _t('editCategoryTitle');
  String get editCategoryChangePic      => _t('editCategoryChangePic');
  String get editCategoryNameLabel      => _t('editCategoryNameLabel');
  String editCategorySaveError(String error) => _tp('editCategorySaveError', {'error': error});
  String get creditsLabel               => _t('creditsLabel');
  String creditsDiscountAvailable(int discount) => _tp('creditsDiscountAvailable', {'discount': '$discount'});
  String creditsToNextDiscount(int remaining)   => _tp('creditsToNextDiscount', {'remaining': '$remaining'});
  String get inspirationFeedTitle       => _t('inspirationFeedTitle');
  String get inspirationFeedNewBadge    => _t('inspirationFeedNewBadge');
  String get inspirationCompletedBadge  => _t('inspirationCompletedBadge');
  String get onlineToggleOn             => _t('onlineToggleOn');
  String get onlineToggleOff            => _t('onlineToggleOff');

  // ── Expert Profile Screen ─────────────────────────────────────────────────────
  // Trait tag labels
  String get traitPunctual             => _t('traitPunctual');
  String get traitProfessional         => _t('traitProfessional');
  String get traitCommunicative        => _t('traitCommunicative');
  String get traitPatient              => _t('traitPatient');
  String get traitKnowledgeable        => _t('traitKnowledgeable');
  String get traitFriendly             => _t('traitFriendly');
  String get traitCreative             => _t('traitCreative');
  String get traitFlexible             => _t('traitFlexible');
  // Service tiers
  String get serviceSingleLesson       => _t('serviceSingleLesson');
  String get serviceSingleSubtitle     => _t('serviceSingleSubtitle');
  String get serviceSingle60min        => _t('serviceSingle60min');
  String get serviceExtendedLesson     => _t('serviceExtendedLesson');
  String get serviceExtendedSubtitle   => _t('serviceExtendedSubtitle');
  String get serviceExtended90min      => _t('serviceExtended90min');
  String get serviceFullSession        => _t('serviceFullSession');
  String get serviceFullSubtitle       => _t('serviceFullSubtitle');
  String get serviceFullSession120min  => _t('serviceFullSession120min');
  // Booking flow
  String get expertInsufficientBalance => _t('expertInsufficientBalance');
  String get expertEscrowSuccess       => _t('expertEscrowSuccess');
  String expertTransactionTitle(String name)             => _tp('expertTransactionTitle', {'name': name});
  String expertSystemMessage(String date, String time, String amount) =>
      _tp('expertSystemMessage', {'date': date, 'time': time, 'amount': amount});
  // Hero badges & power row
  String get expertRecommendedBadge    => _t('expertRecommendedBadge');
  String get expertStatRating          => _t('expertStatRating');
  String get expertStatReviews         => _t('expertStatReviews');
  String get expertStatRepeatClients   => _t('expertStatRepeatClients');
  String get expertStatResponseTime    => _t('expertStatResponseTime');
  String get expertStatOrders          => _t('expertStatOrders');
  String get expertStatXp              => _t('expertStatXp');
  String expertResponseTimeFormat(int minutes) => _tp('expertResponseTimeFormat', {'minutes': '$minutes'});
  // Bio
  String get expertBioPlaceholder      => _t('expertBioPlaceholder');
  String get expertBioShowLess         => _t('expertBioShowLess');
  String get expertBioReadMore         => _t('expertBioReadMore');
  // Time slot picker
  String get expertSelectTime          => _t('expertSelectTime');
  // Reviews section
  String expertReviewsCount(int count) => _tp('expertReviewsCount', {'count': '$count'});
  String get expertReviewsHeader       => _t('expertReviewsHeader');
  String get expertNoReviews           => _t('expertNoReviews');
  String get expertDefaultReviewer     => _t('expertDefaultReviewer');
  String get expertVerifiedBooking     => _t('expertVerifiedBooking');
  String get expertProviderResponse    => _t('expertProviderResponse');
  String get expertAddReply            => _t('expertAddReply');
  String get expertAddReplyTitle       => _t('expertAddReplyTitle');
  String get expertReplyHint           => _t('expertReplyHint');
  String expertReplyError(String error)=> _tp('expertReplyError', {'error': error});
  String get expertPublishReply        => _t('expertPublishReply');
  // Bottom bar / booking flow
  String expertBookForTime(String time)    => _tp('expertBookForTime', {'time': time});
  String expertStartingFrom(String price)  => _tp('expertStartingFrom', {'price': price});
  String get expertSelectDateTime          => _t('expertSelectDateTime');
  // Booking summary sheet
  String get expertBookingSummaryTitle     => _t('expertBookingSummaryTitle');
  String get expertSummaryRowService       => _t('expertSummaryRowService');
  String get expertSummaryRowDate          => _t('expertSummaryRowDate');
  String get expertSummaryRowTime          => _t('expertSummaryRowTime');
  String get expertSummaryRowPrice         => _t('expertSummaryRowPrice');
  String get expertSummaryRowProtection    => _t('expertSummaryRowProtection');
  String get expertSummaryRowIncluded      => _t('expertSummaryRowIncluded');
  String get expertSummaryRowTotal         => _t('expertSummaryRowTotal');
  String expertCancellationNotice(String policy, String deadline, int penalty) =>
      _tp('expertCancellationNotice', {'policy': policy, 'deadline': deadline, 'penalty': '$penalty'});
  String expertCancellationNoDeadline(String policy, String description) =>
      _tp('expertCancellationNoDeadline', {'policy': policy, 'description': description});
  String get expertConfirmPaymentButton    => _t('expertConfirmPaymentButton');
  // Section headers
  String get expertSectionAbout           => _t('expertSectionAbout');
  String get expertSectionService         => _t('expertSectionService');
  String get expertSectionGallery         => _t('expertSectionGallery');
  String get expertSectionSchedule        => _t('expertSectionSchedule');

  // ── Shared actions ────────────────────────────────────────────────────────────
  String get retryButton                => _t('retryButton');

  // ── Business AI screen ────────────────────────────────────────────────────────
  String get bizAiLoading               => _t('bizAiLoading');
  String bizAiError(String error)       => _tp('bizAiError', {'error': error});
  String get bizAiTitle                 => _t('bizAiTitle');
  String get bizAiSubtitle              => _t('bizAiSubtitle');
  String bizAiPending(int count)        => _tp('bizAiPending', {'count': '$count'});
  String get bizAiSectionAiOps          => _t('bizAiSectionAiOps');
  String get bizAiActivityToday         => _t('bizAiActivityToday');
  String get bizAiNewCategories         => _t('bizAiNewCategories');
  String get bizAiApprovalQueue         => _t('bizAiApprovalQueue');
  String get bizAiTapToReview           => _t('bizAiTapToReview');
  String get bizAiModelAccuracy         => _t('bizAiModelAccuracy');
  String get bizAiApprovedTotal         => _t('bizAiApprovedTotal');
  String get bizAiModelAccuracyDetail   => _t('bizAiModelAccuracyDetail');
  String get bizAiApproved              => _t('bizAiApproved');
  String get bizAiRejected              => _t('bizAiRejected');
  String get bizAiPendingLabel          => _t('bizAiPendingLabel');
  String get bizAiNoData                => _t('bizAiNoData');
  String get bizAiSectionMarket         => _t('bizAiSectionMarket');
  String get bizAiPopularSearches       => _t('bizAiPopularSearches');
  String get bizAiNoSearchData          => _t('bizAiNoSearchData');
  String get bizAiMarketOpportunities   => _t('bizAiMarketOpportunities');
  String get bizAiZeroResultsHint       => _t('bizAiZeroResultsHint');
  String get bizAiNoOpportunities       => _t('bizAiNoOpportunities');
  String get bizAiSectionFinancial      => _t('bizAiSectionFinancial');
  String get bizAiWeeklyForecast        => _t('bizAiWeeklyForecast');
  String get bizAiSevenDays             => _t('bizAiSevenDays');
  String get bizAiActualToDate          => _t('bizAiActualToDate');
  String get bizAiWeeklyProjection      => _t('bizAiWeeklyProjection');
  String get bizAiLast7Days             => _t('bizAiLast7Days');
  String get bizAiDailyCommission       => _t('bizAiDailyCommission');
  String get bizAiHighValueCategories   => _t('bizAiHighValueCategories');
  String get bizAiHighValueHint         => _t('bizAiHighValueHint');
  String get bizAiNoOrderData           => _t('bizAiNoOrderData');
  String bizAiProviders(int count)      => _tp('bizAiProviders', {'count': '$count'});
  String get bizAiRefreshData           => _t('bizAiRefreshData');
  String bizAiThresholdUpdated(int count) => _tp('bizAiThresholdUpdated', {'count': '$count'});
  String get bizAiSectionAlerts         => _t('bizAiSectionAlerts');
  String bizAiSearches(int count)       => _tp('bizAiSearches', {'count': '$count'});
  String get bizAiAlertThreshold        => _t('bizAiAlertThreshold');
  String get bizAiAlertThresholdHint    => _t('bizAiAlertThresholdHint');
  String get bizAiReset                 => _t('bizAiReset');
  String get bizAiSaveThreshold         => _t('bizAiSaveThreshold');
  String get bizAiAlertHistory          => _t('bizAiAlertHistory');
  String get bizAiNoAlerts              => _t('bizAiNoAlerts');
  String bizAiAlertCount(int count)     => _tp('bizAiAlertCount', {'count': '$count'});
  String bizAiSearchCount(int count)    => _tp('bizAiSearchCount', {'count': '$count'});
  String bizAiMinutesAgo(int count)     => _tp('bizAiMinutesAgo', {'count': '$count'});
  String bizAiHoursAgo(int count)       => _tp('bizAiHoursAgo', {'count': '$count'});
  String bizAiDaysAgo(int count)        => _tp('bizAiDaysAgo', {'count': '$count'});
  String get bizAiExecSummary           => _t('bizAiExecSummary');
  String get bizAiAccuracy              => _t('bizAiAccuracy');
  String get bizAiCategoriesApproved    => _t('bizAiCategoriesApproved');
  String get bizAiMarketOppsCard        => _t('bizAiMarketOppsCard');
  String get bizAiNichesNoProviders     => _t('bizAiNichesNoProviders');
  String get bizAiExpectedRevenue       => _t('bizAiExpectedRevenue');
  String get bizAiForecastBadge         => _t('bizAiForecastBadge');
  String get bizAiNoChartData           => _t('bizAiNoChartData');
  String bizAiRecruitForQuery(String query) => _tp('bizAiRecruitForQuery', {'query': query});
  String get bizAiRecruitNow            => _t('bizAiRecruitNow');

  // ── Category Results screen ───────────────────────────────────────────────────
  String get catResultsExpertDefault    => _t('catResultsExpertDefault');
  String get catResultsAvailableSlots   => _t('catResultsAvailableSlots');
  String get catResultsNoAvailability   => _t('catResultsNoAvailability');
  String get catResultsFullBooking      => _t('catResultsFullBooking');
  String catResultsOrderCount(int count)      => _tp('catResultsOrderCount', {'count': '$count'});
  String catResultsResponseTime(int minutes)  => _tp('catResultsResponseTime', {'minutes': '$minutes'});
  String get catResultsTopRated         => _t('catResultsTopRated');
  String get catResultsAddPhoto         => _t('catResultsAddPhoto');
  String get catResultsPerHour          => _t('catResultsPerHour');
  String get catResultsRecommended      => _t('catResultsRecommended');
  String get catResultsWhenFree         => _t('catResultsWhenFree');
  String catResultsPageTitle(String category) => _tp('catResultsPageTitle', {'category': category});
  String get catResultsSearchHint       => _t('catResultsSearchHint');
  String get catResultsUnder100         => _t('catResultsUnder100');
  String get catResultsLoadError        => _t('catResultsLoadError');
  String get catResultsNoResults        => _t('catResultsNoResults');
  String catResultsNoExperts(String category) => _tp('catResultsNoExperts', {'category': category});
  String get catResultsNoResultsHint    => _t('catResultsNoResultsHint');
  String get catResultsBeFirst          => _t('catResultsBeFirst');
  String get catResultsClearFilters     => _t('catResultsClearFilters');

  // ── ToS screen ───────────────────────────────────────────────────────────────
  String get tosFullTitle               => _t('tosFullTitle');
  String get tosLastUpdated             => _t('tosLastUpdated');
  String get tosBindingNotice           => _t('tosBindingNotice');
  String get tosAcceptButton            => _t('tosAcceptButton');

  // ── Finance screen ────────────────────────────────────────────────────────────
  String get financeTitle               => _t('financeTitle');
  String get financeTrustBadge          => _t('financeTrustBadge');
  String get financeAvailableBalance    => _t('financeAvailableBalance');
  String get financeMinWithdraw         => _t('financeMinWithdraw');
  String get financeWithdrawButton      => _t('financeWithdrawButton');
  String get financeRecentActivity      => _t('financeRecentActivity');
  String financeError(String error)     => _tp('financeError', {'error': error});
  String get financeNoTransactions      => _t('financeNoTransactions');
  String financePaidTo(String name)     => _tp('financePaidTo', {'name': name});
  String financeReceivedFrom(String name) => _tp('financeReceivedFrom', {'name': name});
  String get financeProcessing          => _t('financeProcessing');

  // ── Withdrawal modal ─────────────────────────────────────────────────────────
  String withdrawMinBalance(int amount) => _tp('withdrawMinBalance', {'amount': '$amount'});
  String get withdrawAvailableBalance   => _t('withdrawAvailableBalance');
  String get withdrawTaxStatusTitle     => _t('withdrawTaxStatusTitle');
  String get withdrawTaxStatusSubtitle  => _t('withdrawTaxStatusSubtitle');
  String get withdrawTaxBusiness        => _t('withdrawTaxBusiness');
  String get withdrawTaxBusinessSub     => _t('withdrawTaxBusinessSub');
  String get withdrawTaxIndividual      => _t('withdrawTaxIndividual');
  String get withdrawTaxIndividualSub   => _t('withdrawTaxIndividualSub');
  String get withdrawTaxIndividualBadge => _t('withdrawTaxIndividualBadge');
  String get withdrawEncryptedNotice    => _t('withdrawEncryptedNotice');
  String get withdrawBankEncryptedNotice => _t('withdrawBankEncryptedNotice');
  String get withdrawCertSection        => _t('withdrawCertSection');
  String get withdrawBankSection        => _t('withdrawBankSection');
  String get withdrawBankName           => _t('withdrawBankName');
  String get withdrawBankBranch         => _t('withdrawBankBranch');
  String get withdrawBankAccount        => _t('withdrawBankAccount');
  String get withdrawBankRequired       => _t('withdrawBankRequired');
  String get withdrawBranchRequired     => _t('withdrawBranchRequired');
  String get withdrawAccountMinDigits   => _t('withdrawAccountMinDigits');
  String get withdrawSelectBankError    => _t('withdrawSelectBankError');
  String get withdrawNoCertError        => _t('withdrawNoCertError');
  String get withdrawNoDeclarationError => _t('withdrawNoDeclarationError');
  String get withdrawUploadError        => _t('withdrawUploadError');
  String get withdrawSubmitError        => _t('withdrawSubmitError');
  String withdrawSubmitButton(String amount) => _tp('withdrawSubmitButton', {'amount': amount});
  String get withdrawSuccessTitle       => _t('withdrawSuccessTitle');
  String withdrawSuccessSubtitle(String amount) => _tp('withdrawSuccessSubtitle', {'amount': amount});
  String get withdrawSuccessNotice      => _t('withdrawSuccessNotice');
  String get withdrawTimeline1Title     => _t('withdrawTimeline1Title');
  String get withdrawTimeline1Sub       => _t('withdrawTimeline1Sub');
  String get withdrawTimeline2Title     => _t('withdrawTimeline2Title');
  String get withdrawTimeline2Sub       => _t('withdrawTimeline2Sub');
  String get withdrawTimeline3Title     => _t('withdrawTimeline3Title');
  String get withdrawTimeline3Sub       => _t('withdrawTimeline3Sub');
  String get withdrawDeclarationText    => _t('withdrawDeclarationText');
  String get withdrawDeclarationSection => _t('withdrawDeclarationSection');
  String get withdrawDeclarationSuffix  => _t('withdrawDeclarationSuffix');
  String get withdrawExistingCert       => _t('withdrawExistingCert');
  String get withdrawCertUploadBtn      => _t('withdrawCertUploadBtn');
  String get withdrawCertReplace        => _t('withdrawCertReplace');
  String get withdrawCertHint           => _t('withdrawCertHint');
  String get withdrawIndividualTitle    => _t('withdrawIndividualTitle');
  String get withdrawIndividualDesc     => _t('withdrawIndividualDesc');
  String get withdrawBankTransferPending => _t('withdrawBankTransferPending');
  String get withdrawBusinessFormTitle  => _t('withdrawBusinessFormTitle');
  String get withdrawIndividualFormTitle => _t('withdrawIndividualFormTitle');

  // ── Onboarding screen ────────────────────────────────────────────────────────
  String onboardingStep(int step, int total) => _tp('onboardingStep', {'step': '$step', 'total': '$total'});
  String get onboardingWelcome           => _t('onboardingWelcome');
  String get onboardingWelcomeSub        => _t('onboardingWelcomeSub');
  String get onboardingRoleCustomerTitle => _t('onboardingRoleCustomerTitle');
  String get onboardingRoleCustomerSub   => _t('onboardingRoleCustomerSub');
  String get onboardingRoleProviderTitle => _t('onboardingRoleProviderTitle');
  String get onboardingRoleProviderSub   => _t('onboardingRoleProviderSub');
  String get onboardingBothRoles         => _t('onboardingBothRoles');
  String get onboardingServiceTitle      => _t('onboardingServiceTitle');
  String get onboardingServiceSub        => _t('onboardingServiceSub');
  String get onboardingCategory          => _t('onboardingCategory');
  String get onboardingCategoryHint      => _t('onboardingCategoryHint');
  String get onboardingPriceLabel        => _t('onboardingPriceLabel');
  String get onboardingPriceHint         => _t('onboardingPriceHint');
  String get onboardingPriceTip          => _t('onboardingPriceTip');
  String get onboardingProfileTitle      => _t('onboardingProfileTitle');
  String get onboardingProfileSub        => _t('onboardingProfileSub');
  String get onboardingAddPhoto          => _t('onboardingAddPhoto');
  String get onboardingBioLabel          => _t('onboardingBioLabel');
  String get onboardingBioHint           => _t('onboardingBioHint');
  String get onboardingSkipFinish        => _t('onboardingSkipFinish');
  String get onboardingNext              => _t('onboardingNext');
  String get onboardingStart             => _t('onboardingStart');
  String onboardingError(String error)   => _tp('onboardingError', {'error': error});
  String onboardingUploadError(String e) => _tp('onboardingUploadError', {'error': e});

  // ── Onboarding — Tax Compliance ──────────────────────────────────────────────
  String get onboardingTaxTitle          => _t('onboardingTaxTitle');
  String get onboardingTaxSubtitle       => _t('onboardingTaxSubtitle');
  String get onboardingTaxNotice         => _t('onboardingTaxNotice');
  String get onboardingTaxStatusLabel    => _t('onboardingTaxStatusLabel');
  String get onboardingTaxStatusRequired => _t('onboardingTaxStatusRequired');
  String get onboardingDocRequired       => _t('onboardingDocRequired');
  String get onboardingTaxBusiness       => _t('onboardingTaxBusiness');
  String get onboardingTaxBusinessSub    => _t('onboardingTaxBusinessSub');
  String get onboardingTaxIndividual     => _t('onboardingTaxIndividual');
  String get onboardingTaxIndividualSub  => _t('onboardingTaxIndividualSub');
  String get onboardingDocLabelBusiness  => _t('onboardingDocLabelBusiness');
  String get onboardingDocLabelIndividual=> _t('onboardingDocLabelIndividual');
  String get onboardingDocHintBusiness   => _t('onboardingDocHintBusiness');
  String get onboardingDocHintIndividual => _t('onboardingDocHintIndividual');
  String get onboardingDocUploadPrompt   => _t('onboardingDocUploadPrompt');
  String get onboardingDocUploadSub      => _t('onboardingDocUploadSub');
  String get onboardingUploading         => _t('onboardingUploading');
  String get onboardingDocUploaded       => _t('onboardingDocUploaded');
  String get onboardingDocReplace        => _t('onboardingDocReplace');

  // ── Opportunities lock screen ────────────────────────────────────────────────
  String get oppUnderReviewTitle         => _t('oppUnderReviewTitle');
  String get oppUnderReviewSubtitle      => _t('oppUnderReviewSubtitle');
  String get oppUnderReviewBody          => _t('oppUnderReviewBody');
  String get oppUnderReviewStep1         => _t('oppUnderReviewStep1');
  String get oppUnderReviewStep2         => _t('oppUnderReviewStep2');
  String get oppUnderReviewStep3         => _t('oppUnderReviewStep3');
  String get oppUnderReviewContact       => _t('oppUnderReviewContact');

  // ── Admin — Compliance ───────────────────────────────────────────────────────
  String get adminVerifyProvider         => _t('adminVerifyProvider');
  String get adminUnverifyProvider       => _t('adminUnverifyProvider');
  String adminVerifiedSuccess(String name)   => _tp('adminVerifiedSuccess', {'name': name});
  String adminUnverifiedSuccess(String name) => _tp('adminUnverifiedSuccess', {'name': name});
  String get adminViewDoc                => _t('adminViewDoc');
  String get adminComplianceSection      => _t('adminComplianceSection');
  String get adminComplianceTaxStatus    => _t('adminComplianceTaxStatus');
  String get adminCompliancePending      => _t('adminCompliancePending');
  String get adminComplianceApproved     => _t('adminComplianceApproved');

  // ── Help Center screen ───────────────────────────────────────────────────────
  String get helpCenterProviderSupport   => _t('helpCenterProviderSupport');
  String get helpCenterCustomerSupport   => _t('helpCenterCustomerSupport');
  String get helpCenterProviderWelcome   => _t('helpCenterProviderWelcome');
  String get helpCenterCustomerWelcome   => _t('helpCenterCustomerWelcome');
  String get helpCenterProviderFaq       => _t('helpCenterProviderFaq');
  String get helpCenterCustomerFaq       => _t('helpCenterCustomerFaq');
  String get helpCenterInputHint         => _t('helpCenterInputHint');
  String get helpCenterTitle             => _t('helpCenterTitle');

  // ── Dispute Resolution ────────────────────────────────────────────────────────
  String get disputeOpenDisputes         => _t('disputeOpenDisputes');
  String get disputeLockedEscrow         => _t('disputeLockedEscrow');
  String get disputeTapForDetails        => _t('disputeTapForDetails');
  String get disputePartyCustomer        => _t('disputePartyCustomer');
  String get disputePartyProvider        => _t('disputePartyProvider');
  String get disputeArbitrationCenter    => _t('disputeArbitrationCenter');
  String get disputeIdPrefix             => _t('disputeIdPrefix');
  String get disputeLockedSuffix         => _t('disputeLockedSuffix');
  String get disputePartiesSection       => _t('disputePartiesSection');
  String get disputeReasonSection        => _t('disputeReasonSection');
  String get disputeNoReason             => _t('disputeNoReason');
  String get disputeChatHistory          => _t('disputeChatHistory');
  String get disputeAdminNote            => _t('disputeAdminNote');
  String get disputeAdminNoteHint        => _t('disputeAdminNoteHint');
  String disputeExistingNote(String note)  => _tp('disputeExistingNote', {'note': note});
  String get disputeActionsSection       => _t('disputeActionsSection');
  String get disputeResolving            => _t('disputeResolving');
  String get disputeRefundLabel          => _t('disputeRefundLabel');
  String disputeRefundSublabel(String amount) => _tp('disputeRefundSublabel', {'amount': amount});
  String get disputeReleaseLabel         => _t('disputeReleaseLabel');
  String disputeReleaseSublabel(String amount) => _tp('disputeReleaseSublabel', {'amount': amount});
  String get disputeSplitLabel           => _t('disputeSplitLabel');
  String disputeSplitSublabel(String amount) => _tp('disputeSplitSublabel', {'amount': amount});
  String get disputeConfirmRefund        => _t('disputeConfirmRefund');
  String get disputeConfirmRelease       => _t('disputeConfirmRelease');
  String get disputeConfirmSplit         => _t('disputeConfirmSplit');
  String disputeRefundBody(String amount, String name) => _tp('disputeRefundBody', {'amount': amount, 'name': name});
  String disputeReleaseBody(String amount, String name, String fee) => _tp('disputeReleaseBody', {'amount': amount, 'name': name, 'fee': fee});
  String disputeSplitBody(String half, String halfNet, String platform) => _tp('disputeSplitBody', {'half': half, 'halfNet': halfNet, 'platform': platform});
  String get disputeIrreversible         => _t('disputeIrreversible');
  String get disputeResolvedRefund       => _t('disputeResolvedRefund');
  String get disputeResolvedRelease      => _t('disputeResolvedRelease');
  String get disputeResolvedSplit        => _t('disputeResolvedSplit');
  String disputeErrorPrefix(String error)  => _tp('disputeErrorPrefix', {'error': error});
  String get disputeNoChatId             => _t('disputeNoChatId');
  String get disputeNoMessages           => _t('disputeNoMessages');
  String get disputeSystemSender         => _t('disputeSystemSender');
  String get disputeTypeImage            => _t('disputeTypeImage');
  String get disputeTypeLocation         => _t('disputeTypeLocation');
  String get disputeTypeAudio            => _t('disputeTypeAudio');
  String disputeOpenedAt(String date)    => _tp('disputeOpenedAt', {'date': date});
  String get disputeEmptyTitle           => _t('disputeEmptyTitle');
  String get disputeEmptySubtitle        => _t('disputeEmptySubtitle');

  // ── My Calendar ───────────────────────────────────────────────────────────────
  String get calendarTitle               => _t('calendarTitle');
  String get calendarRefresh             => _t('calendarRefresh');
  String get calendarNoEvents            => _t('calendarNoEvents');
  String get calendarStatusPending       => _t('calendarStatusPending');
  String get calendarStatusWaiting       => _t('calendarStatusWaiting');
  String get calendarStatusCompleted     => _t('calendarStatusCompleted');

  // ── My Requests ───────────────────────────────────────────────────────────────
  String get requestsTitle               => _t('requestsTitle');
  String get requestsEmpty               => _t('requestsEmpty');
  String get requestsEmptySubtitle       => _t('requestsEmptySubtitle');
  String requestsInterested(int count)   => _tp('requestsInterested', {'count': count.toString()});
  String get requestsWaiting             => _t('requestsWaiting');
  String get requestsWaitingProviders    => _t('requestsWaitingProviders');
  String get requestsClosed              => _t('requestsClosed');
  String requestsViewInterested(int count) => _tp('requestsViewInterested', {'count': count.toString()});
  String get requestsInterestedTitle     => _t('requestsInterestedTitle');
  String get requestsNoInterested        => _t('requestsNoInterested');
  String get requestsJustNow             => _t('requestsJustNow');
  String requestsMinutesAgo(int minutes) => _tp('requestsMinutesAgo', {'minutes': minutes.toString()});
  String requestsHoursAgo(int hours)     => _tp('requestsHoursAgo', {'hours': hours.toString()});
  String requestsDaysAgo(int days)       => _tp('requestsDaysAgo', {'days': days.toString()});
  String get requestsDefaultExpert       => _t('requestsDefaultExpert');
  String requestsHiredAgo(String ago)    => _tp('requestsHiredAgo', {'ago': ago});
  String requestsOrderCount(int count)   => _tp('requestsOrderCount', {'count': count.toString()});
  String get requestsTopMatch            => _t('requestsTopMatch');
  String get requestsMatchLabel          => _t('requestsMatchLabel');
  String get requestsChatNow             => _t('requestsChatNow');
  String get requestsConfirmPay          => _t('requestsConfirmPay');
  String get requestsMoneyProtected      => _t('requestsMoneyProtected');
  String get requestsEscrowTooltip       => _t('requestsEscrowTooltip');
  String get requestsVerifiedBadge       => _t('requestsVerifiedBadge');
  String requestsPricePerHour(String price) => _tp('requestsPricePerHour', {'price': price});
  String get requestsBestValue           => _t('requestsBestValue');
  String get requestsFastResponse        => _t('requestsFastResponse');

  // ── XP Manager ───────────────────────────────────────────────────────────────
  String get xpManagerTitle              => _t('xpManagerTitle');
  String get xpManagerSubtitle           => _t('xpManagerSubtitle');
  String get xpEventsSection             => _t('xpEventsSection');
  String xpEventsCount(int count)        => _tp('xpEventsCount', {'count': count.toString()});
  String get xpEventsEmpty               => _t('xpEventsEmpty');
  String get xpAddEventButton            => _t('xpAddEventButton');
  String get xpEditEventTitle            => _t('xpEditEventTitle');
  String get xpAddEventTitle             => _t('xpAddEventTitle');
  String get xpFieldId                   => _t('xpFieldId');
  String get xpFieldIdHint               => _t('xpFieldIdHint');
  String get xpFieldName                 => _t('xpFieldName');
  String get xpFieldPoints               => _t('xpFieldPoints');
  String get xpFieldDesc                 => _t('xpFieldDesc');
  String get xpEventUpdated              => _t('xpEventUpdated');
  String get xpEventAdded                => _t('xpEventAdded');
  String get xpEventDeleted              => _t('xpEventDeleted');
  String get xpDeleteEventTitle          => _t('xpDeleteEventTitle');
  String xpDeleteEventConfirm(String name) => _tp('xpDeleteEventConfirm', {'name': name});
  String get xpReservedId                => _t('xpReservedId');
  String get xpTooltipEdit               => _t('xpTooltipEdit');
  String get xpTooltipDelete             => _t('xpTooltipDelete');
  String get xpLevelsTitle               => _t('xpLevelsTitle');
  String get xpLevelsSubtitle            => _t('xpLevelsSubtitle');
  String get xpSaveLevels                => _t('xpSaveLevels');
  String get xpLevelsSaved               => _t('xpLevelsSaved');
  String get xpLevelsError               => _t('xpLevelsError');
  String get xpLevelBronze               => _t('xpLevelBronze');
  String get xpLevelSilver               => _t('xpLevelSilver');
  String get xpLevelGold                 => _t('xpLevelGold');
  String get xpSaveAction                => _t('xpSaveAction');
  String get xpAddAction                 => _t('xpAddAction');
  String xpErrorPrefix(String error)     => _tp('xpErrorPrefix', {'error': error});

  // ── System Wallet ─────────────────────────────────────────────────────────────
  String get systemWalletTitle           => _t('systemWalletTitle');
  String get systemWalletBalance         => _t('systemWalletBalance');
  String get systemWalletPendingFees     => _t('systemWalletPendingFees');
  String systemWalletActiveJobs(int count) => _tp('systemWalletActiveJobs', {'count': count.toString()});
  String get systemWalletFeePanel        => _t('systemWalletFeePanel');
  String get systemWalletUpdateFee       => _t('systemWalletUpdateFee');
  String systemWalletFeeUpdated(String value) => _tp('systemWalletFeeUpdated', {'value': value});
  String get systemWalletEnterNumber     => _t('systemWalletEnterNumber');
  String get systemWalletInvalidNumber   => _t('systemWalletInvalidNumber');
  String get systemWalletEarningsTitle   => _t('systemWalletEarningsTitle');
  String get systemWalletExportCsv       => _t('systemWalletExportCsv');
  String systemWalletExported(int count) => _tp('systemWalletExported', {'count': count.toString()});
  String systemWalletExportError(String error) => _tp('systemWalletExportError', {'error': error});
  String get systemWalletNoEarnings      => _t('systemWalletNoEarnings');
  String get systemWalletTxStatus        => _t('systemWalletTxStatus');

  // ── Pending Categories ────────────────────────────────────────────────────────
  String get pendingCatsTitle            => _t('pendingCatsTitle');
  String get pendingCatsSectionPending   => _t('pendingCatsSectionPending');
  String get pendingCatsSectionReviewed  => _t('pendingCatsSectionReviewed');
  String get pendingCatsApproved         => _t('pendingCatsApproved');
  String get pendingCatsRejected         => _t('pendingCatsRejected');
  String pendingCatsErrorPrefix(String error) => _tp('pendingCatsErrorPrefix', {'error': error});
  String pendingCatsSubCategory(String name)  => _tp('pendingCatsSubCategory', {'name': name});
  String get pendingCatsProviderDesc     => _t('pendingCatsProviderDesc');
  String get pendingCatsAiReason         => _t('pendingCatsAiReason');
  String get pendingCatsImagePrompt      => _t('pendingCatsImagePrompt');
  String get pendingCatsReject           => _t('pendingCatsReject');
  String get pendingCatsApprove          => _t('pendingCatsApprove');
  String get pendingCatsStatusApproved   => _t('pendingCatsStatusApproved');
  String get pendingCatsStatusRejected   => _t('pendingCatsStatusRejected');
  String get pendingCatsEmptyTitle       => _t('pendingCatsEmptyTitle');
  String get pendingCatsEmptySubtitle    => _t('pendingCatsEmptySubtitle');
  String pendingCatsOpenedAt(String date) => _tp('pendingCatsOpenedAt', {'date': date});

  // ── Greeting helper ───────────────────────────────────────────────────────────
  String greetingForHour(int hour) {
    if (hour < 12) return greetingMorning;
    if (hour < 17) return greetingAfternoon;
    if (hour < 21) return greetingEvening;
    return greetingNight;
  }

  // ── Auth error mapper ─────────────────────────────────────────────────────────
  String authError(String code) {
    switch (code) {
      case 'user-not-found':         return errorUserNotFound;
      case 'wrong-password':         return errorWrongPassword;
      case 'invalid-credential':     return errorInvalidCredential;
      case 'invalid-email':          return errorInvalidEmail;
      case 'user-disabled':          return errorUserDisabled;
      case 'too-many-requests':      return errorTooManyRequests;
      case 'network-request-failed': return errorNetworkFailed;
      default:                       return errorGenericLogin;
    }
  }

  // ── RTL detection ─────────────────────────────────────────────────────────────
  static bool isRtl(Locale locale) => locale.languageCode == 'he';
  bool get isCurrentRtl => isRtl(locale);

  // ── Flutter localization delegates ───────────────────────────────────────────
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = [
    _AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static const List<Locale> supportedLocales = [_he, _en, _es];
}

// ── Delegate ──────────────────────────────────────────────────────────────────

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['he', 'en', 'es'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
