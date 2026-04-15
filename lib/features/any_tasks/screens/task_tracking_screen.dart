/// AnySkill — Task Tracking Screen (AnyTasks v14.0.0)
///
/// Client-facing live view of a task in progress. Shows milestone
/// stepper (goal-gradient psychology), selected provider card, proof
/// preview when submitted, and a "אשר השלמה" CTA that flips the task
/// to `completed` and triggers payment release.
library;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../models/any_task.dart';
import '../services/any_task_service.dart';
import '../theme/any_tasks_palette.dart';
import '../widgets/lifecycle_stepper.dart';
import 'task_review_screen.dart';

class TaskTrackingScreen extends StatelessWidget {
  final String taskId;
  const TaskTrackingScreen({super.key, required this.taskId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TasksPalette.scaffoldBg,
      appBar: AppBar(
        backgroundColor: TasksPalette.cardBg,
        foregroundColor: TasksPalette.textPrimary,
        elevation: 0,
        title: const Text('מעקב משימה',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      ),
      body: StreamBuilder<AnyTask?>(
        stream: AnyTaskService.instance.streamTask(taskId),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(
                    color: TasksPalette.clientPrimary));
          }
          final task = snap.data;
          if (task == null) {
            return const Center(child: Text('המשימה לא נמצאה'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _TaskHeader(task: task),
              const SizedBox(height: 14),
              _ProviderCard(task: task),
              const SizedBox(height: 14),
              _LifecycleCard(task: task),
              const SizedBox(height: 14),
              if (task.status == 'proof_submitted') _ProofPreview(task: task),
              const SizedBox(height: 14),
              _EscrowCard(task: task),
              const SizedBox(height: 20),
              if (task.status == 'proof_submitted')
                _ConfirmButton(task: task),
              if (task.status == 'completed') ...[
                const _CompletedBanner(),
                const SizedBox(height: 14),
                _RateButton(task: task, isClientReview: true),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Sub-widgets
// ═══════════════════════════════════════════════════════════════════

class _TaskHeader extends StatelessWidget {
  final AnyTask task;
  const _TaskHeader({required this.task});

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
          Text(task.title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: TasksPalette.textPrimary)),
          const SizedBox(height: 6),
          Text(task.description,
              style: const TextStyle(
                  fontSize: 13, color: TasksPalette.textSecondary)),
          const SizedBox(height: 10),
          Row(
            children: [
              _Chip(
                  icon: Icons.category_outlined,
                  label: kTaskCategoryLabels[task.category] ?? task.category,
                  color: TasksPalette.clientPrimary,
                  bg: TasksPalette.clientPrimarySoft),
              const SizedBox(width: 8),
              _Chip(
                  icon: Icons.payments_outlined,
                  label: '₪${task.agreedPriceNis ?? task.budgetNis}',
                  color: TasksPalette.amber,
                  bg: TasksPalette.amberSoft),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final AnyTask task;
  const _ProviderCard({required this.task});

  @override
  Widget build(BuildContext context) {
    if (task.selectedProviderId == null) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TasksPalette.cardBg,
        borderRadius: BorderRadius.circular(TasksPalette.rCard),
        border: Border.all(color: TasksPalette.border),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 22,
            backgroundColor: TasksPalette.providerPrimarySft,
            child: Icon(Icons.person_rounded,
                color: TasksPalette.providerPrimary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('נותן השירות שלך',
                    style: TextStyle(
                        fontSize: 11, color: TasksPalette.textSecondary)),
                const SizedBox(height: 2),
                Text(task.selectedProviderName ?? '',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: TasksPalette.textPrimary)),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('הודעות יגיעו בשלב הבא'),
                  backgroundColor: TasksPalette.clientPrimary,
                ),
              );
            },
            icon: const Icon(Icons.chat_bubble_outline_rounded,
                color: TasksPalette.clientPrimary),
          ),
        ],
      ),
    );
  }
}

class _LifecycleCard extends StatelessWidget {
  final AnyTask task;
  const _LifecycleCard({required this.task});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TasksPalette.cardWhite,
        borderRadius: BorderRadius.circular(TasksPalette.rCard),
        boxShadow: TasksPalette.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('מעקב משימה',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: TasksPalette.darkNavy)),
          const SizedBox(height: 16),
          TaskLifecycleStepper(task: task),
        ],
      ),
    );
  }
}

