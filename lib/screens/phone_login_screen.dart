import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../main.dart' show currentAppVersion, OnboardingGate;
import '../widgets/anyskill_logo.dart';
import 'otp_screen.dart';
import 'login_screen.dart'; // email fallback for migrating users

// ── Brand tokens ──────────────────────────────────────────────────────────────
const _kPurple      = Color(0xFF6366F1);
const _kPurpleDark  = Color(0xFF4F46E5);
const _kPurpleLight = Color(0xFF8B5CF6);
const _kRed         = Color(0xFFEF4444);

// ── Country model ─────────────────────────────────────────────────────────────
class _Country {
  const _Country(this.flag, this.name, this.dialCode);
  final String flag, name, dialCode;
}

const _kCountries = [
  _Country('🇮🇱', 'ישראל',          '+972'),
  _Country('🇺🇸', 'United States',  '+1'),
  _Country('🇬🇧', 'United Kingdom', '+44'),
  _Country('🇩🇪', 'Deutschland',    '+49'),
  _Country('🇫🇷', 'France',         '+33'),
  _Country('🇷🇺', 'Россия',         '+7'),
  _Country('🇵🇱', 'Polska',         '+48'),
  _Country('🇺🇦', 'Україна',        '+380'),
  _Country('🇲🇦', 'المغرب',         '+212'),
  _Country('🇯🇴', 'الأردن',         '+962'),
  _Country('🇹🇷', 'Türkiye',        '+90'),
  _Country('🇮🇳', 'India',          '+91'),
  _Country('🇧🇷', 'Brasil',         '+55'),
  _Country('🇦🇷', 'Argentina',      '+54'),
  _Country('🇪🇸', 'España',         '+34'),
];

// ── Rate-limit tracker (in-memory, resets on restart — server-side Firebase limits apply) ──
final List<DateTime> _otpSendTimestamps = [];
const _kMaxSends   = 3;
const _kWindowMins = 10;

bool _isRateLimited() {
  final cutoff = DateTime.now().subtract(const Duration(minutes: _kWindowMins));
  _otpSendTimestamps.removeWhere((t) => t.isBefore(cutoff));
  return _otpSendTimestamps.length >= _kMaxSends;
}

void _recordSend() => _otpSendTimestamps.add(DateTime.now());

