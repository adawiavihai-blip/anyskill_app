import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../main.dart' show currentAppVersion;
import '../widgets/anyskill_logo.dart';
import 'otp_screen.dart';
import 'terms_of_service_screen.dart';
import 'provider_registration_wizard_screen.dart';
import '../services/private_data_service.dart';
import '../services/auth_duplicate_guard.dart';
import '../services/locale_provider.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

// ── Brand tokens — reuse existing Brand.* palette ─────────────────────────────
final _kPrimary     = Brand.indigo;       // #6366F1
final _kPrimaryDark = Brand.indigoDark;   // #4F46E5
final _kPrimaryLight = Brand.purple;      // #8B5CF6
const _kRed         = Brand.error;

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

class _PhoneLoginScreenState extends State<PhoneLoginScreen>
    with TickerProviderStateMixin {
  /// True when running as iOS PWA (standalone mode from Home Screen).
  /// Google/Apple OAuth require popups which iOS PWA blocks entirely.
  bool get _isIOSPwa {
    if (!kIsWeb) return false;
    final hasManifestParam = Uri.base.queryParameters.containsKey('v');
    return hasManifestParam;
  }

  final _phoneCtrl = TextEditingController();
  final _langBtnKey = GlobalKey();
  final _phoneFocus = FocusNode();

  _Country  _country   = _kCountries[0]; // IL +972
  bool      _isLoading = false;
  bool?     _phoneOk;
  bool      _phoneFocused = false;

  OverlayEntry? _langOverlay;

  // ── Animations ───────────────────────────────────────────────────────────
  late final AnimationController _staggerCtrl;
  late final AnimationController _orbCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _ctaPulseCtrl;
  late final AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..forward();

    _orbCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();

    _ctaPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _phoneFocus.addListener(() {
      if (mounted) setState(() => _phoneFocused = _phoneFocus.hasFocus);
    });
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _phoneFocus.dispose();
    _staggerCtrl.dispose();
    _orbCtrl.dispose();
    _pulseCtrl.dispose();
    _ctaPulseCtrl.dispose();
    _shimmerCtrl.dispose();
    _removeLangOverlay();
    super.dispose();
  }

  // ── Validation ───────────────────────────────────────────────────────────
  bool _validate(String v) => RegExp(r'^\d{7,12}$').hasMatch(v.trim());

  String get _fullPhone => '${_country.dialCode}${_phoneCtrl.text.trim()}';

  // ── Send OTP ─────────────────────────────────────────────────────────────
  Future<void> _sendOtp() async {
    final number = _phoneCtrl.text.trim();
    if (!_validate(number)) {
      _snack(AppLocalizations.of(context).phoneInvalidNumber, _kRed);
      return;
    }
    if (_isRateLimited()) {
      _snack(AppLocalizations.of(context).phoneTooManyCodes(_kWindowMins), _kRed);
      return;
    }

    setState(() => _isLoading = true);
    _recordSend();

    try {
      if (kIsWeb) {
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
        final completer = Completer<String>();
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: _fullPhone,
          timeout: const Duration(seconds: 60),
          verificationCompleted: (PhoneAuthCredential cred) async {
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
      if (mounted) _snack(AppLocalizations.of(context).phoneSendCodeError, _kRed);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _mapFirebaseError(String code) {
    final l10n = AppLocalizations.of(context);
    switch (code) {
      case 'invalid-phone-number':   return l10n.phoneInvalidNumber;
      case 'too-many-requests':      return l10n.phoneErrorTooManyRequests;
      case 'quota-exceeded':         return l10n.phoneErrorQuotaExceeded;
      case 'network-request-failed': return l10n.phoneErrorNoNetwork;
      default:                       return l10n.phoneErrorGeneric(code);
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

  // ── Country picker ───────────────────────────────────────────────────────
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

  // ═══════════════════════════════════════════════════════════════════════════
  // LANGUAGE SWITCHER — Dropdown
  // ═══════════════════════════════════════════════════════════════════════════

  String _currentFlag() {
    switch (LocaleProvider.instance.locale.languageCode) {
      case 'en': return '🇺🇸';
      case 'es': return '🇪🇸';
      case 'ar': return '🇸🇦';
      default:   return '🇮🇱';
    }
  }

  String _currentLangLabel(AppLocalizations l10n) {
    switch (LocaleProvider.instance.locale.languageCode) {
      case 'en': return l10n.languageEn;
      case 'es': return l10n.languageEs;
      case 'ar': return l10n.languageAr;
      default:   return l10n.languageHe;
    }
  }

  void _toggleLangOverlay() {
    if (_langOverlay != null) {
      _removeLangOverlay();
    } else {
      _showLangOverlay();
    }
  }

  void _showLangOverlay() {
    final renderBox =
        _langBtnKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final screenSize = MediaQuery.of(context).size;

    // Position dropdown below the button
    final top = offset.dy + size.height + 6;
    // In RTL, button is on the "start" (right) — dropdown aligns to right edge of button
    final right = screenSize.width - offset.dx - size.width;

    _langOverlay = OverlayEntry(
      builder: (_) => Stack(
        children: [
          // Click-outside catcher
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _removeLangOverlay,
            ),
          ),
          // Dropdown menu
          Positioned(
            top: top,
            right: right,
            child: _LanguageDropdown(
              onPick: (locale) {
                LocaleProvider.instance.setLocale(locale);
                _removeLangOverlay();
                if (mounted) setState(() {});
              },
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_langOverlay!);
  }

  void _removeLangOverlay() {
    _langOverlay?.remove();
    _langOverlay = null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FF),
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTap: () {
          _removeLangOverlay();
          FocusScope.of(context).unfocus();
        },
        behavior: HitTestBehavior.translucent,
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height,
            ),
            child: Column(
              children: [
                _buildCard(l10n),
                // Version footer
                const SizedBox(height: 16),
                Text(
                  'AnySkill v$currentAppVersion',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFFB4B4BC),
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Main card (hero + form + bottom strip)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCard(AppLocalizations l10n) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 20, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHero(l10n),
              _buildForm(l10n),
              _buildBottomStrip(l10n),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 1. HERO SECTION — Gradient + animated orbs + logo + subtitle
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHero(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kPrimaryDark, _kPrimary, _kPrimaryLight],
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
      child: RepaintBoundary(
        child: Stack(
          children: [
            // Animated floating orbs
            _buildFloatingOrb(
              size: 180,
              top: -40,
              end: -40,
              color: Brand.warning.withValues(alpha: 0.22),
              animOffset: 0,
            ),
            _buildFloatingOrb(
              size: 140,
              bottom: -30,
              start: -30,
              color: Colors.white.withValues(alpha: 0.15),
              animOffset: 0.5,
            ),
            // Pulsing dots
            _buildPulseDot(top: 40, end: 50, size: 5, color: Colors.white),
            _buildPulseDot(top: 90, end: 120, size: 4, color: Brand.warning, delay: 0.3),
            _buildPulseDot(bottom: 70, start: 60, size: 3, color: Colors.white, delay: 0.6),

            // Content
            Column(
              children: [
                // Language switcher — top-start (right in RTL)
                Align(
                  alignment: AlignmentDirectional.topStart,
                  child: _buildStagger(
                    delay: 0,
                    child: _buildLanguageButton(l10n),
                  ),
                ),
                const SizedBox(height: 14),
                // Logo in white rounded square
                _buildStagger(
                  delay: 0,
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.1),
                          blurRadius: 0,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: AnySkillBrandIcon(size: 56),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                // Subtitle
                _buildStagger(
                  delay: 0.14,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Text(
                      l10n.phoneLoginHeroSubtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingOrb({
    required double size,
    required Color color,
    double? top,
    double? bottom,
    double? start,
    double? end,
    double animOffset = 0,
  }) {
    return AnimatedBuilder(
      animation: _orbCtrl,
      builder: (_, __) {
        // Offset the sine wave by animOffset so the two orbs move in opposite phases
        final t = (_orbCtrl.value + animOffset) % 1.0;
        final dx = math.sin(t * 2 * math.pi) * 18;
        final dy = math.cos(t * 2 * math.pi) * 14;
        final scale = 1 + math.sin(t * 2 * math.pi) * 0.06;
        return PositionedDirectional(
          top: top,
          bottom: bottom,
          start: start,
          end: end,
          child: Transform.translate(
            offset: Offset(dx, dy),
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [color, color.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPulseDot({
    required double size,
    required Color color,
    double? top,
    double? bottom,
    double? start,
    double? end,
    double delay = 0,
  }) {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) {
        final t = (_pulseCtrl.value + delay) % 1.0;
        final scale = 1 + t * 0.4;
        final opacity = (1 - t).clamp(0.3, 0.8);
        return PositionedDirectional(
          top: top,
          bottom: bottom,
          start: start,
          end: end,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: opacity),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLanguageButton(AppLocalizations l10n) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          key: _langBtnKey,
          color: Colors.white.withValues(alpha: 0.14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.22),
              width: 0.5,
            ),
          ),
          child: InkWell(
            onTap: _toggleLangOverlay,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.language_rounded,
                      color: Colors.white, size: 13),
                  const SizedBox(width: 6),
                  Text(
                    _currentLangLabel(l10n),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _currentFlag(),
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.white.withValues(alpha: 0.85),
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 2. FORM SECTION — Social buttons + phone + CTA + terms
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildForm(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_isIOSPwa) ...[
            _buildStagger(
              delay: 0.22,
              child: _buildSocialButton(
                label: l10n.phoneLoginContinueGoogle,
                icon: _buildGoogleIcon(),
                onTap: _loginGoogle,
                dark: false,
              ),
            ),
            const SizedBox(height: 9),
            _buildStagger(
              delay: 0.26,
              child: _buildSocialButton(
                label: l10n.phoneLoginContinueApple,
                icon: const Icon(Icons.apple, size: 20, color: Color(0xFF1C1C28)),
                onTap: _loginApple,
                dark: false,
              ),
            ),
            const SizedBox(height: 16),
            _buildStagger(
              delay: 0.30,
              child: _buildDivider(l10n),
            ),
            const SizedBox(height: 16),
          ],
          _buildStagger(
            delay: 0.34,
            child: _buildPhoneField(l10n),
          ),
          const SizedBox(height: 14),
          _buildStagger(
            delay: 0.38,
            child: _buildCTAButton(l10n),
          ),
          const SizedBox(height: 14),
          _buildStagger(
            delay: 0.44,
            child: _buildTermsText(l10n),
          ),
        ],
      ),
    );
  }

  // ── Social button ────────────────────────────────────────────────────────
  Widget _buildSocialButton({
    required String label,
    required Widget icon,
    required VoidCallback onTap,
    bool dark = false,
  }) {
    // Listener (onPointerUp) matches the iOS PWA-safe pattern from the
    // original implementation — avoids the 300ms delay + swallowed taps.
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerUp: _isLoading ? null : (_) => onTap(),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E5EC), width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF1C1C28),
                fontWeight: FontWeight.w500,
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
      width: 18,
      height: 18,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }

  // ── Divider "or with phone" ──────────────────────────────────────────────
  Widget _buildDivider(AppLocalizations l10n) {
    return Row(
      children: [
        const Expanded(
          child: Divider(color: Color(0xFFE5E5EC), height: 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            l10n.phoneLoginOrPhone,
            style: const TextStyle(
              color: Color(0xFF9A9AA8),
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const Expanded(
          child: Divider(color: Color(0xFFE5E5EC), height: 1),
        ),
      ],
    );
  }

  // ── Phone field ──────────────────────────────────────────────────────────
  Widget _buildPhoneField(AppLocalizations l10n) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _phoneFocused ? _kPrimary : const Color(0xFFE5E5EC),
            width: _phoneFocused ? 1.5 : 0.5,
          ),
          boxShadow: _phoneFocused
              ? [
                  BoxShadow(
                    color: _kPrimary.withValues(alpha: 0.12),
                    blurRadius: 0,
                    spreadRadius: 4,
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Row(
            children: [
              // Country prefix (left in LTR)
              InkWell(
                onTap: _pickCountry,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF7F7FB),
                    border: Border(
                      right: BorderSide(color: Color(0xFFE5E5EC), width: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_country.flag,
                          style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text(
                        _country.dialCode,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1C1C28),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Phone input
              Expanded(
                child: TextField(
                  controller: _phoneCtrl,
                  focusNode: _phoneFocus,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.start,
                  onChanged: (v) => setState(() => _phoneOk = _validate(v)),
                  onSubmitted: (_) => _sendOtp(),
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF1C1C28),
                  ),
                  decoration: InputDecoration(
                    hintText: l10n.phoneLoginPhoneHint,
                    hintStyle: const TextStyle(
                        color: Color(0xFF9A9AA8), fontSize: 14),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    suffixIcon: _phoneOk == true
                        ? const Padding(
                            padding: EdgeInsets.only(left: 10),
                            child: Icon(Icons.check_circle_rounded,
                                color: Brand.success, size: 18),
                          )
                        : null,
                    suffixIconConstraints: const BoxConstraints(minWidth: 0),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Primary CTA — gradient + pulse + shimmer ─────────────────────────────
  Widget _buildCTAButton(AppLocalizations l10n) {
    return AnimatedBuilder(
      animation: Listenable.merge([_ctaPulseCtrl, _shimmerCtrl]),
      builder: (_, __) {
        final pulseT = _ctaPulseCtrl.value;
        // Pulse interpolates between "resting" shadow and "expanded" shadow
        final blur = 20 + pulseT * 12;
        final spread = pulseT * 6;
        final pulseAlpha = (0.42 * (1 - pulseT)).clamp(0.0, 0.42);

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: _kPrimary.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: _kPrimary.withValues(alpha: pulseAlpha),
                blurRadius: blur,
                spreadRadius: spread,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _isLoading ? null : _sendOtp,
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_kPrimary, _kPrimaryDark],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Shimmer overlay
                      if (!_isLoading)
                        Positioned.fill(
                          child: Transform.translate(
                            offset: Offset(
                              (_shimmerCtrl.value * 400) - 200,
                              0,
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Colors.white.withValues(alpha: 0),
                                    Colors.white.withValues(alpha: 0.16),
                                    Colors.white.withValues(alpha: 0),
                                  ],
                                  stops: const [0.0, 0.5, 1.0],
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Content
                      if (_isLoading)
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.2,
                          ),
                        )
                      else
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l10n.phoneLoginCtaLogin,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.arrow_back_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Terms text with tappable links ───────────────────────────────────────
  Widget _buildTermsText(AppLocalizations l10n) {
    return Text.rich(
      TextSpan(
        style: const TextStyle(
          fontSize: 10,
          color: Color(0xFF9A9AA8),
          height: 1.6,
          fontWeight: FontWeight.w400,
        ),
        children: [
          TextSpan(text: '${l10n.phoneLoginTermsPrefix} '),
          _linkSpan(l10n.phoneLoginTermsOfUse, _openTerms),
          TextSpan(text: ' ${l10n.phoneLoginAnd} '),
          _linkSpan(l10n.phoneLoginPrivacyPolicy, _openTerms),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  InlineSpan _linkSpan(String text, VoidCallback onTap) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10,
            color: _kPrimary,
            fontWeight: FontWeight.w500,
            height: 1.6,
          ),
        ),
      ),
    );
  }

  void _openTerms() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const TermsOfServiceScreen(showAcceptButton: false),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 3. BOTTOM STRIP — "Offering service? Earn with AnySkill →"
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBottomStrip(AppLocalizations l10n) {
    return _buildStagger(
      delay: 0.48,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ProviderRegistrationWizardScreen(),
              ),
            );
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFAFAFF), Color(0xFFF0EEF9)],
              ),
              border: const Border(
                top: BorderSide(color: Color(0xFFEEEDFE), width: 0.5),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.badge_outlined, size: 14, color: _kPrimary),
                const SizedBox(width: 6),
                Text(
                  l10n.phoneLoginOfferingService,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF5A5A68),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  l10n.phoneLoginBecomeProvider,
                  style: TextStyle(
                    fontSize: 11,
                    color: _kPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Stagger animation helper — fadeInUp with delay
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStagger({required double delay, required Widget child}) {
    // Each item: 700ms slide-in, starting at delay*totalDuration
    final begin = delay.clamp(0.0, 1.0);
    final end = (delay + 0.54).clamp(0.0, 1.0);
    final anim = CurvedAnimation(
      parent: _staggerCtrl,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) {
        return Opacity(
          opacity: anim.value,
          child: Transform.translate(
            offset: Offset(0, (1 - anim.value) * 14),
            child: child,
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Social sign-in — Google + Apple (preserved from original)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _loginGoogle() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      // ignore: avoid_print
      print('🔍 [Google] Starting GoogleSignIn flow (unified)...');

      final googleSignIn = kIsWeb
          ? GoogleSignIn(
              clientId: '281981409319-nck912ajndlmnagiiqm32mdahferap04.apps.googleusercontent.com',
              scopes: ['email', 'profile'],
            )
          : GoogleSignIn();

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        // ignore: avoid_print
        print('ℹ️ [Google] User cancelled');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // ignore: avoid_print
      print('✅ [Google] Got Google account: ${googleUser.email}');

      final googleAuth = await googleUser.authentication;
      // ignore: avoid_print
      print('✅ [Google] Got tokens: idToken=${googleAuth.idToken != null}, accessToken=${googleAuth.accessToken != null}');

      final cred = await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        ),
      );
      // ignore: avoid_print
      print('✅ [Google] Firebase signIn SUCCESS: uid=${cred.user?.uid}');

      unawaited(_createProfileIfNew(cred));
    } on FirebaseAuthException catch (e) {
      // ignore: avoid_print
      print('🔴 [Google] FirebaseAuthException: code=${e.code}, message=${e.message}');
      if (mounted) _snack(AppLocalizations.of(context).phoneLoginError(e.code), _kRed);
    } catch (e) {
      // ignore: avoid_print
      print('🔴 [Google] Error: ${e.runtimeType}: $e');
      final msg = e.toString();
      if (mounted && !msg.contains('cancel') && !msg.contains('popup_closed')
          && !msg.contains('popup-closed')) {
        _snack(msg.length > 200 ? msg.substring(0, 200) : msg, _kRed);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loginApple() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      if (kIsWeb) {
        // ignore: avoid_print
        print('🔍 [Apple] Web: calling signInWithPopup(apple.com)...');
        // ignore: avoid_print
        print('   authDomain: ${FirebaseAuth.instance.app.options.authDomain}');

        final provider = OAuthProvider('apple.com')
          ..addScope('email')
          ..addScope('name');

        final cred = await FirebaseAuth.instance.signInWithPopup(provider);
        // ignore: avoid_print
        print('✅ [Apple] signInWithPopup SUCCESS: uid=${cred.user?.uid}');

        unawaited(_createProfileIfNew(cred));
        return;
      }

      // ignore: avoid_print
      print('🔍 [Apple] Native: starting Apple Sign-In...');

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

      // ignore: avoid_print
      print('✅ [Apple] Got Apple credential');

      final cred = await FirebaseAuth.instance.signInWithCredential(oauthCredential);
      // ignore: avoid_print
      print('✅ [Apple] Firebase signIn SUCCESS: uid=${cred.user?.uid}');

      final user = cred.user!;
      String displayName = user.displayName ?? '';
      if (displayName.isEmpty) {
        final given  = appleCredential.givenName ?? '';
        final family = appleCredential.familyName ?? '';
        displayName  = '$given $family'.trim();
      }
      if (displayName.isNotEmpty && (user.displayName ?? '').isEmpty) {
        await user.updateDisplayName(displayName);
      }

      unawaited(_createProfileIfNew(cred));
    } on FirebaseAuthException catch (e) {
      // ignore: avoid_print
      print('🔴 [Apple] FirebaseAuthException: code=${e.code}, message=${e.message}');
      if (mounted) _snack(AppLocalizations.of(context).phoneLoginError(e.code), _kRed);
    } catch (e) {
      // ignore: avoid_print
      print('🔴 [Apple] Error: ${e.runtimeType}: $e');
      final msg = e.toString();
      if (mounted && !msg.contains('cancel') && !msg.contains('AuthorizationErrorCode.canceled')) {
        _snack(msg.length > 200 ? msg.substring(0, 200) : msg, _kRed);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Shared: create Firestore profile for new social users ─────────────

  /// Returns `true` if the profile was created/updated and it is safe to
  /// navigate forward. Returns `false` if the Anti-Duplicate Guard found an
  /// existing user doc with the same email under a different uid — in that
  /// case the user has already been signed out and shown the conflict
  /// dialog, so the caller MUST stop the flow (no navigation).
  Future<bool> _createProfileIfNew(UserCredential cred) async {
    final user = cred.user!;

    // ignore: avoid_print
    print('📝 [Profile] uid=${user.uid}, email=${user.email}');

    // PR-A Anti-Duplicate Guard — block if email is already used by another uid.
    if (mounted) {
      final safe = await AuthDuplicateGuard.enforceOrSignOut(
        context: context,
        cred: cred,
      );
      if (!safe) return false;
    }

    await user.getIdToken(true);
    // ignore: avoid_print
    print('📝 [Profile] Token refreshed');

    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

    // v12.8.0 — CRITICAL: do NOT overwrite an existing profile on re-login.
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        // ignore: avoid_print
        print('📝 [Profile] Attempt $attempt — checking existing doc');
        final existing =
            await docRef.get().timeout(const Duration(seconds: 5));
        if (existing.exists) {
          // ignore: avoid_print
          print('✅ [Profile] Existing doc preserved as-is (no overwrite).');
          unawaited(PrivateDataService.writeContactData(
            user.uid,
            phone: user.phoneNumber ?? '',
            email: user.email ?? '',
          ));
          return true;
        }
        // ignore: avoid_print
        print('📝 [Profile] First-time doc create for ${user.uid}');
        await docRef.set({
          'uid':            user.uid,
          'name':           user.displayName ?? '',
          'email':          user.email ?? '',
          'phone':          user.phoneNumber ?? '',
          'rating':         5.0,
          'reviewsCount':   0,
          'pricePerHour':   0.0,
          'serviceType':    '',
          'aboutMe':        '',
          'profileImage':   user.photoURL ?? '',
          'gallery':        [],
          'quickTags':      [],
          'isOnline':       true,
          'isCustomer':     true,
          'isProvider':     false,
          'termsAccepted':  true,
          'onboardingComplete': false,
          'tourComplete':   false,
          'createdAt':      FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 5));
        unawaited(PrivateDataService.writeContactData(
          user.uid,
          phone: user.phoneNumber ?? '',
          email: user.email ?? '',
        ));
        // ignore: avoid_print
        print('✅ [Profile] First-time doc created on attempt $attempt');
        return true;
      } catch (e) {
        // ignore: avoid_print
        print('🔴 [Profile] Attempt $attempt FAILED: ${e.runtimeType}: $e');
        if (attempt < 3) {
          await Future.delayed(Duration(milliseconds: 800 * attempt));
          await user.getIdToken(true);
        } else {
          // ignore: avoid_print
          print('🔴 [Profile] All attempts failed — user will see onboarding');
        }
      }
    }
    return true;
  }

  static String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = math.Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Language dropdown (shown via Overlay from language button)
// ─────────────────────────────────────────────────────────────────────────────
class _LanguageDropdown extends StatefulWidget {
  const _LanguageDropdown({required this.onPick});
  final ValueChanged<Locale> onPick;

  @override
  State<_LanguageDropdown> createState() => _LanguageDropdownState();
}

class _LanguageDropdownState extends State<_LanguageDropdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final current = LocaleProvider.instance.locale;
    final items = <_LangItem>[
      _LangItem('he', '🇮🇱', l10n.languageHe, const Locale('he')),
      _LangItem('en', '🇺🇸', l10n.languageEn, const Locale('en')),
      _LangItem('ar', '🇸🇦', l10n.languageAr, const Locale('ar')),
      _LangItem('es', '🇪🇸', l10n.languageEs, const Locale('es')),
    ];
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = Curves.easeOutCubic.transform(_ctrl.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * -6),
            child: Transform.scale(
              scale: 0.96 + t * 0.04,
              alignment: AlignmentDirectional.topEnd,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 160),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: items.map((item) {
                        final selected =
                            current.languageCode == item.code;
                        return InkWell(
                          onTap: () => widget.onPick(item.locale),
                          child: Container(
                            color: selected
                                ? const Color(0xFFEEEDFE)
                                : Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                Text(item.flag,
                                    style: const TextStyle(fontSize: 14)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    item.label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: selected
                                          ? FontWeight.w500
                                          : FontWeight.w400,
                                      color: const Color(0xFF1C1C28),
                                    ),
                                  ),
                                ),
                                if (selected)
                                  Icon(Icons.check_rounded,
                                      color: _kPrimary, size: 14),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LangItem {
  final String code;
  final String flag;
  final String label;
  final Locale locale;
  _LangItem(this.code, this.flag, this.label, this.locale);
}

// ─────────────────────────────────────────────────────────────────────────────
// Google logo painter
// ─────────────────────────────────────────────────────────────────────────────
class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    canvas.drawArc(Rect.fromLTWH(0, 0, s, s), -0.5, 1.8,
        true, Paint()..color = const Color(0xFF4285F4));
    canvas.drawArc(Rect.fromLTWH(0, 0, s, s), 1.3, 1.2,
        true, Paint()..color = const Color(0xFF34A853));
    canvas.drawArc(Rect.fromLTWH(0, 0, s, s), 2.5, 1.0,
        true, Paint()..color = const Color(0xFFFBBC05));
    canvas.drawArc(Rect.fromLTWH(0, 0, s, s), 3.5, 1.1,
        true, Paint()..color = const Color(0xFFEA4335));
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
          Text(AppLocalizations.of(context).phoneLoginSelectCountry,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
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
                        color: isSelected ? Brand.indigo : Colors.black87,
                      )),
                  trailing: Text(c.dialCode,
                      style: TextStyle(
                        color: isSelected ? Brand.indigo : Colors.grey[600],
                        fontWeight: FontWeight.w600,
                      )),
                  selected: isSelected,
                  selectedTileColor: Brand.indigo.withValues(alpha: 0.06),
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
