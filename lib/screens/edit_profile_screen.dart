import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/app_localizations.dart';
import '../utils/input_sanitizer.dart';
import '../utils/error_mapper.dart';
import 'price_settings_screen.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import '../services/category_service.dart';
import '../services/cancellation_policy_service.dart';
import '../widgets/category_specs_widget.dart';
import '../services/cached_readers.dart';
import '../constants/quick_tags.dart';
import '../widgets/category_tags_selector.dart';
import '../widgets/price_list_widget.dart';
import '../services/provider_listing_service.dart';
import '../services/view_mode_service.dart';
import '../services/private_data_service.dart';
import '../main.dart' show PhoneCollectionScreen;
import '../utils/safe_image_provider.dart';
import '../features/pet_stay/models/dog_profile.dart';
import '../features/pet_stay/services/dog_profile_service.dart';
import '../features/pet_stay/screens/dog_profile_builder_screen.dart';
import '../features/pet_stay/screens/dog_profile_list_screen.dart';
import 'identity_onboarding_screen.dart';
import '../models/massage_profile.dart';
import '../models/pest_control_profile.dart';
import '../models/delivery_profile.dart';
import '../models/cleaning_profile.dart';
import '../models/handyman_profile.dart';
import '../models/fitness_trainer_profile.dart';
import '../models/babysitter_profile.dart';
import '../models/motorcycle_tow_profile.dart';
import 'massage/massage_settings_block.dart';
import 'pest_control/pest_control_settings_block.dart';
import 'delivery/delivery_settings_block.dart';
import 'cleaning/cleaning_settings_block.dart';
import 'handyman/handyman_settings_block.dart';
import 'fitness_trainer/fitness_trainer_settings_block.dart';
import 'babysitter/babysitter_settings_block.dart';
import 'motorcycle_tow/motorcycle_tow_settings_block.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  /// v10.3.2: Optional listingId — when provided, loads identity-specific
  /// fields (serviceType, price, gallery, aboutMe) from that listing doc
  /// instead of the user doc. Shared fields (name, phone, image) always
  /// come from the user doc.
  final String? listingId;

  const EditProfileScreen({
    super.key,
    required this.userData,
    this.listingId,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _aboutController;
  late TextEditingController _priceController;
  late TextEditingController _taxIdController;
  late TextEditingController _videoUrlController;

  /// True when the user signed in with Google or Apple — in that case the
  /// email comes from Firebase Auth (authoritative) and the field renders
  /// read-only. Phone-OTP signups can still type/edit a email by hand.
  bool _emailLockedFromAuth = false;

  String? _selectedMainCatId; // doc ID of selected main category
  String? _selectedSubCatId; // doc ID of selected sub-category (nullable)
  List<Map<String, dynamic>> _mainCategories = [];
  List<Map<String, dynamic>> _subCategories = []; // subs for selected main
  List<SchemaField> _categorySchema = []; // v1 legacy — kept for fallback
  ServiceSchema _serviceSchema = ServiceSchema.empty(); // v2 — full schema
  Map<String, dynamic> _categoryDetails = {};
  Map<String, dynamic> _priceList = {};

  // `_responseTimeMinutes` (manual chip selector) was removed — replaced by
  // the auto-computed `avgResponseMinutes` field (set by the
  // `computeResponseTimeOnMessage` CF from real chat timestamps).
  String _cancellationPolicy = 'flexible';
  Set<String> _selectedQuickTags = {};
  Set<String> _selectedCategoryTags = {};

  /// Weekly working hours — keys are weekday indices (0=Sunday..6=Saturday),
  /// values are `{"from": "09:00", "to": "17:00"}`.
  /// Empty map = "all hours" (legacy behaviour — no restrictions).
  Map<int, Map<String, String>> _workingHours = {};

  MassageProfile _massageProfile = const MassageProfile();
  PestControlProfile _pestControlProfile = const PestControlProfile();
  DeliveryProfile _deliveryProfile = const DeliveryProfile();
  CleaningProfile _cleaningProfile = const CleaningProfile();
  HandymanProfile _handymanProfile = const HandymanProfile();
  FitnessTrainerProfile _fitnessTrainerProfile = const FitnessTrainerProfile();
  BabysitterProfile _babysitterProfile = const BabysitterProfile();
  MotorcycleTowProfile _motorcycleTowProfile = const MotorcycleTowProfile();

  static List<String> _dayNames(BuildContext ctx) {
    final l = AppLocalizations.of(ctx);
    return [l.editDaySunday, l.editDayMonday, l.editDayTuesday, l.editDayWednesday, l.editDayThursday, l.editDayFriday, l.editDaySaturday];
  }
  static const _kHourOptions = [
    '07:00', '08:00', '09:00', '10:00', '11:00', '12:00',
    '13:00', '14:00', '15:00', '16:00', '17:00', '18:00',
    '19:00', '20:00', '21:00', '22:00',
  ];

  String? _profileImageUrl;
  String _phoneDisplay = ''; // read-only — shown from Auth / Firestore
  List<dynamic> _galleryImages = [];
  bool _isLoading = false;

  String? _verificationVideoUrl;
  bool _videoUploadInProgress = false;
  double _videoUploadProgress = 0.0;

  String? _certificationImage;

  bool _isCustomer = false;
  bool _isProvider = false;
  bool _isVolunteer = false;
  bool _isPendingExpert = false;

  List<Map<String, dynamic>> _categories = [];
  late StreamSubscription<List<Map<String, dynamic>>> _categorySub;
  // True once the CategoryService.stream() has delivered at least one
  // snapshot (or hit `onError`). Used to swap the perpetual spinner for
  // a friendly fallback state (read-only saved-selection card or empty
  // hint), per the §10 stream-error-resilience rule.
  bool _categoriesStreamFired = false;

  // v10.3.2: Active listing tracking
  String? _activeListingId;
  // ignore: unused_field
  int _activeIdentityIndex = 0;
  String _activeListingServiceType = '';
  List<Map<String, dynamic>> _allListings = [];

  @override
  void initState() {
    super.initState();
    _activeListingId = widget.listingId;
    _loadListingsAndApply();
    _nameController = TextEditingController(text: widget.userData['name']);
    _aboutController = TextEditingController(
      text: widget.userData['aboutMe'] ?? widget.userData['bio'] ?? "",
    );
    _priceController = TextEditingController(
      text: (widget.userData['pricePerHour'] ?? "0").toString(),
    );
    _taxIdController = TextEditingController(
      text: widget.userData['taxId'] as String? ?? '',
    );
    _videoUrlController = TextEditingController(
      text: widget.userData['videoUrl'] as String? ?? '',
    );
    _galleryImages = List.from(widget.userData['gallery'] ?? []);
    _categoryDetails = Map<String, dynamic>.from(
      widget.userData['categoryDetails'] as Map? ?? {},
    );
    _priceList = Map<String, dynamic>.from(
      widget.userData['priceList'] as Map? ?? {},
    );
    _selectedQuickTags = Set<String>.from(
      (widget.userData['quickTags'] as List? ?? []).cast<String>(),
    );
    _selectedCategoryTags = Set<String>.from(
      (widget.userData['categoryTags'] as List? ?? []).cast<String>(),
    );
    _profileImageUrl = widget.userData['profileImage'];
    _verificationVideoUrl = widget.userData['verificationVideoUrl'] as String?;
    _certificationImage = widget.userData['certificationImage'] as String?;

    // Phone: prefer Firestore value, fall back to Firebase Auth phoneNumber
    _phoneDisplay = (widget.userData['phone'] as String? ?? '').trim();
    if (_phoneDisplay.isEmpty) {
      _phoneDisplay = (widget.userData['phoneNumber'] as String? ?? '').trim();
    }
    if (_phoneDisplay.isEmpty) {
      _phoneDisplay = FirebaseAuth.instance.currentUser?.phoneNumber ?? '';
    }

    // Email: 3-tier resolution
    //   1. Firebase Auth email (authoritative when signed in via Google/Apple)
    //   2. Firestore-stored email (the user's last saved value)
    //   3. Empty (phone-OTP user that hasn't filled email yet)
    //
    // Detect Google/Apple via providerData. When present, the field is locked
    // (the auth provider is the source of truth) AND we autosave the value to
    // Firestore + private/identity if Firestore is missing or out-of-sync.
    final authUser = FirebaseAuth.instance.currentUser;
    final firestoreEmail = (widget.userData['email'] as String? ?? '').trim();
    final providerIds =
        authUser?.providerData.map((p) => p.providerId).toList() ?? const [];
    final isSocialSignIn = providerIds.contains('google.com') ||
        providerIds.contains('apple.com');
    final authEmail = (authUser?.email ?? '').trim();

    String initialEmail;
    if (isSocialSignIn && authEmail.isNotEmpty) {
      initialEmail = authEmail;
      _emailLockedFromAuth = true;
      // Auto-sync to Firestore the FIRST time we see a Google/Apple user
      // whose Firestore record is empty or outdated. Fire-and-forget.
      if (firestoreEmail != authEmail && authUser != null) {
        // ignore: discarded_futures
        _autoSaveSocialEmail(authUser.uid, authEmail);
      }
    } else {
      initialEmail = firestoreEmail;
      _emailLockedFromAuth = false;
    }
    _emailController = TextEditingController(text: initialEmail);

    _isCustomer = widget.userData['isCustomer'] ?? true;
    _isProvider = widget.userData['isProvider'] ?? false;
    _isVolunteer = widget.userData['isVolunteer'] ?? false;
    _isPendingExpert = widget.userData['isPendingExpert'] ?? false;
    // `responseTimeMinutes` no longer hydrated — replaced by auto-computed
    // `avgResponseMinutes` (see CF `computeResponseTimeOnMessage`).
    _cancellationPolicy =
        widget.userData['cancellationPolicy'] as String? ?? 'flexible';

    // Load working hours from Firestore (Map<String, dynamic> → Map<int, Map<String, String>>)
    final rawHours = widget.userData['workingHours'] as Map<String, dynamic>? ?? {};
    _workingHours = {};
    for (final entry in rawHours.entries) {
      final day = int.tryParse(entry.key);
      if (day != null && entry.value is Map) {
        final m = entry.value as Map;
        _workingHours[day] = {
          'from': m['from']?.toString() ?? '09:00',
          'to':   m['to']?.toString()   ?? '17:00',
        };
      }
    }

    final rawMassage = widget.userData['massageProfile'] as Map<String, dynamic>?;
    if (rawMassage != null) {
      _massageProfile = MassageProfile.fromMap(rawMassage);
    }
    final rawPest = widget.userData['pestControlProfile'] as Map<String, dynamic>?;
    if (rawPest != null) {
      _pestControlProfile = PestControlProfile.fromMap(rawPest);
    }
    final rawDelivery = widget.userData['deliveryProfile'] as Map<String, dynamic>?;
    if (rawDelivery != null) {
      _deliveryProfile = DeliveryProfile.fromMap(rawDelivery);
    }
    final rawHandyman = widget.userData['handymanProfile'] as Map<String, dynamic>?;
    if (rawHandyman != null) {
      _handymanProfile = HandymanProfile.fromMap(rawHandyman);
    }
    final rawCleaning = widget.userData['cleaningProfile'] as Map<String, dynamic>?;
    if (rawCleaning != null) {
      _cleaningProfile = CleaningProfile.fromMap(rawCleaning);
    }
    final rawFitness = widget.userData['fitnessTrainerProfile'] as Map<String, dynamic>?;
    if (rawFitness != null) {
      _fitnessTrainerProfile = FitnessTrainerProfile.fromMap(rawFitness);
    }
    final rawBabysitter = widget.userData['babysitterProfile'] as Map<String, dynamic>?;
    if (rawBabysitter != null) {
      _babysitterProfile = BabysitterProfile.fromMap(rawBabysitter);
    }
    final rawMotorcycleTow =
        widget.userData['motorcycleTowProfile'] as Map<String, dynamic>?;
    if (rawMotorcycleTow != null) {
      _motorcycleTowProfile = MotorcycleTowProfile.fromMap(rawMotorcycleTow);
    }

    // HARD TIMEOUT — safety net.
    Future.delayed(const Duration(seconds: 6), () {
      if (!mounted) return;
      if (!_categoriesStreamFired) {
        debugPrint(
            '[EditProfile] Categories stream did not fire in 6s — forcing fallback');
        setState(() => _categoriesStreamFired = true);
      }
    });

    // ONE-SHOT FAST FETCH — guarantees the dropdowns have data ASAP.
    // The .snapshots() stream below provides live updates, but its first
    // snapshot can lag (post-nuclear-purge cold network, IndexedDB-less
    // Firestore web reads, etc.). A direct .get() typically completes in
    // <500ms and gives us a populated dropdown immediately. The stream
    // takes over for any subsequent updates.
    // ignore: discarded_futures
    _oneshotLoadCategories();

    _categorySub =
        CategoryService.stream().listen(_applyCategoriesSnapshot, onError: (e) {
      if (!mounted) return;
      debugPrint('[EditProfile] CategoryService stream error: $e');
      if (!_categoriesStreamFired) {
        setState(() => _categoriesStreamFired = true);
      }
    });
  }

  /// One-shot fetch of categories — backup for the snapshot stream.
  Future<void> _oneshotLoadCategories() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('categories')
          .limit(100)
          .get()
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      final cats =
          snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      if (cats.isEmpty) return;
      _applyCategoriesSnapshot(cats);
      debugPrint(
          '[EditProfile] One-shot categories loaded: ${cats.length} docs');
    } catch (e) {
      debugPrint('[EditProfile] One-shot categories fetch failed: $e');
      // Don't flip _categoriesStreamFired here — let the snapshot stream
      // OR the 6s timeout do it. We want to keep the stream's authoritative
      // result winning if it eventually arrives.
    }
  }

  /// Shared logic for processing a categories snapshot (used by both the
  /// snapshot stream and the one-shot get). Idempotent — safe to call
  /// multiple times.
  void _applyCategoriesSnapshot(List<Map<String, dynamic>> cats) {
    if (!mounted) return;
    if (!_categoriesStreamFired) _categoriesStreamFired = true;
    final mains =
        cats.where((c) => (c['parentId'] as String? ?? '').isEmpty).toList();
    // v13.3.0: prefer the active listing's serviceType over the user
    // doc's — ensures dual-identity providers see the right category
    // resolved when they switch identities.
    final serviceType = _activeListingServiceType.isNotEmpty
        ? _activeListingServiceType
        : widget.userData['serviceType'] as String?;

    // Resolve existing serviceType into main-category ID + optional sub-category ID
    final subMatch = cats.firstWhere(
      (c) =>
          c['name'] == serviceType &&
          (c['parentId'] as String? ?? '').isNotEmpty,
      orElse: () => <String, dynamic>{},
    );
    String? mainId, subId;
    if (subMatch.isNotEmpty) {
      subId = subMatch['id'] as String?;
      mainId = subMatch['parentId'] as String?;
    } else {
      final mainMatch = mains.firstWhere(
        (c) => c['name'] == serviceType,
        orElse: () => <String, dynamic>{},
      );
      mainId = mainMatch.isNotEmpty ? mainMatch['id'] as String? : null;
      // Self-heal: providers who registered through the buggy
      // provider_registration_screen path landed with `serviceType`
      // == parent name and `subCategory` filled separately.
      if (mainId != null) {
        final savedSub =
            (widget.userData['subCategory'] as String? ?? '').trim();
        if (savedSub.isNotEmpty) {
          final fallbackSub = cats.firstWhere(
            (c) =>
                c['name'] == savedSub &&
                (c['parentId'] as String? ?? '') == mainId,
            orElse: () => <String, dynamic>{},
          );
          if (fallbackSub.isNotEmpty) {
            subId = fallbackSub['id'] as String?;
          }
        }
      }
    }

    final subs = mainId != null
        ? cats.where((c) => c['parentId'] == mainId).toList()
        : <Map<String, dynamic>>[];

    setState(() {
      _categories = cats;
      _mainCategories = mains;
      _selectedMainCatId = _selectedMainCatId ?? mainId;
      _subCategories = subs;
      _selectedSubCatId = _selectedSubCatId ?? subId;
    });
    // Load v2 schema for the resolved category.
    final resolvedCatName = widget.userData['serviceType'] as String? ?? '';
    if (resolvedCatName.isNotEmpty && _serviceSchema.isEmpty) {
      _loadV2SchemaFor(resolvedCatName);
    }
  }

  /// Loads the v2 [ServiceSchema] for the given category name and merges
  /// its defaults into provider state. If the provider has not yet picked
  /// a cancellation policy, the schema's `defaultPolicy` is auto-selected.
  Future<void> _loadV2SchemaFor(String categoryName) async {
    if (categoryName.trim().isEmpty) return;
    try {
      // §61: cached read — 30 min TTL.
      final schema = await CachedReaders.serviceSchemaForCategory(categoryName);
      if (!mounted) return;
      setState(() {
        _serviceSchema = schema;
        // Keep the v1 list in sync for any legacy display widget
        _categorySchema = schema.fields;
        // Auto-apply default policy ONLY when the provider hasn't set one
        // (i.e. they're a brand-new account or the field is null/empty).
        final hasPolicy = (widget.userData['cancellationPolicy'] as String?)
                ?.isNotEmpty ??
            false;
        if (!hasPolicy && schema.defaultPolicy.isNotEmpty) {
          _cancellationPolicy = schema.defaultPolicy;
        }
      });
    } catch (_) {
      // Schema is optional — silent fallback to empty
    }
  }

  @override
  void dispose() {
    _categorySub.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _aboutController.dispose();
    _priceController.dispose();
    _taxIdController.dispose();
    _videoUrlController.dispose();
    super.dispose();
  }

  /// One-shot autosave for Google/Apple users whose email isn't yet
  /// mirrored in Firestore. Writes to BOTH the main user doc AND
  /// `private/identity` per the dual-write rule (CLAUDE.md §11).
  /// Fire-and-forget — silent failure is OK because the next save tap
  /// will re-attempt via the regular `_saveProfile` path.
  Future<void> _autoSaveSocialEmail(String uid, String email) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'email': email}, SetOptions(merge: true));
      await PrivateDataService.writeContactData(uid, email: email);
    } catch (_) {
      // Silent — user-facing save flow will retry on next "save" tap.
    }
  }

  /// v10.3.2: Load all listings for this user and apply identity-specific
  /// fields from the active listing (overrides the user-doc defaults).
  Future<void> _loadListingsAndApply() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final listings = await ProviderListingService.getListings(uid);
      if (!mounted) return;
      _allListings = listings;

      // Determine which listing is active
      Map<String, dynamic>? activeListing;
      if (_activeListingId != null) {
        activeListing = listings.firstWhere(
          (l) => l['listingId'] == _activeListingId,
          orElse: () => <String, dynamic>{},
        );
        if (activeListing.isEmpty) activeListing = null;
      }
      // Default to primary listing if no specific one requested
      activeListing ??= listings.isNotEmpty ? listings.first : null;

      if (activeListing != null) {
        _activeListingId = activeListing['listingId'] as String?;
        _activeIdentityIndex = (activeListing['identityIndex'] as num?)?.toInt() ?? 0;

        // Override identity-specific fields from the listing doc.
        // v13.3.0: apply ALL identity-scoped fields (including serviceType +
        // category selection) so switching between identities actually
        // flips the fields shown below the identity picker.
        final about = activeListing['aboutMe'] as String? ?? '';
        final price = (activeListing['pricePerHour'] as num?)?.toDouble() ?? 0;
        final gallery = List<dynamic>.from(activeListing['gallery'] ?? []);
        final catDetails = Map<String, dynamic>.from(activeListing['categoryDetails'] as Map? ?? {});
        final prices = Map<String, dynamic>.from(activeListing['priceList'] as Map? ?? {});
        final tags = Set<String>.from((activeListing['quickTags'] as List? ?? []).cast<String>());
        final catTags = Set<String>.from((activeListing['categoryTags'] as List? ?? []).cast<String>());
        final listingServiceType = (activeListing['serviceType'] as String? ?? '').trim();
        _activeListingServiceType = listingServiceType;

        setState(() {
          // aboutMe / price / gallery / details always follow the listing
          _aboutController.text = about;
          if (price > 0) _priceController.text = price.toString();
          _galleryImages = gallery;
          _categoryDetails = catDetails;
          _priceList = prices;
          _selectedQuickTags = tags;
          _selectedCategoryTags = catTags;
        });

        // Re-resolve main/sub category IDs against the listing's serviceType.
        if (listingServiceType.isNotEmpty && _categories.isNotEmpty) {
          _applyListingCategoryFromServiceType(listingServiceType);
        }
      }
    } catch (e) {
      debugPrint('[EditProfile] Listing load error: $e');
    }
  }

  /// Resolves listing's serviceType → (mainCatId, subCatId) against the
  /// loaded categories, and re-loads the v2 schema so the pricing fields
  /// re-render with the correct category-specific UI.
  bool _isMassageSubCategory() {
    if (_selectedSubCatId == null) return false;
    final subName = _subCategories
        .where((c) => c['id'] == _selectedSubCatId)
        .map((c) => c['name'] as String? ?? '')
        .firstOrNull ?? '';
    return isMassageCategory(subName);
  }

  bool _isPestControlSubCategory() {
    if (_selectedSubCatId == null) return false;
    final subName = _subCategories
        .where((c) => c['id'] == _selectedSubCatId)
        .map((c) => c['name'] as String? ?? '')
        .firstOrNull ?? '';
    return isPestControlCategory(subName);
  }

  bool _isDeliverySubCategory() {
    if (_selectedSubCatId == null) return false;
    final subName = _subCategories
        .where((c) => c['id'] == _selectedSubCatId)
        .map((c) => c['name'] as String? ?? '')
        .firstOrNull ?? '';
    return isDeliveryCategory(subName);
  }

  bool _isCleaningSubCategory() {
    if (_selectedSubCatId == null) return false;
    final subName = _subCategories
        .where((c) => c['id'] == _selectedSubCatId)
        .map((c) => c['name'] as String? ?? '')
        .firstOrNull ?? '';
    return isCleaningCategory(subName);
  }

  bool _isBabysitterSubCategory() {
    if (_selectedSubCatId == null) return false;
    final subName = _subCategories
        .where((c) => c['id'] == _selectedSubCatId)
        .map((c) => c['name'] as String? ?? '')
        .firstOrNull ?? '';
    return isBabysitterCategory(subName);
  }

  bool _isHandymanSubCategory() {
    if (_selectedSubCatId == null) return false;
    final subName = _subCategories
        .where((c) => c['id'] == _selectedSubCatId)
        .map((c) => c['name'] as String? ?? '')
        .firstOrNull ?? '';
    return isHandymanCategory(subName);
  }

  bool _isFitnessTrainerSubCategory() {
    if (_selectedSubCatId == null) return false;
    final subName = _subCategories
        .where((c) => c['id'] == _selectedSubCatId)
        .map((c) => c['name'] as String? ?? '')
        .firstOrNull ?? '';
    return isFitnessTrainerCategory(subName);
  }

  bool _isMotorcycleTowingSubCategory() {
    if (_selectedSubCatId == null) return false;
    final subName = _subCategories
        .where((c) => c['id'] == _selectedSubCatId)
        .map((c) => c['name'] as String? ?? '')
        .firstOrNull ?? '';
    return isMotorcycleTowingCategory(subName);
  }

  void _applyListingCategoryFromServiceType(String serviceType) {
    final subMatch = _categories.firstWhere(
      (c) =>
          c['name'] == serviceType &&
          (c['parentId'] as String? ?? '').isNotEmpty,
      orElse: () => <String, dynamic>{},
    );
    String? mainId;
    String? subId;
    if (subMatch.isNotEmpty) {
      subId = subMatch['id'] as String?;
      mainId = subMatch['parentId'] as String?;
    } else {
      final mainMatch = _categories.firstWhere(
        (c) =>
            c['name'] == serviceType &&
            (c['parentId'] as String? ?? '').isEmpty,
        orElse: () => <String, dynamic>{},
      );
      mainId = mainMatch.isNotEmpty ? mainMatch['id'] as String? : null;
    }
    final subs = mainId != null
        ? _categories.where((c) => c['parentId'] == mainId).toList()
        : <Map<String, dynamic>>[];
    setState(() {
      _selectedMainCatId = mainId;
      _subCategories = subs;
      _selectedSubCatId = subId;
      _serviceSchema = ServiceSchema.empty();
      _categorySchema = [];
    });
    _loadV2SchemaFor(serviceType);
  }

  Future<void> _pickProfileImage() async {
    // Wrapped in try/catch (Law 10 §9b) — image_picker can throw on web
    // (HEIC images on iOS Safari, file-permission denials, focus-loss),
    // and a silent throw left users tapping the avatar with no feedback.
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 300,
        maxHeight: 300,
        imageQuality: 50,
      );
      if (image == null) return; // user cancelled

      final Uint8List imageBytes = await image.readAsBytes();
      // image_picker returns JPEG by default; claim the correct MIME so
      // downstream decoders that strict-check the data URI don't reject.
      final encoded = base64Encode(imageBytes);
      // Hard guard against the Firestore 1 MB document size limit. With
      // 300×300 + quality 50 the encoded blob is normally ~10-20 KB, but
      // raw web uploads on some Safari builds skip the resize step.
      if (encoded.length > 800 * 1024) {
        if (!mounted) return;
        messenger.showSnackBar(const SnackBar(
          content: Text('התמונה גדולה מדי — בחר/י תמונה קטנה יותר'),
          backgroundColor: Color(0xFFEF4444),
        ));
        return;
      }
      if (!mounted) return;
      setState(() {
        _profileImageUrl = 'data:image/jpeg;base64,$encoded';
      });
    } catch (e) {
      if (!mounted) return;
      ErrorMapper.show(context, e);
    }
  }

  Future<void> _pickAndCompressGalleryImage() async {
    // Gallery images are stored as base64 strings inside the Firestore user
    // document (1 MB hard limit).  Without compression, a single 600×600 JPEG
    // at default quality can reach 200-500 KB after base64 encoding.
    // imageQuality: 60 keeps each image under ~50 KB, giving comfortable
    // headroom for up to ~15 photos before the limit is approached.
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 60, // ← JPEG compression; prevents Firestore 1 MB overflow
    );

    if (image != null) {
      setState(() => _isLoading = true);
      try {
        final Uint8List imageBytes = await image.readAsBytes();
        final String encoded = base64Encode(imageBytes);

        // Sanity-check: warn if a single image is still unusually large
        // (e.g. a PNG screenshot that imageQuality cannot compress further).
        if (encoded.length > 150000) {
          debugPrint(
            'EditProfile: gallery image is ${encoded.length ~/ 1024} KB '
            'after compression — consider a lower-res source.',
          );
        }

        if (mounted) setState(() => _galleryImages.add(encoded));
      } catch (e) {
        if (mounted) ErrorMapper.show(context, e);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickCertificationImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 65,
    );
    if (image != null) {
      setState(() => _isLoading = true);
      try {
        final Uint8List imageBytes = await image.readAsBytes();
        final String encoded = base64Encode(imageBytes);
        if (mounted) setState(() => _certificationImage = encoded);
      } catch (e) {
        if (mounted) ErrorMapper.show(context, e);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickAndUploadVerificationVideo() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ImagePicker picker = ImagePicker();
    final XFile? video = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 60),
    );
    if (video == null) return;

    setState(() {
      _videoUploadInProgress = true;
      _videoUploadProgress = 0.0;
    });

    try {
      final ref = FirebaseStorage.instance.ref(
        'users/$uid/verification_video.mp4',
      );
      final bytes = await video.readAsBytes();
      final task = ref.putData(
        bytes,
        SettableMetadata(contentType: 'video/mp4'),
      );

      task.snapshotEvents.listen((snap) {
        if (!mounted) return;
        final progress =
            snap.bytesTransferred /
            (snap.totalBytes == 0 ? 1 : snap.totalBytes);
        setState(() => _videoUploadProgress = progress);
      });

      await task;
      final downloadUrl = await ref.getDownloadURL();

      // Save URL to Firestore immediately; reset verification flag so admin re-approves
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'verificationVideoUrl': downloadUrl,
        'videoVerifiedByAdmin': false,
      });
      // §61 invalidation contract
      CachedReaders.invalidateProvider(uid);

      if (mounted) {
        setState(() => _verificationVideoUrl = downloadUrl);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ הסרטון הועלה בהצלחה! ממתין לאישור מנהל.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).editVideoUploadError(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _videoUploadInProgress = false);
    }
  }

  /// Shows an orange error snackbar and returns false; call `return` after.
  bool _validationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.orange),
    );
    return false;
  }

  Widget _buildHourDropdown(String value, ValueChanged<String> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButton<String>(
        value: _kHourOptions.contains(value) ? value : '09:00',
        underline: const SizedBox.shrink(),
        isDense: true,
        style: const TextStyle(fontSize: 13, color: Colors.black87),
        items: _kHourOptions.map((h) => DropdownMenuItem(
          value: h,
          child: Text(h, style: const TextStyle(fontSize: 13)),
        )).toList(),
        onChanged: (v) { if (v != null) onChanged(v); },
      ),
    );
  }

  Future<void> _saveProfile() async {
    final l10n = AppLocalizations.of(context);

    // ── Sanitize & validate Name ─────────────────────────────────────────────
    final nameResult = InputSanitizer.sanitizeName(
      _nameController.text,
      errForbidden: l10n.validationNameForbidden,
      errTooLong: l10n.validationNameTooLong,
    );
    if (!nameResult.isOk) {
      _validationError(nameResult.error!);
      return;
    }
    final safeName = nameResult.value;
    if (safeName.isEmpty) {
      _validationError(l10n.validationNameRequired);
      return;
    }
    if (safeName.length < 2) {
      _validationError(l10n.validationNameLength);
      return;
    }

    // ── Validate Email ──────────────────────────────────────────────────────
    // Email is OPTIONAL for phone-OTP users (they can leave it blank). When
    // provided, it must look like a real address. Google/Apple users have a
    // locked field whose value comes from Firebase Auth — we still validate
    // for safety, but it should never fail in that path.
    final rawEmail = _emailController.text.trim();
    String? safeEmail;
    if (rawEmail.isNotEmpty) {
      // Permissive RFC-style check — same shape as login_screen / onboarding.
      final ok = RegExp(r"^[\w.\-+]+@[\w\-]+\.[\w\-.]+$").hasMatch(rawEmail);
      if (!ok) {
        _validationError(l10n.errorInvalidEmail);
        return;
      }
      safeEmail = rawEmail.toLowerCase();
    }

    // ── Sanitize & validate About/Bio (provider only) ────────────────────────
    SanitizeResult? aboutResult;
    if (_isProvider) {
      aboutResult = InputSanitizer.sanitizeAbout(
        _aboutController.text,
        errForbidden: l10n.validationAboutForbidden,
        errTooLong: l10n.validationAboutTooLong,
      );
      if (!aboutResult.isOk) {
        _validationError(aboutResult.error!);
        return;
      }
    }

    // ── Sanitize & validate Video URL (provider only) ────────────────────────
    SanitizeResult? videoUrlResult;
    if (_isProvider && _videoUrlController.text.trim().isNotEmpty) {
      videoUrlResult = InputSanitizer.sanitizeUrl(
        _videoUrlController.text,
        errScheme: l10n.validationUrlHttps,
      );
      if (!videoUrlResult.isOk) {
        _validationError(videoUrlResult.error!);
        return;
      }
    }

    // ── Sanitize tax ID (provider only) ─────────────────────────────────────
    SanitizeResult? taxResult;
    if (_isProvider) {
      taxResult = InputSanitizer.sanitizeShortText(
        _taxIdController.text,
        kMaxTaxIdLength,
        errForbidden: l10n.validationFieldForbidden,
      );
      if (!taxResult.isOk) {
        _validationError(taxResult.error!);
        return;
      }
    }

    // ── Role & provider-specific checks ─────────────────────────────────────
    if (!_isCustomer && !_isProvider) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.validationRoleRequired)));
      return;
    }

    if (_isProvider) {
      if (_selectedMainCatId == null) {
        _validationError(l10n.validationCategoryRequired);
        return;
      }
      // The legacy "מחיר לשעה" field is HIDDEN for sub-categories that own
      // their own CSM-driven pricing (motorcycle towing has base price +
      // per-km + night/emergency surcharges declared in its block). If we
      // ran the price validation here for those providers, _priceController
      // would still hold "0" (default init from widget.userData) and the
      // `price <= 0` check would block the save with "המחיר חייב להיות חיובי"
      // — a confusing dead-end since there's no field for the user to fix.
      if (!_isMotorcycleTowingSubCategory()) {
        final price = double.tryParse(_priceController.text.trim());
        if (price == null) {
          _validationError(l10n.validationPriceInvalid);
          return;
        }
        if (price <= 0) {
          _validationError(l10n.validationPricePositive);
          return;
        }
      }

      if (_isMassageSubCategory()) {
        if (_massageProfile.specialties.isEmpty) {
          _validationError('בחרי לפחות סוג טיפול אחד');
          return;
        }
        final locs = _massageProfile.serviceLocations;
        if (!locs.home.enabled && !locs.clinic.enabled) {
          _validationError('בחרי לפחות מיקום אחד (בית או קליניקה)');
          return;
        }
        if (locs.clinic.enabled && locs.clinic.address.trim().isEmpty) {
          _validationError('הזיני כתובת לקליניקה');
          return;
        }
        if (_massageProfile.durations.where((d) => d.enabled).isEmpty) {
          _validationError('בחרי לפחות משך טיפול אחד');
          return;
        }
      }

      if (_isPestControlSubCategory()) {
        if (_pestControlProfile.pestTypes.isEmpty) {
          _validationError('בחר לפחות סוג מזיק אחד');
          return;
        }
        if (_pestControlProfile.treatmentMethods.isEmpty) {
          _validationError('בחר לפחות שיטת טיפול אחת');
          return;
        }
      }

      if (_isDeliverySubCategory()) {
        if (_deliveryProfile.vehicles.isEmpty) {
          _validationError('בחר לפחות רכב אחד פעיל (קטנוע / רכב)');
          return;
        }
        if (_deliveryProfile.deliveryTypes.isEmpty) {
          _validationError('בחר לפחות סוג משלוח אחד');
          return;
        }
      }

      if (_isCleaningSubCategory()) {
        final v = _cleaningProfile.verifications;
        if (!v.idVerified) {
          _validationError('נדרשת תעודת זהות מאומתת');
          return;
        }
        if (!v.backgroundChecked) {
          _validationError('נדרשת בדיקת רקע');
          return;
        }
        if (v.referencesCount < 3) {
          _validationError('נדרשים לפחות 3 ממליצים מאומתים');
          return;
        }
        if (_cleaningProfile.cleaningTypes.isEmpty) {
          _validationError('בחרי לפחות סוג נקיון אחד');
          return;
        }
        if (_cleaningProfile.baseChecklist.isEmpty) {
          _validationError('בנייה לפחות קטגוריה אחת ב-Checklist');
          return;
        }
      }

      if (_isHandymanSubCategory()) {
        if (!_handymanProfile.verifications.backgroundCheck.verified) {
          _validationError('נדרשת בדיקת רקע מאושרת');
          return;
        }
        if (!_handymanProfile.specialties.any((s) => s.active)) {
          _validationError('בחר לפחות תחום התמחות אחד');
          return;
        }
      }

      if (_isFitnessTrainerSubCategory()) {
        if (_fitnessTrainerProfile.selectedSpecialties.isEmpty) {
          _validationError('בחרי לפחות התמחות אחת (עד 5)');
          return;
        }
        if (_fitnessTrainerProfile.packages.isEmpty) {
          _validationError('הוסיפי לפחות חבילת אימונים אחת');
          return;
        }
        if (_fitnessTrainerProfile.locations.isEmpty) {
          _validationError('בחרי לפחות מיקום אימון אחד (בית / פארק / חדר כושר)');
          return;
        }
      }

      if (_isMotorcycleTowingSubCategory()) {
        if (!_motorcycleTowProfile.hasBikeTypes) {
          _validationError('בחר לפחות סוג אופנוע אחד שאתה גורר');
          return;
        }
        if (!_motorcycleTowProfile.hasPricing) {
          _validationError('הזן מחיר בסיס ומחיר לק"מ');
          return;
        }
        if (!_motorcycleTowProfile.hasServiceArea) {
          _validationError(
              'הגדר אזור פעילות (כתובת בסיס + רדיוס או פוליגון)');
          return;
        }
      }
    }

    setState(() => _isLoading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final savedSuccess = l10n.saveSuccess;
    String saveErrMsg(Object e) => l10n.saveError('$e');

    // Defensive guard — should never happen since the screen is only reached
    // when a Firebase Auth user exists, but a stale FutureBuilder could race.
    if (uid == null || uid.isEmpty) {
      setState(() => _isLoading = false);
      messenger.showSnackBar(SnackBar(content: Text(saveErrMsg('not-signed-in'))));
      return;
    }

    try {
      // Resolve the most-specific category name (sub → main → null)
      // serviceType = sub-category name if selected, else main category name
      // parentCategory = main category name (only when sub-category is used)
      String? serviceTypeName;
      String? parentCategoryName;
      if (_selectedSubCatId != null) {
        final sub = _categories.firstWhere(
          (c) => c['id'] == _selectedSubCatId,
          orElse: () => <String, dynamic>{},
        );
        serviceTypeName = sub.isNotEmpty ? sub['name'] as String? : null;
        // Resolve parent category name for the fallback search query
        if (_selectedMainCatId != null) {
          final main = _mainCategories.firstWhere(
            (c) => c['id'] == _selectedMainCatId,
            orElse: () => <String, dynamic>{},
          );
          parentCategoryName = main.isNotEmpty ? main['name'] as String? : null;
        }
      } else if (_selectedMainCatId != null) {
        final main = _mainCategories.firstWhere(
          (c) => c['id'] == _selectedMainCatId,
          orElse: () => <String, dynamic>{},
        );
        serviceTypeName = main.isNotEmpty ? main['name'] as String? : null;
      }

      // Build payload with sanitized values — only include keys with non-null values.
      // The Firestore Web SDK throws INTERNAL ASSERTION FAILED: Unexpected state
      // when update() receives a null value.  Omitting the key is the correct
      // approach for optional fields; use FieldValue.delete() only when you
      // explicitly want to remove an existing field.
      // NOTE: `phone` + `phoneVerifiedAt` are intentionally NOT in this
      // payload. They are written exclusively by the OTP-link flow
      // (PhoneCollectionScreen) so the rules can enforce a one-shot
      // first-time-only write. Edit profile must never re-save the phone.
      final Map<String, dynamic> payload = {
        'name': safeName, // ← sanitized
        'isCustomer': _isCustomer,
        'isProvider': _isProvider,
        if (safeEmail != null && safeEmail.isNotEmpty) 'email': safeEmail,
        if (_profileImageUrl != null) 'profileImage': _profileImageUrl,
        if (_isProvider && serviceTypeName != null)
          'serviceType': serviceTypeName
        else if (!_isProvider)
          'serviceType': AppLocalizations.of(context).editCustomerServiceType,
        if (_isProvider && parentCategoryName != null)
          'parentCategory': parentCategoryName
        else if (_isProvider && _selectedSubCatId == null)
          'parentCategory': FieldValue.delete(),
        if (_isProvider && _selectedSubCatId != null)
          'subCategoryId': _selectedSubCatId
        else if (_isProvider && _selectedSubCatId == null)
          'subCategoryId': FieldValue.delete(),
      };

      // Provider-only fields — all values are sanitized results from above
      if (_isProvider) {
        payload['isVolunteer'] = _isVolunteer;
        // For motorcycle towing the legacy "מחיר לשעה" field is hidden in
        // the UI (CSM owns pricing). Mirror the CSM's base price into the
        // legacy `pricePerHour` field so search cards + sort-by-price flows
        // still have a sensible value to display.
        if (_isMotorcycleTowingSubCategory()) {
          payload['pricePerHour'] = _motorcycleTowProfile.pricing.basePrice;
        } else {
          payload['pricePerHour'] =
              double.tryParse(_priceController.text) ?? 0.0;
        }
        payload['aboutMe'] = aboutResult!.value; // ← sanitized
        payload['gallery'] = _galleryImages;
        if (_certificationImage != null) {
          payload['certificationImage'] = _certificationImage;
        }
        payload['taxId'] = taxResult!.value; // ← sanitized
        payload['quickTags'] = _selectedQuickTags.toList();
        payload['categoryTags'] = _selectedCategoryTags.toList();
        payload['cancellationPolicy'] = _cancellationPolicy;
        payload['videoUrl'] = videoUrlResult?.value ?? ''; // ← sanitized
        // Response time is now computed automatically by the
        // `computeResponseTimeOnMessage` CF; the manual setter was
        // removed (UX bug — providers shouldn't declare their own SLAs).
        // We intentionally do NOT write `responseTimeMinutes` here so the
        // CF-managed `avgResponseMinutes` stays authoritative.
        // Weekly working hours (convert Map<int,...> → Map<String,...> for Firestore)
        if (_workingHours.isNotEmpty) {
          payload['workingHours'] = {
            for (final e in _workingHours.entries) '${e.key}': e.value,
          };
        } else {
          payload['workingHours'] = FieldValue.delete();
        }
        if (_isMassageSubCategory() && _massageProfile.specialties.isNotEmpty) {
          payload['massageProfile'] = _massageProfile.toMap();
        }
        if (_isPestControlSubCategory() && _pestControlProfile.pestTypes.isNotEmpty) {
          payload['pestControlProfile'] = _pestControlProfile.toMap();
        }
        if (_isDeliverySubCategory() && _deliveryProfile.vehicles.isNotEmpty) {
          payload['deliveryProfile'] = _deliveryProfile.toMap();
        }
        if (_isCleaningSubCategory() &&
            _cleaningProfile.cleaningTypes.isNotEmpty) {
          payload['cleaningProfile'] = _cleaningProfile.toMap();
        }
        if (_isHandymanSubCategory() &&
            _handymanProfile.specialties.any((s) => s.active)) {
          payload['handymanProfile'] = _handymanProfile.toMap();
        }
        if (_isFitnessTrainerSubCategory() &&
            _fitnessTrainerProfile.selectedSpecialties.isNotEmpty) {
          payload['fitnessTrainerProfile'] = _fitnessTrainerProfile.toMap();
        }
        if (_isBabysitterSubCategory()) {
          payload['babysitterProfile'] = _babysitterProfile.toMap();
        }
        if (_isMotorcycleTowingSubCategory() &&
            _motorcycleTowProfile.bikeTypeIds.isNotEmpty) {
          payload['motorcycleTowProfile'] = _motorcycleTowProfile.toMap();
        }
        // Dynamic v2 service schema values: fields + _bundles + _surcharge.
        // We always write the map (even empty) so deletes propagate too.
        payload['categoryDetails'] = _categoryDetails;
        // Structured price list (category-specific, e.g. balloon decorators)
        if (_priceList.isNotEmpty) {
          payload['priceList'] = _priceList;
        }
      }

      // Use set(merge:true) instead of update() so this also works for the
      // edge case where the user doc doesn't yet exist (a brand-new phone-OTP
      // signup whose role-selection sheet write was lost mid-flow). With
      // update() Firestore returns permission-denied because the rule's
      // `request.resource.data.diff(resource.data)` errors when resource.data
      // is null. set(merge:true) routes through the create rule when the
      // doc is missing, and through the update rule when it already exists.
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(payload, SetOptions(merge: true));

      // CLAUDE.md §61 invalidation contract: every mutation of a cached
      // entity MUST invalidate so other screens (favorites §63, chat §66,
      // BookingProfileAvatar §67) re-read the new profileImage / name /
      // category instead of serving the 5-min cached copy.
      CachedReaders.invalidateProvider(uid);

      // CLAUDE.md §11 — dual-write contact email to private/identity.
      // Phone is no longer mirrored here because PhoneCollectionScreen owns
      // the phone field end-to-end (writes both main doc and private/identity
      // when OTP succeeds, and edits are blocked thereafter).
      if (safeEmail != null) {
        try {
          await PrivateDataService.writeContactData(uid, email: safeEmail);
        } catch (e) {
          debugPrint('[EditProfile] writeContactData error: $e');
        }
      }

      // v10.1.0: Dual-write — sync identity-specific fields to provider_listings
      if (_isProvider) {
        try {
          await _syncToProviderListing(uid, payload, serviceTypeName, parentCategoryName);
        } catch (e) {
          debugPrint('[EditProfile] Listing sync error: $e');
        }
      }

      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(backgroundColor: Colors.green, content: Text(savedSuccess)),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(saveErrMsg(e))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── v10.1.2: Safe gallery image builder ─────────────────────────────────────
  /// Renders a gallery image that could be an HTTPS URL or a base64 string.
  /// Prevents FormatException crashes from base64Decode on URL strings.
  Widget _buildGalleryImage(String raw) {
    if (raw.isEmpty) {
      return Container(color: Colors.grey[200]);
    }
    // HTTPS URL — use network image
    if (raw.startsWith('http')) {
      return Image.network(
        raw,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => Container(
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
        ),
      );
    }
    // Base64 data URI or raw base64 string
    try {
      final b64 = raw.contains(',') ? raw.split(',').last : raw;
      return Image.memory(
        base64Decode(b64),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    } catch (_) {
      return Container(
        color: Colors.grey[200],
        child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
      );
    }
  }

  // ── v10.1.0: Second Identity Card ──────────────────────────────────────────

  Widget _buildSecondIdentityCard() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    // Use cached listings if available, otherwise fetch
    final listingsToShow = _allListings.isNotEmpty
        ? _allListings
        : null;

    if (listingsToShow != null) {
      return _buildIdentityCards(listingsToShow);
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: ProviderListingService.getListings(uid),
      builder: (context, snap) {
        final listings = snap.data ?? [];
        return _buildIdentityCards(listings);
      },
    );
  }

  Widget _buildIdentityCards(List<Map<String, dynamic>> listings) {
    final hasSecond = listings.length >= 2;

    return Column(
      children: [
        // ── Show ALL identity cards (not just the "other" one) ─────────
        if (listings.isNotEmpty) ...[
          for (final listing in listings) _buildIdentityTile(listing),
          const SizedBox(height: 12),
        ],

        // ── Add second identity CTA (only if fewer than 2) ────────────
        if (!hasSecond)
          GestureDetector(
            onTap: _openAddSecondIdentity,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF8FAFC), Color(0xFFF0F0FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.add_business_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(AppLocalizations.of(context).editAddSecondIdentity,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A2E),
                            )),
                        const SizedBox(height: 4),
                        Text(
                          AppLocalizations.of(context).editSecondIdentitySubtitle,
                          style: TextStyle(fontSize: 12.5, color: Colors.grey[600], height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_left_rounded, color: Color(0xFF6366F1)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// v10.3.2: Builds a single identity tile with "current" badge or "switch" action.
  Widget _buildIdentityTile(Map<String, dynamic> listing) {
    final listingId = listing['listingId'] as String? ?? '';
    final serviceType = listing['serviceType'] as String? ?? '';
    final index = (listing['identityIndex'] as num?)?.toInt() ?? 0;
    final isCurrent = listingId == _activeListingId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: isCurrent
            ? null
            : () {
                // Navigate to same screen with the other listing
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditProfileScreen(
                      userData: widget.userData,
                      listingId: listingId,
                    ),
                  ),
                );
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isCurrent ? const Color(0xFFEEF2FF) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isCurrent
                  ? const Color(0xFF6366F1)
                  : Colors.grey.shade200,
              width: isCurrent ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: isCurrent
                      ? const Color(0xFF6366F1).withValues(alpha: 0.12)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  index == 0 ? Icons.work_rounded : Icons.add_business_rounded,
                  size: 20,
                  color: isCurrent ? const Color(0xFF6366F1) : Colors.grey[600],
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      serviceType,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isCurrent ? const Color(0xFF6366F1) : const Color(0xFF1A1A2E),
                      ),
                    ),
                    Text(
                      index == 0 ? AppLocalizations.of(context).editPrimaryIdentity : AppLocalizations.of(context).editSecondaryIdentity,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              // Badge or switch icon
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(AppLocalizations.of(context).editEditingNow,
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                )
              else
                const Icon(Icons.swap_horiz_rounded,
                    color: Color(0xFF6366F1), size: 22),
            ],
          ),
        ),
      ),
    );
  }

  void _openAddSecondIdentity() async {
    // v10.2.0: Full-screen premium onboarding flow instead of basic bottom sheet
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const IdentityOnboardingScreen()),
    );
    if (created == true && mounted) setState(() {}); // Rebuild to show new identity
  }

  // _openSecondIdentityEditor removed in v10.3.2 — replaced by
  // _buildIdentityTile + Navigator.pushReplacement to the same screen
  // with the target listingId.

  /// v10.3.2: Dual-write — sync identity fields to the ACTIVE provider_listing.
  /// Uses _activeListingId when available, falls back to primary (index 0).
  Future<void> _syncToProviderListing(
    String uid,
    Map<String, dynamic> payload,
    String? serviceTypeName,
    String? parentCategoryName,
  ) async {
    final db = FirebaseFirestore.instance;

    // Use the active listing if we know it, else find index 0
    QuerySnapshot<Map<String, dynamic>>? snap;
    if (_activeListingId != null) {
      // Direct doc reference — no query needed
    } else {
      snap = await db
          .collection('provider_listings')
          .where('uid', isEqualTo: uid)
          .where('identityIndex', isEqualTo: 0)
          .limit(1)
          .get();
    }

    final listingUpdate = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Mirror identity-specific fields
    if (payload.containsKey('name')) listingUpdate['name'] = payload['name'];
    if (payload.containsKey('profileImage')) listingUpdate['profileImage'] = payload['profileImage'];
    if (payload.containsKey('serviceType')) listingUpdate['serviceType'] = payload['serviceType'];
    if (payload.containsKey('parentCategory')) listingUpdate['parentCategory'] = payload['parentCategory'];
    if (payload.containsKey('aboutMe')) listingUpdate['aboutMe'] = payload['aboutMe'];
    if (payload.containsKey('pricePerHour')) listingUpdate['pricePerHour'] = payload['pricePerHour'];
    if (payload.containsKey('gallery')) listingUpdate['gallery'] = payload['gallery'];
    if (payload.containsKey('quickTags')) listingUpdate['quickTags'] = payload['quickTags'];
    if (payload.containsKey('categoryTags')) listingUpdate['categoryTags'] = payload['categoryTags'];
    if (payload.containsKey('cancellationPolicy')) listingUpdate['cancellationPolicy'] = payload['cancellationPolicy'];
    if (payload.containsKey('workingHours')) listingUpdate['workingHours'] = payload['workingHours'];
    if (payload.containsKey('categoryDetails')) listingUpdate['categoryDetails'] = payload['categoryDetails'];
    if (payload.containsKey('priceList')) listingUpdate['priceList'] = payload['priceList'];
    if (payload.containsKey('isVolunteer')) listingUpdate['isVolunteer'] = payload['isVolunteer'];
    if (payload.containsKey('massageProfile')) listingUpdate['massageProfile'] = payload['massageProfile'];
    if (payload.containsKey('pestControlProfile')) listingUpdate['pestControlProfile'] = payload['pestControlProfile'];
    if (payload.containsKey('deliveryProfile')) listingUpdate['deliveryProfile'] = payload['deliveryProfile'];
    if (payload.containsKey('cleaningProfile')) listingUpdate['cleaningProfile'] = payload['cleaningProfile'];
    if (payload.containsKey('handymanProfile')) listingUpdate['handymanProfile'] = payload['handymanProfile'];
    if (payload.containsKey('fitnessTrainerProfile')) listingUpdate['fitnessTrainerProfile'] = payload['fitnessTrainerProfile'];
    if (payload.containsKey('babysitterProfile')) listingUpdate['babysitterProfile'] = payload['babysitterProfile'];
    if (payload.containsKey('motorcycleTowProfile')) listingUpdate['motorcycleTowProfile'] = payload['motorcycleTowProfile'];

    // Remove FieldValue.delete() entries — can't write them to a doc that may not have the field
    listingUpdate.removeWhere((_, v) => v is FieldValue);

    if (_activeListingId != null) {
      // Direct update to the known active listing
      await db.collection('provider_listings').doc(_activeListingId).update(listingUpdate);
      debugPrint('[EditProfile] Active listing synced: $_activeListingId');
    } else if (snap != null && snap.docs.isNotEmpty) {
      await db.collection('provider_listings').doc(snap.docs.first.id).update(listingUpdate);
      debugPrint('[EditProfile] Primary listing synced: ${snap.docs.first.id}');
    } else {
      // No listing yet — auto-migrate on save
      final listingId = await ProviderListingService.migrateIfNeeded(uid);
      debugPrint('[EditProfile] Listing migrated on save: $listingId');
    }
  }

  /// Pushes the OTP-link flow when the user has no verified phone yet.
  /// Re-loads the user doc on success so `_phoneDisplay` flips from empty
  /// to the new verified number without leaving the screen.
  Future<void> _addPhoneFlow() async {
    final navigator = Navigator.of(context);
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => PhoneCollectionScreen(
          existingData: widget.userData,
          showSkipButton: false, // mandatory completion
          onSuccess: () {
            // Pop back to edit profile.
            if (navigator.canPop()) navigator.pop();
          },
        ),
      ),
    );
    // Re-read the user doc so the new phone shows immediately.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !mounted) return;
    try {
      final fresh = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final phone = (fresh.data()?['phone'] as String? ?? '').trim();
      if (phone.isNotEmpty && mounted) {
        setState(() => _phoneDisplay = phone);
      }
    } catch (e) {
      debugPrint('[EditProfile] Phone refresh failed: $e');
    }
  }

  Widget _buildLockedPhoneField() {
    // No phone yet → show an actionable "Add Phone" CTA. After OTP-link the
    // value comes back via `_addPhoneFlow` and this collapses to the locked
    // display below.
    if (_phoneDisplay.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const Icon(Icons.phone_rounded, size: 14, color: Color(0xFF6366F1)),
              const SizedBox(width: 4),
              Text(
                AppLocalizations.of(context).editPhoneLabel,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: _addPhoneFlow,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsetsDirectional.fromSTEB(16, 13, 16, 13),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF6366F1), width: 1.2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.add_circle_rounded,
                      size: 18, color: Color(0xFF6366F1)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'הוסף מספר טלפון ואמת אותו',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_back_ios_rounded,
                      size: 13, color: Color(0xFF6366F1)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsetsDirectional.only(start: 4),
            child: Text(
              'הוספת מספר חובה. תקבל קוד SMS לאימות. לאחר השמירה לא ניתן לשנות — צוות AnySkill בלבד.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const Icon(Icons.lock_rounded, size: 13, color: Color(0xFF6366F1)),
            const SizedBox(width: 4),
            Text(
              AppLocalizations.of(context).editPhoneLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F7FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _phoneDisplay,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.phone_rounded,
                size: 17,
                color: Color(0xFF6366F1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Text(
            AppLocalizations.of(context).editPhoneVerified,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  /// Editable email field — or a locked Google/Apple display when the user
  /// signed in via a social provider (in that case the email is authoritative
  /// and cannot be changed inside the app).
  Widget _buildEmailField(AppLocalizations l10n) {
    if (_emailLockedFromAuth) {
      // Locked state — mirrors `_buildLockedPhoneField` design language but
      // shows a Google-icon hint instead of the lock icon.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const Icon(Icons.lock_rounded,
                  size: 13, color: Color(0xFF6366F1)),
              const SizedBox(width: 4),
              Text(
                l10n.loginEmail,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F7FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _emailController.text.isEmpty ? '—' : _emailController.text,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 15,
                      color: _emailController.text.isEmpty
                          ? Colors.grey[400]
                          : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.alternate_email_rounded,
                  size: 17,
                  color: Color(0xFF6366F1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              'מסונכרן אוטומטית מחשבון Google / Apple',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ],
      );
    }

    // Editable state — phone-OTP user can type their own email.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.loginEmail,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _emailController,
          textAlign: TextAlign.start,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(
            hintText: 'name@example.com',
            prefixIcon: Icon(Icons.alternate_email_rounded,
                size: 18, color: Color(0xFF6366F1)),
          ),
        ),
      ],
    );
  }

  Widget _buildPendingExpertBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFC107)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.amber,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  AppLocalizations.of(context).editAppPending,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  AppLocalizations.of(context).editAppPendingDesc,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12, color: Colors.brown),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context).editProfileTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _saveProfile,
            icon: const Icon(Icons.check, color: Colors.blue, size: 30),
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Builder(
                builder: (context) {
                  final l10n = AppLocalizations.of(context);
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(25),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // v12.7.0 — View-mode toggle.
                        //  Provider → 2 chips (נותן שירות / לקוח)
                        //  Admin    → 3 chips (ניהול / נותן שירות / לקוח)
                        //  Support agent → toggle hidden (dedicated workspace)
                        if ((_isProvider || _hasAdminPrivilege()) &&
                            !_isSupportAgent()) ...[
                          _buildViewModeToggleCard(context),
                          const SizedBox(height: 16),
                        ],
                        // --- תמונת פרופיל ---
                        Center(
                          child: Column(
                            children: [
                              GestureDetector(
                                onTap: _pickProfileImage,
                                child: Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 55,
                                      backgroundColor: Colors.grey[200],
                                      // v10.1.2: Use safeImageProvider to handle
                                      // both HTTPS URLs and base64 data URIs
                                      // without FormatException crashes.
                                      backgroundImage:
                                          safeImageProvider(_profileImageUrl),
                                      child:
                                          (_profileImageUrl == null ||
                                                  _profileImageUrl!.isEmpty)
                                              ? const Icon(
                                                Icons.person,
                                                size: 50,
                                                color: Colors.grey,
                                              )
                                              : null,
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: CircleAvatar(
                                        radius: 18,
                                        backgroundColor: Colors.blue,
                                        child: const Icon(
                                          Icons.camera_alt,
                                          size: 18,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                AppLocalizations.of(context).editUploadClearPhoto,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                AppLocalizations.of(context).editClearPhotoDesc,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF6366F1),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            l10n.profileFieldName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        TextField(
                          controller: _nameController,
                          textAlign: TextAlign.start,
                          decoration: InputDecoration(
                            hintText: l10n.profileFieldNameHint,
                          ),
                        ),

                        const SizedBox(height: 20),

                        // ── Phone — verified, read-only ──────────────────────────
                        _buildLockedPhoneField(),

                        const SizedBox(height: 20),

                        // ── Email ────────────────────────────────────────────────
                        _buildEmailField(l10n),

                        const SizedBox(height: 25),

                        // ── Dogs (customers only — private, owner-only view) ──
                        if (!_isProvider) ...[
                          _buildMyDogsSection(context),
                          const SizedBox(height: 18),
                        ],

                        Text(
                          l10n.profileFieldRole,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (_isProvider)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  // Provider chip — locked selected, non-interactive
                                  FilterChip(
                                    label: Text(l10n.roleProvider),
                                    selected: true,
                                    onSelected: null,
                                    selectedColor: Colors.green[100],
                                    disabledColor: Colors.green[50],
                                  ),
                                  const SizedBox(width: 10),
                                  // Customer chip — locked unselected, non-interactive
                                  FilterChip(
                                    label: Text(l10n.roleCustomer),
                                    selected: false,
                                    onSelected: null,
                                    disabledColor: Colors.grey[100],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                AppLocalizations.of(context).editAccountTypeChange,
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          )
                        else if (_isPendingExpert)
                          _buildPendingExpertBanner(),

                        // ── Volunteer toggle (providers only) ────────────────────
                        if (_isProvider) ...[
                          const SizedBox(height: 16),
                          Container(
                            decoration: BoxDecoration(
                              color:
                                  _isVolunteer
                                      ? const Color(0xFFECFDF5)
                                      : Colors.grey[50],
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color:
                                    _isVolunteer
                                        ? const Color(0xFF10B981)
                                        : Colors.grey.shade200,
                                width: _isVolunteer ? 1.5 : 1,
                              ),
                            ),
                            child: SwitchListTile.adaptive(
                              value: _isVolunteer,
                              onChanged:
                                  (val) => setState(() => _isVolunteer = val),
                              activeColor: const Color(0xFF10B981),
                              title: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    AppLocalizations.of(context).editVolunteerToggleTitle,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  if (_isVolunteer)
                                    const Icon(
                                      Icons.favorite,
                                      color: Colors.red,
                                      size: 18,
                                    ),
                                ],
                              ),
                              subtitle: Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: Text(
                                  AppLocalizations.of(context).editVolunteerToggleDesc,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 4,
                              ),
                            ),
                          ),
                        ],

                        if (_isProvider) ...[
                          // v10.1.0 → v13.2.0: identity switcher moved above
                          // "תחום עיסוק" so providers can instantly flip between
                          // identities and see the right fields loaded.
                          const SizedBox(height: 25),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              AppLocalizations.of(context).editIdentitiesTitle,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildSecondIdentityCard(),
                          const SizedBox(height: 25),

                          // ── Main Category dropdown ──────────────────────────────
                          Text(
                            l10n.profileFieldCategoryMain,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          // ALWAYS render the dropdown structure — never swap it
                          // out for a fallback card. When items are loading
                          // (one-shot get + stream both pending), show an
                          // inline spinner + "טוען..." text INSIDE the hint
                          // area so the user knows to wait. The `onChanged`
                          // is null while empty → Flutter renders the dropdown
                          // as disabled (clearly non-interactive), avoiding
                          // the previous bug where the user tapped an empty
                          // dropdown and nothing happened.
                          DropdownButtonFormField<String>(
                              isExpanded:
                                  true, // ← required on Web; without it the tap
                              //   target collapses to 0 in RTL columns
                              value:
                                  _mainCategories.any(
                                        (c) => c['id'] == _selectedMainCatId,
                                      )
                                      ? _selectedMainCatId
                                      : null,
                              hint: _mainCategories.isEmpty
                                  ? _buildLoadingHint(
                                      l10n.profileFieldCategoryMainHint)
                                  : Text(
                                      l10n.profileFieldCategoryMainHint,
                                      textAlign: TextAlign.right,
                                    ),
                              items:
                                  _mainCategories
                                      .map(
                                        (c) => DropdownMenuItem(
                                          value: c['id'] as String,
                                          child: Text(
                                            c['name'] as String? ?? '',
                                            textAlign: TextAlign.right,
                                          ),
                                        ),
                                      )
                                      .toList(),
                              // Disable taps while empty — Flutter shows a
                              // greyed dropdown so the user knows it's a
                              // loading state (not a "broken" widget).
                              onChanged: _mainCategories.isEmpty ? null : (val) {
                                setState(() {
                                  _selectedMainCatId = val;
                                  _selectedSubCatId = null;
                                  _subCategories = _categories
                                      .where((c) => c['parentId'] == val)
                                      .toList();
                                  _categorySchema = [];
                                  _serviceSchema = ServiceSchema.empty();
                                  _categoryDetails = {};
                                });
                                // Load schema for the parent category as a
                                // baseline. Will be replaced when the user
                                // picks a sub-category (more specific).
                                if (val != null) {
                                  final catName = _mainCategories
                                      .where((c) => c['id'] == val)
                                      .map((c) => c['name'] as String? ?? '')
                                      .firstOrNull ?? '';
                                  if (catName.isNotEmpty) {
                                    _loadV2SchemaFor(catName);
                                  }
                                }
                              },
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                              ),
                            ),
                          // ── Sub-Category dropdown (shown only when subs exist) ──
                          if (_subCategories.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              l10n.profileFieldCategorySub,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              isExpanded: true, // ← same fix for sub-category
                              value:
                                  _subCategories.any(
                                        (c) => c['id'] == _selectedSubCatId,
                                      )
                                      ? _selectedSubCatId
                                      : null,
                              hint: Text(
                                l10n.profileFieldCategorySubHint,
                                textAlign: TextAlign.right,
                              ),
                              items:
                                  _subCategories
                                      .map(
                                        (c) => DropdownMenuItem(
                                          value: c['id'] as String,
                                          child: Text(
                                            c['name'] as String? ?? '',
                                            textAlign: TextAlign.right,
                                          ),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (val) {
                                setState(() {
                                  _selectedSubCatId = val;
                                  _serviceSchema = ServiceSchema.empty();
                                  _categoryDetails = {};
                                });
                                // Load the most specific schema available.
                                if (val != null) {
                                  final subName = _subCategories
                                      .where((c) => c['id'] == val)
                                      .map((c) => c['name'] as String? ?? '')
                                      .firstOrNull ?? '';
                                  if (subName.isNotEmpty) {
                                    _loadV2SchemaFor(subName);
                                  }
                                }
                              },
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],

                          // ── Massage Settings Block (only for massage sub-category) ──
                          if (_isMassageSubCategory()) ...[
                            const SizedBox(height: 16),
                            MassageSettingsBlock(
                              initialProfile: _massageProfile,
                              onChanged: (profile) {
                                _massageProfile = profile;
                              },
                            ),
                          ],

                          // ── Pest Control Settings Block (only for pest control sub-category) ──
                          if (_isPestControlSubCategory()) ...[
                            const SizedBox(height: 16),
                            PestControlSettingsBlock(
                              initialProfile: _pestControlProfile,
                              onChanged: (profile) {
                                _pestControlProfile = profile;
                              },
                            ),
                          ],

                          if (_isDeliverySubCategory()) ...[
                            const SizedBox(height: 16),
                            DeliverySettingsBlock(
                              initialProfile: _deliveryProfile,
                              onChanged: (profile) {
                                _deliveryProfile = profile;
                              },
                            ),
                          ],

                          if (_isCleaningSubCategory()) ...[
                            const SizedBox(height: 16),
                            CleaningSettingsBlock(
                              initialProfile: _cleaningProfile,
                              providerId: FirebaseAuth.instance.currentUser?.uid,
                              onChanged: (profile) {
                                _cleaningProfile = profile;
                              },
                            ),
                          ],

                          if (_isHandymanSubCategory()) ...[
                            const SizedBox(height: 16),
                            HandymanSettingsBlock(
                              initialProfile: _handymanProfile,
                              onChanged: (profile) {
                                _handymanProfile = profile;
                              },
                            ),
                          ],

                          if (_isFitnessTrainerSubCategory()) ...[
                            const SizedBox(height: 16),
                            FitnessTrainerSettingsBlock(
                              initialProfile: _fitnessTrainerProfile,
                              onChanged: (profile) {
                                _fitnessTrainerProfile = profile;
                              },
                            ),
                          ],

                          if (_isBabysitterSubCategory()) ...[
                            const SizedBox(height: 16),
                            BabysitterSettingsBlock(
                              initialProfile: _babysitterProfile,
                              onChanged: (profile) {
                                _babysitterProfile = profile;
                              },
                            ),
                          ],

                          if (_isMotorcycleTowingSubCategory()) ...[
                            const SizedBox(height: 16),
                            MotorcycleTowSettingsBlock(
                              initialProfile: _motorcycleTowProfile,
                              onChanged: (profile) {
                                _motorcycleTowProfile = profile;
                              },
                            ),
                          ],

                          const SizedBox(height: 20),

                          // ── Tax ID ──────────────────────────────────────────────
                          Text(
                            l10n.profileFieldTaxId,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.profileFieldTaxIdHelp,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _taxIdController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.start,
                            decoration: InputDecoration(
                              hintText: l10n.profileFieldTaxIdHint,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              prefixIcon: const Icon(
                                Icons.receipt_long_outlined,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // ── הגדרות תשלום (Payment Settings) ─────────────────────────────────
                          // Phase 2: Stripe Connect was removed pending Israeli payment provider
                          // integration. Provider payouts are temporarily handled via the manual
                          // withdrawal flow (admin reviews requests in the Withdrawals tab).
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.construction_rounded,
                                      color: Color(0xFFF59E0B),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        AppLocalizations.of(context).editPaymentSettings,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: Color(0xFF1A1A2E),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  AppLocalizations.of(context).editPaymentSettingsDesc,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF7C2D12),
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // ── Price Settings + per-hour field ───────────────────
                          // Hidden for sub-categories that own their own pricing
                          // editor (e.g. Motorcycle Towing CSM §55 — base price,
                          // included km, per-km, night/emergency surcharge are
                          // declared inside the CSM block above). Showing the
                          // legacy "₪/hour" field on top of that would be
                          // confusing + irrelevant.
                          if (!_isMotorcycleTowingSubCategory()) ...[
                            GestureDetector(
                              onTap:
                                  () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => PriceSettingsScreen(
                                            userData: {
                                              ...widget.userData,
                                              // Pass the live price the user may have typed
                                              'pricePerHour':
                                                  double.tryParse(
                                                    _priceController.text.trim(),
                                                  ) ??
                                                  widget
                                                      .userData['pricePerHour'] ??
                                                  100.0,
                                            },
                                          ),
                                    ),
                                  ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF6366F1),
                                      Color(0xFF8B5CF6),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF6366F1,
                                      ).withValues(alpha: 0.3),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.arrow_back_ios_new_rounded,
                                          color: Colors.white70,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          AppLocalizations.of(context).editAdvancedSettings,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          AppLocalizations.of(context).editPricingSettings,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(
                                          Icons.price_change_outlined,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              l10n.profileFieldPrice,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            TextField(
                              controller: _priceController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.start,
                              decoration: InputDecoration(
                                hintText: l10n.profileFieldPriceHint,
                              ),
                            ),
                          ],

                          // ── v2 Service Schema (fields + bundles + surcharge + deposit) ──
                          // Hidden for motorcycle towing — the CSM block above
                          // already declares "תעריף קריאה" + "תעריף לשעת עבודה"
                          // + night/emergency surcharges. Showing the schema
                          // form here would render duplicate inputs for the
                          // same data and confuse the provider.
                          if (!_isMotorcycleTowingSubCategory()) ...[
                            if (!_serviceSchema.isEmpty)
                              DynamicServiceSchemaForm(
                                key: ValueKey(
                                    'svc_schema_${_selectedSubCatId ?? _selectedMainCatId ?? ''}'),
                                schema: _serviceSchema,
                                initialValues: _categoryDetails,
                                onChanged: (vals) => _categoryDetails = vals,
                              )
                            else if (_categorySchema.isNotEmpty)
                              // Legacy v1 fallback (only fires for categories
                              // whose serviceSchema is still in List shape).
                              DynamicSchemaForm(
                                schema: _categorySchema,
                                initialValues: _categoryDetails,
                                onChanged: (vals) => _categoryDetails = vals,
                              ),
                          ],

                          // ── Structured price list (category-specific) ──
                          if (hasPriceList(widget.userData))
                            PriceListEditor(
                              type: priceListType(widget.userData),
                              initialData: _priceList,
                              onChanged: (val) => _priceList = val,
                            ),

                          // Response time used to be a manual chip selector
                          // here. Removed — the value is now computed
                          // automatically by the `computeResponseTimeOnMessage`
                          // Cloud Function from real chat timestamps, and
                          // written to `users/{uid}.avgResponseMinutes`. The
                          // public profile / search cards still read that
                          // field; only the manual setter is gone.
                        ],

                        // ── Provider-only fields ──────────────────────────────────
                        if (_isProvider) ...[
                          const SizedBox(height: 25),

                          // ── Quick Tags picker ───────────────────────────────────
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                l10n.editProfileTagsSelected(
                                  _selectedQuickTags.length,
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      _selectedQuickTags.length >= 3
                                          ? const Color(0xFF6366F1)
                                          : Colors.grey,
                                ),
                              ),
                              Text(
                                l10n.editProfileQuickTags,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              l10n.editProfileTagsHint,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.end,
                            children:
                                kQuickTagCatalog.map((tag) {
                                  final key = tag['key']!;
                                  final selected = _selectedQuickTags.contains(
                                    key,
                                  );
                                  final maxed = _selectedQuickTags.length >= 3;
                                  return GestureDetector(
                                    onTap: () {
                                      if (!selected && maxed) return;
                                      setState(() {
                                        if (selected) {
                                          _selectedQuickTags.remove(key);
                                        } else {
                                          _selectedQuickTags.add(key);
                                        }
                                      });
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 7,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            selected
                                                ? const Color(0xFF6366F1)
                                                : (!selected && maxed)
                                                ? Colors.grey[100]
                                                : const Color(0xFFF0F0FF),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color:
                                              selected
                                                  ? const Color(0xFF6366F1)
                                                  : (!selected && maxed)
                                                  ? Colors.grey.shade300
                                                  : const Color(
                                                    0xFF6366F1,
                                                  ).withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Text(
                                        '${tag['emoji']} ${tag['label']}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color:
                                              selected
                                                  ? Colors.white
                                                  : (!selected && maxed)
                                                  ? Colors.grey
                                                  : const Color(0xFF6366F1),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                          ),

                          // ── Category-specific tags (complements quickTags) ────────
                          // Shows up to 5 additional chips drawn from the seeded
                          // `category_tags/{serviceType}` catalog. Hidden when the
                          // category has no catalog doc.
                          const SizedBox(height: 20),
                          CategoryTagsSelector(
                            category: _activeListingServiceType,
                            initialSelected: _selectedCategoryTags,
                            onChanged: (s) =>
                                setState(() => _selectedCategoryTags = s),
                          ),

                          const SizedBox(height: 25),

                          // ── Cancellation Policy picker ──────────────────────────
                          Text(
                            l10n.editProfileCancellationPolicy,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              l10n.editProfileCancellationHint,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Column(
                            children:
                                CancellationPolicyService.kPolicies.map((p) {
                                  final selected = _cancellationPolicy == p;
                                  return GestureDetector(
                                    onTap:
                                        () => setState(
                                          () => _cancellationPolicy = p,
                                        ),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            selected
                                                ? const Color(0xFFF0F0FF)
                                                : Colors.grey[50],
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color:
                                              selected
                                                  ? const Color(0xFF6366F1)
                                                  : Colors.grey.shade200,
                                          width: selected ? 2 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            selected
                                                ? Icons.radio_button_checked
                                                : Icons.radio_button_unchecked,
                                            color:
                                                selected
                                                    ? const Color(0xFF6366F1)
                                                    : Colors.grey,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  CancellationPolicyService.label(
                                                    p,
                                                  ),
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                    color:
                                                        selected
                                                            ? const Color(
                                                              0xFF6366F1,
                                                            )
                                                            : Colors.black87,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  CancellationPolicyService.description(
                                                    p,
                                                  ),
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                          ),

                          const SizedBox(height: 25),

                          // ── Working Hours (שעות עבודה) ─────────────────────────
                          Text(
                            AppLocalizations.of(context).editWorkingHours,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              AppLocalizations.of(context).editWorkingHoursHint,
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...List.generate(7, (dayIndex) {
                            final enabled = _workingHours.containsKey(dayIndex);
                            final from = _workingHours[dayIndex]?['from'] ?? '09:00';
                            final to   = _workingHours[dayIndex]?['to']   ?? '17:00';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  // Day toggle
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: Checkbox(
                                      value: enabled,
                                      activeColor: const Color(0xFF6366F1),
                                      onChanged: (val) {
                                        setState(() {
                                          if (val == true) {
                                            _workingHours[dayIndex] = {'from': '09:00', 'to': '17:00'};
                                          } else {
                                            _workingHours.remove(dayIndex);
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 52,
                                    child: Text(
                                      _dayNames(context)[dayIndex],
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: enabled ? Colors.black87 : Colors.grey,
                                      ),
                                    ),
                                  ),
                                  if (enabled) ...[
                                    // From dropdown
                                    _buildHourDropdown(from, (val) {
                                      setState(() => _workingHours[dayIndex]!['from'] = val);
                                    }),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      child: Text('–', style: TextStyle(color: Colors.grey[600])),
                                    ),
                                    // To dropdown
                                    _buildHourDropdown(to, (val) {
                                      setState(() => _workingHours[dayIndex]!['to'] = val);
                                    }),
                                  ] else
                                    Text(
                                      AppLocalizations.of(context).editDayOff,
                                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                                    ),
                                ],
                              ),
                            );
                          }),

                          const SizedBox(height: 25),

                          // ── Business Description / Bio ──────────────────────────
                          Text(
                            l10n.editProfileAbout,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextField(
                            controller: _aboutController,
                            maxLines: 4,
                            textAlign: TextAlign.start,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              hintText: l10n.editProfileAboutHint,
                            ),
                          ),

                          const SizedBox(height: 30),

                          // ── Work Gallery / Portfolio ────────────────────────────
                          Text(
                            l10n.editProfileGallery,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                ),
                            itemCount: _galleryImages.length + 1,
                            itemBuilder: (context, index) {
                              if (index == _galleryImages.length) {
                                return GestureDetector(
                                  onTap: _pickAndCompressGalleryImage,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.blue[50],
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.blue.shade100,
                                        style: BorderStyle.solid,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.add_photo_alternate_outlined,
                                      color: Colors.blue,
                                      size: 35,
                                    ),
                                  ),
                                );
                              }
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    // v10.1.2: Gallery items can be HTTPS URLs
                                    // (Firebase Storage) or base64 strings.
                                    // safeImageProvider handles both formats.
                                    child: _buildGalleryImage(
                                      _galleryImages[index] as String? ?? '',
                                    ),
                                  ),
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: GestureDetector(
                                      onTap:
                                          () => setState(
                                            () =>
                                                _galleryImages.removeAt(index),
                                          ),
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.cancel,
                                          color: Colors.red,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 25),

                          // ── Certification Image ────────────────────────────────
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              AppLocalizations.of(context).editCertificate,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              AppLocalizations.of(context).editCertificateDesc,
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_certificationImage != null) ...[
                            Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: _buildGalleryImage(_certificationImage!),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: () => setState(() => _certificationImage = null),
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.cancel, color: Colors.red, size: 22),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _pickCertificationImage,
                              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                              label: Text(AppLocalizations.of(context).editReplaceCertificate),
                            ),
                          ] else
                            GestureDetector(
                              onTap: _pickCertificationImage,
                              child: Container(
                                height: 120,
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.amber.shade200),
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.workspace_premium_rounded, size: 36, color: Colors.amber[700]),
                                      const SizedBox(height: 6),
                                      Text(
                                        AppLocalizations.of(context).editUploadCertificate,
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.amber[800]),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 25),

                          // ── Video Verification Upload ───────────────────────────
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              AppLocalizations.of(context).editIntroVideo,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              AppLocalizations.of(context).editIntroVideoDesc,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap:
                                _videoUploadInProgress
                                    ? null
                                    : _pickAndUploadVerificationVideo,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                vertical: 18,
                                horizontal: 20,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    _verificationVideoUrl != null
                                        ? const Color(0xFFECFDF5)
                                        : const Color(0xFFF0F0FF),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color:
                                      _verificationVideoUrl != null
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFF6366F1),
                                  width: 1.5,
                                ),
                              ),
                              child:
                                  _videoUploadInProgress
                                      ? Column(
                                        children: [
                                          LinearProgressIndicator(
                                            value: _videoUploadProgress,
                                            backgroundColor: const Color(
                                              0xFFE0E0FF,
                                            ),
                                            valueColor:
                                                const AlwaysStoppedAnimation<
                                                  Color
                                                >(Color(0xFF6366F1)),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            AppLocalizations.of(context).editUploading((_videoUploadProgress * 100).toInt()),
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Color(0xFF6366F1),
                                            ),
                                          ),
                                        ],
                                      )
                                      : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            _verificationVideoUrl != null
                                                ? Icons.videocam_rounded
                                                : Icons.video_call_rounded,
                                            color:
                                                _verificationVideoUrl != null
                                                    ? const Color(0xFF10B981)
                                                    : const Color(0xFF6366F1),
                                            size: 24,
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            _verificationVideoUrl != null
                                                ? AppLocalizations.of(context).editVideoUploaded
                                                : AppLocalizations.of(context).editUploadVideo,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color:
                                                  _verificationVideoUrl != null
                                                      ? const Color(0xFF10B981)
                                                      : const Color(0xFF6366F1),
                                            ),
                                          ),
                                        ],
                                      ),
                            ),
                          ),
                          if (_verificationVideoUrl != null) ...[
                            const SizedBox(height: 6),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: Text(
                                AppLocalizations.of(context).editPendingAdmin,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ], // end provider-only fields

                        const SizedBox(height: 40),
                        ElevatedButton(
                          onPressed: _saveProfile,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 60),
                            backgroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          child: Text(
                            l10n.saveChanges,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 50),
                      ],
                    ),
                  );
                },
              ), // Builder
    );
  }

  // `_buildSavedCategoryFallback` was removed in v10.5.5. It replaced the
  // dropdown with a read-only card while the CategoryService stream loaded
  // — but this also hid the sub-category dropdown (gated on
  // `_subCategories.isNotEmpty`), leaving the user unable to pick a sub.
  // The dropdowns now ALWAYS render directly; empty-items handling +
  // the 6s timeout safety net in initState replace the fallback.

  /// Inline hint widget shown inside a dropdown while its items are still
  /// loading. Renders a small spinner + "טוען..." + the regular hint so
  /// the user immediately knows the dropdown is a loading-state rather
  /// than a broken empty box.
  Widget _buildLoadingHint(String hintText) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            hintText,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF6B7280)),
          ),
        ),
        const SizedBox(width: 8),
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      ],
    );
  }

  // Defense-in-depth per CLAUDE.md §50: only treat the user as admin when
  // the `isAdmin: true` flag is corroborated by an admin role field. A
  // stale `isAdmin: true` on its own (without `role == 'admin'` and
  // without `'admin'` in `roles[]`) is rejected. Legacy users predating
  // the role fields still pass through (no role field at all → trust the
  // flag, matches existing behavior).
  bool _hasAdminPrivilege() {
    final hasAdminFlag = widget.userData['isAdmin'] == true;
    if (!hasAdminFlag) return false;
    final role = widget.userData['role'] as String?;
    final rolesList =
        (widget.userData['roles'] as List?)?.cast<dynamic>() ?? const [];
    final hasRoleField = role != null || rolesList.isNotEmpty;
    if (!hasRoleField) return true; // legacy users — trust the bool
    return role == 'admin' || rolesList.contains('admin');
  }

  // Support agents have a dedicated workspace (SupportDashboardScreen,
  // CLAUDE.md §4.8) and shouldn't see the "switch hats" toggle at all.
  bool _isSupportAgent() {
    final role = widget.userData['role'] as String?;
    final rolesList =
        (widget.userData['roles'] as List?)?.cast<dynamic>() ?? const [];
    return role == 'support_agent' || rolesList.contains('support_agent');
  }

  // v12.7.0: View-mode toggle card.
  //  - Non-admin provider: 2 chips (נותן שירות / לקוח)
  //  - Admin: 3 chips     (ניהול / נותן שירות / לקוח)
  //
  // Defense-in-depth per CLAUDE.md §50: admin chip is gated by `_hasAdminPrivilege`,
  // which requires `isAdmin == true` AND a corroborating role field. A stale
  // `isAdmin: true` without a matching `role`/`roles[]` entry is rejected, so
  // a regular provider can never see admin-only options.
  Widget _buildViewModeToggleCard(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isAdmin = _hasAdminPrivilege();
    var current = ViewModeService.instance.mode;

    // Auto-correct a stuck `providerOnly` mode for non-admins. This can
    // happen if an admin previously switched into provider-preview mode
    // and was later demoted — their stored mode would otherwise leave
    // no chip selected (admin chip hidden, provider chip checks
    // ViewMode.normal). Reset to `normal` so the provider chip lights up.
    if (!isAdmin && current == ViewMode.providerOnly) {
      // ignore: discarded_futures
      ViewModeService.instance
          .setMode(uid: uid, mode: ViewMode.normal);
      current = ViewMode.normal;
    }

    Future<void> apply(ViewMode target, String successMsg) async {
      await ViewModeService.instance.setMode(uid: uid, mode: target);
      if (!context.mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMsg),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    final l = AppLocalizations.of(context);
    final chips = <Widget>[
      if (isAdmin)
        _buildModeChip(
          label: l.editManagement,
          icon: Icons.admin_panel_settings_rounded,
          selected: current == ViewMode.normal,
          gradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          onTap: () => apply(ViewMode.normal, l.editAdminModeActive),
        ),
      _buildModeChip(
        label: l.editServiceProvider,
        icon: Icons.work_outline_rounded,
        // For admin: providerOnly. For non-admin provider: normal = provider.
        selected: isAdmin
            ? current == ViewMode.providerOnly
            : current == ViewMode.normal,
        gradient: const [Color(0xFF0EA5E9), Color(0xFF3B82F6)],
        onTap: () => apply(
          isAdmin ? ViewMode.providerOnly : ViewMode.normal,
          l.editProviderModeActive,
        ),
      ),
      _buildModeChip(
        label: l.editCustomer,
        icon: Icons.visibility_rounded,
        selected: current == ViewMode.customer,
        gradient: const [Color(0xFF10B981), Color(0xFF22C55E)],
        onTap: () => apply(ViewMode.customer, l.editCustomerModeActive),
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 2, bottom: 8),
            child: Text(
              AppLocalizations.of(context).editViewMode,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
          Row(
            textDirection: TextDirection.rtl,
            children: [
              for (int i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: chips[i]),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeChip({
    required String label,
    required IconData icon,
    required bool selected,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: gradient,
                  )
                : null,
            color: selected ? null : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? Colors.transparent : const Color(0xFFE5E7EB),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: gradient.first.withValues(alpha: 0.30),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? Colors.white : const Color(0xFF6B7280),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : const Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // My Dogs — customer-only, private. Owner sees + edits their own dog
  // profiles from inside the Edit Profile screen.
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildMyDogsSection(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<List<DogProfile>>(
      stream: DogProfileService.instance.streamForOwner(uid),
      builder: (ctx, snap) {
        if (snap.hasError) return const SizedBox.shrink();
        final dogs = snap.data ?? const <DogProfile>[];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.pets_rounded,
                      color: Color(0xFF6366F1), size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(AppLocalizations.of(context).editMyDogs,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                ),
                if (dogs.isNotEmpty)
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const DogProfileListScreen()),
                    ),
                    style: TextButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(AppLocalizations.of(context).editShowAll,
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF1A1A2E),
                            fontWeight: FontWeight.w700)),
                  ),
              ]),
              const SizedBox(height: 10),
              if (dogs.isEmpty)
                InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const DogProfileBuilderScreen()),
                  ),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.add_circle_outline_rounded,
                            size: 28, color: Color(0xFF6366F1)),
                        const SizedBox(height: 6),
                        Text(AppLocalizations.of(context).editAddDogProfile,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF6366F1))),
                      ],
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 116,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: dogs.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) {
                      if (i == dogs.length) {
                        return InkWell(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    const DogProfileBuilderScreen()),
                          ),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: 92,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: const Color(0xFF6366F1),
                                  width: 1.2),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.add_rounded,
                                    color: Color(0xFF6366F1)),
                                const SizedBox(height: 4),
                                Text(AppLocalizations.of(context).editNewDog,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF6366F1),
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        );
                      }
                      final d = dogs[i];
                      final photo = safeImageProvider(d.photoUrl);
                      return InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  DogProfileBuilderScreen(existing: d)),
                        ),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 92,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border:
                                Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black
                                    .withValues(alpha: 0.04),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundColor:
                                    const Color(0xFFEEF2FF),
                                backgroundImage: photo,
                                child: photo == null
                                    ? const Icon(Icons.pets_rounded,
                                        color: Color(0xFF6366F1))
                                    : null,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                d.name.isEmpty ? AppLocalizations.of(context).editUnnamedDog : d.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1A1A2E)),
                              ),
                              if (d.breed.isNotEmpty)
                                Text(
                                  d.breed,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF6B7280)),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// v10.1.0: ADD SECOND IDENTITY BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class _AddSecondIdentitySheet extends StatefulWidget {
  final List<Map<String, dynamic>> mainCategories;
  final VoidCallback onCreated;

  const _AddSecondIdentitySheet({
    required this.mainCategories,
    required this.onCreated,
  });

  @override
  State<_AddSecondIdentitySheet> createState() => _AddSecondIdentitySheetState();
}

