import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart' show currentAppVersion;
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
                    const SizedBox(height: 28),

                    // ── Email fallback (migrating users) ──────────────────────
                    Center(
                      child: GestureDetector(
                        onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const LoginScreen())),
                        child: Text.rich(
                          TextSpan(
                            text: 'יש לך חשבון ישן עם אימייל? ',
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
