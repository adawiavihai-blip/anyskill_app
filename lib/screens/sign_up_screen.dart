import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../constants.dart';
import '../services/category_ai_service.dart';
import 'terms_of_service_screen.dart';

// ── Brand tokens ──────────────────────────────────────────────────────────────
const _kPurple      = Color(0xFF6366F1);
const _kPurpleDark  = Color(0xFF4F46E5);
const _kPurpleLight = Color(0xFF8B5CF6);
const _kGreen       = Color(0xFF10B981);
const _kRed         = Color(0xFFEF4444);

// ── User type enum ────────────────────────────────────────────────────────────
enum _UserType { customer, provider }

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
  _UserType _userType     = _UserType.customer;
  bool      _obscurePass  = true;
  bool      _termsOk      = false;
  bool      _isLoading    = false;
  String    _category     = 'אחר';

  // Live validation (null = untouched, true = valid, false = invalid)
  bool? _nameOk;
  bool? _emailOk;
  bool? _passOk;
  int   _passStrength = 0; // 0–4

  // Type-toggle animation
  late final AnimationController _toggleCtrl;

  @override
  void initState() {
    super.initState();
    _toggleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _phoneCtrl.dispose();
    _toggleCtrl.dispose();
    super.dispose();
  }

  // ── Validation helpers ───────────────────────────────────────────────────────
  static bool _emailValid(String v) =>
      RegExp(r'^[\w\.\+\-]+@[\w\-]+\.[a-z]{2,}$', caseSensitive: false)
          .hasMatch(v.trim());

  int _calcStrength(String p) {
    int s = 0;
    if (p.length >= 8)                          s++;
    if (RegExp(r'[A-Z]').hasMatch(p))           s++;
    if (RegExp(r'[0-9]').hasMatch(p))           s++;
    if (RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(p)) s++;
    return s;
  }

  // ── Sign-up logic ─────────────────────────────────────────────────────────
  Future<void> _signUp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_termsOk) {
      _snack('יש לאשר את תנאי השימוש כדי להמשיך', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);
    final nav  = Navigator.of(context);
    final msg  = ScaffoldMessenger.of(context);

    try {
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailCtrl.text.trim(),
            password: _passCtrl.text.trim(),
          );

      final uid = cred.user!.uid;
      final isProvider = _userType == _UserType.provider;

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
        'aboutMe':          isProvider
            ? 'מומחה חדש בקהילת AnySkill 🚀'
            : 'לקוח חדש ב-AnySkill',
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

      // Fire-and-forget AI categorization for new providers
      if (isProvider && _category.isNotEmpty) {
        CategoryAiService.categorize(_category).ignore();
      }

      if (mounted) {
        nav.pop();
        msg.showSnackBar(SnackBar(
          backgroundColor: _kGreen,
          content: const Text('החשבון נוצר! ברוכים הבאים ל-AnySkill 🎉'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ));
      }
    } on FirebaseAuthException catch (e) {
      final errs = {
        'email-already-in-use': 'כתובת האימייל כבר רשומה במערכת',
        'invalid-email':        'כתובת האימייל אינה תקינה',
        'weak-password':        'הסיסמה חלשה מדי — נסו סיסמה חזקה יותר',
        'network-request-failed': 'שגיאת רשת — בדקו חיבור לאינטרנט',
      };
      _snack(errs[e.code] ?? 'שגיאה ברישום', _kRed);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Social auth stubs (add google_sign_in + sign_in_with_apple packages) ──
  Future<void> _signInGoogle() async {
    setState(() => _isLoading = true);
    final nav = Navigator.of(context);
    final msg = ScaffoldMessenger.of(context);
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
      final isProvider = _userType == _UserType.provider;

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
          'aboutMe':          isProvider
              ? 'מומחה חדש בקהילת AnySkill 🚀'
              : 'לקוח חדש ב-AnySkill',
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

        // Fire-and-forget AI categorization — same as email sign-up
        if (isProvider && _category.isNotEmpty) {
          CategoryAiService.categorize(_category).ignore();
        }
      }

      if (mounted) {
        nav.pop();
        msg.showSnackBar(SnackBar(
          backgroundColor: _kGreen,
          content: Text(isNew
              ? 'החשבון נוצר! ברוכים הבאים ל-AnySkill 🎉'
              : 'ברוכים השבים! 👋'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (_) {
      if (mounted) _snack('שגיאה בהתחברות עם Google', _kRed);
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

  void _setType(_UserType t) {
    if (t == _userType) return;
    setState(() => _userType = t);
    t == _UserType.provider
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
                      // Type toggle
                      _buildTypeToggle(),
                      const SizedBox(height: 28),

                      // Name
                      _buildField(
                        ctrl: _nameCtrl,
                        label: 'שם מלא',
                        icon: Icons.person_outline_rounded,
                        isValid: _nameOk,
                        onChanged: (v) => setState(() =>
                            _nameOk = v.trim().length >= 2),
                        validator: (v) {
                          if ((v ?? '').trim().isEmpty) { return 'נא להזין שם'; }
                          if (v!.trim().length < 2) {
                            return 'השם חייב להכיל לפחות 2 תווים';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Phone (optional)
                      _buildField(
                        ctrl: _phoneCtrl,
                        label: 'טלפון (אופציונלי)',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),

                      // Email
                      _buildField(
                        ctrl: _emailCtrl,
                        label: 'כתובת אימייל',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        isValid: _emailOk,
                        onChanged: (v) => setState(() =>
                            _emailOk = _emailValid(v)),
                        validator: (v) {
                          if ((v ?? '').trim().isEmpty) {
                            return 'נא להזין אימייל';
                          }
                          if (!_emailValid(v!)) {
                            return 'כתובת אימייל אינה תקינה';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Password + strength bar
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
                          if ((v ?? '').isEmpty) { return 'נא להזין סיסמה'; }
                          if (v!.length < 6) {
                            return 'הסיסמה חייבת להכיל לפחות 6 תווים';
                          }
                          return null;
                        },
                      ),
                      if (_passCtrl.text.isNotEmpty)
                        _buildStrengthBar(),
                      const SizedBox(height: 16),

                      // Provider-only: category
                      AnimatedSize(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeInOut,
                        child: _userType == _UserType.provider
                            ? Column(
                                children: [
                                  _buildCategoryPicker(),
                                  const SizedBox(height: 16),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),

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
                // Logo
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text(
                      'AnySkill',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/images/LOGO.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ],
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
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'אני מצטרף/ת כ...',
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey[500],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFF0F0FF),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            children: [
              // Sliding pill
              AnimatedAlign(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOut,
                alignment: _userType == _UserType.provider
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_kPurple, _kPurpleLight],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: _kPurple.withValues(alpha: 0.30),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Labels
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _setType(_UserType.provider),
                      child: Container(
                        color: Colors.transparent,
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.construction_rounded,
                                size: 16,
                                color: _userType == _UserType.provider
                                    ? Colors.white
                                    : Colors.grey[500],
                              ),
                              const SizedBox(width: 6),
                              AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 200),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _userType == _UserType.provider
                                      ? Colors.white
                                      : Colors.grey[500]!,
                                  fontFamily: 'Heebo',
                                ),
                                child: const Text('נותן שירות'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _setType(_UserType.customer),
                      child: Container(
                        color: Colors.transparent,
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.search_rounded,
                                size: 16,
                                color: _userType == _UserType.customer
                                    ? Colors.white
                                    : Colors.grey[500],
                              ),
                              const SizedBox(width: 6),
                              AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 200),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _userType == _UserType.customer
                                      ? Colors.white
                                      : Colors.grey[500]!,
                                  fontFamily: 'Heebo',
                                ),
                                child: const Text('לקוח'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Role description chip
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _userType == _UserType.provider
              ? _RoleHint(
                  key: const ValueKey('provider'),
                  icon: Icons.trending_up_rounded,
                  text: 'קבלו הזמנות, נהלו לוח זמנים, והרוויחו יותר',
                )
              : _RoleHint(
                  key: const ValueKey('customer'),
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
  Widget _buildCategoryPicker() {
    final cats = APP_CATEGORIES.map((c) => c['name'] as String).toList();
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
      onChanged: (v) => setState(() => _category = v ?? 'אחר'),
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
    final enabled = _termsOk;
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
          _userType == _UserType.provider
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
