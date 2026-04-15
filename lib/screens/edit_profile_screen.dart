import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/app_localizations.dart';
import '../utils/input_sanitizer.dart';
import 'price_settings_screen.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import '../services/category_service.dart';
import '../services/cancellation_policy_service.dart';
import '../widgets/category_specs_widget.dart';
import '../constants/quick_tags.dart';
import '../widgets/category_tags_selector.dart';
import '../widgets/price_list_widget.dart';
import '../services/provider_listing_service.dart';
import '../services/view_mode_service.dart';
import '../utils/safe_image_provider.dart';
import '../features/pet_stay/models/dog_profile.dart';
import '../features/pet_stay/services/dog_profile_service.dart';
import '../features/pet_stay/screens/dog_profile_builder_screen.dart';
import '../features/pet_stay/screens/dog_profile_list_screen.dart';
import 'identity_onboarding_screen.dart';

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
  late TextEditingController _aboutController;
  late TextEditingController _priceController;
  late TextEditingController _taxIdController;
  late TextEditingController _videoUrlController;

  String? _selectedMainCatId; // doc ID of selected main category
  String? _selectedSubCatId; // doc ID of selected sub-category (nullable)
  List<Map<String, dynamic>> _mainCategories = [];
  List<Map<String, dynamic>> _subCategories = []; // subs for selected main
  List<SchemaField> _categorySchema = []; // v1 legacy — kept for fallback
  ServiceSchema _serviceSchema = ServiceSchema.empty(); // v2 — full schema
  Map<String, dynamic> _categoryDetails = {};
  Map<String, dynamic> _priceList = {};

  int? _responseTimeMinutes;
  String _cancellationPolicy = 'flexible';
  Set<String> _selectedQuickTags = {};
  Set<String> _selectedCategoryTags = {};

  /// Weekly working hours — keys are weekday indices (0=Sunday..6=Saturday),
  /// values are `{"from": "09:00", "to": "17:00"}`.
  /// Empty map = "all hours" (legacy behaviour — no restrictions).
  Map<int, Map<String, String>> _workingHours = {};

  static const _kDayNames = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת'];
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

  bool _isCustomer = false;
  bool _isProvider = false;
  bool _isVolunteer = false;
  bool _isPendingExpert = false;

  List<Map<String, dynamic>> _categories = [];
  late StreamSubscription<List<Map<String, dynamic>>> _categorySub;

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

    // Phone: prefer Firestore value, fall back to Firebase Auth phoneNumber
    _phoneDisplay = (widget.userData['phone'] as String? ?? '').trim();
    if (_phoneDisplay.isEmpty) {
      _phoneDisplay = (widget.userData['phoneNumber'] as String? ?? '').trim();
    }
    if (_phoneDisplay.isEmpty) {
      _phoneDisplay = FirebaseAuth.instance.currentUser?.phoneNumber ?? '';
    }

    _isCustomer = widget.userData['isCustomer'] ?? true;
    _isProvider = widget.userData['isProvider'] ?? false;
    _isVolunteer = widget.userData['isVolunteer'] ?? false;
    _isPendingExpert = widget.userData['isPendingExpert'] ?? false;
    _responseTimeMinutes = widget.userData['responseTimeMinutes'] as int?;
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

    _categorySub = CategoryService.stream().listen((cats) {
      if (!mounted) return;
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
      }

      final subs =
          mainId != null
              ? cats.where((c) => c['parentId'] == mainId).toList()
              : <Map<String, dynamic>>[];

      setState(() {
        _categories = cats;
        _mainCategories = mains;
        _selectedMainCatId = _selectedMainCatId ?? mainId;
        _subCategories = subs;
        _selectedSubCatId = _selectedSubCatId ?? subId;
      });
      // Load v2 schema for the resolved category. `serviceType` always
      // holds the most specific name (sub-category if one is set, else
      // parent), which is exactly what the schema is keyed by.
      final resolvedCatName = widget.userData['serviceType'] as String? ?? '';
      if (resolvedCatName.isNotEmpty && _serviceSchema.isEmpty) {
        _loadV2SchemaFor(resolvedCatName);
      }
    });
  }

  /// Loads the v2 [ServiceSchema] for the given category name and merges
  /// its defaults into provider state. If the provider has not yet picked
  /// a cancellation policy, the schema's `defaultPolicy` is auto-selected.
  Future<void> _loadV2SchemaFor(String categoryName) async {
    if (categoryName.trim().isEmpty) return;
    try {
      final schema = await loadServiceSchemaFor(categoryName);
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
    _aboutController.dispose();
    _priceController.dispose();
    _taxIdController.dispose();
    _videoUrlController.dispose();
    super.dispose();
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
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 300,
      maxHeight: 300,
      imageQuality: 50,
    );

    if (image != null) {
      Uint8List imageBytes = await image.readAsBytes();
      setState(() {
        _profileImageUrl = "data:image/png;base64,${base64Encode(imageBytes)}";
      });
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
            content: Text('שגיאה בהעלאת הסרטון: $e'),
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

    setState(() => _isLoading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final savedSuccess = l10n.saveSuccess;
    String saveErrMsg(Object e) => l10n.saveError('$e');

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
      final Map<String, dynamic> payload = {
        'name': safeName, // ← sanitized
        'isCustomer': _isCustomer,
        'isProvider': _isProvider,
        if (_phoneDisplay.isNotEmpty) 'phone': _phoneDisplay,
        if (_profileImageUrl != null) 'profileImage': _profileImageUrl,
        if (_isProvider && serviceTypeName != null)
          'serviceType': serviceTypeName
        else if (!_isProvider)
          'serviceType': 'לקוח',
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
        payload['pricePerHour'] = double.tryParse(_priceController.text) ?? 0.0;
        payload['aboutMe'] = aboutResult!.value; // ← sanitized
        payload['gallery'] = _galleryImages;
        payload['taxId'] = taxResult!.value; // ← sanitized
        payload['quickTags'] = _selectedQuickTags.toList();
        payload['categoryTags'] = _selectedCategoryTags.toList();
        payload['cancellationPolicy'] = _cancellationPolicy;
        payload['videoUrl'] = videoUrlResult?.value ?? ''; // ← sanitized
        if (_responseTimeMinutes != null) {
          payload['responseTimeMinutes'] = _responseTimeMinutes;
        }
        // Weekly working hours (convert Map<int,...> → Map<String,...> for Firestore)
        if (_workingHours.isNotEmpty) {
          payload['workingHours'] = {
            for (final e in _workingHours.entries) '${e.key}': e.value,
          };
        } else {
          payload['workingHours'] = FieldValue.delete();
        }
        // Dynamic v2 service schema values: fields + _bundles + _surcharge.
        // We always write the map (even empty) so deletes propagate too.
        payload['categoryDetails'] = _categoryDetails;
        // Structured price list (category-specific, e.g. balloon decorators)
        if (_priceList.isNotEmpty) {
          payload['priceList'] = _priceList;
        }
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update(payload);

      // v10.1.0: Dual-write — sync identity-specific fields to provider_listings
      if (_isProvider && uid != null) {
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
                        const Text('הוסף זהות מקצועית שנייה',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A2E),
                            )),
                        const SizedBox(height: 4),
                        Text(
                          'הרוויחו יותר — הציעו שירות נוסף תחת אותו חשבון',
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
                      index == 0 ? 'זהות ראשית' : 'זהות שנייה',
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
                  child: const Text('עורך כעת',
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

  Widget _buildLockedPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Icon(Icons.lock_rounded, size: 13, color: Color(0xFF6366F1)),
            const SizedBox(width: 4),
            const Text(
              'מספר טלפון',
              style: TextStyle(fontWeight: FontWeight.bold),
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
                  _phoneDisplay.isEmpty ? '—' : _phoneDisplay,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 15,
                    color:
                        _phoneDisplay.isEmpty
                            ? Colors.grey[400]
                            : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.phone_rounded,
                size: 17,
                color:
                    _phoneDisplay.isEmpty
                        ? Colors.grey[400]
                        : const Color(0xFF6366F1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Text(
            'מספר הטלפון מאומת ולא ניתן לשינוי',
            style: TextStyle(fontSize: 11, color: Colors.grey),
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
      child: const Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.amber,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'הבקשה שלך בבדיקה 🕐',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                SizedBox(height: 4),
                Text(
                  'הצוות שלנו בודק את הפרטים ויחזור אליך בקרוב.',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, color: Colors.brown),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApplyToBeExpertButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: GestureDetector(
        onTap: _showExpertApplicationForm,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.work_outline_rounded, color: Colors.white, size: 22),
              SizedBox(width: 10),
              Text(
                'רוצה לעבוד ולהרוויח כסף? לחץ כאן',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showExpertApplicationForm() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => _ExpertApplicationSheet(
            mainCategories: _mainCategories,
            onSubmit: _submitExpertApplication,
          ),
    );
  }

  Future<void> _submitExpertApplication({
    required String category,
    required String taxId,
    required String aboutMe,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.update(FirebaseFirestore.instance.collection('users').doc(uid), {
        'isPendingExpert': true,
        'expertApplicationData': {
          'category': category,
          'taxId': taxId,
          'aboutMe': aboutMe,
          'submittedAt': FieldValue.serverTimestamp(),
        },
      });
      batch.set(FirebaseFirestore.instance.collection('activity_log').doc(), {
        'type': 'expert_application',
        'userId': uid,
        'userName': widget.userData['name'] ?? '',
        'category': category,
        'priority': 'high',
        'timestamp': FieldValue.serverTimestamp(),
        'message': 'בקשה להצטרפות כמומחה: ${widget.userData['name'] ?? uid}',
        'expireAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 30))),
      });
      await batch.commit();
      if (mounted) {
        setState(() => _isPendingExpert = true);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('✅ הבקשה שלך נשלחה! נחזור אליך בקרוב.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
        );
      }
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
                        if (_isProvider || widget.userData['isAdmin'] == true)
                          _buildViewModeToggleCard(context),
                        if (_isProvider || widget.userData['isAdmin'] == true)
                          const SizedBox(height: 16),
                        // ── Dogs (customers only — private, owner-only view) ──
                        if (!_isProvider) ...[
                          _buildMyDogsSection(context),
                          const SizedBox(height: 18),
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
                              const Text(
                                'העלה תמונת פנים ברורה',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'פרופילים עם תמונה ברורה נהנים מפי 3 יותר פניות',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF6366F1),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        Text(
                          l10n.profileFieldName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
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

                        const SizedBox(height: 25),

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
                              const Text(
                                'שינוי סוג חשבון מתבצע מול שירות הלקוחות בלבד',
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          )
                        else if (_isPendingExpert)
                          _buildPendingExpertBanner()
                        else
                          _buildApplyToBeExpertButton(),

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
                                  const Text(
                                    'אני מעוניין להתנדב',
                                    style: TextStyle(
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
                                  'הצע את כישוריך ללא עלות לאנשים הזקוקים לעזרה',
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
                          const Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              'הזהויות המקצועיות שלך',
                              style: TextStyle(
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
                          // Show a spinner until the CategoryService stream delivers
                          // the first batch.  An empty-items DropdownButtonFormField is
                          // visually non-responsive on Flutter Web.
                          if (_mainCategories.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          else
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
                              hint: Text(
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
                              onChanged: (val) {
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
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.construction_rounded,
                                      color: Color(0xFFF59E0B),
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'הגדרות תשלום בקרוב',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: Color(0xFF1A1A2E),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'אנו עוברים לספק תשלומים ישראלי. בינתיים בקשות משיכה מטופלות ידנית על ידי הצוות.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF7C2D12),
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // ── Price Settings shortcut ────────────────────────────
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
                              child: const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.arrow_back_ios_new_rounded,
                                        color: Colors.white70,
                                        size: 14,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'הגדרות מתקדמות',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        'הגדרות תמחור',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(
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
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextField(
                            controller: _priceController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.start,
                            decoration: InputDecoration(
                              hintText: l10n.profileFieldPriceHint,
                            ),
                          ),

                          // ── v2 Service Schema (fields + bundles + surcharge + deposit) ──
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

                          // ── Structured price list (category-specific) ──
                          if (hasPriceList(widget.userData))
                            PriceListEditor(
                              type: priceListType(widget.userData),
                              initialData: _priceList,
                              onChanged: (val) => _priceList = val,
                            ),

                          const SizedBox(height: 20),
                          Text(
                            l10n.profileFieldResponseTime,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.profileFieldResponseTimeHint,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                for (final minutes in [5, 10, 15, 30, 60])
                                  GestureDetector(
                                    onTap:
                                        () => setState(
                                          () =>
                                              _responseTimeMinutes =
                                                  _responseTimeMinutes ==
                                                          minutes
                                                      ? null
                                                      : minutes,
                                        ),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            _responseTimeMinutes == minutes
                                                ? const Color(0xFF6366F1)
                                                : Colors.white,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color:
                                              _responseTimeMinutes == minutes
                                                  ? const Color(0xFF6366F1)
                                                  : Colors.grey.shade300,
                                        ),
                                      ),
                                      child: Text(
                                        minutes == 60
                                            ? l10n.timeOneHour
                                            : '~$minutesד\'',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color:
                                              _responseTimeMinutes == minutes
                                                  ? Colors.white
                                                  : Colors.grey[700],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
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
                            'שעות עבודה',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              'סמן את הימים ושעות העבודה שלך',
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
                                      _kDayNames[dayIndex],
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
                                      'לא עובד',
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

                          // ── Video Verification Upload ───────────────────────────
                          const Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              'סרטון היכרות',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              'הוסף סרטון קצר (עד 60 שניות) שמציג אותך ואת כישוריך. הסרטון יופיע בפרופיל שלך לאחר אישור מנהל.',
                              textAlign: TextAlign.right,
                              style: TextStyle(
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
                                            'מעלה... ${(_videoUploadProgress * 100).toInt()}%',
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
                                                ? 'סרטון הועלה — לחץ להחלפה'
                                                : 'העלה סרטון היכרות (עד 60 שניות)',
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
                            const Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: Text(
                                'ממתין לאישור מנהל — יופיע בפרופיל לאחר האישור',
                                style: TextStyle(
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

  // v12.7.0: View-mode toggle card.
  //  - Non-admin provider: 2 chips (נותן שירות / לקוח)
  //  - Admin: 3 chips     (ניהול / נותן שירות / לקוח)
  Widget _buildViewModeToggleCard(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isAdmin = widget.userData['isAdmin'] == true;
    final current = ViewModeService.instance.mode;

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

    final chips = <Widget>[
      if (isAdmin)
        _buildModeChip(
          label: 'ניהול',
          icon: Icons.admin_panel_settings_rounded,
          selected: current == ViewMode.normal,
          gradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          onTap: () => apply(ViewMode.normal, 'מצב ניהול פעיל'),
        ),
      _buildModeChip(
        label: 'נותן שירות',
        icon: Icons.work_outline_rounded,
        // For admin: providerOnly. For non-admin provider: normal = provider.
        selected: isAdmin
            ? current == ViewMode.providerOnly
            : current == ViewMode.normal,
        gradient: const [Color(0xFF0EA5E9), Color(0xFF3B82F6)],
        onTap: () => apply(
          isAdmin ? ViewMode.providerOnly : ViewMode.normal,
          'מצב נותן שירות פעיל',
        ),
      ),
      _buildModeChip(
        label: 'לקוח',
        icon: Icons.visibility_rounded,
        selected: current == ViewMode.customer,
        gradient: const [Color(0xFF10B981), Color(0xFF22C55E)],
        onTap: () => apply(ViewMode.customer, 'מצב לקוח פעיל'),
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
          const Padding(
            padding: EdgeInsets.only(right: 2, bottom: 8),
            child: Text(
              'מצב תצוגה',
              style: TextStyle(
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
                const Expanded(
                  child: Text('הכלבים שלי',
                      style: TextStyle(
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
                    child: const Text('הצג הכל',
                        style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6366F1),
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
                    child: const Column(
                      children: [
                        Icon(Icons.add_circle_outline_rounded,
                            size: 28, color: Color(0xFF6366F1)),
                        SizedBox(height: 6),
                        Text('הוסף פרופיל כלב',
                            style: TextStyle(
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
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_rounded,
                                    color: Color(0xFF6366F1)),
                                SizedBox(height: 4),
                                Text('כלב חדש',
                                    style: TextStyle(
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
                                d.name.isEmpty ? 'ללא שם' : d.name,
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

// ── Expert Application Bottom Sheet ─────────────────────────────────────────
class _ExpertApplicationSheet extends StatefulWidget {
  final List<Map<String, dynamic>> mainCategories;
  final Future<void> Function({
    required String category,
    required String taxId,
    required String aboutMe,
  })
  onSubmit;

  const _ExpertApplicationSheet({
    required this.mainCategories,
    required this.onSubmit,
  });

  @override
  State<_ExpertApplicationSheet> createState() =>
      _ExpertApplicationSheetState();
}

class _ExpertApplicationSheetState extends State<_ExpertApplicationSheet> {
  String? _selectedCategory;
  final _taxIdCtrl = TextEditingController();
  final _aboutCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _taxIdCtrl.dispose();
    _aboutCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder:
          (_, scrollCtrl) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Header
                const Text(
                  'הגש מועמדות כמומחה',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'מלא את הפרטים ואנחנו נבדוק את הבקשה שלך',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 24),

                // Category
                const Text(
                  'תחום עיסוק *',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  hint: const Text('בחר תחום', textAlign: TextAlign.right),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                  items:
                      widget.mainCategories.map((cat) {
                        return DropdownMenuItem<String>(
                          value: cat['name'] as String,
                          child: Text(cat['name'] as String),
                        );
                      }).toList(),
                  onChanged: (val) => setState(() => _selectedCategory = val),
                ),
                const SizedBox(height: 16),

                // Tax / ID
                const Text(
                  'מספר ת.ז. / ח.פ. *',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _taxIdCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    hintText: 'הכנס מספר זהות',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // About Me
                const Text(
                  'ספר על עצמך *',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _aboutCtrl,
                  maxLines: 4,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    hintText: 'תאר את הניסיון שלך, השירותים שאתה מציע...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Submit
                ElevatedButton(
                  onPressed: _submitting ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 54),
                    backgroundColor: const Color(0xFF6366F1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child:
                      _submitting
                          ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                          : const Text(
                            'שלח בקשה',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _handleSubmit() async {
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('בחר תחום עיסוק'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_taxIdCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הכנס מספר זהות'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_aboutCtrl.text.trim().length < 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('כתוב לפחות 20 תווים על עצמך'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(
        category: _selectedCategory!,
        taxId: _taxIdCtrl.text.trim(),
        aboutMe: _aboutCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
          const SnackBar(
            backgroundColor: Color(0xFF22C55E),
            content: Text('זהות מקצועית שנייה נוצרה בהצלחה! 🎉'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e')),
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
            const Text('הוספת זהות מקצועית שנייה',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text('בחר קטגוריה חדשה, מחיר ותיאור — הפרופיל השני יוצג בנפרד בחיפוש',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),

            // Category dropdown
            DropdownButtonFormField<String>(
              value: _selectedCatId,
              decoration: InputDecoration(
                labelText: 'קטגוריה מקצועית',
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
                labelText: 'מחיר לשעה (₪)',
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
                labelText: 'תיאור השירות',
                hintText: 'ספרו ללקוחות על השירות השני שלכם...',
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
                    : const Text('צור זהות מקצועית',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
          const SnackBar(
            backgroundColor: Color(0xFF22C55E),
            content: Text('הזהות המקצועית עודכנה בהצלחה'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('מחיקת זהות מקצועית'),
        content: const Text('האם למחוק את הזהות המקצועית השנייה? הפעולה לא ניתנת לביטול.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('מחק', style: TextStyle(color: Colors.red)),
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
          const SnackBar(
            backgroundColor: Color(0xFFEF4444),
            content: Text('הזהות המקצועית נמחקה'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('שגיאה: $e')));
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
            Text('עריכת $serviceType',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),

            TextFormField(
              controller: _priceCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'מחיר לשעה (₪)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixText: '₪ ',
              ),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _aboutCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'תיאור השירות',
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
                    : const Text('שמור שינויים',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),

            // Delete button
            TextButton.icon(
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
              label: const Text('מחק זהות מקצועית',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
