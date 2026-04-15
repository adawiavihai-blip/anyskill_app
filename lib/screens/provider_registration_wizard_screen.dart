/// AnySkill — Provider Registration Wizard (v3)
///
/// 4-step wizard for clients upgrading to providers. Replaces the old
/// "רוצה להרוויח כסף?" single-form flow. Design source of truth:
/// [anyskill_provider_registration_v3.html] at the project root.
///
/// Step 1 — Personal details
/// Step 2 — Field of work (categories + subcategories synced with Firestore)
/// Step 3 — Location + ID verification (doc upload)
/// Step 4 — Business type + business doc + bank + ToS with scroll-to-bottom
///
/// Submission writes to:
///   users/{uid} {isPendingExpert: true, expertApplicationData: {...}}
///   users/{uid}/private/kyc       (idDocUrl, idNumber, businessDocUrl)
///   users/{uid}/private/identity  (phone, email)
///   users/{uid}/private/financial (bankDetails)
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/category.dart';
import '../repositories/category_repository.dart';
import '../services/private_data_service.dart';
import '../utils/image_compressor.dart';

// ── Brand tokens (match HTML reference) ─────────────────────────────────────
const _kAccent       = Color(0xFF6C5CE7);
const _kAccentDark   = Color(0xFF5A49D6);
const _kAccentLight  = Color(0xFFEDEAFD);
const _kBg           = Color(0xFFF5F6FA);
const _kSurface      = Colors.white;
const _kBorder       = Color(0xFFE2E6F0);
const _kTextPrimary  = Color(0xFF171B2E);
const _kTextSecondary = Color(0xFF5A6180);
const _kTextMuted    = Color(0xFF959CB8);
const _kSuccess      = Color(0xFF10B981);
const _kSuccessLight = Color(0xFFECFDF5);
const _kError        = Color(0xFFEF4444);

// ── Israeli cities (matches HTML reference) ─────────────────────────────────
const List<String> _kIsraeliCities = [
  'תל אביב - יפו',
  'ירושלים',
  'חיפה',
  'ראשון לציון',
  'פתח תקווה',
  'אשדוד',
  'נתניה',
  'באר שבע',
  'חולון',
  'בני ברק',
  'רמת גן',
  'אשקלון',
  'הרצליה',
  'כפר סבא',
  'רעננה',
  'מודיעין',
  'אילת',
  'נצרת',
  'עכו',
  'בת ים',
  'אחר',
];

const List<String> _kCountries = [
  'ישראל',
  'ארצות הברית',
  'בריטניה',
  'גרמניה',
  'צרפת',
  'קנדה',
  'אוסטרליה',
  'אחר',
];

const List<String> _kBusinessTypes = [
  'עוסק פטור',
  'עוסק מורשה',
  'חברה בע"מ',
  'חשבונית למשכיר',
];

// Israeli banks: {name → bank number}
const Map<String, String> _kIsraeliBanks = {
  'בנק הפועלים': '12',
  'בנק דיסקונט': '11',
  'בנק לאומי': '10',
  'בנק מזרחי טפחות': '20',
  'בנק הבינלאומי': '31',
  'בנק אוצר החייל': '14',
  'בנק איגוד': '13',
  'בנק מרכנתיל דיסקונט': '17',
  'בנק הדואר': '09',
  'בנק מסד': '46',
  'בנק ירושלים': '54',
  'יובנק': '26',
  'בנק יהב': '04',
  'בנק ערבי ישראלי': '34',
};

class ProviderRegistrationWizardScreen extends StatefulWidget {
  const ProviderRegistrationWizardScreen({super.key});

  @override
  State<ProviderRegistrationWizardScreen> createState() =>
      _ProviderRegistrationWizardScreenState();
}

