import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../constants.dart';
import '../services/service_architect.dart';
import '../services/private_data_service.dart';
import '../utils/safe_image_provider.dart';
import 'pending_verification_screen.dart';

// ── Brand tokens ──────────────────────────────────────────────────────────────
const _kPurple      = Color(0xFF6366F1);
const _kPurpleDark  = Color(0xFF4F46E5);
const _kPurpleLight = Color(0xFF8B5CF6);
const _kGreen       = Color(0xFF059669);
const _kRed         = Color(0xFFEF4444);

// ─────────────────────────────────────────────────────────────────────────────
/// Handles both registration paths:
///
/// • [isExistingUser] = false — new user (no Firestore doc yet).
///   Creates the full user document on submit.
///
/// • [isExistingUser] = true — existing client upgrading to provider.
///   Updates the existing document on submit.
///
/// [prefillData] keys used:
///   uid, phone, name, email, photoURL / profileImage
// ─────────────────────────────────────────────────────────────────────────────
class ProviderRegistrationScreen extends StatefulWidget {
  const ProviderRegistrationScreen({
    super.key,
    required this.isExistingUser,
    required this.prefillData,
  });

  final bool                 isExistingUser;
  final Map<String, dynamic> prefillData;

  @override
  State<ProviderRegistrationScreen> createState() =>
      _ProviderRegistrationScreenState();
}

