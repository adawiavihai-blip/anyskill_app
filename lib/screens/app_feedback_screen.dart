// AnySkill Feedback & Ideas screen (v15.x, 2026-04-18).
//
// Dedicated product-feedback surface opened from the Profile tab. Writes to a
// new `app_feedback` collection — NOT `support_tickets` (those are for
// support/bug issues per §16). A Firestore-onCreate Cloud Function
// (`analyzeFeedbackOnCreate`) adds Gemini-driven `priority` + `topic` tags,
// and a weekly scheduled CF (`generateFeedbackWeeklyInsight`) summarises the
// top 3 recurring themes for the AI CEO tab.
//
// Design: clean, premium, light theme (Brand.* tokens — no scoped palette).
// Matches the app's shared Material 3 aesthetic.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../utils/error_mapper.dart';

/// Four feedback categories shown as selectable chips on the form.
/// Stored in Firestore as snake_case IDs for easy aggregation.
class _FeedbackCategory {
  final String id;
  final String labelHe;
  final IconData icon;
  final Color color;
  const _FeedbackCategory({
    required this.id,
    required this.labelHe,
    required this.icon,
    required this.color,
  });
}

const List<_FeedbackCategory> _kCategories = [
  _FeedbackCategory(
    id: 'app_interface',
    labelHe: 'ממשק האפליקציה',
    icon: Icons.design_services_rounded,
    color: Brand.indigo,
  ),
  _FeedbackCategory(
    id: 'payment_process',
    labelHe: 'תהליך התשלום',
    icon: Icons.payments_rounded,
    color: Brand.success,
  ),
  _FeedbackCategory(
    id: 'new_feature_idea',
    labelHe: 'רעיון לפיצ\'ר חדש',
    icon: Icons.lightbulb_rounded,
    color: Brand.warning,
  ),
  _FeedbackCategory(
    id: 'other',
    labelHe: 'אחר',
    icon: Icons.chat_bubble_rounded,
    color: Brand.purple,
  ),
];

class AppFeedbackScreen extends StatefulWidget {
  const AppFeedbackScreen({super.key});

  @override
  State<AppFeedbackScreen> createState() => _AppFeedbackScreenState();
}

class _AppFeedbackScreenState extends State<AppFeedbackScreen> {
  static const int _maxChars = 500;

