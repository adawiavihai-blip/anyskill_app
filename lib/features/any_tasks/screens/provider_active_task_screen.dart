/// AnySkill — Provider Active Task Screen (AnyTasks v14.0.0)
///
/// Provider works a task they were chosen for. Spec section 5.7:
///   • Milestone stepper with "סמן כהושלם" buttons
///   • "העלה הוכחה" → pick image → upload to Storage → flip status
///   • Chat entry (deferred to Phase 5)
library;

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/any_task.dart';
import '../models/task_milestone.dart';
import '../services/any_task_service.dart';
import '../theme/any_tasks_palette.dart';

class ProviderActiveTaskScreen extends StatelessWidget {
  final String taskId;
  const ProviderActiveTaskScreen({super.key, required this.taskId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TasksPalette.scaffoldBg,
      appBar: AppBar(
        backgroundColor: TasksPalette.cardBg,
        foregroundColor: TasksPalette.textPrimary,
        elevation: 0,
        title: const Text('משימה פעילה',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      ),
      body: StreamBuilder<AnyTask?>(
        stream: AnyTaskService.instance.streamTask(taskId),
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
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _TaskSummary(task: task),
              const SizedBox(height: 14),
              _ClientCard(task: task),
              const SizedBox(height: 14),
              _StepperSection(task: task),
              const SizedBox(height: 14),
              if (task.status == 'in_progress') _ProofSection(task: task),
              if (task.status == 'proof_submitted')
                const _WaitingClient(),
              if (task.status == 'completed') const _CompletedBanner(),
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════

class _TaskSummary extends StatelessWidget {
  final AnyTask task;
  const _TaskSummary({required this.task});

  @override
  Widget build(BuildContext context) {
    final amount = task.agreedPriceNis ?? task.budgetNis;
    final net = task.providerPayoutNis ??
        AnyTask.computeNet(amount, 0.10);
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
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: TasksPalette.amberSoft,
                  borderRadius: BorderRadius.circular(TasksPalette.rChip),
                ),
                child: Text('₪$amount',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: TasksPalette.amber)),
              ),
              const SizedBox(width: 8),
              Text('נטו: ₪$net',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: TasksPalette.success)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  final AnyTask task;
  const _ClientCard({required this.task});

  @override
  Widget build(BuildContext context) {
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
            backgroundColor: TasksPalette.clientPrimarySoft,
            child: Icon(Icons.person_rounded,
                color: TasksPalette.clientPrimary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('הלקוח',
                    style: TextStyle(
                        fontSize: 11,
                        color: TasksPalette.textSecondary)),
                const SizedBox(height: 2),
                Text(task.clientName,
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
                  backgroundColor: TasksPalette.providerPrimary,
                ),
              );
            },
            icon: const Icon(Icons.chat_bubble_outline_rounded,
                color: TasksPalette.providerPrimary),
          ),
        ],
      ),
    );
  }
}

