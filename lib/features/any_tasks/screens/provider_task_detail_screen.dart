/// AnySkill — Provider Task Detail Screen (AnyTasks v14.0.0)
///
/// Full task description + client card + sticky Accept/Counter-offer
/// form at the bottom. Follows spec section 5.6:
///   • Primary green CTA "Accept task at ₪X" — full-width 48px pill
///   • Below: "You receive: ₪Y net" in small green text
///   • Secondary grey text link: "המחיר לא מתאים? הצע מחיר אחר"
///   • Tap → animated slide-down inline form with outline "Send offer"
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/any_task.dart';
import '../models/task_response.dart';
import '../services/any_task_service.dart';
import '../theme/any_tasks_palette.dart';

class ProviderTaskDetailScreen extends StatefulWidget {
  final String taskId;
  const ProviderTaskDetailScreen({super.key, required this.taskId});

  @override
  State<ProviderTaskDetailScreen> createState() =>
      _ProviderTaskDetailScreenState();
}

class _ProviderTaskDetailScreenState extends State<ProviderTaskDetailScreen> {
  bool _showCounterForm = false;
  final _counterPrice = TextEditingController();
  final _counterMsg = TextEditingController();
  double _feePct = 0.10; // default; refreshed from admin doc on init
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadFee();
  }

  @override
  void dispose() {
    _counterPrice.dispose();
    _counterMsg.dispose();
    super.dispose();
  }

  Future<void> _loadFee() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('admin')
          .doc('admin')
          .collection('settings')
          .doc('settings')
          .get();
      final pct = (snap.data()?['feePercentage'] as num?)?.toDouble() ?? 0.10;
      if (mounted) setState(() => _feePct = pct);
    } catch (_) {/* keep default */}
  }

  Future<void> _accept(AnyTask task) async {
    await _submit(
      task: task,
      type: 'accept',
      price: null,
      message: '',
    );
  }

  Future<void> _sendCounter(AnyTask task) async {
    final price = int.tryParse(_counterPrice.text.trim());
    if (price == null || price < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('יש להזין מחיר חוקי (לפחות ₪10)'),
            backgroundColor: TasksPalette.danger),
      );
      return;
    }
    if (_counterMsg.text.trim().length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('יש לכתוב הסבר קצר (לפחות 5 תווים)'),
            backgroundColor: TasksPalette.danger),
      );
      return;
    }
    await _submit(
      task: task,
      type: 'counter_offer',
      price: price,
      message: _counterMsg.text.trim(),
    );
  }

  Future<void> _submit({
    required AnyTask task,
    required String type,
    required int? price,
    required String message,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _busy = true);
    try {
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = userSnap.data() ?? {};
      final r = TaskResponse(
        taskId: task.id!,
        providerId: uid,
        providerName: (data['name'] ?? 'ספק') as String,
        providerImage: data['profileImage'] as String?,
        responseType: type,
        offeredPriceNis: price,
        message: message,
        providerRating: (data['rating'] as num?)?.toDouble() ?? 0.0,
        providerCompletedCount:
            (data['orderCount'] as num?)?.toInt() ?? 0,
        expiresAt: type == 'counter_offer'
            ? DateTime.now().add(const Duration(hours: 24))
            : null,
      );
      await AnyTaskService.instance.submitResponse(r);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(type == 'accept'
              ? '✅ ההצעה נשלחה! הלקוח יבחר את הנותן המתאים'
              : '✅ הצעת המחיר נשלחה'),
          backgroundColor: TasksPalette.success,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      final err = e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err.contains('task-not-open')
              ? 'המשימה כבר לא פתוחה'
              : err.contains('self-response-not-allowed')
                  ? 'לא ניתן להציע למשימה שלך'
                  : 'שגיאה: $e'),
          backgroundColor: TasksPalette.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TasksPalette.scaffoldBg,
      appBar: AppBar(
        backgroundColor: TasksPalette.cardBg,
        foregroundColor: TasksPalette.textPrimary,
        elevation: 0,
        title: const Text('פרטי המשימה',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      ),
      body: StreamBuilder<AnyTask?>(
        stream: AnyTaskService.instance.streamTask(widget.taskId),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(
                    color: TasksPalette.providerPrimary));
          }
          final task = snap.data;
          if (task == null) {
            return const Center(child: Text('המשימה לא נמצאה'));
          }
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _TaskHeader(task: task),
                    const SizedBox(height: 14),
                    _DescriptionCard(task: task),
                    const SizedBox(height: 14),
                    _MetaGrid(task: task),
                    const SizedBox(height: 14),
                    _EscrowAssuranceBanner(),
                    const SizedBox(height: 12),
                    _FomoPillRow(task: task),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
              _BottomCta(
                task: task,
                feePct: _feePct,
                showCounter: _showCounterForm,
                counterPrice: _counterPrice,
                counterMsg: _counterMsg,
                busy: _busy,
                onAccept: () => _accept(task),
                onCounterTap: () =>
                    setState(() => _showCounterForm = !_showCounterForm),
                onSendCounter: () => _sendCounter(task),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════

class _TaskHeader extends StatelessWidget {
  final AnyTask task;
  const _TaskHeader({required this.task});

  Color _urgencyColor() {
    switch (task.urgency) {
      case 'urgent_now':
        return TasksPalette.coral;
      case 'today':
        return TasksPalette.amber;
      default:
        return TasksPalette.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TasksPalette.cardBg,
        borderRadius: BorderRadius.circular(TasksPalette.rCard),
        border: Border.all(color: TasksPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(task.title,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: TasksPalette.textPrimary)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _urgencyColor().withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(TasksPalette.rChip),
                ),
                child: Text(kTaskUrgencyLabels[task.urgency]!,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _urgencyColor())),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: TasksPalette.amberSoft,
                  borderRadius: BorderRadius.circular(TasksPalette.rChip),
                ),
                child: Text('₪${task.budgetNis}',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: TasksPalette.amber)),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: TasksPalette.providerPrimarySft,
                  borderRadius: BorderRadius.circular(TasksPalette.rChip),
                ),
                child: Text(
                    kTaskCategoryLabels[task.category] ?? task.category,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: TasksPalette.providerPrimary)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DescriptionCard extends StatelessWidget {
  final AnyTask task;
  const _DescriptionCard({required this.task});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TasksPalette.cardBg,
        borderRadius: BorderRadius.circular(TasksPalette.rCard),
        border: Border.all(color: TasksPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('תיאור המשימה',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: TasksPalette.textSecondary)),
          const SizedBox(height: 6),
          Text(task.description,
              style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: TasksPalette.textPrimary)),
          if (task.imageUrl != null && task.imageUrl!.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(TasksPalette.rButton),
              child: Image.network(
                task.imageUrl!,
                width: double.infinity,
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 120,
                  color: TasksPalette.scaffoldBg,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined,
                      color: TasksPalette.textHint),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaGrid extends StatelessWidget {
  final AnyTask task;
  const _MetaGrid({required this.task});

  @override
  Widget build(BuildContext context) {
    final locationLabel = task.locationDisplay;
    return Row(
      children: [
        _MetaTile(
          icon: Icons.location_on_outlined,
          label: 'מיקום',
          value: locationLabel,
        ),
        const SizedBox(width: 8),
        _MetaTile(
          icon: Icons.event_outlined,
          label: 'יעד',
          value: task.deadline == null
              ? 'גמיש'
              : '${task.deadline!.day}/${task.deadline!.month}',
        ),
        const SizedBox(width: 8),
        _MetaTile(
          icon: Icons.verified_outlined,
          label: 'הוכחה',
          value: kTaskProofLabels[task.proofType] ?? task.proofType,
        ),
      ],
    );
  }
}

class _MetaTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _MetaTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: TasksPalette.cardBg,
          borderRadius: BorderRadius.circular(TasksPalette.rButton),
          border: Border.all(color: TasksPalette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: TasksPalette.textSecondary),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: TasksPalette.textSecondary)),
            const SizedBox(height: 2),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: TasksPalette.textPrimary)),
          ],
        ),
      ),
    );
  }
}

