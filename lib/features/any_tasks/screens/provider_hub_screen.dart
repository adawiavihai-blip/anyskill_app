/// AnySkill — Provider Hub Screen (AnyTasks v14.0.0)
///
/// Two-tab container for the provider's AnyTasks experience:
///   Tab 1: "משימות פתוחות" — browse open tasks (ProviderFeedScreen)
///   Tab 2: "העבודות שלי"  — active + proof-submitted tasks (list view)
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/any_task.dart';
import '../services/any_task_service.dart';
import '../theme/any_tasks_palette.dart';
import 'provider_active_task_screen.dart';
import 'provider_feed_screen.dart';

class ProviderHubScreen extends StatelessWidget {
  const ProviderHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: TasksPalette.scaffoldBg,
        appBar: AppBar(
          backgroundColor: TasksPalette.cardBg,
          foregroundColor: TasksPalette.textPrimary,
          elevation: 0,
          title: const Text('AnyTasks — נותן שירות',
              style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          bottom: const TabBar(
            indicatorColor: TasksPalette.providerPrimary,
            labelColor: TasksPalette.providerPrimary,
            unselectedLabelColor: TasksPalette.textSecondary,
            tabs: [
              Tab(text: 'משימות פתוחות'),
              Tab(text: 'העבודות שלי'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            ProviderFeedScreen(),
            _MyJobsTab(),
          ],
        ),
      ),
    );
  }
}

class _MyJobsTab extends StatelessWidget {
  const _MyJobsTab();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('יש להתחבר'));
    }
    return StreamBuilder<List<AnyTask>>(
      stream: AnyTaskService.instance.streamProviderActiveTasks(uid),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(
                  color: TasksPalette.providerPrimary));
        }
        final tasks = snap.data!;
        if (tasks.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.work_outline_rounded,
                      size: 64, color: TasksPalette.textHint),
                  SizedBox(height: 14),
                  Text('אין עבודות פעילות',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: TasksPalette.textPrimary)),
                  SizedBox(height: 6),
                  Text('קבל עבודה חדשה מלשונית "משימות פתוחות"',
                      style: TextStyle(
                          fontSize: 12,
                          color: TasksPalette.textSecondary)),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: tasks.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _JobCard(task: tasks[i]),
        );
      },
    );
  }
}

class _JobCard extends StatelessWidget {
  final AnyTask task;
  const _JobCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final amount = task.agreedPriceNis ?? task.budgetNis;
    final statusLabel = task.status == 'proof_submitted'
        ? 'ממתין לאישור לקוח'
        : 'בביצוע';
    final statusColor = task.status == 'proof_submitted'
        ? TasksPalette.escrowBlue
        : TasksPalette.providerPrimary;
    return InkWell(
      borderRadius: BorderRadius.circular(TasksPalette.rCard),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ProviderActiveTaskScreen(taskId: task.id!)),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(TasksPalette.rChip),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusColor)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.person_rounded,
                    size: 14, color: TasksPalette.textSecondary),
                const SizedBox(width: 4),
                Text(task.clientName,
                    style: const TextStyle(
                        fontSize: 12,
                        color: TasksPalette.textSecondary)),
                const Spacer(),
                Text('₪$amount',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: TasksPalette.amber)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