  String _selectedCategory = 'app_interface';
  int? _npsScore;
  final TextEditingController _contentCtrl = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _contentCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting &&
      _contentCtrl.text.trim().length >= 10 &&
      _npsScore != null;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _submitting = false);
      ErrorMapper.show(context, 'unauthenticated');
      return;
    }
    try {
      // Read the role from the user doc so we can analyse
      // provider-vs-customer themes separately in the weekly digest.
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = userSnap.data() ?? {};
      final isProvider = data['isProvider'] == true;
      final userRole = isProvider ? 'provider' : 'customer';

      await FirebaseFirestore.instance.collection('app_feedback').add({
        'uid': user.uid,
        'userRole': userRole,
        'userName': data['name'] ?? '',
        'userEmail': user.email ?? data['email'] ?? '',
        'category': _selectedCategory,
        'content': _contentCtrl.text.trim(),
        'npsScore': _npsScore,
        'status': 'pending',
        'priority': null, // filled by analyzeFeedbackOnCreate CF
        'topic': null, // filled by analyzeFeedbackOnCreate CF
        'createdAt': FieldValue.serverTimestamp(),
        'appVersion':
            const String.fromEnvironment('APP_VERSION', defaultValue: ''),
        'platform': defaultTargetPlatformName(),
      });
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        _submitted = true;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ErrorMapper.show(context, e);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Brand.scaffoldBg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Brand.textDark,
          elevation: 0,
          shape: Border(
              bottom: BorderSide(
                  color: Brand.textDark.withValues(alpha: 0.08))),
          title: const Text(
            'AnySkill Feedback & Ideas',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: _submitted ? _buildSuccess() : _buildForm(),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SUCCESS VIEW
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSuccess() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (_, v, __) => Transform.scale(
              scale: v,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Brand.indigo, Brand.purple],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Brand.indigo.withValues(alpha: 0.4),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.favorite_rounded,
                    color: Colors.white, size: 44),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'תודה על העזרה!',
            style: TextStyle(
              color: Brand.textDark,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'צוות הפיתוח שלנו קורא אישית כל הצעה\nכדי להפוך את AnySkill לטוב ביותר עבורך.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Brand.textMuted,
              fontSize: 15,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Brand.indigo.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(30),
              border:
                  Border.all(color: Brand.indigo.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_rounded,
                    color: Brand.indigo, size: 18),
                const SizedBox(width: 6),
                const Text(
                  'הפנייה התקבלה ונמצאת בבדיקה',
                  style: TextStyle(
                    color: Brand.indigo,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                side: BorderSide(
                    color: Brand.textDark.withValues(alpha: 0.2)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(
                'חזור לפרופיל',
                style: TextStyle(
                  color: Brand.textDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              // Reset to send another one.
              setState(() {
                _submitted = false;
                _contentCtrl.clear();
                _npsScore = null;
                _selectedCategory = 'app_interface';
              });
            },
            child: Text(
              'שלח הצעה נוספת',
              style: TextStyle(
                color: Brand.indigo,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // FORM
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildIntroCard(),
          const SizedBox(height: 20),
          _sectionTitle('מה הנושא?'),
          const SizedBox(height: 10),
          _buildCategoryChips(),
          const SizedBox(height: 24),
          _sectionTitle('ספר לנו על הרעיון שלך'),
          const SizedBox(height: 10),
          _buildContentField(),
          const SizedBox(height: 24),
          _sectionTitle('עד כמה סביר שתמליץ על AnySkill לחבר?'),
          const SizedBox(height: 4),
          Text(
            '1 = בכלל לא · 10 = בוודאות',
            style: TextStyle(
              color: Brand.textMuted.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          _buildNpsScale(),
          const SizedBox(height: 28),
          _buildSubmitButton(),
          const SizedBox(height: 20),
          _buildPrivacyNote(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildIntroCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Brand.indigo.withValues(alpha: 0.08),
            Brand.purple.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: Brand.indigo.withValues(alpha: 0.2), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Brand.indigo, Brand.purple],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'העזור לנו לבנות את AnySkill',
                  style: TextStyle(
                    color: Brand.textDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'כל הצעה נקראת אישית על ידי צוות הפיתוח.',
                  style: TextStyle(
                    color: Brand.textMuted,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          color: Brand.textDark,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      );

  Widget _buildCategoryChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _kCategories.map((c) {
        final selected = _selectedCategory == c.id;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _selectedCategory = c.id);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? c.color : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color:
                    selected ? c.color : Brand.textDark.withValues(alpha: 0.12),
                width: 1.5,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: c.color.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  c.icon,
                  size: 16,
                  color: selected ? Colors.white : c.color,
                ),
                const SizedBox(width: 6),
                Text(
                  c.labelHe,
                  style: TextStyle(
                    color: selected ? Colors.white : Brand.textDark,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildContentField() {
    final length = _contentCtrl.text.length;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Brand.textDark.withValues(alpha: 0.12), width: 1),
      ),
      child: Column(
        children: [
          TextField(
            controller: _contentCtrl,
            maxLines: 6,
            maxLength: _maxChars,
            textInputAction: TextInputAction.newline,
            style: const TextStyle(
              color: Brand.textDark,
              fontSize: 14,
              height: 1.5,
            ),
            decoration: InputDecoration(
              hintText: 'מה יהפוך את החוויה שלך למושלמת?',
              hintStyle: TextStyle(
                color: Brand.textMuted.withValues(alpha: 0.6),
                fontSize: 14,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
              counterText: '',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Row(
              children: [
                if (length >= 10)
                  Row(
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: Brand.success, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'נשמע מעולה',
                        style: TextStyle(
                          color: Brand.success,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    'לפחות 10 תווים',
                    style: TextStyle(
                      color: Brand.textMuted.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                const Spacer(),
                Text(
                  '$length / $_maxChars',
                  style: TextStyle(
                    color: length >= _maxChars - 20
                        ? Brand.warning
                        : Brand.textMuted.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNpsScale() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Brand.textDark.withValues(alpha: 0.12), width: 1),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(10, (i) {
              final value = i + 1;
              final selected = _npsScore == value;
              final color = _npsColorFor(value);
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _npsScore = value);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 30,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: selected
                        ? LinearGradient(
                            colors: [color, color.withValues(alpha: 0.7)],
                          )
                        : null,
                    color: selected
                        ? null
                        : color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? color
                          : color.withValues(alpha: 0.3),
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      '$value',
                      style: TextStyle(
                        color: selected ? Colors.white : color,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '😕 בכלל לא',
                style: TextStyle(
                  color: Brand.textMuted.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'בוודאות 🤩',
                style: TextStyle(
                  color: Brand.textMuted.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Map 1-10 → red → amber → green for NPS (detractors/passives/promoters).
  Color _npsColorFor(int value) {
    if (value <= 6) return Brand.error;
    if (value <= 8) return Brand.warning;
    return Brand.success;
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _canSubmit ? _submit : null,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          backgroundColor: Brand.indigo,
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              Brand.textDark.withValues(alpha: 0.1),
          elevation: _canSubmit ? 4 : 0,
          shadowColor: Brand.indigo.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
        child: _submitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.send_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'שלח הצעה',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: _canSubmit
                          ? Colors.white
                          : Brand.textMuted.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPrivacyNote() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_rounded,
            size: 14, color: Brand.textMuted.withValues(alpha: 0.6)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'הפנייה שלך מגיעה ישירות לצוות הפיתוח. אנו לא משתפים אותה עם צדדים שלישיים.',
            style: TextStyle(
              color: Brand.textMuted.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

// Top-level helper so we can capture the platform name without
// importing dart:io (breaks on web).
String defaultTargetPlatformName() {
  try {
    return defaultTargetPlatform.name;
  } catch (_) {
    return 'unknown';
  }
}
