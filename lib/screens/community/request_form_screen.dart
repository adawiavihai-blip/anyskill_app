/// Mockup 08 — 3-step form for publishing a new community help request.
///
/// **When this screen is shown:**
/// - From [CommunityHubScreenV2]'s bottom CTA "פרסם בקשה להתנדבות".
///
/// **Steps:**
/// 1. **Content** — title (≤60 chars) + description + category pills.
/// 2. **Audience + urgency** — requester type (elderly / lone_soldier /
///    struggling_family / general) + urgency (normal / this_week / high)
///    + anonymous toggle.
/// 3. **Preview + submit** — read-only summary card; primary CTA calls
///    [CommunityHubService.createRequest]. On success pops back with
///    the new doc id as result.
///
/// **Validation gates** (Hebrew error inline; CTA stays disabled):
/// - Title length ≥ 5 chars and ≤ 60 chars.
/// - Description length ≥ 15 chars.
/// - Category selected.
/// - Requester type selected.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/community_hub_service.dart';
import '../../theme/community_theme.dart';
import '../../widgets/community/pill_chip.dart';
import '../../widgets/community/primary_button.dart';
import '../../widgets/community/secondary_button.dart';

class RequestFormScreen extends StatefulWidget {
  const RequestFormScreen({super.key});

  @override
  State<RequestFormScreen> createState() => _RequestFormScreenState();
}

class _RequestFormScreenState extends State<RequestFormScreen> {
  static const _kMaxTitle = 60;
  static const _kMinTitle = 5;
  static const _kMinDesc  = 15;

  final _titleCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();

  String? _category;
  String? _requesterType;
  String _urgency = 'normal';
  bool _isAnonymous = false;

  int _step = 0; // 0..2
  bool _busy = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // ── Validation per step ────────────────────────────────────────────────
  bool get _step1Valid {
    final titleLen = _titleCtrl.text.trim().length;
    return titleLen >= _kMinTitle &&
        titleLen <= _kMaxTitle &&
        _descCtrl.text.trim().length >= _kMinDesc &&
        _category != null;
  }

  bool get _step2Valid => _requesterType != null;

  bool get _canProceed {
    if (_step == 0) return _step1Valid;
    if (_step == 1) return _step2Valid;
    return true;
  }

