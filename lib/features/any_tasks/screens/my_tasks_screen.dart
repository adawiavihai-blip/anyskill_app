/// AnySkill — My Tasks Screen (AnyTasks v14.2.0 — Redesign)
///
/// Client home for the AnyTasks module. Per the April-15 redesign spec:
///   • Dark-navy gradient header (avatar + greeting + back)
///   • Horizontal row of 5 main categories (משלוחים, ניקיון, תיקונים,
///     הובלות, טיפול בחיות) — tap routes to Publish pre-filled
///   • Upgraded task cards with colored status pill, offer count and
///     two CTAs ("צפה בהצעות" / "פרטי המשימה")
///   • No search bar, no suitcase icon, explicit back navigation
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/any_task.dart';
import '../services/any_task_service.dart';
import '../theme/any_tasks_palette.dart';
import 'compare_offers_screen.dart';
import 'publish_task_screen.dart';
import 'task_tracking_screen.dart';

class MyTasksScreen extends StatelessWidget {
  const MyTasksScreen({super.key});

  void _openPublish(BuildContext context, {String? presetCategory}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublishTaskScreen(presetCategory: presetCategory),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: TasksPalette.bgPrimary,
      body: Column(
        children: [
          const _GradientHeader(),
          Expanded(
            child: uid == null
                ? const _SignInEmpty()
                : _Body(
                    uid: uid,
                    onCategoryTap: (cat) =>
                        _openPublish(context, presetCategory: cat),
                  ),
          ),
          _StickyCta(onTap: () => _openPublish(context)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// HEADER — dark gradient, back + avatar + greeting
// ═══════════════════════════════════════════════════════════════════

class _GradientHeader extends StatelessWidget {
  const _GradientHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [TasksPalette.darkNavy, TasksPalette.darkNavy2],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 18),
          child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: _loadUser(),
            builder: (context, snap) {
              final name = snap.data?.data()?['name']?.toString() ?? 'אורח';
              final image = snap.data?.data()?['profileImage']?.toString();
              return Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.arrow_forward_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 2),
                  TasksAvatar(name: name, size: 42, imageUrl: image),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('היי $name 👋',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        const Text('מה צריך לעשות היום?',
                            style: TextStyle(
                                color: Color(0xFFCBD5E1),
                                fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
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

// ═══════════════════════════════════════════════════════════════════
// BODY
// ═══════════════════════════════════════════════════════════════════

class _Body extends StatelessWidget {
  final String uid;
  final ValueChanged<String> onCategoryTap;
  const _Body({required this.uid, required this.onCategoryTap});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      children: [
        _CategoryRow(onTap: onCategoryTap),
        const SizedBox(height: 20),
        StreamBuilder<List<AnyTask>>(
          stream: AnyTaskService.instance.streamMyTasks(uid),
          builder: (context, snap) {
            final tasks = snap.data ?? const <AnyTask>[];
            final active = tasks
                .where((t) => !['completed', 'cancelled', 'expired']
                    .contains(t.status))
                .length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 4),
                  child: Text('המשימות שלי ($active פעילות)',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: TasksPalette.darkNavy)),
                ),
                const SizedBox(height: 12),
                if (!snap.hasData)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(
                        child: CircularProgressIndicator(
                            color: TasksPalette.primaryGreen)),
                  )
                else if (tasks.isEmpty)
                  const _EmptyState()
                else
                  ...tasks.map((t) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _TaskCard(task: t),
                      )),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// CATEGORY ROW — 5 main categories per redesign spec
// ═══════════════════════════════════════════════════════════════════

class _CategoryRow extends StatelessWidget {
  final ValueChanged<String> onTap;
  const _CategoryRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final items = <_CatItem>[
      _CatItem('delivery', 'משלוחים', Icons.local_shipping_rounded,
          const Color(0xFFE0F2FE), const Color(0xFF0369A1)),
      _CatItem('cleaning', 'ניקיון', Icons.cleaning_services_rounded,
          const Color(0xFFDCFCE7), const Color(0xFF15803D)),
      _CatItem('handyman', 'תיקונים', Icons.build_rounded,
          TasksPalette.amberLight, TasksPalette.amber),
      _CatItem('moving', 'הובלות', Icons.fire_truck_rounded,
          const Color(0xFFFFE4E6), const Color(0xFFBE123C)),
      _CatItem('pet_care', 'חיות', Icons.pets_rounded,
          TasksPalette.pinkLight, TasksPalette.pink),
    ];
    return SizedBox(
      height: 94,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final c = items[i];
          return InkWell(
            onTap: () => onTap(c.id),
            borderRadius: BorderRadius.circular(16),
            child: Column(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: c.bg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Icon(c.icon, color: c.fg, size: 28),
                ),
                const SizedBox(height: 8),
                Text(c.label,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: TasksPalette.darkNavy)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CatItem {
  final String id;
  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;
  _CatItem(this.id, this.label, this.icon, this.bg, this.fg);
}

// ═══════════════════════════════════════════════════════════════════
// TASK CARD — upgraded with status pill + offer count + two CTAs
// ═══════════════════════════════════════════════════════════════════

class _TaskCard extends StatelessWidget {
  final AnyTask task;
  const _TaskCard({required this.task});

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
    final hasOffers = task.status == 'open' && task.responseCount > 0;
    final inProgress =
        task.status == 'in_progress' || task.status == 'proof_submitted';

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: TasksPalette.darkNavy)),
              ),
              const SizedBox(width: 8),
              _StatusPill(status: task.status),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(_timeAgo(),
                  style: const TextStyle(
                      fontSize: 12, color: TasksPalette.textMuted)),
              const SizedBox(width: 8),
              const Text('·',
                  style:
                      TextStyle(color: TasksPalette.textMuted, fontSize: 12)),
              const SizedBox(width: 8),
              Text('₪${task.agreedPriceNis ?? task.budgetNis}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: TasksPalette.primaryGreenDark)),
            ],
          ),
          if (hasOffers) ...[
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: TasksPalette.escrowBlueLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.people_alt_rounded,
                      size: 16, color: TasksPalette.escrowBlue),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        '${task.responseCount} נותני שירות הגישו הצעה',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: TasksPalette.escrowBlue)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => hasOffers
                              ? CompareOffersScreen(taskId: task.id!)
                              : TaskTrackingScreen(taskId: task.id!)),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasOffers
                          ? TasksPalette.primaryGreen
                          : TasksPalette.darkNavy,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(TasksPalette.rButton)),
                    ),
                    child: Text(
                        hasOffers
                            ? 'צפה בהצעות (${task.responseCount})'
                            : inProgress
                                ? 'מעקב משימה'
                                : 'פרטי המשימה',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 42,
                child: OutlinedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            TaskTrackingScreen(taskId: task.id!)),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: TasksPalette.darkNavy,
                    side: const BorderSide(
                        color: TasksPalette.borderLight, width: 1),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(TasksPalette.rButton)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: const Text('פרטים',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                ),
              ),
            ],
          ),
        ],
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
        bg = TasksPalette.escrowBlueLight;
        fg = TasksPalette.escrowBlue;
        break;
      case 'in_progress':
        label = 'בביצוע';
        bg = TasksPalette.amberLight;
        fg = TasksPalette.amber;
        break;
      case 'proof_submitted':
        label = 'ממתין לאישור';
        bg = TasksPalette.clientLight;
        fg = TasksPalette.clientPrimary;
        break;
      case 'completed':
        label = 'הושלמה';
        bg = const Color(0xFFDCFCE7);
        fg = TasksPalette.primaryGreenDark;
        break;
      case 'disputed':
        label = 'מחלוקת';
        bg = TasksPalette.coralLight;
        fg = TasksPalette.coral;
        break;
      default:
        label = status == 'cancelled' ? 'בוטלה' : 'פגה';
        bg = const Color(0xFFF1F5F9);
        fg = TasksPalette.textMuted;
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