class _ProviderRegistrationWizardScreenState
    extends State<ProviderRegistrationWizardScreen> {
  int _step = 0; // 0..3

  // ── Step 1 — personal details ─────────────────────────────────────────
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  // ── Step 2 — field of work ────────────────────────────────────────────
  Category? _category;
  Category? _subCategory;
  final _bioCtrl = TextEditingController();

  // ── Step 3 — location + ID ────────────────────────────────────────────
  String _country = 'ישראל';
  String? _city;
  final _streetCtrl = TextEditingController();
  String? _idDocUrl;
  String? _idDocName;
  bool _uploadingId = false;

  // ── Step 4 — business + bank + terms ──────────────────────────────────
  String? _businessType;
  String? _businessDocUrl;
  String? _businessDocName;
  bool _uploadingBusinessDoc = false;

  String? _bankName;
  String _bankNumber = '';
  final _branchCtrl  = TextEditingController();
  final _accountCtrl = TextEditingController();

  final _termsScrollCtrl = ScrollController();
  bool _termsScrolledToBottom = false;
  bool _termsAccepted = false;

  // ── Meta ──────────────────────────────────────────────────────────────
  bool _submitting = false;
  final _categoryRepo = CategoryRepository();

  @override
  void initState() {
    super.initState();
    // Prefill from existing Firebase Auth user.
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _nameCtrl.text  = user.displayName ?? '';
      _phoneCtrl.text = user.phoneNumber ?? '';
      _emailCtrl.text = user.email ?? '';
    }
    _termsScrollCtrl.addListener(_checkTermsScroll);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _bioCtrl.dispose();
    _streetCtrl.dispose();
    _branchCtrl.dispose();
    _accountCtrl.dispose();
    _termsScrollCtrl.removeListener(_checkTermsScroll);
    _termsScrollCtrl.dispose();
    super.dispose();
  }

  void _checkTermsScroll() {
    if (!_termsScrollCtrl.hasClients) return;
    final pos = _termsScrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 20 && !_termsScrolledToBottom) {
      setState(() => _termsScrolledToBottom = true);
    }
  }

  // ── Validation per step ─────────────────────────────────────────────────
  String? _validateStep(int step) {
    switch (step) {
      case 0:
        if (_nameCtrl.text.trim().isEmpty) return 'נא למלא שם מלא';
        if (!RegExp(r'^0\d{1,2}-?\d{7}$').hasMatch(_phoneCtrl.text.trim())) {
          return 'מספר טלפון לא תקין';
        }
        if (!RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(_emailCtrl.text.trim())) {
          return 'אימייל לא תקין';
        }
        return null;
      case 1:
        if (_category == null) return 'נא לבחור קטגוריה';
        if (_subCategory == null) return 'נא לבחור תת-קטגוריה';
        if (_bioCtrl.text.trim().length < 20) return 'תיאור קצר מדי (מינימום 20 תווים)';
        return null;
      case 2:
        if (_country.isEmpty) return 'נא לבחור מדינה';
        if (_city == null || _city!.isEmpty) return 'נא לבחור עיר';
        if (_streetCtrl.text.trim().isEmpty) return 'נא למלא רחוב ומספר';
        if (_idDocUrl == null) return 'נא להעלות צילום תעודת זהות';
        return null;
      case 3:
        if (_businessType == null) return 'נא לבחור סוג עסק';
        if (_businessDocUrl == null) return 'נא להעלות אישור עוסק';
        if (_bankName == null) return 'נא לבחור בנק';
        if (_branchCtrl.text.trim().length < 3) return 'מספר סניף לא תקין';
        if (_accountCtrl.text.trim().length < 4) return 'מספר חשבון לא תקין';
        if (!_termsAccepted) return 'יש לאשר את תנאי השימוש';
        return null;
    }
    return null;
  }

  void _next() {
    final err = _validateStep(_step);
    if (err != null) {
      _snack(err, isError: true);
      return;
    }
    if (_step < 3) {
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  void _back() {
    if (_step == 0) {
      Navigator.pop(context);
    } else {
      setState(() => _step--);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? _kError : _kSuccess,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Upload handlers ─────────────────────────────────────────────────────
  Future<void> _pickIdDoc() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _uploadingId = true);
    try {
      final img = await ImageCompressor.pick(ImagePreset.document);
      if (img == null) {
        setState(() => _uploadingId = false);
        return;
      }
      if (img.bytes.lengthInBytes > 10 * 1024 * 1024) {
        _snack('הקובץ גדול מדי (מקסימום 10MB)', isError: true);
        setState(() => _uploadingId = false);
        return;
      }
      final ref = FirebaseStorage.instance
          .ref('id_docs/$uid/id_${DateTime.now().millisecondsSinceEpoch}.${img.ext}');
      await ref.putData(img.bytes,
          SettableMetadata(contentType: 'image/${img.ext == 'jpg' ? 'jpeg' : img.ext}'));
      final url = await ref.getDownloadURL();
      setState(() {
        _idDocUrl = url;
        _idDocName = img.name;
        _uploadingId = false;
      });
    } catch (e) {
      setState(() => _uploadingId = false);
      _snack('שגיאה בהעלאה: $e', isError: true);
    }
  }

  Future<void> _pickBusinessDoc() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _uploadingBusinessDoc = true);
    try {
      final img = await ImageCompressor.pick(ImagePreset.document);
      if (img == null) {
        setState(() => _uploadingBusinessDoc = false);
        return;
      }
      if (img.bytes.lengthInBytes > 10 * 1024 * 1024) {
        _snack('הקובץ גדול מדי (מקסימום 10MB)', isError: true);
        setState(() => _uploadingBusinessDoc = false);
        return;
      }
      final ref = FirebaseStorage.instance.ref(
          'business_docs/$uid/license_${DateTime.now().millisecondsSinceEpoch}.${img.ext}');
      await ref.putData(img.bytes,
          SettableMetadata(contentType: 'image/${img.ext == 'jpg' ? 'jpeg' : img.ext}'));
      final url = await ref.getDownloadURL();
      setState(() {
        _businessDocUrl = url;
        _businessDocName = img.name;
        _uploadingBusinessDoc = false;
      });
    } catch (e) {
      setState(() => _uploadingBusinessDoc = false);
      _snack('שגיאה בהעלאה: $e', isError: true);
    }
  }

  // ── Submit ──────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _snack('לא מחובר/ת', isError: true);
      return;
    }
    setState(() => _submitting = true);

    try {
      final applicationData = <String, dynamic>{
        'full_name':            _nameCtrl.text.trim(),
        'phone':                _phoneCtrl.text.trim(),
        'email':                _emailCtrl.text.trim(),
        'category':             _category!.name,
        'category_id':          _category!.id,
        'subcategory':          _subCategory!.name,
        'subcategory_id':       _subCategory!.id,
        'bio_description':      _bioCtrl.text.trim(),
        'country':              _country,
        'city':                 _city,
        'street_address':       _streetCtrl.text.trim(),
        'id_document_url':      _idDocUrl,
        'id_verification_status': 'pending_verification',
        'business_type':        _businessType,
        'business_document_url': _businessDocUrl,
        'bank_name':            _bankName,
        'bank_number':          _bankNumber,
        'branch_number':        _branchCtrl.text.trim(),
        'account_number':       _accountCtrl.text.trim(),
        'terms_accepted':       true,
        'terms_version':        '2.0',
        'terms_accepted_at':    FieldValue.serverTimestamp(),
        'terms_fully_scrolled': true,
      };

      // Main user doc — flag pending + snapshot under expertApplicationData
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'isPendingExpert':       true,
        'isProvider':            false,
        'name':                  _nameCtrl.text.trim(),
        'phone':                 _phoneCtrl.text.trim(),
        'email':                 _emailCtrl.text.trim(),
        'serviceType':           _subCategory!.name,
        'category':              _category!.name,
        'aboutMe':               _bioCtrl.text.trim(),
        'country':               _country,
        'city':                  _city,
        'businessType':          _businessType,
        'expertApplicationData': applicationData,
        'expertApplicationSubmittedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Dual-write private subcollections (per Law Section 11)
      await PrivateDataService.writeContactData(
        uid,
        phone: _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
      );
      await PrivateDataService.writeKycData(
        uid,
        idDocUrl: _idDocUrl,
        businessDocUrl: _businessDocUrl,
      );
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('private')
          .doc('financial')
          .set({
        'bankDetails': {
          'bankName':      _bankName,
          'bankNumber':    _bankNumber,
          'branchNumber':  _branchCtrl.text.trim(),
          'accountNumber': _accountCtrl.text.trim(),
          'accountHolder': _nameCtrl.text.trim(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Notify admins (in-app)
      await _notifyAdmins(uid, _nameCtrl.text.trim(), _subCategory!.name);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const _ConfirmationScreen()),
      );
    } catch (e) {
      setState(() => _submitting = false);
      _snack('שגיאה בשליחה: $e', isError: true);
    }
  }

  Future<void> _notifyAdmins(String applicantUid, String name, String category) async {
    try {
      final admins = await FirebaseFirestore.instance
          .collection('users')
          .where('isAdmin', isEqualTo: true)
          .limit(20)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final admin in admins.docs) {
        final ref = FirebaseFirestore.instance.collection('notifications').doc();
        batch.set(ref, {
          'userId':        admin.id,
          'title':         'בקשת הצטרפות חדשה',
          'body':          '$name מבקש/ת להצטרף כנותן שירות ($category)',
          'type':          'expert_application_submitted',
          'relatedUserId': applicantUid,
          'isRead':        false,
          'createdAt':     FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (_) {
      // Non-fatal
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _kBg,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildProgressBar(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                  child: _buildStepContent(),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomCta(),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6C5CE7), Color(0xFF4834D4)],
        ),
      ),
      child: const Column(
        children: [
          Text('AnySkill',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5)),
          SizedBox(height: 2),
          Text('הצטרפות כנותן שירות',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Container(
      color: _kSurface,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        children: [
          InkWell(
            onTap: _back,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _kBorder, width: 1.5),
                color: _kSurface,
              ),
              child: const Icon(Icons.arrow_forward_rounded,
                  size: 18, color: _kTextPrimary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: List.generate(4, (i) {
                    final done = i <= _step;
                    return Expanded(
                      child: Container(
                        margin: EdgeInsetsDirectional.only(end: i == 3 ? 0 : 4),
                        height: 6,
                        decoration: BoxDecoration(
                          color: done ? _kAccent : _kBorder,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 6),
                Text(
                  'שלב ${_step + 1} מתוך 4 · ${_stepTitle(_step)}',
                  style: const TextStyle(
                      fontSize: 12,
                      color: _kTextSecondary,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _stepTitle(int s) {
    switch (s) {
      case 0: return 'פרטים אישיים';
      case 1: return 'תחום עיסוק';
      case 2: return 'מיקום ואימות זהות';
      case 3: return 'פרטי עסק וחשבון בנק';
    }
    return '';
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0: return _buildStep1();
      case 1: return _buildStep2();
      case 2: return _buildStep3();
      case 3: return _buildStep4();
    }
    return const SizedBox.shrink();
  }

  // ── Step 1 ──────────────────────────────────────────────────────────────
  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: 'פרטים אישיים', subtitle: 'איך לקוחות יוכלו ליצור איתך קשר'),
        const SizedBox(height: 18),
        _LabeledField(
          label: 'שם מלא',
          child: _TextField(
            controller: _nameCtrl,
            hint: 'השם שיוצג ללקוחות',
          ),
        ),
        const SizedBox(height: 14),
        _LabeledField(
          label: 'מספר טלפון',
          child: _TextField(
            controller: _phoneCtrl,
            hint: '05X-XXXXXXX',
            keyboardType: TextInputType.phone,
            ltr: true,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]'))],
          ),
        ),
        const SizedBox(height: 14),
        _LabeledField(
          label: 'כתובת אימייל',
          child: _TextField(
            controller: _emailCtrl,
            hint: 'your@email.com',
            keyboardType: TextInputType.emailAddress,
            ltr: true,
          ),
        ),
      ],
    );
  }

  // ── Step 2 ──────────────────────────────────────────────────────────────
  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: 'תחום עיסוק', subtitle: 'מה תרצה/י להציע ב-AnySkill?'),
        const SizedBox(height: 18),
        _LabeledField(
          label: 'קטגוריה ראשית',
          child: StreamBuilder<List<Category>>(
            stream: _categoryRepo.watchMainCategories(),
            builder: (ctx, snap) {
              final cats = snap.data ?? const <Category>[];
              return _Dropdown<Category>(
                value: _category,
                hint: 'בחר/י קטגוריה...',
                items: cats
                    .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                    .toList(),
                onChanged: (c) => setState(() {
                  _category    = c;
                  _subCategory = null;
                }),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        if (_category != null)
          _LabeledField(
            label: 'תת-קטגוריה (התמחות)',
            child: StreamBuilder<List<Category>>(
              stream: _categoryRepo.watchSubCategories(_category!.id),
              builder: (ctx, snap) {
                final subs = snap.data ?? const <Category>[];
                if (subs.isEmpty) {
                  return const Text(
                    'אין תת-קטגוריות זמינות',
                    style: TextStyle(color: _kTextMuted, fontSize: 13),
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: subs.map((s) {
                    final selected = _subCategory?.id == s.id;
                    return InkWell(
                      onTap: () => setState(() => _subCategory = s),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: selected ? _kAccent : _kAccentLight,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: selected ? _kAccentDark : _kAccentLight,
                              width: 1.4),
                        ),
                        child: Text(
                          s.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : _kAccentDark,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        if (_subCategory != null) ...[
          const SizedBox(height: 14),
          _LabeledField(
            label: 'תיאור העיסוק',
            child: _TextField(
              controller: _bioCtrl,
              hint: 'ספרו על הניסיון שלכם, סוגי השירות, זמינות, ומה מייחד אתכם... (מינימום 20 תווים)',
              maxLines: 5,
            ),
          ),
        ],
      ],
    );
  }

  // ── Step 3 ──────────────────────────────────────────────────────────────
  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: 'מיקום ואימות זהות', subtitle: 'מסמכים מוצפנים לצורכי אימות בלבד'),
        const SizedBox(height: 18),
        _LabeledField(
          label: 'מדינה',
          child: _Dropdown<String>(
            value: _country,
            items: _kCountries
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _country = v ?? 'ישראל'),
          ),
        ),
        const SizedBox(height: 14),
        _LabeledField(
          label: 'עיר',
          child: _Dropdown<String>(
            value: _city,
            hint: 'בחר/י עיר...',
            items: _kIsraeliCities
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _city = v),
          ),
        ),
        const SizedBox(height: 14),
        _LabeledField(
          label: 'רחוב ומספר',
          child: _TextField(
            controller: _streetCtrl,
            hint: 'לדוגמא: הרצל 15',
          ),
        ),
        const SizedBox(height: 18),
        _LabeledField(
          label: 'אימות זהות',
          child: _UploadBox(
            icon: Icons.badge_outlined,
            title: _idDocUrl == null
                ? 'העלה צילום תעודת זהות / דרכון'
                : 'הקובץ הועלה בהצלחה',
            subtitle: _idDocUrl == null ? 'JPG או PNG · עד 10MB' : _idDocName,
            uploading: _uploadingId,
            uploaded: _idDocUrl != null,
            onTap: _uploadingId ? null : _pickIdDoc,
          ),
        ),
        if (_idDocUrl != null) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: const [
              _MiniTag(icon: Icons.lock_rounded, label: 'מוצפן'),
              _MiniTag(icon: Icons.visibility_off_rounded, label: 'פרטי'),
              _MiniTag(icon: Icons.hourglass_top_rounded, label: 'ממתין לאישור'),
            ],
          ),
        ],
        const SizedBox(height: 8),
        const Text(
          'המסמך מאוחסן בהצפנה ומשמש לאימות בלבד — לא יוצג ללקוחות',
          style: TextStyle(fontSize: 12, color: _kTextMuted, height: 1.5),
        ),
      ],
    );
  }

  // ── Step 4 ──────────────────────────────────────────────────────────────
  Widget _buildStep4() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: 'פרטי עסק וחשבון בנק', subtitle: 'מסמכים ופרטים להעברת תשלומים'),
        const SizedBox(height: 18),

        // Business type
        _LabeledField(
          label: 'סוג העסק',
          child: _Dropdown<String>(
            value: _businessType,
            hint: 'בחר/י סוג עסק...',
            items: _kBusinessTypes
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (v) => setState(() => _businessType = v),
          ),
        ),
        if (_businessType != null) ...[
          const SizedBox(height: 14),
          _LabeledField(
            label: 'העלאת אישור עוסק',
            child: _UploadBox(
              icon: Icons.description_outlined,
              title: _businessDocUrl == null
                  ? 'העלה תעודת עוסק / רישיון עסק'
                  : 'הקובץ הועלה בהצלחה',
              subtitle: _businessDocUrl == null
                  ? 'JPG או PNG · עד 10MB'
                  : _businessDocName,
              uploading: _uploadingBusinessDoc,
              uploaded: _businessDocUrl != null,
              onTap: _uploadingBusinessDoc ? null : _pickBusinessDoc,
            ),
          ),
        ],

        const SizedBox(height: 18),
        const Divider(color: _kBorder, height: 1),
        const SizedBox(height: 18),

        // Bank
        _LabeledField(
          label: 'שם הבנק',
          child: _Dropdown<String>(
            value: _bankName,
            hint: 'בחר/י בנק...',
            items: _kIsraeliBanks.entries
                .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text('${e.key} (${e.value})'),
                    ))
                .toList(),
            onChanged: (v) => setState(() {
              _bankName   = v;
              _bankNumber = v != null ? _kIsraeliBanks[v] ?? '' : '';
            }),
          ),
        ),
        if (_bankName != null) ...[
          const SizedBox(height: 14),
          _LabeledField(
            label: 'מספר בנק',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: _kBg,
                border: Border.all(color: _kBorder, width: 1.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _bankNumber,
                style: const TextStyle(
                    fontSize: 14, color: _kTextMuted, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        _LabeledField(
          label: 'מספר סניף',
          child: _TextField(
            controller: _branchCtrl,
            hint: '185',
            keyboardType: TextInputType.number,
            ltr: true,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _LabeledField(
          label: 'מספר חשבון',
          child: _TextField(
            controller: _accountCtrl,
            hint: '123456',
            keyboardType: TextInputType.number,
            ltr: true,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(9),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const _InfoLine(
          icon: Icons.lock_outline_rounded,
          text: 'פרטי הבנק מוצפנים ומשמשים להעברת תשלומים בלבד',
        ),

        const SizedBox(height: 24),
        _AnySkillInBriefCard(),

        const SizedBox(height: 18),
        _buildTermsBox(),
      ],
    );
  }

  Widget _buildTermsBox() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: _kSurface,
            border: Border.all(color: _kBorder, width: 1.2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: const BoxDecoration(
                  color: _kAccentLight,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(13),
                    topRight: Radius.circular(13),
                  ),
                ),
                child: const Text(
                  '📜 תנאי שימוש ומדיניות פרטיות',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: _kAccentDark),
                ),
              ),
              SizedBox(
                height: 300,
                child: Scrollbar(
                  controller: _termsScrollCtrl,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _termsScrollCtrl,
                    padding: const EdgeInsets.all(14),
                    child: const _TermsContent(),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!_termsScrolledToBottom) ...[
          const SizedBox(height: 8),
          const _ScrollHint(),
        ],
        const SizedBox(height: 12),
        InkWell(
          onTap: _termsScrolledToBottom
              ? () => setState(() => _termsAccepted = !_termsAccepted)
              : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _termsScrolledToBottom
                  ? (_termsAccepted ? _kAccentLight : _kSurface)
                  : const Color(0xFFF4F5F8),
              border: Border.all(
                color: _termsAccepted ? _kAccent : _kBorder,
                width: 1.4,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _termsAccepted ? _kAccent : _kSurface,
                    border: Border.all(
                      color: _termsAccepted ? _kAccent : _kBorder,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: _termsAccepted
                      ? const Icon(Icons.check_rounded,
                          size: 16, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'אני מאשר/ת שקראתי והסכמתי לתנאי השימוש ולמדיניות הפרטיות של AnySkill (גרסה 2.0)',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: _termsScrolledToBottom
                          ? _kTextPrimary
                          : _kTextMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Bottom CTA ──────────────────────────────────────────────────────────
  Widget _buildBottomCta() {
    final isLast = _step == 3;
    final canProceed = !_submitting;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      decoration: BoxDecoration(
        color: _kSurface,
        border: Border(top: BorderSide(color: _kBorder, width: 1.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: canProceed ? _next : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _kAccent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            disabledBackgroundColor: _kTextMuted,
          ),
          child: _submitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(isLast ? 'שלח בקשת הצטרפות ל-AnySkill' : 'המשך'),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_back_rounded, size: 18),
                  ],
                ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//                               Helper widgets
// ────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: _kTextPrimary)),
        const SizedBox(height: 4),
        Text(subtitle,
            style: const TextStyle(fontSize: 13, color: _kTextSecondary, height: 1.4)),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: _kTextPrimary)),
            const SizedBox(width: 6),
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                  color: _kError, shape: BoxShape.circle),
            ),
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool ltr;
  final List<TextInputFormatter>? inputFormatters;
  const _TextField({
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.maxLines = 1,
    this.ltr = false,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      textDirection: ltr ? TextDirection.ltr : null,
      inputFormatters: inputFormatters,
      style: const TextStyle(fontSize: 14, color: _kTextPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _kTextMuted, fontSize: 13),
        filled: true,
        fillColor: _kSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBorder, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBorder, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kAccent, width: 1.8),
        ),
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  final T? value;
  final String? hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      hint: hint != null
          ? Text(hint!, style: const TextStyle(color: _kTextMuted, fontSize: 13))
          : null,
      items: items,
      onChanged: onChanged,
      decoration: InputDecoration(
        filled: true,
        fillColor: _kSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBorder, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBorder, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kAccent, width: 1.8),
        ),
      ),
    );
  }
}

class _UploadBox extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool uploading;
  final bool uploaded;
  final VoidCallback? onTap;
  const _UploadBox({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.uploading,
    required this.uploaded,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        decoration: BoxDecoration(
          color: uploaded ? _kSuccessLight : _kSurface,
          border: Border.all(
            color: uploaded ? _kSuccess : _kBorder,
            width: 1.4,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            if (uploading)
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: _kAccent),
              )
            else
              Icon(
                uploaded ? Icons.check_circle_rounded : icon,
                color: uploaded ? _kSuccess : _kAccent,
                size: 32,
              ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: uploaded ? _kSuccess : _kTextPrimary,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: _kTextMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MiniTag({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _kAccentLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: _kAccentDark),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: _kAccentDark)),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: _kTextMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: _kTextMuted, height: 1.5),
          ),
        ),
      ],
    );
  }
}