  void _next() {
    if (!_canProceed) return;
    if (_step < 2) {
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _step--);
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() => _busy = false);
      return;
    }
    String? requesterImage;
    String requesterName = user.displayName ?? '';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final m = snap.data() ?? {};
      requesterImage = m['profileImage'] as String?;
      final n = (m['name'] as String? ?? '').trim();
      if (n.isNotEmpty) requesterName = n;
    } catch (_) {/* tolerate */}

    final newId = await CommunityHubService.createRequest(
      requesterId: user.uid,
      requesterName: requesterName.isEmpty ? 'משתמש' : requesterName,
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      category: _category!,
      requesterType: _requesterType!,
      urgency: _urgency,
      isAnonymous: _isAnonymous,
      requesterImage: requesterImage,
    );

    if (!mounted) return;
    setState(() => _busy = false);

    if (newId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הבקשה פורסמה ✓',
              style: TextStyle(fontFamily: CommunityType.fontFamily)),
          backgroundColor: CommunityColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(newId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('פרסום הבקשה נכשל. נסה שוב.',
              style: TextStyle(fontFamily: CommunityType.fontFamily)),
          backgroundColor: CommunityColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CommunityColors.primaryWhite,
      body: SafeArea(
        child: Column(
          children: [
            _Header(step: _step + 1, total: 3, onClose: _back),
            _ProgressBar(step: _step),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: KeyedSubtree(
                  key: ValueKey(_step),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
                    child: _buildStepBody(),
                  ),
                ),
              ),
            ),
            _BottomBar(
              step: _step,
              canProceed: _canProceed,
              isBusy: _busy,
              onBack: _step > 0 ? () => setState(() => _step--) : null,
              onNext: _next,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepBody() {
    switch (_step) {
      case 0: return _step1();
      case 1: return _step2();
      default: return _step3();
    }
  }

  // ── Step 1 — content ──────────────────────────────────────────────────
  Widget _step1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('במה אפשר לעזור?', style: CommunityType.h22),
        const SizedBox(height: 6),
        const Text(
          'תאר/י בקצרה. ככל שתפרט/י יותר, מתנדבים יבינו טוב יותר.',
          style: CommunityType.body13,
        ),
        const SizedBox(height: 20),

        // Title
        const _FieldLabel(label: 'כותרת'),
        const SizedBox(height: 8),
        _SoftField(
          controller: _titleCtrl,
          hint: 'תיקון ברז דולף במטבח',
          maxLines: 1,
          counterMax: _kMaxTitle,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),

        // Description
        const _FieldLabel(label: 'תיאור'),
        const SizedBox(height: 8),
        _SoftField(
          controller: _descCtrl,
          hint: 'הסבר/י מה צריך — מקום, ציוד, נסיבות.',
          maxLines: 4,
          minLines: 3,
          onChanged: (_) => setState(() {}),
        ),
        if (_descCtrl.text.trim().isNotEmpty &&
            _descCtrl.text.trim().length < _kMinDesc) ...[
          const SizedBox(height: 6),
          Text(
            'נא לכתוב לפחות $_kMinDesc תווים',
            style: const TextStyle(
              fontFamily: CommunityType.fontFamily,
              fontSize: 11,
              color: CommunityColors.warningText,
            ),
          ),
        ],
        const SizedBox(height: 20),

        // Category
        const _FieldLabel(label: 'קטגוריה'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in CommunityHubService.helpCategories)
              CommunityPillChip(
                label: c['label'] as String,
                selected: _category == c['id'],
                onTap: () => setState(() => _category = c['id'] as String),
              ),
          ],
        ),
      ],
    );
  }

  // ── Step 2 — audience + urgency ────────────────────────────────────────
  Widget _step2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('מי צריך/ה את העזרה?', style: CommunityType.h22),
        const SizedBox(height: 6),
        const Text(
          'נעזור למתנדבים להבין את ההקשר ולהגיע מוכנים.',
          style: CommunityType.body13,
        ),
        const SizedBox(height: 20),

        // Requester type — 4 options as a grid
        const _FieldLabel(label: 'עבור מי הסיוע?'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _typePill('elderly', 'קשישים'),
            _typePill('lone_soldier', 'חיילים בודדים'),
            _typePill('struggling_family', 'משפחות'),
            _typePill('general', 'כללי'),
          ],
        ),

        const SizedBox(height: 22),

        // Urgency — 3-button toggle
        const _FieldLabel(label: 'דחיפות'),
        const SizedBox(height: 12),
        Row(
          children: [
            _urgencyBtn('normal',    'רגיל'),
            const SizedBox(width: 8),
            _urgencyBtn('this_week', 'השבוע'),
            const SizedBox(width: 8),
            _urgencyBtn('high',      'דחוף'),
          ],
        ),

        const SizedBox(height: 22),

        // Anonymous toggle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: CommunityDecorations.cardSoft,
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'בקשה אנונימית',
                      style: TextStyle(
                        fontFamily: CommunityType.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                        color: CommunityColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'השם שלך לא יוצג למתנדבים',
                      style: TextStyle(
                        fontFamily: CommunityType.fontFamily,
                        fontSize: 11,
                        color: CommunityColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _isAnonymous,
                onChanged: (v) => setState(() => _isAnonymous = v),
                activeColor: CommunityColors.primaryBlack,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _typePill(String id, String label) {
    return CommunityPillChip(
      label: label,
      selected: _requesterType == id,
      onTap: () => setState(() => _requesterType = id),
    );
  }

  Widget _urgencyBtn(String id, String label) {
    final isSel = _urgency == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _urgency = id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSel
                ? CommunityColors.primaryBlack
                : CommunityColors.primaryWhite,
            border: isSel
                ? null
                : Border.all(color: const Color(0x1F000000), width: 0.5),
            borderRadius: const BorderRadius.all(CommunityRadius.field),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: CommunityType.fontFamily,
              fontSize: 12,
              fontWeight: isSel ? FontWeight.w500 : FontWeight.w400,
              letterSpacing: -0.1,
              color: isSel
                  ? CommunityColors.primaryWhite
                  : CommunityColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  // ── Step 3 — preview + submit ─────────────────────────────────────────
  Widget _step3() {
    final cat = CommunityHubService.helpCategories
            .firstWhere((c) => c['id'] == _category, orElse: () => const {})['label']
        as String? ??
        '';
    final type = _requesterTypeLabel(_requesterType ?? '');
    final urgencyLabel = _urgencyLabel(_urgency);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('סיכום הבקשה', style: CommunityType.h22),
        const SizedBox(height: 6),
        const Text(
          'בדוק/י את הפרטים. אחרי הפרסום הבקשה גלויה למתנדבים פעילים.',
          style: CommunityType.body13,
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: CommunityDecorations.cardSoft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_urgency == 'high') ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: CommunityColors.dangerBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'דחוף',
                    style: TextStyle(
                      fontFamily: CommunityType.fontFamily,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                      color: CommunityColors.danger,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Text(_titleCtrl.text.trim(), style: CommunityType.title15),
              const SizedBox(height: 6),
              Text(_descCtrl.text.trim(), style: CommunityType.body13),
              const Divider(height: 24, color: CommunityColors.borderSubtle),
              _summaryRow('קטגוריה', cat),
              _summaryRow('עבור מי', type),
              _summaryRow('דחיפות', urgencyLabel),
              _summaryRow(
                'אנונימי',
                _isAnonymous ? 'כן' : 'לא',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              key,
              style: const TextStyle(
                fontFamily: CommunityType.fontFamily,
                fontSize: 11,
                color: CommunityColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(
                fontFamily: CommunityType.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
                color: CommunityColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _requesterTypeLabel(String id) {
    switch (id) {
      case 'elderly':            return 'קשישים';
      case 'lone_soldier':       return 'חיילים בודדים';
      case 'struggling_family':  return 'משפחות נזקקות';
      case 'general':            return 'כללי';
      default:                   return id;
    }
  }

  static String _urgencyLabel(String id) {
    switch (id) {
      case 'high':      return 'דחוף';
      case 'this_week': return 'השבוע';
      case 'normal':    return 'רגיל';
      default:          return id;
    }
  }
}

// ── Header ────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({
    required this.step,
    required this.total,
    required this.onClose,
  });
  final int step;
  final int total;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 12, 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: CommunityColors.borderSofter, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            iconSize: 20,
            color: CommunityColors.textPrimary,
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'בקשת התנדבות',
                style: TextStyle(
                  fontFamily: CommunityType.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1,
                  color: CommunityColors.textPrimary,
                ),
              ),
            ),
          ),
          Text(
            '$step מתוך $total',
            style: const TextStyle(
              fontFamily: CommunityType.fontFamily,
              fontSize: 11,
              color: CommunityColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Top progress bar (3 segments) ─────────────────────────────────────────
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          children: [
            Container(
              height: 2,
              color: const Color(0x0F000000),
            ),
            FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: (step + 1) / 3,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                height: 2,
                color: CommunityColors.primaryBlack,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Field label ───────────────────────────────────────────────────────────
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontFamily: CommunityType.fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
        color: CommunityColors.textPrimary,
      ),
    );
  }
}

// ── Soft field with optional counter ──────────────────────────────────────
class _SoftField extends StatelessWidget {
  const _SoftField({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.minLines,
    this.counterMax,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final int? minLines;
  final int? counterMax;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CommunityColors.surface,
        border: Border.all(color: const Color(0x14000000), width: 0.5),
        borderRadius: const BorderRadius.all(CommunityRadius.field),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TextField(
            controller: controller,
            maxLines: maxLines,
            minLines: minLines,
            maxLength: counterMax,
            onChanged: onChanged,
            style: const TextStyle(
              fontFamily: CommunityType.fontFamily,
              fontSize: 14,
              color: CommunityColors.textPrimary,
              height: 1.55,
              letterSpacing: -0.1,
            ),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              counterText: '',
              hintText: hint,
              hintStyle: const TextStyle(
                fontFamily: CommunityType.fontFamily,
                fontSize: 14,
                color: CommunityColors.textMuted,
              ),
            ),
          ),
          if (counterMax != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${controller.text.length}/$counterMax',
                style: const TextStyle(
                  fontFamily: CommunityType.fontFamily,
                  fontSize: 10,
                  color: CommunityColors.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Bottom bar ────────────────────────────────────────────────────────────
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.step,
    required this.canProceed,
    required this.isBusy,
    required this.onBack,
    required this.onNext,
  });

  final int step;
  final bool canProceed;
  final bool isBusy;
  final VoidCallback? onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final primaryLabel = step == 2 ? 'פרסם בקשה' : 'המשך';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: CommunityDecorations.footerWithTopDivider,
      child: Row(
        children: [
          if (onBack != null) ...[
            CommunitySecondaryButton(
              label: 'הקודם',
              onPressed: isBusy ? null : onBack,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: CommunityPrimaryButton(
              label: primaryLabel,
              isLoading: isBusy,
              onPressed: canProceed ? onNext : null,
            ),
          ),
        ],
      ),
    );
  }
}
