// ignore_for_file: use_build_context_synchronously
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' show DateFormat;

// ─── Firebase v2 Cloud Run endpoints (hard-coded, no SDK URL resolution) ─────
// Copied verbatim from Firebase Console → Functions → each function's URL.
// Using these directly bypasses the Firebase Functions Flutter SDK's internal
// URL routing, which falls back to cloudfunctions.net for callable functions.
const _kUrlOnboardProvider     = 'https://onboardprovider-cj73alnlua-uc.a.run.app';
const _kUrlUpdateStripeAccount = 'https://updatestripeaccount-cj73alnlua-uc.a.run.app';

// ─── Palette (matches app-wide indigo theme) ──────────────────────────────────
const _kIndigo   = Color(0xFF6366F1);
const _kIndigoBg = Color(0xFFF0F0FF);
const _kDark     = Color(0xFF1A1A2E);
const _kGrey     = Color(0xFF6B7280);

// ─────────────────────────────────────────────────────────────────────────────
// StripeOnboardingScreen
// Collects provider KYC details (name, DOB, address, ID, IBAN) inside the app
// and submits them directly to Stripe via the updateStripeAccount Cloud Function.
// The user never sees a Stripe page — 100% AnySkill-branded.
// ─────────────────────────────────────────────────────────────────────────────
class StripeOnboardingScreen extends StatefulWidget {
  const StripeOnboardingScreen({super.key});

  @override
  State<StripeOnboardingScreen> createState() => _StripeOnboardingScreenState();
}

