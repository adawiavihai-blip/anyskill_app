// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import '../constants.dart';
import '../services/category_service.dart';
import '../services/provider_listing_service.dart';
import '../services/private_data_service.dart';
import '../utils/safe_image_provider.dart';
import 'home_screen.dart';
import 'pending_verification_screen.dart';
import 'terms_of_service_screen.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _kPurple      = Color(0xFF6366F1);
const _kPurpleDark  = Color(0xFF4F46E5);
const _kPurpleLight = Color(0xFF8B5CF6);
const _kGreen       = Color(0xFF10B981);
const _kRed         = Color(0xFFEF4444);
const _kAmber       = Color(0xFFF59E0B);
const _kScaffoldBg  = Color(0xFFF4F7F9);
const _kDarkText    = Color(0xFF1E1B4B);
const _kMuted       = Color(0xFF6B7280);

enum UserRole { customer, expert }

const _kBusinessTypes = [
  'עוסק פטור',
  'עוסק מורשה',
  'חברה בע"מ',
  'שכיר המוציא חשבונית דרך חברה חיצונית',
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  bool _isSaving = false;

  // ── Role ──────────────────────────────────────────────────────────────────
  UserRole _currentRole = UserRole.customer;
  bool get _isProvider => _currentRole == UserRole.expert;
  bool get _isCustomer => _currentRole == UserRole.customer;

  // ── Expert fields ─────────────────────────────────────────────────────────
  String? _businessType;
  final _idController = TextEditingController();
  final _nameController = TextEditingController();

  // Business document upload
  String? _businessDocUrl;
  String? _businessDocName;
  Uint8List? _businessDocThumb;
  bool _isUploadingBizDoc = false;

  // ID / Passport upload
  String? _idDocUrl;
  String? _idDocName;
  Uint8List? _idDocThumb;
  bool _isUploadingIdDoc = false;

  // Live selfie verification
  String? _selfieUrl;
  Uint8List? _selfieThumb;
  bool _isUploadingSelfie = false;

  // Category selection
  String? _selectedCategory;
  String? _selectedSubCategory;
  bool _isOtherCategory = false;
  bool _isOtherSubCategory = false;
  final _otherCategoryController = TextEditingController();

  // Price is set later from profile settings after approval

  // ── All users ─────────────────────────────────────────────────────────────
  String? _profileImageBase64;
  final _bioController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  // ── Terms ─────────────────────────────────────────────────────────────────
  bool _termsAccepted = false;
  bool _termsRead = false;

  // ── Live categories from Firestore ─────────────────────────────────────
  List<Map<String, dynamic>> _firestoreCategories = [];
  List<Map<String, dynamic>> _firestoreSubCategories = [];
  StreamSubscription<List<Map<String, dynamic>>>? _catSub;
  StreamSubscription<List<Map<String, dynamic>>>? _subCatSub;

  // ── Progress ──────────────────────────────────────────────────────────────
  late AnimationController _progressAnimCtrl;

  @override
  void initState() {
    super.initState();
    _progressAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    // Pre-fill from Firebase Auth
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _nameController.text = user.displayName ?? '';
      _emailController.text = user.email ?? '';
      _phoneController.text = user.phoneNumber ?? '';
    }
    // Stream live categories from Firestore
    _catSub = CategoryService.streamMainCategories().listen((cats) {
      if (mounted) setState(() => _firestoreCategories = cats);
    });
  }

  void _loadSubCategories(String parentId) {
    _subCatSub?.cancel();
    _subCatSub = CategoryService.streamSubCategories(parentId).listen((subs) {
      if (mounted) setState(() => _firestoreSubCategories = subs);
    });
  }

  @override
  void dispose() {
    _catSub?.cancel();
    _subCatSub?.cancel();
    _progressAnimCtrl.dispose();
    _idController.dispose();
    _nameController.dispose();
    _otherCategoryController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // ── Progress calculation ─────────────────────────────────────────────────
  double get _progress {
    if (_isCustomer) {
      int done = 1; // role selected = 1
      const total = 5;
      if (_nameController.text.trim().isNotEmpty) done++;
      if (_phoneController.text.trim().isNotEmpty) done++;
      if (_profileImageBase64 != null) done++;
      if (_termsAccepted) done++;
      return done / total;
    }
    int done = 1; // role selected
    const total = 11;
    if (_nameController.text.trim().isNotEmpty) done++;
    if (_phoneController.text.trim().isNotEmpty) done++;
    if (_emailController.text.trim().isNotEmpty) done++;
    if (_businessType != null) done++;
    if (_idController.text.trim().isNotEmpty) done++;
    if (_idDocUrl != null) done++;
    if (_selectedCategory != null || _isOtherCategory) done++;
    if (_profileImageBase64 != null) done++;
    if (_bioController.text.trim().isNotEmpty) done++;
    if (_termsAccepted) done++;
    return done / total;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ══════════════════════════════════════════════════════════════════════════

  void _submit() {
    // ── Mandatory for ALL roles ────────────────────────────────────────
    if (_nameController.text.trim().isEmpty) {
      _snack('נא להזין שם מלא', _kRed);
      return;
    }
    if (_phoneController.text.trim().isEmpty) {
      _snack('נא להזין מספר טלפון', _kRed);
      return;
    }

    // ── Provider-only mandatory fields ─────────────────────────────────
    if (_isProvider) {
      if (_emailController.text.trim().isEmpty) {
        _snack('נא להזין כתובת אימייל', _kRed);
        return;
      }
      if (_profileImageBase64 == null) {
        _snack('נא להעלות תמונת פרופיל', _kRed);
        return;
      }
      if (_businessType == null) {
        _snack('נא לבחור סוג עסק', _kRed);
        return;
      }
      if (_idController.text.trim().isEmpty) {
        _snack('נא להזין מספר ת.ז. / ח.פ.', _kRed);
        return;
      }
      if (_idDocUrl == null) {
        _snack('נא להעלות צילום תעודת זהות או דרכון', _kRed);
        return;
      }
      if (_selectedCategory == null && !_isOtherCategory) {
        _snack('נא לבחור קטגוריה מקצועית', _kRed);
        return;
      }
      if (_isOtherCategory && _otherCategoryController.text.trim().length < 3) {
        _snack('נא לפרט את תחום המומחיות שלך', _kRed);
        return;
      }
    }
    if (!_termsAccepted) {
      _snack('יש לקרוא ולאשר את תנאי השימוש', _kRed);
      return;
    }
    _finish();
  }

  Future<void> _finish() async {
    setState(() => _isSaving = true);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    try {
      // ── Check if user doc already exists (legacy provider re-onboarding) ──
      // Existing verified providers who are only here because of a missing
      // phone field must NOT have their verification status overwritten.
      // Server-only fields (isVerified, isAdmin, balance, xp) are blocked
      // by Firestore rules on update — writing them would cause permission-denied.
      final existingSnap = await FirebaseFirestore.instance
          .collection('users').doc(uid).get();
      final existingData = existingSnap.data() ?? {};
      final isExistingUser = existingSnap.exists && existingData.isNotEmpty;
      final isAlreadyVerified = existingData['isVerified'] == true;
      final isAlreadyProvider = existingData['isProvider'] == true;

      if (isExistingUser) {
        debugPrint('[Onboarding] Existing user detected: uid=$uid, '
            'isProvider=$isAlreadyProvider, isVerified=$isAlreadyVerified, '
            'isPendingExpert=${existingData['isPendingExpert']}');
      }

      final updates = <String, dynamic>{
        'isCustomer':         _isCustomer,
        'onboardingComplete': true,
        'termsAccepted':      true,
        'name':               _nameController.text.trim(),
        'phone':              _phoneController.text.trim(),
      };

      // Only set isProvider for truly new users. For existing providers
      // returning through re-onboarding (e.g., missing phone), don't
      // downgrade their provider status.
      if (!isAlreadyProvider) {
        updates['isProvider'] = _isProvider;
      }

      if (_emailController.text.trim().isNotEmpty) {
        updates['email'] = _emailController.text.trim();
      }

      if (_isProvider) {
        final effectiveCategory = _isOtherCategory
            ? _otherCategoryController.text.trim()
            : _selectedCategory;
        final effectiveSubCategory = _isOtherSubCategory
            ? ''
            : (_selectedSubCategory ?? '');

        // serviceType = most-specific name (sub-category if selected, else main)
        // parentCategory = main category (only when sub-category is used)
        // This ensures CategoryResultsScreen finds the provider when:
        //   a) User taps the exact sub-category → serviceType match
        //   b) User taps "Show All" on parent → parentCategory fallback match
        final hasSubCat = effectiveSubCategory.isNotEmpty;
        updates['serviceType'] = hasSubCat ? effectiveSubCategory : effectiveCategory;
        if (hasSubCat) {
          updates['parentCategory'] = effectiveCategory;
        }
        updates['subCategory']    = effectiveSubCategory;
        updates['businessType']   = _businessType;
        updates['idNumber']       = _idController.text.trim();
        updates['categoryReviewedByAdmin'] = false;
        if (_businessDocUrl != null) updates['businessDocUrl'] = _businessDocUrl;
        if (_idDocUrl != null) updates['idDocUrl'] = _idDocUrl;
        if (_selfieUrl != null) updates['selfieVerificationUrl'] = _selfieUrl;
        if (_isOtherCategory) updates['pendingCategoryApproval'] = true;

        // ── CRITICAL: Never write server-only fields on existing users ────
        // isVerified, isApprovedProvider are managed by admin. Writing them
        // on an update() call triggers Firestore permission-denied.
        // Only set pending status for genuinely NEW provider applications.
        if (!isAlreadyVerified && !isAlreadyProvider) {
          updates['isPendingExpert']    = true;
          updates['isProvider']         = false;
          updates['isApprovedProvider'] = false;
          // isVerified is ONLY safe on create, never on update
        }

        updates['expertApplicationData'] = {
          'submittedAt':      FieldValue.serverTimestamp(),
          'category':         effectiveCategory,
          'subCategory':      effectiveSubCategory,
          'businessType':     _businessType,
          'idNumber':         _idController.text.trim(),
          'isCustomCategory': _isOtherCategory,
          if (_businessDocUrl != null) 'businessDocUrl': _businessDocUrl,
          if (_idDocUrl != null) 'idDocUrl': _idDocUrl,
        };
      }

      if (_bioController.text.trim().isNotEmpty) {
        updates['aboutMe'] = _bioController.text.trim();
      }
      if (_profileImageBase64 != null) {
        updates['profileImage'] = 'data:image/png;base64,$_profileImageBase64';
      }

      debugPrint('[Onboarding] Writing fields: ${updates.keys.toList()}');
      await FirebaseFirestore.instance.collection('users').doc(uid).update(updates);

      // PR 1 (v11.9.x): Also mirror KYC fields into private/kyc subcollection.
      // This is a dual-write during migration — legacy readers still hit the
      // main doc, new readers (admin_id_verification_tab) pull from private.
      if (_isProvider) {
        await PrivateDataService.writeKycData(
          uid,
          idNumber:              _idController.text.trim(),
          idDocUrl:              _idDocUrl,
          selfieVerificationUrl: _selfieUrl,
          businessDocUrl:        _businessDocUrl,
        );
      }

      // PR 2a: Mirror contact fields into private/identity. All users.
      // Main-doc `phone`/`email` writes above stay in place until every
      // reader migrates to PrivateDataService.getContactData.
      await PrivateDataService.writeContactData(
        uid,
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
      );

      // v10.1.0: Create primary provider_listing doc for dual-identity system
      if (_isProvider && !_isOtherCategory) {
        try {
          await ProviderListingService.migrateIfNeeded(uid);
          debugPrint('[Onboarding] Provider listing created for uid=$uid');
        } catch (e) {
          debugPrint('[Onboarding] Listing creation error (non-fatal): $e');
        }
      }

      // "Other" category request
      if (_isProvider && _isOtherCategory) {
        await FirebaseFirestore.instance.collection('category_requests').add({
          'userId':           uid,
          'userName':         _nameController.text.trim(),
          'description':      _otherCategoryController.text.trim(),
          'originalCategory': null,
          'status':           'pending',
          'createdAt':        FieldValue.serverTimestamp(),
        });
      }

      // Admin email
      try {
        final authUser  = FirebaseAuth.instance.currentUser;
        final userName  = _nameController.text.trim().isNotEmpty
            ? _nameController.text.trim()
            : (authUser?.displayName ?? 'לא צוין');
        final userEmail = authUser?.email ?? 'לא צוין';
        final userType  = _isProvider ? 'נותן שירות (ספק)' : 'לקוח';
        final serviceStr = _isProvider
            ? (_selectedCategory ?? _otherCategoryController.text.trim())
            : '—';
        await FirebaseFirestore.instance.collection('mail').add({
          'to': 'adawiavihai@gmail.com',
          'message': {
            'subject': '🆕 [AnySkill] נרשם $userType: $userName',
            'html': '<div dir="rtl" style="font-family:Arial;padding:16px">'
              '<h2>משתמש חדש נרשם ל-AnySkill</h2>'
              '<p><b>שם:</b> $userName</p>'
              '<p><b>אימייל:</b> $userEmail</p>'
              '<p><b>סוג:</b> $userType</p>'
              '<p><b>תחום:</b> $serviceStr</p>'
              '<p><b>UID:</b> $uid</p></div>',
          },
        });
      } catch (_) {}

      try { await _sendWelcomeMessage(uid, _isProvider); } catch (_) {}

      if (mounted) {
        if (_isProvider) {
          // Provider: show pending approval screen (real-time listener
          // auto-redirects to HomeScreen when admin approves)
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const PendingVerificationScreen()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      }
    } catch (e) {
      if (mounted) _snack('שגיאה בשמירה: $e', _kRed);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _sendWelcomeMessage(String uid, bool isProvider) async {
    const systemUid = 'anyskill_system';
    final db = FirebaseFirestore.instance;
    final text = isProvider
        ? 'איזה כיף שהצטרפת לנבחרת אנשי המקצוע של AnySkill! 🚀 '
          'המסמכים שלך התקבלו ובביקורת. תקבל עדכון ברגע שהחשבון יאושר.'
        : 'ברוכים הבאים ל-AnySkill! 🌟 צריכים עזרה במשהו? הגעתם למקום הנכון. '
          'אלפי אנשי מקצוע זמינים עבורכם עכשיו.';

    try {
      await db.collection('users').doc(systemUid).set({
        'uid': systemUid, 'name': 'AnySkill', 'profileImage': '',
        'isProvider': false, 'isCustomer': false, 'isOnline': true, 'balance': 0,
      }, SetOptions(merge: true));
    } catch (_) {}

    final ids = [uid, systemUid]..sort();
    final chatRoomId = ids.join('_');

    await db.collection('chats').doc(chatRoomId).set({
      'users': [uid, systemUid],
      'lastMessage': text.length > 50 ? '${text.substring(0, 50)}...' : text,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': systemUid,
      'unreadCount_$uid': 1,
      'unreadCount_$systemUid': 0,
    }, SetOptions(merge: true));

    await db.collection('chats').doc(chatRoomId).collection('messages').add({
      'senderId': systemUid, 'receiverId': uid,
      'message': text, 'type': 'text',
      'timestamp': FieldValue.serverTimestamp(), 'isRead': false,
    });
  }

  // ── File uploads ────────────────────────────────────────────────────────

  Future<void> _pickProfileImage() async {
    final XFile? image = await ImagePicker().pickImage(
      source: ImageSource.gallery, maxWidth: 300, maxHeight: 300, imageQuality: 50,
    );
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() => _profileImageBase64 = base64Encode(bytes));
    }
  }

  Future<void> _uploadDocument({
    required String storagePath,
    required void Function(String url, String name, Uint8List thumb) onSuccess,
    required void Function(bool val) setUploading,
  }) async {
    final XFile? image = await ImagePicker().pickImage(
      source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85,
    );
    if (image == null) return;
    setUploading(true);

    try {
      final uid   = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      final ext   = image.name.split('.').last;
      final bytes = await image.readAsBytes();
      final ref   = FirebaseStorage.instance
          .ref()
          .child('$storagePath/$uid/${DateTime.now().millisecondsSinceEpoch}.$ext');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/$ext'));
      final url = await ref.getDownloadURL();

      // Use the uploaded bytes as thumbnail preview
      if (mounted) onSuccess(url, image.name, bytes);
    } catch (e) {
      if (mounted) _snack('שגיאה בהעלאה: $e', _kRed);
    } finally {
      if (mounted) setUploading(false);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kScaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Sticky progress bar ─────────────────────────────────────
            _buildProgressBar(),
            // ── Scrollable content ──────────────────────────────────────
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader()),
                  // Social proof
                  SliverToBoxAdapter(child: _buildSocialProof()),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // 1. Role
                        _sectionCard(
                          icon: Icons.person_outline_rounded,
                          title: 'בחר תפקיד',
                          check: true,
                          child: _buildRoleCards(),
                        ),
                        const SizedBox(height: 16),

                        // 2. Provider fields
                        if (_isProvider) ...[
                          _sectionCard(
                            icon: Icons.business_center_outlined,
                            title: 'פרטים עסקיים',
                            check: _businessType != null && _idController.text.trim().isNotEmpty,
                            child: _buildBusinessFields(),
                          ),
                          const SizedBox(height: 16),
                          _sectionCard(
                            icon: Icons.category_outlined,
                            title: 'תחום שירות',
                            check: _selectedCategory != null || _isOtherCategory,
                            child: _buildCategoryFields(),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // 3. Contact info (mandatory for all)
                        _sectionCard(
                          icon: Icons.contact_phone_outlined,
                          title: 'פרטי קשר',
                          check: _phoneController.text.trim().isNotEmpty &&
                              _nameController.text.trim().isNotEmpty,
                          child: _buildContactFields(),
                        ),
                        const SizedBox(height: 16),

                        // 4. Profile
                        _sectionCard(
                          icon: Icons.badge_outlined,
                          title: 'הפרופיל שלך',
                          check: _profileImageBase64 != null || _bioController.text.trim().isNotEmpty,
                          child: _buildProfileSection(),
                        ),
                        const SizedBox(height: 16),

                        // 4. Terms
                        _buildTermsSection(),
                        const SizedBox(height: 20),

                        // 5. Submit
                        _buildSubmitButton(),
                        const SizedBox(height: 24),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Progress bar (sticky at top) ───────────────────────────────────────

  Widget _buildProgressBar() {
    final pct = _progress;
    final label = (pct * 100).toInt();
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      color: Colors.white,
      child: Column(
        children: [
          Row(
            children: [
              Text('$label%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: pct >= 1.0 ? _kGreen : _kPurple,
                )),
              const SizedBox(width: 8),
              Expanded(child: Text(
                pct >= 1.0 ? 'הכל מוכן!' : 'השלם את הפרטים',
                style: const TextStyle(fontSize: 12, color: _kMuted),
              )),
              if (pct >= 1.0)
                const Icon(Icons.check_circle_rounded, size: 18, color: _kGreen),
            ],
          ),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (_, val, __) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: val,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(
                  pct >= 1.0 ? _kGreen : _kPurple,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final user = FirebaseAuth.instance.currentUser;
    final greeting = user?.displayName?.isNotEmpty == true
        ? 'היי ${user!.displayName!.split(' ').first},'
        : 'היי,';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_kPurpleDark, _kPurple, _kPurpleLight],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.rocket_launch_rounded, size: 32, color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            '$greeting ברוכים הבאים!',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            'עוד רגע מתחילים. ספר לנו קצת על עצמך.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.85)),
          ),
        ],
      ),
    );
  }

  // ── Social proof banner ────────────────────────────────────────────────

  Widget _buildSocialProof() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _kGreen.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kGreen.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.trending_up_rounded, size: 16, color: _kGreen),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'מעל 250 אנשי מקצוע הצטרפו החודש',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kGreen),
              ),
            ),
            const Text('🔥', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }

  // ── Section card wrapper ───────────────────────────────────────────────

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required bool check,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: (check ? _kGreen : _kPurple).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: check ? _kGreen : _kPurple),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _kDarkText))),
                if (check)
                  const Icon(Icons.check_circle_rounded, size: 20, color: _kGreen),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: child,
          ),
        ],
      ),
    );
  }

  // ── Role cards ──────────────────────────────────────────────────────────

  Widget _buildRoleCards() {
    return Row(
      children: [
        Expanded(child: _roleCard(
          role: UserRole.customer,
          icon: Icons.search_rounded,
          title: 'אני מחפש שירות',
          subtitle: 'אני רוצה למצוא איש מקצוע',
        )),
        const SizedBox(width: 12),
        Expanded(child: _roleCard(
          role: UserRole.expert,
          icon: Icons.star_rounded,
          title: 'אני רוצה לתת שירות',
          subtitle: 'ברצוני לעבוד דרך AnySkill',
        )),
      ],
    );
  }

  Widget _roleCard({
    required UserRole role,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _currentRole == role;
    return GestureDetector(
      onTap: () => setState(() => _currentRole = role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? _kPurple.withValues(alpha: 0.08) : _kScaffoldBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _kPurple : Colors.grey.shade200,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (selected ? _kPurple : _kMuted).withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 26, color: selected ? _kPurple : _kMuted),
            ),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                color: selected ? _kPurple : _kDarkText)),
            const SizedBox(height: 3),
            Text(subtitle, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10.5, color: _kMuted)),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PROVIDER: BUSINESS FIELDS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildBusinessFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Business type
        _buildDropdown(
          value: _businessType,
          hint: 'סוג עסק',
          items: _kBusinessTypes,
          onChanged: (v) => setState(() => _businessType = v),
        ),
        const SizedBox(height: 12),

        // Business doc upload (conditional)
        if (_businessType != null) ...[
          _buildUploadCard(
            label: 'העלה צילום תעודת עוסק (פטור/מורשה/חברה)',
            fileName: _businessDocName,
            thumb: _businessDocThumb,
            isUploading: _isUploadingBizDoc,
            onTap: () => _uploadDocument(
              storagePath: 'business_docs',
              onSuccess: (url, name, thumb) => setState(() {
                _businessDocUrl = url; _businessDocName = name; _businessDocThumb = thumb;
              }),
              setUploading: (v) => setState(() => _isUploadingBizDoc = v),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ID Number
        _buildTextField(
          controller: _idController,
          label: 'מספר תעודת זהות / ח.פ.',
          hint: 'הזן מספר ת.ז. או ח.פ.',
          keyboardType: TextInputType.number,
          prefixIcon: const Icon(Icons.badge_outlined, size: 20, color: _kMuted),
        ),
        const SizedBox(height: 12),

        // ID doc upload
        _buildUploadCard(
          label: 'העלה צילום תעודת זהות או דרכון',
          fileName: _idDocName,
          thumb: _idDocThumb,
          isUploading: _isUploadingIdDoc,
          required_: true,
          onTap: () => _uploadDocument(
            storagePath: 'id_docs',
            onSuccess: (url, name, thumb) => setState(() {
              _idDocUrl = url; _idDocName = name; _idDocThumb = thumb;
            }),
            setUploading: (v) => setState(() => _isUploadingIdDoc = v),
          ),
        ),
        const SizedBox(height: 16),

        // ── Live Selfie Verification ──────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _selfieUrl != null ? const Color(0xFFF0FDF4) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _selfieUrl != null
                  ? const Color(0xFF22C55E)
                  : Colors.grey.shade300,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  if (_selfieThumb != null)
                    ClipOval(
                      child: Image.memory(_selfieThumb!,
                          width: 48, height: 48, fit: BoxFit.cover),
                    )
                  else
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F0FF),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.face_rounded,
                          color: Color(0xFF6366F1), size: 24),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (_selfieUrl != null)
                              const Icon(Icons.check_circle_rounded,
                                  size: 16, color: Color(0xFF22C55E)),
                            if (_selfieUrl != null) const SizedBox(width: 4),
                            const Text('סלפי לאימות זהות',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _selfieUrl != null
                              ? 'תמונה צולמה בהצלחה ✓'
                              : 'צלם תמונה חיה של הפנים שלך',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontSize: 12,
                            color: _selfieUrl != null
                                ? const Color(0xFF22C55E)
                                : Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isUploadingSelfie ? null : _takeLiveSelfie,
                  icon: _isUploadingSelfie
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Icon(
                          _selfieUrl != null
                              ? Icons.refresh_rounded
                              : Icons.camera_alt_rounded,
                          size: 18),
                  label: Text(
                    _selfieUrl != null ? 'צלם שוב' : 'צלם סלפי',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Opens the camera for a live selfie, compresses, uploads to Storage.
  Future<void> _takeLiveSelfie() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 70,
    );
    if (photo == null) return;

    setState(() => _isUploadingSelfie = true);
    try {
      final bytes = await photo.readAsBytes();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final ref = FirebaseStorage.instance
          .ref('verification_selfies/$uid.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();

      if (mounted) {
        setState(() {
          _selfieUrl = url;
          _selfieThumb = bytes;
          _isUploadingSelfie = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingSelfie = false);
        _snack('שגיאה בצילום: $e', _kRed);
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PROVIDER: CATEGORY FIELDS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildCategoryFields() {
    // Use live Firestore categories if available, fallback to hardcoded
    final mainCatNames = _firestoreCategories.isNotEmpty
        ? _firestoreCategories.map((c) => c['name'] as String).toList()
        : APP_CATEGORIES.map((c) => c['name'] as String).toList();

    // Sub-categories: use Firestore stream if loaded, else hardcoded fallback
    final subCatNames = _firestoreSubCategories.isNotEmpty
        ? _firestoreSubCategories.map((c) => c['name'] as String).toList()
        : (_selectedCategory != null && !_isOtherCategory
            ? (APP_SUB_CATEGORIES[_selectedCategory] ?? <String>[])
            : <String>[]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDropdown(
          value: _isOtherCategory ? 'אחר / לא מצאתי' : _selectedCategory,
          hint: 'בחר קטגוריה ראשית',
          items: [...mainCatNames, 'אחר / לא מצאתי'],
          onChanged: (v) {
            setState(() {
              if (v == 'אחר / לא מצאתי') {
                _isOtherCategory = true;
                _selectedCategory = null;
                _selectedSubCategory = null;
                _isOtherSubCategory = false;
                _firestoreSubCategories = [];
              } else {
                _isOtherCategory = false;
                _selectedCategory = v;
                _selectedSubCategory = null;
                _isOtherSubCategory = false;
                // Load sub-categories from Firestore for selected parent
                final parentDoc = _firestoreCategories
                    .where((c) => c['name'] == v)
                    .toList();
                if (parentDoc.isNotEmpty) {
                  _loadSubCategories(parentDoc.first['id'] as String);
                } else {
                  _firestoreSubCategories = [];
                }
              }
            });
          },
        ),
        const SizedBox(height: 12),

        if (!_isOtherCategory && _selectedCategory != null && subCatNames.isNotEmpty) ...[
          _buildDropdown(
            value: _isOtherSubCategory ? 'אחר / לא מצאתי' : _selectedSubCategory,
            hint: 'בחר תת-קטגוריה',
            items: [...subCatNames, 'אחר / לא מצאתי'],
            onChanged: (v) => setState(() {
              if (v == 'אחר / לא מצאתי') {
                _isOtherSubCategory = true; _selectedSubCategory = null;
              } else {
                _isOtherSubCategory = false; _selectedSubCategory = v;
              }
            }),
          ),
          const SizedBox(height: 12),
        ],

        if (_isOtherCategory) ...[
          _buildTextField(
            controller: _otherCategoryController,
            label: 'פרט את תחום המומחיות שלך',
            hint: 'עד 30 תווים',
            maxLength: 30,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kAmber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kAmber.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: _kAmber),
                SizedBox(width: 8),
                Expanded(child: Text(
                  'צוות AnySkill יבחן את הפרטים וישייך אותך לקטגוריה המתאימה',
                  style: TextStyle(fontSize: 12, color: _kDarkText),
                )),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CONTACT INFO SECTION (mandatory for all roles)
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildContactFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTextField(
          controller: _nameController,
          label: 'שם מלא *',
          hint: 'השם שיוצג בפרופיל',
          prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
        ),
        const SizedBox(height: 12),
        _buildTextField(
          controller: _phoneController,
          label: 'מספר טלפון *',
          hint: '050-1234567',
          keyboardType: TextInputType.phone,
          prefixIcon: const Icon(Icons.phone_outlined, size: 20),
        ),
        if (_isProvider) ...[
          const SizedBox(height: 12),
          _buildTextField(
            controller: _emailController,
            label: 'אימייל *',
            hint: 'example@mail.com',
            keyboardType: TextInputType.emailAddress,
            prefixIcon: const Icon(Icons.email_outlined, size: 20),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          _isProvider
              ? '* כל השדות חובה לנותני שירות'
              : '* שם וטלפון הם שדות חובה',
          style: const TextStyle(fontSize: 11, color: _kMuted),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PROFILE SECTION
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildProfileSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: GestureDetector(
            onTap: _pickProfileImage,
            child: Stack(
              children: [
                Builder(
                  builder: (_) {
                    // safeImageProvider swallows FormatException so a
                    // malformed cached string (e.g. from a previous crash)
                    // never propagates into the widget tree.
                    final provider = safeImageProvider(_profileImageBase64);
                    return CircleAvatar(
                      radius: 44,
                      backgroundColor: _kPurple.withValues(alpha: 0.10),
                      backgroundImage: provider,
                      child: provider == null
                          ? const Icon(Icons.camera_alt_rounded,
                              size: 28, color: _kPurple)
                          : null,
                    );
                  },
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: _kPurple,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit, size: 14, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(child: Text(
          _profileImageBase64 != null ? 'לחץ להחלפה' : 'הוסף תמונת פרופיל',
          style: const TextStyle(fontSize: 12, color: _kPurple),
        )),
        const SizedBox(height: 14),
        _buildTextField(
          controller: _bioController,
          label: 'ספר על עצמך',
          hint: _isProvider
              ? 'ניסיון, כישורים, התמחויות...'
              : 'מה תרצה שנדע עליך?',
          maxLines: 3,
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TERMS SECTION
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildTermsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _termsAccepted ? _kGreen : Colors.grey.shade200,
          width: _termsAccepted ? 1.5 : 1,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () async {
              // Open the SAME full TermsOfServiceScreen used in Email sign-up.
              // It returns true when user taps "קראתי והבנתי".
              final accepted = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => const TermsOfServiceScreen(showAcceptButton: true),
                ),
              );
              if (accepted == true && mounted) {
                setState(() => _termsRead = true);
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined, size: 18, color: _kPurple),
                  const SizedBox(width: 8),
                  const Expanded(child: Text(
                    'קרא את תנאי השימוש ומדיניות הפרטיות',
                    style: TextStyle(fontSize: 13, color: _kPurple, decoration: TextDecoration.underline),
                  )),
                  if (_termsRead)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _kGreen.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('נקרא', style: TextStyle(fontSize: 10, color: _kGreen, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22, height: 22,
                child: Checkbox(
                  value: _termsAccepted,
                  activeColor: _kGreen,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  onChanged: _termsRead
                      ? (v) => setState(() => _termsAccepted = v ?? false)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'אני מאשר/ת שקראתי והסכמתי לתנאי השימוש ולמדיניות הפרטיות של AnySkill',
                style: TextStyle(fontSize: 12, color: _termsRead ? _kDarkText : _kMuted),
              )),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SUBMIT BUTTON
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildSubmitButton() {
    final canSubmit = _termsAccepted &&
        !_isSaving &&
        _nameController.text.trim().isNotEmpty &&
        _phoneController.text.trim().isNotEmpty;
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: canSubmit ? _submit : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kPurple,
          disabledBackgroundColor: Colors.grey.shade300,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: canSubmit ? 6 : 0,
          shadowColor: _kPurple.withValues(alpha: 0.4),
        ),
        child: _isSaving
            ? const SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('סיום הרשמה',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                ],
              ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // REUSABLE WIDGETS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildDropdown({
    required String? value,
    required String hint,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _kScaffoldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonFormField<String>(
        value: items.contains(value) ? value : null,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: InputBorder.none,
          hintText: hint,
          hintStyle: const TextStyle(color: _kMuted, fontSize: 14),
        ),
        isExpanded: true,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _kMuted),
        items: items.map((item) => DropdownMenuItem(
          value: item,
          child: Text(item, style: const TextStyle(fontSize: 14)),
        )).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? helperText,
    TextInputType? keyboardType,
    int maxLines = 1,
    int? maxLength,
    Widget? prefixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _kScaffoldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        maxLength: maxLength,
        onChanged: (_) => setState(() {}), // refresh progress bar
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helperText,
          helperMaxLines: 2,
          prefixIcon: prefixIcon,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: InputBorder.none,
          labelStyle: const TextStyle(fontSize: 14, color: _kMuted),
          hintStyle: TextStyle(fontSize: 13, color: _kMuted.withValues(alpha: 0.6)),
          helperStyle: const TextStyle(fontSize: 11, color: _kMuted),
          counterStyle: const TextStyle(fontSize: 10, color: _kMuted),
        ),
      ),
    );
  }

  Widget _buildUploadCard({
    required String label,
    required String? fileName,
    required bool isUploading,
    required VoidCallback onTap,
    Uint8List? thumb,
    bool required_ = false,
  }) {
    final hasFile = fileName != null;
    return GestureDetector(
      onTap: isUploading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: hasFile ? _kGreen.withValues(alpha: 0.05) : _kScaffoldBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasFile ? _kGreen : (required_ ? _kAmber.withValues(alpha: 0.5) : Colors.grey.shade200),
            width: hasFile ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Thumbnail or icon
            if (hasFile && thumb != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(thumb, width: 44, height: 44, fit: BoxFit.cover),
              )
            else
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: (hasFile ? _kGreen : _kPurple).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: isUploading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(
                        hasFile ? Icons.check_circle_rounded : Icons.cloud_upload_outlined,
                        size: 22,
                        color: hasFile ? _kGreen : _kPurple,
                      ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                    style: TextStyle(
                      fontSize: 12,
                      color: hasFile ? _kGreen : _kDarkText,
                      fontWeight: FontWeight.w500,
                    )),
                  if (hasFile) ...[
                    const SizedBox(height: 2),
                    Text(fileName, style: const TextStyle(fontSize: 10, color: _kMuted),
                      overflow: TextOverflow.ellipsis),
                  ],
                  if (required_ && !hasFile) ...[
                    const SizedBox(height: 2),
                    const Text('שדה חובה *', style: TextStyle(fontSize: 10, color: _kRed)),
                  ],
                ],
              ),
            ),
            Icon(
              hasFile ? Icons.swap_horiz_rounded : Icons.arrow_forward_ios_rounded,
              size: 16, color: _kMuted,
            ),
          ],
        ),
      ),
    );
  }
}