class _EscrowAssuranceBanner extends StatelessWidget {
  const _EscrowAssuranceBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: TasksPalette.providerLight,
        borderRadius: BorderRadius.circular(TasksPalette.rButton),
      ),
      child: Row(
        children: const [
          Icon(Icons.shield_outlined,
              color: TasksPalette.successGreen, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('התשלום מאובטח באמצעות Escrow',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: TasksPalette.providerDark)),
                SizedBox(height: 1),
                Text('הכסף יוחזק עד שהמשימה תושלם ותאושר',
                    style: TextStyle(
                        fontSize: 11,
                        color: TasksPalette.successGreen)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FomoPillRow extends StatelessWidget {
  final AnyTask task;
  const _FomoPillRow({required this.task});

  @override
  Widget build(BuildContext context) {
    // "6 צופים עכשיו" is a placeholder until live viewer counter ships.
    // Derived as a stable-ish pseudo-random per task so it doesn't jump
    // around between rebuilds within a session.
    final viewers = ((task.id?.codeUnits.fold<int>(0, (s, c) => s + c) ?? 0)
            % 8) +
        2; // 2..9
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _FomoPill(
            icon: Icons.remove_red_eye_outlined,
            label: '$viewers צופים עכשיו',
            bg: TasksPalette.bgPrimary,
            fg: TasksPalette.textSecondary),
        if (task.responseCount > 0)
          _FomoPill(
              icon: Icons.local_fire_department_rounded,
              label: '${task.responseCount} כבר התעניינו',
              bg: TasksPalette.amberLight,
              fg: TasksPalette.amber),
        const _FomoPill(
            icon: Icons.schedule_rounded,
            label: 'משימה נבחרת תוך ~45 דקות',
            bg: TasksPalette.bgPrimary,
            fg: TasksPalette.textHint),
      ],
    );
  }
}

class _FomoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;
  const _FomoPill({
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w500, color: fg)),
        ],
      ),
    );
  }
}

