/// AnySkill — Provider Feed (AnyTasks v14.1.0 — UI Overhaul)
///
/// Two public widgets:
///   • `ProviderFeedScreen` — standalone screen (kept for direct nav, used
///     by the legacy entry point that doesn't go through the Hub).
///   • `ProviderFeedSection` — embeddable section used inside ProviderHub
///     (filter chips + task cards, no AppBar of its own).
///
/// Layout per design spec:
///   • Filter chip row (הכל / קרוב / ₪+)
///   • Task cards: title + price-net stack, client meta, description,
///     pill row (distance/urgency/proof/escrow), green Accept CTA, grey
///     "הצע מחיר אחר" link, recommended card has 2px green border + AI badge.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/any_task.dart';
import '../services/any_task_service.dart';
import '../theme/any_tasks_palette.dart';
import 'provider_task_detail_screen.dart';

class ProviderFeedScreen extends StatelessWidget {
  const ProviderFeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TasksPalette.bgPrimary,
      appBar: AppBar(
        backgroundColor: TasksPalette.cardWhite,
        foregroundColor: TasksPalette.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('משימות פתוחות',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(0.5),
          child: Divider(
              height: 0.5, thickness: 0.5, color: TasksPalette.borderLight),
        ),
      ),
      body: const Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 24),
        child: ProviderFeedSection(),
      ),
    );
  }
}

/// Embeddable feed (filters + cards) — used inside ProviderHub.
class ProviderFeedSection extends StatefulWidget {
  const ProviderFeedSection({super.key});

  @override
  State<ProviderFeedSection> createState() => _ProviderFeedSectionState();
}

class _ProviderFeedSectionState extends State<ProviderFeedSection> {
  String _filter = 'all'; // all | near | high_pay

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _filterChip('הכל', 'all'),
            const SizedBox(width: 8),
            _filterChip('קרוב', 'near'),
            const SizedBox(width: 8),
            _filterChip('₪+', 'high_pay'),
          ],
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<AnyTask>>(
          stream: AnyTaskService.instance.streamOpenTasksForProvider(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(
                    child: CircularProgressIndicator(
                        color: TasksPalette.providerPrimary)),
              );
            }
            var tasks = snap.data!.where((t) => t.clientId != uid).toList();
            if (_filter == 'high_pay') {
              tasks.sort((a, b) => b.budgetNis.compareTo(a.budgetNis));
            }
            if (tasks.isEmpty) return const _EmptyFeed();
            return Column(
              children: List.generate(tasks.length, (i) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ProviderTaskCard(
                      task: tasks[i], recommended: i == 0),
                );
              }),
            );
          },
        ),
      ],
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return InkWell(
      onTap: () => setState(() => _filter = value),
      borderRadius: BorderRadius.circular(TasksPalette.rCard),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? TasksPalette.textPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(TasksPalette.rCard),
          border: Border.all(
              color:
                  selected ? TasksPalette.textPrimary : TasksPalette.borderLight,
              width: 0.5),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: selected
                    ? Colors.white
                    : TasksPalette.textSecondary)),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: const [
          Icon(Icons.inbox_outlined,
              size: 56, color: TasksPalette.textHint),
          SizedBox(height: 12),
          Text('אין משימות פתוחות כרגע',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: TasksPalette.textPrimary)),
          SizedBox(height: 4),
          Text('חזור עוד מעט — משימות חדשות מתפרסמות כל הזמן',
              style: TextStyle(
                  fontSize: 11, color: TasksPalette.textSecondary)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// TASK CARD
// ═══════════════════════════════════════════════════════════════════

class _ProviderTaskCard extends StatelessWidget {
  final AnyTask task;
  final bool recommended;
  const _ProviderTaskCard({required this.task, required this.recommended});

  Color _urgencyColor() {
    switch (task.urgency) {
      case 'urgent_now':
        return TasksPalette.coral;
      case 'today':
        return TasksPalette.amber;
      default:
        return TasksPalette.successGreen;
    }
  }

  Color _urgencyBg() {
    switch (task.urgency) {
      case 'urgent_now':
        return TasksPalette.coralLight;
      case 'today':
        return TasksPalette.amberLight;
      default:
        return TasksPalette.providerLight;
    }
  }

  String _timeAgo() {
    final c = task.createdAt;
    if (c == null) return '';
    final d = DateTime.now().difference(c);
    if (d.inMinutes < 60) return 'לפני ${d.inMinutes}ד׳';
    if (d.inHours < 24) return 'לפני ${d.inHours} שעות';
    return 'לפני ${d.inDays} ימים';
  }

  @override
  Widget build(BuildContext context) {
    final net = AnyTask.computeNet(task.budgetNis, 0.10);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    ProviderTaskDetailScreen(taskId: task.id!)),
          ),
          borderRadius: BorderRadius.circular(TasksPalette.rCard),
          child: Container(
            padding: EdgeInsets.fromLTRB(14, recommended ? 18 : 14, 14, 14),
            decoration: BoxDecoration(
              color: TasksPalette.cardWhite,
              borderRadius: BorderRadius.circular(TasksPalette.rCard),
              border: recommended
                  ? Border.all(color: TasksPalette.successGreen, width: 2)
                  : Border.all(
                      color: TasksPalette.borderLight, width: 0.5),
              boxShadow: TasksPalette.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: TasksPalette.textPrimary)),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('₪${task.budgetNis}',
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: TasksPalette.successGreen)),
                        Text('תקבל: ~₪$net',
                            style: const TextStyle(
                                fontSize: 10,
                                color: TasksPalette.textHint)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    TasksAvatar(name: task.clientName, size: 16),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'מפרסם: ${task.clientName} · ${_timeAgo()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11,
                            color: TasksPalette.textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(task.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: TasksPalette.textSecondary)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Pill(
                        label: task.locationDisplay,
                        bg: TasksPalette.providerLight,
                        fg: TasksPalette.successGreen),
                    _Pill(
                        label: kTaskUrgencyLabels[task.urgency] ?? '',
                        bg: _urgencyBg(),
                        fg: _urgencyColor()),
                    _Pill(
                        label:
                            'הוכחה: ${kTaskProofLabels[task.proofType] ?? ''}',
                        bg: TasksPalette.bgPrimary,
                        fg: TasksPalette.textSecondary),
                    const _Pill(
                        label: 'Escrow',
                        bg: TasksPalette.bgPrimary,
                        fg: TasksPalette.textSecondary),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ProviderTaskDetailScreen(
                              taskId: task.id!)),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TasksPalette.providerPrimary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              TasksPalette.rButton)),
                    ),
                    child: const Text('אשר משימה',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ProviderTaskDetailScreen(
                              taskId: task.id!)),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: TasksPalette.textSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                    ),
                    child: const Text('הצע מחיר אחר',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (recommended)
          Positioned(
            top: -1,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 3),
                decoration: const BoxDecoration(
                  color: TasksPalette.providerLight,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: const Text('AI: התאמה 95%',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: TasksPalette.successGreen)),
              ),
            ),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _Pill({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w500, color: fg)),
    );
  }
}
