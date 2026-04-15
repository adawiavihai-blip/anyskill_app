/// AnySkill — Provider Feed Screen (AnyTasks v14.0.0)
///
/// Provider browses open tasks. Spec section 5.5: sticky header with
/// earnings/streak stats, category filter chips, AI-sorted task cards
/// with urgency badges. For v1 we ship a simpler feed: category filters
/// + task cards sorted by recency. AI match-score sort comes in Phase 5.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/any_task.dart';
import '../services/any_task_service.dart';
import '../theme/any_tasks_palette.dart';
import 'provider_task_detail_screen.dart';

class ProviderFeedScreen extends StatefulWidget {
  const ProviderFeedScreen({super.key});

  @override
  State<ProviderFeedScreen> createState() => _ProviderFeedScreenState();
}

class _ProviderFeedScreenState extends State<ProviderFeedScreen> {
  String? _category;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: TasksPalette.scaffoldBg,
      appBar: AppBar(
        backgroundColor: TasksPalette.cardBg,
        foregroundColor: TasksPalette.textPrimary,
        elevation: 0,
        title: const Text('משימות פתוחות',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _chip(label: 'הכל', value: null),
                ...kTaskCategories.map((c) =>
                    _chip(label: kTaskCategoryLabels[c]!, value: c)),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<AnyTask>>(
              stream: AnyTaskService.instance.streamOpenTasksForProvider(
                categories: _category == null ? null : [_category!],
              ),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: TasksPalette.providerPrimary));
                }
                // Filter out own tasks
                final tasks =
                    snap.data!.where((t) => t.clientId != uid).toList();
                if (tasks.isEmpty) {
                  return const _EmptyState();
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: tasks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _TaskCard(task: tasks[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({required String label, required String? value}) {
    final selected = _category == value;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8, top: 8, bottom: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _category = value),
        selectedColor: TasksPalette.providerPrimarySft,
        labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? TasksPalette.providerPrimary
                : TasksPalette.textSecondary),
        side: BorderSide(
            color: selected
                ? TasksPalette.providerPrimary
                : TasksPalette.border),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TasksPalette.rChip)),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final AnyTask task;
  const _TaskCard({required this.task});

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

  String _timeAgo() {
    final created = task.createdAt;
    if (created == null) return '';
    final diff = DateTime.now().difference(created);
    if (diff.inMinutes < 60) return 'לפני ${diff.inMinutes}ד׳';
    if (diff.inHours < 24) return 'לפני ${diff.inHours} שעות';
    return 'לפני ${diff.inDays} ימים';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(TasksPalette.rCard),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ProviderTaskDetailScreen(taskId: task.id!)),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: TasksPalette.cardBg,
          borderRadius: BorderRadius.circular(TasksPalette.rCard),
          border: Border.all(color: TasksPalette.border),
          boxShadow: TasksPalette.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(task.title,
                      maxLines: 2,
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
                    color: _urgencyColor().withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(TasksPalette.rChip),
                  ),
                  child: Text(kTaskUrgencyLabels[task.urgency]!,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _urgencyColor())),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(task.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, color: TasksPalette.textSecondary)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                    task.isRemote
                        ? Icons.public_rounded
                        : Icons.location_on_outlined,
                    size: 13,
                    color: TasksPalette.textSecondary),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    task.locationDisplay,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11,
                        color: TasksPalette.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: TasksPalette.amberSoft,
                    borderRadius:
                        BorderRadius.circular(TasksPalette.rChip),
                  ),
                  child: Text('₪${task.budgetNis}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: TasksPalette.amber)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: TasksPalette.providerPrimarySft,
                    borderRadius:
                        BorderRadius.circular(TasksPalette.rChip),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.category_outlined,
                          size: 12,
                          color: TasksPalette.providerPrimary),
                      const SizedBox(width: 4),
                      Text(
                          kTaskCategoryLabels[task.category] ?? task.category,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: TasksPalette.providerPrimary)),
                    ],
                  ),
                ),
                const Spacer(),
                if (_timeAgo().isNotEmpty)
                  Text(_timeAgo(),
                      style: const TextStyle(
                          fontSize: 11,
                          color: TasksPalette.textHint)),
                if (task.responseCount > 0) ...[
                  const SizedBox(width: 8),
                  Row(
                    children: [
                      const Icon(Icons.people_outline,
                          size: 13, color: TasksPalette.coral),
                      const SizedBox(width: 3),
                      Text('${task.responseCount} התעניינו',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: TasksPalette.coral)),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.inbox_outlined,
                size: 64, color: TasksPalette.textHint),
            SizedBox(height: 14),
            Text('אין משימות בקטגוריה זו',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: TasksPalette.textPrimary)),
            SizedBox(height: 6),
            Text('נסה קטגוריה אחרת או חזור מאוחר יותר',
                style: TextStyle(
                    fontSize: 12, color: TasksPalette.textSecondary)),
          ],
        ),
      ),
    );
  }
}
