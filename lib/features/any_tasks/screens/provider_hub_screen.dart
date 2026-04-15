/// AnySkill — Provider Hub Screen (AnyTasks v14.1.0 — UI Overhaul)
///
/// Provider home — single scroll with greeting header, stats row, level
/// progress card, streak banner, monthly goal card, then "משימות פתוחות"
/// feed (delegated to `ProviderFeedScreen` widgets via inline tabs).
library;

import 'package:cloud_firestore/cloud_firestore.dart';
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
        backgroundColor: TasksPalette.bgPrimary,
        body: SafeArea(
          child: Column(
            children: [
              const _ProviderHeader(),
              const TabBar(
                indicatorColor: TasksPalette.providerPrimary,
                indicatorWeight: 2.5,
                labelColor: TasksPalette.providerPrimary,
                unselectedLabelColor: TasksPalette.textSecondary,
                labelStyle: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500),
                tabs: [
                  Tab(text: 'משימות פתוחות'),
                  Tab(text: 'העבודות שלי'),
                ],
              ),
              const Expanded(
                child: TabBarView(
                  children: [
                    _OpenTasksTab(),
                    _MyJobsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// HEADER
// ═══════════════════════════════════════════════════════════════════

class _ProviderHeader extends StatelessWidget {
  const _ProviderHeader();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _loadUser(),
      builder: (context, snap) {
        final d = snap.data?.data() ?? {};
        final name = (d['name'] ?? 'נותן שירות').toString();
        final image = d['profileImage']?.toString();
        final rating = (d['rating'] as num?)?.toDouble() ?? 0.0;
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            color: TasksPalette.cardWhite,
            border: Border(
                bottom: BorderSide(
                    color: TasksPalette.borderLight, width: 0.5)),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_forward_rounded,
                    color: TasksPalette.textPrimary, size: 22),
              ),
              TasksAvatar(name: name, size: 34, imageUrl: image),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('שלום $name',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: TasksPalette.textPrimary)),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        Text('★ ${rating.toStringAsFixed(1)} · ',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: TasksPalette.successGreen)),
                        const Text('נותן שירות מאומת',
                            style: TextStyle(
                                fontSize: 11,
                                color: TasksPalette.textSecondary)),
                      ],
                    ),
                  ],
                ),
              ),
              const _BellWithBadge(),
            ],
          ),
        );
      },
    );
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _loadUser() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid ?? 'unknown')
        .get();
  }
}

class _BellWithBadge extends StatelessWidget {
  const _BellWithBadge();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: uid == null
          ? const Stream.empty()
          : FirebaseFirestore.instance
              .collection('notifications')
              .where('userId', isEqualTo: uid)
              .where('isRead', isEqualTo: false)
              .limit(20)
              .snapshots(),
      builder: (context, snap) {
        final n = snap.data?.docs.length ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.notifications_none_rounded,
                  color: TasksPalette.textPrimary, size: 22),
            ),
            if (n > 0)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  width: 16,
                  height: 16,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: TasksPalette.dangerRed,
                    shape: BoxShape.circle,
                  ),
                  child: Text(n > 9 ? '9+' : '$n',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w500)),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// TAB 1 — Open tasks (with provider header stats above the feed)
// ═══════════════════════════════════════════════════════════════════

class _OpenTasksTab extends StatelessWidget {
  const _OpenTasksTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        const _StatsRow(),
        const SizedBox(height: 14),
        const _LevelCard(),
        const SizedBox(height: 10),
        const _StreakBanner(),
        const SizedBox(height: 10),
        const _MonthlyGoalCard(),
        const SizedBox(height: 18),
        const _SectionTitle('משימות פתוחות'),
        const SizedBox(height: 10),
        const ProviderFeedSection(),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4),
      child: Text(text,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: TasksPalette.textPrimary)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// STATS ROW
// ═══════════════════════════════════════════════════════════════════

