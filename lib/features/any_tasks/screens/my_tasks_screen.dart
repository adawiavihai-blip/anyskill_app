/// AnySkill — My Tasks Screen (AnyTasks v14.1.0 — UI Overhaul)
///
/// Client home for the AnyTasks module. Layout per design spec:
///   • White header (avatar + greeting + bell)
///   • Pill search bar
///   • Horizontal category icon row
///   • "המשימות שלי" section + task cards
///   • Sticky bottom CTA "פרסם משימה חדשה" (dark, pill)
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/any_task.dart';
import '../services/any_task_service.dart';
import '../theme/any_tasks_palette.dart';
import 'compare_offers_screen.dart';
import 'provider_hub_screen.dart';
import 'publish_task_screen.dart';
import 'task_tracking_screen.dart';

class MyTasksScreen extends StatefulWidget {
  const MyTasksScreen({super.key});

  @override
  State<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends State<MyTasksScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openPublish() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PublishTaskScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: TasksPalette.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            _Header(onProvider: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProviderHubScreen()),
              );
            }),
            Expanded(
              child: uid == null
                  ? const _SignInEmpty()
                  : _Body(uid: uid, searchCtrl: _searchCtrl),
            ),
            _StickyCta(onTap: _openPublish),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// HEADER
// ═══════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  final VoidCallback onProvider;
  const _Header({required this.onProvider});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: TasksPalette.cardWhite,
        border: Border(
            bottom: BorderSide(color: TasksPalette.borderLight, width: 0.5)),
      ),
      child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: _loadUser(),
        builder: (context, snap) {
          final name = snap.data?.data()?['name']?.toString() ?? 'אורח';
          final image = snap.data?.data()?['profileImage']?.toString();
          return Row(
            children: [
              TasksAvatar(name: name, size: 34, imageUrl: image),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('היי $name',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: TasksPalette.textPrimary)),
                    const SizedBox(height: 1),
                    const Text('מה צריך לעשות היום?',
                        style: TextStyle(
                            fontSize: 11,
                            color: TasksPalette.textSecondary)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'נותן שירות',
                onPressed: onProvider,
                icon: const Icon(Icons.work_outline_rounded,
                    color: TasksPalette.providerPrimary, size: 22),
              ),
              const _NotificationBell(),
            ],
          );
        },
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

class _NotificationBell extends StatelessWidget {
  const _NotificationBell();

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
              .limit(1)
              .snapshots(),
      builder: (context, snap) {
        final hasUnread = snap.data?.docs.isNotEmpty ?? false;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.notifications_none_rounded,
                  color: TasksPalette.textPrimary, size: 22),
            ),
            if (hasUnread)
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: TasksPalette.dangerRed,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// BODY (search + categories + tasks)
// ═══════════════════════════════════════════════════════════════════

class _Body extends StatelessWidget {
  final String uid;
  final TextEditingController searchCtrl;
  const _Body({required this.uid, required this.searchCtrl});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      children: [
        _SearchBar(controller: searchCtrl),
        const SizedBox(height: 16),
        const _CategoryRow(),
        const SizedBox(height: 18),
        StreamBuilder<List<AnyTask>>(
          stream: AnyTaskService.instance.streamMyTasks(uid),
          builder: (context, snap) {
            final tasks = snap.data ?? const <AnyTask>[];
            final activeCount = tasks
                .where((t) => !['completed', 'cancelled', 'expired']
                    .contains(t.status))
                .length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 4),
                  child: Text(
                    'המשימות שלי ($activeCount פעילות)',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: TasksPalette.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (!snap.hasData)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(
                        child: CircularProgressIndicator(
                            color: TasksPalette.clientPrimary)),
                  )
                else if (tasks.isEmpty)
                  const _EmptyState()
                else
                  ...tasks.map((t) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
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

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  const _SearchBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: TasksPalette.bgPrimary,
        borderRadius: BorderRadius.circular(TasksPalette.rPill),
        border: Border.all(color: TasksPalette.borderLight, width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(
                  fontSize: 13, color: TasksPalette.textPrimary),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 11),
                hintText: 'תאר מה אתה צריך ו-AI ימצא את האיש הנכון...',
                hintStyle: TextStyle(
                    fontSize: 13, color: TasksPalette.textHint),
                border: InputBorder.none,
              ),
            ),
          ),
          const Icon(Icons.search_rounded,
              size: 18, color: TasksPalette.textSecondary),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow();