// ═══════════════════════════════════════════════════════════════════
// EMPTY + STICKY CTA
// ═══════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      alignment: Alignment.center,
      child: Column(
        children: const [
          Icon(Icons.assignment_outlined,
              size: 56, color: TasksPalette.textMuted),
          SizedBox(height: 12),
          Text('עוד לא פרסמת משימה',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: TasksPalette.darkNavy)),
          SizedBox(height: 6),
          Text('בחר קטגוריה למעלה או לחץ "פרסם משימה חדשה"',
              style: TextStyle(
                  fontSize: 12, color: TasksPalette.textSecondary)),
        ],
      ),
    );
  }
}

class _SignInEmpty extends StatelessWidget {
  const _SignInEmpty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('יש להתחבר',
          style: TextStyle(fontSize: 14, color: TasksPalette.textSecondary)),
    );
  }
}

class _StickyCta extends StatelessWidget {
  final VoidCallback onTap;
  const _StickyCta({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        color: TasksPalette.cardWhite,
        border: Border(
            top: BorderSide(color: TasksPalette.borderLight, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.add_rounded, size: 20, color: Colors.white),
            label: const Text('פרסם משימה חדשה',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: TasksPalette.primaryGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(TasksPalette.rButton)),
            ),
          ),
        ),
      ),
    );
  }
}