// ─────────────────────────────────────────────────────────────────────────────
class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _phoneCtrl = TextEditingController();

  _Country  _country   = _kCountries[0]; // IL +972
  bool      _isLoading = false;
  bool?     _phoneOk;

  @override
  void initState() {
    super.initState();
    // After a signInWithRedirect (Google/Apple on mobile web), the page
    // reloads and we land here again. Process the redirect result to
    // create the Firestore profile for new users.
    if (kIsWeb) _handleRedirectResult();
  }

  Future<void> _handleRedirectResult() async {
    try {
      final result = await FirebaseAuth.instance.getRedirectResult();
      final user = result.user;
      if (user == null) return; // no redirect happened

      debugPrint('[Redirect] Got user: ${user.uid}');
      final isNew = result.additionalUserInfo?.isNewUser ?? false;

      if (isNew) {
        // Build display name — works for both Google and Apple redirects
        String name = user.displayName ?? '';
        if (name.isEmpty) {
          final profile = result.additionalUserInfo?.profile;
          if (profile != null) {
            name = (profile['name'] as String?) ?? '';
          }
        }

        final existing = await FirebaseFirestore.instance
            .collection('users').doc(user.uid).get();
        if (!existing.exists) {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'uid':            user.uid,
            'name':           name,
            'email':          user.email ?? '',
            'phone':          '',
            'balance':        0.0,
            'rating':         5.0,
            'reviewsCount':   0,
            'pricePerHour':   0.0,
            'serviceType':    '',
            'aboutMe':        '',
            'profileImage':   user.photoURL ?? '',
            'gallery':        [],
            'quickTags':      [],
            'isOnline':       true,
            'isAdmin':        false,
            'isVerified':     false,
            'isCustomer':     true,
            'isProvider':     false,
            'termsAccepted':  true,
            'onboardingComplete': false,
            'tourComplete':   false,
            'createdAt':      FieldValue.serverTimestamp(),
          });
          debugPrint('[Redirect] Created profile for new user: ${user.uid}');
        }
      }
      // AuthWrapper's StreamBuilder will pick up the user and navigate
      // to OnboardingGate automatically — no manual navigation needed.
    } catch (e) {
      debugPrint('[Redirect] getRedirectResult error: $e');
      // Non-fatal — if redirect didn't happen, this throws harmlessly
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ── Validation ───────────────────────────────────────────────────────────────
  bool _validate(String v) => RegExp(r'^\d{7,12}$').hasMatch(v.trim());

  String get _fullPhone => '${_country.dialCode}${_phoneCtrl.text.trim()}';

  // ── Send OTP ─────────────────────────────────────────────────────────────────
  Future<void> _sendOtp() async {
    final number = _phoneCtrl.text.trim();
    if (!_validate(number)) {
      _snack('מספר טלפון לא תקין', _kRed);
      return;
    }
    if (_isRateLimited()) {
      _snack('שלחת יותר מדי קודים. המתן $_kWindowMins דקות ונסה שוב.', _kRed);
      return;
    }

    setState(() => _isLoading = true);
    _recordSend();

    try {
      if (kIsWeb) {
        // Web: invisible reCAPTCHA handled by Firebase SDK automatically
        final confirmationResult = await FirebaseAuth.instance
            .signInWithPhoneNumber(_fullPhone);
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => OtpScreen(
            phoneDisplay:       _fullPhone,
            confirmationResult: confirmationResult,
          ),
        ));
      } else {
        // Mobile: native SMS Retriever / User Consent handled by Firebase
        final completer = Completer<String>();
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: _fullPhone,
          timeout: const Duration(seconds: 60),
          verificationCompleted: (PhoneAuthCredential cred) async {
            // Android instant auto-verification — sign in immediately
            try {
              await FirebaseAuth.instance.signInWithCredential(cred);
            } catch (_) {}
          },
          verificationFailed: (FirebaseAuthException e) {
            completer.completeError(e);
          },
          codeSent: (String verificationId, int? resendToken) {
            completer.complete(verificationId);
          },
          codeAutoRetrievalTimeout: (_) {},
        );
        final verificationId = await completer.future;
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => OtpScreen(
            phoneDisplay:   _fullPhone,
            verificationId: verificationId,
          ),
        ));
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) _snack(_mapFirebaseError(e.code), _kRed);
    } catch (e) {
      if (mounted) _snack('שגיאה בשליחת הקוד. נסה שוב.', _kRed);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _mapFirebaseError(String code) {
    switch (code) {
      case 'invalid-phone-number':   return 'מספר טלפון לא תקין';
      case 'too-many-requests':      return 'יותר מדי ניסיונות. נסה מאוחר יותר.';
      case 'quota-exceeded':         return 'מכסת SMS חרגה. נסה מחר.';
      case 'network-request-failed': return 'אין חיבור לאינטרנט';
      default:                       return 'שגיאה: $code';
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

  // ── Country picker ───────────────────────────────────────────────────────────
  void _pickCountry() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CountryPickerSheet(
        selected: _country,
        onPicked: (c) => setState(() => _country = c),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FF),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHero()),
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
                    const Text(
                      'כניסה / הרשמה',
                      textAlign: TextAlign.start,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E1B4B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'הזן את מספר הטלפון שלך ונשלח קוד אימות',
                      textAlign: TextAlign.start,
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 28),

                    // ── Phone field with country code ─────────────────────────
                    _buildPhoneField(),
                    const SizedBox(height: 10),

                    // Rate-limit hint
                    Text(
                      'ניתן לשלוח עד $_kMaxSends קודים בכל $_kWindowMins דקות',
                      textAlign: TextAlign.start,
                      style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                    ),
                    const SizedBox(height: 24),

                    // ── Send button ───────────────────────────────────────────
                    _buildSendButton(),
                    const SizedBox(height: 20),

                    // ── Social divider ────────────────────────────────────────
                    Row(children: [
                      Expanded(child: Divider(color: Colors.grey[300])),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text('או',
                            style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                      ),
                      Expanded(child: Divider(color: Colors.grey[300])),
                    ]),
                    const SizedBox(height: 16),

                    // ── Social sign-in buttons ───────────────────────────────
                    Row(
                      children: [
                        Expanded(child: _buildSocialBtn(
                          label: 'Google',
                          icon: _buildGoogleIcon(),
                          onTap: _loginGoogle,
                          dark: false,
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: _buildSocialBtn(
                          label: 'Apple',
                          icon: const Icon(Icons.apple, size: 22, color: Colors.white),
                          onTap: _loginApple,
                          dark: true,
                        )),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Email fallback (migrating users) ──────────────────────
                    Center(
                      child: GestureDetector(
                        onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const LoginScreen())),
                        child: Text.rich(
                          TextSpan(
                            text: 'יש לך חשבון עם אימייל? ',
                            style: TextStyle(color: Colors.grey[500], fontSize: 13),
                            children: const [
                              TextSpan(
                                text: 'כניסה עם אימייל',
                                style: TextStyle(
                                  color: _kPurple,
                                  fontWeight: FontWeight.w600,
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
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 36, top: 4),
              child: Center(
                child: Text(
                  'v$currentAppVersion',
                  style: const TextStyle(fontSize: 11, color: Color(0xFFBDBDBD)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Phone field ───────────────────────────────────────────────────────────────
  Widget _buildPhoneField() {
    final borderColor = _phoneOk == true
        ? const Color(0xFF10B981)
        : _phoneOk == false
            ? _kRed
            : Colors.grey.shade200;
    final fillColor = _phoneOk == true
        ? const Color(0xFFF0FDF4)
        : _phoneOk == false
            ? const Color(0xFFFFF5F5)
            : const Color(0xFFFAFAFF);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Row(
        children: [
          // Country code button
          GestureDetector(
            onTap: _pickCountry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_country.flag, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 6),
                  Text(
                    _country.dialCode,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E1B4B),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey[500]),
                ],
              ),
            ),
          ),

          // Phone number input
          Expanded(
            child: TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.start,
              onChanged: (v) => setState(() => _phoneOk = _validate(v)),
              onSubmitted: (_) => _sendOtp(),
              decoration: InputDecoration(
                hintText: 'מספר טלפון',
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                suffixIcon: _phoneOk == true
                    ? const Icon(Icons.check_circle_rounded,
                        color: Color(0xFF10B981), size: 20)
                    : null,
              ),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  // ── Send button ───────────────────────────────────────────────────────────────
  Widget _buildSendButton() {
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
        onPressed: _sendOtp,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
        label: const Text(
          'שלח קוד אימות',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ── Hero (identical purple gradient from login_screen) ────────────────────────
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
          Positioned(top: -50, left: -50,
            child: Container(width: 180, height: 180,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06)))),
          Positioned(bottom: 20, right: -20,
            child: Container(width: 130, height: 130,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.07)))),
          Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 32,
              right: 28, left: 28,
            ),
            child: Column(
              children: [
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('system_settings').doc('global').snapshots(),
                  builder: (context, snap) {
                    final size = ((snap.data?.data() ?? {})['authLogoSize'] as num? ?? 100).toDouble();
                    return AnySkillBrandIcon(size: size);
                  },
                ),
                const SizedBox(height: 8),
                const Text('AnySkill',
                  style: TextStyle(color: Colors.white, fontSize: 28,
                      fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text('כניסה מהירה עם מספר טלפון',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _chip(Icons.lock_outline_rounded, 'מאובטח'),
                    const SizedBox(width: 12),
                    _chip(Icons.bolt_rounded, 'מהיר'),
                    const SizedBox(width: 12),
                    _chip(Icons.verified_rounded, 'אמין'),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: CustomPaint(
              size: const Size(double.infinity, 32),
              painter: _WavePainter(color: const Color(0xFFF5F5FF)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12,
              fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Social sign-in — Google + Apple (on the landing page for 1-tap access)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSocialBtn({
    required String label,
    required Widget icon,
    required VoidCallback onTap,
    bool dark = false,
  }) {
    return GestureDetector(
      onTap: _isLoading ? null : onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: dark ? Colors.black87 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: dark ? null : Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.18 : 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 8),
            Text(label,
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

  Widget _buildGoogleIcon() {
    return SizedBox(
      width: 20, height: 20,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }

  // ── Google Sign-In ──────────────────────────────────────────────────────

  Future<void> _loginGoogle() async {
    setState(() => _isLoading = true);
    try {
      if (kIsWeb) {
        // On web (especially mobile Safari/Chrome): use redirect.
        // Popups are blocked on iOS Safari. After redirect, the page
        // reloads and _handleRedirectResult() processes the new user.
        await FirebaseAuth.instance.signInWithRedirect(GoogleAuthProvider());
        return; // page navigates away — no further code runs
      }

      // Native mobile: use GoogleSignIn plugin
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final googleAuth = await googleUser.authentication;
      final cred = await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        ),
      );

      final user  = cred.user!;
      final isNew = cred.additionalUserInfo?.isNewUser ?? false;

      if (isNew) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'uid':            user.uid,
          'name':           user.displayName ?? '',
          'email':          user.email ?? '',
          'phone':          '',
          'balance':        0.0,
          'rating':         5.0,
          'reviewsCount':   0,
          'pricePerHour':   0.0,
          'serviceType':    '',
          'aboutMe':        '',
          'profileImage':   user.photoURL ?? '',
          'gallery':        [],
          'quickTags':      [],
          'isOnline':       true,
          'isAdmin':        false,
          'isVerified':     false,
          'isCustomer':     true,
          'isProvider':     false,
          'termsAccepted':  true,
          'onboardingComplete': false,
          'tourComplete':   false,
          'createdAt':      FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const OnboardingGate()),
          (_) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('[GoogleLogin] FirebaseAuth: ${e.code} — ${e.message}');
      if (mounted) _snack('Google: ${e.code}\n${e.message ?? ""}', _kRed);
    } catch (e) {
      debugPrint('[GoogleLogin] ${e.runtimeType}: $e');
      if (mounted) {
        final msg = e.toString();
        if (!msg.contains('canceled') && !msg.contains('cancelled')) {
          _snack('Google: ${e.runtimeType}\n${msg.length > 120 ? msg.substring(0, 120) : msg}', _kRed);
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Apple Sign-In ───────────────────────────────────────────────────────

  Future<void> _loginApple() async {
    setState(() => _isLoading = true);
    try {
      if (kIsWeb) {
        // On web: use Firebase's built-in OAuthProvider with redirect.
        // The sign_in_with_apple package returns JS objects that crash
        // in minified builds ("Instance of 'minified:Pc' is not a subtype").
        // Firebase's OAuthProvider handles the Apple OAuth flow natively.
        final provider = OAuthProvider('apple.com')
          ..addScope('email')
          ..addScope('name');
        await FirebaseAuth.instance.signInWithRedirect(provider);
        return; // page navigates away — _handleRedirectResult picks up
      }

      // Native iOS: use sign_in_with_apple package
      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken:     appleCredential.identityToken,
        rawNonce:    rawNonce,
        accessToken: appleCredential.authorizationCode,
      );

      final cred = await FirebaseAuth.instance.signInWithCredential(oauthCredential);
      final user  = cred.user!;
      final isNew = cred.additionalUserInfo?.isNewUser ?? false;

      // Apple only provides name on FIRST sign-in
      String displayName = user.displayName ?? '';
      if (displayName.isEmpty) {
        final given  = appleCredential.givenName ?? '';
        final family = appleCredential.familyName ?? '';
        displayName  = '$given $family'.trim();
      }
      if (displayName.isNotEmpty && (user.displayName ?? '').isEmpty) {
        await user.updateDisplayName(displayName);
      }

      if (isNew) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'uid':            user.uid,
          'name':           displayName,
          'email':          user.email ?? appleCredential.email ?? '',
          'phone':          '',
          'balance':        0.0,
          'rating':         5.0,
          'reviewsCount':   0,
          'pricePerHour':   0.0,
          'serviceType':    '',
          'aboutMe':        '',
          'profileImage':   '',
          'gallery':        [],
          'quickTags':      [],
          'isOnline':       true,
          'isAdmin':        false,
          'isVerified':     false,
          'isCustomer':     true,
          'isProvider':     false,
          'termsAccepted':  true,
          'onboardingComplete': false,
          'tourComplete':   false,
          'createdAt':      FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const OnboardingGate()),
          (_) => false,
        );
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      debugPrint('[AppleLogin] AppleAuth: ${e.code} — ${e.message}');
      if (e.code != AuthorizationErrorCode.canceled && mounted) {
        _snack('Apple: ${e.code.name}\n${e.message}', _kRed);
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('[AppleLogin] FirebaseAuth: ${e.code} — ${e.message}');
      if (mounted) _snack('Apple: ${e.code}\n${e.message ?? ""}', _kRed);
    } catch (e) {
      debugPrint('[AppleLogin] ${e.runtimeType}: $e');
      if (mounted) {
        final msg = e.toString();
        if (!msg.contains('canceled') && !msg.contains('cancelled')) {
          _snack('Apple: ${e.runtimeType}\n${msg.length > 120 ? msg.substring(0, 120) : msg}', _kRed);
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = math.Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// Google logo painter (matches login_screen.dart)
// ─────────────────────────────────────────────────────────────────────────────
class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    // Blue arc (top-right)
    canvas.drawArc(Rect.fromLTWH(0, 0, s, s), -0.5, 1.8,
        true, Paint()..color = const Color(0xFF4285F4));
    // Green arc (bottom-right)
    canvas.drawArc(Rect.fromLTWH(0, 0, s, s), 1.3, 1.2,
        true, Paint()..color = const Color(0xFF34A853));
    // Yellow arc (bottom-left)
    canvas.drawArc(Rect.fromLTWH(0, 0, s, s), 2.5, 1.0,
        true, Paint()..color = const Color(0xFFFBBC05));
    // Red arc (top-left)
    canvas.drawArc(Rect.fromLTWH(0, 0, s, s), 3.5, 1.1,
        true, Paint()..color = const Color(0xFFEA4335));
    // White center
    canvas.drawCircle(Offset(s / 2, s / 2), s * 0.3,
        Paint()..color = Colors.white);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Country picker bottom sheet
// ─────────────────────────────────────────────────────────────────────────────
class _CountryPickerSheet extends StatelessWidget {
  const _CountryPickerSheet({required this.selected, required this.onPicked});
  final _Country          selected;
  final ValueChanged<_Country> onPicked;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 16),
          const Text('בחר מדינה',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
                  color: Color(0xFF1E1B4B))),
          const SizedBox(height: 8),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _kCountries.length,
              itemBuilder: (_, i) {
                final c = _kCountries[i];
                final isSelected = c.dialCode == selected.dialCode;
                return ListTile(
                  leading: Text(c.flag, style: const TextStyle(fontSize: 24)),
                  title: Text(c.name,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? _kPurple : Colors.black87,
                      )),
                  trailing: Text(c.dialCode,
                      style: TextStyle(
                        color: isSelected ? _kPurple : Colors.grey[600],
                        fontWeight: FontWeight.w600,
                      )),
                  selected: isSelected,
                  selectedTileColor: _kPurple.withValues(alpha: 0.06),
                  onTap: () {
                    onPicked(c);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
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
