import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'provider_registration_screen.dart';

// ── Brand tokens ──────────────────────────────────────────────────────────────
const _kPurple      = Color(0xFF6366F1);
const _kPurpleDark  = Color(0xFF4F46E5);
const _kPurpleLight = Color(0xFF8B5CF6);
const _kGreen       = Color(0xFF10B981);
const _kRed         = Color(0xFFEF4444);
const _kAmber       = Color(0xFFF59E0B);

// ─────────────────────────────────────────────────────────────────────────────
// OtpScreen — receives either a ConfirmationResult (web) or verificationId (mobile)
// ─────────────────────────────────────────────────────────────────────────────
class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.phoneDisplay,
    this.confirmationResult,   // web
    this.verificationId,       // mobile
  }) : assert(confirmationResult != null || verificationId != null,
              'Provide either confirmationResult or verificationId');

  final String              phoneDisplay;
  final ConfirmationResult? confirmationResult;
  final String?             verificationId;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  // ── 6 digit controllers ───────────────────────────────────────────────────
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _focusNodes  = List.generate(6, (_) => FocusNode());

  // ── State ─────────────────────────────────────────────────────────────────
  bool    _isLoading    = false;
  bool    _autoFilled   = false;
  int     _resendLeft   = 60;   // seconds until resend enabled
  Timer?  _resendTimer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    // Auto-focus first box
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focusNodes[0].requestFocus());
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (final c in _controllers) { c.dispose(); }
    for (final f in _focusNodes)  { f.dispose(); }
    super.dispose();
  }

  // ── Resend countdown ──────────────────────────────────────────────────────
  void _startResendTimer() {
    _resendLeft = 60;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (_resendLeft > 0) {
          _resendLeft--;
        } else {
          t.cancel();
        }
      });
    });
  }

  // ── Get current OTP string ────────────────────────────────────────────────
  String get _otp => _controllers.map((c) => c.text).join();

  // ── Verify ────────────────────────────────────────────────────────────────
  Future<void> _verify() async {
    final code = _otp;
    if (code.length < 6) {
      _snack('הזן את 6 הספרות', _kAmber);
      return;
    }

    setState(() => _isLoading = true);
    try {
      UserCredential cred;
      if (widget.confirmationResult != null) {
        // Web
        cred = await widget.confirmationResult!.confirm(code);
      } else {
        // Mobile
        final authCred = PhoneAuthProvider.credential(
          verificationId: widget.verificationId!,
          smsCode: code,
        );
        cred = await FirebaseAuth.instance.signInWithCredential(authCred);
      }

      final user  = cred.user!;
      final isNew = cred.additionalUserInfo?.isNewUser ?? false;

      if (isNew) {
        // First time — show role selection.
        // _RoleSelectionSheet calls popUntil(isFirst) on success, so
        // no navigation needed here after the sheet closes.
        if (mounted) await _showRoleSelection(user);
      } else {
        // Existing user — OtpScreen is still on the stack above AuthWrapper.
        // Pop everything back to root so AuthWrapper's StreamBuilder
        // (which now sees an authenticated user) renders _OnboardingGate → HomeScreen.
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }

    } on FirebaseAuthException catch (e) {
      if (mounted) _snack(_mapError(e.code), _kRed);
      _clearCode();
    } catch (_) {
      if (mounted) _snack('שגיאת אימות. נסה שוב.', _kRed);
      _clearCode();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Role selection for new users ──────────────────────────────────────────
  Future<void> _showRoleSelection(User user) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RoleSelectionSheet(
        user: user,
        phoneNumber: widget.phoneDisplay,
      ),
    );

    // Provider selected — sheet just closed, now push the full registration form
    if (result == 'provider' && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProviderRegistrationScreen(
            isExistingUser: false,
            prefillData: {
              'uid':      user.uid,
              'phone':    widget.phoneDisplay,
              'name':     user.displayName ?? '',
              'email':    user.email ?? '',
              'photoURL': user.photoURL ?? '',
            },
          ),
        ),
      );
    }
    // Client path: _RoleSelectionSheet already created the profile + called
    // popUntil(isFirst), so nothing more to do here.
  }

  // ── Resend OTP ────────────────────────────────────────────────────────────
  Future<void> _resend() async {
    if (_resendLeft > 0) return;
    Navigator.pop(context); // go back to phone input to re-send
  }

  void _clearCode() {
    for (final c in _controllers) { c.clear(); }
    _focusNodes[0].requestFocus();
  }

  String _mapError(String code) {
    switch (code) {
      case 'invalid-verification-code': return 'קוד שגוי. נסה שוב.';
      case 'session-expired':           return 'הקוד פג תוקף. בקש קוד חדש.';
      case 'code-expired':              return 'הקוד פג תוקף. בקש קוד חדש.';
      case 'too-many-requests':         return 'יותר מדי ניסיונות. נסה מאוחר יותר.';
      default:                          return 'שגיאה: $code';
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

  // ── Box input handler ─────────────────────────────────────────────────────
  void _onDigitChanged(int index, String value) {
    if (value.isEmpty) {
      // Backspace — move focus back
      if (index > 0) _focusNodes[index - 1].requestFocus();
      return;
    }
    // Handle paste: if >1 char entered (e.g. from SMS autofill), distribute
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (int i = 0; i < 6 && i < digits.length; i++) {
        _controllers[i].text = digits[i];
      }
      _focusNodes[5].requestFocus();
      setState(() => _autoFilled = true);
      if (digits.length >= 6) _verify();
      return;
    }
    // Move to next box
    if (index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else {
      _focusNodes[index].unfocus();
      _verify();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1E1B4B)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),

            // ── Icon ─────────────────────────────────────────────────────────
            Center(
              child: Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_kPurpleDark, _kPurpleLight],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: _kPurple.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.sms_rounded, color: Colors.white, size: 36),
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'הזן קוד אימות',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E1B4B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'שלחנו קוד SMS ל-${widget.phoneDisplay}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 36),

            // ── 6 digit boxes ─────────────────────────────────────────────────
            _buildDigitBoxes(),
            const SizedBox(height: 12),

            // Autofill indicator
            if (_autoFilled)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.auto_fix_high_rounded, color: _kGreen, size: 14),
                  SizedBox(width: 4),
                  Text('מולא אוטומטית',
                      style: TextStyle(color: _kGreen, fontSize: 12,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            const SizedBox(height: 32),

            // ── Verify button ─────────────────────────────────────────────────
            _buildVerifyButton(),
            const SizedBox(height: 24),

            // ── Resend ─────────────────────────────────────────────────────────
            Center(
              child: _resendLeft > 0
                  ? Text.rich(TextSpan(
                      text: 'שלח קוד חדש בעוד ',
                      style: TextStyle(color: Colors.grey[500], fontSize: 14),
                      children: [
                        TextSpan(
                          text: '$_resendLeft ש\'',
                          style: const TextStyle(
                              color: _kPurple, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ))
                  : GestureDetector(
                      onTap: _resend,
                      child: const Text('שלח קוד חדש',
                        style: TextStyle(
                          color: _kPurple,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          decoration: TextDecoration.underline,
                          decorationColor: _kPurple,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── 6 boxes ───────────────────────────────────────────────────────────────
  Widget _buildDigitBoxes() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(6, (i) {
        final hasValue = _controllers[i].text.isNotEmpty;
        return SizedBox(
          width: 46,
          height: 56,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: hasValue
                  ? _kPurple.withValues(alpha: 0.07)
                  : const Color(0xFFFAFAFF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasValue ? _kPurple : Colors.grey.shade300,
                width: hasValue ? 2.0 : 1.2,
              ),
            ),
            child: TextField(
              controller: _controllers[i],
              focusNode: _focusNodes[i],
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 6, // allows paste of full code
              // iOS SMS autofill
              autofillHints: i == 0
                  ? const [AutofillHints.oneTimeCode]
                  : null,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _kPurple,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                counterText: '',
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (v) {
                setState(() {}); // refresh hasValue decoration
                _onDigitChanged(i, v);
              },
            ),
          ),
        );
      }),
    );
  }

  // ── Verify button ─────────────────────────────────────────────────────────
  Widget _buildVerifyButton() {
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
        onPressed: _verify,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: const Icon(Icons.verified_rounded, color: Colors.white, size: 20),
        label: const Text(
          'אמת ועבור',
          style: TextStyle(color: Colors.white, fontSize: 17,
              fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Role selection sheet — shown only for brand-new users
// ─────────────────────────────────────────────────────────────────────────────
class _RoleSelectionSheet extends StatefulWidget {
  const _RoleSelectionSheet({required this.user, required this.phoneNumber});
  final User   user;
  final String phoneNumber;

  @override
  State<_RoleSelectionSheet> createState() => _RoleSelectionSheetState();
}

class _RoleSelectionSheetState extends State<_RoleSelectionSheet> {
  bool _isLoading     = false;
  bool _agreedToTerms = false;

  Future<void> _createProfile({required bool isProvider}) async {
    setState(() => _isLoading = true);
    try {
      final uid  = widget.user.uid;
      final name = widget.user.displayName ?? '';

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'uid':            uid,
        'name':           name,
        'email':          widget.user.email ?? '',
        'phone':          widget.phoneNumber,
        'balance':        0.0,
        'pendingBalance': 0.0,
        'rating':         5.0,
        'reviewsCount':   0,
        'pricePerHour':   0.0,
        'serviceType':    '',
        'aboutMe':        '',
        'profileImage':   widget.user.photoURL ?? '',
        'gallery':        [],
        'quickTags':      [],
        'isOnline':       true,
        'isAdmin':        false,
        'isVerified':     false,
        // Provider path: pending approval — no isProvider:true until admin approves
        'isCustomer':     !isProvider,
        'isProvider':     false,
        'isPendingExpert': isProvider,
        'expertApplicationData': isProvider
            ? {
                'submittedAt': FieldValue.serverTimestamp(),
                'phoneNumber': widget.phoneNumber,
              }
            : null,
        'termsAccepted':      true,
        'agreedToTerms':      true,
        'agreementTimestamp': FieldValue.serverTimestamp(),
        'onboardingComplete': false,
        'tourComplete':       false,
        'createdAt':          FieldValue.serverTimestamp(),
      }, SetOptions(merge: false));

      // Write activity_log entry for admin Live Feed
      await FirebaseFirestore.instance.collection('activity_log').add({
        'type':      isProvider ? 'expert_application' : 'registration',
        'userId':    uid,
        'name':      name,
        'phone':     widget.phoneNumber,
        'priority':  isProvider ? 'high' : 'normal',
        'timestamp': FieldValue.serverTimestamp(),
        'message':   isProvider
            ? 'בקשת הצטרפות כנותן שירות: $name ($uid)'
            : 'משתמש חדש נרשם: $name ($uid)',
      });

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('שגיאה ביצירת פרופיל: $e'),
          backgroundColor: _kRed,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 24),

          const Text(
            'ברוך הבא ל-AnySkill! 👋',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                color: Color(0xFF1E1B4B)),
          ),
          const SizedBox(height: 8),
          Text(
            'בחר כיצד תרצה להשתמש באפליקציה',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          const SizedBox(height: 32),

          // ── Terms & Conditions checkbox ───────────────────────────────────
          GestureDetector(
            onTap: _isLoading
                ? null
                : () => setState(() => _agreedToTerms = !_agreedToTerms),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: _agreedToTerms,
                    onChanged: _isLoading
                        ? null
                        : (v) => setState(() => _agreedToTerms = v ?? false),
                    activeColor: _kPurple,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey[600],
                          height: 1.45),
                      children: const [
                        TextSpan(text: 'אני מאשר/ת שקראתי והסכמתי ל-'),
                        TextSpan(
                          text: 'תנאי השימוש',
                          style: TextStyle(
                              color: _kPurple,
                              decoration: TextDecoration.underline,
                              decorationColor: _kPurple),
                        ),
                        TextSpan(text: ' ול-'),
                        TextSpan(
                          text: 'מדיניות הפרטיות',
                          style: TextStyle(
                              color: _kPurple,
                              decoration: TextDecoration.underline,
                              decorationColor: _kPurple),
                        ),
                        TextSpan(text: ' של AnySkill'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Client card ───────────────────────────────────────────────────
          _RoleCard(
            icon: Icons.search_rounded,
            color: const Color(0xFF6366F1),
            title: 'לקוח',
            subtitle: 'מחפש שירותים מקצועיים\nומזמין ספקים',
            enabled: _agreedToTerms,
            onTap: (_isLoading || !_agreedToTerms)
                ? null
                : () => _createProfile(isProvider: false),
          ),
          const SizedBox(height: 16),

          // ── Provider card ─────────────────────────────────────────────────
          // Returns 'provider' to _showRoleSelection which then pushes
          // ProviderRegistrationScreen for the full form.
          _RoleCard(
            icon: Icons.handyman_rounded,
            color: const Color(0xFF059669),
            title: 'נותן שירות',
            subtitle: 'מציע שירותים מקצועיים\nומרוויח דרך AnySkill',
            badge: 'ממתין לאישור מנהל',
            enabled: _agreedToTerms,
            onTap: (_isLoading || !_agreedToTerms)
                ? null
                : () => Navigator.pop(context, 'provider'),
          ),

          if (_isLoading) ...[
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: _kPurple),
          ],
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.enabled,
    this.badge,
  });
  final IconData      icon;
  final Color         color;
  final String        title;
  final String        subtitle;
  final String?       badge;
  final VoidCallback? onTap;
  final bool          enabled;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.38,
      duration: const Duration(milliseconds: 200),
      child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: color.withValues(alpha: enabled ? 0.05 : 0.02),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: color.withValues(alpha: enabled ? 0.25 : 0.12),
              width: 1.5),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: TextStyle(fontSize: 18,
                              fontWeight: FontWeight.bold, color: color)),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _kAmber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(badge!,
                              style: const TextStyle(fontSize: 10,
                                  color: _kAmber,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600],
                          height: 1.4)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: color),
          ],
        ),
      ),
      ),
    );
  }
}