class _ProviderRegistrationScreenState
    extends State<ProviderRegistrationScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _nameCtrl     = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _idCtrl       = TextEditingController();
  final _countryCtrl  = TextEditingController(text: 'ישראל');
  final _cityCtrl     = TextEditingController();
  final _aboutCtrl    = TextEditingController();
  final _priceCtrl    = TextEditingController();
  final _taxCtrl      = TextEditingController();
  final _otherDescCtrl = TextEditingController();

  static const String _kOther = 'אחר...';

  // Business type options (exact strings stored in Firestore).
  static const List<String> _kBusinessTypes = [
    'עוסק פטור',
    'עוסק מורשה',
    'חשבונית למשכיר',
  ];

  String  _category    = APP_CATEGORIES.first['name'] as String;
  String  _subCategory = '';
  bool    _isOtherCategory = false;
  bool    _isOtherSubCategory = false;
  bool    _isLoading   = false;

  // ── Business document upload ───────────────────────────────────────────
  String? _businessDocUrl;
  bool    _isUploading = false;

  // ── Profile image (base64 data URI) ───────────────────────────────────
  String? _profileImageBase64;
  bool    _isUploadingProfile = false;

  // ── Gallery (Firebase Storage URLs, up to 6) ──────────────────────────
  final List<String> _galleryUrls = [];
  bool    _isUploadingGallery = false;

  // ── Intro video (Firebase Storage URL) ─────────────────────────────────
  String? _introVideoUrl;
  bool    _isUploadingVideo = false;

  // ── Business type (עוסק פטור / עוסק מורשה / חשבונית למשכיר) ────────────
  String? _businessType;

  @override
  void initState() {
    super.initState();
    final d = widget.prefillData;
    _nameCtrl.text  = (d['name']  as String? ?? '').trim();
    _phoneCtrl.text = (d['phone'] as String? ?? '').trim();
    _emailCtrl.text = (d['email'] as String? ?? '').trim();
    _idCtrl.text    = (d['idNumber'] as String? ?? '').trim();
    final prefCountry = (d['country'] as String? ?? '').trim();
    if (prefCountry.isNotEmpty) _countryCtrl.text = prefCountry;
    _cityCtrl.text  = (d['city'] as String? ?? '').trim();
    final prefBusinessType = d['businessType'] as String?;
    if (prefBusinessType != null && _kBusinessTypes.contains(prefBusinessType)) {
      _businessType = prefBusinessType;
    }
    final prefImage = d['profileImage'] as String?;
    if (prefImage != null && prefImage.startsWith('data:image')) {
      // Strip the data URI prefix — we re-add it on save.
      _profileImageBase64 = prefImage.split(',').last;
    }
    final prefGallery = d['gallery'];
    if (prefGallery is List) {
      _galleryUrls.addAll(prefGallery.whereType<String>().where((s) => s.startsWith('http')));
    }
    final prefVideo = d['introVideoUrl'] as String?;
    if (prefVideo != null && prefVideo.isNotEmpty) _introVideoUrl = prefVideo;
    // Pre-fill aboutMe if upgrading existing client
    _aboutCtrl.text = (d['aboutMe'] as String? ?? '').trim();
    // Pre-select category if already set
    final existingCat = d['serviceType'] as String? ?? '';
    if (APP_CATEGORIES.any((c) => c['name'] == existingCat)) {
      _category = existingCat;
    }
    final existingSub = d['subCategory'] as String? ?? '';
    final validSubs = APP_SUB_CATEGORIES[_category] ?? [];
    if (existingSub.isNotEmpty && validSubs.contains(existingSub)) {
      _subCategory = existingSub;
    } else {
      _subCategory = validSubs.isNotEmpty ? validSubs.first : '';
    }
    if (d['pricePerHour'] != null && d['pricePerHour'] != 0) {
      _priceCtrl.text = d['pricePerHour'].toString();
    }
    // Rebuild suggestion panel whenever price changes
    _priceCtrl.addListener(() => setState(() {}));
    // Rebuild suggestion panel whenever about-me is edited (hides the hint button)
    _aboutCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _idCtrl.dispose();
    _countryCtrl.dispose();
    _cityCtrl.dispose();
    _aboutCtrl.dispose();
    _priceCtrl.dispose();
    _taxCtrl.dispose();
    _otherDescCtrl.dispose();
    super.dispose();
  }

  // ── Submit ────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Mandatory checks beyond basic field validators.
    if (_profileImageBase64 == null &&
        !(widget.prefillData['profileImage'] as String? ?? '').startsWith('http')) {
      _snack('יש להעלות תמונת פרופיל', _kRed);
      return;
    }
    if (_galleryUrls.length < 3) {
      _snack('יש להעלות לפחות 3 תמונות לגלריה', _kRed);
      return;
    }
    if (_businessType == null) {
      _snack('יש לבחור סוג עסק (עוסק פטור / מורשה / חשבונית)', _kRed);
      return;
    }

    setState(() => _isLoading = true);

    final uid     = widget.prefillData['uid'] as String?
        ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    final name    = _nameCtrl.text.trim();
    final phone   = _phoneCtrl.text.trim();
    final email   = _emailCtrl.text.trim();
    final idNum   = _idCtrl.text.trim();
    final country = _countryCtrl.text.trim();
    final city    = _cityCtrl.text.trim();
    final about   = _aboutCtrl.text.trim();
    final price   = double.tryParse(_priceCtrl.text.trim()) ?? 0.0;
    final taxId   = _taxCtrl.text.trim();

    final isOther = _isOtherCategory || _isOtherSubCategory;
    final effectiveCategory = isOther ? _otherDescCtrl.text.trim() : _category;
    final effectiveSubCategory = _isOtherCategory ? '' : _subCategory;

    try {
      final db    = FirebaseFirestore.instance;
      final batch = db.batch();
      final userRef = db.collection('users').doc(uid);

      final applicationData = {
        'submittedAt':  FieldValue.serverTimestamp(),
        'phoneNumber':  phone,
        'email':        email,
        'idNumber':     idNum,
        'country':      country,
        'city':         city,
        'businessType': _businessType,
        'category':     effectiveCategory,
        'subCategory':  effectiveSubCategory,
        'taxId':        taxId,
        'aboutMe':      about,
        'pricePerHour': price,
        'isCustomCategory': isOther,
        if (_businessDocUrl != null) 'businessDocUrl': _businessDocUrl,
        if (_introVideoUrl != null) 'introVideoUrl': _introVideoUrl,
        if (_galleryUrls.isNotEmpty) 'gallery': _galleryUrls,
      };

      final userPayload = <String, dynamic>{
        'name':                    name,
        'phone':                   phone,
        if (email.isNotEmpty) 'email': email,
        if (idNum.isNotEmpty) 'idNumber': idNum,
        if (country.isNotEmpty) 'country': country,
        if (city.isNotEmpty) 'city': city,
        'businessType':            _businessType,
        'serviceType':             effectiveCategory,
        'subCategory':             effectiveSubCategory,
        'aboutMe':                 about,
        'pricePerHour':            price,
        'gallery':                 _galleryUrls,
        'isPendingExpert':         true,
        'isProvider':              false,   // admin approval flips this
        'isVerified':              false,
        'categoryReviewedByAdmin': false,
        'expertApplicationData':   applicationData,
        'updatedAt':               FieldValue.serverTimestamp(),
        if (_profileImageBase64 != null)
          'profileImage': 'data:image/png;base64,$_profileImageBase64',
        if (_introVideoUrl != null) 'introVideoUrl': _introVideoUrl,
        if (_businessDocUrl != null) 'businessDocUrl': _businessDocUrl,
        if (isOther) 'pendingCategoryApproval': true,
      };

      if (widget.isExistingUser) {
        batch.set(userRef, userPayload, SetOptions(merge: true));
      } else {
        final d = widget.prefillData;
        batch.set(userRef, {
          'uid':            uid,
          'email':          d['email'] ?? '',
          'profileImage':   d['photoURL'] ?? d['profileImage'] ?? '',
          'balance':        0.0,
          'pendingBalance': 0.0,
          'rating':         5.0,
          'reviewsCount':   0,
          'gallery':        [],
          'quickTags':      [],
          'isOnline':       true,
          'isAdmin':        false,
          'isCustomer':     false,
          'termsAccepted':      true,
          'onboardingComplete': true,
          'tourComplete':       false,
          'createdAt':          FieldValue.serverTimestamp(),
          ...userPayload,
        }, SetOptions(merge: false));
      }

      // ── Activity log for admin Live Feed ──────────────────────────────────
      batch.set(db.collection('activity_log').doc(), {
        'type':        'expert_application',
        'userId':      uid,
        'name':        name,
        'phone':       phone,
        'category':    effectiveCategory,
        'priority':    isOther ? 'urgent' : 'high',
        'timestamp':   FieldValue.serverTimestamp(),
        'message':     isOther
            ? 'בקשת קטגוריה חדשה מ$name: "$effectiveCategory"'
            : 'בקשת הצטרפות כנותן שירות ב$effectiveCategory: $name',
        'expireAt':    Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 30))),
      });

      // ── "Other" category: create request + send admin email ────────────
      if (isOther) {
        batch.set(db.collection('category_requests').doc(), {
          'userId':      uid,
          'userName':    name,
          'description': _otherDescCtrl.text.trim(),
          'originalCategory': _isOtherCategory ? null : _category,
          'status':      'pending',
          'createdAt':   FieldValue.serverTimestamp(),
        });

        // Admin email notification via mail collection (Firebase Trigger Email)
        batch.set(db.collection('mail').doc(), {
          'to': ['adawiavihai@gmail.com'],
          'message': {
            'subject': 'AnySkill — בקשת קטגוריה חדשה מ$name',
            'html': '<p style="direction:rtl;font-family:sans-serif">'
                '<strong>$name</strong> ($phone) ביקש/ה קטגוריה חדשה:<br><br>'
                '<em>"${_otherDescCtrl.text.trim()}"</em><br><br>'
                'UID: $uid<br>'
                'אישור דרך לוח הניהול → ניהול → תיבת פניות</p>',
          },
        });
      }

      await batch.commit();

      // PR 1 (v11.9.x): Mirror KYC fields into private/kyc subcollection.
      // Dual-write during migration — admin verification tab now reads from
      // the subcollection (with legacy fallback).
      await PrivateDataService.writeKycData(
        uid,
        idNumber: idNum.isNotEmpty ? idNum : null,
        businessDocUrl: _businessDocUrl,
      );

      // PR 2a: Mirror contact fields into private/identity.
      await PrivateDataService.writeContactData(
        uid,
        phone: phone,
        email: email.isNotEmpty ? email : null,
      );

      if (mounted) {
        if (widget.isExistingUser) {
          Navigator.of(context).pop();
          _snack(
            isOther
                ? 'הבקשה נשלחה! נבדוק את הקטגוריה החדשה ונחזור אליך.'
                : 'הבקשה נשלחה! נחזור אליך בהקדם לאחר בדיקת הפרטים.',
            _kGreen,
          );
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
                builder: (_) => const PendingVerificationScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _snack('שגיאה בשמירת הבקשה. נסה שוב.\n$e', _kRed);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FF),
      body: CustomScrollView(
        slivers: [
          // ── Header ──────────────────────────────────────────────────────────
          SliverToBoxAdapter(child: _buildHeader()),

          // ── Form card ───────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -24),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: _kPurple.withValues(alpha: 0.10),
                      blurRadius: 32,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionTitle('פרטים אישיים'),
                      const SizedBox(height: 16),

                      // Profile image
                      _buildProfileImagePicker(),
                      const SizedBox(height: 16),

                      // Name
                      _field(
                        ctrl: _nameCtrl,
                        label: 'שם מלא',
                        icon: Icons.person_outline_rounded,
                        validator: (v) =>
                            (v?.trim().isEmpty ?? true) ? 'שדה חובה' : null,
                      ),
                      const SizedBox(height: 14),

                      // Phone (readonly if pre-filled from phone auth)
                      _field(
                        ctrl: _phoneCtrl,
                        label: 'מספר טלפון',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        readOnly: _phoneCtrl.text.isNotEmpty,
                        validator: (v) =>
                            (v?.trim().isEmpty ?? true) ? 'שדה חובה' : null,
                      ),
                      const SizedBox(height: 14),

                      // Email
                      _field(
                        ctrl: _emailCtrl,
                        label: 'אימייל',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          final s = v?.trim() ?? '';
                          if (s.isEmpty) return 'שדה חובה';
                          if (!s.contains('@') || !s.contains('.')) return 'אימייל לא תקין';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // ID number (ת.ז / דרכון)
                      _field(
                        ctrl: _idCtrl,
                        label: 'ת.ז / דרכון',
                        icon: Icons.badge_outlined,
                        keyboardType: TextInputType.number,
                        validator: (v) =>
                            (v?.trim().length ?? 0) < 5 ? 'הזן מספר תקין' : null,
                      ),
                      const SizedBox(height: 14),

                      // Country + City in one row
                      Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          Expanded(
                            child: _field(
                              ctrl: _countryCtrl,
                              label: 'מדינה',
                              icon: Icons.public_rounded,
                              validator: (v) =>
                                  (v?.trim().isEmpty ?? true) ? 'שדה חובה' : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _field(
                              ctrl: _cityCtrl,
                              label: 'עיר',
                              icon: Icons.location_city_rounded,
                              validator: (v) =>
                                  (v?.trim().isEmpty ?? true) ? 'שדה חובה' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      _sectionTitle('פרטי השירות'),
                      const SizedBox(height: 16),

                      // Category
                      _buildCategoryDropdown(),
                      const SizedBox(height: 14),

                      // Sub-category
                      _buildSubCategoryDropdown(),

                      // "Other" free-text (shown when אחר... selected)
                      _buildOtherDescription(),
                      const SizedBox(height: 14),

                      // AI service suggestions (only for known categories)
                      if (!_isOtherCategory) _buildServiceSuggestions(),
                      if (!_isOtherCategory) const SizedBox(height: 14),

                      // About me
                      _field(
                        ctrl: _aboutCtrl,
                        label: 'ספר/י על עצמך ועל השירות שאתה מציע',
                        icon: Icons.description_outlined,
                        maxLines: 4,
                        validator: (v) => (v?.trim().length ?? 0) < 20
                            ? 'יש לכתוב לפחות 20 תווים'
                            : null,
                      ),
                      const SizedBox(height: 14),

                      // Price — label changes per category
                      _field(
                        ctrl: _priceCtrl,
                        label: ServiceArchitect.priceLabelFor(_category),
                        icon: Icons.attach_money_rounded,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
                        ],
                        validator: (v) {
                          final n = double.tryParse(v?.trim() ?? '');
                          if (n == null || n <= 0) return 'הזן מחיר תקני';
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      _sectionTitle('גלריה ווידאו'),
                      const SizedBox(height: 16),

                      _buildGalleryPicker(),
                      const SizedBox(height: 18),

                      _buildIntroVideoPicker(),
                      const SizedBox(height: 24),

                      _sectionTitle('עוסק ומסמכים'),
                      const SizedBox(height: 16),

                      // Business type (עוסק פטור / מורשה / חשבונית למשכיר)
                      _buildBusinessTypeDropdown(),
                      const SizedBox(height: 14),

                      // Tax / business ID
                      _field(
                        ctrl: _taxCtrl,
                        label: 'מספר עוסק (אופציונלי)',
                        icon: Icons.numbers_rounded,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),

                      // ── Business document upload ────────────────────────
                      _buildDocumentUpload(),
                      const SizedBox(height: 28),

                      // ── Info box ─────────────────────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _kGreen.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: _kGreen.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          textDirection: TextDirection.rtl,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded,
                                color: _kGreen, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'לאחר הגשת הבקשה, צוות AnySkill יבדוק את הפרטים שלך ויאשר את הפרופיל בדרך כלל תוך 24 שעות.',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.grey[700],
                                    height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Submit button ────────────────────────────────────────
                      _buildSubmitButton(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      height: 220,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF059669), Color(0xFF10B981), Color(0xFF34D399)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(top: -40, left: -40,
            child: Container(width: 160, height: 160,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06)))),
          Positioned(bottom: 10, right: -20,
            child: Container(width: 110, height: 110,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.07)))),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white),
                    onPressed: () => Navigator.maybePop(context),
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.handyman_rounded,
                            color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('הצטרפות כנותן שירות',
                              style: TextStyle(color: Colors.white,
                                  fontSize: 20, fontWeight: FontWeight.w900)),
                          Text(
                            widget.isExistingUser
                                ? 'שדרג את חשבונך ותתחיל להרוויח'
                                : 'מלא את הפרטים ונאשר אותך בהקדם',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: CustomPaint(
              size: const Size(double.infinity, 28),
              painter: _WavePainter(color: const Color(0xFFF5F5FF)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Category dropdown (with "אחר..." option) ─────────────────────────────
  Widget _buildCategoryDropdown() {
    final cats = APP_CATEGORIES.map((c) => c['name'] as String).toList();
    final allOptions = [...cats, _kOther];
    final displayValue = _isOtherCategory ? _kOther : _category;

    return DropdownButtonFormField<String>(
      value: allOptions.contains(displayValue) ? displayValue : cats.first,
      decoration: _inputDeco('תחום עיסוק', Icons.category_outlined),
      isExpanded: true,
      items: allOptions.map((name) => DropdownMenuItem(
        value: name,
        child: Text(
          name,
          textAlign: TextAlign.right,
          style: name == _kOther
              ? const TextStyle(color: _kPurple, fontWeight: FontWeight.w600)
              : null,
        ),
      )).toList(),
      onChanged: (v) {
        if (v == null) return;
        if (v == _kOther) {
          setState(() {
            _isOtherCategory = true;
            _isOtherSubCategory = true;
            _category = '';
            _subCategory = '';
          });
        } else {
          final subs = APP_SUB_CATEGORIES[v] ?? [];
          setState(() {
            _isOtherCategory = false;
            _isOtherSubCategory = false;
            _category = v;
            _subCategory = subs.isNotEmpty ? subs.first : '';
          });
        }
      },
    );
  }

  // ── Sub-category dropdown (with "אחר..." option) ─────────────────────────
  Widget _buildSubCategoryDropdown() {
    // If "Other" category → show only the free-text field
    if (_isOtherCategory) return const SizedBox.shrink();

    final subs = APP_SUB_CATEGORIES[_category] ?? [];
    if (subs.isEmpty) return const SizedBox.shrink();

    final allSubs = [...subs, _kOther];
    final displayValue = _isOtherSubCategory ? _kOther
        : (subs.contains(_subCategory) ? _subCategory : subs.first);

    return DropdownButtonFormField<String>(
      value: allSubs.contains(displayValue) ? displayValue : subs.first,
      decoration: _inputDeco('תת-קטגוריה', Icons.tune_rounded),
      isExpanded: true,
      items: allSubs.map((s) => DropdownMenuItem(
        value: s,
        child: Text(
          s,
          textAlign: TextAlign.right,
          style: s == _kOther
              ? const TextStyle(color: _kPurple, fontWeight: FontWeight.w600)
              : null,
        ),
      )).toList(),
      onChanged: (v) {
        if (v == _kOther) {
          setState(() {
            _isOtherSubCategory = true;
            _subCategory = '';
          });
        } else {
          setState(() {
            _isOtherSubCategory = false;
            _subCategory = v ?? _subCategory;
          });
        }
      },
    );
  }

  // ── "Other" free-text description field ──────────────────────────────────
  Widget _buildOtherDescription() {
    if (!_isOtherCategory && !_isOtherSubCategory) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kPurple.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kPurple.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.edit_note_rounded, size: 16, color: _kPurple),
                  SizedBox(width: 6),
                  Text(
                    'קטגוריה חדשה — ממתין לאישור מנהל',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _kPurple,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _otherDescCtrl,
                textAlign: TextAlign.right,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'תאר את השירות שלך בפירוט...',
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _kPurple, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
                validator: (v) {
                  if ((_isOtherCategory || _isOtherSubCategory) &&
                      (v?.trim().length ?? 0) < 10) {
                    return 'יש לתאר את השירות (לפחות 10 תווים)';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Submit button ─────────────────────────────────────────────────────────
  Widget _buildSubmitButton() {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 40, height: 40,
          child: CircularProgressIndicator(strokeWidth: 3, color: _kPurple),
        ),
      );
    }
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kPurpleDark, _kPurple, _kPurpleLight],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _kPurple.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
        label: Text(
          widget.isExistingUser ? 'שלח בקשה לאישור' : 'צור פרופיל ושלח לאישור',
          style: const TextStyle(color: Colors.white, fontSize: 17,
              fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // ── AI Service Suggestions ────────────────────────────────────────────────
  Widget _buildServiceSuggestions() {
    final templates = ServiceArchitect.templatesFor(_category);
    final priceText = _priceCtrl.text.trim();
    final basePrice = double.tryParse(priceText) ?? 0.0;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF4F46E5).withValues(alpha: 0.06),
            const Color(0xFF7C3AED).withValues(alpha: 0.04),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _kPurple.withValues(alpha: 0.18),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _kPurple.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: _kPurple,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded,
                      color: Colors.white, size: 14),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Service Architect — מנוע השירותים',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4F46E5),
                  ),
                ),
                const Spacer(),
                Text(
                  _category,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // ── Service cards ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: List.generate(templates.length, (i) {
                final t         = templates[i];
                final calcPrice = basePrice > 0
                    ? (basePrice * t.multiplier).round()
                    : null;
                return Padding(
                  padding: EdgeInsets.only(bottom: i < 2 ? 8 : 0),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      // Unit icon badge
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: _kPurple.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(t.unitIcon,
                            size: 18, color: _kPurple),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(t.title,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E1B4B),
                                )),
                            Text(t.subtitle,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey[500],
                                )),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Price estimate + unit label
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (calcPrice != null)
                            Text('₪$calcPrice',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF4F46E5),
                                )),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: _kPurple.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(t.unitLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: _kPurple,
                                )),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          // ── Bio suggestion button ─────────────────────────────────────────
          if (_aboutCtrl.text.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _aboutCtrl.text =
                        ServiceArchitect.bioSuggestionFor(_category);
                  });
                },
                style: TextButton.styleFrom(
                  backgroundColor: _kPurple.withValues(alpha: 0.06),
                  foregroundColor: _kPurple,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.edit_note_rounded, size: 16),
                label: const Text('מלא תיאור מוצע',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
    );
  }

  // ── Business Document Upload ───────────────────────────────────────────────
  Widget _buildDocumentUpload() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.upload_file_rounded, size: 18, color: _kPurple),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'העלה תעודת עוסק מורשה/פטור או רישיון עסק',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'אופציונלי — מזרז את תהליך האישור',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
          const SizedBox(height: 12),

          if (_businessDocUrl != null) ...[
            // ── Uploaded state ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kGreen.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: _kGreen, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'מסמך הועלה בהצלחה',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF065F46),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _businessDocUrl = null),
                    child: const Icon(Icons.close, size: 16,
                        color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            ),
          ] else ...[
            // ── Upload button ───────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                icon: _isUploading
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _kPurple))
                    : const Icon(Icons.cloud_upload_outlined, size: 18),
                label: Text(
                  _isUploading ? 'מעלה...' : 'בחר קובץ',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kPurple,
                  side: const BorderSide(color: _kPurple, width: 1.2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isUploading ? null : _pickAndUploadDocument,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickAndUploadDocument() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 85,
    );
    if (file == null) return;

    setState(() => _isUploading = true);
    try {
      final uid = widget.prefillData['uid'] as String?
          ?? FirebaseAuth.instance.currentUser?.uid ?? '';
      final bytes = await file.readAsBytes();
      final ext = file.name.split('.').last;
      final ref = FirebaseStorage.instance
          .ref('business_docs/$uid/license_${DateTime.now().millisecondsSinceEpoch}.$ext');

      await ref.putData(
        Uint8List.fromList(bytes),
        SettableMetadata(contentType: 'image/$ext'),
      );
      final url = await ref.getDownloadURL();

      if (mounted) setState(() => _businessDocUrl = url);
    } catch (e) {
      if (mounted) _snack('שגיאה בהעלאה: $e', _kRed);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _sectionTitle(String text) {
    return Row(
      children: [
        Container(width: 3, height: 16,
            decoration: BoxDecoration(
                color: _kPurple,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(text,
            style: const TextStyle(fontSize: 15,
                fontWeight: FontWeight.bold, color: Color(0xFF1E1B4B))),
      ],
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
      prefixIcon: Icon(icon, size: 20, color: Colors.grey[400]),
      filled: true,
      fillColor: const Color(0xFFFAFAFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade200, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kPurple, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kRed, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kRed, width: 1.6),
      ),
    );
  }

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
    bool readOnly = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      readOnly: readOnly,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      textAlign: TextAlign.right,
      validator: validator,
      decoration: _inputDeco(label, icon),
    );
  }

  // ── Business type dropdown ─────────────────────────────────────────────
  Widget _buildBusinessTypeDropdown() {
    return DropdownButtonFormField<String>(
      value: _businessType,
      decoration: _inputDeco('סוג עסק', Icons.business_center_outlined),
      isExpanded: true,
      items: _kBusinessTypes
          .map((t) => DropdownMenuItem(
                value: t,
                child: Text(t, textAlign: TextAlign.right),
              ))
          .toList(),
      onChanged: (v) => setState(() => _businessType = v),
      validator: (v) => v == null || v.isEmpty ? 'בחר סוג עסק' : null,
    );
  }

  // ── Profile image picker (base64 data URI) ─────────────────────────────
  Widget _buildProfileImagePicker() {
    final hasImage = _profileImageBase64 != null;
    final prefillImage = widget.prefillData['profileImage'] as String? ?? '';
    final provider = hasImage
        ? safeImageProvider('data:image/png;base64,$_profileImageBase64')
        : (prefillImage.isNotEmpty ? safeImageProvider(prefillImage) : null);
    return GestureDetector(
      onTap: _isUploadingProfile ? null : _pickProfileImage,
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Container(
            width: 76, height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFAFAFF),
              border: Border.all(color: _kPurple.withValues(alpha: 0.2), width: 1.5),
            ),
            child: _isUploadingProfile
                ? const Center(
                    child: SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _kPurple),
                    ),
                  )
                : ClipOval(
                    child: provider != null
                        ? Image(image: provider, fit: BoxFit.cover, width: 76, height: 76)
                        : const Icon(Icons.person_rounded,
                            size: 36, color: _kPurple),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  provider != null ? 'החלף תמונה' : 'הוסף תמונת פרופיל',
                  style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: _kPurple),
                ),
                const SizedBox(height: 4),
                Text(
                  'תמונה ברורה ומקצועית תעזור לך לקבל יותר לקוחות',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickProfileImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      imageQuality: 70,
    );
    if (file == null) return;
    setState(() => _isUploadingProfile = true);
    try {
      final bytes = await file.readAsBytes();
      setState(() => _profileImageBase64 = base64Encode(bytes));
    } catch (e) {
      if (mounted) _snack('שגיאה בטעינת התמונה', _kRed);
    } finally {
      if (mounted) setState(() => _isUploadingProfile = false);
    }
  }

  // ── Gallery picker (up to 6 images) ────────────────────────────────────
  Widget _buildGalleryPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          textDirection: TextDirection.rtl,
          children: [
            const Icon(Icons.photo_library_rounded, size: 18, color: _kPurple),
            const SizedBox(width: 8),
            const Text('גלריית תמונות',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
                    color: Color(0xFF1E1B4B))),
            const SizedBox(width: 6),
            Text('(${_galleryUrls.length}/6 — מינימום 3)',
                style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            reverse: true,
            itemCount: _galleryUrls.length + (_galleryUrls.length < 6 ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              if (i == _galleryUrls.length) {
                return _addGallerySlot();
              }
              final url = _galleryUrls[i];
              return _gallerySlot(url);
            },
          ),
        ),
      ],
    );
  }

  Widget _addGallerySlot() {
    return GestureDetector(
      onTap: _isUploadingGallery ? null : _pickAndUploadGalleryImage,
      child: Container(
        width: 92, height: 92,
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kPurple.withValues(alpha: 0.3), width: 1.5),
        ),
        child: _isUploadingGallery
            ? const Center(
                child: SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _kPurple),
                ),
              )
            : const Icon(Icons.add_photo_alternate_rounded,
                size: 32, color: _kPurple),
      ),
    );
  }

  Widget _gallerySlot(String url) {
    final provider = safeImageProvider(url);
    return Stack(
      children: [
        Container(
          width: 92, height: 92,
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: provider != null
                ? Image(image: provider, fit: BoxFit.cover, width: 92, height: 92)
                : const Icon(Icons.broken_image_rounded, color: Colors.grey),
          ),
        ),
        Positioned(
          top: 4, right: 4,
          child: GestureDetector(
            onTap: () => setState(() => _galleryUrls.remove(url)),
            child: Container(
              width: 22, height: 22,
              decoration: const BoxDecoration(
                color: _kRed, shape: BoxShape.circle),
              child: const Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickAndUploadGalleryImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 75,
    );
    if (file == null) return;
    setState(() => _isUploadingGallery = true);
    try {
      final uid = widget.prefillData['uid'] as String?
          ?? FirebaseAuth.instance.currentUser?.uid ?? '';
      final bytes = await file.readAsBytes();
      final ext = file.name.split('.').last;
      final ref = FirebaseStorage.instance.ref(
          'gallery/$uid/g_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await ref.putData(
        Uint8List.fromList(bytes),
        SettableMetadata(contentType: 'image/$ext'),
      );
      final url = await ref.getDownloadURL();
      if (mounted) setState(() => _galleryUrls.add(url));
    } catch (e) {
      if (mounted) _snack('שגיאה בהעלאת תמונה: $e', _kRed);
    } finally {
      if (mounted) setState(() => _isUploadingGallery = false);
    }
  }

  // ── Intro video picker (optional) ──────────────────────────────────────
  Widget _buildIntroVideoPicker() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            children: [
              const Icon(Icons.videocam_rounded, size: 18, color: _kPurple),
              const SizedBox(width: 8),
              const Text('וידאו היכרות',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
                      color: Color(0xFF1E1B4B))),
              const SizedBox(width: 6),
              Text('(אופציונלי — עד 60 שניות)',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            ],
          ),
          const SizedBox(height: 10),
          if (_introVideoUrl != null) ...[
            Row(
              children: [
                const Icon(Icons.check_circle, color: _kGreen, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                    child: Text('וידאו הועלה',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF065F46)))),
                GestureDetector(
                  onTap: () => setState(() => _introVideoUrl = null),
                  child: const Icon(Icons.close, size: 16, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
          ] else
            SizedBox(
              width: double.infinity, height: 44,
              child: OutlinedButton.icon(
                icon: _isUploadingVideo
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _kPurple))
                    : const Icon(Icons.video_call_rounded, size: 18),
                label: Text(_isUploadingVideo ? 'מעלה...' : 'הקלט / בחר וידאו',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kPurple,
                  side: const BorderSide(color: _kPurple, width: 1.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isUploadingVideo ? null : _pickAndUploadVideo,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadVideo() async {
    final file = await ImagePicker().pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 60),
    );
    if (file == null) return;
    setState(() => _isUploadingVideo = true);
    try {
      final uid = widget.prefillData['uid'] as String?
          ?? FirebaseAuth.instance.currentUser?.uid ?? '';
      final bytes = await file.readAsBytes();
      final ext = file.name.split('.').last;
      final ref = FirebaseStorage.instance.ref(
          'intro_videos/$uid/v_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await ref.putData(
        Uint8List.fromList(bytes),
        SettableMetadata(contentType: 'video/$ext'),
      );
      final url = await ref.getDownloadURL();
      if (mounted) setState(() => _introVideoUrl = url);
    } catch (e) {
      if (mounted) _snack('שגיאה בהעלאת הוידאו: $e', _kRed);
    } finally {
      if (mounted) setState(() => _isUploadingVideo = false);
    }
  }
}

// ── Wave painter ──────────────────────────────────────────────────────────────
class _WavePainter extends CustomPainter {
  const _WavePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..quadraticBezierTo(size.width * 0.25, 0, size.width * 0.5, size.height * 0.5)
      ..quadraticBezierTo(size.width * 0.75, size.height, size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.color != color;
}
