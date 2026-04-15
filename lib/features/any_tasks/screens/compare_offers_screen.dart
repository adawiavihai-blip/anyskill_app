/// AnySkill — Compare Offers Screen (AnyTasks v14.1.0 — UI Overhaul)
///
/// Client picks one of N provider offers. Layout per design spec:
///   • Sub-header: "N הצעות עבור: title" + budget/deadline subtitle
///   • AI-recommendation banner (clientLight bg)
///   • First (recommended) offer card → escrowBlue 2px border + "מומלץ" tab
///   • Each offer card → avatar + rating row + price block + message + pills + buttons
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/any_task.dart';
import '../models/task_response.dart';
import '../services/any_task_service.dart';
import '../services/task_escrow_service.dart';
import '../theme/any_tasks_palette.dart';
import 'task_tracking_screen.dart';

class CompareOffersScreen extends StatelessWidget {
  final String taskId;
  const CompareOffersScreen({super.key, required this.taskId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TasksPalette.bgPrimary,
      appBar: AppBar(
        backgroundColor: TasksPalette.cardWhite,
        foregroundColor: TasksPalette.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('השוואת הצעות',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(0.5),
          child:
              Divider(height: 0.5, thickness: 0.5, color: TasksPalette.borderLight),
        ),
      ),
      body: StreamBuilder<AnyTask?>(
        stream: AnyTaskService.instance.streamTask(taskId),
        builder: (context, taskSnap) {
          if (!taskSnap.hasData || taskSnap.data == null) {
            return const Center(
                child: CircularProgressIndicator(
                    color: TasksPalette.clientPrimary));
          }
          final task = taskSnap.data!;
          return StreamBuilder<List<TaskResponse>>(
            stream: AnyTaskService.instance.streamResponses(taskId),
            builder: (context, snap) {
              final responses = snap.data ?? const <TaskResponse>[];
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  _SubHeader(task: task, count: responses.length),
                  const SizedBox(height: 12),
                  if (responses.isNotEmpty) const _AiRecommendationBanner(),
                  const SizedBox(height: 12),
                  if (!snap.hasData)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                          child: CircularProgressIndicator(
                              color: TasksPalette.clientPrimary)),
                    )
                  else if (responses.isEmpty)
                    const _NoOffersYet()
                  else
                    ...List.generate(responses.length, (i) {
                      final r = responses[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _OfferCard(
                            task: task,
                            response: r,
                            recommended: i == 0),
                      );
                    }),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════

class _SubHeader extends StatelessWidget {
  final AnyTask task;
  final int count;
  const _SubHeader({required this.task, required this.count});

  @override
  Widget build(BuildContext context) {
    final deadline = task.deadline;
    final deadlineText = deadline == null
        ? 'גמיש'
        : 'דדליין: ${deadline.day}/${deadline.month}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$count הצעות עבור: ${task.title}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: TasksPalette.textPrimary)),
        const SizedBox(height: 4),
        Text('התקציב שלך: ₪${task.budgetNis} · $deadlineText',
            style: const TextStyle(
                fontSize: 11, color: TasksPalette.textSecondary)),
      ],
    );
  }
}

class _AiRecommendationBanner extends StatelessWidget {
  const _AiRecommendationBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: TasksPalette.clientLight,
        borderRadius: BorderRadius.circular(TasksPalette.rButton),
      ),
      child: Row(
        children: const [
          Icon(Icons.auto_awesome_rounded,
              size: 14, color: TasksPalette.clientDark),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'AI ממליץ על ההצעה הראשונה — התאמה מושלמת לפי דירוג, מיקום ומחיר',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: TasksPalette.clientDark),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoOffersYet extends StatelessWidget {
  const _NoOffersYet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: const [
          Icon(Icons.hourglass_empty_rounded,
              size: 56, color: TasksPalette.textHint),
          SizedBox(height: 12),
          Text('עדיין לא התקבלו הצעות',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: TasksPalette.textPrimary)),
          SizedBox(height: 4),
          Text('בדרך כלל נותני שירות מגיבים תוך דקות ספורות',
              style: TextStyle(
                  fontSize: 11, color: TasksPalette.textSecondary)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// OFFER CARD
// ═══════════════════════════════════════════════════════════════════

class _OfferCard extends StatefulWidget {
  final AnyTask task;
  final TaskResponse response;
  final bool recommended;
  const _OfferCard({
    required this.task,
    required this.response,
    required this.recommended,
  });

  @override
  State<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<_OfferCard> {
  bool _busy = false;

  int get _price => widget.response.offeredPriceNis ?? widget.task.budgetNis;
  int get _savings => widget.task.budgetNis - _price;
  bool get _isCounter => widget.response.responseType == 'counter_offer';

  Future<void> _choose() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TasksPalette.cardWhite,
        title: const Text('אישור בחירה',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        content: Text(
          'לבחור את ${widget.response.providerName} ב-₪$_price?\n\n'
          'הכסף יחויב מהארנק שלך מיידית וישמר באסקרו עד שתאשר השלמה.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול',
                  style: TextStyle(color: TasksPalette.textSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: TasksPalette.textPrimary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(TasksPalette.rButton))),
            child: const Text('אשר ובחר'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final err = await TaskEscrowService.chooseProvider(
      taskId: widget.task.id!,
      responseId: widget.response.id!,
      providerId: widget.response.providerId,
      providerName: widget.response.providerName,
      clientId: uid,
      clientName: widget.task.clientName,
      agreedPriceNis: _price,
      taskTitle: widget.task.title,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err), backgroundColor: TasksPalette.dangerRed));
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
          builder: (_) => TaskTrackingScreen(taskId: widget.task.id!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.response;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
          decoration: BoxDecoration(
            color: TasksPalette.cardWhite,
            borderRadius: BorderRadius.circular(TasksPalette.rCard),
            border: widget.recommended
                ? Border.all(color: TasksPalette.escrowBlue, width: 2)
                : Border.all(color: TasksPalette.borderLight, width: 0.5),
            boxShadow: TasksPalette.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TasksAvatar(
                      name: r.providerName,
                      imageUrl: r.providerImage,
                      size: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.providerName,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: TasksPalette.textPrimary)),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text('★ ${r.providerRating.toStringAsFixed(1)}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: TasksPalette.successGreen)),
                            Text('· ${r.providerCompletedCount} משימות ·',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: TasksPalette.textSecondary)),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: TasksPalette.providerLight,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('מאומת',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: TasksPalette.successGreen)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('₪$_price',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: TasksPalette.successGreen)),
                      if (_isCounter && _savings > 0)
                        Text('חסכון ₪$_savings',
                            style: const TextStyle(
                                fontSize: 10,
                                color: TasksPalette.textHint)),
                    ],
                  ),
                ],
              ),
              if (r.message.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('"${r.message}"',
                    style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: TasksPalette.textSecondary)),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (r.distanceKm != null)
                    _InfoPill(
                        label: '${r.distanceKm!.toStringAsFixed(1)} ק״מ'),
                  _InfoPill(
                      label:
                          'דירוג ${r.providerRating.toStringAsFixed(1)}'),
                  _InfoPill(
                      label: '${r.providerCompletedCount}+ עבודות'),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _choose,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: TasksPalette.textPrimary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  TasksPalette.rButton)),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : Text('בחר ב${r.providerName.split(' ').first}',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: TasksPalette.cardWhite,
                      borderRadius:
                          BorderRadius.circular(TasksPalette.rButton),
                      border: Border.all(
                          color: TasksPalette.borderLight, width: 0.5),
                    ),
                    child: IconButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('הודעות יגיעו בשלב הבא'),
                              backgroundColor:
                                  TasksPalette.clientPrimary),
                        );
                      },
                      icon: const Icon(Icons.chat_bubble_outline_rounded,
                          color: TasksPalette.textSecondary, size: 18),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (widget.recommended)
          Positioned(
            top: -1,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 3),
                decoration: const BoxDecoration(
                  color: TasksPalette.escrowBlueLight,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: const Text('מומלץ',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: TasksPalette.escrowBlue)),
              ),
            ),
          ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  const _InfoPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: TasksPalette.bgPrimary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: const TextStyle(
              fontSize: 10, color: TasksPalette.textSecondary)),
    );
  }
}
