/// AnySkill — My Tasks Screen (AnyTasks v14.0.0)
///
/// Client-side list of tasks the user has published. Entry screen from
/// the home-tab "AnyTasks" banner. FAB opens [PublishTaskScreen]. Each
/// row shows title + category + budget + status pill. Taps currently
/// show a placeholder snackbar — Compare Offers / Task Tracking screens
/// will wire up in Phase 2.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/any_task.dart';
import '../services/any_task_service.dart';
import '../theme/any_tasks_palette.dart';
import 'compare_offers_screen.dart';
import 'provider_hub_screen.dart';
import 'publish_task_screen.dart';
import 'task_tracking_screen.dart';

class MyTasksScreen extends StatelessWidget {
  const MyTasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: TasksPalette.scaffoldBg,
      appBar: AppBar(
        backgroundColor: TasksPalette.cardBg,
        foregroundColor: TasksPalette.textPrimary,
        elevation: 0,
        title: const Text('המשימות שלי',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProviderHubScreen()),
            ),
            icon: const Icon(Icons.work_outline_rounded,
                size: 18, color: TasksPalette.providerPrimary),
            label: const Text('נותן שירות',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: TasksPalette.providerPrimary)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PublishTaskScreen()),
          );
        },
        backgroundColor: TasksPalette.clientPrimary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('פרסם משימה'),
      ),
      body: uid == null
          ? const _EmptyState(
              icon: Icons.login_rounded,
              title: 'יש להתחבר',
              subtitle: 'התחבר כדי לראות את המשימות שלך',
            )
          : StreamBuilder<List<AnyTask>>(
              stream: AnyTaskService.instance.streamMyTasks(uid),
              builder: (context, snap) {
                if (snap.hasError) {
                  return const _EmptyState(
                    icon: Icons.error_outline,
                    title: 'שגיאה בטעינה',
                    subtitle: 'נסה לרענן את המסך',
                  );
                }
                if (!snap.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: TasksPalette.clientPrimary));
                }
                final tasks = snap.data!;
                if (tasks.isEmpty) {
                  return const _EmptyState(
                    icon: Icons.assignment_outlined,
                    title: 'עוד לא פרסמת משימה',
                    subtitle: 'לחץ "פרסם משימה" כדי להתחיל',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: tasks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _TaskCard(task: tasks[i]),
                );
              },
            ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final AnyTask task;
  const _TaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(TasksPalette.rCard),
      onTap: () {
        final Widget next;
        if (task.status == 'open') {
          next = CompareOffersScreen(taskId: task.id!);
        } else {
          next = TaskTrackingScreen(taskId: task.id!);
        }
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => next),
        );
      },
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
                  child: Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: TasksPalette.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _StatusPill(status: task.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              task.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, color: TasksPalette.textSecondary),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Chip(
                  icon: Icons.category_outlined,
                  label: kTaskCategoryLabels[task.category] ?? task.category,
                  color: TasksPalette.clientPrimary,
                  bg: TasksPalette.clientPrimarySoft,
                ),
                const SizedBox(width: 8),
                _Chip(
                  icon: Icons.payments_outlined,
                  label: '₪${task.budgetNis}',
                  color: TasksPalette.amber,
                  bg: TasksPalette.amberSoft,
                ),
                const SizedBox(width: 8),
                if (task.responseCount > 0)
                  _Chip(
                    icon: Icons.people_outline,
                    label: '${task.responseCount} הצעות',
                    color: TasksPalette.success,
                    bg: TasksPalette.providerPrimarySft,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final Color bg;
    late final Color fg;
    switch (status) {
      case 'open':
        label = 'פתוחה';
        bg = TasksPalette.clientPrimarySoft;
        fg = TasksPalette.clientPrimary;
        break;
      case 'in_progress':
        label = 'בביצוע';
        bg = TasksPalette.amberSoft;
        fg = TasksPalette.amber;
        break;
      case 'proof_submitted':
        label = 'ממתין לאישור';
        bg = TasksPalette.escrowBlueSoft;
        fg = TasksPalette.escrowBlue;
        break;
      case 'completed':
        label = 'הושלמה';
        bg = TasksPalette.providerPrimarySft;
        fg = TasksPalette.success;
        break;
      case 'disputed':
        label = 'מחלוקת';
        bg = TasksPalette.coralSoft;
        fg = TasksPalette.coral;
        break;
      case 'cancelled':
        label = 'בוטלה';
        bg = const Color(0xFFF3F4F6);
        fg = TasksPalette.textSecondary;
        break;
      case 'expired':
        label = 'פגה';
        bg = const Color(0xFFF3F4F6);
        fg = TasksPalette.textSecondary;
        break;
      default:
        label = status;
        bg = const Color(0xFFF3F4F6);
        fg = TasksPalette.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(TasksPalette.rChip),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
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

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: TasksPalette.textHint),
            const SizedBox(height: 14),
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: TasksPalette.textPrimary)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: TasksPalette.textSecondary)),
          ],
        ),
      ),
    );
  }
}