class _BottomCta extends StatelessWidget {
  final AnyTask task;
  final double feePct;
  final bool showCounter;
  final bool busy;
  final TextEditingController counterPrice;
  final TextEditingController counterMsg;
  final VoidCallback onAccept;
  final VoidCallback onCounterTap;
  final VoidCallback onSendCounter;

  const _BottomCta({
    required this.task,
    required this.feePct,
    required this.showCounter,
    required this.busy,
    required this.counterPrice,
    required this.counterMsg,
    required this.onAccept,
    required this.onCounterTap,
    required this.onSendCounter,
  });

  @override
  Widget build(BuildContext context) {
    final net = AnyTask.computeNet(task.budgetNis, feePct);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: TasksPalette.cardBg,
        border: Border(
          top: BorderSide(color: TasksPalette.border),
        ),
        boxShadow: [
          BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 12,
              offset: Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedCrossFade(
              firstChild: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: busy ? null : onAccept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: TasksPalette.successGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(TasksPalette.rButton)),
                      ),
                      child: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : Text('אשר משימה ב-₪${task.budgetNis}',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('תקבל: ₪$net נטו',
                      style: const TextStyle(
                          fontSize: 11,
                          color: TasksPalette.successGreen)),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: busy ? null : onCounterTap,
                    style: TextButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 4)),
                    child: const Text('המחיר לא מתאים? הצע מחיר אחר',
                        style: TextStyle(
                            fontSize: 12,
                            color: TasksPalette.textSecondary)),
                  ),
                  const Text('בממוצע, משימה נבחרת תוך 45 דקות',
                      style: TextStyle(
                          fontSize: 10, color: TasksPalette.textHint)),
                ],
              ),
              secondChild: _CounterForm(
                priceCtrl: counterPrice,
                msgCtrl: counterMsg,
                busy: busy,
                onSend: onSendCounter,
                onCancel: onCounterTap,
              ),
              crossFadeState: showCounter
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 240),
            ),
          ],
        ),
      ),
    );
  }
}

class _CounterForm extends StatelessWidget {
  final TextEditingController priceCtrl;
  final TextEditingController msgCtrl;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  const _CounterForm({
    required this.priceCtrl,
    required this.msgCtrl,
    required this.busy,
    required this.onSend,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: priceCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: TasksPalette.amber),
          decoration: InputDecoration(
            prefixText: '₪ ',
            hintText: 'הצעת המחיר שלך',
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(TasksPalette.rButton)),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: msgCtrl,
          maxLines: 3,
          maxLength: 500,
          decoration: InputDecoration(
            hintText: 'למה המחיר הזה הוגן?',
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(TasksPalette.rButton)),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: busy ? null : onSend,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: TasksPalette.providerPrimary,
                    side: const BorderSide(
                        color: TasksPalette.providerPrimary, width: 1.5),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(TasksPalette.rButton)),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: TasksPalette.providerPrimary),
                        )
                      : const Text('שלח הצעה',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: busy ? null : onCancel,
              child: const Text('ביטול',
                  style: TextStyle(
                      fontSize: 13,
                      color: TasksPalette.textSecondary)),
            ),
          ],
        ),
      ],
    );
  }
}