class _AddSecondIdentitySheetState extends State<_AddSecondIdentitySheet> {
  String? _selectedCatId;
  final _aboutCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _aboutCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_selectedCatId == null) return;
    final price = double.tryParse(_priceCtrl.text.trim());
    if (price == null || price <= 0) return;

    setState(() => _saving = true);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final cat = widget.mainCategories.firstWhere(
      (c) => c['id'] == _selectedCatId,
      orElse: () => <String, dynamic>{},
    );
    final catName = cat['name'] as String? ?? '';

    try {
      // Ensure primary listing exists first
      await ProviderListingService.migrateIfNeeded(uid);

      await ProviderListingService.createListing(
        uid: uid,
        identityIndex: 1,
        serviceType: catName,
        aboutMe: _aboutCtrl.text.trim(),
        pricePerHour: price,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onCreated();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF22C55E),
            content: Text(AppLocalizations.of(context).editSecondIdentityCreated),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).editGenericError(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 20),
            Text(AppLocalizations.of(context).editAddSecondIdentityTitle,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(AppLocalizations.of(context).editAddSecondIdentityDesc,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),

            // Category dropdown
            DropdownButtonFormField<String>(
              value: _selectedCatId,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).editCategoryLabel,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: widget.mainCategories.map((c) => DropdownMenuItem(
                value: c['id'] as String?,
                child: Text(c['name'] as String? ?? ''),
              )).toList(),
              onChanged: (v) => setState(() => _selectedCatId = v),
            ),
            const SizedBox(height: 16),

            // Price
            TextFormField(
              controller: _priceCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).editPriceLabel,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixText: '₪ ',
              ),
            ),
            const SizedBox(height: 16),

            // About
            TextFormField(
              controller: _aboutCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).chatServiceDescLabel,
                hintText: AppLocalizations.of(context).editSecondServiceDesc,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),

            // Create button
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _create,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(AppLocalizations.of(context).editCreateIdentity,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// v10.1.0: EDIT SECOND IDENTITY BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class _EditSecondIdentitySheet extends StatefulWidget {
  final Map<String, dynamic> listing;
  final List<Map<String, dynamic>> mainCategories;
  final VoidCallback onSaved;

  const _EditSecondIdentitySheet({
    required this.listing,
    required this.mainCategories,
    required this.onSaved,
  });

  @override
  State<_EditSecondIdentitySheet> createState() => _EditSecondIdentitySheetState();
}

