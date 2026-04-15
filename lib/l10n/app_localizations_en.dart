// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'AnySkill';

  @override
  String get appSlogan => 'Your professionals, one tap away';

  @override
  String get greetingMorning => 'Good Morning';

  @override
  String get greetingAfternoon => 'Good Afternoon';

  @override
  String get greetingEvening => 'Good Evening';

  @override
  String get greetingNight => 'Good Night';

  @override
  String get greetingSubMorning => 'What would you like to do today?';

  @override
  String get greetingSubAfternoon => 'Need help with something?';

  @override
  String get greetingSubEvening => 'Still looking for a service?';

  @override
  String get greetingSubNight => 'See you tomorrow!';

  @override
  String get tabHome => 'Home';

  @override
  String get tabBookings => 'Bookings';

  @override
  String get tabChat => 'Messages';

  @override
  String get tabWallet => 'Wallet';

  @override
  String get bookNow => 'Book Now';

  @override
  String get bookingCompleted => 'Booking completed successfully';

  @override
  String get close => 'Close';

  @override
  String get retryButton => 'Retry';

  @override
  String get saveChanges => 'Save Changes';

  @override
  String get saveSuccess => 'Saved successfully';

  @override
  String saveError(String error) {
    return 'Error saving: $error';
  }

  @override
  String get defaultUserName => 'User';

  @override
  String get notLoggedIn => 'Not logged in';

  @override
  String get linkCopied => 'Link copied';

  @override
  String get errorEmptyFields => 'Please fill in all fields';

  @override
  String get errorGeneric => 'An error occurred. Please try again';

  @override
  String get errorInvalidEmail => 'Invalid email address';

  @override
  String get whatsappError => 'Unable to open WhatsApp';

  @override
  String get markAllReadTooltip => 'Mark all as read';

  @override
  String get onlineStatus => 'Available';

  @override
  String get offlineStatus => 'Unavailable';

  @override
  String get onlineToggleOn => 'You are now available';

  @override
  String get onlineToggleOff => 'You are now unavailable';

  @override
  String get roleCustomer => 'Customer';

  @override
  String get roleProvider => 'Service Provider';

  @override
  String get loginAccountTitle => 'Account Login';

  @override
  String get loginButton => 'Sign In';

  @override
  String get loginEmail => 'Email';

  @override
  String get loginForgotPassword => 'Forgot password?';

  @override
  String get loginNoAccount => 'Don\'t have an account? ';

  @override
  String get loginPassword => 'Password';

  @override
  String get loginRememberMe => 'Remember me';

  @override
  String get loginSignUpFree => 'Sign up for free';

  @override
  String get loginStats10k => '10K+';

  @override
  String get loginStats50 => '50+';

  @override
  String get loginStats49 => '4.9★';

  @override
  String get loginWelcomeBack => 'Welcome back!';

  @override
  String get signupAccountCreated => 'Account created successfully!';

  @override
  String get signupEmailInUse => 'Email already in use';

  @override
  String get signupGenericError => 'An error occurred during signup';

  @override
  String get signupGoogleError => 'Error signing in with Google';

  @override
  String get signupNetworkError => 'Network error. Check your connection';

  @override
  String get signupNewCustomerBio => 'New customer on AnySkill';

  @override
  String get signupNewProviderBio => 'New service provider on AnySkill';

  @override
  String get signupTosMustAgree => 'You must agree to the Terms of Service';

  @override
  String get signupWeakPassword => 'Password is too weak';

  @override
  String get forgotPasswordEmail => 'Email address';

  @override
  String get forgotPasswordError => 'Error sending reset link';

  @override
  String get forgotPasswordSubmit => 'Send Reset Link';

  @override
  String get forgotPasswordSubtitle => 'Enter your email and we\'ll send you a password reset link';

  @override
  String get forgotPasswordSuccess => 'Reset link sent to your email';

  @override
  String get forgotPasswordTitle => 'Forgot Password';

  @override
  String authError(String code) {
    return 'Auth error: $code';
  }

  @override
  String get profileTitle => 'My Profile';

  @override
  String get profileFieldName => 'Full Name';

  @override
  String get profileFieldNameHint => 'Enter your full name';

  @override
  String get profileFieldRole => 'User Type';

  @override
  String get profileFieldCategoryMain => 'Main Category';

  @override
  String get profileFieldCategoryMainHint => 'Choose your main category';

  @override
  String get profileFieldCategorySub => 'Sub-Category';

  @override
  String get profileFieldCategorySubHint => 'Choose a specific specialty';

  @override
  String get profileFieldPrice => 'Price per Hour (₪)';

  @override
  String get profileFieldPriceHint => 'Enter your hourly rate';

  @override
  String get profileFieldResponseTime => 'Response Time (minutes)';

  @override
  String get profileFieldResponseTimeHint => 'Average response time';

  @override
  String get profileFieldTaxId => 'Business License Number';

  @override
  String get profileFieldTaxIdHint => 'Enter business license number';

  @override
  String get profileFieldTaxIdHelp => 'This number will be used for invoicing';

  @override
  String get editProfileAbout => 'About Me';

  @override
  String get editProfileAboutHint => 'Tell clients about your experience...';

  @override
  String get editProfileCancellationPolicy => 'Cancellation Policy';

  @override
  String get editProfileCancellationHint => 'Choose a cancellation policy';

  @override
  String get editProfileGallery => 'Gallery';

  @override
  String get editProfileQuickTags => 'Quick Tags';

  @override
  String get editProfileTagsHint => 'Add tags to your profile';

  @override
  String editProfileTagsSelected(int count) {
    return '$count selected';
  }

  @override
  String get editCategoryTitle => 'Edit Category';

  @override
  String get editCategoryNameLabel => 'Category Name';

  @override
  String get editCategoryChangePic => 'Change Picture';

  @override
  String get shareProfileTitle => 'Share Profile';

  @override
  String get shareProfileTooltip => 'Share your profile';

  @override
  String get shareProfileCopyLink => 'Copy Link';

  @override
  String get shareProfileWhatsapp => 'Share on WhatsApp';

  @override
  String get statBalance => 'Balance';

  @override
  String get searchHintExperts => 'Search professionals...';

  @override
  String get searchDefaultTitle => 'Search';

  @override
  String get searchDefaultCity => 'Israel';

  @override
  String get searchDefaultExpert => 'Professional';

  @override
  String get searchSectionCategories => 'Categories';

  @override
  String searchSectionResultsFor(String query) {
    return 'Results for \"$query\"';
  }

  @override
  String searchNoResultsFor(String query) {
    return 'No results for \"$query\"';
  }

  @override
  String get searchNoCategoriesBody => 'No categories found';

  @override
  String get searchPerHour => '₪/hr';

  @override
  String get searchRecommendedBadge => 'Recommended';

  @override
  String get searchChipHomeVisit => 'Home Visit';

  @override
  String get searchChipWeekend => 'Available on Weekends';

  @override
  String get searchDatePickerHint => 'Select a date';

  @override
  String get searchTourSearchTitle => 'Search Professionals';

  @override
  String get searchTourSearchDesc => 'Search by name, service, or category';

  @override
  String get searchTourSuggestionsTitle => 'Smart Suggestions';

  @override
  String get searchTourSuggestionsDesc => 'Personalized suggestions based on your searches';

  @override
  String get searchUrgencyMorning => 'Morning';

  @override
  String get searchUrgencyAfternoon => 'Afternoon';

  @override
  String get searchUrgencyEvening => 'Evening';

  @override
  String get catResultsSearchHint => 'Search within category...';

  @override
  String catResultsNoExperts(String category) {
    return 'No professionals in $category';
  }

  @override
  String get catResultsNoResults => 'No results';

  @override
  String get catResultsNoResultsHint => 'Try changing your search';

  @override
  String get catResultsPerHour => '₪/hr';

  @override
  String catResultsOrderCount(int count) {
    return '$count orders';
  }

  @override
  String catResultsResponseTime(int minutes) {
    return 'Responds in $minutes min';
  }

  @override
  String get catResultsRecommended => 'Recommended';

  @override
  String get catResultsTopRated => 'Top Rated';

  @override
  String get catResultsUnder100 => 'Under ₪100';

  @override
  String get catResultsClearFilters => 'Clear Filters';

  @override
  String get catResultsBeFirst => 'Be the first!';

  @override
  String get catResultsExpertDefault => 'Professional';

  @override
  String get catResultsLoadMore => 'Load More';

  @override
  String get catResultsAvailableSlots => 'Available Slots';

  @override
  String get catResultsNoAvailability => 'No Availability';

  @override
  String get catResultsFullBooking => 'Fully Booked';

  @override
  String get catResultsWhenFree => 'When available?';

  @override
  String get chatListTitle => 'Messages';

  @override
  String get expertSectionAbout => 'About';

  @override
  String get expertSectionService => 'Service';

  @override
  String get expertSectionSchedule => 'Availability';

  @override
  String get expertBioPlaceholder => 'No bio yet';

  @override
  String get expertBioReadMore => 'Read more';

  @override
  String get expertBioShowLess => 'Show less';

  @override
  String get expertNoReviews => 'No reviews yet';

  @override
  String get expertDefaultReviewer => 'User';

  @override
  String get expertProviderResponse => 'Provider response';

  @override
  String get expertAddReply => 'Add reply';

  @override
  String get expertAddReplyTitle => 'Add reply to review';

  @override
  String get expertReplyHint => 'Write a reply...';

  @override
  String get expertPublishReply => 'Publish reply';

  @override
  String get expertReplyError => 'Error publishing reply';

  @override
  String get expertSelectDateTime => 'Select date and time';

  @override
  String get expertSelectTime => 'Select time';

  @override
  String expertBookForTime(String time) {
    return 'Book for $time';
  }

  @override
  String expertStartingFrom(String price) {
    return 'Starting from ₪$price';
  }

  @override
  String get expertBookingSummaryTitle => 'Booking Summary';

  @override
  String get expertSummaryRowService => 'Service';

  @override
  String get expertSummaryRowDate => 'Date';

  @override
  String get expertSummaryRowTime => 'Time';

  @override
  String get expertSummaryRowPrice => 'Price';

  @override
  String get expertSummaryRowIncluded => 'Included';

  @override
  String get expertSummaryRowProtection => 'Buyer Protection';

  @override
  String get expertSummaryRowTotal => 'Total';

  @override
  String get expertConfirmPaymentButton => 'Confirm & Pay';

  @override
  String get expertVerifiedBooking => 'Verified Booking';

  @override
  String get expertInsufficientBalance => 'Insufficient balance';

  @override
  String get expertEscrowSuccess => 'Payment confirmed and secured until the transaction is complete';

  @override
  String expertTransactionTitle(String name) {
    return 'Payment to $name';
  }

  @override
  String expertSystemMessage(String date, String time, String amount) {
    return 'Booking confirmed for $date at $time. ₪$amount locked in escrow.';
  }

  @override
  String expertCancellationNotice(String policy, String deadline, String penalty) {
    return '$policy policy: Free cancellation until $deadline. After that $penalty% penalty.';
  }

  @override
  String expertCancellationNoDeadline(String policy, String description) {
    return '$policy policy: $description';
  }

  @override
  String get financeTitle => 'Finances';

  @override
  String get financeAvailableBalance => 'Available Balance';

  @override
  String get financePending => 'Pending';

  @override
  String get financeProcessing => 'Processing';

  @override
  String get financeRecentActivity => 'Recent Activity';

  @override
  String get financeNoTransactions => 'No transactions';

  @override
  String get financeWithdrawButton => 'Withdraw Funds';

  @override
  String get financeMinWithdraw => 'Minimum withdrawal: ₪50';

  @override
  String get financeTrustBadge => 'Your money is protected';

  @override
  String financeReceivedFrom(String name) {
    return 'Received from $name';
  }

  @override
  String financePaidTo(String name) {
    return 'Paid to $name';
  }

  @override
  String financeError(String error) {
    return 'Error: $error';
  }

  @override
  String get disputeConfirmRefund => 'Confirm Refund';

  @override
  String get disputeConfirmRelease => 'Confirm Payment Release';

  @override
  String get disputeConfirmSplit => 'Confirm Split';

  @override
  String get disputePartyCustomer => 'the customer';

  @override
  String disputeRefundBody(String amount, String customerName) {
    return '₪$amount will be refunded to $customerName';
  }

  @override
  String disputeReleaseBody(String netAmount, String expertName, String feePercent) {
    return '₪$netAmount will be released to $expertName ($feePercent% fee)';
  }

  @override
  String disputeSplitBody(String halfAmount, String halfNet, String platformFee) {
    return 'Split: ₪$halfAmount each side. Provider gets ₪$halfNet, platform ₪$platformFee';
  }

  @override
  String get disputeResolvedRefund => 'Dispute resolved — refund issued';

  @override
  String get disputeResolvedRelease => 'Dispute resolved — payment released';

  @override
  String get disputeResolvedSplit => 'Dispute resolved — amount split';

  @override
  String get disputeTypeAudio => 'Audio';

  @override
  String get disputeTypeImage => 'Image';

  @override
  String get disputeTypeLocation => 'Location';

  @override
  String get releasePaymentError => 'Error releasing payment';

  @override
  String get oppTitle => 'Opportunities';

  @override
  String get oppAllCategories => 'All Categories';

  @override
  String get oppEmptyAll => 'No opportunities right now';

  @override
  String get oppEmptyAllSubtitle => 'Check back later';

  @override
  String get oppEmptyCategory => 'No opportunities in this category';

  @override
  String get oppEmptyCategorySubtitle => 'Try a different category';

  @override
  String get oppTakeOpportunity => 'Take Opportunity';

  @override
  String get oppInterested => 'Interested';

  @override
  String get oppAlreadyInterested => 'Already expressed interest';

  @override
  String get oppAlreadyExpressed => 'You already expressed interest in this request';

  @override
  String get oppAlready3Interested => 'Already has 3 interested providers';

  @override
  String get oppInterestSuccess => 'Your interest has been registered!';

  @override
  String get oppRequestClosed3 => 'Request closed — 3 interested';

  @override
  String get oppRequestClosedBtn => 'Request Closed';

  @override
  String get oppRequestUnavailable => 'Request is no longer available';

  @override
  String get oppDefaultClient => 'Client';

  @override
  String get oppHighDemand => 'High Demand';

  @override
  String get oppQuickBid => 'Quick Bid';

  @override
  String oppQuickBidMessage(String clientName, String providerName) {
    return 'Hi $clientName, I\'m $providerName and I\'d love to help!';
  }

  @override
  String get oppEstimatedEarnings => 'Estimated Earnings';

  @override
  String get oppAfterFee => 'After fee';

  @override
  String get oppWalletHint => 'Earnings go to your wallet';

  @override
  String oppXpToNextLevel(int xpNeeded, String levelName) {
    return '$xpNeeded XP to $levelName level';
  }

  @override
  String get oppMaxLevel => 'Max level!';

  @override
  String get oppBoostEarned => 'Profile boost earned!';

  @override
  String oppBoostProgress(int count) {
    return '$count/3 opportunities to boost';
  }

  @override
  String oppProfileBoosted(String timeLabel) {
    return 'Profile boosted! $timeLabel remaining';
  }

  @override
  String oppError(String error) {
    return 'Error: $error';
  }

  @override
  String get oppTimeJustNow => 'Just now';

  @override
  String oppTimeMinAgo(int minutes) {
    return '$minutes min ago';
  }

  @override
  String oppTimeHourAgo(int hours) {
    return '$hours hours ago';
  }

  @override
  String oppTimeDayAgo(int days) {
    return '$days days ago';
  }

  @override
  String oppTimeHours(int hours) {
    return '$hours hours';
  }

  @override
  String oppTimeMinutes(int minutes) {
    return '$minutes minutes';
  }

  @override
  String get oppUnderReviewTitle => 'Your profile is under review';

  @override
  String get oppUnderReviewSubtitle => 'The AnySkill team is reviewing your profile';

  @override
  String get oppUnderReviewBody => 'We\'ll notify you once verification is complete';

  @override
  String get oppUnderReviewContact => 'Contact Support';

  @override
  String get oppUnderReviewStep1 => 'Profile submitted';

  @override
  String get oppUnderReviewStep2 => 'Under review';

  @override
  String get oppUnderReviewStep3 => 'Final approval';

  @override
  String get requestsEmpty => 'No requests';

  @override
  String get requestsEmptySubtitle => 'No requests posted yet';

  @override
  String get requestsChatNow => 'Send Message';

  @override
  String get requestsClosed => 'Closed';

  @override
  String get requestsConfirmPay => 'Confirm & Pay';

  @override
  String get requestsDefaultExpert => 'Professional';

  @override
  String get requestsEscrowTooltip => 'Funds are held in escrow until the job is done';

  @override
  String get requestsMatchLabel => 'Match';

  @override
  String get requestsTopMatch => 'Top Match';

  @override
  String get requestsVerifiedBadge => 'Verified';

  @override
  String get requestsMoneyProtected => 'Your money is protected';

  @override
  String get requestsWaiting => 'Waiting';

  @override
  String get requestsWaitingProviders => 'Waiting for providers...';

  @override
  String get requestsJustNow => 'Just now';

  @override
  String requestsMinutesAgo(int minutes) {
    return '$minutes min ago';
  }

  @override
  String requestsHoursAgo(int hours) {
    return '$hours hours ago';
  }

  @override
  String requestsDaysAgo(int days) {
    return '$days days ago';
  }

  @override
  String requestsInterested(int count) {
    return '$count interested';
  }

  @override
  String requestsViewInterested(int count) {
    return 'View $count interested';
  }

  @override
  String requestsOrderCount(int count) {
    return '$count orders';
  }

  @override
  String requestsHiredAgo(String label) {
    return 'Hired $label';
  }

  @override
  String requestsPricePerHour(String price) {
    return '₪$price/hr';
  }

  @override
  String get timeNow => 'Now';

  @override
  String get timeOneHour => 'Hour';

  @override
  String timeMinutesAgo(int minutes) {
    return '$minutes min ago';
  }

  @override
  String timeHoursAgo(int hours) {
    return '$hours hours ago';
  }

  @override
  String get urgentBannerRequests => 'Urgent Requests';

  @override
  String get urgentBannerPending => 'Pending';

  @override
  String get urgentBannerServiceNeeded => 'Service Needed';

  @override
  String get urgentBannerCustomerWaiting => 'Customer Waiting';

  @override
  String get calendarTitle => 'Calendar';

  @override
  String get calendarRefresh => 'Refresh';

  @override
  String get calendarNoEvents => 'No events';

  @override
  String get calendarStatusCompleted => 'Completed';

  @override
  String get calendarStatusPending => 'Pending';

  @override
  String get calendarStatusWaiting => 'Waiting';

  @override
  String get creditsLabel => 'Credits';

  @override
  String creditsDiscountAvailable(int discount) {
    return '$discount% discount available!';
  }

  @override
  String creditsToNextDiscount(int remaining) {
    return '$remaining credits to next discount';
  }

  @override
  String get serviceFullSession => 'Full Session';

  @override
  String get serviceSingleLesson => 'Single Lesson';

  @override
  String get serviceExtendedLesson => 'Extended Lesson';

  @override
  String get validationNameRequired => 'Name is required';

  @override
  String get validationNameLength => 'Name must be at least 2 characters';

  @override
  String get validationNameTooLong => 'Name is too long';

  @override
  String get validationNameForbidden => 'Name contains forbidden characters';

  @override
  String get validationCategoryRequired => 'Please select a category';

  @override
  String get validationRoleRequired => 'Please select a user type';

  @override
  String get validationPriceInvalid => 'Invalid price';

  @override
  String get validationPricePositive => 'Price must be positive';

  @override
  String get validationAboutTooLong => 'Description is too long';

  @override
  String get validationAboutForbidden => 'Description contains forbidden characters';

  @override
  String get validationFieldForbidden => 'Field contains forbidden characters';

  @override
  String get validationUrlHttps => 'URL must start with https://';

  @override
  String get vipSheetHeader => 'AnySkill VIP';

  @override
  String get vipPriceMonthly => '₪99/month';

  @override
  String get vipActivateButton => 'Activate VIP';

  @override
  String get vipActivationSuccess => 'VIP activated successfully!';

  @override
  String get vipInsufficientBalance => 'Insufficient balance to activate VIP';

  @override
  String get vipInsufficientTooltip => 'Top up your wallet to activate VIP';

  @override
  String get vipBenefit1 => 'Priority in search results';

  @override
  String get vipBenefit2 => 'VIP badge on profile';

  @override
  String get vipBenefit3 => 'Priority in opportunities';

  @override
  String get vipBenefit4 => 'Premium support';

  @override
  String withdrawMinBalance(int amount) {
    return 'Minimum withdrawal amount is $amount ₪';
  }

  @override
  String get withdrawAvailableBalance => 'Available balance for withdrawal';

  @override
  String get withdrawBankSection => 'Bank Details';

  @override
  String get withdrawBankName => 'Bank Name';

  @override
  String get withdrawBankBranch => 'Branch';

  @override
  String get withdrawBankAccount => 'Account Number';

  @override
  String get withdrawBankRequired => 'Bank name is required';

  @override
  String get withdrawBranchRequired => 'Branch is required';

  @override
  String get withdrawAccountMinDigits => 'Account number must be at least 5 digits';

  @override
  String get withdrawBankEncryptedNotice => 'Details are encrypted and secure';

  @override
  String get withdrawEncryptedNotice => 'Information is encrypted and secure';

  @override
  String get withdrawBankTransferPending => 'Bank transfer in progress';

  @override
  String get withdrawCertSection => 'Certificates';

  @override
  String get withdrawCertHint => 'Upload business license / exemption certificate';

  @override
  String get withdrawCertUploadBtn => 'Upload Certificate';

  @override
  String get withdrawCertReplace => 'Replace Certificate';

  @override
  String get withdrawDeclarationSection => 'Declaration';

  @override
  String get withdrawDeclarationText => 'I declare sole responsibility for reporting my income taxes as required by law';

  @override
  String get withdrawDeclarationSuffix => '(Section 6 of the Terms)';

  @override
  String get withdrawTaxStatusTitle => 'Business Type';

  @override
  String get withdrawTaxStatusSubtitle => 'Select your business type';

  @override
  String get withdrawTaxIndividual => 'Exempt Dealer';

  @override
  String get withdrawTaxIndividualSub => 'Exempt from VAT collection';

  @override
  String get withdrawTaxIndividualBadge => 'Exempt';

  @override
  String get withdrawTaxBusiness => 'Licensed Dealer';

  @override
  String get withdrawTaxBusinessSub => 'Required to collect VAT';

  @override
  String get withdrawIndividualTitle => 'Exempt Dealer Details';

  @override
  String get withdrawIndividualDesc => 'Enter your exempt dealer details';

  @override
  String get withdrawIndividualFormTitle => 'Exempt Dealer Form';

  @override
  String get withdrawBusinessFormTitle => 'Licensed Dealer Form';

  @override
  String get withdrawNoCertError => 'Please upload a business certificate';

  @override
  String get withdrawNoDeclarationError => 'Please confirm the declaration';

  @override
  String get withdrawSelectBankError => 'Please select a bank';

  @override
  String withdrawSubmitButton(String amount) {
    return 'Withdraw $amount';
  }

  @override
  String get withdrawSubmitError => 'Error submitting request';

  @override
  String get withdrawSuccessTitle => 'Request Submitted!';

  @override
  String withdrawSuccessSubtitle(String amount) {
    return 'Withdrawal request for $amount submitted successfully';
  }

  @override
  String get withdrawSuccessNotice => 'Bank transfer will be processed within 3-5 business days';

  @override
  String get withdrawTimeline1Title => 'Request Submitted';

  @override
  String get withdrawTimeline1Sub => 'Request received by the system';

  @override
  String get withdrawTimeline2Title => 'Processing';

  @override
  String get withdrawTimeline2Sub => 'Team is processing your request';

  @override
  String get withdrawTimeline3Title => 'Completed';

  @override
  String get withdrawTimeline3Sub => 'Funds transferred to your account';

  @override
  String get pendingCatsApproved => 'Category approved';

  @override
  String get pendingCatsRejected => 'Category rejected';

  @override
  String get helpCenterTitle => 'Help Center';

  @override
  String get helpCenterTooltip => 'Help';

  @override
  String get helpCenterCustomerWelcome => 'Welcome to the Help Center';

  @override
  String get helpCenterCustomerFaq => 'Customer FAQ';

  @override
  String get helpCenterCustomerSupport => 'Customer Support';

  @override
  String get helpCenterProviderWelcome => 'Welcome to the Provider Help Center';

  @override
  String get helpCenterProviderFaq => 'Provider FAQ';

  @override
  String get helpCenterProviderSupport => 'Provider Support';

  @override
  String get languageTitle => 'Language';

  @override
  String get languageSectionLabel => 'Select Language';

  @override
  String get languageHe => 'עברית';

  @override
  String get languageEn => 'English';

  @override
  String get languageEs => 'Español';

  @override
  String get languageAr => 'العربية';

  @override
  String get systemWalletEnterNumber => 'Enter a valid number';

  @override
  String get updateBannerText => 'New version available';

  @override
  String get updateNowButton => 'Update Now';

  @override
  String get xpLevelBronze => 'Rookie';

  @override
  String get xpLevelSilver => 'Pro';

  @override
  String get xpLevelGold => 'Gold';

  @override
  String get bizAiTitle => 'Business Intelligence';

  @override
  String get bizAiSubtitle => 'AI-powered analysis and forecasting';

  @override
  String get bizAiLoading => 'Loading data...';

  @override
  String get bizAiRefreshData => 'Refresh Data';

  @override
  String get bizAiNoData => 'No data available';

  @override
  String bizAiError(String error) {
    return 'Error: $error';
  }

  @override
  String get bizAiSectionFinancial => 'Financial';

  @override
  String get bizAiSectionMarket => 'Market';

  @override
  String get bizAiSectionAlerts => 'Alerts';

  @override
  String get bizAiSectionAiOps => 'AI Operations';

  @override
  String get bizAiDailyCommission => 'Daily Commission';

  @override
  String get bizAiWeeklyProjection => 'Weekly Projection';

  @override
  String get bizAiWeeklyForecast => 'Weekly Forecast';

  @override
  String get bizAiExpectedRevenue => 'Expected Revenue';

  @override
  String get bizAiForecastBadge => 'Forecast';

  @override
  String get bizAiActualToDate => 'Actual to Date';

  @override
  String get bizAiAccuracy => 'Accuracy';

  @override
  String get bizAiModelAccuracy => 'Model Accuracy';

  @override
  String get bizAiModelAccuracyDetail => 'Revenue prediction accuracy';

  @override
  String get bizAiNoChartData => 'No chart data';

  @override
  String get bizAiNoOrderData => 'No order data';

  @override
  String get bizAiSevenDays => '7 Days';

  @override
  String get bizAiLast7Days => 'Last 7 Days';

  @override
  String get bizAiExecSummary => 'Executive Summary';

  @override
  String get bizAiActivityToday => 'Today\'s Activity';

  @override
  String get bizAiApprovalQueue => 'Approval Queue';

  @override
  String bizAiPending(int count) {
    return '$count pending';
  }

  @override
  String get bizAiPendingLabel => 'Pending';

  @override
  String get bizAiApproved => 'Approved';

  @override
  String get bizAiRejected => 'Rejected';

  @override
  String get bizAiApprovedTotal => 'Total Approved';

  @override
  String get bizAiTapToReview => 'Tap to review';

  @override
  String get bizAiCategoriesApproved => 'Approved Categories';

  @override
  String get bizAiNewCategories => 'New Categories';

  @override
  String get bizAiMarketOpportunities => 'Market Opportunities';

  @override
  String get bizAiMarketOppsCard => 'Market Opportunities';

  @override
  String get bizAiHighValueCategories => 'High-Value Categories';

  @override
  String get bizAiHighValueHint => 'Categories with high revenue potential';

  @override
  String bizAiProviders(int count) {
    return '$count providers';
  }

  @override
  String get bizAiPopularSearches => 'Popular Searches';

  @override
  String get bizAiNoSearchData => 'No search data';

  @override
  String get bizAiNichesNoProviders => 'Niches Without Providers';

  @override
  String get bizAiNoOpportunities => 'No opportunities at this time';

  @override
  String bizAiRecruitForQuery(String query) {
    return 'Recruit providers for \"$query\"';
  }

  @override
  String get bizAiZeroResultsHint => 'Searches with no results — recruitment opportunity';

  @override
  String bizAiSearches(int count) {
    return 'Searches: $count+';
  }

  @override
  String bizAiSearchCount(int count) {
    return '$count searches';
  }

  @override
  String get bizAiAlertHistory => 'Alert History';

  @override
  String get bizAiAlertThreshold => 'Alert Threshold';

  @override
  String get bizAiAlertThresholdHint => 'Minimum searches for alert';

  @override
  String get bizAiSaveThreshold => 'Save Threshold';

  @override
  String get bizAiReset => 'Reset';

  @override
  String get bizAiNoAlerts => 'No alerts';

  @override
  String bizAiAlertCount(int count) {
    return '$count alerts';
  }

  @override
  String bizAiMinutesAgo(int minutes) {
    return '$minutes min ago';
  }

  @override
  String bizAiHoursAgo(int hours) {
    return '$hours hours ago';
  }

  @override
  String bizAiDaysAgo(int days) {
    return '$days days ago';
  }

  @override
  String get tabProfile => 'Profile';

  @override
  String get searchPlaceholder => 'Search for a professional, service...';

  @override
  String get searchTitle => 'Search';

  @override
  String get discoverCategories => 'Discover Categories';

  @override
  String get confirm => 'Confirm';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get submit => 'Submit';

  @override
  String get next => 'Next';

  @override
  String get back => 'Back';

  @override
  String get delete => 'Delete';

  @override
  String get currencySymbol => '₪';

  @override
  String get statusPaidEscrow => 'Pending Approval';

  @override
  String get statusExpertCompleted => 'Completed — Awaiting Your Approval';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get statusDispute => 'In Dispute';

  @override
  String get statusPendingPayment => 'Pending Payment';

  @override
  String get profileCustomer => 'Customer';

  @override
  String get profileProvider => 'Service Provider';

  @override
  String get profileOrders => 'Orders';

  @override
  String get profileRating => 'Rating';

  @override
  String get profileReviews => 'Reviews';

  @override
  String get reviewsPlaceholder => 'Tell us about your experience...';

  @override
  String get reviewSubmit => 'Submit Review';

  @override
  String get ratingLabel => 'Rate the Service';

  @override
  String get walletBalance => 'Balance';

  @override
  String get openChat => 'Open Chat';

  @override
  String get quickRequest => 'Quick Request';

  @override
  String get trendingBadge => 'Trending';

  @override
  String get isCurrentRtl => 'false';

  @override
  String get taxDeclarationText => 'I declare sole responsibility for tax reporting as required by law.';

  @override
  String get loginTitle => 'Login';

  @override
  String get loginSubtitle => 'Sign in to your account';

  @override
  String get errorGenericLogin => 'Login error';

  @override
  String get subCategoryPrompt => 'Choose a sub-category';

  @override
  String get emptyActivityTitle => 'No activity';

  @override
  String get emptyActivityCta => 'Get started';

  @override
  String get errorNetworkTitle => 'Network Error';

  @override
  String get errorNetworkBody => 'Check your internet connection';

  @override
  String get errorProfileLoad => 'Error loading profile';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get signupButton => 'Sign Up';

  @override
  String get tosAgree => 'I agree to the Terms of Service';

  @override
  String get tosTitle => 'Terms of Service';

  @override
  String get tosVersion => 'Version 1.0';

  @override
  String get urgentCustomerLabel => 'Urgent Service';

  @override
  String get urgentProviderLabel => 'Urgent Opportunities';

  @override
  String get urgentOpenButton => 'Open';

  @override
  String get walletMinWithdraw => 'Minimum withdrawal';

  @override
  String get withdrawalPending => 'Withdrawal pending';

  @override
  String get withdrawFunds => 'Withdraw Funds';

  @override
  String onboardingError(String error) {
    return 'Error: $error';
  }

  @override
  String onboardingUploadError(String error) {
    return 'Upload error: $error';
  }

  @override
  String get onboardingWelcome => 'Welcome!';

  @override
  String get availabilityUpdated => 'Availability updated';

  @override
  String get bizAiRecruitNow => 'Recruit Now';

  @override
  String get chatEmptyState => 'No messages yet';

  @override
  String get chatLastMessageDefault => 'No last message';

  @override
  String get chatSearchHint => 'Search chats...';

  @override
  String get chatUserDefault => 'User';

  @override
  String get deleteChatConfirm => 'Confirm';

  @override
  String get deleteChatContent => 'Are you sure you want to delete this chat?';

  @override
  String get deleteChatSuccess => 'Chat deleted successfully';

  @override
  String get deleteChatTitle => 'Delete Chat';

  @override
  String get disputeActionsSection => 'Actions';

  @override
  String get disputeAdminNote => 'Admin Note';

  @override
  String get disputeAdminNoteHint => 'Add a note (optional)';

  @override
  String get disputeArbitrationCenter => 'Arbitration Center';

  @override
  String get disputeChatHistory => 'Chat History';

  @override
  String get disputeDescription => 'Description';

  @override
  String get disputeEmptySubtitle => 'No open disputes at this time';

  @override
  String get disputeEmptyTitle => 'No Disputes';

  @override
  String get disputeHint => 'Describe the issue in detail';

  @override
  String get disputeIdPrefix => 'Dispute #';

  @override
  String get disputeIrreversible => 'This action cannot be undone';

  @override
  String get disputeLockedEscrow => 'Locked in Escrow';

  @override
  String get disputeLockedSuffix => '₪';

  @override
  String get disputeNoChatId => 'No chat ID';

  @override
  String get disputeNoMessages => 'No messages';

  @override
  String get disputeNoReason => 'No reason provided';

  @override
  String get disputeOpenDisputes => 'Open Disputes';

  @override
  String get disputePartiesSection => 'Parties';

  @override
  String get disputePartyProvider => 'the provider';

  @override
  String get disputeReasonSection => 'Dispute Reason';

  @override
  String get disputeRefundLabel => 'Refund';

  @override
  String get disputeReleaseLabel => 'Release Payment';

  @override
  String get disputeResolving => 'Processing...';

  @override
  String get disputeSplitLabel => 'Split';

  @override
  String get disputeSystemSender => 'System';

  @override
  String get disputeTapForDetails => 'Tap for details';

  @override
  String get disputeTitle => 'Dispute';

  @override
  String get editProfileTitle => 'Edit Profile';

  @override
  String get helpCenterInputHint => 'Write your question here...';

  @override
  String get logoutButton => 'Log Out';

  @override
  String get markAllReadSuccess => 'All notifications marked as read';

  @override
  String get markedDoneSuccess => 'Marked as done successfully';

  @override
  String get noCategoriesYet => 'No categories yet';

  @override
  String get notifClearAll => 'Clear All';

  @override
  String get notifEmptySubtitle => 'You have no new notifications';

  @override
  String get notifEmptyTitle => 'No Notifications';

  @override
  String get notifOpen => 'Open';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get oppNotifTitle => 'New Interest';

  @override
  String get pendingCatsApprove => 'Approve';

  @override
  String get pendingCatsEmptySubtitle => 'No pending category requests';

  @override
  String get pendingCatsEmptyTitle => 'No Requests';

  @override
  String get pendingCatsImagePrompt => 'Upload category image';

  @override
  String get pendingCatsProviderDesc => 'Provider description';

  @override
  String get pendingCatsReject => 'Reject';

  @override
  String get pendingCatsSectionPending => 'Pending';

  @override
  String get pendingCatsSectionReviewed => 'Reviewed';

  @override
  String get pendingCatsStatusApproved => 'Approved';

  @override
  String get pendingCatsStatusRejected => 'Rejected';

  @override
  String get pendingCatsTitle => 'Category Requests';

  @override
  String get pendingCatsAiReason => 'AI Reason';

  @override
  String get profileLoadError => 'Error loading profile';

  @override
  String get requestsBestValue => 'Best Value';

  @override
  String get requestsFastResponse => 'Fast Response';

  @override
  String get requestsInterestedTitle => 'Interested';

  @override
  String get requestsNoInterested => 'No one interested yet';

  @override
  String get requestsTitle => 'Requests';

  @override
  String get submitDispute => 'Submit Dispute';

  @override
  String get systemWalletFeePanel => 'Platform Fee';

  @override
  String get systemWalletInvalidNumber => 'Invalid number';

  @override
  String get systemWalletUpdateFee => 'Update Fee';

  @override
  String get tosAcceptButton => 'I Agree';

  @override
  String get tosBindingNotice => 'By clicking confirm, you agree to the Terms of Service';

  @override
  String get tosFullTitle => 'Full Terms of Service';

  @override
  String get tosLastUpdated => 'Last Updated';

  @override
  String get withdrawExistingCert => 'Existing certificate';

  @override
  String get withdrawUploadError => 'Error uploading file';

  @override
  String get xpAddAction => 'Add';

  @override
  String get xpAddEventButton => 'Add Event';

  @override
  String get xpAddEventTitle => 'Add XP Event';

  @override
  String get xpDeleteEventTitle => 'Delete Event';

  @override
  String get xpEditEventTitle => 'Edit XP Event';

  @override
  String get xpEventAdded => 'Event added successfully';

  @override
  String get xpEventDeleted => 'Event deleted successfully';

  @override
  String get xpEventUpdated => 'Event updated successfully';

  @override
  String get xpEventsEmpty => 'No XP events';

  @override
  String get xpEventsSection => 'XP Events';

  @override
  String get xpFieldDesc => 'Description';

  @override
  String get xpFieldId => 'ID';

  @override
  String get xpFieldIdHint => 'Enter a unique ID';

  @override
  String get xpFieldName => 'Name';

  @override
  String get xpFieldPoints => 'Points';

  @override
  String get xpLevelsError => 'Error saving levels';

  @override
  String get xpLevelsSaved => 'Levels saved successfully';

  @override
  String get xpLevelsSubtitle => 'Set the XP thresholds for each level';

  @override
  String get xpLevelsTitle => 'XP Levels';

  @override
  String get xpManagerSubtitle => 'Manage XP events and levels';

  @override
  String get xpManagerTitle => 'XP Manager';

  @override
  String get xpReservedId => 'Reserved ID';

  @override
  String get xpSaveAction => 'Save';

  @override
  String get xpSaveLevels => 'Save Levels';

  @override
  String get xpTooltipDelete => 'Delete';

  @override
  String get xpTooltipEdit => 'Edit';

  @override
  String bizAiThresholdUpdated(int value) {
    return 'Threshold updated to $value';
  }

  @override
  String disputeErrorPrefix(String error) {
    return 'Error: $error';
  }

  @override
  String disputeExistingNote(String note) {
    return 'Admin note: $note';
  }

  @override
  String disputeOpenedAt(String date) {
    return 'Opened on $date';
  }

  @override
  String disputeRefundSublabel(String amount) {
    return 'Full refund — $amount ₪ to customer';
  }

  @override
  String disputeReleaseSublabel(String amount) {
    return 'Release — $amount ₪ to provider';
  }

  @override
  String disputeSplitSublabel(String amount) {
    return 'Split — $amount ₪ to each side';
  }

  @override
  String editCategorySaveError(String error) {
    return 'Error saving: $error';
  }

  @override
  String oppInterestChatMessage(String providerName, String description) {
    return 'Hi, I\'m $providerName and I\'d love to help: $description';
  }

  @override
  String oppNotifBody(String providerName) {
    return '$providerName is interested in your opportunity';
  }

  @override
  String pendingCatsErrorPrefix(String error) {
    return 'Error: $error';
  }

  @override
  String pendingCatsSubCategory(String name) {
    return 'Sub-category: $name';
  }

  @override
  String xpDeleteEventConfirm(String name) {
    return 'Delete $name?';
  }

  @override
  String xpErrorPrefix(String error) {
    return 'Error: $error';
  }

  @override
  String xpEventsCount(int count) {
    return '$count events';
  }
}