class _StepperSection extends StatelessWidget {
  final AnyTask task;
  const _StepperSection({required this.task});

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
          const Text('שלבי העבודה',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: TasksPalette.textPrimary)),
          const SizedBox(height: 10),
          StreamBuilder<List<TaskMilestone>>(
            stream: AnyTaskService.instance.streamMilestones(task.id!),
            builder: (context, snap) {
              final items = snap.data ?? const <TaskMilestone>[];
              if (items.isEmpty) {
                return const Text('אין שלבים',
                    style: TextStyle(
                        color: TasksPalette.textSecondary, fontSize: 12));
              }
              return Column(
                children: items.map((m) {
                  final done = m.isDone;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: done
                                ? TasksPalette.success
                                : TasksPalette.scaffoldBg,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: done
                                    ? TasksPalette.success
                                    : TasksPalette.border),
                          ),
                          child: done
                              ? const Icon(Icons.check_rounded,
                                  size: 14, color: Colors.white)
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(m.title,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: done
                                      ? TasksPalette.textPrimary
                                      : TasksPalette.textSecondary)),
                        ),
                        if (!done && task.status == 'in_progress')
                          TextButton(
                            onPressed: () => AnyTaskService.instance
                                .completeMilestone(
                                    taskId: task.id!,
                                    milestoneId: m.id!),
                            style: TextButton.styleFrom(
                                foregroundColor:
                                    TasksPalette.providerPrimary,
                                visualDensity:
                                    VisualDensity.compact),
                            child: const Text('סמן כהושלם',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProofSection extends StatefulWidget {
  final AnyTask task;
  const _ProofSection({required this.task});

  @override
  State<_ProofSection> createState() => _ProofSectionState();
}

class _ProofSectionState extends State<_ProofSection> {
  final _text = TextEditingController();
  File? _picked;
  String? _pickedWebUrl; // for web preview
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 1200,
    );
    if (x == null) return;
    setState(() {
      _picked = File(x.path);
      _pickedWebUrl = x.path;
    });
  }

  Future<String?> _upload(String taskId) async {
    if (_picked == null) return null;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final ref = FirebaseStorage.instance
        .ref('task_proofs/$taskId/${uid}_${DateTime.now().millisecondsSinceEpoch}.jpg');
    final snap = await ref.putFile(_picked!);
    return snap.ref.getDownloadURL();
  }

  Future<void> _submit() async {
    final requiresPhoto = widget.task.proofType != 'text';
    final requiresText = widget.task.proofType != 'photo';
    if (requiresPhoto && _picked == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('יש לצרף תמונה'),
          backgroundColor: TasksPalette.danger));
      return;
    }
    if (requiresText && _text.text.trim().length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('יש לכתוב תיאור (לפחות 5 תווים)'),
          backgroundColor: TasksPalette.danger));
      return;
    }
    setState(() => _busy = true);
    try {
      final url = _picked != null ? await _upload(widget.task.id!) : null;
      await AnyTaskService.instance.submitProof(
        taskId: widget.task.id!,
        proofUrl: url,
        proofText: _text.text.trim().isEmpty ? null : _text.text.trim(),
      );
      // Also record on the first uncompleted milestone — spec says last
      // step gets the proof.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ הוכחה נשלחה! ממתין לאישור הלקוח'),
          backgroundColor: TasksPalette.success));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('שגיאה: $e'),
          backgroundColor: TasksPalette.danger));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requiresPhoto = widget.task.proofType != 'text';
    final requiresText = widget.task.proofType != 'photo';
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
              const Icon(Icons.verified_outlined,
                  color: TasksPalette.providerPrimary, size: 20),
              const SizedBox(width: 8),
              Text('הוכחת ביצוע — ${kTaskProofLabels[widget.task.proofType]}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: TasksPalette.textPrimary)),
            ],
          ),
          const SizedBox(height: 12),
          if (requiresPhoto) ...[
            InkWell(
              onTap: _pickImage,
              borderRadius: BorderRadius.circular(TasksPalette.rButton),
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  color: TasksPalette.scaffoldBg,
                  borderRadius:
                      BorderRadius.circular(TasksPalette.rButton),
                  border: Border.all(
                      color: _picked == null
                          ? TasksPalette.border
                          : TasksPalette.providerPrimary,
                      width: _picked == null ? 1 : 1.5),
                ),
                child: _picked != null && _pickedWebUrl != null
                    ? ClipRRect(
                        borderRadius:
                            BorderRadius.circular(TasksPalette.rButton),
                        child: Image.file(_picked!, fit: BoxFit.cover),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.photo_camera_outlined,
                              color: TasksPalette.providerPrimary, size: 32),
                          SizedBox(height: 6),
                          Text('לחץ לצילום תמונה',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: TasksPalette.providerPrimary)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (requiresText)
            TextField(
              controller: _text,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'תיאור הביצוע...',
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(TasksPalette.rButton)),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: TasksPalette.providerPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(TasksPalette.rButton)),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('שלח הוכחה ללקוח',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitingClient extends StatelessWidget {
  const _WaitingClient();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TasksPalette.escrowBlueSoft,
        borderRadius: BorderRadius.circular(TasksPalette.rCard),
        border: Border.all(color: TasksPalette.escrowBlue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: const [
          Icon(Icons.hourglass_empty_rounded,
              color: TasksPalette.escrowBlue, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
                'הוכחה נשלחה. ממתין לאישור הלקוח — הכסף ישוחרר ברגע שיאשר.',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: TasksPalette.escrowBlue)),
          ),
        ],
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
          Text('הושלם! הכסף הועבר לארנק שלך',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: TasksPalette.success)),
        ],
      ),
    );
  }
}

// Suppress unused import warning on non-web builds.
// ignore: unused_element
void _keepCloudFirestoreAlive() {
  FirebaseFirestore.instance;
}
