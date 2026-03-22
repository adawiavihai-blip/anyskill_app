import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/app_localizations.dart';
import 'price_settings_screen.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import '../services/category_service.dart';
import '../services/cancellation_policy_service.dart';
import '../constants/quick_tags.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  const EditProfileScreen({super.key, required this.userData});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _aboutController;
  late TextEditingController _priceController;
  late TextEditingController _taxIdController;
  
  String? _selectedMainCatId;       // doc ID of selected main category
  String? _selectedSubCatId;        // doc ID of selected sub-category (nullable)
  List<Map<String, dynamic>> _mainCategories = [];
  List<Map<String, dynamic>> _subCategories  = []; // subs for selected main

  int?   _responseTimeMinutes;
  String _cancellationPolicy = 'flexible';
  Set<String> _selectedQuickTags = {};

  String? _profileImageUrl;
  String  _phoneDisplay = '';   // read-only — shown from Auth / Firestore
  List<dynamic> _galleryImages = [];
  bool _isLoading = false;

  String? _verificationVideoUrl;
  bool   _videoUploadInProgress = false;
  double _videoUploadProgress   = 0.0;

  bool _isCustomer     = false;
  bool _isProvider     = false;
  bool _isVolunteer    = false;
  bool _isPendingExpert = false;

  List<Map<String, dynamic>> _categories = [];
  late StreamSubscription<List<Map<String, dynamic>>> _categorySub;

  @override
  void initState() {
    super.initState();
    _nameController  = TextEditingController(text: widget.userData['name']);
    _aboutController = TextEditingController(text: widget.userData['aboutMe'] ?? widget.userData['bio'] ?? "");
    _priceController = TextEditingController(text: (widget.userData['pricePerHour'] ?? "0").toString());
    _taxIdController = TextEditingController(text: widget.userData['taxId'] as String? ?? '');
    _galleryImages = List.from(widget.userData['gallery'] ?? []);
    _selectedQuickTags = Set<String>.from(
        (widget.userData['quickTags'] as List? ?? []).cast<String>());
    _profileImageUrl       = widget.userData['profileImage'];
    _verificationVideoUrl  = widget.userData['verificationVideoUrl'] as String?;

    // Phone: prefer Firestore value, fall back to Firebase Auth phoneNumber
    _phoneDisplay = (widget.userData['phone']        as String? ?? '').trim();
    if (_phoneDisplay.isEmpty) {
      _phoneDisplay = (widget.userData['phoneNumber'] as String? ?? '').trim();
    }
    if (_phoneDisplay.isEmpty) {
      _phoneDisplay = FirebaseAuth.instance.currentUser?.phoneNumber ?? '';
    }

    _isCustomer     = widget.userData['isCustomer']     ?? true;
    _isProvider     = widget.userData['isProvider']     ?? false;
    _isVolunteer    = widget.userData['isVolunteer']    ?? false;
    _isPendingExpert = widget.userData['isPendingExpert'] ?? false;
    _responseTimeMinutes = widget.userData['responseTimeMinutes'] as int?;
    _cancellationPolicy  = widget.userData['cancellationPolicy'] as String? ?? 'flexible';

    _categorySub = CategoryService.stream().listen((cats) {
      if (!mounted) return;
      final mains = cats.where((c) => (c['parentId'] as String? ?? '').isEmpty).toList();
      final serviceType = widget.userData['serviceType'] as String?;

      // Resolve existing serviceType into main-category ID + optional sub-category ID
      final subMatch = cats.firstWhere(
        (c) => c['name'] == serviceType && (c['parentId'] as String? ?? '').isNotEmpty,
        orElse: () => <String, dynamic>{},
      );
      String? mainId, subId;
      if (subMatch.isNotEmpty) {
        subId  = subMatch['id']       as String?;
        mainId = subMatch['parentId'] as String?;
      } else {
        final mainMatch = mains.firstWhere(
          (c) => c['name'] == serviceType,
          orElse: () => <String, dynamic>{},
        );
        mainId = mainMatch.isNotEmpty ? mainMatch['id'] as String? : null;
      }

      final subs = mainId != null
          ? cats.where((c) => c['parentId'] == mainId).toList()
          : <Map<String, dynamic>>[];

      setState(() {
        _categories        = cats;
        _mainCategories    = mains;
        _selectedMainCatId = _selectedMainCatId ?? mainId;
        _subCategories     = subs;
        _selectedSubCatId  = _selectedSubCatId ?? subId;
      });
    });
  }

  @override
  void dispose() {
    _categorySub.cancel();
    _nameController.dispose();
    _aboutController.dispose();
    _priceController.dispose();
    _taxIdController.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, maxWidth: 300, maxHeight: 300, imageQuality: 50);

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
      maxWidth:     600,
      maxHeight:    600,
      imageQuality: 60,   // ← JPEG compression; prevents Firestore 1 MB overflow
    );

    if (image != null) {
      setState(() => _isLoading = true);
      try {
        final Uint8List imageBytes = await image.readAsBytes();
        final String   encoded     = base64Encode(imageBytes);

        // Sanity-check: warn if a single image is still unusually large
        // (e.g. a PNG screenshot that imageQuality cannot compress further).
        if (encoded.length > 150000) {
          debugPrint(
              'EditProfile: gallery image is ${encoded.length ~/ 1024} KB '
              'after compression — consider a lower-res source.');
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
      _videoUploadProgress   = 0.0;
    });

    try {
      final ref = FirebaseStorage.instance
          .ref('users/$uid/verification_video.mp4');
      final bytes = await video.readAsBytes();
      final task  = ref.putData(bytes, SettableMetadata(contentType: 'video/mp4'));

      task.snapshotEvents.listen((snap) {
        if (!mounted) return;
        final progress = snap.bytesTransferred / (snap.totalBytes == 0 ? 1 : snap.totalBytes);
        setState(() => _videoUploadProgress = progress);
      });

      await task;
      final downloadUrl = await ref.getDownloadURL();

      // Save URL to Firestore immediately; reset verification flag so admin re-approves
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'verificationVideoUrl':  downloadUrl,
        'videoVerifiedByAdmin':  false,
      });

      if (mounted) {
        setState(() => _verificationVideoUrl = downloadUrl);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ הסרטון הועלה בהצלחה! ממתין לאישור מנהל.'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('שגיאה בהעלאת הסרטון: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _videoUploadInProgress = false);
    }
  }

  Future<void> _saveProfile() async {
    final l10n = AppLocalizations.of(context);
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.validationNameRequired), backgroundColor: Colors.orange));
      return;
    }
    if (name.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.validationNameLength), backgroundColor: Colors.orange));
      return;
    }

    if (!_isCustomer && !_isProvider) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.validationRoleRequired)));
      return;
    }

    if (_isProvider) {
      // Validate against the dropdown's own state (_selectedMainCatId), not the
      // stale _selectedCategory field loaded from userData.
      if (_selectedMainCatId == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.validationCategoryRequired), backgroundColor: Colors.orange));
        return;
      }
      final price = double.tryParse(_priceController.text.trim());
      if (price == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.validationPriceInvalid), backgroundColor: Colors.orange));
        return;
      }
      if (price <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.validationPricePositive), backgroundColor: Colors.orange));
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
      String? serviceTypeName;
      if (_selectedSubCatId != null) {
        final sub = _categories.firstWhere(
          (c) => c['id'] == _selectedSubCatId,
          orElse: () => <String, dynamic>{},
        );
        serviceTypeName = sub.isNotEmpty ? sub['name'] as String? : null;
      } else if (_selectedMainCatId != null) {
        final main = _mainCategories.firstWhere(
          (c) => c['id'] == _selectedMainCatId,
          orElse: () => <String, dynamic>{},
        );
        serviceTypeName = main.isNotEmpty ? main['name'] as String? : null;
      }

      // Build payload — only include keys with non-null values.
      // The Firestore Web SDK throws INTERNAL ASSERTION FAILED: Unexpected state
      // when update() receives a null value.  Omitting the key is the correct
      // approach for optional fields; use FieldValue.delete() only when you
      // explicitly want to remove an existing field.
      final Map<String, dynamic> payload = {
        'name':       _nameController.text.trim(),
        'isCustomer': _isCustomer,
        'isProvider': _isProvider,
        // Always persist verified phone so it survives future profile edits
        if (_phoneDisplay.isNotEmpty) 'phone': _phoneDisplay,
        if (_profileImageUrl != null) 'profileImage': _profileImageUrl,
        if (_isProvider && serviceTypeName != null)
          'serviceType': serviceTypeName
        else if (!_isProvider)
          'serviceType': 'לקוח',
        // subCategoryId: write the value when set, delete the field when cleared
        if (_isProvider && _selectedSubCatId != null)
          'subCategoryId': _selectedSubCatId
        else if (_isProvider && _selectedSubCatId == null)
          'subCategoryId': FieldValue.delete(),
      };

      // Provider-only fields — never written for pure customers
      if (_isProvider) {
        payload['isVolunteer']       = _isVolunteer;
        payload['pricePerHour']      = double.tryParse(_priceController.text) ?? 0.0;
        payload['aboutMe']           = _aboutController.text.trim();
        payload['gallery']           = _galleryImages;
        payload['taxId']             = _taxIdController.text.trim();
        payload['quickTags']         = _selectedQuickTags.toList();
        payload['cancellationPolicy']= _cancellationPolicy;
        // responseTimeMinutes is optional — omit rather than write null
        if (_responseTimeMinutes != null) {
          payload['responseTimeMinutes'] = _responseTimeMinutes;
        }
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update(payload);
      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(SnackBar(backgroundColor: Colors.green, content: Text(savedSuccess)));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(saveErrMsg(e))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
            const Text('מספר טלפון',
                style: TextStyle(fontWeight: FontWeight.bold)),
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
                    color: _phoneDisplay.isEmpty ? Colors.grey[400] : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.phone_rounded, size: 17,
                  color: _phoneDisplay.isEmpty
                      ? Colors.grey[400]
                      : const Color(0xFF6366F1)),
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
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('הבקשה שלך בבדיקה 🕐',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                SizedBox(height: 4),
                Text('הצוות שלנו בודק את הפרטים ויחזור אליך בקרוב.',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12, color: Colors.brown)),
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
              Text('רוצה לעבוד ולהרוויח כסף? לחץ כאן',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
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
      builder: (_) => _ExpertApplicationSheet(
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
      batch.update(
        FirebaseFirestore.instance.collection('users').doc(uid),
        {
          'isPendingExpert': true,
          'expertApplicationData': {
            'category': category,
            'taxId': taxId,
            'aboutMe': aboutMe,
            'submittedAt': FieldValue.serverTimestamp(),
          },
        },
      );
      batch.set(
        FirebaseFirestore.instance.collection('activity_log').doc(),
        {
          'type': 'expert_application',
          'userId': uid,
          'userName': widget.userData['name'] ?? '',
          'category': category,
          'priority': 'high',
          'timestamp': FieldValue.serverTimestamp(),
          'message': 'בקשה להצטרפות כמומחה: ${widget.userData['name'] ?? uid}',
        },
      );
      await batch.commit();
      if (mounted) {
        setState(() => _isPendingExpert = true);
        messenger.showSnackBar(const SnackBar(
          content: Text('✅ הבקשה שלך נשלחה! נחזור אליך בקרוב.'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('שגיאה: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).editProfileTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [IconButton(onPressed: _saveProfile, icon: const Icon(Icons.check, color: Colors.blue, size: 30))],
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Builder(builder: (context) {
            final l10n = AppLocalizations.of(context);
            return SingleChildScrollView(
            padding: const EdgeInsets.all(25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
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
                              backgroundImage: (_profileImageUrl != null && _profileImageUrl!.isNotEmpty)
                                  ? (_profileImageUrl!.startsWith('http')
                                      ? NetworkImage(_profileImageUrl!)
                                      : MemoryImage(base64Decode(_profileImageUrl!.split(',').last)) as ImageProvider)
                                  : null,
                              child: (_profileImageUrl == null || _profileImageUrl!.isEmpty)
                                  ? const Icon(Icons.person, size: 50, color: Colors.grey) : null,
                            ),
                            Positioned(
                              bottom: 0, right: 0,
                              child: CircleAvatar(
                                radius: 18,
                                backgroundColor: Colors.blue,
                                child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'העלה תמונת פנים ברורה',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'פרופילים עם תמונה ברורה נהנים מפי 3 יותר פניות',
                        style: TextStyle(fontSize: 11, color: Color(0xFF6366F1)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                Text(l10n.profileFieldName, style: const TextStyle(fontWeight: FontWeight.bold)),
                TextField(controller: _nameController, textAlign: TextAlign.start, decoration: InputDecoration(hintText: l10n.profileFieldNameHint)),

                const SizedBox(height: 20),

                // ── Phone — verified, read-only ──────────────────────────
                _buildLockedPhoneField(),

                const SizedBox(height: 25),

                Text(l10n.profileFieldRole, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                        style: TextStyle(fontSize: 11.5, color: Colors.grey),
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
                      color: _isVolunteer
                          ? const Color(0xFFECFDF5)
                          : Colors.grey[50],
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _isVolunteer
                            ? const Color(0xFF10B981)
                            : Colors.grey.shade200,
                        width: _isVolunteer ? 1.5 : 1,
                      ),
                    ),
                    child: SwitchListTile.adaptive(
                      value: _isVolunteer,
                      onChanged: (val) => setState(() => _isVolunteer = val),
                      activeColor: const Color(0xFF10B981),
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Text(
                            'אני מעוניין להתנדב',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(width: 6),
                          if (_isVolunteer)
                            const Icon(Icons.favorite,
                                color: Colors.red, size: 18),
                        ],
                      ),
                      subtitle: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(
                          'הצע את כישוריך ללא עלות לאנשים הזקוקים לעזרה',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                          textAlign: TextAlign.right,
                        ),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    ),
                  ),
                ],

                if (_isProvider) ...[
                  const SizedBox(height: 25),
                  // ── Main Category dropdown ──────────────────────────────
                  Text(l10n.profileFieldCategoryMain, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  // Show a spinner until the CategoryService stream delivers
                  // the first batch.  An empty-items DropdownButtonFormField is
                  // visually non-responsive on Flutter Web.
                  if (_mainCategories.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else
                    DropdownButtonFormField<String>(
                      isExpanded: true,   // ← required on Web; without it the tap
                                          //   target collapses to 0 in RTL columns
                      value: _mainCategories.any((c) => c['id'] == _selectedMainCatId)
                          ? _selectedMainCatId
                          : null,
                      hint: Text(l10n.profileFieldCategoryMainHint, textAlign: TextAlign.right),
                      items: _mainCategories.map((c) => DropdownMenuItem(
                        value: c['id'] as String,
                        child: Text(c['name'] as String? ?? '', textAlign: TextAlign.right),
                      )).toList(),
                      onChanged: (val) => setState(() {
                        _selectedMainCatId = val;
                        _selectedSubCatId  = null;
                        _subCategories = _categories.where((c) => c['parentId'] == val).toList();
                      }),
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                    ),
                  // ── Sub-Category dropdown (shown only when subs exist) ──
                  if (_subCategories.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(l10n.profileFieldCategorySub, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      isExpanded: true,   // ← same fix for sub-category
                      value: _subCategories.any((c) => c['id'] == _selectedSubCatId)
                          ? _selectedSubCatId
                          : null,
                      hint: Text(l10n.profileFieldCategorySubHint, textAlign: TextAlign.right),
                      items: _subCategories.map((c) => DropdownMenuItem(
                        value: c['id'] as String,
                        child: Text(c['name'] as String? ?? '', textAlign: TextAlign.right),
                      )).toList(),
                      onChanged: (val) => setState(() => _selectedSubCatId = val),
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // ── Tax ID ──────────────────────────────────────────────
                  Text(l10n.profileFieldTaxId, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(l10n.profileFieldTaxIdHelp,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _taxIdController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.start,
                    decoration: InputDecoration(
                      hintText: l10n.profileFieldTaxIdHint,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.receipt_long_outlined, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Price Settings shortcut ────────────────────────────
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PriceSettingsScreen(
                          userData: {
                            ...widget.userData,
                            // Pass the live price the user may have typed
                            'pricePerHour': double.tryParse(
                                    _priceController.text.trim()) ??
                                widget.userData['pricePerHour'] ??
                                100.0,
                          },
                        ),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6366F1)
                                .withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.arrow_back_ios_new_rounded,
                                  color: Colors.white70, size: 14),
                              SizedBox(width: 4),
                              Text('הגדרות מתקדמות',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                          Row(
                            children: [
                              Text('הגדרות תמחור',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                              SizedBox(width: 8),
                              Icon(Icons.price_change_outlined,
                                  color: Colors.white, size: 20),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(l10n.profileFieldPrice, style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextField(controller: _priceController, keyboardType: TextInputType.number, textAlign: TextAlign.start, decoration: InputDecoration(hintText: l10n.profileFieldPriceHint)),
                  const SizedBox(height: 20),
                  Text(l10n.profileFieldResponseTime, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(l10n.profileFieldResponseTimeHint, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final minutes in [5, 10, 15, 30, 60])
                          GestureDetector(
                            onTap: () => setState(() =>
                                _responseTimeMinutes = _responseTimeMinutes == minutes ? null : minutes),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: _responseTimeMinutes == minutes
                                    ? const Color(0xFF6366F1)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _responseTimeMinutes == minutes
                                      ? const Color(0xFF6366F1)
                                      : Colors.grey.shade300,
                                ),
                              ),
                              child: Text(
                                minutes == 60 ? l10n.timeOneHour : '~$minutesד\'',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _responseTimeMinutes == minutes
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
                        l10n.editProfileTagsSelected(_selectedQuickTags.length),
                        style: TextStyle(
                            fontSize: 12,
                            color: _selectedQuickTags.length >= 3
                                ? const Color(0xFF6366F1)
                                : Colors.grey),
                      ),
                      Text(l10n.editProfileQuickTags,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      l10n.editProfileTagsHint,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: kQuickTagCatalog.map((tag) {
                      final key      = tag['key']!;
                      final selected = _selectedQuickTags.contains(key);
                      final maxed    = _selectedQuickTags.length >= 3;
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
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF6366F1)
                                : (!selected && maxed)
                                    ? Colors.grey[100]
                                    : const Color(0xFFF0F0FF),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFF6366F1)
                                  : (!selected && maxed)
                                      ? Colors.grey.shade300
                                      : const Color(0xFF6366F1)
                                          .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            '${tag['emoji']} ${tag['label']}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected
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

                  const SizedBox(height: 25),

                  // ── Cancellation Policy picker ──────────────────────────
                  Text(l10n.editProfileCancellationPolicy,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      l10n.editProfileCancellationHint,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Column(
                    children: CancellationPolicyService.kPolicies.map((p) {
                      final selected = _cancellationPolicy == p;
                      return GestureDetector(
                        onTap: () => setState(() => _cancellationPolicy = p),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFFF0F0FF)
                                : Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
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
                                color: selected
                                    ? const Color(0xFF6366F1)
                                    : Colors.grey,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      CancellationPolicyService.label(p),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: selected
                                            ? const Color(0xFF6366F1)
                                            : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      CancellationPolicyService.description(p),
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.grey),
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

                  // ── Business Description / Bio ──────────────────────────
                  Text(l10n.editProfileAbout,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
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
                  Text(l10n.editProfileGallery,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10),
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
                                  style: BorderStyle.solid),
                            ),
                            child: const Icon(
                                Icons.add_photo_alternate_outlined,
                                color: Colors.blue,
                                size: 35),
                          ),
                        );
                      }
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(
                                base64Decode(_galleryImages[index]),
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () => setState(
                                  () => _galleryImages.removeAt(index)),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.cancel,
                                    color: Colors.red, size: 20),
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
                    child: Text('סרטון היכרות',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 4),
                  const Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      'הוסף סרטון קצר (עד 60 שניות) שמציג אותך ואת כישוריך. הסרטון יופיע בפרופיל שלך לאחר אישור מנהל.',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _videoUploadInProgress ? null : _pickAndUploadVerificationVideo,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                      decoration: BoxDecoration(
                        color: _verificationVideoUrl != null
                            ? const Color(0xFFECFDF5)
                            : const Color(0xFFF0F0FF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _verificationVideoUrl != null
                              ? const Color(0xFF10B981)
                              : const Color(0xFF6366F1),
                          width: 1.5,
                        ),
                      ),
                      child: _videoUploadInProgress
                          ? Column(
                              children: [
                                LinearProgressIndicator(
                                  value: _videoUploadProgress,
                                  backgroundColor: const Color(0xFFE0E0FF),
                                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'מעלה... ${(_videoUploadProgress * 100).toInt()}%',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF6366F1)),
                                ),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _verificationVideoUrl != null
                                      ? Icons.videocam_rounded
                                      : Icons.video_call_rounded,
                                  color: _verificationVideoUrl != null
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
                                    color: _verificationVideoUrl != null
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
                        style: TextStyle(fontSize: 11, color: Colors.grey),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                  ),
                  child: Text(l10n.saveChanges, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 50),
              ],
            ),
          );
        }), // Builder
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
  }) onSubmit;

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
  final _taxIdCtrl  = TextEditingController();
  final _aboutCtrl  = TextEditingController();
  bool _submitting  = false;

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
      builder: (_, scrollCtrl) => Container(
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
            const Text('הגש מועמדות כמומחה',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('מלא את הפרטים ואנחנו נבדוק את הבקשה שלך',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 24),

            // Category
            const Text('תחום עיסוק *',
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              hint: const Text('בחר תחום', textAlign: TextAlign.right),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
              items: widget.mainCategories.map((cat) {
                return DropdownMenuItem<String>(
                  value: cat['name'] as String,
                  child: Text(cat['name'] as String),
                );
              }).toList(),
              onChanged: (val) => setState(() => _selectedCategory = val),
            ),
            const SizedBox(height: 16),

            // Tax / ID
            const Text('מספר ת.ז. / ח.פ. *',
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _taxIdCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                hintText: 'הכנס מספר זהות',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),

            // About Me
            const Text('ספר על עצמך *',
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _aboutCtrl,
              maxLines: 4,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                hintText: 'תאר את הניסיון שלך, השירותים שאתה מציע...',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
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
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('שלח בקשה',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
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
              backgroundColor: Colors.orange));
      return;
    }
    if (_taxIdCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('הכנס מספר זהות'),
              backgroundColor: Colors.orange));
      return;
    }
    if (_aboutCtrl.text.trim().length < 20) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('כתוב לפחות 20 תווים על עצמך'),
              backgroundColor: Colors.orange));
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