class _StripeOnboardingScreenState extends State<StripeOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();

  // ── Controllers ──────────────────────────────────────────────────────────
  final _firstNameCtrl  = TextEditingController();
  final _lastNameCtrl   = TextEditingController();
  final _idCtrl         = TextEditingController();
  final _streetCtrl     = TextEditingController();
  final _cityCtrl       = TextEditingController();
  final _postalCtrl     = TextEditingController();
  final _ibanCtrl       = TextEditingController();

  DateTime? _dob;
  bool      _loading        = false;

  // ── Two-step flow ─────────────────────────────────────────────────────────
  // Step 1: _initAccount() calls onboardProvider → stores stripeAccountId
  // Step 2: _submit()      calls updateStripeAccount with form data
  bool    _showForm        = false; // false = landing, true = KYC form
  String? _stripeAccountId;        // set after step 1 succeeds
  String  _loadingLabel    = 'מכין חשבון…';

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _idCtrl.dispose();
    _streetCtrl.dispose();
    _cityCtrl.dispose();
    _postalCtrl.dispose();
    _ibanCtrl.dispose();
    super.dispose();
  }

  // ── Date picker ───────────────────────────────────────────────────────────
  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(1990, 1, 1),
      firstDate: DateTime(1920),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
      locale: const Locale('he'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _kIndigo,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  // ── Shared helper: POST to a callable function via plain HTTP ─────────────
  // Calls a Firebase v2 Cloud Run function directly by its console URL.
  // Bypasses the Firebase Functions Flutter SDK (which resolves to the old
  // cloudfunctions.net URL and throws minified:kv<void> on web).
  Future<Map<String, dynamic>?> _callFunction(
    String url,
    Map<String, dynamic> payload,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final idToken = await user.getIdToken(true);

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({'data': payload}),
    ).timeout(const Duration(seconds: 20));

    debugPrint('[Stripe] POST $url → ${response.statusCode}');
    final body = jsonDecode(response.body) as Map<String, dynamic>?;
    if (response.statusCode != 200 || body == null) {
      final msg = ((body?['error'] as Map?)?['message'] as String?)
          ?? 'Server error ${response.statusCode}';
      throw Exception(msg);
    }
    return (body['result'] as Map<String, dynamic>?)
        ?? (body['data']   as Map<String, dynamic>?)
        ?? {};
  }

  // ── Step 1: create Stripe account, then show form ─────────────────────────
  Future<void> _initAccount() async {
    setState(() { _loading = true; _loadingLabel = 'מכין חשבון…'; });

    String? accountId;

    // ── Attempt 1: direct POST to Cloud Run URL ────────────────────────────
    try {
      final result = await _callFunction(_kUrlOnboardProvider, {});
      accountId = result?['stripeAccountId']?.toString();
      debugPrint('[Stripe] CF returned accountId: $accountId');
    } catch (cfErr) {
      debugPrint('[Stripe] CF failed: $cfErr — trying Firestore fallback');
    }

    // ── Attempt 2: Firestore hard-sync (runs whenever accountId is still null)
    if (accountId == null || accountId.isEmpty) {
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          final snap = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get(const GetOptions(source: Source.server));
          accountId = (snap.data() ?? {})['stripeAccountId']?.toString();
          if (accountId != null && accountId.isNotEmpty) {
            debugPrint('[Stripe] Hard-sync recovered accountId: $accountId');
          }
        }
      } catch (fsErr) {
        debugPrint('[Stripe] Firestore hard-sync failed: $fsErr');
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);

    if (accountId != null && accountId.isNotEmpty) {
      setState(() { _stripeAccountId = accountId; _showForm = true; });
    } else {
      _showError('לא ניתן להתחבר לשרת התשלומים.\nוודא חיבור לאינטרנט ונסה שוב.');
    }
  }

  // ── Step 2: submit KYC form to Stripe via updateStripeAccount ─────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dob == null) { _showError('נא לבחור תאריך לידה.'); return; }

    setState(() { _loading = true; _loadingLabel = 'שולח פרטים ל-Stripe…'; });
    try {
      final data = await _callFunction(_kUrlUpdateStripeAccount, {
        'stripeAccountId': _stripeAccountId,
        'firstName':       _firstNameCtrl.text.trim(),
        'lastName':        _lastNameCtrl.text.trim(),
        'dobDay':          _dob!.day,
        'dobMonth':        _dob!.month,
        'dobYear':         _dob!.year,
        'idNumber':        _idCtrl.text.trim(),
        'street':          _streetCtrl.text.trim(),
        'city':            _cityCtrl.text.trim(),
        'postalCode':      _postalCtrl.text.trim(),
        'ibanNumber':      _ibanCtrl.text.replaceAll(' ', ''),
      });

      final payoutsEnabled = data?['payoutsEnabled'] == true;
      final remaining = ((data?['requirementsRemaining']) as List?)
                            ?.map((e) => e.toString()).toList() ?? [];
      if (!mounted) return;

      if (payoutsEnabled || remaining.isEmpty) {
        _showSuccess();
      } else {
        _showPendingVerification(remaining);
      }
    } catch (e) {
      if (mounted) _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, textDirection: TextDirection.rtl),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showSuccess() {
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('חשבון הבנק חובר בהצלחה! 🎉',
          textDirection: TextDirection.rtl),
      backgroundColor: Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showPendingVerification(List<String> remaining) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.hourglass_top_rounded, color: _kIndigo),
          SizedBox(width: 8),
          Text('בבדיקה אצל Stripe', style: TextStyle(fontSize: 16)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'הפרטים נשלחו. Stripe עשויה לדרוש אימות נוסף:',
              style: TextStyle(color: _kGrey, fontSize: 13),
            ),
            const SizedBox(height: 12),
            ...remaining.map((r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                const Icon(Icons.circle, size: 6, color: _kIndigo),
                const SizedBox(width: 8),
                Expanded(child: Text(_friendlyRequirement(r),
                    style: const TextStyle(fontSize: 13))),
              ]),
            )),
            const SizedBox(height: 12),
            const Text(
              'תקבל/י התראה באפליקציה כשהאימות יושלם.',
              style: TextStyle(color: _kGrey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(context); Navigator.pop(context, true); },
            child: const Text('הבנתי', style: TextStyle(color: _kIndigo)),
          ),
        ],
      ),
    );
  }

  String _friendlyRequirement(String stripeField) {
    const map = {
      'individual.id_number':              'מספר תעודת זהות',
      'individual.dob.day':                'תאריך לידה',
      'individual.dob.month':              'תאריך לידה',
      'individual.dob.year':               'תאריך לידה',
      'individual.first_name':             'שם פרטי',
      'individual.last_name':              'שם משפחה',
      'individual.address.line1':          'כתובת',
      'individual.address.city':           'עיר',
      'individual.address.postal_code':    'מיקוד',
      'external_account':                  'חשבון בנק / IBAN',
      'tos_acceptance.date':               'אישור תנאי שימוש',
      'business_profile.url':              'אתר אינטרנט',
      'individual.verification.document':  'צילום תעודת זהות / דרכון',
    };
    return map[stripeField] ?? stripeField;
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FF),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0.5,
          leading: IconButton(
            icon: const Icon(Icons.close, color: _kDark),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          title: const Text(
            'חיבור חשבון בנק',
            style: TextStyle(
              color: _kDark,
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
          centerTitle: true,
        ),
        body: _loading
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: _kIndigo),
                    const SizedBox(height: 16),
                    Text(_loadingLabel,
                        style: const TextStyle(color: _kGrey)),
                  ],
                ),
              )
            : !_showForm
                ? _buildLanding()
                : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                  children: [
                    // ── Header ──────────────────────────────────────────
                    _buildInfoBanner(),
                    const SizedBox(height: 24),

                    // ── Section 1: Personal ─────────────────────────────
                    _sectionTitle('פרטים אישיים', Icons.person_outline),
                    const SizedBox(height: 12),
                    _buildCard([
                      Row(children: [
                        Expanded(child: _field(
                          controller: _firstNameCtrl,
                          label: 'שם פרטי',
                          hint: 'ישראל',
                          validator: _requiredValidator,
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: _field(
                          controller: _lastNameCtrl,
                          label: 'שם משפחה',
                          hint: 'ישראלי',
                          validator: _requiredValidator,
                        )),
                      ]),
                      const SizedBox(height: 16),
                      _field(
                        controller: _idCtrl,
                        label: 'תעודת זהות',
                        hint: '123456789',
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly,
                                          LengthLimitingTextInputFormatter(9)],
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'שדה חובה';
                          if (v.length < 7) return 'מספר ת"ז קצר מדי';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      _dobField(),
                    ]),

                    const SizedBox(height: 20),

                    // ── Section 2: Address ──────────────────────────────
                    _sectionTitle('כתובת מגורים', Icons.home_outlined),
                    const SizedBox(height: 12),
                    _buildCard([
                      _field(
                        controller: _streetCtrl,
                        label: 'רחוב ומספר',
                        hint: 'הרצל 10',
                        validator: _requiredValidator,
                      ),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(child: _field(
                          controller: _cityCtrl,
                          label: 'עיר',
                          hint: 'תל אביב',
                          validator: _requiredValidator,
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: _field(
                          controller: _postalCtrl,
                          label: 'מיקוד',
                          hint: '6100000',
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          validator: _requiredValidator,
                        )),
                      ]),
                    ]),

                    const SizedBox(height: 20),

                    // ── Section 3: Bank ─────────────────────────────────
                    _sectionTitle('פרטי חשבון בנק', Icons.account_balance_outlined),
                    const SizedBox(height: 12),
                    _buildCard([
                      _field(
                        controller: _ibanCtrl,
                        label: 'מספר IBAN',
                        hint: 'PT50 0000 0000 0000 0000 0000 0',
                        keyboardType: TextInputType.text,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [_IbanFormatter()],
                        validator: (v) {
                          final clean = (v ?? '').replaceAll(' ', '');
                          if (clean.isEmpty) return 'שדה חובה';
                          if (clean.length < 15) return 'IBAN קצר מדי';
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'הכנס את מספר ה-IBAN כפי שמופיע בחשבון הבנק שלך.',
                        style: TextStyle(fontSize: 12, color: _kGrey),
                        textDirection: TextDirection.rtl,
                      ),
                    ]),

                    const SizedBox(height: 32),

                    // ── Submit button ────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _submit,
                        icon: const Icon(Icons.lock_outline, size: 18),
                        label: const Text(
                          'שלח לאימות מאובטח',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kIndigo,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                    const _StripeBadge(),
                  ],
                ),
              ),
      ),
    );
  }

  // ── Landing screen (Step 1) ───────────────────────────────────────────────
  Widget _buildLanding() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88, height: 88,
            decoration: BoxDecoration(
              color: _kIndigoBg,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.account_balance_outlined,
                color: _kIndigo, size: 44),
          ),
          const SizedBox(height: 28),
          const Text(
            'חיבור חשבון בנק לתשלומים',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: _kDark),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'AnySkill משתמשת ב-Stripe לניהול תשלומים. '
            'תהליך זה מאובטח ומוצפן — הפרטים שלך לא נשמרים אצלנו.',
            style: TextStyle(fontSize: 14, color: _kGrey, height: 1.6),
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 36),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _initAccount,   // ← Step 1 entry point
              icon: const Icon(Icons.arrow_back_ios_new, size: 16),
              label: const Text(
                'התחל הגדרה',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kIndigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _StripeBadge(),
        ],
      ),
    );
  }

  // ── Reusable builders ─────────────────────────────────────────────────────

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kIndigoBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kIndigo.withValues(alpha: 0.25)),
      ),
      child: const Row(
        children: [
          Icon(Icons.shield_outlined, color: _kIndigo, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'הפרטים שלך מוצפנים ומועברים ישירות ל-Stripe. AnySkill לא שומרת פרטי בנק.',
              style: TextStyle(fontSize: 13, color: _kDark, height: 1.4),
              textDirection: TextDirection.rtl,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(children: [
      Icon(icon, color: _kIndigo, size: 20),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(
          fontWeight: FontWeight.bold, fontSize: 15, color: _kDark)),
    ]);
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 8, offset: const Offset(0, 2),
        )],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.words,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      textDirection: TextDirection.ltr,
      inputFormatters: inputFormatters,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: _kGrey, fontSize: 14),
        hintStyle: TextStyle(color: _kGrey.withValues(alpha: 0.5), fontSize: 13),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kIndigo, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.red.shade400),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  Widget _dobField() {
    final label = _dob == null
        ? 'תאריך לידה *'
        : DateFormat('dd/MM/yyyy').format(_dob!);
    return GestureDetector(
      onTap: _pickDob,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(children: [
          const Icon(Icons.calendar_today_outlined, color: _kGrey, size: 18),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: _dob == null ? _kGrey : _kDark,
              fontSize: 14,
            ),
          ),
        ]),
      ),
    );
  }

  String? _requiredValidator(String? v) =>
      (v == null || v.trim().isEmpty) ? 'שדה חובה' : null;
}

// ─── IBAN formatter — groups in blocks of 4, uppercase ────────────────────────
class _IbanFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue old, TextEditingValue next) {
    final clean = next.text.replaceAll(' ', '').toUpperCase();
    final buffer = StringBuffer();
    for (int i = 0; i < clean.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(clean[i]);
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// ─── "Secured by Stripe" badge ────────────────────────────────────────────────
class _StripeBadge extends StatelessWidget {
  const _StripeBadge();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock, size: 13, color: _kGrey.withValues(alpha: 0.7)),
        const SizedBox(width: 4),
        Text(
          'מאובטח על ידי Stripe',
          style: TextStyle(
              fontSize: 12, color: _kGrey.withValues(alpha: 0.7)),
        ),
      ],
    );
  }
}
