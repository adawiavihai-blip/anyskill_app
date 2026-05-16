// B.3 (§80, 2026-05-14): _AddSecondIdentitySheet + _EditSecondIdentitySheet
// moved to edit_profile/widgets/edit_profile_widgets.dart. They stay private
// thanks to the `part` directive below.
library;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../l10n/app_localizations.dart';
import '../utils/input_sanitizer.dart';
import '../utils/error_mapper.dart';
import 'price_settings_screen.dart';
import 'dart:convert';
import 'dart:async';
import '../services/category_service.dart';
import '../services/cancellation_policy_service.dart';
import '../widgets/category_specs_widget.dart';
import '../services/cached_readers.dart';
import '../constants/quick_tags.dart';
import '../widgets/category_tags_selector.dart';
import '../widgets/price_list_widget.dart';
import '../services/provider_listing_service.dart';
// view_mode_service.dart used by view_mode_toggle_card.dart (§81 C.6).
import '../services/private_data_service.dart';
import '../services/profile_media_service.dart';
import '../services/profile_save_service.dart';
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
import 'edit_profile/widgets/view_mode_toggle_card.dart';

part 'edit_profile/widgets/edit_profile_widgets.dart';

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
  // §83 E.3 (2026-05-14): _kHourOptions moved to top-level const in
  // edit_profile_widgets.dart (part-of). Same library, same name.

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

  // 2026-05-15 — server-authoritative serviceType / subCategory.
  // `widget.userData` can be a STALE snapshot (profile_screen's
  // parent StreamBuilder occasionally pushes EditProfile with old
  // data). `_refreshRoleFlagsFromServer` does a fresh Source.server
  // read and stores the authoritative values here. Category
  // resolution prefers these over `widget.userData`.
  String _serverServiceType = '';
  String _serverSubCategory = '';

  // True once the user MANUALLY changes the category dropdown. After
  // that, no automatic resolution (snapshot re-emit, listing load,
  // server refresh) is allowed to clobber the selection.
  bool _userPickedCategory = false;

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

    // DEFENSIVE — re-read users/{uid} fresh from server to make sure
    // role flags (_isProvider / _isCustomer / _isVolunteer /
    // _isPendingExpert) are correct regardless of what widget.userData
    // had at mount time. Live bug 2026-05-15 — רועי צברי "תחום עיסוק
    // נעלם לפעמים": profile_screen's parent StreamBuilder occasionally
    // pushed EditProfile with a stale snapshot where `isProvider:
    // false`, which made the entire `if (_isProvider) ...[]` block in
    // build() vanish. Fresh fetch corrects local state within ~500ms
    // post-mount so the dropdowns appear without requiring browser
    // refresh.
    // ignore: discarded_futures
    _refreshRoleFlagsFromServer();
  }

  /// Fire-and-forget: pull the user doc directly from server and flip
  /// role flags + serviceType if they disagree with widget.userData.
  /// Never throws — stale widget data is the worst case we tolerate.
  ///
  /// 2026-05-15: extended to ALSO capture `serviceType` + `subCategory`
  /// as the authoritative resolution input. `widget.userData` can be a
  /// stale parent-StreamBuilder snapshot — the server doc is the truth.
  /// After capturing, re-runs `_applyCategoriesSnapshot` so the
  /// dropdown re-resolves against the fresh serviceType.
  Future<void> _refreshRoleFlagsFromServer() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      final d = snap.data() ?? const <String, dynamic>{};
      if (d.isEmpty) return;
      final freshIsProvider = d['isProvider'] == true;
      final freshIsCustomer = (d['isCustomer'] as bool?) ?? true;
      final freshIsVolunteer = (d['isVolunteer'] as bool?) ?? false;
      final freshIsPending = (d['isPendingExpert'] as bool?) ?? false;
      final freshServiceType = (d['serviceType'] as String? ?? '').trim();
      final freshSubCategory = (d['subCategory'] as String? ?? '').trim();

      final flagsChanged = freshIsProvider != _isProvider ||
          freshIsCustomer != _isCustomer ||
          freshIsVolunteer != _isVolunteer ||
          freshIsPending != _isPendingExpert;
      final serviceTypeChanged = freshServiceType != _serverServiceType ||
          freshSubCategory != _serverSubCategory;

      if (flagsChanged || serviceTypeChanged) {
        debugPrint(
            '[EditProfile] Server refresh — isProvider: $_isProvider→$freshIsProvider, '
            'serviceType: "$_serverServiceType"→"$freshServiceType"');
        setState(() {
          _isProvider = freshIsProvider;
          _isCustomer = freshIsCustomer;
          _isVolunteer = freshIsVolunteer;
          _isPendingExpert = freshIsPending;
          _serverServiceType = freshServiceType;
          _serverSubCategory = freshSubCategory;
        });
      }
      // Re-resolve the category dropdown against the fresh serviceType.
      // If categories are already loaded this fixes a dropdown that
      // resolved (or failed to) against stale widget.userData. If not
      // loaded yet, the next snapshot will pick up _serverServiceType.
      if (_categories.isNotEmpty) {
        _applyCategoriesSnapshot(_categories);
      }
    } catch (e) {
      // Network slow / permission denied / etc. — fine, widget.userData
      // is the worst case which is fine.
      debugPrint('[EditProfile] Server refresh failed: $e');
    }
  }

  /// Single source of truth for the serviceType the category dropdown
  /// should resolve. Priority: active listing → fresh server doc →
  /// widget.userData (potentially stale). All three are kept in sync;
  /// this picks the most authoritative non-empty value.
  String _bestServiceType() {
    if (_activeListingServiceType.isNotEmpty) return _activeListingServiceType;
    if (_serverServiceType.isNotEmpty) return _serverServiceType;
    return (widget.userData['serviceType'] as String? ?? '').trim();
  }

  /// Best subCategory hint — used by the self-heal path when a provider
  /// registered with `serviceType == parent name` and `subCategory`
  /// stored separately.
  String _bestSubCategory() {
    if (_serverSubCategory.isNotEmpty) return _serverSubCategory;
    return (widget.userData['subCategory'] as String? ?? '').trim();
  }

  /// One-shot fetch of categories — backup for the snapshot stream.
  /// Auto-retries up to 3 times with backoff so a flaky cold-start
  /// connect doesn't leave the dropdown spinning forever (live user
  /// report from רועי צברי 2026-05-14: profile-edit dropdown stuck on
  /// spinner even though he had a saved category).
  Future<void> _oneshotLoadCategories() async {
    const attempts = 3;
    const perAttemptTimeout = Duration(seconds: 6);
    const backoff = Duration(seconds: 2);
    for (int i = 0; i < attempts; i++) {
      if (i > 0) {
        await Future.delayed(backoff);
        if (!mounted) return;
        if (_mainCategories.isNotEmpty) return; // stream filled in meanwhile
      }
      try {
        // ROOT-CAUSE FIX (2026-05-15, רועי צברי "תחום עיסוק נעלם
        // לפעמים"): `.limit(100)` SILENTLY TRUNCATED the categories
        // collection. With Categories v3 (77+ categories) + all the
        // CSM additions, the collection is at/past 100 docs. Firestore
        // returns 100 docs by document-ID order — if "גרר אופנועים" or
        // "תחבורה" sorted beyond position 100, the resolution
        // `cats.firstWhere(name == serviceType)` found nothing →
        // category dropdown empty. The intermittency came from the
        // collection size hovering around the 100 boundary as admins
        // add/remove categories. Raised to 500 (same as the admin
        // tools — admin_demo_experts_tab, power_tools_footer,
        // schema_migration_service all use 500). 500 docs is a tiny,
        // cheap read for a categories collection.
        final snap = await FirebaseFirestore.instance
            .collection('categories')
            .limit(500)
            .get()
            .timeout(perAttemptTimeout);
        if (!mounted) return;
        final cats =
            snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        if (cats.isEmpty) {
          debugPrint('[EditProfile] One-shot got empty list (attempt ${i + 1})');
          continue;
        }
        _applyCategoriesSnapshot(cats);
        debugPrint(
            '[EditProfile] One-shot categories loaded: ${cats.length} docs '
            '(attempt ${i + 1})');
        return; // success
      } catch (e) {
        debugPrint(
            '[EditProfile] One-shot fetch failed (attempt ${i + 1}): $e');
        // Loop will retry after backoff. Snapshot stream may also still
        // win — _applyCategoriesSnapshot is idempotent so dual wins is fine.
      }
    }
    debugPrint(
        '[EditProfile] One-shot all $attempts attempts failed — relying on stream');
  }

  /// Single deterministic, idempotent category resolver. Called from
  /// the one-shot fetch, EVERY snapshot stream emit, the listing load,
  /// and the server-refresh. Same `cats` + same serviceType → same
  /// result, every time. Safe to call any number of times in any order.
  ///
  /// 2026-05-15 RE-ARCHITECTURE (רועי צברי "תחום עיסוק נעלם / לפעמים
  /// עובד לפעמים לא"): the old design had THREE racing writers
  /// (one-shot, stream, listing-load) each with subtly different
  /// resolution logic. This is now the ONLY resolver. It:
  ///   1. Uses `_bestServiceType()` — the most authoritative non-empty
  ///      serviceType (active listing → fresh server → widget.userData).
  ///   2. Resolves it to (mainId, subId) — handles serviceType being a
  ///      sub-cat name, a main-cat name, or main-name + separate
  ///      `subCategory` field (the legacy registration self-heal).
  ///   3. RESPECTS `_userPickedCategory` — once the user manually
  ///      changes the dropdown, automatic resolution NEVER touches the
  ///      selection again (only refreshes the items lists).
  ///   4. NEVER wipes valid state with empty data.
  void _applyCategoriesSnapshot(List<Map<String, dynamic>> cats) {
    if (!mounted) return;
    if (cats.isEmpty) {
      // EMPTY snapshot — don't WIPE existing state. Just record we've
      // seen at least one tick so the perpetual-spinner fallback clears.
      if (!_categoriesStreamFired) {
        setState(() => _categoriesStreamFired = true);
      }
      return;
    }
    if (!_categoriesStreamFired) _categoriesStreamFired = true;
    final mains =
        cats.where((c) => (c['parentId'] as String? ?? '').isEmpty).toList();

    // ── Resolve serviceType → (mainId, subId) ───────────────────────────
    final serviceType = _bestServiceType();
    String? mainId, subId;
    if (serviceType.isNotEmpty) {
      // (a) serviceType matches a SUB-category name (the common case —
      //     providers save `serviceType = sub-cat name`).
      final subMatch = cats.firstWhere(
        (c) =>
            c['name'] == serviceType &&
            (c['parentId'] as String? ?? '').isNotEmpty,
        orElse: () => <String, dynamic>{},
      );
      if (subMatch.isNotEmpty) {
        subId = subMatch['id'] as String?;
        mainId = subMatch['parentId'] as String?;
      } else {
        // (b) serviceType matches a MAIN-category name.
        final mainMatch = mains.firstWhere(
          (c) => c['name'] == serviceType,
          orElse: () => <String, dynamic>{},
        );
        mainId = mainMatch.isNotEmpty ? mainMatch['id'] as String? : null;
        // (c) Self-heal: serviceType == parent name AND `subCategory`
        //     stored separately (legacy provider_registration path).
        if (mainId != null) {
          final savedSub = _bestSubCategory();
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
    }
    debugPrint(
        '[EditProfile] Resolve serviceType="$serviceType" → mainId=$mainId subId=$subId '
        '(${cats.length} cats, userPicked=$_userPickedCategory)');

    // ── Decide the effective selection ──────────────────────────────────
    // If the user manually picked a category, their choice is sacred —
    // automatic resolution NEVER overrides it. Otherwise use the
    // resolved mainId (falling back to any prior selection so a
    // momentary failed resolution doesn't clear it).
    final String? effectiveMainId = _userPickedCategory
        ? _selectedMainCatId
        : (mainId ?? _selectedMainCatId);
    final String? effectiveSubId = _userPickedCategory
        ? _selectedSubCatId
        : (subId ?? _selectedSubCatId);

    // Derive subs from the EFFECTIVE main cat. If we can't derive any
    // (effectiveMainId null OR no subs in this snapshot), keep the
    // existing list — never wipe a populated sub-cat dropdown.
    final derivedSubs = effectiveMainId != null
        ? cats.where((c) => c['parentId'] == effectiveMainId).toList()
        : const <Map<String, dynamic>>[];
    final nextSubs =
        derivedSubs.isNotEmpty ? derivedSubs : _subCategories;

    setState(() {
      _categories = cats;
      if (mains.isNotEmpty) _mainCategories = mains;
      _selectedMainCatId = effectiveMainId;
      _subCategories = nextSubs;
      _selectedSubCatId = effectiveSubId;
    });

    // Load v2 schema for the resolved category (sub-cat name preferred,
    // else the main serviceType). Only when we don't already have one.
    if (_serviceSchema.isEmpty) {
      final subName = effectiveSubId != null
          ? cats
              .where((c) => c['id'] == effectiveSubId)
              .map((c) => c['name'] as String? ?? '')
              .firstOrNull
          : null;
      final schemaCat = (subName != null && subName.isNotEmpty)
          ? subName
          : serviceType;
      if (schemaCat.isNotEmpty) _loadV2SchemaFor(schemaCat);
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

  /// Re-resolve the category dropdown after the active listing's
  /// serviceType becomes known. The unified resolver
  /// [_applyCategoriesSnapshot] already prefers `_activeListingServiceType`
  /// via `_bestServiceType()` — so all this needs to do is RE-TRIGGER
  /// the resolver with the categories we already have. No duplicate
  /// resolution logic (the old `_applyListingCategoryFromServiceType`
  /// had its own subtly-different copy — that was a bug source).
  void _applyListingCategoryFromServiceType(String serviceType) {
    if (_categories.isNotEmpty) {
      _applyCategoriesSnapshot(_categories);
    }
  }

  // §85 (2026-05-14): All 4 media-picker methods delegate to
  // ProfileMediaService (lib/services/profile_media_service.dart). Screen
  // keeps setState + UI feedback; service does picker + Storage I/O.

  Future<void> _pickProfileImage() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ProfileMediaService.pickAndEncodeProfileImage();
      if (result == null || !mounted) return;
      if (result == ProfileMediaService.profileImageTooLargeSentinel) {
        messenger.showSnackBar(const SnackBar(
          content: Text('התמונה גדולה מדי — בחר/י תמונה קטנה יותר'),
          backgroundColor: Color(0xFFEF4444),
        ));
        return;
      }
      setState(() => _profileImageUrl = result);
    } catch (e) {
      if (!mounted) return;
      ErrorMapper.show(context, e);
    }
  }

  /// Maximum gallery images per provider — bumped from 6 to 10
  /// (רועי צברי request 2026-05-14). With Storage-backed uploads
  /// the doc-size pressure is gone, so 10 (or more in future) is safe.
  static const int _kMaxGalleryImages = 10;

  Future<void> _pickAndCompressGalleryImage() async {
    if (_galleryImages.length >= _kMaxGalleryImages) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF6366F1),
          content: Text(
              'הגעת למקסימום של 10 תמונות. הסר תמונה לפני העלאת חדשה.'),
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      // Pass uid so the service uploads to Firebase Storage instead of
      // base64. Avoids the 1 MB doc-size cap that caused the
      // "INTERNAL ASSERTION FAILED" race on save for providers with
      // many gallery images.
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final encoded = await ProfileMediaService.pickAndCompressGalleryImage(
        uid: uid,
      );
      if (encoded != null && mounted) {
        setState(() => _galleryImages.add(encoded));
      }
    } catch (e) {
      if (mounted) ErrorMapper.show(context, e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickCertificationImage() async {
    setState(() => _isLoading = true);
    try {
      final encoded = await ProfileMediaService.pickAndEncodeCertificationImage();
      if (encoded != null && mounted) {
        setState(() => _certificationImage = encoded);
      }
    } catch (e) {
      if (mounted) ErrorMapper.show(context, e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndUploadVerificationVideo() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() {
      _videoUploadInProgress = true;
      _videoUploadProgress = 0.0;
    });

    try {
      final downloadUrl = await ProfileMediaService.uploadVerificationVideo(
        uid: uid,
        onProgress: (progress) {
          if (mounted) setState(() => _videoUploadProgress = progress);
        },
      );
      if (downloadUrl == null || !mounted) return;

      setState(() => _verificationVideoUrl = downloadUrl);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ הסרטון הועלה בהצלחה! ממתין לאישור מנהל.'),
          backgroundColor: Colors.green,
        ),
      );
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

  // §83 E.3 (2026-05-14): _buildHourDropdown moved to part-of file.

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
    // Friendly error mapping — raw Firestore stack traces are scary
    // and unactionable (רועי צברי report 2026-05-14: saw the full
    // "FIRESTORE (12.9.0) INTERNAL ASSERTION FAILED" stack as
    // snackbar text). Map known patterns to short Hebrew messages.
    String saveErrMsg(Object e) {
      final s = e.toString();
      if (s.contains('INTERNAL ASSERTION FAILED') ||
          s.contains('ID: b815') ||
          s.contains('ID: ca9') ||
          s.contains('[cloud_firestore/internal]')) {
        // 2026-05-15: the §10.8.0 retry now does 5 attempts × 15s +
        // a final network bounce. If we still ended up here, the
        // SDK genuinely couldn't recover — refresh is the right
        // action. Message says exactly that instead of the misleading
        // "connection problem" (it's not a network issue at all —
        // it's an SDK watch-stream race).
        return 'תקלה זמנית בשמירה. רענן/י את הדף ונסה/י שוב';
      }
      if (s.contains('document-too-large') ||
          s.contains('bytes for the document exceeded')) {
        return 'הנתונים גדולים מדי — הסר/י תמונות ישנות מהגלריה ונסה/י שוב';
      }
      if (s.contains('permission-denied')) {
        return 'אין הרשאה לשמור — התחבר/י מחדש ונסה/י שוב';
      }
      if (s.contains('unavailable') || s.contains('deadline-exceeded')) {
        return 'בעיית חיבור — בדוק/י את הרשת ונסה/י שוב';
      }
      // Gallery upload failure surfaces here via the new throw-on-fail
      // path in ProfileMediaService (2026-05-15). The exception
      // message is already in Hebrew, so pass it through directly
      // instead of wrapping in the localized template.
      if (s.contains('העלאת התמונה לשרת נכשלה')) {
        return 'העלאת התמונה לשרת נכשלה — בדוק/י את החיבור ונסה/י שוב';
      }
      if (e == 'not-signed-in') return 'יש להתחבר כדי לשמור';
      // Fallback to localized generic — uses the localized template
      // but limits visible error string length so the snackbar stays
      // readable.
      final shortErr = s.length > 80 ? '${s.substring(0, 80)}…' : s;
      return l10n.saveError(shortErr);
    }

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

      // §84 (2026-05-14): All Firestore writes moved to ProfileSaveService.
      //   • users/{uid} main doc (set merge:true)
      //   • CachedReaders invalidation
      //   • private/identity email dual-write (best-effort)
      //   • provider_listings mirror sync (best-effort, provider only)
      //   • Auto-migrate listing when none exists
      // The screen now only builds the validated `payload` Map and calls
      // the service. Failures throw — caught by the catch block below.
      await ProfileSaveService.save(
        uid: uid,
        payload: payload,
        safeEmail: safeEmail,
        syncListings: _isProvider,
        activeListingId: _activeListingId,
        serviceTypeName: serviceTypeName,
        parentCategoryName: parentCategoryName,
      );

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

  // ── v10.1.0: Second Identity Card ──────────────────────────────────────────


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
                          ViewModeToggleCard(
                              isAdmin: _hasAdminPrivilege()),
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
                        _LockedPhoneField(
                          phoneDisplay: _phoneDisplay,
                          onAddPhone: _addPhoneFlow,
                        ),

                        const SizedBox(height: 20),

                        // ── Email ────────────────────────────────────────────────
                        _EmailField(
                          controller: _emailController,
                          lockedFromAuth: _emailLockedFromAuth,
                        ),

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
                          const _PendingExpertBanner(),

                        // ── Volunteer toggle (providers only) ────────────────────
                        // I.2 (§87): extracted to part file.
                        if (_isProvider) ...[
                          const SizedBox(height: 16),
                          _VolunteerToggleCard(
                            isVolunteer: _isVolunteer,
                            onChanged: (val) =>
                                setState(() => _isVolunteer = val),
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
                          _IdentityCardsSection(
                            cachedListings: _allListings,
                            activeListingId: _activeListingId,
                            userData: widget.userData,
                            onAddSecond: _openAddSecondIdentity,
                          ),
                          const SizedBox(height: 25),

                          // ── Main Category dropdown ──────────────────────────────
                          Text(
                            l10n.profileFieldCategoryMain,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          // ── ALWAYS render the cascading dropdown ──────────
                          // 2026-05-15: ROLLBACK of the §10.8.3 read-only
                          // fallback. The user expects the original
                          // cascade flow: pick category → sub-cats appear
                          // → pick sub-cat → CSM block opens. A read-only
                          // field blocks that interaction entirely.
                          //
                          // Now: the dropdown is ALWAYS rendered. While
                          // categories load (1-3s), the field is grey
                          // (onChanged: null) with the user's saved value
                          // shown as the hint TEXT — no spinning circle,
                          // no read-only block. As soon as categories
                          // arrive, _applyCategoriesSnapshot sets
                          // _selectedMainCatId + _selectedSubCatId from
                          // the saved serviceType, AND the dropdown
                          // becomes interactive — letting the user pick
                          // a different category if they want.
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
                              // While categories load, show the user's
                              // SAVED value as the hint text — they know
                              // the form has their data, the dropdown
                              // just isn't tappable yet. As soon as
                              // categories arrive, the value pre-selects
                              // and the dropdown becomes interactive.
                              hint: Builder(builder: (_) {
                                if (_mainCategories.isNotEmpty) {
                                  return Text(
                                    l10n.profileFieldCategoryMainHint,
                                    textAlign: TextAlign.right,
                                  );
                                }
                                final savedSvc =
                                    _activeListingServiceType.isNotEmpty
                                        ? _activeListingServiceType
                                        : ((widget.userData['serviceType']
                                                as String?) ??
                                            '');
                                return Text(
                                  savedSvc.isNotEmpty
                                      ? savedSvc
                                      : l10n.profileFieldCategoryMainHint,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: savedSvc.isNotEmpty
                                        ? const Color(0xFF1A1A2E)
                                        : const Color(0xFF9CA3AF),
                                    fontWeight: savedSvc.isNotEmpty
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                );
                              }),
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
                                  // Mark manual pick — automatic
                                  // resolution must NEVER override this.
                                  _userPickedCategory = true;
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
                                  _userPickedCategory = true;
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
                          // I.3 (§87): extracted to part file.
                          _TaxIdField(controller: _taxIdController),
                          const SizedBox(height: 20),

                          // ── הגדרות תשלום (Payment Settings) ─────────────────────────────────
                          // I.3 (§87): extracted to part file.
                          const _PaymentSettingsNotice(),
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
                          // I.2 (§87): extracted to part file.
                          _QuickTagsPicker(
                            selectedKeys: _selectedQuickTags,
                            onToggle: (key) => setState(() {
                              if (_selectedQuickTags.contains(key)) {
                                _selectedQuickTags.remove(key);
                              } else {
                                _selectedQuickTags.add(key);
                              }
                            }),
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
                          // G.3 (§85, 2026-05-14): extracted to part file.
                          _CancellationPolicyPicker(
                            selectedPolicy: _cancellationPolicy,
                            onChanged: (p) =>
                                setState(() => _cancellationPolicy = p),
                          ),

                          const SizedBox(height: 25),

                          // ── Working Hours (שעות עבודה) ─────────────────────────
                          // G.3 (§85, 2026-05-14): extracted to part file.
                          _WorkingHoursEditor(
                            workingHours: _workingHours,
                            dayNames: _dayNames(context),
                            onToggle: (dayIndex, enabled) {
                              setState(() {
                                if (enabled) {
                                  _workingHours[dayIndex] = {
                                    'from': '09:00',
                                    'to': '17:00',
                                  };
                                } else {
                                  _workingHours.remove(dayIndex);
                                }
                              });
                            },
                            onHoursChanged: (dayIndex, field, value) {
                              setState(() {
                                _workingHours[dayIndex]![field] = value;
                              });
                            },
                          ),

                          const SizedBox(height: 25),

                          // ── Business Description / Bio ──────────────────────────
                          // I.3 (§87): extracted to part file.
                          _BusinessBioField(controller: _aboutController),
                          const SizedBox(height: 30),

                          // ── Work Gallery / Portfolio ────────────────────────────
                          // I.1 (§87): extracted to part file.
                          _GallerySection(
                            galleryImages: _galleryImages,
                            onPickImage: _pickAndCompressGalleryImage,
                            onRemoveImage: (i) => setState(
                                () => _galleryImages.removeAt(i)),
                          ),
                          const SizedBox(height: 25),

                          // ── Certification Image ────────────────────────────────
                          // I.1 (§87): extracted to part file.
                          _CertificationImageSection(
                            imageData: _certificationImage,
                            onPick: _pickCertificationImage,
                            onClear: () =>
                                setState(() => _certificationImage = null),
                          ),
                          const SizedBox(height: 25),

                          // ── Video Verification Upload ───────────────────────────
                          // I.1 (§87): extracted to part file.
                          _VideoVerificationSection(
                            videoUrl: _verificationVideoUrl,
                            uploadInProgress: _videoUploadInProgress,
                            uploadProgress: _videoUploadProgress,
                            onPick: _pickAndUploadVerificationVideo,
                          ),
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

  // ─────────────────────────────────────────────────────────────────────
  // My Dogs — customer-only, private. Owner sees + edits their own dog
  // profiles from inside the Edit Profile screen.
  // ─────────────────────────────────────────────────────────────────────
}