class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snap) {
        final d = snap.data?.data() ?? {};
        final earnings =
            (d['monthlyEarnings'] as num?)?.toInt() ?? 0;
        final completed = (d['orderCount'] as num?)?.toInt() ?? 0;
        final completionRate = completed > 0 ? '100%' : '—';
        return Row(
          children: [
            Expanded(
                child: _StatCard(
                    value: '₪$earnings',
                    label: 'הרווחת החודש',
                    color: TasksPalette.textPrimary)),
            const SizedBox(width: 8),
            Expanded(
                child: _StatCard(
                    value: '$completed',
                    label: 'משימות הושלמו',
                    color: TasksPalette.successGreen)),
            const SizedBox(width: 8),
            Expanded(
                child: _StatCard(
                    value: completionRate,
                    label: 'שיעור השלמה',
                    color: TasksPalette.escrowBlue)),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _StatCard(
      {required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: TasksPalette.bgPrimary,
        borderRadius: BorderRadius.circular(TasksPalette.rButton),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: TasksPalette.textSecondary)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// LEVEL + PROGRESS
// ═══════════════════════════════════════════════════════════════════

class _LevelCard extends StatelessWidget {
  const _LevelCard();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snap) {
        final d = snap.data?.data() ?? {};
        final name = (d['name'] ?? 'נותן שירות').toString();
        final image = d['profileImage']?.toString();
        final rating = (d['rating'] as num?)?.toDouble() ?? 0.0;
        final completed = (d['orderCount'] as num?)?.toInt() ?? 0;
        const target = 25; // hard-coded next-tier threshold for v1
        final progress = (completed / target).clamp(0.0, 1.0);
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: TasksPalette.cardWhite,
            borderRadius: BorderRadius.circular(TasksPalette.rCard),
            border: Border.all(
                color: TasksPalette.borderLight, width: 0.5),
            boxShadow: TasksPalette.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TasksAvatar(name: name, size: 50, imageUrl: image),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: TasksPalette.textPrimary)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: TasksPalette.clientLight,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('רמה: מקצוען',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: TasksPalette.clientPrimary)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: TasksPalette.providerLight,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('★ ${rating.toStringAsFixed(1)}',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: TasksPalette.successGreen)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(
                    child: Text('עוד 2 משימות לרמת מומחה',
                        style: TextStyle(
                            fontSize: 11,
                            color: TasksPalette.textSecondary)),
                  ),
                  Text('$completed/$target',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: TasksPalette.textPrimary)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: TasksPalette.bgPrimary,
                  valueColor: const AlwaysStoppedAnimation(
                      TasksPalette.clientPrimary),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'כמעט שם! רמת מומחה פותחת badge מיוחד + חשיפה מוגברת',
                style: TextStyle(
                    fontSize: 10, color: TasksPalette.clientPrimary),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: const [
                  _BadgeChip(
                      label: 'מהיר',
                      bg: TasksPalette.amberLight,
                      fg: TasksPalette.amber),
                  _BadgeChip(
                      label: '5 כוכבים',
                      bg: TasksPalette.providerLight,
                      fg: TasksPalette.successGreen),
                  _BadgeChip(
                      label: 'מומחה איסוף',
                      bg: TasksPalette.escrowBlueLight,
                      fg: TasksPalette.escrowBlue),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _BadgeChip(
      {required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w500, color: fg)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// STREAK BANNER + MONTHLY GOAL
// ═══════════════════════════════════════════════════════════════════

class _StreakBanner extends StatelessWidget {
  const _StreakBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: TasksPalette.amberLight,
        borderRadius: BorderRadius.circular(TasksPalette.rButton),
      ),
      child: Row(
        children: const [
          Text('🔥', style: TextStyle(fontSize: 18)),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('5 משימות ברצף!',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: TasksPalette.amber)),
                Text('השלם עוד אחת היום ותקבל בונוס ₪25',
                    style: TextStyle(
                        fontSize: 11, color: TasksPalette.amber)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyGoalCard extends StatelessWidget {
  const _MonthlyGoalCard();

  @override
  Widget build(BuildContext context) {
    const earned = 2340;
    const goal = 3000;
    final pct = (earned / goal).clamp(0.0, 1.0);
    final pctText = '${(pct * 100).toInt()}%';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TasksPalette.cardWhite,
        borderRadius: BorderRadius.circular(TasksPalette.rCard),
        border: Border.all(color: TasksPalette.borderLight, width: 0.5),
        boxShadow: TasksPalette.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('יעד חודשי',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: TasksPalette.textPrimary)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('₪$earned',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: TasksPalette.textPrimary)),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text('/ ₪$goal',
                    style: TextStyle(
                        fontSize: 13,
                        color: TasksPalette.textSecondary)),
              ),
              const Spacer(),
              Text(pctText,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: TasksPalette.successGreen)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: TasksPalette.providerLight,
              valueColor: const AlwaysStoppedAnimation(
                  TasksPalette.successGreen),
            ),
          ),
          const SizedBox(height: 6),
          const Text('עוד ₪${goal - earned} ליעד! עוד 5 משימות ממוצעות ואתה שם',
              style: TextStyle(
                  fontSize: 11, color: TasksPalette.textSecondary)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// TAB 2 — My Jobs (active tasks)
// ═══════════════════════════════════════════════════════════════════

class _MyJobsTab extends StatelessWidget {
  const _MyJobsTab();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(
          child: Text('יש להתחבר',
              style: TextStyle(color: TasksPalette.textSecondary)));
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
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.work_outline_rounded,
                      size: 56, color: TasksPalette.textHint),
                  SizedBox(height: 12),
                  Text('אין עבודות פעילות',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: TasksPalette.textPrimary)),
                  SizedBox(height: 4),
                  Text('קבל עבודה חדשה מלשונית "משימות פתוחות"',
                      style: TextStyle(
                          fontSize: 11,
                          color: TasksPalette.textSecondary)),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          itemCount: tasks.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _ActiveJobCard(task: tasks[i]),
        );
      },
    );
  }
}

class _ActiveJobCard extends StatelessWidget {
  final AnyTask task;
  const _ActiveJobCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final amount = task.agreedPriceNis ?? task.budgetNis;
    final pending = task.status == 'proof_submitted';
    final label = pending ? 'ממתין לאישור לקוח' : 'בביצוע';
    final color = pending
        ? TasksPalette.escrowBlue
        : TasksPalette.providerPrimary;
    final bg =
        pending ? TasksPalette.escrowBlueLight : TasksPalette.providerLight;
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
          color: TasksPalette.cardWhite,
          borderRadius: BorderRadius.circular(TasksPalette.rCard),
          border: Border.all(color: TasksPalette.borderLight, width: 0.5),
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
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: TasksPalette.textPrimary)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TasksPalette.rChip),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: color)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TasksAvatar(name: task.clientName, size: 24),
                const SizedBox(width: 6),
                Text(task.clientName,
                    style: const TextStyle(
                        fontSize: 12, color: TasksPalette.textSecondary)),
                const Spacer(),
                Text('₪$amount',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: TasksPalette.successGreen)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