class _AnySkillInBriefCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kAccentLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kAccent.withValues(alpha: 0.3)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('AnySkill בקיצור',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: _kAccentDark)),
          SizedBox(height: 10),
          _BriefBullet(
            emoji: '🔒',
            title: 'הכסף שלך בטוח:',
            body: 'ברגע שלקוח מבצע הזמנה, התשלום נכנס לנאמנות. בסיום השירות ואישור הלקוח — הכסף מועבר אליך.',
          ),
          SizedBox(height: 8),
          _BriefBullet(
            emoji: '🤝',
            title: 'תיווך בלבד:',
            body: 'AnySkill מחברת בינך לבין הלקוח. האחריות המקצועית על ביצוע העבודה היא שלך.',
          ),
          SizedBox(height: 8),
          _BriefBullet(
            emoji: '📋',
            title: 'מדיניות ביטולים:',
            body: 'הגדירו מדיניות ביטולים ברורה בפרופיל שלכם — הלקוחות רואים אותה לפני ההזמנה.',
          ),
          SizedBox(height: 8),
          _BriefBullet(
            emoji: '💰',
            title: 'העברות מהירות:',
            body: 'לאחר אישור סיום השירות, התשלום מועבר ישירות לחשבון הבנק שלכם.',
          ),
        ],
      ),
    );
  }
}

