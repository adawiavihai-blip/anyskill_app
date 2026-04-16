// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'AnySkill';

  @override
  String get appSlogan => 'محترفوك، بلمسة واحدة';

  @override
  String get greetingMorning => 'صباح الخير';

  @override
  String get greetingAfternoon => 'مساء الخير';

  @override
  String get greetingEvening => 'مساء الخير';

  @override
  String get greetingNight => 'ليلة سعيدة';

  @override
  String get greetingSubMorning => 'ماذا تريد أن تفعل اليوم؟';

  @override
  String get greetingSubAfternoon => 'هل تحتاج مساعدة بشيء؟';

  @override
  String get greetingSubEvening => 'هل لا تزال تبحث عن خدمة؟';

  @override
  String get greetingSubNight => 'نراك غداً!';

  @override
  String get tabHome => 'الرئيسية';

  @override
  String get tabBookings => 'الحجوزات';

  @override
  String get tabChat => 'الرسائل';

  @override
  String get tabWallet => 'المحفظة';

  @override
  String get bookNow => 'احجز الآن';

  @override
  String get bookingCompleted => 'تم إكمال الحجز بنجاح';

  @override
  String get close => 'إغلاق';

  @override
  String get retryButton => 'إعادة المحاولة';

  @override
  String get saveChanges => 'حفظ التغييرات';

  @override
  String get saveSuccess => 'تم الحفظ بنجاح';

  @override
  String saveError(String error) {
    return 'خطأ في الحفظ: $error';
  }

  @override
  String get defaultUserName => 'مستخدم';

  @override
  String get notLoggedIn => 'غير مسجّل الدخول';

  @override
  String get linkCopied => 'تم نسخ الرابط';

  @override
  String get errorEmptyFields => 'يرجى ملء جميع الحقول';

  @override
  String get errorGeneric => 'حدث خطأ. حاول مجدداً';

  @override
  String get errorInvalidEmail => 'عنوان بريد إلكتروني غير صالح';

  @override
  String get whatsappError => 'تعذّر فتح واتساب';

  @override
  String get markAllReadTooltip => 'تحديد الكل كمقروء';

  @override
  String get onlineStatus => 'متاح';

  @override
  String get offlineStatus => 'غير متاح';

  @override
  String get onlineToggleOn => 'أنت متاح الآن';

  @override
  String get onlineToggleOff => 'أنت غير متاح الآن';

  @override
  String get roleCustomer => 'عميل';

  @override
  String get roleProvider => 'مقدّم خدمة';

  @override
  String get loginAccountTitle => 'دخول الحساب';

  @override
  String get loginButton => 'دخول';

  @override
  String get loginEmail => 'البريد الإلكتروني';

  @override
  String get loginForgotPassword => 'نسيت كلمة المرور؟';

  @override
  String get loginNoAccount => 'ليس لديك حساب؟ ';

  @override
  String get loginPassword => 'كلمة المرور';

  @override
  String get loginRememberMe => 'تذكرني';

  @override
  String get loginSignUpFree => 'سجل مجاناً';

  @override
  String get loginStats10k => '10K+';

  @override
  String get loginStats50 => '50+';

  @override
  String get loginStats49 => '4.9★';

  @override
  String get loginWelcomeBack => 'مرحباً بعودتك!';

  @override
  String get signupAccountCreated => 'تم إنشاء الحساب بنجاح!';

  @override
  String get signupEmailInUse => 'البريد الإلكتروني مستخدم بالفعل';

  @override
  String get signupGenericError => 'حدث خطأ أثناء التسجيل';

  @override
  String get signupGoogleError => 'خطأ في تسجيل الدخول عبر Google';

  @override
  String get signupNetworkError => 'خطأ في الشبكة. تحقق من الاتصال';

  @override
  String get signupNewCustomerBio => 'عميل جديد في AnySkill';

  @override
  String get signupNewProviderBio => 'مقدّم خدمة جديد في AnySkill';

  @override
  String get signupTosMustAgree => 'يجب الموافقة على شروط الاستخدام';

  @override
  String get signupWeakPassword => 'كلمة المرور ضعيفة جداً';

  @override
  String get forgotPasswordEmail => 'البريد الإلكتروني';

  @override
  String get forgotPasswordError => 'خطأ في إرسال رابط الاستعادة';

  @override
  String get forgotPasswordSubmit => 'إرسال رابط الاستعادة';

  @override
  String get forgotPasswordSubtitle => 'أدخل بريدك الإلكتروني وسنرسل لك رابطاً لاستعادة كلمة المرور';

  @override
  String get forgotPasswordSuccess => 'تم إرسال رابط الاستعادة إلى بريدك';

  @override
  String get forgotPasswordTitle => 'نسيت كلمة المرور';

  @override
  String authError(String code) {
    return 'خطأ في المصادقة: $code';
  }

  @override
  String get profileTitle => 'ملفي الشخصي';

  @override
  String get profileFieldName => 'الاسم الكامل';

  @override
  String get profileFieldNameHint => 'أدخل اسمك الكامل';

  @override
  String get profileFieldRole => 'نوع المستخدم';

  @override
  String get profileFieldCategoryMain => 'المجال الرئيسي';

  @override
  String get profileFieldCategoryMainHint => 'اختر مجالك الرئيسي';

  @override
  String get profileFieldCategorySub => 'الفئة الفرعية';

  @override
  String get profileFieldCategorySubHint => 'اختر تخصصاً محدداً';

  @override
  String get profileFieldPrice => 'السعر بالساعة (₪)';

  @override
  String get profileFieldPriceHint => 'أدخل سعرك بالساعة';

  @override
  String get profileFieldResponseTime => 'وقت الاستجابة (دقائق)';

  @override
  String get profileFieldResponseTimeHint => 'متوسط وقت الاستجابة';

  @override
  String get profileFieldTaxId => 'رقم الترخيص التجاري';

  @override
  String get profileFieldTaxIdHint => 'أدخل رقم الترخيص التجاري';

  @override
  String get profileFieldTaxIdHelp => 'سيُستخدم هذا الرقم لإصدار الفواتير';

  @override
  String get editProfileAbout => 'نبذة عني';

  @override
  String get editProfileAboutHint => 'أخبر العملاء عن خبرتك...';

  @override
  String get editProfileCancellationPolicy => 'سياسة الإلغاء';

  @override
  String get editProfileCancellationHint => 'اختر سياسة إلغاء';

  @override
  String get editProfileGallery => 'المعرض';

  @override
  String get editProfileQuickTags => 'وسوم سريعة';

  @override
  String get editProfileTagsHint => 'أضف وسوماً لملفك الشخصي';

  @override
  String editProfileTagsSelected(int count) {
    return '$count محددة';
  }

  @override
  String get editCategoryTitle => 'تعديل الفئة';

  @override
  String get editCategoryNameLabel => 'اسم الفئة';

  @override
  String get editCategoryChangePic => 'تغيير الصورة';

  @override
  String get shareProfileTitle => 'مشاركة الملف الشخصي';

  @override
  String get shareProfileTooltip => 'شارك ملفك الشخصي';

  @override
  String get shareProfileCopyLink => 'نسخ الرابط';

  @override
  String get shareProfileWhatsapp => 'مشاركة عبر واتساب';

  @override
  String get statBalance => 'الرصيد';

  @override
  String get searchHintExperts => 'ابحث عن محترفين...';

  @override
  String get searchDefaultTitle => 'البحث';

  @override
  String get searchDefaultCity => 'إسرائيل';

  @override
  String get searchDefaultExpert => 'محترف';

  @override
  String get searchSectionCategories => 'الفئات';

  @override
  String searchSectionResultsFor(String query) {
    return 'نتائج لـ \"$query\"';
  }

  @override
  String searchNoResultsFor(String query) {
    return 'لا توجد نتائج لـ \"$query\"';
  }

  @override
  String get searchNoCategoriesBody => 'لم يتم العثور على فئات';

  @override
  String get searchPerHour => '₪/ساعة';

  @override
  String get searchRecommendedBadge => 'موصى به';

  @override
  String get searchChipHomeVisit => 'زيارة منزلية';

  @override
  String get searchChipWeekend => 'متاح في عطلة نهاية الأسبوع';

  @override
  String get searchDatePickerHint => 'اختر تاريخاً';

  @override
  String get searchTourSearchTitle => 'البحث عن محترفين';

  @override
  String get searchTourSearchDesc => 'ابحث بالاسم أو الخدمة أو الفئة';

  @override
  String get searchTourSuggestionsTitle => 'اقتراحات ذكية';

  @override
  String get searchTourSuggestionsDesc => 'اقتراحات مخصصة بناءً على عمليات بحثك';

  @override
  String get searchUrgencyMorning => 'صباحاً';

  @override
  String get searchUrgencyAfternoon => 'ظهراً';

  @override
  String get searchUrgencyEvening => 'مساءً';

  @override
  String get catResultsSearchHint => 'ابحث داخل الفئة...';

  @override
  String catResultsNoExperts(String category) {
    return 'لا يوجد محترفون في $category';
  }

  @override
  String get catResultsNoResults => 'لا توجد نتائج';

  @override
  String get catResultsNoResultsHint => 'حاول تغيير بحثك';

  @override
  String get catResultsPerHour => '₪/ساعة';

  @override
  String catResultsOrderCount(int count) {
    return '$count طلبات';
  }

  @override
  String catResultsResponseTime(int minutes) {
    return 'يستجيب خلال $minutes دقيقة';
  }

  @override
  String get catResultsRecommended => 'موصى به';

  @override
  String get catResultsTopRated => 'الأعلى تقييماً';

  @override
  String get catResultsUnder100 => 'أقل من ₪100';

  @override
  String get catResultsClearFilters => 'مسح المرشحات';

  @override
  String get catResultsBeFirst => 'كن الأول!';

  @override
  String get catResultsExpertDefault => 'محترف';

  @override
  String get catResultsLoadMore => 'تحميل المزيد';

  @override
  String get catResultsAvailableSlots => 'مواعيد متاحة';

  @override
  String get catResultsNoAvailability => 'غير متاح';

  @override
  String get catResultsFullBooking => 'محجوز بالكامل';

  @override
  String get catResultsWhenFree => 'متى يكون متاحاً؟';

  @override
  String get chatListTitle => 'الرسائل';

  @override
  String get expertSectionAbout => 'حول';

  @override
  String get expertSectionService => 'الخدمة';

  @override
  String get expertSectionSchedule => 'التوفر';

  @override
  String get expertBioPlaceholder => 'لا توجد نبذة بعد';

  @override
  String get expertBioReadMore => 'اقرأ المزيد';

  @override
  String get expertBioShowLess => 'عرض أقل';

  @override
  String get expertNoReviews => 'لا توجد مراجعات بعد';

  @override
  String get expertDefaultReviewer => 'مستخدم';

  @override
  String get expertProviderResponse => 'رد مقدّم الخدمة';

  @override
  String get expertAddReply => 'أضف رداً';

  @override
  String get expertAddReplyTitle => 'أضف رداً على المراجعة';

  @override
  String get expertReplyHint => 'اكتب رداً...';

  @override
  String get expertPublishReply => 'نشر الرد';

  @override
  String get expertReplyError => 'خطأ في نشر الرد';

  @override
  String get expertSelectDateTime => 'اختر التاريخ والوقت';

  @override
  String get expertSelectTime => 'اختر الوقت';

  @override
  String expertBookForTime(String time) {
    return 'احجز لـ $time';
  }

  @override
  String expertStartingFrom(String price) {
    return 'ابتداءً من ₪$price';
  }

  @override
  String get expertBookingSummaryTitle => 'ملخص الحجز';

  @override
  String get expertSummaryRowService => 'الخدمة';

  @override
  String get expertSummaryRowDate => 'التاريخ';

  @override
  String get expertSummaryRowTime => 'الوقت';

  @override
  String get expertSummaryRowPrice => 'السعر';

  @override
  String get expertSummaryRowIncluded => 'يشمل';

  @override
  String get expertSummaryRowProtection => 'حماية المشتري';

  @override
  String get expertSummaryRowTotal => 'الإجمالي';

  @override
  String get expertConfirmPaymentButton => 'تأكيد والدفع';

  @override
  String get expertVerifiedBooking => 'حجز مؤكد';

  @override
  String get expertInsufficientBalance => 'رصيد غير كافٍ';

  @override
  String get expertEscrowSuccess => 'تم تأكيد الدفع وتأمينه حتى انتهاء المعاملة';

  @override
  String expertTransactionTitle(String name) {
    return 'دفع لـ $name';
  }

  @override
  String expertSystemMessage(String date, String time, String amount) {
    return 'تم تأكيد الحجز لـ $date الساعة $time. ₪$amount محفوظة في الضمان.';
  }

  @override
  String expertCancellationNotice(String policy, String deadline, String penalty) {
    return 'سياسة $policy: إلغاء مجاني حتى $deadline. بعد ذلك $penalty% غرامة.';
  }

  @override
  String expertCancellationNoDeadline(String policy, String description) {
    return 'سياسة $policy: $description';
  }

  @override
  String get financeTitle => 'المالية';

  @override
  String get financeAvailableBalance => 'الرصيد المتاح';

  @override
  String get financePending => 'قيد الانتظار';

  @override
  String get financeProcessing => 'قيد المعالجة';

  @override
  String get financeRecentActivity => 'النشاط الأخير';

  @override
  String get financeNoTransactions => 'لا توجد معاملات';

  @override
  String get financeWithdrawButton => 'سحب الأموال';

  @override
  String get financeMinWithdraw => 'الحد الأدنى للسحب: ₪50';

  @override
  String get financeTrustBadge => 'أموالك محمية';

  @override
  String financeReceivedFrom(String name) {
    return 'تم الاستلام من $name';
  }

  @override
  String financePaidTo(String name) {
    return 'تم الدفع لـ $name';
  }

  @override
  String financeError(String error) {
    return 'خطأ: $error';
  }

  @override
  String get disputeConfirmRefund => 'تأكيد الاسترداد';

  @override
  String get disputeConfirmRelease => 'تأكيد تحرير الدفع';

  @override
  String get disputeConfirmSplit => 'تأكيد التقسيم';

  @override
  String get disputePartyCustomer => 'العميل';

  @override
  String disputeRefundBody(String amount, String customerName) {
    return '₪$amount سيتم استردادها لـ $customerName';
  }

  @override
  String disputeReleaseBody(String netAmount, String expertName, String feePercent) {
    return '₪$netAmount سيتم تحريرها لـ $expertName (عمولة $feePercent%)';
  }

  @override
  String disputeSplitBody(String halfAmount, String halfNet, String platformFee) {
    return 'تقسيم: ₪$halfAmount لكل طرف. المقدّم يحصل على ₪$halfNet، المنصة ₪$platformFee';
  }

  @override
  String get disputeResolvedRefund => 'تم حل النزاع — تم الاسترداد';

  @override
  String get disputeResolvedRelease => 'تم حل النزاع — تم تحرير الدفع';

  @override
  String get disputeResolvedSplit => 'تم حل النزاع — تم تقسيم المبلغ';

  @override
  String get disputeTypeAudio => 'تسجيل صوتي';

  @override
  String get disputeTypeImage => 'صورة';

  @override
  String get disputeTypeLocation => 'موقع';

  @override
  String get releasePaymentError => 'خطأ في تحرير الدفع';

  @override
  String get oppTitle => 'الفرص';

  @override
  String get oppAllCategories => 'جميع الفئات';

  @override
  String get oppEmptyAll => 'لا توجد فرص حالياً';

  @override
  String get oppEmptyAllSubtitle => 'تحقق مجدداً لاحقاً';

  @override
  String get oppEmptyCategory => 'لا توجد فرص في هذه الفئة';

  @override
  String get oppEmptyCategorySubtitle => 'جرّب فئة أخرى';

  @override
  String get oppTakeOpportunity => 'اغتنم الفرصة';

  @override
  String get oppInterested => 'مهتم';

  @override
  String get oppAlreadyInterested => 'أبديت اهتمامك بالفعل';

  @override
  String get oppAlreadyExpressed => 'لقد أبديت اهتمامك بهذا الطلب بالفعل';

  @override
  String get oppAlready3Interested => 'يوجد بالفعل 3 مهتمين';

  @override
  String get oppInterestSuccess => 'تم تسجيل اهتمامك بنجاح!';

  @override
  String get oppRequestClosed3 => 'تم إغلاق الطلب — 3 مهتمين';

  @override
  String get oppRequestClosedBtn => 'الطلب مغلق';

  @override
  String get oppRequestUnavailable => 'الطلب لم يعد متاحاً';

  @override
  String get oppDefaultClient => 'عميل';

  @override
  String get oppHighDemand => 'طلب مرتفع';

  @override
  String get oppQuickBid => 'عرض سريع';

  @override
  String oppQuickBidMessage(String clientName, String providerName) {
    return 'مرحباً $clientName، أنا $providerName وأرغب بالمساعدة!';
  }

  @override
  String get oppEstimatedEarnings => 'الأرباح المقدّرة';

  @override
  String get oppAfterFee => 'بعد العمولة';

  @override
  String get oppWalletHint => 'الأرباح تذهب إلى محفظتك';

  @override
  String oppXpToNextLevel(int xpNeeded, String levelName) {
    return '$xpNeeded XP لمستوى $levelName';
  }

  @override
  String get oppMaxLevel => 'المستوى الأقصى!';

  @override
  String get oppBoostEarned => 'تم الحصول على تعزيز الملف الشخصي!';

  @override
  String oppBoostProgress(int count) {
    return '$count/3 فرص للتعزيز';
  }

  @override
  String oppProfileBoosted(String timeLabel) {
    return 'ملفك الشخصي معزّز! متبقي $timeLabel';
  }

  @override
  String oppError(String error) {
    return 'خطأ: $error';
  }

  @override
  String get oppTimeJustNow => 'الآن';

  @override
  String oppTimeMinAgo(int minutes) {
    return 'قبل $minutes دقيقة';
  }

  @override
  String oppTimeHourAgo(int hours) {
    return 'قبل $hours ساعات';
  }

  @override
  String oppTimeDayAgo(int days) {
    return 'قبل $days أيام';
  }

  @override
  String oppTimeHours(int hours) {
    return '$hours ساعات';
  }

  @override
  String oppTimeMinutes(int minutes) {
    return '$minutes دقائق';
  }

  @override
  String get oppUnderReviewTitle => 'ملفك الشخصي قيد المراجعة';

  @override
  String get oppUnderReviewSubtitle => 'فريق AnySkill يراجع ملفك الشخصي';

  @override
  String get oppUnderReviewBody => 'سنبلغك فور اكتمال التحقق';

  @override
  String get oppUnderReviewContact => 'تواصل مع الدعم';

  @override
  String get oppUnderReviewStep1 => 'تم إرسال الملف الشخصي';

  @override
  String get oppUnderReviewStep2 => 'قيد المراجعة';

  @override
  String get oppUnderReviewStep3 => 'الموافقة النهائية';

  @override
  String get requestsEmpty => 'لا توجد طلبات';

  @override
  String get requestsEmptySubtitle => 'لم يتم نشر طلبات بعد';

  @override
  String get requestsChatNow => 'إرسال رسالة';

  @override
  String get requestsClosed => 'مغلق';

  @override
  String get requestsConfirmPay => 'تأكيد والدفع';

  @override
  String get requestsDefaultExpert => 'محترف';

  @override
  String get requestsEscrowTooltip => 'الأموال محفوظة في الضمان حتى إتمام العمل';

  @override
  String get requestsMatchLabel => 'تطابق';

  @override
  String get requestsTopMatch => 'أفضل تطابق';

  @override
  String get requestsVerifiedBadge => 'موثّق';

  @override
  String get requestsMoneyProtected => 'أموالك محمية';

  @override
  String get requestsWaiting => 'بالانتظار';

  @override
  String get requestsWaitingProviders => 'بانتظار مقدّمي الخدمات...';

  @override
  String get requestsJustNow => 'الآن';

  @override
  String requestsMinutesAgo(int minutes) {
    return 'قبل $minutes دقيقة';
  }

  @override
  String requestsHoursAgo(int hours) {
    return 'قبل $hours ساعات';
  }

  @override
  String requestsDaysAgo(int days) {
    return 'قبل $days أيام';
  }

  @override
  String requestsInterested(int count) {
    return '$count مهتمين';
  }

  @override
  String requestsViewInterested(int count) {
    return 'عرض $count مهتمين';
  }

  @override
  String requestsOrderCount(int count) {
    return '$count طلبات';
  }

  @override
  String requestsHiredAgo(String label) {
    return 'تم التوظيف $label';
  }

  @override
  String requestsPricePerHour(String price) {
    return '₪$price/ساعة';
  }

  @override
  String get timeNow => 'الآن';

  @override
  String get timeOneHour => 'ساعة';

  @override
  String timeMinutesAgo(int minutes) {
    return 'قبل $minutes دقيقة';
  }

  @override
  String timeHoursAgo(int hours) {
    return 'قبل $hours ساعات';
  }

  @override
  String get urgentBannerRequests => 'طلبات عاجلة';

  @override
  String get urgentBannerPending => 'قيد الانتظار';

  @override
  String get urgentBannerServiceNeeded => 'خدمة مطلوبة';

  @override
  String get urgentBannerCustomerWaiting => 'عميل ينتظر';

  @override
  String get calendarTitle => 'التقويم';

  @override
  String get calendarRefresh => 'تحديث';

  @override
  String get calendarNoEvents => 'لا توجد أحداث';

  @override
  String get calendarStatusCompleted => 'مكتمل';

  @override
  String get calendarStatusPending => 'قيد الانتظار';

  @override
  String get calendarStatusWaiting => 'بالانتظار';

  @override
  String get creditsLabel => 'رصيد النقاط';

  @override
  String creditsDiscountAvailable(int discount) {
    return 'خصم $discount% متاح!';
  }

  @override
  String creditsToNextDiscount(int remaining) {
    return '$remaining نقطة للخصم التالي';
  }

  @override
  String get serviceFullSession => 'جلسة كاملة';

  @override
  String get serviceSingleLesson => 'درس واحد';

  @override
  String get serviceExtendedLesson => 'درس موسّع';

  @override
  String get validationNameRequired => 'الاسم مطلوب';

  @override
  String get validationNameLength => 'يجب أن يحتوي الاسم على حرفين على الأقل';

  @override
  String get validationNameTooLong => 'الاسم طويل جداً';

  @override
  String get validationNameForbidden => 'الاسم يحتوي على أحرف محظورة';

  @override
  String get validationCategoryRequired => 'يرجى اختيار فئة';

  @override
  String get validationRoleRequired => 'يرجى اختيار نوع المستخدم';

  @override
  String get validationPriceInvalid => 'سعر غير صالح';

  @override
  String get validationPricePositive => 'يجب أن يكون السعر إيجابياً';

  @override
  String get validationAboutTooLong => 'الوصف طويل جداً';

  @override
  String get validationAboutForbidden => 'الوصف يحتوي على أحرف محظورة';

  @override
  String get validationFieldForbidden => 'الحقل يحتوي على أحرف محظورة';

  @override
  String get validationUrlHttps => 'يجب أن يبدأ الرابط بـ https://';

  @override
  String get vipSheetHeader => 'AnySkill VIP';

  @override
  String get vipPriceMonthly => '₪99/شهر';

  @override
  String get vipActivateButton => 'تفعيل VIP';

  @override
  String get vipActivationSuccess => 'تم تفعيل VIP بنجاح!';

  @override
  String get vipInsufficientBalance => 'رصيد غير كافٍ لتفعيل VIP';

  @override
  String get vipInsufficientTooltip => 'اشحن محفظتك لتفعيل VIP';

  @override
  String get vipBenefit1 => 'أولوية في نتائج البحث';

  @override
  String get vipBenefit2 => 'شارة VIP على الملف الشخصي';

  @override
  String get vipBenefit3 => 'أولوية في الفرص';

  @override
  String get vipBenefit4 => 'دعم مميز';

  @override
  String withdrawMinBalance(int amount) {
    return 'الحد الأدنى للسحب هو $amount ₪';
  }

  @override
  String get withdrawAvailableBalance => 'الرصيد المتاح للسحب';

  @override
  String get withdrawBankSection => 'بيانات البنك';

  @override
  String get withdrawBankName => 'اسم البنك';

  @override
  String get withdrawBankBranch => 'الفرع';

  @override
  String get withdrawBankAccount => 'رقم الحساب';

  @override
  String get withdrawBankRequired => 'يجب إدخال اسم البنك';

  @override
  String get withdrawBranchRequired => 'يجب إدخال الفرع';

  @override
  String get withdrawAccountMinDigits => 'رقم الحساب يجب أن يحتوي على 5 أرقام على الأقل';

  @override
  String get withdrawBankEncryptedNotice => 'البيانات مشفرة وآمنة';

  @override
  String get withdrawEncryptedNotice => 'المعلومات مشفرة وآمنة';

  @override
  String get withdrawBankTransferPending => 'التحويل البنكي قيد المعالجة';

  @override
  String get withdrawCertSection => 'الشهادات';

  @override
  String get withdrawCertHint => 'ارفع شهادة الترخيص التجاري / الإعفاء';

  @override
  String get withdrawCertUploadBtn => 'رفع شهادة';

  @override
  String get withdrawCertReplace => 'استبدال الشهادة';

  @override
  String get withdrawDeclarationSection => 'الإقرار';

  @override
  String get withdrawDeclarationText => 'أُقرّ بمسؤوليتي الحصرية عن الإبلاغ الضريبي وفقاً للقانون';

  @override
  String get withdrawDeclarationSuffix => '(البند 6 في النظام)';

  @override
  String get withdrawTaxStatusTitle => 'نوع النشاط التجاري';

  @override
  String get withdrawTaxStatusSubtitle => 'اختر نوع نشاطك التجاري';

  @override
  String get withdrawTaxIndividual => 'معفى من الضرائب';

  @override
  String get withdrawTaxIndividualSub => 'معفى من تحصيل ضريبة القيمة المضافة';

  @override
  String get withdrawTaxIndividualBadge => 'معفى';

  @override
  String get withdrawTaxBusiness => 'مرخّص تجارياً';

  @override
  String get withdrawTaxBusinessSub => 'ملزم بتحصيل ضريبة القيمة المضافة';

  @override
  String get withdrawIndividualTitle => 'بيانات المعفى';

  @override
  String get withdrawIndividualDesc => 'أدخل بيانات الإعفاء الخاصة بك';

  @override
  String get withdrawIndividualFormTitle => 'نموذج المعفى';

  @override
  String get withdrawBusinessFormTitle => 'نموذج المرخّص تجارياً';

  @override
  String get withdrawNoCertError => 'يرجى رفع شهادة تجارية';

  @override
  String get withdrawNoDeclarationError => 'يرجى تأكيد الإقرار';

  @override
  String get withdrawSelectBankError => 'يرجى اختيار بنك';

  @override
  String withdrawSubmitButton(String amount) {
    return 'سحب $amount';
  }

  @override
  String get withdrawSubmitError => 'خطأ في إرسال الطلب';

  @override
  String get withdrawSuccessTitle => 'تم إرسال الطلب!';

  @override
  String withdrawSuccessSubtitle(String amount) {
    return 'طلب سحب بمبلغ $amount تم إرساله بنجاح';
  }

  @override
  String get withdrawSuccessNotice => 'التحويل البنكي سيتم خلال 3-5 أيام عمل';

  @override
  String get withdrawTimeline1Title => 'تم إرسال الطلب';

  @override
  String get withdrawTimeline1Sub => 'تم استلام الطلب في النظام';

  @override
  String get withdrawTimeline2Title => 'قيد المعالجة';

  @override
  String get withdrawTimeline2Sub => 'الفريق يعالج طلبك';

  @override
  String get withdrawTimeline3Title => 'مكتمل';

  @override
  String get withdrawTimeline3Sub => 'تم تحويل الأموال إلى حسابك';

  @override
  String get pendingCatsApproved => 'تمت الموافقة على الفئة';

  @override
  String get pendingCatsRejected => 'تم رفض الفئة';

  @override
  String get helpCenterTitle => 'مركز المساعدة';

  @override
  String get helpCenterTooltip => 'مساعدة';

  @override
  String get helpCenterCustomerWelcome => 'مرحباً بك في مركز المساعدة';

  @override
  String get helpCenterCustomerFaq => 'الأسئلة الشائعة للعملاء';

  @override
  String get helpCenterCustomerSupport => 'دعم العملاء';

  @override
  String get helpCenterProviderWelcome => 'مرحباً بك في مركز مساعدة مقدّمي الخدمات';

  @override
  String get helpCenterProviderFaq => 'الأسئلة الشائعة لمقدّمي الخدمات';

  @override
  String get helpCenterProviderSupport => 'دعم مقدّمي الخدمات';

  @override
  String get languageTitle => 'اللغة';

  @override
  String get languageSectionLabel => 'اختر اللغة';

  @override
  String get languageHe => 'עברית';

  @override
  String get languageEn => 'English';

  @override
  String get languageEs => 'Español';

  @override
  String get languageAr => 'العربية';

  @override
  String get systemWalletEnterNumber => 'أدخل رقماً صالحاً';

  @override
  String get updateBannerText => 'إصدار جديد متاح';

  @override
  String get updateNowButton => 'تحديث الآن';

  @override
  String get xpLevelBronze => 'مبتدئ';

  @override
  String get xpLevelSilver => 'محترف';

  @override
  String get xpLevelGold => 'ذهبي';

  @override
  String get bizAiTitle => 'الذكاء التجاري';

  @override
  String get bizAiSubtitle => 'تحليل وتوقعات مدعومة بالذكاء الاصطناعي';

  @override
  String get bizAiLoading => 'جارٍ تحميل البيانات...';

  @override
  String get bizAiRefreshData => 'تحديث البيانات';

  @override
  String get bizAiNoData => 'لا توجد بيانات متاحة';

  @override
  String bizAiError(String error) {
    return 'خطأ: $error';
  }

  @override
  String get bizAiSectionFinancial => 'المالية';

  @override
  String get bizAiSectionMarket => 'السوق';

  @override
  String get bizAiSectionAlerts => 'التنبيهات';

  @override
  String get bizAiSectionAiOps => 'عمليات الذكاء الاصطناعي';

  @override
  String get bizAiDailyCommission => 'العمولة اليومية';

  @override
  String get bizAiWeeklyProjection => 'التوقعات الأسبوعية';

  @override
  String get bizAiWeeklyForecast => 'التوقعات الأسبوعية';

  @override
  String get bizAiExpectedRevenue => 'الإيرادات المتوقعة';

  @override
  String get bizAiForecastBadge => 'توقعات';

  @override
  String get bizAiActualToDate => 'الفعلي حتى الآن';

  @override
  String get bizAiAccuracy => 'الدقة';

  @override
  String get bizAiModelAccuracy => 'دقة النموذج';

  @override
  String get bizAiModelAccuracyDetail => 'دقة توقع الإيرادات';

  @override
  String get bizAiNoChartData => 'لا توجد بيانات للرسم البياني';

  @override
  String get bizAiNoOrderData => 'لا توجد بيانات طلبات';

  @override
  String get bizAiSevenDays => '7 أيام';

  @override
  String get bizAiLast7Days => 'آخر 7 أيام';

  @override
  String get bizAiExecSummary => 'ملخص تنفيذي';

  @override
  String get bizAiActivityToday => 'نشاط اليوم';

  @override
  String get bizAiApprovalQueue => 'قائمة الموافقات';

  @override
  String bizAiPending(int count) {
    return '$count قيد الانتظار';
  }

  @override
  String get bizAiPendingLabel => 'قيد الانتظار';

  @override
  String get bizAiApproved => 'موافق عليه';

  @override
  String get bizAiRejected => 'مرفوض';

  @override
  String get bizAiApprovedTotal => 'إجمالي الموافقات';

  @override
  String get bizAiTapToReview => 'اضغط للمراجعة';

  @override
  String get bizAiCategoriesApproved => 'الفئات الموافق عليها';

  @override
  String get bizAiNewCategories => 'فئات جديدة';

  @override
  String get bizAiMarketOpportunities => 'فرص السوق';

  @override
  String get bizAiMarketOppsCard => 'فرص السوق';

  @override
  String get bizAiHighValueCategories => 'فئات عالية القيمة';

  @override
  String get bizAiHighValueHint => 'فئات ذات إمكانات إيرادات عالية';

  @override
  String bizAiProviders(int count) {
    return '$count مقدّمي خدمات';
  }

  @override
  String get bizAiPopularSearches => 'عمليات البحث الشائعة';

  @override
  String get bizAiNoSearchData => 'لا توجد بيانات بحث';

  @override
  String get bizAiNichesNoProviders => 'تخصصات بدون مقدّمي خدمات';

  @override
  String get bizAiNoOpportunities => 'لا توجد فرص حالياً';

  @override
  String bizAiRecruitForQuery(String query) {
    return 'تجنيد مقدّمي خدمات لـ \"$query\"';
  }

  @override
  String get bizAiZeroResultsHint => 'عمليات بحث بدون نتائج — فرصة للتجنيد';

  @override
  String bizAiSearches(int count) {
    return 'عمليات بحث: $count+';
  }

  @override
  String bizAiSearchCount(int count) {
    return '$count عملية بحث';
  }

  @override
  String get bizAiAlertHistory => 'سجل التنبيهات';

  @override
  String get bizAiAlertThreshold => 'حد التنبيه';

  @override
  String get bizAiAlertThresholdHint => 'الحد الأدنى لعمليات البحث للتنبيه';

  @override
  String get bizAiSaveThreshold => 'حفظ الحد';

  @override
  String get bizAiReset => 'إعادة تعيين';

  @override
  String get bizAiNoAlerts => 'لا توجد تنبيهات';

  @override
  String bizAiAlertCount(int count) {
    return '$count تنبيهات';
  }

  @override
  String bizAiMinutesAgo(int minutes) {
    return 'قبل $minutes دقيقة';
  }

  @override
  String bizAiHoursAgo(int hours) {
    return 'قبل $hours ساعات';
  }

  @override
  String bizAiDaysAgo(int days) {
    return 'قبل $days أيام';
  }

  @override
  String get tabProfile => 'الملف الشخصي';

  @override
  String get searchPlaceholder => 'ابحث عن محترف، خدمة...';

  @override
  String get searchTitle => 'بحث';

  @override
  String get discoverCategories => 'اكتشف الفئات';

  @override
  String get confirm => 'تأكيد';

  @override
  String get cancel => 'إلغاء';

  @override
  String get save => 'حفظ';

  @override
  String get submit => 'إرسال';

  @override
  String get next => 'التالي';

  @override
  String get back => 'رجوع';

  @override
  String get delete => 'حذف';

  @override
  String get currencySymbol => '₪';

  @override
  String get statusPaidEscrow => 'في انتظار الموافقة';

  @override
  String get statusExpertCompleted => 'مكتمل — في انتظار موافقتك';

  @override
  String get statusCompleted => 'مكتمل';

  @override
  String get statusCancelled => 'ملغي';

  @override
  String get statusDispute => 'في نزاع';

  @override
  String get statusPendingPayment => 'في انتظار الدفع';

  @override
  String get profileCustomer => 'عميل';

  @override
  String get profileProvider => 'مزود خدمة';

  @override
  String get profileOrders => 'الطلبات';

  @override
  String get profileRating => 'التقييم';

  @override
  String get profileReviews => 'المراجعات';

  @override
  String get reviewsPlaceholder => 'أخبرنا عن تجربتك...';

  @override
  String get reviewSubmit => 'إرسال مراجعة';

  @override
  String get ratingLabel => 'قيّم الخدمة';

  @override
  String get walletBalance => 'الرصيد';

  @override
  String get openChat => 'فتح المحادثة';

  @override
  String get quickRequest => 'طلب سريع';

  @override
  String get trendingBadge => 'رائج';

  @override
  String get isCurrentRtl => 'true';

  @override
  String get taxDeclarationText => 'أتحمل المسؤولية الكاملة عن الإبلاغ الضريبي وفقاً للقانون.';

  @override
  String get loginTitle => 'تسجيل الدخول';

  @override
  String get loginSubtitle => 'سجل الدخول إلى حسابك';

  @override
  String get errorGenericLogin => 'خطأ في تسجيل الدخول';

  @override
  String get subCategoryPrompt => 'اختر فئة فرعية';

  @override
  String get emptyActivityTitle => 'لا يوجد نشاط';

  @override
  String get emptyActivityCta => 'ابدأ الآن';

  @override
  String get errorNetworkTitle => 'خطأ في الشبكة';

  @override
  String get errorNetworkBody => 'تحقق من اتصالك بالإنترنت';

  @override
  String get errorProfileLoad => 'خطأ في تحميل الملف الشخصي';

  @override
  String get forgotPassword => 'نسيت كلمة المرور؟';

  @override
  String get signupButton => 'التسجيل';

  @override
  String get tosAgree => 'أوافق على شروط الخدمة';

  @override
  String get tosTitle => 'شروط الخدمة';

  @override
  String get tosVersion => 'الإصدار 1.0';

  @override
  String get urgentCustomerLabel => 'خدمة عاجلة';

  @override
  String get urgentProviderLabel => 'فرص عاجلة';

  @override
  String get urgentOpenButton => 'فتح';

  @override
  String get walletMinWithdraw => 'الحد الأدنى للسحب';

  @override
  String get withdrawalPending => 'سحب قيد المعالجة';

  @override
  String get withdrawFunds => 'سحب الأموال';

  @override
  String onboardingError(String error) {
    return 'خطأ: $error';
  }

  @override
  String onboardingUploadError(String error) {
    return 'خطأ في الرفع: $error';
  }

  @override
  String get onboardingWelcome => '!مرحباً';

  @override
  String get availabilityUpdated => 'تم تحديث التوفر';

  @override
  String get bizAiRecruitNow => 'جنّد الآن';

  @override
  String get chatEmptyState => 'لا توجد رسائل بعد';

  @override
  String get chatLastMessageDefault => 'لا توجد رسالة أخيرة';

  @override
  String get chatSearchHint => 'ابحث في المحادثات...';

  @override
  String get chatUserDefault => 'مستخدم';

  @override
  String get deleteChatConfirm => 'تأكيد';

  @override
  String get deleteChatContent => 'هل أنت متأكد من حذف هذه المحادثة؟';

  @override
  String get deleteChatSuccess => 'تم حذف المحادثة بنجاح';

  @override
  String get deleteChatTitle => 'حذف المحادثة';

  @override
  String get disputeActionsSection => 'إجراءات';

  @override
  String get disputeAdminNote => 'ملاحظة المسؤول';

  @override
  String get disputeAdminNoteHint => 'أضف ملاحظة (اختياري)';

  @override
  String get disputeArbitrationCenter => 'مركز التحكيم';

  @override
  String get disputeChatHistory => 'سجل المحادثة';

  @override
  String get disputeDescription => 'الوصف';

  @override
  String get disputeEmptySubtitle => 'لا توجد نزاعات مفتوحة حالياً';

  @override
  String get disputeEmptyTitle => 'لا توجد نزاعات';

  @override
  String get disputeHint => 'صف المشكلة بالتفصيل';

  @override
  String get disputeIdPrefix => 'نزاع #';

  @override
  String get disputeIrreversible => 'لا يمكن التراجع عن هذا الإجراء';

  @override
  String get disputeLockedEscrow => 'محجوز في الضمان';

  @override
  String get disputeLockedSuffix => '₪';

  @override
  String get disputeNoChatId => 'لا يوجد معرف محادثة';

  @override
  String get disputeNoMessages => 'لا توجد رسائل';

  @override
  String get disputeNoReason => 'لم يتم تقديم سبب';

  @override
  String get disputeOpenDisputes => 'النزاعات المفتوحة';

  @override
  String get disputePartiesSection => 'الأطراف';

  @override
  String get disputePartyProvider => 'مقدّم الخدمة';

  @override
  String get disputeReasonSection => 'سبب النزاع';

  @override
  String get disputeRefundLabel => 'استرداد';

  @override
  String get disputeReleaseLabel => 'تحرير الدفع';

  @override
  String get disputeResolving => 'جاري المعالجة...';

  @override
  String get disputeSplitLabel => 'تقسيم';

  @override
  String get disputeSystemSender => 'النظام';

  @override
  String get disputeTapForDetails => 'اضغط للتفاصيل';

  @override
  String get disputeTitle => 'نزاع';

  @override
  String get editProfileTitle => 'تعديل الملف الشخصي';

  @override
  String get helpCenterInputHint => 'اكتب سؤالك هنا...';

  @override
  String get logoutButton => 'تسجيل الخروج';

  @override
  String get markAllReadSuccess => 'تم تحديد جميع الإشعارات كمقروءة';

  @override
  String get markedDoneSuccess => 'تم التحديد كمنجز بنجاح';

  @override
  String get noCategoriesYet => 'لا توجد فئات بعد';

  @override
  String get notifClearAll => 'مسح الكل';

  @override
  String get notifEmptySubtitle => 'ليس لديك إشعارات جديدة';

  @override
  String get notifEmptyTitle => 'لا توجد إشعارات';

  @override
  String get notifOpen => 'فتح';

  @override
  String get notificationsTitle => 'الإشعارات';

  @override
  String get oppNotifTitle => 'اهتمام جديد';

  @override
  String get pendingCatsApprove => 'موافقة';

  @override
  String get pendingCatsEmptySubtitle => 'لا توجد طلبات فئات معلقة';

  @override
  String get pendingCatsEmptyTitle => 'لا توجد طلبات';

  @override
  String get pendingCatsImagePrompt => 'ارفع صورة للفئة';

  @override
  String get pendingCatsProviderDesc => 'وصف مقدّم الخدمة';

  @override
  String get pendingCatsReject => 'رفض';

  @override
  String get pendingCatsSectionPending => 'معلقة';

  @override
  String get pendingCatsSectionReviewed => 'تمت المراجعة';

  @override
  String get pendingCatsStatusApproved => 'تمت الموافقة';

  @override
  String get pendingCatsStatusRejected => 'مرفوض';

  @override
  String get pendingCatsTitle => 'طلبات الفئات';

  @override
  String get pendingCatsAiReason => 'سبب الذكاء الاصطناعي';

  @override
  String get profileLoadError => 'خطأ في تحميل الملف الشخصي';

  @override
  String get requestsBestValue => 'أفضل قيمة';

  @override
  String get requestsFastResponse => 'استجابة سريعة';

  @override
  String get requestsInterestedTitle => 'المهتمون';

  @override
  String get requestsNoInterested => 'لا يوجد مهتمون بعد';

  @override
  String get requestsTitle => 'الطلبات';

  @override
  String get submitDispute => 'إرسال النزاع';

  @override
  String get systemWalletFeePanel => 'رسوم المنصة';

  @override
  String get systemWalletInvalidNumber => 'رقم غير صالح';

  @override
  String get systemWalletUpdateFee => 'تحديث الرسوم';

  @override
  String get tosAcceptButton => 'أوافق';

  @override
  String get tosBindingNotice => 'بالضغط على تأكيد، أنت توافق على شروط الخدمة';

  @override
  String get tosFullTitle => 'شروط الخدمة الكاملة';

  @override
  String get tosLastUpdated => 'آخر تحديث';

  @override
  String get withdrawExistingCert => 'شهادة موجودة';

  @override
  String get withdrawUploadError => 'خطأ في رفع الملف';

  @override
  String get xpAddAction => 'إضافة';

  @override
  String get xpAddEventButton => 'إضافة حدث';

  @override
  String get xpAddEventTitle => 'إضافة حدث XP';

  @override
  String get xpDeleteEventTitle => 'حذف الحدث';

  @override
  String get xpEditEventTitle => 'تعديل حدث XP';

  @override
  String get xpEventAdded => 'تمت إضافة الحدث بنجاح';

  @override
  String get xpEventDeleted => 'تم حذف الحدث بنجاح';

  @override
  String get xpEventUpdated => 'تم تحديث الحدث بنجاح';

  @override
  String get xpEventsEmpty => 'لا توجد أحداث XP';

  @override
  String get xpEventsSection => 'أحداث XP';

  @override
  String get xpFieldDesc => 'الوصف';

  @override
  String get xpFieldId => 'المعرف';

  @override
  String get xpFieldIdHint => 'أدخل معرفاً فريداً';

  @override
  String get xpFieldName => 'الاسم';

  @override
  String get xpFieldPoints => 'النقاط';

  @override
  String get xpLevelsError => 'خطأ في حفظ المستويات';

  @override
  String get xpLevelsSaved => 'تم حفظ المستويات بنجاح';

  @override
  String get xpLevelsSubtitle => 'حدد عتبات XP لكل مستوى';

  @override
  String get xpLevelsTitle => 'مستويات XP';

  @override
  String get xpManagerSubtitle => 'إدارة أحداث ومستويات XP';

  @override
  String get xpManagerTitle => 'مدير XP';

  @override
  String get xpReservedId => 'معرف محجوز';

  @override
  String get xpSaveAction => 'حفظ';

  @override
  String get xpSaveLevels => 'حفظ المستويات';

  @override
  String get xpTooltipDelete => 'حذف';

  @override
  String get xpTooltipEdit => 'تعديل';

  @override
  String bizAiThresholdUpdated(int value) {
    return 'تم تحديث الحد إلى $value';
  }

  @override
  String disputeErrorPrefix(String error) {
    return 'خطأ: $error';
  }

  @override
  String disputeExistingNote(String note) {
    return 'ملاحظة المسؤول: $note';
  }

  @override
  String disputeOpenedAt(String date) {
    return 'تم الفتح في $date';
  }

  @override
  String disputeRefundSublabel(String amount) {
    return 'استرداد كامل — $amount ₪ للعميل';
  }

  @override
  String disputeReleaseSublabel(String amount) {
    return 'تحرير — $amount ₪ لمقدّم الخدمة';
  }

  @override
  String disputeSplitSublabel(String amount) {
    return 'تقسيم — $amount ₪ لكل طرف';
  }

  @override
  String editCategorySaveError(String error) {
    return 'خطأ في الحفظ: $error';
  }

  @override
  String oppInterestChatMessage(String providerName, String description) {
    return 'مرحباً، أنا $providerName وأحب أن أساعد: $description';
  }

  @override
  String oppNotifBody(String providerName) {
    return '$providerName مهتم بفرصتك';
  }

  @override
  String pendingCatsErrorPrefix(String error) {
    return 'خطأ: $error';
  }

  @override
  String pendingCatsSubCategory(String name) {
    return 'فئة فرعية: $name';
  }

  @override
  String xpDeleteEventConfirm(String name) {
    return 'حذف $name؟';
  }

  @override
  String xpErrorPrefix(String error) {
    return 'خطأ: $error';
  }

  @override
  String xpEventsCount(int count) {
    return '$count أحداث';
  }

  @override
  String get phoneLoginHeader => 'تسجيل الدخول / التسجيل';

  @override
  String get phoneLoginSubtitleSimple => 'أدخل رقم هاتفك وسنرسل رمز تحقق';

  @override
  String get phoneLoginSubtitleSocial => 'سجّل الدخول بـ Google أو Apple أو رقم الهاتف';

  @override
  String get phoneLoginOrDivider => 'أو';

  @override
  String get phoneLoginPhoneHint => 'رقم الهاتف';

  @override
  String get phoneLoginSendCode => 'إرسال رمز التحقق';

  @override
  String get phoneLoginHeroSubtitle => 'دخول سريع برقم هاتفك';

  @override
  String get phoneLoginChipSecure => 'آمن';

  @override
  String get phoneLoginChipFast => 'سريع';

  @override
  String get phoneLoginChipReliable => 'موثوق';

  @override
  String get phoneLoginSelectCountry => 'اختر الدولة';

  @override
  String get otpEnter6Digits => 'أدخل الأرقام الستة';

  @override
  String get otpVerifyError => 'خطأ في التحقق. حاول مرة أخرى.';

  @override
  String get otpErrorInvalidCode => 'رمز غير صحيح. حاول مرة أخرى.';

  @override
  String get otpErrorSessionExpired => 'انتهت صلاحية الرمز. اطلب رمزاً جديداً.';

  @override
  String get otpErrorTooManyRequests => 'محاولات كثيرة. حاول لاحقاً.';

  @override
  String otpErrorPrefix(String code) {
    return 'خطأ: $code';
  }

  @override
  String get otpTitle => 'أدخل رمز التحقق';

  @override
  String otpSubtitle(String phone) {
    return 'أرسلنا رمز SMS إلى $phone';
  }

  @override
  String get otpAutoFilled => 'تم التعبئة تلقائياً';

  @override
  String get otpResendIn => 'إعادة الإرسال خلال ';

  @override
  String get otpResendNow => 'إرسال رمز جديد';

  @override
  String get otpVerifyButton => 'تحقق وتابع';

  @override
  String get otpExistingAccountTitle => 'تم العثور على حساب موجود';

  @override
  String get otpExistingAccountBody => 'لهذا الرقم حساب موجود تم إنشاؤه بالبريد/كلمة مرور.\n\nربطه بتسجيل الدخول بالهاتف يتطلب إجراءً لمرة واحدة من المدير.\n\nيرجى التواصل مع الدعم وسنقوم بربط الحساب.';

  @override
  String get otpUnderstood => 'فهمت';

  @override
  String otpCreateProfileError(String error) {
    return 'خطأ في إنشاء الملف: $error';
  }

  @override
  String get otpWelcomeTitle => 'مرحباً بك في AnySkill! 👋';

  @override
  String get otpWelcomeSubtitle => 'اختر كيف تريد استخدام التطبيق';

  @override
  String get otpTermsPrefix => 'أؤكد أنني قرأت ووافقت على ';

  @override
  String get otpTermsOfService => 'شروط الخدمة';

  @override
  String get otpPrivacyPolicy => 'سياسة الخصوصية';

  @override
  String get otpRoleCustomer => 'عميل';

  @override
  String get otpRoleCustomerDesc => 'أبحث عن خدمات احترافية\nوأحجز مزودين';

  @override
  String get otpRoleProvider => 'مزود خدمة';

  @override
  String get otpRoleProviderDesc => 'أقدم خدمات احترافية\nوأكسب عبر AnySkill';

  @override
  String get otpRoleProviderBadge => 'بانتظار موافقة المدير';

  @override
  String get onbValEnterName => 'يرجى إدخال الاسم الكامل';

  @override
  String get onbValEnterPhone => 'يرجى إدخال رقم الهاتف';

  @override
  String get onbValEnterEmail => 'يرجى إدخال البريد الإلكتروني';

  @override
  String get onbValUploadProfile => 'يرجى رفع صورة الملف الشخصي';

  @override
  String get onbValChooseBusiness => 'يرجى اختيار نوع العمل';

  @override
  String get onbValEnterId => 'يرجى إدخال رقم الهوية / السجل التجاري';

  @override
  String get onbValUploadId => 'يرجى رفع صورة الهوية أو جواز السفر';

  @override
  String get onbValChooseCategory => 'يرجى اختيار فئة مهنية';

  @override
  String get onbValExpertise => 'يرجى وصف مجال خبرتك';

  @override
  String get onbValAcceptTerms => 'يرجى قراءة شروط الخدمة والموافقة عليها';

  @override
  String onbSaveError(String error) {
    return 'خطأ في الحفظ: $error';
  }

  @override
  String onbUploadError(String error) {
    return 'خطأ في الرفع: $error';
  }

  @override
  String onbCameraError(String error) {
    return 'خطأ في التصوير: $error';
  }

  @override
  String get onbToastProvider => 'أهلاً بك في فريق محترفي AnySkill! 🚀 مستنداتك قيد المراجعة. سنبلغك عند الموافقة.';

  @override
  String get onbToastCustomer => 'أهلاً بك في AnySkill! 🌟 تحتاج مساعدة؟ أنت في المكان الصحيح. آلاف المحترفين بانتظارك.';

  @override
  String get onbStepRole => 'اختر الدور';

  @override
  String get onbStepBusiness => 'بيانات العمل';

  @override
  String get onbStepService => 'مجال الخدمة';

  @override
  String get onbStepContact => 'معلومات الاتصال';

  @override
  String get onbStepProfile => 'ملفك الشخصي';

  @override
  String get onbProgressComplete => 'كل شيء جاهز!';

  @override
  String get onbProgressIncomplete => 'أكمل بياناتك';

  @override
  String onbGreeting(String name) {
    return 'مرحباً $name،';
  }

  @override
  String get onbGreetingFallback => 'مرحباً،';

  @override
  String get onbIntroLine => 'لحظة فقط. أخبرنا قليلاً عن نفسك.';

  @override
  String get onbSocialProof => 'أكثر من 250 محترفاً انضموا هذا الشهر';

  @override
  String get onbRoleCustomerTitle => 'أبحث عن خدمة';

  @override
  String get onbRoleCustomerSubtitle => 'أريد العثور على محترف';

  @override
  String get onbRoleProviderTitle => 'أريد تقديم خدمة';

  @override
  String get onbRoleProviderSubtitle => 'أود العمل عبر AnySkill';

  @override
  String get onbBusinessTypeHint => 'نوع العمل';

  @override
  String get onbUploadBusinessDocLabel => 'ارفع الرخصة التجارية';

  @override
  String get onbIdLabel => 'رقم الهوية / السجل التجاري';

  @override
  String get onbIdHint => 'أدخل الرقم';

  @override
  String get onbUploadIdLabel => 'ارفع صورة الهوية أو جواز السفر';

  @override
  String get onbSelfieTitle => 'سيلفي للتحقق من الهوية';

  @override
  String get onbSelfieSuccess => 'تم التقاط الصورة ✓';

  @override
  String get onbSelfiePrompt => 'التقط صورة مباشرة لوجهك';

  @override
  String get onbSelfieRetake => 'إعادة التقاط';

  @override
  String get onbSelfieTake => 'التقط سيلفي';

  @override
  String get onbCategoryOther => 'أخرى / لم أجد';

  @override
  String get onbCategoryHint => 'اختر الفئة الرئيسية';

  @override
  String get onbSubCategoryHint => 'اختر الفئة الفرعية';

  @override
  String get onbExpertiseLabel => 'صف مجال خبرتك';

  @override
  String get onbExpertiseHint => 'حتى 30 حرفاً';

  @override
  String get onbOtherCategoryNote => 'سيقوم فريق AnySkill بمراجعة البيانات وإسنادك للفئة المناسبة';

  @override
  String get onbFullNameLabel => 'الاسم الكامل *';

  @override
  String get onbFullNameHint => 'الاسم الذي سيظهر في الملف';

  @override
  String get onbPhoneLabel => 'رقم الهاتف *';

  @override
  String get onbEmailLabel => 'البريد الإلكتروني *';

  @override
  String get onbReplacePhoto => 'اضغط للاستبدال';

  @override
  String get onbAddPhoto => 'أضف صورة الملف';

  @override
  String get onbAboutLabel => 'أخبرنا عن نفسك';

  @override
  String get onbAboutHintProvider => 'الخبرة، المهارات، التخصصات...';

  @override
  String get onbAboutHintCustomer => 'ماذا تود أن نعرف عنك؟';

  @override
  String get onbTermsTitle => 'اقرأ شروط الخدمة وسياسة الخصوصية';

  @override
  String get onbTermsRead => 'مقروء';

  @override
  String get onbTermsAccept => 'أؤكد أنني قرأت ووافقت على شروط الخدمة وسياسة الخصوصية لـ AnySkill';

  @override
  String get onbFinish => 'إنهاء التسجيل';

  @override
  String get onbRequiredField => 'حقل مطلوب *';

  @override
  String get onbNotSpecified => 'غير محدد';

  @override
  String get onbUserTypeProvider => 'مزود خدمة';

  @override
  String get onbUserTypeCustomer => 'عميل';

  @override
  String get onbBizExempt => 'معفى من الضرائب';

  @override
  String get onbBizAuthorized => 'مسجل للضرائب';

  @override
  String get onbBizCompany => 'شركة محدودة';

  @override
  String get onbBizExternal => 'موظف، يصدر فواتير عبر شركة خارجية';

  @override
  String get profNoGooglePhoto => 'لم يتم العثور على صورة في حساب Google';

  @override
  String get profPhotoUpdatedFromGoogle => 'تم تحديث الصورة من Google';

  @override
  String get profInvoiceEmailOn => 'ستُرسل الفواتير إلى بريدك';

  @override
  String get profInvoiceEmailOff => 'لن تُرسل الفواتير إلى بريدك';

  @override
  String profSaveError(String error) {
    return 'خطأ في الحفظ: $error';
  }

  @override
  String get profInvoiceEmailTitle => 'استلام الفواتير بالبريد';

  @override
  String get profInvoiceEmailSubOn => 'ستستلم فاتورة بالبريد بعد كل معاملة';

  @override
  String get profInvoiceEmailSubOff => 'لن تستلم فواتير بالبريد';

  @override
  String get profSyncGooglePhoto => 'مزامنة الصورة من Google';

  @override
  String get profProviderRole => 'مزود خدمة';

  @override
  String get profJobsStat => 'الأعمال';

  @override
  String get profRatingStat => 'التقييم';

  @override
  String get profReviewsStat => 'المراجعات';

  @override
  String get profAngelBadge => 'ملاك المجتمع';

  @override
  String get profPillarBadge => 'ركيزة';

  @override
  String get profStarterBadge => 'متطوع نشط';

  @override
  String get profWorkGallery => 'معرض الأعمال';

  @override
  String get profVipActive => 'VIP فعال';

  @override
  String get profJoinVip => 'الانضمام إلى VIP';

  @override
  String get profVideoIntro => 'فيديو التعريف';

  @override
  String get profMyDogs => 'كلابي';

  @override
  String get profMyDogsSubtitle => 'ملف واحد → كل الحجوزات';

  @override
  String get profJoinAsProvider => 'الانضمام إلى AnySkill كمزود خدمة';

  @override
  String get profRequestInReview => 'طلبك قيد المراجعة — سنبلغك قريباً';

  @override
  String get profTermsOfService => 'شروط الخدمة';

  @override
  String get profPrivacyPolicy => 'سياسة الخصوصية';

  @override
  String get profSwitchRole => 'تبديل الدور';

  @override
  String get profLogout => 'تسجيل الخروج';

  @override
  String get profDeleteAccount => 'حذف الحساب';

  @override
  String get profTitle => 'الملف الشخصي';

  @override
  String get profCustomerRole => 'عميل';

  @override
  String get profStatServicesTaken => 'الخدمات التي استعنت بها';

  @override
  String get profStatReviews => 'المراجعات';

  @override
  String get profStatYears => 'سنوات في AnySkill';

  @override
  String get profReceivedService => 'خدمة مستلمة';

  @override
  String get profFavorites => 'المفضلة';

  @override
  String get profDeleteConfirmBody => 'هل أنت متأكد من حذف حسابك؟\n\nجميع البيانات — السجل، المحفظة، المحادثات — ستُحذف نهائياً.\n\nهذا الإجراء لا يمكن التراجع عنه.';

  @override
  String get profCancel => 'إلغاء';

  @override
  String get profContinue => 'متابعة';

  @override
  String get profFinalConfirm => 'تأكيد نهائي';

  @override
  String get profDeleteFinalBody => 'بعد التأكيد، سيتم حذف حسابك نهائياً ولا يمكن استعادته.';

  @override
  String get profDeletePermanent => 'حذف نهائي';

  @override
  String get profReauthNeeded => 'يلزم تسجيل دخول جديد';

  @override
  String get profReauthBody => 'لحذف الحساب، يتطلب Firebase تسجيل دخول حديث.\n\nيرجى تسجيل الخروج والدخول مجدداً ثم المحاولة.';

  @override
  String get profLogoutAndReauth => 'تسجيل خروج ودخول من جديد';

  @override
  String profDeleteError(String error) {
    return 'خطأ في حذف الحساب: $error';
  }

  @override
  String get profNoWorksYet => 'لم ترفع أعمالاً بعد.\nاضغط على القلم للتحديث!';

  @override
  String get homeTestEmailSent => 'تم إرسال بريد اختبار! تحقق من صندوق الوارد.';

  @override
  String homeGenericError(String error) {
    return 'خطأ: $error';
  }

  @override
  String get homeShowAll => 'عرض الكل';

  @override
  String get homeMicroTasks => 'مهام صغيرة — اكسب بسرعة';

  @override
  String get homeCommunityTitle => 'العطاء من القلب';

  @override
  String get homeCommunitySlogan => 'مهارة واحدة، قلب واحد';

  @override
  String get homeDefaultExpert => 'المحترف';

  @override
  String get homeDefaultReengageMsg => 'جاهز للحجز مجدداً؟';

  @override
  String get homeSmartOffer => 'عرض ذكي';

  @override
  String get homeBookNow => 'احجز الآن';

  @override
  String get homeWelcomeTitle => 'مرحباً بك في AnySkill';

  @override
  String get homeWelcomeSubtitle => 'اعثر على محترفين من حيّك';

  @override
  String get homeServiceTitle => 'خدمة احترافية بنقرة واحدة';

  @override
  String get homeServiceSubtitle => 'ترميم • تنظيف • تصوير والمزيد';

  @override
  String get homeBecomeExpertTitle => 'كن محترفاً اليوم';

  @override
  String get homeBecomeExpertSubtitle => 'انشر خدمتك وابدأ الكسب';

  @override
  String notifGenericError(String error) {
    return 'خطأ: $error';
  }

  @override
  String get notifDefaultClient => 'عميل';

  @override
  String get notifUrgentJobAvailable => 'وظيفة عاجلة متاحة!';

  @override
  String get notifJobTaken => 'تم أخذ الوظيفة';

  @override
  String get notifJobExpired => 'انتهت الوظيفة';

  @override
  String get notifGrabNow => 'خذها الآن!';

  @override
  String notifTakenBy(String name) {
    return 'أخذها $name';
  }

  @override
  String get notifCommunityHelpTitle => 'طلب مساعدة مجتمعية';

  @override
  String get notifNotNow => 'ليس الآن';

  @override
  String get notifWantToHelp => 'أريد المساعدة!';

  @override
  String get notifCantAccept => 'لا يمكن قبول هذا الطلب';

  @override
  String get notifAccepted => '✓ تم القبول! نفتح محادثة مع العميل';

  @override
  String get notifLoadError => 'خطأ في تحميل الإشعارات';

  @override
  String get notifEmptyNow => 'لا توجد إشعارات حالياً';

  @override
  String get chatUnknown => 'غير معروف';

  @override
  String get chatSafetyWarning => 'تنبيه: من أجل سلامتك، لا تتبادل أرقام الهواتف ولا تبرم صفقات خارج التطبيق.';

  @override
  String get chatNoInternet => 'لا يوجد اتصال بالإنترنت.';

  @override
  String get chatDefaultCustomer => 'عميل';

  @override
  String get chatPaymentRequest => 'طلب دفع';

  @override
  String get chatAmountLabel => 'المبلغ';

  @override
  String get chatServiceDescLabel => 'وصف الخدمة';

  @override
  String get chatSend => 'إرسال';

  @override
  String get chatQuoteSent => 'تم إرسال العرض بنجاح ✅';

  @override
  String get chatQuoteError => 'خطأ في إرسال العرض. حاول مرة أخرى.';

  @override
  String get chatOfficialQuote => 'عرض رسمي';

  @override
  String get chatQuoteDescHint => 'صف الخدمة المشمولة في السعر...';

  @override
  String get chatEscrowNote => 'سيُحجز المبلغ في ضمان AnySkill بعد موافقة العميل';

  @override
  String get chatSendQuote => 'إرسال العرض';

  @override
  String get chatQuoteLabel => 'عرض سعر';

  @override
  String get chatOnMyWay => 'أنا في الطريق! 🚗 سأصل قريباً.';

  @override
  String get chatWorkDone => 'تم إنجاز العمل! ✅';

  @override
  String get expCantBookSelf => 'لا يمكنك حجز خدمة من نفسك';

  @override
  String get expSlotTakenTitle => 'الموعد محجوز';

  @override
  String get expSlotTakenBody => 'قام شخص آخر بحجز الخبير لنفس الموعد.\nالرجاء اختيار تاريخ أو وقت آخر.';

  @override
  String get expUnderstood => 'فهمت';

  @override
  String get expBookingError => 'حدث خطأ في عملية الحجز، يرجى المحاولة مرة أخرى.';

  @override
  String get expDefaultCustomer => 'عميل';

  @override
  String expDemoBookingMsg(String name) {
    return 'قمت بحجز $name. سنبلغك عند توفر مزود الخدمة.';
  }

  @override
  String get expOptionalAddons => 'إضافات اختيارية';

  @override
  String get expProviderDayOff => 'المزود لا يعمل في هذا اليوم';

  @override
  String get expAnonymous => 'مجهول';

  @override
  String get expRatingProfessional => 'المهنية';

  @override
  String get expRatingTiming => 'الالتزام بالوقت';

  @override
  String get expRatingCommunication => 'التواصل';

  @override
  String get expSearchReviewsHint => 'ابحث في المراجعات...';

  @override
  String get expReviewsTitle => 'المراجعات';

  @override
  String expNoReviewsMatch(String query) {
    return 'لا توجد مراجعات لـ \"$query\"';
  }

  @override
  String expShowAllReviews(int count) {
    return 'عرض كل $count المراجعات';
  }

  @override
  String get expCommunityVolunteerBadge => 'متطوع مجتمعي';

  @override
  String get expPriceAfterPhotos => 'مضمون بعد الموافقة على الصور';

  @override
  String get expDeposit => 'دفعة مقدمة';

  @override
  String get expNights => 'ليالي';

  @override
  String get expNightsCount => 'عدد الليالي';

  @override
  String get expEndDate => 'تاريخ انتهاء الإقامة';

  @override
  String get expSelectDate => 'الرجاء اختيار تاريخ';

  @override
  String get expMustFillAll => 'الرجاء تعبئة جميع الحقول المطلوبة للمتابعة';

  @override
  String get expBookingReceivedDemo => 'تم استلام الحجز!';

  @override
  String get expBookingSuccess => 'تم الحجز بنجاح! 🎉';

  @override
  String get expBookingDemoBody => 'قمت بحجز الخدمة. نتحقق من توفر مزود الخدمة.\nسنبلغك فور الحصول على رد.';

  @override
  String get expWillNotify => 'سنرسل لك تحديثاً قريباً';

  @override
  String get expGotIt => 'فهمت ✓';

  @override
  String get expProviderRole => 'مزود خدمة';

  @override
  String get expJobsLabel => 'الأعمال';

  @override
  String get expRatingLabel => 'التقييم';

  @override
  String get expReviewsLabel => 'المراجعات';

  @override
  String get expVolunteersLabel => 'التطوع المجتمعي';

  @override
  String get expVideoIntro => 'فيديو التعريف';

  @override
  String get expGallery => 'معرض الأعمال';

  @override
  String get expVerifiedCertificate => 'شهادة معتمدة';

  @override
  String get expView => 'عرض';

  @override
  String get expCertificateTitle => 'شهادة';

  @override
  String get expImageLoadError => 'خطأ في تحميل الصورة';

  @override
  String get catBadgeAngel => 'ملاك';

  @override
  String get catBadgePillar => 'ركيزة';

  @override
  String get catBadgeVolunteer => 'متطوع';

  @override
  String get catDayOffline => 'غير متاح الآن';

  @override
  String get catStartLesson => 'ابدأ الدرس';

  @override
  String get catYourProfile => 'ملفك الشخصي';

  @override
  String get catMapView => 'عرض الخريطة';

  @override
  String get catListView => 'عرض القائمة';

  @override
  String get catInstantBookingSoon => 'حجز فوري — قريباً 🎉';

  @override
  String get catFreeCommunityBadge => 'خدمة مجتمعية مجانية — 100% مجانية ❤️';

  @override
  String get catNeedHelp => 'أحتاج مساعدة';

  @override
  String get catHelpForOther => 'مساعدة لشخص آخر';

  @override
  String get catRespectTime => 'يرجى احترام وقتهم واستخدام هذه الخدمة للاحتياجات الحقيقية فقط.';

  @override
  String get catFilterRating => 'التقييم';

  @override
  String get catFilterDistance => 'المسافة';

  @override
  String get catFilterKm => 'كم';

  @override
  String get catFilterMore => 'المزيد';

  @override
  String get catFilterRatingTitle => 'تصفية حسب التقييم';

  @override
  String get catFilterAll => 'الكل';

  @override
  String get catFilterApply => 'تطبيق';

  @override
  String get catFilterDistanceTitle => 'تصفية حسب المسافة';

  @override
  String get catFilterNeedLocation => 'يرجى تفعيل الموقع للتصفية حسب المسافة';

  @override
  String get catFilterClear => 'مسح';

  @override
  String get catMaxDistance => 'أقصى مسافة';

  @override
  String get catNoLimit => 'بدون حد';

  @override
  String catUpToKm(int km) {
    return 'حتى $km كم';
  }

  @override
  String get catMinRating => 'الحد الأدنى للتقييم';

  @override
  String get catSupport => 'الدعم';

  @override
  String get catFillFields => 'يرجى تعبئة الفئة والوصف ورقم الهاتف';

  @override
  String get catRequestSent => 'تم إرسال الطلب! سيتم إبلاغ المتطوعين المناسبين.';

  @override
  String catRequestError(String error) {
    return 'خطأ: $error';
  }

  @override
  String get catCategory => 'الفئة';

  @override
  String get catChooseCategory => 'اختر مجال المساعدة';

  @override
  String get catRequestDescription => 'وصف الطلب';

  @override
  String get catDescHint => 'صف ما يجب فعله...';

  @override
  String get catLocation => 'الموقع';

  @override
  String get catLocationHint => 'المدينة / الحي';

  @override
  String get catContactPhone => 'هاتف للتواصل';

  @override
  String get catBeneficiaryName => 'اسم المستفيد';

  @override
  String get catBeneficiaryHint => 'اسم الشخص الذي يحتاج المساعدة';

  @override
  String get catIAmContact => 'أنا جهة الاتصال';

  @override
  String get catIAmCoordinator => 'سأنسق مع المتطوع';

  @override
  String get catSendRequest => 'إرسال طلب المساعدة';

  @override
  String get catBack => 'رجوع';

  @override
  String get catSearchInCategory => 'ابحث داخل الفئة...';

  @override
  String get catUnder100 => 'حتى ₪100';

  @override
  String get catAvailableNow => 'متاح الآن';

  @override
  String get catInstantBook => 'حجز فوري';

  @override
  String get catInNeighborhood => 'في حيك';

  @override
  String get catAvailableNowUser => 'متاح الآن';

  @override
  String get catRecommended => 'موصى به';

  @override
  String get catWhenAvailable => 'متى متاح؟';

  @override
  String get catBookNow => 'احجز الآن';

  @override
  String editVideoUploadError(String error) {
    return 'خطأ في رفع الفيديو: $error';
  }

  @override
  String get editAddSecondIdentity => 'أضف هوية مهنية ثانية';

  @override
  String get editSecondIdentitySubtitle => 'اربح أكثر — قدّم خدمة أخرى تحت نفس الحساب';

  @override
  String get editPrimaryIdentity => 'الهوية الأساسية';

  @override
  String get editSecondaryIdentity => 'الهوية الثانوية';

  @override
  String get editEditingNow => 'جاري التحرير';

  @override
  String get editPhoneLabel => 'رقم الهاتف';

  @override
  String get editPhoneVerified => 'الرقم موثّق — لا يمكن تغييره';

  @override
  String get editAppPending => 'طلبك قيد المراجعة 🕐';

  @override
  String get editAppPendingDesc => 'فريقنا يراجع التفاصيل وسيرد عليك قريباً.';

  @override
  String get editBecomeProvider => 'تريد العمل والربح؟ اضغط هنا';

  @override
  String editApplicationMessage(String name) {
    return 'طلب الانضمام كمزود خدمة: $name';
  }

  @override
  String editGenericError(String error) {
    return 'خطأ: $error';
  }

  @override
  String get editUploadClearPhoto => 'ارفع صورة واضحة لوجهك';

  @override
  String get editClearPhotoDesc => 'الملفات ذات الصور الواضحة تحصل على استفسارات أكثر بـ 3 أضعاف';

  @override
  String get editAccountTypeChange => 'يتم تغيير نوع الحساب عبر خدمة العملاء فقط';

  @override
  String get editVolunteerToggleTitle => 'أريد التطوع';

  @override
  String get editVolunteerToggleDesc => 'قدّم مهاراتك مجاناً لمن يحتاجها';

  @override
  String get editIdentitiesTitle => 'هوياتك المهنية';

  @override
  String get editPaymentSettings => 'إعدادات الدفع قريباً';

  @override
  String get editPaymentSettingsDesc => 'نعمل على الانتقال إلى مزود دفع إسرائيلي. خلال ذلك يتم معالجة طلبات السحب يدوياً بواسطة فريقنا.';

  @override
  String get editAdvancedSettings => 'إعدادات متقدمة';

  @override
  String get editPricingSettings => 'إعدادات التسعير';

  @override
  String get editWorkingHours => 'ساعات العمل';

  @override
  String get editWorkingHoursHint => 'حدد أيام وساعات عملك';

  @override
  String get editDayOff => 'إجازة';

  @override
  String get editCertificate => 'شهادة';

  @override
  String get editCertificateDesc => 'ارفع شهادة مهنية (اختياري)';

  @override
  String get editReplaceCertificate => 'استبدال الشهادة';

  @override
  String get editUploadCertificate => 'رفع شهادة';

  @override
  String get editIntroVideo => 'فيديو تعريفي';

  @override
  String get editIntroVideoDesc => 'أضف فيديو قصير (حتى 60 ثانية) يعرّف بك وبمهاراتك. سيظهر في ملفك بعد موافقة المدير.';

  @override
  String editUploading(int percent) {
    return 'جاري الرفع... $percent%';
  }

  @override
  String get editVideoUploaded => 'تم رفع الفيديو — اضغط للاستبدال';

  @override
  String get editUploadVideo => 'رفع فيديو تعريفي (حتى 60 ثانية)';

  @override
  String get editPendingAdmin => 'بانتظار موافقة المدير — سيظهر في الملف بعد الموافقة';

  @override
  String get editManagement => 'إدارة';

  @override
  String get editServiceProvider => 'مزود خدمة';

  @override
  String get editCustomer => 'عميل';

  @override
  String get editAdminModeActive => 'وضع الإدارة فعّال';

  @override
  String get editProviderModeActive => 'وضع مزود الخدمة فعّال';

  @override
  String get editCustomerModeActive => 'وضع العميل فعّال';

  @override
  String get editViewMode => 'وضع العرض';

  @override
  String get editMyDogs => 'كلابي';

  @override
  String get editShowAll => 'عرض الكل';

  @override
  String get editAddDogProfile => 'إضافة ملف كلب';

  @override
  String get editNewDog => 'كلب جديد';

  @override
  String get editUnnamedDog => 'بدون اسم';

  @override
  String get editApplyAsProvider => 'تقديم طلب كمزود خدمة';

  @override
  String get editApplyDesc => 'املأ البيانات وسنراجع طلبك';

  @override
  String get editServiceFieldLabel => 'مجال الخدمة *';

  @override
  String get editChooseField => 'اختر المجال';

  @override
  String get editIdNumberLabel => 'رقم الهوية / السجل *';

  @override
  String get editIdNumberHint => 'أدخل رقم الهوية أو السجل';

  @override
  String get editAboutYouLabel => 'عن نفسك *';

  @override
  String get editAboutYouHint => 'صف خبرتك، الخدمات التي تقدمها...';

  @override
  String get editSubmitApplication => 'إرسال الطلب';

  @override
  String get editChooseFieldError => 'اختر مجال الخدمة';

  @override
  String get editEnterIdError => 'أدخل رقم الهوية';

  @override
  String get editDaySunday => 'الأحد';

  @override
  String get editDayMonday => 'الاثنين';

  @override
  String get editDayTuesday => 'الثلاثاء';

  @override
  String get editDayWednesday => 'الأربعاء';

  @override
  String get editDayThursday => 'الخميس';

  @override
  String get editDayFriday => 'الجمعة';

  @override
  String get editDaySaturday => 'السبت';

  @override
  String get phoneInvalidNumber => 'رقم هاتف غير صالح';

  @override
  String phoneTooManyCodes(int mins) {
    return 'تم إرسال رموز كثيرة. انتظر $mins دقائق.';
  }

  @override
  String get phoneSendCodeError => 'خطأ في إرسال الرمز. حاول مرة أخرى.';

  @override
  String get phoneErrorTooManyRequests => 'محاولات كثيرة. حاول لاحقاً.';

  @override
  String get phoneErrorQuotaExceeded => 'تجاوزت حصة SMS. حاول غداً.';

  @override
  String get phoneErrorNoNetwork => 'لا يوجد اتصال بالإنترنت';

  @override
  String phoneErrorGeneric(String code) {
    return 'خطأ: $code';
  }

  @override
  String phoneRateLimitInfo(int max, int mins) {
    return 'حتى $max رموز كل $mins دقائق';
  }

  @override
  String phoneLoginError(String code) {
    return 'خطأ في الدخول: $code';
  }

  @override
  String get countryIsrael => 'إسرائيل';

  @override
  String get otpLegacyUserDialogTitle => 'حساب موجود';

  @override
  String get otpLegacyUserDialogBody => 'لهذا الرقم حساب موجود. يرجى التواصل مع الدعم.';

  @override
  String get notifMuted => 'مكتوم';

  @override
  String get notifMuteAll => 'كتم الكل';

  @override
  String get chatTyping => 'يكتب...';

  @override
  String get chatOnline => 'متصل';

  @override
  String get expertPhotoGalleryEmpty => 'لا توجد صور بعد';

  @override
  String catMapResultsCount(int count) {
    return '$count نتائج في منطقتك';
  }

  @override
  String catSearchResultsTitle(String category) {
    return 'مزودو الخدمة في $category';
  }

  @override
  String get catAnyExpert => 'جميع مزودي الخدمة';

  @override
  String get catSortBy => 'ترتيب حسب';

  @override
  String get catSortRelevance => 'الصلة';

  @override
  String get catSortDistance => 'المسافة';

  @override
  String get catSortRating => 'التقييم';

  @override
  String get catSortPrice => 'السعر';

  @override
  String get catNoResults => 'لا توجد نتائج';

  @override
  String get catNoResultsDesc => 'جرب تغيير التصفية أو البحث في منطقة أخرى';

  @override
  String get catUrgent => 'عاجل';

  @override
  String get catExpressDelivery => 'توصيل سريع';

  @override
  String get editVerifiedBadge => 'موثّق';

  @override
  String get editAdminOnlyChange => 'هذا التغيير متاح للمدير فقط';

  @override
  String get editProfileSaved => 'تم حفظ الملف بنجاح';

  @override
  String get editPriceLabel => 'السعر في الساعة (₪)';

  @override
  String get editPriceHint => 'أدخل السعر بالشيكل';

  @override
  String get editAboutMeLabel => 'أخبرنا عن نفسك';

  @override
  String get editAboutMeHint => 'صف خبرتك، الخدمات التي تقدمها...';

  @override
  String get editCategoryLabel => 'الفئة المهنية';

  @override
  String get editSubCategoryLabel => 'الفئة الفرعية';

  @override
  String get editDogNameLabel => 'اسم الكلب';

  @override
  String get editDogBreedLabel => 'السلالة';

  @override
  String get editDogAgeLabel => 'العمر';

  @override
  String get editDogWeightLabel => 'الوزن (كغ)';

  @override
  String get editDogSizeLabel => 'الحجم';

  @override
  String get editDogDescLabel => 'الوصف';

  @override
  String get editDogSaveBtn => 'حفظ ملف الكلب';

  @override
  String get editDogPickPhoto => 'اختر صورة';

  @override
  String get editDogNameHint => 'ما اسم الكلب؟';

  @override
  String get editDogBreedHint => 'مثلاً: غولدن ريتريفر';

  @override
  String get editDogSizeSmall => 'صغير';

  @override
  String get editDogSizeMedium => 'متوسط';

  @override
  String get editDogSizeLarge => 'كبير';

  @override
  String get editDogYears => 'سنوات';

  @override
  String get editDogDescHint => 'الشخصية، الهوايات، أشياء مهمة...';

  @override
  String get editCancellationPolicyTitle => 'سياسة الإلغاء';

  @override
  String get editCancellationFlexible => 'مرنة';

  @override
  String get editCancellationModerate => 'متوسطة';

  @override
  String get editCancellationStrict => 'صارمة';

  @override
  String get editCancellationFlexibleDesc => 'استرداد كامل حتى 4 ساعات قبل';

  @override
  String get editCancellationModerateDesc => 'استرداد كامل حتى 24 ساعة قبل';

  @override
  String get editCancellationStrictDesc => 'استرداد كامل حتى 48 ساعة قبل';

  @override
  String get editResponseTimeLabel => 'متوسط وقت الرد';

  @override
  String get editResponseImmediate => 'فوري';

  @override
  String get editResponse30min => 'خلال 30 دقيقة';

  @override
  String get editResponse1h => 'خلال ساعة';

  @override
  String get editResponseDay => 'خلال يوم';

  @override
  String get editQuickTagsTitle => 'علامات سريعة';

  @override
  String get editQuickTagsDesc => 'اختر حتى 5 علامات تصف خدمتك';

  @override
  String get editSave => 'حفظ';

  @override
  String get editSaving => 'جاري الحفظ...';

  @override
  String get editDiscardChanges => 'إلغاء التغييرات؟';

  @override
  String get editDiscardConfirm => 'لديك تغييرات غير محفوظة. إلغاؤها؟';

  @override
  String get editDiscard => 'إلغاء التغييرات';

  @override
  String get editContinueEditing => 'متابعة التحرير';

  @override
  String get editFieldRequired => 'مطلوب';

  @override
  String get editInvalidPrice => 'سعر غير صالح';

  @override
  String editMinPrice(int min) {
    return 'السعر الأدنى هو ₪$min';
  }

  @override
  String get editCustomerServiceType => 'عميل';

  @override
  String get editAboutMinChars => 'اكتب على الأقل 20 حرفاً عن نفسك';

  @override
  String get editSecondIdentityCreated => 'تم إنشاء الهوية المهنية الثانية! 🎉';

  @override
  String get editAddSecondIdentityTitle => 'إضافة هوية مهنية ثانية';

  @override
  String get editAddSecondIdentityDesc => 'اختر فئة وسعراً ووصفاً جديداً — ستظهر الهوية الثانية بشكل منفصل في البحث';

  @override
  String get editSecondServiceDesc => 'أخبر العملاء عن خدمتك الثانية...';

  @override
  String get editCreateIdentity => 'إنشاء هوية مهنية';

  @override
  String get editIdentityUpdated => 'تم تحديث الهوية المهنية بنجاح';

  @override
  String get editDeleteIdentityTitle => 'حذف الهوية المهنية';

  @override
  String get editDeleteIdentityConfirm => 'حذف الهوية المهنية الثانية؟ لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get editDelete => 'حذف';

  @override
  String get editIdentityDeleted => 'تم حذف الهوية المهنية';

  @override
  String get editSaveChanges => 'حفظ التغييرات';

  @override
  String get editDeleteIdentity => 'حذف الهوية المهنية';

  @override
  String editEditingIdentity(String type) {
    return 'تحرير $type';
  }

  @override
  String get phoneLoginContinueGoogle => 'المتابعة مع Google';

  @override
  String get phoneLoginContinueApple => 'المتابعة مع Apple';

  @override
  String get phoneLoginOrPhone => 'أو برقم الهاتف';

  @override
  String get phoneLoginCtaLogin => 'تسجيل الدخول';

  @override
  String get phoneLoginTermsPrefix => 'بالمتابعة، أوافق على';

  @override
  String get phoneLoginTermsOfUse => 'شروط الاستخدام';

  @override
  String get phoneLoginAnd => 'و';

  @override
  String get phoneLoginPrivacyPolicy => 'سياسة الخصوصية';

  @override
  String get phoneLoginOfferingService => 'تقدّم خدمة؟';

  @override
  String get phoneLoginBecomeProvider => 'اربح مع AnySkill ←';
}
