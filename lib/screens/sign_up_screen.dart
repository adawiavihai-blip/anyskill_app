import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import '../constants.dart';
import '../l10n/app_localizations.dart';
import '../widgets/anyskill_logo.dart';
import '../services/category_ai_service.dart';
import 'terms_of_service_screen.dart';

// ── Brand tokens ──────────────────────────────────────────────────────────────
const _kPurple      = Color(0xFF6366F1);
const _kPurpleDark  = Color(0xFF4F46E5);
const _kPurpleLight = Color(0xFF8B5CF6);
const _kGreen       = Color(0xFF10B981);
const _kRed         = Color(0xFFEF4444);

// ── User type enum ────────────────────────────────────────────────────────────
enum UserRole { customer, expert }

// ─────────────────────────────────────────────────────────────────────────────
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen>
    with SingleTickerProviderStateMixin {
  // ── Form ────────────────────────────────────────────────────────────────────
  final _formKey    = GlobalKey<FormState>();
  final _nameCtrl   = TextEditingController();
  final _emailCtrl  = TextEditingController();
  final _passCtrl   = TextEditingController();
  final _phoneCtrl  = TextEditingController();

  // ── State ───────────────────────────────────────────────────────────────────
  UserRole  _currentRole  = UserRole.customer;
  bool      _obscurePass  = true;
  bool      _termsOk      = false;
  bool      _isLoading    = false;
  String    _category    = 'אחר';
  String?   _subCategory; // display name — set by AI, passed to finalizeSetup on submit

  // Expert-only fields
  String?          _businessType;
  final            _descCtrl = TextEditingController(); // free-text occupation
  bool             _isClassifying = false;
  CategoryResult?  _aiResult;

  // ID / Passport image
  Uint8List?  _idImageBytes;  // raw bytes (web + mobile)
  String?     _idImageName;   // original filename for display

  // Submit loading overlay
  String  _loadingStepMsg = '';

  // Live validation (null = untouched, true = valid, false = invalid)
  bool? _nameOk;
  bool? _emailOk;
  bool? _phoneOk;
  bool? _passOk;
  int   _passStrength = 0; // 0–4

  // ── Validation-error tracking ─────────────────────────────────────────────
  // Set by each validator on failure so _signUp can log which field stopped
  // the user to the abandoned-registrations funnel in Firestore.
  String? _lastFailedField;

  // Type-toggle animation
  late final AnimationController _toggleCtrl;

  // ── Abandoned-lead tracking ───────────────────────────────────────────────
  // A random session ID identifies this attempt in incomplete_registrations.
  // Partial data is saved 2 s after the user stops typing (debounced).
  final String _sessionId =
      '${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(99999)}';
  bool  _partialDocCreated = false;
  Timer? _partialSaveTimer;

  // ── Funnel step tracking ──────────────────────────────────────────────────
  // One-shot flags prevent duplicate events per session.
  bool _loggedStep2 = false; // name first typed
  bool _loggedStep3 = false; // email first typed
  bool _loggedStep4 = false; // submit attempted
  bool _loggedStep5 = false; // registration completed

  static const _kStepLabels = <String, String>{
    'reg_step_1': 'פתח מסך הרשמה',
    'reg_step_2': 'התחיל למלא שם',
    'reg_step_3': 'הזין כתובת אימייל',
    'reg_step_4': 'לחץ כפתור הרשמה',
    'reg_step_5': 'הרשמה הושלמה בהצלחה',
  };

  Future<void> _logRegStep(String step) async {
    try {
      await FirebaseFirestore.instance.collection('activity_log').add({
        'type':      step,
        'sessionId': _sessionId,
        'role':      _currentRole == UserRole.expert ? 'expert' : 'customer',
        'createdAt': FieldValue.serverTimestamp(),
        'title':     _kStepLabels[step] ?? step,
        'detail':    '',
        'priority':  'normal',
      });
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _toggleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    // Attach debounced listeners for funnel tracking
    _nameCtrl.addListener(_onPartialChange);
    _emailCtrl.addListener(_onPartialChange);
    _phoneCtrl.addListener(_onPartialChange);
    // Step 1: user opened the sign-up screen
    _logRegStep('reg_step_1');
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_onPartialChange);
    _emailCtrl.removeListener(_onPartialChange);
    _phoneCtrl.removeListener(_onPartialChange);
    _partialSaveTimer?.cancel();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _phoneCtrl.dispose();
    _descCtrl.dispose();
    _toggleCtrl.dispose();
    super.dispose();
  }

  // ── Partial-registration persistence ─────────────────────────────────────

  void _onPartialChange() {
    _partialSaveTimer?.cancel();
    _partialSaveTimer =
        Timer(const Duration(seconds: 2), _savePartialRegistration);
    // Step 2: first time a name is typed
    if (!_loggedStep2 && _nameCtrl.text.trim().isNotEmpty) {
      _loggedStep2 = true;
      _logRegStep('reg_step_2');
    }
    // Step 3: first time an email is typed
    if (!_loggedStep3 && _emailCtrl.text.trim().isNotEmpty) {
      _loggedStep3 = true;
      _logRegStep('reg_step_3');
    }
  }

  Future<void> _savePartialRegistration() async {
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.isEmpty && email.isEmpty && phone.isEmpty) return;

    // Determine which funnel step the user has reached
    String lastField = 'name';
    if (phone.isNotEmpty) {
      lastField = 'phone';
    } else if (email.isNotEmpty) {
      lastField = 'email';
    }

    final data = <String, dynamic>{
      if (name.isNotEmpty)  'name':  name,
      if (email.isNotEmpty) 'email': email,
      if (phone.isNotEmpty) 'phone': phone,
      'role':                 _currentRole == UserRole.expert ? 'expert' : 'customer',
      'lastField':            lastField,
      'isRegistrationComplete': false,
      'lastUpdatedAt':        FieldValue.serverTimestamp(),
      // startedAt only written on first create to preserve the original timestamp
      if (!_partialDocCreated) 'startedAt': FieldValue.serverTimestamp(),
    };

    await FirebaseFirestore.instance
        .collection('incomplete_registrations')
        .doc(_sessionId)
        .set(data, SetOptions(merge: true))
        .catchError((_) {}); // non-fatal — analytics must never block UX
    _partialDocCreated = true;
  }

  /// Called after form.validate() returns false.
  /// Records which field blocked the user so the admin funnel can show it.
  Future<void> _trackValidationFail(String field) async {
    FirebaseFirestore.instance
        .collection('incomplete_registrations')
        .doc(_sessionId)
        .set({
          'lastField':            field,
          'lastValidationError':  field,
          'isRegistrationComplete': false,
          'lastUpdatedAt':        FieldValue.serverTimestamp(),
          if (!_partialDocCreated) 'startedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true))
        .catchError((_) {});
    _partialDocCreated = true;
  }

  // ── Validation helpers ───────────────────────────────────────────────────────
  static bool _emailValid(String v) =>
      RegExp(r'^[\w\.\+\-]+@[\w\-]+\.[a-z]{2,}$', caseSensitive: false)
          .hasMatch(v.trim());

  /// Israeli phone: 10 digits starting with 0 (e.g. 0501234567),
  /// or 12 digits starting with 972 (international format).
  static bool _phoneValid(String v) {
    final digits = v.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10 && digits.startsWith('0')) return true;
    if (digits.length == 12 && digits.startsWith('972')) return true;
    return false;
  }

  /// Returns true when [v] contains at least two whitespace-separated words
  /// each with at least one character — enforces first + last name.
  static bool _fullNameValid(String v) {
    final parts = v.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return parts.length >= 2;
  }

  int _calcStrength(String p) {
    int s = 0;
    if (p.length >= 8)                          s++;
    if (RegExp(r'[A-Z]').hasMatch(p))           s++;
    if (RegExp(r'[0-9]').hasMatch(p))           s++;
    if (RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(p)) s++;
    return s;
  }

  // ── ID image picker ───────────────────────────────────────────────────────
  Future<void> _pickIdImage(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _idImageBytes = bytes;
        _idImageName  = picked.name;
      });
    } catch (e) {
      if (!mounted) return;
      _snack('לא ניתן לטעון את התמונה: $e', _kRed);
    }
  }

  void _showIdSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: _kPurple),
              title: const Text('צלם את המסמך'),
              onTap: () { Navigator.pop(context); _pickIdImage(ImageSource.camera); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: _kPurple),
              title: const Text('בחר מהגלריה'),
              onTap: () { Navigator.pop(context); _pickIdImage(ImageSource.gallery); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Uploads _idImageBytes to Storage and returns the download URL.
  /// Must be called AFTER the user is authenticated (within _signUp flow).
  Future<String?> _uploadIdImage(String uid) async {
    if (_idImageBytes == null) return null;
    try {
      final ext = (_idImageName ?? 'id.jpg').split('.').last.toLowerCase();
      final ref = FirebaseStorage.instance
          .ref('id_verifications/$uid/id_document.$ext');
      final meta = SettableMetadata(
        contentType: 'image/${ext == 'jpg' ? 'jpeg' : ext}',
        customMetadata: {'uploadedBy': uid, 'purpose': 'id_verification'},
      );
      await ref.putData(_idImageBytes!, meta);
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('ID upload failed (non-fatal): $e');
      return null; // upload failure doesn't block account creation
    }
  }

  // _ensureCategoryIds removed — replaced by CategoryAiService.finalizeSetup()
  // which is called after user creation in _signUp.

  // ── Sign-up logic ─────────────────────────────────────────────────────────
  Future<void> _signUp() async {
    // Reset per-run tracker so validators can record the first blocking field
    _lastFailedField = null;
    if (!(_formKey.currentState?.validate() ?? false)) {
      // Log which field caused validation failure to the funnel analytics
      _trackValidationFail(_lastFailedField ?? 'unknown');
      return;
    }

    final l10n = AppLocalizations.of(context);

    if (!_termsOk) {
      _snack(l10n.signupTosMustAgree, Colors.orange);
      return;
    }

    // Guard: don't submit while AI is still running — _aiResult would be null
    if (_isClassifying) {
      _snack('המתן לסיום הסיווג לפני יצירת הפרופיל', Colors.orange);
      return;
    }

    // Step 4: user pressed submit
    if (!_loggedStep4) {
      _loggedStep4 = true;
      _logRegStep('reg_step_4');
    }

    setState(() { _isLoading = true; _loadingStepMsg = 'יוצר חשבון...'; });
    final nav  = Navigator.of(context);
    final msg  = ScaffoldMessenger.of(context);

    // Capture l10n strings before any await (context may not be safe after)
    final strAccountCreated   = l10n.signupAccountCreated;
    final strEmailInUse       = l10n.signupEmailInUse;
    final strInvalidEmail     = l10n.errorInvalidEmail;
    final strWeakPassword     = l10n.signupWeakPassword;
    final strNetworkError     = l10n.signupNetworkError;
    final strGenericError     = l10n.signupGenericError;
    final strNewProviderBio   = l10n.signupNewProviderBio;
    final strNewCustomerBio   = l10n.signupNewCustomerBio;

    try {
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailCtrl.text.trim(),
            password: _passCtrl.text.trim(),
          );

      final uid        = cred.user!.uid;
      final isProvider = _currentRole == UserRole.expert;

      // Upload ID image (if provided) — show step label in overlay
      if (isProvider && _idImageBytes != null) {
        if (mounted) setState(() => _loadingStepMsg = 'מעלה מסמך זהות...');
      }
      final idImageUrl = isProvider ? await _uploadIdImage(uid) : null;

      // Step 1: Create the user doc (without category IDs — those come from finalizecategorysetup)
      if (mounted) setState(() => _loadingStepMsg = 'שומר פרופיל...');
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'uid':              uid,
        'name':             _nameCtrl.text.trim(),
        'email':            _emailCtrl.text.trim(),
        'phone':            _phoneCtrl.text.trim(),
        'balance':          0.0,
        'rating':           5.0,
        'reviewsCount':     0,
        'pricePerHour':     isProvider ? 100.0 : 0.0,
        'serviceType':      isProvider ? _category : '',
        if (isProvider && _subCategory != null) 'subCategoryName': _subCategory,
        'aboutMe':          isProvider && _descCtrl.text.trim().isNotEmpty
            ? _descCtrl.text.trim()
            : (isProvider ? strNewProviderBio : strNewCustomerBio),
        if (isProvider && _businessType != null) 'businessType': _businessType,
        if (isProvider && idImageUrl != null) ...{
          'idVerificationUrl':    idImageUrl,
          'idVerificationStatus': 'pending',
        },
        'profileImage':     '',
        'gallery':          [],
        'quickTags':        [],
        'isOnline':         true,
        'isAdmin':          false,
        'isVerified':       false,
        'isCustomer':       !isProvider,
        'isProvider':       isProvider,
        // ── ToS consent trail ──────────────────────────────────────────────
        'tos_agreed':       true,
        'tos_version':      '2.0',
        'tos_agreed_at':    FieldValue.serverTimestamp(),
        'onboardingComplete': false,
        'tourComplete':     false,
        'createdAt':        FieldValue.serverTimestamp(),
      });

      // Step 2: Create/find category + subcategory, update user doc, admin log + email.
      // Called AFTER auth + user doc exist (Cloud Function needs both to exist).
      // Isolated in its own try/catch — a category error must NOT undo account creation.
      if (isProvider && _aiResult != null) {
        if (mounted) setState(() => _loadingStepMsg = 'מגדיר קטגוריה...');
        try {
          await CategoryAiService.finalizeSetup(
            categoryName:       _category,
            subCategoryName:    _subCategory,
            matchedCategoryId:  _aiResult!.action == CategoryAction.match
                ? _aiResult!.categoryId
                : null,
            serviceDescription: _descCtrl.text.trim(),
            confidence:         _aiResult!.confidence,
            reasoning:          _aiResult!.reasoning,
          );
        } on CategoryAiException catch (e) {
          // Non-fatal: account is created. Category can be fixed later in profile.
          debugPrint('finalizeSetup warning (non-fatal): $e');
        }
      }

      // Mark the partial-registration doc as completed so it no longer
      // appears in the abandoned-leads list.
      if (_partialDocCreated) {
        FirebaseFirestore.instance
            .collection('incomplete_registrations')
            .doc(_sessionId)
            .set({
              'isRegistrationComplete': true,
              'completedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true))
            .catchError((_) {});
      }

      // Step 5: registration completed
      if (!_loggedStep5) {
        _loggedStep5 = true;
        _logRegStep('reg_step_5');
      }

      if (mounted) {
        nav.pop();
        msg.showSnackBar(SnackBar(
          backgroundColor: _kGreen,
          content: Text(strAccountCreated),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ));
      }
    } on FirebaseAuthException catch (e) {
      final errs = {
        'email-already-in-use':   strEmailInUse,
        'invalid-email':          strInvalidEmail,
        'weak-password':          strWeakPassword,
        'network-request-failed': strNetworkError,
      };
      _snack(errs[e.code] ?? strGenericError, _kRed);
    } catch (_) {
      // Firestore set() or other unexpected failure
      _snack(strGenericError, _kRed);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Social auth stubs (add google_sign_in + sign_in_with_apple packages) ──
  Future<void> _signInGoogle() async {
    setState(() => _isLoading = true);
    final nav = Navigator.of(context);
    final msg = ScaffoldMessenger.of(context);

    // Capture l10n strings before any await (context may not be safe after)
    final l10n = AppLocalizations.of(context);
    final strAccountCreated = l10n.signupAccountCreated;
    final strNewProviderBio = l10n.signupNewProviderBio;
    final strNewCustomerBio = l10n.signupNewCustomerBio;
    final strGoogleError    = l10n.signupGoogleError;

    try {
      UserCredential cred;
      if (kIsWeb) {
        cred = await FirebaseAuth.instance
            .signInWithPopup(GoogleAuthProvider());
      } else {
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) return; // user cancelled
        final googleAuth = await googleUser.authentication;
        cred = await FirebaseAuth.instance.signInWithCredential(
          GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          ),
        );
      }

      final user    = cred.user!;
      final isNew   = cred.additionalUserInfo?.isNewUser ?? false;
      final isProvider = _currentRole == UserRole.expert;

      if (isNew) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'uid':              user.uid,
          'name':             user.displayName ?? '',
          'email':            user.email ?? '',
          'phone':            '',
          'balance':          0.0,
          'rating':           5.0,
          'reviewsCount':     0,
          'pricePerHour':     isProvider ? 100.0 : 0.0,
          'serviceType':      isProvider ? _category : '',
          if (isProvider && _subCategory != null) 'subCategoryName': _subCategory,
          'aboutMe':          isProvider ? strNewProviderBio : strNewCustomerBio,
          'profileImage':     user.photoURL ?? '',
          'gallery':          [],
          'quickTags':        [],
          'isOnline':         true,
          'isAdmin':          false,
          'isVerified':       false,
          'isCustomer':       !isProvider,
          'isProvider':       isProvider,
          // ── ToS consent trail ────────────────────────────────────────────
          'tos_agreed':       true,
          'tos_version':      '2.0',
          'tos_agreed_at':    FieldValue.serverTimestamp(),
          'onboardingComplete': false,
          'tourComplete':     false,
          'createdAt':        FieldValue.serverTimestamp(),
        });

        if (isProvider && _aiResult != null) {
          try {
            await CategoryAiService.finalizeSetup(
              categoryName:       _category,
              subCategoryName:    _subCategory,
              matchedCategoryId:  _aiResult!.action == CategoryAction.match
                  ? _aiResult!.categoryId
                  : null,
              serviceDescription: '',
              confidence:         _aiResult!.confidence,
              reasoning:          _aiResult!.reasoning,
            );
          } on CategoryAiException catch (e) {
            debugPrint('finalizeSetup warning (non-fatal): $e');
          }
        }
      }

      if (mounted) {
        nav.pop();
        msg.showSnackBar(SnackBar(
          backgroundColor: _kGreen,
          content: Text(isNew ? strAccountCreated : 'ברוכים השבים! 👋'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (_) {
      if (mounted) _snack(strGoogleError, _kRed);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInApple() async {
    _snack('התחברות עם Apple תהיה זמינה בקרוב', Colors.black87);
    // TODO: implement with sign_in_with_apple package
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _classifyWithAI() async {
    final text = _descCtrl.text.trim();
    if (text.length < 6) {
      _snack('תאר את השירות שלך בכמה מילים לפחות', Colors.orange);
      return;
    }
    setState(() { _isClassifying = true; _aiResult = null; });
    try {
      final result = await CategoryAiService.categorize(text);
      if (!mounted) return;
      setState(() {
        _aiResult        = result;
        _isClassifying   = false;
        if (result.categoryName != null) _category = result.categoryName!;
        _subCategory = result.subCategoryName;
      });
    } on CategoryAiException catch (e) {
      if (!mounted) return;
      setState(() => _isClassifying = false);
      // Show the detailed diagnostic message from the service layer.
      _snack(e.message, _kRed);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isClassifying = false);
      _snack('שגיאה לא צפויה: $e', _kRed);
    }
  }

  void _setType(UserRole t) {
    if (t == _currentRole) return;
    setState(() => _currentRole = t);
    t == UserRole.expert
        ? _toggleCtrl.forward()
        : _toggleCtrl.reverse();
  }

  Future<void> _showTerms() async {
    final accepted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const TermsOfServiceScreen(showAcceptButton: true),
      ),
    );
    // Auto-tick the checkbox if the user tapped "הבנתי ומסכים/ה"
    if (accepted == true && mounted) {
      setState(() => _termsOk = true);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _buildScaffold(),
        if (_isLoading) _buildLoadingOverlay(),
      ],
    );
  }

  Widget _buildScaffold() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FF),
      body: CustomScrollView(
        slivers: [
          // ── Hero ─────────────────────────────────────────────────────────────
          SliverToBoxAdapter(child: _buildHero()),

          // ── Form card ────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -28),
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
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Type toggle — two side-by-side cards
                      _buildTypeToggle(),
                      const SizedBox(height: 28),

                      // ── Full Name (mandatory — first + last) ─────────────
                      _buildField(
                        ctrl: _nameCtrl,
                        label: 'שם פרטי ומשפחה',
                        icon: Icons.person_outline_rounded,
                        isValid: _nameOk,
                        onChanged: (v) => setState(() =>
                            _nameOk = _fullNameValid(v)),
                        validator: (v) {
                          final val = (v ?? '').trim();
                          if (val.isEmpty) {
                            _lastFailedField ??= 'name';
                            return 'שדה זה הוא חובה';
                          }
                          if (!_fullNameValid(val)) {
                            _lastFailedField ??= 'name';
                            return 'נא להזין שם פרטי ושם משפחה';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // ── Phone (mandatory — Israeli format) ───────────────
                      _buildField(
                        ctrl: _phoneCtrl,
                        label: 'טלפון',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        isValid: _phoneOk,
                        onChanged: (v) => setState(() =>
                            _phoneOk = _phoneValid(v)),
                        validator: (v) {
                          final val = (v ?? '').trim();
                          if (val.isEmpty) {
                            _lastFailedField ??= 'phone';
                            return 'שדה זה הוא חובה';
                          }
                          if (!_phoneValid(val)) {
                            _lastFailedField ??= 'phone';
                            return 'מספר טלפון ישראלי לא תקין (10 ספרות)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // ── Email (mandatory) ─────────────────────────────────
                      _buildField(
                        ctrl: _emailCtrl,
                        label: 'כתובת אימייל',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        isValid: _emailOk,
                        onChanged: (v) => setState(() =>
                            _emailOk = _emailValid(v)),
                        validator: (v) {
                          final val = (v ?? '').trim();
                          if (val.isEmpty) {
                            _lastFailedField ??= 'email';
                            return 'שדה זה הוא חובה';
                          }
                          if (!_emailValid(val)) {
                            _lastFailedField ??= 'email';
                            return 'כתובת אימייל אינה תקינה';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // ── Password (mandatory — min 6 chars) ───────────────
                      _buildField(
                        ctrl: _passCtrl,
                        label: 'סיסמה (מינימום 6 תווים)',
                        icon: Icons.lock_outline_rounded,
                        obscure: _obscurePass,
                        isValid: _passOk,
                        suffix: IconButton(
                          icon: Icon(
                            _obscurePass
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                            color: Colors.grey[500],
                          ),
                          onPressed: () =>
                              setState(() => _obscurePass = !_obscurePass),
                        ),
                        onChanged: (v) => setState(() {
                          _passStrength = _calcStrength(v);
                          _passOk = v.length >= 6;
                        }),
                        validator: (v) {
                          if ((v ?? '').isEmpty) {
                            _lastFailedField ??= 'password';
                            return 'שדה זה הוא חובה';
                          }
                          if (v!.length < 6) {
                            _lastFailedField ??= 'password';
                            return 'הסיסמה חייבת להכיל לפחות 6 תווים';
                          }
                          return null;
                        },
                      ),
                      if (_passCtrl.text.isNotEmpty)
                        _buildStrengthBar(),
                      const SizedBox(height: 16),

                      // Expert-only fields — direct inline if block
                      if (_currentRole == UserRole.expert) ...[
                        // 0. Free-text occupation description
                        TextFormField(
                          controller: _descCtrl,
                          maxLines: 3,
                          textAlign: TextAlign.right,
                          textDirection: TextDirection.rtl,
                          decoration: InputDecoration(
                            labelText: 'תיאור העיסוק שלך',
                            hintText:
                                'לדוגמה: אני שרברב מוסמך עם 5 שנות ניסיון...',
                            hintStyle: TextStyle(
                                color: Colors.grey[400], fontSize: 13),
                            labelStyle: TextStyle(
                                color: Colors.grey[500], fontSize: 14),
                            prefixIcon: const Padding(
                              padding: EdgeInsets.only(bottom: 36),
                              child: Icon(Icons.edit_note_rounded,
                                  size: 20, color: _kPurple),
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF0F0FF),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: _kPurple, width: 1.2),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: _kPurple, width: 1.6),
                            ),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // AI classify button
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kPurple,
                              disabledBackgroundColor:
                                  _kPurple.withValues(alpha: 0.5),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed:
                                _isClassifying ? null : _classifyWithAI,
                            icon: _isClassifying
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white))
                                : const Icon(Icons.auto_awesome_rounded,
                                    color: Colors.white, size: 18),
                            label: Text(
                              _isClassifying
                                  ? 'מסווג...'
                                  : 'סווג קטגוריה עם AI',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14),
                            ),
                          ),
                        ),

                        // AI classification result — solid indigo card
                        if (_aiResult != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(children: [
                                  Icon(Icons.auto_awesome_rounded,
                                      size: 16, color: Colors.white),
                                  SizedBox(width: 6),
                                  Text('סיווג AI',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.white70,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.5)),
                                ]),
                                const SizedBox(height: 8),
                                Text(
                                  'סווגת לקטגוריה: ${_aiResult!.categoryName ?? ""}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Colors.white),
                                ),
                                if (_subCategory != null && _subCategory!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'ולתת-קטגוריה: $_subCategory',
                                      style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.white70),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),

                        // 1. Category picker (manual override)
                        _buildCategoryPicker(),
                        const SizedBox(height: 16),

                        // 2. Business type dropdown
                        DropdownButtonFormField<String>(
                          value: _businessType,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'סוג עסק',
                            labelStyle: TextStyle(
                                color: Colors.grey[500], fontSize: 14),
                            prefixIcon: const Icon(
                                Icons.business_center_outlined,
                                size: 20,
                                color: _kPurple),
                            filled: true,
                            fillColor: const Color(0xFFF0F0FF),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: _kPurple, width: 1.2),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: _kPurple, width: 1.6),
                            ),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          items: const [
                            'עוסק פטור',
                            'עוסק מורשה',
                            'חברה בע"מ',
                            'שכיר המוציא חשבונית דרך חברה חיצונית',
                          ]
                              .map((t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t,
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(fontSize: 14)),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _businessType = v),
                        ),
                        const SizedBox(height: 16),

                        // 3. ID / Passport upload
                        _buildIdUpload(),
                        const SizedBox(height: 16),
                      ],

                      // ── Social divider ──────────────────────────────────────
                      _buildSocialDivider(),
                      const SizedBox(height: 14),

                      // Google + Apple
                      Row(
                        children: [
                          Expanded(
                              child: _SocialButton(
                            label: 'Google',
                            icon: _googleIcon(),
                            onTap: _signInGoogle,
                            borderColor: Colors.grey.shade300,
                          )),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _SocialButton(
                            label: 'Apple',
                            icon: const Icon(Icons.apple, size: 22),
                            onTap: _signInApple,
                            dark: true,
                          )),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Quick Summary card
                      _buildQuickSummary(),
                      const SizedBox(height: 16),

                      // Terms
                      _buildTermsRow(),
                      const SizedBox(height: 24),

                      // Submit
                      _buildSubmitButton(),
                      const SizedBox(height: 16),

                      // Login link
                      Center(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: RichText(
                            text: TextSpan(
                              text: 'כבר יש לך חשבון? ',
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 14),
                              children: const [
                                TextSpan(
                                  text: 'כניסה כאן',
                                  style: TextStyle(
                                    color: _kPurple,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.underline,
                                    decorationColor: _kPurple,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
        ],
      ),
    );
  } // end _buildScaffold

  // ── Loading overlay ───────────────────────────────────────────────────────────
  Widget _buildLoadingOverlay() {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 44),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 32,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                    strokeWidth: 3.5, color: _kPurple),
              ),
              const SizedBox(height: 20),
              Text(
                _loadingStepMsg.isEmpty ? 'אנא המתן...' : _loadingStepMsg,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F1F33),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Hero section ─────────────────────────────────────────────────────────────
  Widget _buildHero() {
    return Container(
      height: 280,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [_kPurpleDark, _kPurple, _kPurpleLight],
        ),
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            top: -40, left: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: 30, right: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),

          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.arrow_forward_ios_rounded,
                  color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Content
          Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 20,
              right: 24, left: 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Logo — centered, dynamic size from admin branding control
                Center(
                  child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('system_settings')
                        .doc('global')
                        .snapshots(),
                    builder: (context, snap) {
                      final data = snap.data?.data() ?? {};
                      final size = (data['authLogoSize'] as num? ?? 110).toDouble();
                      return AnySkillBrandIcon(size: size);
                    },
                  ),
                ),
                const SizedBox(height: 8),
                // App name below logo
                const Center(
                  child: Text(
                    'AnySkill',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Slogan
                const Text(
                  'המומחים שחיפשת, במרחק קליק ✨',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),

                // Trust badges
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(
                    children: [
                      _TrustPill('🌟 4.9/5 דירוג'),
                      const SizedBox(width: 8),
                      _TrustPill('🔒 תשלום מאובטח'),
                      const SizedBox(width: 8),
                      _TrustPill('👥 10,000+ מקצוענים'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bottom wave
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: CustomPaint(
              size: const Size(double.infinity, 36),
              painter: _WavePainter(
                  color: const Color(0xFFF5F5FF)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Type toggle ───────────────────────────────────────────────────────────────
  Widget _buildTypeToggle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'אני מצטרף/ת כ...',
          textAlign: TextAlign.right,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500]),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            // Expert card (right in RTL = first in list)
            Expanded(
              child: _TypeButton(
                icon:     Icons.construction_rounded,
                label:    'נותן שירות',
                subtitle: 'מספק שירותים',
                selected: _currentRole == UserRole.expert,
                onTap:    () => _setType(UserRole.expert),
              ),
            ),
            const SizedBox(width: 10),
            // Customer card
            Expanded(
              child: _TypeButton(
                icon:     Icons.search_rounded,
                label:    'לקוח',
                subtitle: 'מחפש שירותים',
                selected: _currentRole == UserRole.customer,
                onTap:    () => _setType(UserRole.customer),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _currentRole == UserRole.expert
              ? _RoleHint(
                  key:  const ValueKey('provider'),
                  icon: Icons.trending_up_rounded,
                  text: 'קבלו הזמנות, נהלו לוח זמנים, והרוויחו יותר',
                )
              : _RoleHint(
                  key:  const ValueKey('customer'),
                  icon: Icons.bolt_rounded,
                  text: 'מצאו מומחים, הזמינו שירותים, ושלמו בבטחה',
                ),
        ),
      ],
    );
  }

  // ── Form field ────────────────────────────────────────────────────────────────
  Widget _buildField({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool? isValid,
    bool obscure = false,
    Widget? suffix,
    void Function(String)? onChanged,
    String? Function(String?)? validator,
  }) {
    Color borderColor = Colors.grey.shade200;
    Color fillColor   = const Color(0xFFFAFAFF);

    if (isValid == true)  { borderColor = _kGreen; fillColor = const Color(0xFFF0FDF4); }
    if (isValid == false) { borderColor = _kRed;   fillColor = const Color(0xFFFFF5F5); }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: TextFormField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: keyboardType,
        textAlign: TextAlign.right,
        textDirection: TextDirection.rtl,
        onChanged: onChanged,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
          floatingLabelAlignment: FloatingLabelAlignment.start,
          prefixIcon: Icon(icon, size: 20,
              color: isValid == true ? _kGreen : Colors.grey[400]),
          suffixIcon: suffix ??
              (isValid == true
                  ? const Icon(Icons.check_circle_rounded,
                      color: _kGreen, size: 20)
                  : isValid == false
                      ? const Icon(Icons.cancel_rounded,
                          color: _kRed, size: 20)
                      : null),
          filled: true,
          fillColor: fillColor,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: borderColor, width: 1.2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
                color: isValid == false ? _kRed : _kPurple, width: 1.6),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _kRed, width: 1.2),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _kRed, width: 1.6),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  // ── Password strength bar ────────────────────────────────────────────────────
  Widget _buildStrengthBar() {
    final labels = ['', 'חלשה', 'סבירה', 'טובה', 'חזקה מאוד!'];
    final colors = [
      Colors.transparent,
      _kRed,
      Colors.orange,
      const Color(0xFFEAB308),
      _kGreen,
    ];
    final color = colors[_passStrength.clamp(0, 4)];
    final label = labels[_passStrength.clamp(0, 4)];

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            children: List.generate(4, (i) {
              final active = i < _passStrength;
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 4,
                  margin: EdgeInsets.only(right: i > 0 ? 4 : 0),
                  decoration: BoxDecoration(
                    color: active ? color : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'סיסמה $label',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: color,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  // ── Category picker ───────────────────────────────────────────────────────────
  // ── ID / Passport upload widget ──────────────────────────────────────────
  Widget _buildIdUpload() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Section header ────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _kPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'מומלץ',
                style: TextStyle(
                    fontSize: 10,
                    color: _kPurple,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'אימות זהות',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey[700]),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.verified_user_rounded, size: 16, color: _kPurple),
          ],
        ),
        const SizedBox(height: 10),

        if (_idImageBytes == null) ...[
          // ── Upload card ─────────────────────────────────────────────
          GestureDetector(
            onTap: _showIdSourceSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F3FF),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _kPurple.withValues(alpha: 0.35),
                  width: 1.5,
                  // dashed style achieved via StrokeCap on the decoration
                ),
              ),
              child: Column(
                children: [
                  // Gradient icon container
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_kPurpleDark, _kPurpleLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: _kPurple.withValues(alpha: 0.30),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.file_upload_outlined,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'צילום תעודת זהות / דרכון',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _kPurpleDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'לחץ לבחירת תמונה מהגלריה או צילום חדש',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 14),
                  // Security badges
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _idBadge(Icons.lock_outline_rounded, 'מוצפן'),
                      const SizedBox(width: 10),
                      _idBadge(Icons.visibility_off_outlined, 'פרטי'),
                      const SizedBox(width: 10),
                      _idBadge(Icons.verified_outlined, 'ממתין לאישור'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'המסמך מאוחסן בהצפנה ומשמש לאימות זהות בלבד — לא יוצג ללקוחות',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, color: Colors.grey[400]),
          ),
        ] else ...[
          // ── Preview card — 3 states: checking / verified / failed ──
          _buildIdPreviewCard(),
        ],
      ],
    );
  }

  Widget _buildIdPreviewCard() {
    const Color borderCol = Color(0xFFF59E0B); // amber — pending

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 170,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderCol, width: 2),
            boxShadow: [
              BoxShadow(
                color: borderCol.withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Full-cover thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  _idImageBytes!,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),

              // Bottom gradient scrim
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.35, 1.0],
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.75),
                      ],
                    ),
                  ),
                ),
              ),

              // Top-left remove (X)
              Positioned(
                top: 8,
                left: 8,
                child: GestureDetector(
                  onTap: () => setState(() {
                    _idImageBytes = null;
                    _idImageName  = null;
                  }),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.5)),
                    ),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 16),
                  ),
                ),
              ),

              // Bottom status bar
              Positioned(
                bottom: 10,
                left: 10,
                right: 10,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(Icons.hourglass_top_rounded,
                        color: Color(0xFFF59E0B), size: 18),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'ממתין לאישור מנהל',
                        style: TextStyle(
                          color: Color(0xFFF59E0B),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // Replace button
                    GestureDetector(
                      onTap: _showIdSourceSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.45)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh_rounded,
                                color: Colors.white, size: 13),
                            SizedBox(width: 4),
                            Text('החלף',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline_rounded, size: 12,
                color: Colors.amber[700]),
            const SizedBox(width: 4),
            Text(
              'תאושר על-ידי מנהל תוך 24 שעות — תקבל/י אימייל',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.amber[700],
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ],
    );
  }

  Widget _idBadge(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: _kPurple.withValues(alpha: 0.2), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: _kPurple),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: _kPurple,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildCategoryPicker() {
    final cats = APP_CATEGORIES.map((c) => c['name'] as String).toList();
    // If AI set _category to a value not in APP_CATEGORIES (e.g. an auto-created
    // category like "טיפול בחיות מחמד"), add it at the top so the dropdown
    // never throws "There should be exactly one item with this value".
    if (!cats.contains(_category)) cats.insert(0, _category);

    return DropdownButtonFormField<String>(
      value: _category,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'תחום עיסוק',
        labelStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
        prefixIcon: const Icon(Icons.work_outline_rounded,
            size: 20, color: Color(0xFF6366F1)),
        filled: true,
        fillColor: const Color(0xFFF0F0FF),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
              color: Color(0xFF6366F1), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
              color: Color(0xFF6366F1), width: 1.6),
        ),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14)),
      ),
      items: cats.map((c) => DropdownMenuItem(
        value: c,
        child: Text(c, textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 14)),
      )).toList(),
      onChanged: (v) => setState(() => _category = v ?? _category),
    );
  }

  // ── Social divider ────────────────────────────────────────────────────────────
  Widget _buildSocialDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade200)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'או הצטרפו עם',
            style: TextStyle(
                fontSize: 12, color: Colors.grey[500],
                fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey.shade200)),
      ],
    );
  }

  // ── Quick summary card ────────────────────────────────────────────────────────
  Widget _buildQuickSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E0FF), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Title
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text(
                'AnySkill בקיצור',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _kPurple),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _kPurple,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('חשוב לדעת',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _summaryItem(
            emoji: '🔒',
            text:
                'הכסף שלך בטוח: התשלום מוחזק בנאמנות ומשוחרר רק באישור שלך.',
          ),
          const SizedBox(height: 8),
          _summaryItem(
            emoji: '🤝',
            text:
                'תיווך בלבד: האחריות על ביצוע העבודה היא על הספק.',
          ),
          const SizedBox(height: 8),
          _summaryItem(
            emoji: '⏱️',
            text:
                'מדיניות ביטולים: שים לב למדיניות של כל ספק לפני ההזמנה.',
          ),
        ],
      ),
    );
  }

  Widget _summaryItem({required String emoji, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            text,
            textAlign: TextAlign.right,
            style: TextStyle(
                fontSize: 13, height: 1.5, color: Colors.grey[700]),
          ),
        ),
        const SizedBox(width: 8),
        Text(emoji, style: const TextStyle(fontSize: 16)),
      ],
    );
  }

  // ── Terms row ─────────────────────────────────────────────────────────────────
  Widget _buildTermsRow() {
    // Individual TapGestureRecognizers so each link can be tapped separately
    // while the checkbox is tapped independently.
    final tosTap = TapGestureRecognizer()..onTap = _showTerms;
    final privacyTap = TapGestureRecognizer()..onTap = _showTerms;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _termsOk
            ? const Color(0xFFF0F0FF)
            : const Color(0xFFFAFAFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _termsOk ? _kPurple : Colors.grey.shade200,
          width: 1.2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Label ──────────────────────────────────────────────────────────
          Expanded(
            child: RichText(
              textAlign: TextAlign.right,
              text: TextSpan(
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.55,
                    color: Colors.grey[700]),
                children: [
                  const TextSpan(
                    text: 'אני מאשר/ת שקראתי והסכמתי ל',
                  ),
                  TextSpan(
                    text: 'תנאי השימוש',
                    recognizer: tosTap,
                    style: const TextStyle(
                      color: _kPurple,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                      decorationColor: _kPurple,
                    ),
                  ),
                  const TextSpan(text: ' ול'),
                  TextSpan(
                    text: 'מדיניות הפרטיות',
                    recognizer: privacyTap,
                    style: const TextStyle(
                      color: _kPurple,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                      decorationColor: _kPurple,
                    ),
                  ),
                  const TextSpan(text: ' של AnySkill (גרסה 2.0)'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          // ── Checkbox ───────────────────────────────────────────────────────
          GestureDetector(
            onTap: () => setState(() => _termsOk = !_termsOk),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: _termsOk ? _kPurple : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _termsOk ? _kPurple : Colors.grey.shade400,
                  width: 1.5,
                ),
              ),
              child: _termsOk
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 16)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  // ── Submit button ─────────────────────────────────────────────────────────────
  Widget _buildSubmitButton() {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
              strokeWidth: 3, color: _kPurple),
        ),
      );
    }
    // Providers must upload an ID photo before submitting
    final idGateOk = _currentRole != UserRole.expert || _idImageBytes != null;
    final enabled  = _termsOk && idGateOk;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1.0 : 0.45,
      child: Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: enabled
              ? [_kPurpleDark, _kPurple, _kPurpleLight]
              : [Colors.grey.shade400, Colors.grey.shade500,
                 Colors.grey.shade400],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: _kPurple.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : [],
      ),
      child: ElevatedButton(
        onPressed: enabled ? _signUp : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(
          _currentRole == UserRole.expert
              ? 'צור פרופיל מקצועי →'
              : 'הצטרף בחינם →',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
      ),
    ),   // AnimatedOpacity
    );
  }

  // ── Google icon ───────────────────────────────────────────────────────────────
  Widget _googleIcon() {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleIconPainter()),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _TrustPill extends StatelessWidget {
  const _TrustPill(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Role type button card ──────────────────────────────────────────────────────
class _TypeButton extends StatelessWidget {
  const _TypeButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final IconData     icon;
  final String       label;
  final String       subtitle;
  final bool         selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? _kPurple : const Color(0xFFF0F0FF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _kPurple : Colors.grey.shade200,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _kPurple.withValues(alpha: 0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 24,
                color: selected ? Colors.white : Colors.grey[500]),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: selected
                    ? Colors.white.withValues(alpha: 0.8)
                    : Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleHint extends StatelessWidget {
  const _RoleHint(
      {super.key, required this.icon, required this.text});
  final IconData icon;
  final String   text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 15, color: _kPurple),
        ],
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.borderColor,
    this.dark = false,
  });

  final String     label;
  final Widget     icon;
  final VoidCallback onTap;
  final Color?     borderColor;
  final bool       dark;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: dark ? Colors.black87 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: dark
              ? null
              : Border.all(color: borderColor ?? Colors.grey.shade300),
          boxShadow: dark
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: dark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Custom painters
// ─────────────────────────────────────────────────────────────────────────────

class _WavePainter extends CustomPainter {
  const _WavePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, size.height)
      ..quadraticBezierTo(
          size.width * 0.25, 0,
          size.width * 0.5, size.height * 0.5)
      ..quadraticBezierTo(
          size.width * 0.75, size.height,
          size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.color != color;
}

class _GoogleIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width / 2;

    // Background circle
    canvas.drawCircle(
      Offset(cx, cy), r,
      Paint()..color = Colors.white,
    );

    // Simplified coloured arcs
    final arc = Paint()
      ..style    = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.62);

    arc.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, -0.3,     1.2, false, arc);
    arc.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 0.9,      1.1, false, arc);
    arc.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, 2.0,      1.1, false, arc);
    arc.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, 3.1 + math.pi, 1.1, false, arc);
  }

  @override
  bool shouldRepaint(_GoogleIconPainter _) => false;
}