class _BriefBullet extends StatelessWidget {
  final String emoji;
  final String title;
  final String body;
  const _BriefBullet({required this.emoji, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                  fontSize: 12, color: _kTextPrimary, height: 1.5),
              children: [
                TextSpan(
                    text: '$title ',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                TextSpan(text: body),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ScrollHint extends StatelessWidget {
  const _ScrollHint();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Icon(Icons.keyboard_double_arrow_down_rounded,
            size: 16, color: _kAccent),
        SizedBox(width: 6),
        Text('גללו למטה כדי לקרוא את כל התנאים',
            style: TextStyle(
                fontSize: 11, color: _kAccent, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _TermsContent extends StatelessWidget {
  const _TermsContent();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TermsH('תנאי שימוש מלאים — AnySkill (גרסה 2.0)'),
        _TermsP('בלחיצה על אישור, אתה מסכים לתנאי השימוש', muted: true, center: true),
        SizedBox(height: 10),

        _TermsBold('1. מהי AnySkill?'),
        _TermsP('AnySkill היא פלטפורמת תיווך דיגיטלית ("הפלטפורמה") המאפשרת חיבור בין לקוחות לבין נותני שירות מקצועיים ("ספקים") בתחומים שונים. AnySkill מספקת תשתית טכנולוגית בלבד — לרבות מנגנון חיפוש, מערכת תשלומי נאמנות (Escrow), מערכת הודעות, ומנגנון דירוג.'),
        _TermsP('גישה לפלטפורמה ושימוש בה כפופים להסכמה מלאה לכל הסעיפים שלהלן. שימוש ראשון מהווה הסכמה מחייבת. גיל מינימום לשימוש: 18.'),

        _TermsBold('2. סטטוס ספקים — קבלן עצמאי'),
        _TermsP('AnySkill אינה מעסיקה את הספקים בכל אופן שהוא. הספקים הם קבלנים עצמאיים הפועלים על אחריותם הבלעדית.'),
        _TermsP('בין AnySkill לספק לא מתקיימים יחסי עובד-מעביד, שליחות, שותפות, או כל מסגרת אחרת המקימה אחריות של AnySkill כלפי צד שלישי בשל מעשי הספק.'),
        _TermsP('הספק אחראי באופן בלעדי ל:'),
        _TermsP('• כלים, ציוד, חומרים ורישיונות מקצועיים הנדרשים לביצוע השירות.'),
        _TermsP('• ביטוח צד שלישי, ביטוח אחריות מקצועית, וביטוח בריאות.'),
        _TermsP('• זכויות סוציאליות, פנסיה, דמי אבטלה — AnySkill אינה נושאת בכל אלה.'),
        _TermsP('• עמידה בכל חוק, תקן, ורגולציה החלים על מקצועו.'),
        _TermsP('AnySkill שומרת לעצמה את הזכות להשעות או לסיים חשבון ספק שנפגעה אמינותו, ללא יצירת יחסי עבודה.'),

        _TermsBold('3. מודל תשלום — נאמנות (Escrow)'),
        _TermsP('AnySkill פועלת כ"נאמן" (Trustee) על כספי העסקה בלבד. היא אינה בעלים של הכסף ואינה מרוויחה ממנו ריבית.'),
        _TermsP('זרימת הכספים:'),
        _TermsP('• עם אישור ההזמנה, הלקוח מעביר את סכום העסקה המלא לחשבון הנאמנות של AnySkill.'),
        _TermsP('• הכסף מוקפא ואינו מועבר לספק עד להשלמת אחד מהתנאים הבאים:'),
        _TermsP('(א) הלקוח אישר ידנית "שחרור תשלום" לאחר השלמת השירות.'),
        _TermsP('(ב) חלפו 72 שעות ממועד סימון "הושלם" על ידי הספק ללא פעולה מצד הלקוח — השחרור יתבצע אוטומטית (אלא אם נפתחה מחלוקת).'),
        _TermsP('(ג) צוות AnySkill הוציא החלטת בוררות המורה על שחרור.'),
        _TermsP('AnySkill תנכה את עמלת השירות מהסכום המועבר לספק. הלקוח לא יחויב בסכום נוסף מעבר למה שאושר בהזמנה.'),

        _TermsBold('4. עמלות ודמי שירות'),
        _TermsP('AnySkill גובה עמלת שירות מסכום כל עסקה מוצלחת. שיעור העמלה המעודכן מוצג בהגדרות האפליקציה ובדף האישור לפני כל תשלום.'),
        _TermsP('• העמלה מנוכה אוטומטית מהסכום המועבר לספק — הלקוח לא מחויב בנפרד.'),
        _TermsP('• AnySkill רשאית לשנות את שיעור העמלה בהתראה של 14 ימים מראש.'),
        _TermsP('• עסקאות שבוטלו לפני תחילת השירות יזוכו במלואן ללקוח ללא ניכוי עמלה.'),

        _TermsBold('5. מדיניות ביטולים'),
        _TermsP('כל ספק קובע את מדיניות הביטול שלו בעת פתיחת הפרופיל. שלושה מסלולים אפשריים:'),
        _TermsP('🟢 גמישה — ביטול חינם עד 4 שעות לפני המפגש. ביטול מאוחר: קנס 50% לספק.'),
        _TermsP('🟡 בינונית — ביטול חינם עד 24 שעות לפני. ביטול מאוחר: קנס 50%.'),
        _TermsP('🔴 קפדנית — ביטול חינם עד 48 שעות לפני. ביטול מאוחר: קנס 100%.'),
        _TermsP('ביטול מצד הספק — ללא קשר למועד — מזכה את הלקוח בהחזר מלא של 100%.'),
        _TermsP('קנס הביטול מועבר לספק בניכוי עמלת AnySkill הרגילה.'),
        _TermsP('חלון הביטול המדויק מוצג בסיכום ההזמנה לפני האישור הסופי.'),

        _TermsBold('6. ציות מס ואחריות פיסקלית'),
        _TermsP('הספק הוא האחראי הבלעדי לדיווח ותשלום כל מס, היטל, וכל חיוב חוקי אחר הנובע מהכנסותיו דרך הפלטפורמה. AnySkill אינה גורמת מנכה-מס-במקור ואינה אחראית להגשת כל דיווח מס עבור הספק.'),
        _TermsP('חובות הספק:'),
        _TermsP('• בעל עסק מורשה / חברה בע"מ: להוציא חשבונית מס כדין ללקוח ו/או ל-AnySkill בגין כל עסקה, בהתאם לחובות חוק מע"מ.'),
        _TermsP('• עוסק פטור: להוציא קבלה כדין ולציין סטטוס עוסק פטור.'),
        _TermsP('• פרילנסר ששכרו מגיע לסף חייב ברישום: מחובתו להירשם ברשויות המס.'),
        _TermsP('• ספקים המשתמשים בשירותי הפקת חשבוניות דרך צד שלישי מורשה אחראים לוודא כי השירות עומד בדרישות פקיד שומה.'),
        _TermsP('AnySkill שומרת לעצמה הזכות להשעות משיכת כספים אם יש חשש לאי-ציות לחובות הדיווח.'),

        _TermsBold('7. אחריות משתמשים והתנהגות אסורה'),
        _TermsP('כל משתמש (לקוח וספק כאחד) מתחייב:'),
        _TermsP('• לספק מידע אמיתי, מדויק ועדכני בעת הרישום ובמהלך השימוש.'),
        _TermsP('• לנהוג בכבוד, ביושר ובהגינות כלפי כל משתמש אחר בפלטפורמה.'),
        _TermsP('• שלא לבצע עסקאות מחוץ לפלטפורמה כדי לעקוף עמלת AnySkill.'),
        _TermsP('שימושים אסורים:'),
        _TermsP('• הטרדה, איומים, שפה פוגענית או גזענית, ציוד מיני.'),
        _TermsP('• פרסום שירותים בלתי חוקיים, מזויפים, או מטעים.'),
        _TermsP('• העלאת תוכן הפוגע בזכויות יוצרים של צד שלישי.'),
        _TermsP('• ניסיון לפרוץ, לסרוק, לסרוק לפגיעויות, או לשבש את הפלטפורמה.'),
        _TermsP('• יצירת חשבונות כפולים לצורך הטיה בדירוגים.'),
        _TermsP('הפרה של כל אחד מהאמור לעיל עלולה לגרור השעיה מיידית ו/או הפניה לרשויות אכיפת החוק.'),

        _TermsBold('8. אבטחת חשבון ואחריות אישית'),
        _TermsP('המשתמש אחראי באופן מלא לשמירת סיסמתו ופרטי הגישה לחשבונו.'),
        _TermsP('• חל איסור מוחלט להעביר גישה לחשבון לאדם אחר.'),
        _TermsP('• כל פעולה שתתבצע מתוך חשבון המשתמש תיחשב כפעולה שבוצעה על ידיו, אלא אם דיווח על גישה לא מורשית בתוך 24 שעות.'),
        _TermsP('• AnySkill ממליצה להפעיל אימות דו-שלבי (2FA) ולהשתמש בסיסמה חזקה ייחודית.'),
        _TermsP('• במקרה של חשד לפריצה לחשבון יש לפנות מיידית לתמיכה ב-support@anyskill.app.'),
        _TermsP('AnySkill תחסום חשבון חשוד בפעילות בלתי מורשית ותחקור. AnySkill לא תישא באחריות להפסדים שנגרמו כתוצאה מגישה לא מורשית שנבעה מרשלנות המשתמש.'),

        _TermsBold('9. הגבלת אחריות'),
        _TermsP('AnySkill מספקת פלטפורמה טכנולוגית בלבד ואינה צד לחוזה השירות בין הלקוח לבין הספק. בהתאם, AnySkill לא תישא בכל אחריות ל:'),
        _TermsP('• איכות, בטיחות, חוקיות, או תוצאות של שירות שסיפק ספק.'),
        _TermsP('• נזק גוף, נזק לרכוש, או כל נזק אחר שנגרם ללקוח על ידי ספק.'),
        _TermsP('• אובדן הכנסה, אובדן נתונים, נזק עקיף או תוצאתי מכל סיבה שהיא.'),
        _TermsP('• הפסקות שירות, תקלות טכניות, עיכובים, או שגיאות בפלטפורמה.'),
        _TermsP('• מידע שגוי שסיפק משתמש בפרופיל, בהזמנה, או בצ\'אט.'),
        _TermsP('בכל מקרה, האחריות הכוללת של AnySkill כלפי כל משתמש לא תעלה על הסכום הכולל ששילם אותו משתמש ל-AnySkill בשלושת החודשים שקדמו לאירוע הנזק.'),
        _TermsP('הגבלה זו חלה במידה המרבית המותרת על פי הדין החל בישראל.'),

        _TermsBold('10. יישוב מחלוקות ובוררות'),
        _TermsP('מחלוקת בין משתמשים תטופל בשלבים הבאים:'),
        _TermsP('(א) פנייה ישירה — הצדדים מעודדים לנסות ליישב את המחלוקת ביניהם דרך מערכת הצ\'אט בתוך 24 שעות.'),
        _TermsP('(ב) בקשת בוררות — אם לא הושגה הסכמה, כל צד רשאי לפתוח "בקשת בוררות" דרך האפליקציה. הכספים ימשיכו להיות מוחזקים בנאמנות עד לפתרון.'),
        _TermsP('(ג) סקירת AnySkill — צוות ה-Trust & Safety יבחן ראיות (הודעות, צילומי מסך, תיאורים) ויוציא החלטה תוך 48 שעות עסקים.'),
        _TermsP('(ד) אפשרויות ההחלטה:'),
        _TermsP('• החזר מלא ללקוח.'),
        _TermsP('• שחרור מלא לספק.'),
        _TermsP('• פשרה יחסית לפי שיקול דעת הצוות.'),
        _TermsP('החלטת הצוות סופית בתוך מסגרת הפלטפורמה. הצדדים שומרים על זכותם לפנות לערכאות משפטיות חיצוניות.'),

        _TermsBold('11. קניין רוחני'),
        _TermsP('כל הזכויות בפלטפורמה AnySkill — לרבות קוד, עיצוב, לוגו, שם המותג, וחוויית המשתמש — שייכות ל-AnySkill בלבד.'),
        _TermsP('• המשתמש מקבל רישיון שימוש אישי, מוגבל, ולא-ייחודי לגישה לפלטפורמה.'),
        _TermsP('• אין להעתיק, לשכפל, לפרסם מחדש, לבצע הנדסה לאחור, או ליצור יצירות נגזרות מהפלטפורמה.'),
        _TermsP('• תוכן שהמשתמש מעלה לפלטפורמה (תמונות, ביקורות, פרופיל) מעניק ל-AnySkill רישיון להציגו בתוך הפלטפורמה.'),

        _TermsH('12. מדיניות פרטיות'),
        _TermsP('AnySkill אוספת ומעבדת מידע אישי הנדרש לתפעול השירות:'),
        _TermsP('• מידע זיהוי: שם, אימייל, מספר טלפון, תמונה.'),
        _TermsP('• מידע פיננסי: גרסה מוצפנת של פרטי תשלום בתקן PCI DSS. AnySkill לא שומרת מספרי כרטיסי אשראי שלמים על שרתיה.'),
        _TermsP('• מידע שימוש: היסטוריית הזמנות, עסקאות, שיחות תמיכה.'),
        _TermsP('• מידע מיקום: משוער, לצורך תצוגת ספקים בקרבת מקום.'),
        _TermsP('עקרונות שימוש:'),
        _TermsP('• AnySkill לא תמכור, תשכיר, או תעביר מידע אישי לצדדים שלישיים למטרות שיווק.'),
        _TermsP('• שיתוף מוגבל עם שותפים טכנולוגיים (Firebase / Google) כחלק מתפעול השירות, בכפוף לתנאי הפרטיות שלהם.'),
        _TermsP('• המשתמש רשאי לבקש עיון, תיקון, או מחיקת מידע אישי בפנייה ל-support@anyskill.app. מחיקת חשבון תתבצע תוך 30 יום ממועד הבקשה.'),

        _TermsBold('13. שינויים בתנאים'),
        _TermsP('AnySkill שומרת לעצמה הזכות לעדכן תנאים אלה בכל עת. שינויים מהותיים יימסרו בהודעה דחיפה (Push) ו/או בבאנר באפליקציה לפחות 14 ימים לפני כניסתם לתוקף.'),
        _TermsP('המשך שימוש בפלטפורמה לאחר מועד כניסת השינויים לתוקף מהווה הסכמה מלאה ובלתי חוזרת לתנאים המעודכנים. גרסה ארכיונית של כל עדכון שמורה וזמינה לעיון לפי בקשה.'),

        _TermsBold('14. דין חל ושיפוט'),
        _TermsP('הסכם זה כפוף לדיני מדינת ישראל.'),
        _TermsP('כל מחלוקת משפטית שלא הוכרעה דרך מנגנון הבוררות הפנימי תובא בפני בתי המשפט המוסמכים במחוז תל אביב בלבד, והצדדים מקבלים עליהם את סמכות השיפוט הייחודית של בתי משפט אלה.'),
        _TermsP('ויתור של AnySkill על הפעלת זכות מסוימת לא ייחשב כוויתור גורף. אם ייקבע שסעיף כלשהו בהסכם זה אינו אכיף, יתר הסעיפים יישארו בתוקף מלא.'),
        SizedBox(height: 14),
        _TermsP('© AnySkill 2026. כל הזכויות שמורות.\nsupport@anyskill.app',
            muted: true, center: true),
      ],
    );
  }
}

class _TermsH extends StatelessWidget {
  final String text;
  const _TermsH(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 6),
      child: Text(
        text,
        style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w800, color: _kAccentDark),
      ),
    );
  }
}

class _TermsBold extends StatelessWidget {
  final String text;
  const _TermsBold(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
            fontSize: 12.5, fontWeight: FontWeight.w800, color: _kTextPrimary),
      ),
    );
  }
}