  @override
  Widget build(BuildContext context) {
    final items = <_CatItem>[
      _CatItem('צילום', Icons.photo_camera_outlined,
          TasksPalette.coralLight, TasksPalette.coral),
      _CatItem('מחקר', Icons.travel_explore_outlined,
          TasksPalette.escrowBlueLight, TasksPalette.escrowBlue),
      _CatItem('משלוחים', Icons.local_shipping_outlined,
          TasksPalette.providerLight, TasksPalette.providerPrimary),
      _CatItem('עריכה', Icons.edit_outlined,
          TasksPalette.amberLight, TasksPalette.amber),
      _CatItem('תרגום', Icons.translate_outlined,
          TasksPalette.pinkLight, TasksPalette.pink),
      _CatItem('עוד', Icons.more_horiz_rounded,
          TasksPalette.bgPrimary, TasksPalette.textSecondary),
    ];
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final c = items[i];
          return Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: c.bg,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(c.icon, color: c.fg, size: 22),
              ),
              const SizedBox(height: 8),
              Text(c.label,
                  style: const TextStyle(
                      fontSize: 10,
                      color: TasksPalette.textSecondary)),
            ],
          );
        },
      ),
    );
  }
}

class _CatItem {
  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;
  _CatItem(this.label, this.icon, this.bg, this.fg);
}

// ═══════════════════════════════════════════════════════════════════
// TASK CARD
// ═══════════════════════════════════════════════════════════════════

class _TaskCard extends StatelessWidget {
  final AnyTask task;
  const _TaskCard({required this.task});

  void _open(BuildContext context) {
    final next = task.status == 'open'
        ? CompareOffersScreen(taskId: task.id!) as Widget
        : TaskTrackingScreen(taskId: task.id!);
    Navigator.push(context, MaterialPageRoute(builder: (_) => next));
  }

  String _timeAgo() {
    final c = task.createdAt;
    if (c == null) return '';
    final d = DateTime.now().difference(c);
    if (d.inMinutes < 60) return 'פורסם לפני ${d.inMinutes}ד׳';
    if (d.inHours < 24) return 'פורסם לפני ${d.inHours} שעות';
    return 'פורסם לפני ${d.inDays} ימים';
  }

  @override
  Widget build(BuildContext context) {
    final isOpenWithOffers =
        task.status == 'open' && task.responseCount > 0;
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(TasksPalette.rCard),
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
                const SizedBox(width: 8),
                _BudgetPill(amount: task.agreedPriceNis ?? task.budgetNis),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _StatusBadge(task: task),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_timeAgo(),
                      style: const TextStyle(
                          fontSize: 11, color: TasksPalette.textHint)),
                ),
              ],
            ),
            if (isOpenWithOffers) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  _AvatarStack(count: task.responseCount.clamp(1, 4)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        '${task.responseCount} נותני שירות הגישו הצעה',
                        style: const TextStyle(
                            fontSize: 11,
                            color: TasksPalette.textSecondary)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _open(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TasksPalette.textPrimary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(TasksPalette.rButton)),
                  ),
                  child: const Text('השווה הצעות ובחר',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BudgetPill extends StatelessWidget {
  final int amount;
  const _BudgetPill({required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: TasksPalette.amberLight,
        borderRadius: BorderRadius.circular(TasksPalette.rCard),
      ),
      child: Text('₪$amount',
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: TasksPalette.amber)),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final AnyTask task;
  const _StatusBadge({required this.task});

  @override
  Widget build(BuildContext context) {
    String label;
    Color bg;
    Color fg;
    if (task.status == 'open' && task.responseCount > 0) {
      label = '${task.responseCount} הצעות חדשות!';
      bg = TasksPalette.escrowBlueLight;
      fg = TasksPalette.escrowBlue;
    } else {
      switch (task.status) {
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
          bg = TasksPalette.providerLight;
          fg = TasksPalette.successGreen;
          break;
        case 'disputed':
          label = 'מחלוקת';
          bg = TasksPalette.coralLight;
          fg = TasksPalette.coral;
          break;
        default:
          label = task.status == 'cancelled' ? 'בוטלה' : 'פגה';
          bg = TasksPalette.bgPrimary;
          fg = TasksPalette.textHint;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(TasksPalette.rChip),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w500, color: fg)),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  final int count;
  const _AvatarStack({required this.count});

  @override
  Widget build(BuildContext context) {
    final palette = [
      TasksPalette.providerLight,
      TasksPalette.amberLight,
      TasksPalette.clientLight,
      TasksPalette.pinkLight,
    ];
    return SizedBox(
      width: 26.0 + (count - 1) * 18,
      height: 26,
      child: Stack(
        children: List.generate(count, (i) {
          return Positioned(
            right: i * 18.0,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: palette[i % palette.length],
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          );
        }),
      ),
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
      padding: const EdgeInsets.symmetric(vertical: 36),
      alignment: Alignment.center,
      child: Column(
        children: const [
          Icon(Icons.assignment_outlined,
              size: 56, color: TasksPalette.textHint),
          SizedBox(height: 12),
          Text('עוד לא פרסמת משימה',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: TasksPalette.textPrimary)),
          SizedBox(height: 4),
          Text('לחץ "פרסם משימה חדשה" כדי להתחיל',
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
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
          label: const Text('פרסם משימה חדשה',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          style: ElevatedButton.styleFrom(
            backgroundColor: TasksPalette.textPrimary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(TasksPalette.rPill)),
          ),
        ),
      ),
    );
  }
}
