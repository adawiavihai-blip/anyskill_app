/// AnySkill — Compare Offers Screen (AnyTasks v14.0.0)
///
/// Client sees all provider responses (accept + counter-offer) for an
/// open task, picks one, and the escrow transaction charges their wallet.
/// Follows spec section 5.3:
///   • Accept cards → green left border + ✓ + "Accepted at ₪X"
///   • Counter-offer cards → amber left border + price tag + "Suggests ₪Y (save ₪Z)"
///   • AI-recommended top match → purple border + "מומלץ" badge (future Phase 5)
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../utils/safe_image_provider.dart';
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
      backgroundColor: TasksPalette.scaffoldBg,
      appBar: AppBar(
        backgroundColor: TasksPalette.cardBg,
        foregroundColor: TasksPalette.textPrimary,
        elevation: 0,
        title: const Text('הצעות שהתקבלו',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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
          return Column(
            children: [
              _TaskSummary(task: task),
              Expanded(
                child: StreamBuilder<List<TaskResponse>>(
                  stream: AnyTaskService.instance.streamResponses(taskId),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: TasksPalette.clientPrimary));
                    }
                    final responses = snap.data!;
                    if (responses.isEmpty) {
                      return const _NoOffersYet();
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: responses.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _OfferCard(
                        task: task,
                        response: responses[i],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TaskSummary extends StatelessWidget {
  final AnyTask task;
  const _TaskSummary({required this.task});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: TasksPalette.textPrimary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: TasksPalette.amberSoft,
                  borderRadius: BorderRadius.circular(TasksPalette.rChip),
                ),
                child: Text('₪${task.budgetNis}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: TasksPalette.amber)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('${task.responseCount} הצעות התקבלו',
              style: const TextStyle(
                  fontSize: 12, color: TasksPalette.textSecondary)),
        ],
      ),
    );
  }
}

class _NoOffersYet extends StatelessWidget {
  const _NoOffersYet();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.hourglass_empty_rounded,
                size: 56, color: TasksPalette.textHint),
            SizedBox(height: 14),
            Text('עדיין לא התקבלו הצעות',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: TasksPalette.textPrimary)),
            SizedBox(height: 6),
            Text('בדרך כלל נותני שירות מגיבים תוך דקות ספורות',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: TasksPalette.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _OfferCard extends StatefulWidget {
  final AnyTask task;
  final TaskResponse response;
  const _OfferCard({required this.task, required this.response});

  @override
  State<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<_OfferCard> {
  bool _busy = false;

  int get _price => widget.response.offeredPriceNis ?? widget.task.budgetNis;
  bool get _isCounter => widget.response.responseType == 'counter_offer';
  int get _savings => widget.task.budgetNis - _price;

  Future<void> _choose() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('אישור בחירה'),
        content: Text(
          'האם לבחור את ${widget.response.providerName} ב-₪$_price?\n\nהכסף יחויב מהארנק שלך מיידית וישמר באסקרו עד שתאשר השלמה.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: TasksPalette.clientPrimary,
                foregroundColor: Colors.white),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(err), backgroundColor: TasksPalette.danger),
      );
      return;
    }
    // Success — navigate to tracking
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
          builder: (_) => TaskTrackingScreen(taskId: widget.task.id!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final borderColor =
        _isCounter ? TasksPalette.amber : TasksPalette.success;
    return Container(
      decoration: BoxDecoration(
        color: TasksPalette.cardBg,
        borderRadius: BorderRadius.circular(TasksPalette.rCard),
        border: Border(
          right: BorderSide(color: borderColor, width: 4), // RTL = start edge
          top: BorderSide(color: TasksPalette.border),
          bottom: BorderSide(color: TasksPalette.border),
          left: BorderSide(color: TasksPalette.border),
        ),
        boxShadow: TasksPalette.cardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: TasksPalette.clientPrimarySoft,
                  backgroundImage:
                      safeImageProvider(widget.response.providerImage),
                  child: widget.response.providerImage == null ||
                          widget.response.providerImage!.isEmpty
                      ? Text(
                          widget.response.providerName.isEmpty
                              ? '?'
                              : widget.response.providerName[0],
                          style: const TextStyle(
                              color: TasksPalette.clientPrimary,
                              fontWeight: FontWeight.w700),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.response.providerName,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: TasksPalette.textPrimary)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 13, color: TasksPalette.amber),
                          Text(
                            ' ${widget.response.providerRating.toStringAsFixed(1)}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: TasksPalette.textSecondary),
                          ),
                          Text(
                            '  •  ${widget.response.providerCompletedCount} משימות',
                            style: const TextStyle(
                                fontSize: 11,
                                color: TasksPalette.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _StatusChip(isCounter: _isCounter, savings: _savings),
              ],
            ),
            if (widget.response.message.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: TasksPalette.scaffoldBg,
                  borderRadius: BorderRadius.circular(TasksPalette.rButton),
                ),
                child: Text(widget.response.message,
                    style: const TextStyle(
                        fontSize: 12, color: TasksPalette.textPrimary)),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isCounter
                        ? 'מציע ₪$_price במקום ₪${widget.task.budgetNis}'
                        : 'מאשר את ₪$_price',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _isCounter
                            ? TasksPalette.amber
                            : TasksPalette.success),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _choose,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TasksPalette.clientPrimary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(TasksPalette.rPill)),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('בחר',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool isCounter;
  final int savings;
  const _StatusChip({required this.isCounter, required this.savings});

  @override
  Widget build(BuildContext context) {
    final color = isCounter ? TasksPalette.amber : TasksPalette.success;
    final bg = isCounter
        ? TasksPalette.amberSoft
        : TasksPalette.providerPrimarySft;
    final label = isCounter
        ? (savings > 0 ? 'חיסכון ₪$savings' : 'מחיר חלופי')
        : 'מאשר מחיר';
    final icon = isCounter
        ? Icons.local_offer_outlined
        : Icons.check_circle_outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(TasksPalette.rChip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