class _ProofPreview extends StatelessWidget {
  final AnyTask task;
  const _ProofPreview({required this.task});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TasksPalette.cardBg,
        borderRadius: BorderRadius.circular(TasksPalette.rCard),
        border: Border.all(color: TasksPalette.escrowBlue.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.verified_outlined,
                  color: TasksPalette.escrowBlue, size: 20),
              SizedBox(width: 8),
              Text('הוכחת ביצוע הוגשה',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: TasksPalette.escrowBlue)),
            ],
          ),
          const SizedBox(height: 10),
          if (task.proofUrl != null && task.proofUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(TasksPalette.rButton),
              child: Image.network(
                task.proofUrl!,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 100,
                  color: TasksPalette.scaffoldBg,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined,
                      color: TasksPalette.textHint),
                ),
              ),
            ),
          if (task.proofText != null && task.proofText!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: TasksPalette.scaffoldBg,
                borderRadius: BorderRadius.circular(TasksPalette.rButton),
              ),
              child: Text(task.proofText!,
                  style: const TextStyle(
                      fontSize: 13, color: TasksPalette.textPrimary)),
            ),
          ],
        ],
      ),
    );
  }
}

class _EscrowCard extends StatelessWidget {
  final AnyTask task;
  const _EscrowCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final amount = task.agreedPriceNis ?? task.budgetNis;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TasksPalette.escrowBlueSoft,
        borderRadius: BorderRadius.circular(TasksPalette.rCard),
        border:
            Border.all(color: TasksPalette.escrowBlue.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_rounded,
              color: TasksPalette.escrowBlue, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('₪$amount מוחזקים באסקרו',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: TasksPalette.escrowBlue)),
                const SizedBox(height: 2),
                const Text(
                    'הכסף ישוחרר לנותן השירות רק אחרי שתאשר את השלמת המשימה',
                    style: TextStyle(
                        fontSize: 11,
                        color: TasksPalette.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmButton extends StatefulWidget {
  final AnyTask task;
  const _ConfirmButton({required this.task});

  @override
  State<_ConfirmButton> createState() => _ConfirmButtonState();
}

class _ConfirmButtonState extends State<_ConfirmButton> {
  bool _busy = false;

  Future<void> _confirm() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('אישור השלמה'),
        content: const Text(
            'האם המשימה הושלמה בהצלחה? התשלום ישוחרר מיידית לנותן השירות.',
            style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('עדיין לא')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: TasksPalette.success,
                foregroundColor: Colors.white),
            child: const Text('אשר ושחרר'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('releaseTaskPayment')
          .call({'taskId': widget.task.id});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ התשלום שוחרר. תודה!'),
          backgroundColor: TasksPalette.success,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'שגיאה בשחרור התשלום'),
          backgroundColor: TasksPalette.danger,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('שגיאה: $e'),
            backgroundColor: TasksPalette.danger),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _busy ? null : _confirm,
        style: ElevatedButton.styleFrom(
          backgroundColor: TasksPalette.success,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TasksPalette.rPill),
          ),
        ),
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : const Icon(Icons.check_circle_rounded, size: 20),
        label: const Text('אשר השלמה ושחרר תשלום',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _CompletedBanner extends StatelessWidget {
  const _CompletedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TasksPalette.providerPrimarySft,
        borderRadius: BorderRadius.circular(TasksPalette.rCard),
        border: Border.all(color: TasksPalette.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: const [
          Icon(Icons.celebration_rounded,
              color: TasksPalette.success, size: 40),
          SizedBox(height: 8),
          Text('המשימה הושלמה!',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: TasksPalette.success)),
          SizedBox(height: 4),
          Text('התשלום שוחרר לנותן השירות',
              style: TextStyle(
                  fontSize: 13, color: TasksPalette.textSecondary)),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bg;
  const _Chip({
    required this.icon,
    required this.label,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(TasksPalette.rChip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}


/// "דרג עכשיו" CTA shown after task completes. Routes to the shared
/// TaskReviewScreen which wraps ReviewService with sourceCollection:'any_tasks'.
class _RateButton extends StatelessWidget {
  final AnyTask task;
  final bool isClientReview;
  const _RateButton({required this.task, required this.isClientReview});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TaskReviewScreen(
                task: task, isClientReview: isClientReview),
          ),
        ),
        icon: const Icon(Icons.star_rounded, size: 20, color: Colors.white),
        label: Text(
          isClientReview ? 'דרג את נותן השירות' : 'דרג את הלקוח',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: TasksPalette.primaryGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(TasksPalette.rButton)),
        ),
      ),
    );
  }
}