class _EditSecondIdentitySheetState extends State<_EditSecondIdentitySheet> {
  late final TextEditingController _aboutCtrl;
  late final TextEditingController _priceCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _aboutCtrl = TextEditingController(text: widget.listing['aboutMe'] as String? ?? '');
    _priceCtrl = TextEditingController(
      text: ((widget.listing['pricePerHour'] as num?) ?? 0).toString(),
    );
  }

  @override
  void dispose() {
    _aboutCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final price = double.tryParse(_priceCtrl.text.trim());
    if (price == null || price <= 0) return;

    setState(() => _saving = true);
    final listingId = widget.listing['listingId'] as String? ?? '';

    try {
      await ProviderListingService.updateListing(listingId, {
        'aboutMe': _aboutCtrl.text.trim(),
        'pricePerHour': price,
      });
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF22C55E),
            content: Text(AppLocalizations.of(context).editIdentityUpdated),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).editGenericError(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.editDeleteIdentityTitle),
        content: Text(l10n.editDeleteIdentityConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.profCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.editDelete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _saving = true);
    try {
      final uid = widget.listing['uid'] as String? ?? '';
      final listingId = widget.listing['listingId'] as String? ?? '';
      await ProviderListingService.deleteListing(listingId, uid);
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text(AppLocalizations.of(context).editIdentityDeleted),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).editGenericError(e.toString()))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final serviceType = widget.listing['serviceType'] as String? ?? '';
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 20),
            Text(AppLocalizations.of(context).editEditingIdentity(serviceType),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),

            TextFormField(
              controller: _priceCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).editPriceLabel,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixText: '₪ ',
              ),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _aboutCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).chatServiceDescLabel,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),

            // Save button
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(AppLocalizations.of(context).editSaveChanges,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),

            // Delete button
            TextButton.icon(
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
              label: Text(AppLocalizations.of(context).editDeleteIdentity,
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