class _TermsP extends StatelessWidget {
  final String text;
  final bool muted;
  final bool center;
  const _TermsP(this.text, {this.muted = false, this.center = false});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        textAlign: center ? TextAlign.center : TextAlign.start,
        style: TextStyle(
          fontSize: 11.5,
          height: 1.6,
          color: muted ? _kTextMuted : _kTextSecondary,
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//                           Confirmation Screen
// ────────────────────────────────────────────────────────────────────────────

class _ConfirmationScreen extends StatelessWidget {
  const _ConfirmationScreen();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _kBg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: _kSuccessLight,
                    shape: BoxShape.circle,
                    border: Border.all(color: _kSuccess, width: 3),
                  ),
                  child: const Icon(Icons.check_rounded,
                      size: 56, color: _kSuccess),
                ),
                const SizedBox(height: 28),
                const Text(
                  'קיבלנו את בקשת ההצטרפות שלכם!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _kTextPrimary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'צוות AnySkill עובר על הפרטים ויאשר את הפרופיל שלכם בקרוב.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: _kTextSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'תודה שבחרתם להצטרף ל-AnySkill! 🎉',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _kAccentDark,
                    height: 1.5,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context)
                        .popUntil((r) => r.isFirst),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    child: const Text('חזרה לדף הבית'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
