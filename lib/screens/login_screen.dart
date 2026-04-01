import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'sign_up_screen.dart';
import '../services/credentials_service.dart';
import '../l10n/app_localizations.dart';
import '../main.dart' show currentAppVersion, OnboardingGate;

// ── Brand tokens ──────────────────────────────────────────────────────────────
const _kPurple      = Color(0xFF6366F1);
const _kPurpleDark  = Color(0xFF4F46E5);
const _kPurpleLight = Color(0xFF8B5CF6);
const _kGreen       = Color(0xFF10B981);
const _kRed         = Color(0xFFEF4444);

// ─────────────────────────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool  _isLoading   = false;
  bool  _obscurePass = true;
  bool? _emailOk;
  bool  _rememberMe  = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  /// Pre-fills fields from encrypted storage when "Remember Me" was ticked
  /// on a previous login.
  Future<void> _loadSavedCredentials() async {
    try {
      final creds = await CredentialsService.load();
      if (creds.enabled && mounted) {
        setState(() {
          _emailCtrl.text = creds.email;
          _passCtrl.text  = creds.password;
          _rememberMe     = true;
          _emailOk        = _emailValid(creds.email);
        });
      }
    } catch (_) {
      // Silently ignore — secure storage unavailable on this device/platform
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────
  static bool _emailValid(String v) =>
      RegExp(r'^[\w\.\+\-]+@[\w\-]+\.[a-z]{2,}$', caseSensitive: false)
          .hasMatch(v.trim());

  String _mapError(String code, AppLocalizations l10n) => l10n.authError(code);

  // ── Login logic ───────────────────────────────────────────────────────────────
  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text.trim();

    final l10n = AppLocalizations.of(context);
    if (email.isEmpty || pass.isEmpty) {
      _snack(l10n.errorEmptyFields, Colors.orange);
      return;
    }
    if (!_emailValid(email)) {
      _snack(l10n.errorInvalidEmail, Colors.orange);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: pass,
      );
      // Persist or wipe credentials based on checkbox
      if (_rememberMe) {
        await CredentialsService.save(email: email, password: pass);
      } else {
        await CredentialsService.clear();
      }
      // Navigate directly to OnboardingGate and remove all previous routes.
      // This avoids the race condition where popUntil() returns to AuthWrapper
      // before its StreamBuilder has rebuilt with the new auth state, leaving
      // the user stuck on PhoneLoginScreen.
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const OnboardingGate()),
          (_) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('[Login] FirebaseAuthException: code=${e.code} message=${e.message}');
      if (mounted) _snack(_mapError(e.code, AppLocalizations.of(context)), _kRed);
    } catch (e) {
      // Catches non-FirebaseAuth errors (network, channel, platform)
      debugPrint('[Login] Unexpected error: $e');
      if (mounted) {
        _snack('${AppLocalizations.of(context).errorGenericLogin}\n(${e.runtimeType})', _kRed);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showForgotPassword() {
    final ctrl = TextEditingController();
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 20),
              Text(l10n.forgotPasswordTitle, textAlign: TextAlign.start, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(l10n.forgotPasswordSubtitle, textAlign: TextAlign.start, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
              const SizedBox(height: 20),
              TextField(
                controller: ctrl,
                textAlign: TextAlign.start,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: l10n.forgotPasswordEmail,
                  prefixIcon: const Icon(Icons.email_outlined, size: 20),
                  filled: true,
                  fillColor: const Color(0xFFF5F5FF),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _kPurple, width: 1.5)),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final email = ctrl.text.trim();
                    if (!_emailValid(email)) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.errorInvalidEmail), backgroundColor: Colors.orange));
                      return;
                    }
                    try {
                      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) _snack(l10n.forgotPasswordSuccess, _kGreen);
                    } catch (_) {
                      if (mounted) _snack(l10n.forgotPasswordError, _kRed);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPurple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(l10n.forgotPasswordSubmit,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() => ctrl.dispose());
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF6366F1)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
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
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Section title
                    Text(
                      l10n.loginAccountTitle,
                      textAlign: TextAlign.start,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E1B4B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.loginWelcomeBack,
                      textAlign: TextAlign.start,
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 28),

                    // Email
                    _buildField(
                      ctrl: _emailCtrl,
                      label: l10n.loginEmail,
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      isValid: _emailOk,
                      onChanged: (v) => setState(
                          () => _emailOk = _emailValid(v)),
                    ),
                    const SizedBox(height: 16),

                    // Password
                    _buildField(
                      ctrl: _passCtrl,
                      label: l10n.loginPassword,
                      icon: Icons.lock_outline_rounded,
                      obscure: _obscurePass,
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePass
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                          color: Colors.grey[500],
                        ),
                        onPressed: () => setState(
                            () => _obscurePass = !_obscurePass),
                      ),
                    ),

                    // ── Remember Me + Forgot password ────────────────
                    // RTL Row: first child → right side, second → left side
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // RIGHT side (RTL start): Remember Me
                          GestureDetector(
                            onTap: () =>
                                setState(() => _rememberMe = !_rememberMe),
                            behavior: HitTestBehavior.opaque,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Checkbox(
                                    value: _rememberMe,
                                    onChanged: (v) => setState(
                                        () => _rememberMe = v ?? false),
                                    activeColor: _kPurple,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    side: BorderSide(
                                      color: _rememberMe
                                          ? _kPurple
                                          : Colors.grey.shade400,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  l10n.loginRememberMe,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: _rememberMe
                                        ? _kPurple
                                        : Colors.grey[600],
                                    fontWeight: _rememberMe
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // LEFT side (RTL end): Forgot password
                          TextButton(
                            onPressed: _showForgotPassword,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 36),
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              l10n.loginForgotPassword,
                              style: TextStyle(
                                color: _kPurple,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Submit
                    _buildLoginButton(),
                    const SizedBox(height: 20),

                    // ── Quick summary card ─────────────────────────────
                    _buildQuickSummary(),
                    const SizedBox(height: 20),

                    // Sign-up link
                    Center(
                      child: GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SignUpScreen()),
                        ),
                        child: RichText(
                          text: TextSpan(
                            text: l10n.loginNoAccount,
                            style: TextStyle(color: Colors.grey[600], fontSize: 14),
                            children: [
                              TextSpan(
                                text: l10n.loginSignUpFree,
                                style: TextStyle(
                                  color: _kPurple,
                                  fontWeight: FontWeight.bold,
                                  decoration:
                                      TextDecoration.underline,
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
          // ── Version badge ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 36, top: 4),
              child: Center(
                child: Text(
                  'v$currentAppVersion',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFBDBDBD),
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero ──────────────────────────────────────────────────────────────────────
  Widget _buildHero() {
    final l10n = AppLocalizations.of(context);
    return Container(
      height: 300,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [_kPurpleDark, _kPurple, _kPurpleLight],
        ),
      ),
      child: Stack(
        children: [
          // Decorative elements
          Positioned(
            top: -50, left: -50,
            child: Container(
              width: 180, height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: 20, right: -20,
            child: Container(
              width: 130, height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          Positioned(
            top: 80, left: 60,
            child: Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),

          // Content
          Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 32,
              right: 28, left: 28,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Logo — centered, static high-res asset
                Center(
                  child: Image.asset(
                    'assets/images/NEW_LOGO1.png.png',
                    height: 80,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 8),
                // App name below logo
                Center(
                  child: Column(
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
                      const SizedBox(height: 2),
                      Text(
                        l10n.appSlogan,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Stats row
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _StatChip(value: '10K+', label: l10n.loginStats10k),
                    const SizedBox(width: 12),
                    _StatChip(value: '50+', label: l10n.loginStats50),
                    const SizedBox(width: 12),
                    _StatChip(value: '4.9★', label: l10n.loginStats49),
                  ],
                ),
              ],
            ),
          ),

          // Wave
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: CustomPaint(
              size: const Size(double.infinity, 36),
              painter: _WavePainter(color: const Color(0xFFF5F5FF)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Field ─────────────────────────────────────────────────────────────────────
  Widget _buildField({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool? isValid,
    bool obscure = false,
    Widget? suffix,
    void Function(String)? onChanged,
  }) {
    final borderColor = isValid == true
        ? _kGreen
        : isValid == false
            ? _kRed
            : Colors.grey.shade200;
    final fillColor = isValid == true
        ? const Color(0xFFF0FDF4)
        : isValid == false
            ? const Color(0xFFFFF5F5)
            : const Color(0xFFFAFAFF);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: keyboardType,
        textAlign: TextAlign.start,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          labelStyle:
              TextStyle(color: Colors.grey[500], fontSize: 14),
          prefixIcon: Icon(icon,
              size: 20,
              color: isValid == true ? _kGreen : Colors.grey[400]),
          suffixIcon: suffix ??
              (isValid == true
                  ? const Icon(Icons.check_circle_rounded,
                      color: _kGreen, size: 20)
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
            borderSide:
                const BorderSide(color: _kPurple, width: 1.6),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginButton() {
    final l10n = AppLocalizations.of(context);
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 40, height: 40,
          child: CircularProgressIndicator(
              strokeWidth: 3, color: _kPurple),
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
      child: ElevatedButton(
        onPressed: _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(
          l10n.loginButton,
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  // ── Quick summary card ("חשוב לדעת") ────────────────────────────────────
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
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('AnySkill בקיצור',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _kPurple)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _kPurple,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('חשוב לדעת',
                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _summaryItem(
            emoji: '🔒',
            text: 'הכסף שלך בטוח: התשלום מוחזק בנאמנות ומשוחרר רק באישור שלך.',
          ),
          const SizedBox(height: 8),
          _summaryItem(
            emoji: '🤝',
            text: 'תיווך בלבד: האחריות על ביצוע העבודה היא על הספק.',
          ),
          const SizedBox(height: 8),
          _summaryItem(
            emoji: '⏱️',
            text: 'מדיניות ביטולים: שים לב למדיניות של כל ספק לפני ההזמנה.',
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
          child: Text(text,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 13, height: 1.5, color: Colors.grey[700])),
        ),
        const SizedBox(width: 8),
        Text(emoji, style: const TextStyle(fontSize: 16)),
      ],
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  const _StatChip({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 10)),
        ],
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
      ..quadraticBezierTo(size.width * 0.25, 0,
          size.width * 0.5, size.height * 0.5)
      ..quadraticBezierTo(
          size.width * 0.75, size.height, size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.color != color;
}

