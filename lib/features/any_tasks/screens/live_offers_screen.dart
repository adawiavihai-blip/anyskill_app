/// AnySkill — Live Offers Screen (AnyTasks v14.3.0)
///
/// Shown IMMEDIATELY after a task is published. Presents a radar-style
/// search animation while the backend fans the notification out to
/// matching providers, then streams incoming `TaskResponse` docs as
/// slide-in cards. When the client picks one, it routes to the existing
/// CompareOffers flow (so the escrow transaction happens there).
///
/// Psychology hooks from the spec:
///   • Animated "סורקים N נותני שירות באזור שלך"
///   • Live "N הצעות התקבלו — עוד מגיעות..." pulse banner
///   • Cards arrive with slide-in animation, newest first
///   • Fallback after 15s of 0 offers: "נמשיך לחפש ונעדכן אותך בהתראה"
library;

import 'package:flutter/material.dart';

import '../models/any_task.dart';
import '../models/task_response.dart';
import '../services/any_task_service.dart';
import '../theme/any_tasks_palette.dart';
import 'compare_offers_screen.dart';
import 'my_tasks_screen.dart';

class LiveOffersScreen extends StatelessWidget {
  final String taskId;
  const LiveOffersScreen({super.key, required this.taskId});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Route back to My Tasks regardless of navigation depth so users
        // never get stuck on the waiting screen.
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MyTasksScreen()),
          (r) => false,
        );
      },
      child: Scaffold(
        backgroundColor: TasksPalette.bgPrimary,
        appBar: AppBar(
          backgroundColor: TasksPalette.cardWhite,
          foregroundColor: TasksPalette.darkNavy,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: const Text('מחפשים נותני שירות',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          leading: IconButton(
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const MyTasksScreen()),
              (r) => false,
            ),
            icon: const Icon(Icons.close_rounded, size: 22),
          ),
        ),
        body: StreamBuilder<AnyTask?>(
          stream: AnyTaskService.instance.streamTask(taskId),
          builder: (context, taskSnap) {
            if (!taskSnap.hasData) {
              return const Center(
                  child: CircularProgressIndicator(
                      color: TasksPalette.primaryGreen));
            }
            final task = taskSnap.data;
            if (task == null) {
              return const Center(
                  child: Text('המשימה לא נמצאה'));
            }
            // If the task already has a selected provider, skip straight
            // to the tracker — user opened this screen by mistake.
            if (task.status != 'open') {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                      builder: (_) => CompareOffersScreen(taskId: taskId)),
                  (r) => false,
                );
              });
              return const Center(
                  child: CircularProgressIndicator(
                      color: TasksPalette.primaryGreen));
            }
            return StreamBuilder<List<TaskResponse>>(
              stream: AnyTaskService.instance.streamResponses(taskId),
              builder: (context, rSnap) {
                final responses = rSnap.data ?? const <TaskResponse>[];
                return _Body(task: task, responses: responses);
              },
            );
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════

class _Body extends StatelessWidget {
  final AnyTask task;
  final List<TaskResponse> responses;
  const _Body({required this.task, required this.responses});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        _TaskPreview(task: task),
        const SizedBox(height: 14),
        if (responses.isEmpty)
          const _RadarSearch()
        else ...[
          _LiveBanner(count: responses.length),
          const SizedBox(height: 14),
          ...List.generate(responses.length, (i) {
            // Newest first
            final r = responses[responses.length - 1 - i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _OfferCard(
                task: task,
                response: r,
                appearDelay: Duration(milliseconds: 60 * i),
              ),
            );
          }),
        ],
        const SizedBox(height: 20),
        _KeepSearchingFooter(),
      ],
    );
  }
}

class _TaskPreview extends StatelessWidget {
  final AnyTask task;
  const _TaskPreview({required this.task});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TasksPalette.cardWhite,
        borderRadius: BorderRadius.circular(TasksPalette.rCard),
        boxShadow: TasksPalette.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: TasksPalette.primaryGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.check_circle_rounded,
                color: TasksPalette.primaryGreen, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('המשימה פורסמה',
                    style: TextStyle(
                        fontSize: 11,
                        color: TasksPalette.textSecondary)),
                const SizedBox(height: 2),
                Text(task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: TasksPalette.darkNavy)),
                const SizedBox(height: 2),
                Text('₪${task.budgetNis} · ${_urgencyLabel(task.urgency)}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: TasksPalette.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _urgencyLabel(String u) {
    switch (u) {
      case 'urgent_now': return 'דחוף';
      case 'today':      return 'היום';
      default:           return 'גמיש';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// RADAR SEARCH — initial state before any offers arrive
// ═══════════════════════════════════════════════════════════════════

class _RadarSearch extends StatefulWidget {
  const _RadarSearch();

  @override
  State<_RadarSearch> createState() => _RadarSearchState();
}

class _RadarSearchState extends State<_RadarSearch>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _counter = 3;
  late final DateTime _start;

  @override
  void initState() {
    super.initState();
    _start = DateTime.now();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    // Ticker bumps "X נותני שירות באזור שלך" every 700ms up to ~18
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted || _counter >= 18) return false;
      setState(() => _counter++);
      return true;
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: TasksPalette.cardWhite,
        borderRadius: BorderRadius.circular(TasksPalette.rCard),
        boxShadow: TasksPalette.cardShadow,
      ),
      child: Column(
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, __) {
                    return Container(
                      width: 120 * _ctrl.value,
                      height: 120 * _ctrl.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: TasksPalette.primaryGreen
                            .withValues(alpha: 0.15 * (1 - _ctrl.value)),
                      ),
                    );
                  },
                ),
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, __) {
                    final v = (_ctrl.value + 0.4) % 1.0;
                    return Container(
                      width: 120 * v,
                      height: 120 * v,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: TasksPalette.primaryGreen
                            .withValues(alpha: 0.12 * (1 - v)),
                      ),
                    );
                  },
                ),
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: TasksPalette.primaryGreen,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: TasksPalette.primaryGreen
                              .withValues(alpha: 0.3),
                          blurRadius: 20,
                          spreadRadius: 2),
                    ],
                  ),
                  child: const Icon(Icons.search_rounded,
                      color: Colors.white, size: 28),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('מחפשים נותני שירות...',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: TasksPalette.darkNavy)),
          const SizedBox(height: 6),
          Text('סורקים $_counter נותני שירות באזור שלך',
              style: const TextStyle(
                  fontSize: 12, color: TasksPalette.textSecondary)),
          const SizedBox(height: 16),
          _ElapsedTag(start: _start),
        ],
      ),
    );
  }
}

class _ElapsedTag extends StatefulWidget {
  final DateTime start;
  const _ElapsedTag({required this.start});

  @override
  State<_ElapsedTag> createState() => _ElapsedTagState();
}

class _ElapsedTagState extends State<_ElapsedTag> {
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _elapsed = DateTime.now().difference(widget.start));
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _elapsed.inSeconds;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: TasksPalette.bgPrimary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('ממתינים $s שניות',
          style: const TextStyle(
              fontSize: 11, color: TasksPalette.textSecondary)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════

class _LiveBanner extends StatelessWidget {
  final int count;
  const _LiveBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: TasksPalette.primaryGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(TasksPalette.rInput),
      ),
      child: Row(
        children: [
          const _PulseDot(),
          const SizedBox(width: 10),
          Expanded(
            child: Text('$count הצעות התקבלו — עוד מגיעות...',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: TasksPalette.primaryGreenDark)),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 14 * (0.6 + _c.value * 0.6),
                height: 14 * (0.6 + _c.value * 0.6),
                decoration: BoxDecoration(
                  color: TasksPalette.primaryGreen
                      .withValues(alpha: 0.25 * (1 - _c.value)),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: TasksPalette.primaryGreen,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// OFFER CARD — slide-in animation
// ═══════════════════════════════════════════════════════════════════

class _OfferCard extends StatefulWidget {
  final AnyTask task;
  final TaskResponse response;
  final Duration appearDelay;
  const _OfferCard({
    required this.task,
    required this.response,
    required this.appearDelay,
  });

  @override
  State<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<_OfferCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 360));
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
            begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(_opacity);
    Future.delayed(widget.appearDelay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int get _price =>
      widget.response.offeredPriceNis ?? widget.task.budgetNis;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: _buildCard(context),
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    final r = widget.response;
    return InkWell(
      onTap: () {
        // Hand off to the existing pick flow so escrow transaction rules
        // stay centralized in one place.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
              builder: (_) =>
                  CompareOffersScreen(taskId: widget.task.id!)),
        );
      },
      borderRadius: BorderRadius.circular(TasksPalette.rCard),
      child: Container(
        padding: const EdgeInsets.all(14),
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
                TasksAvatar(
                    name: r.providerName,
                    imageUrl: r.providerImage,
                    size: 44),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.providerName,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: TasksPalette.darkNavy)),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 5,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                              '★ ${r.providerRating.toStringAsFixed(1)}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: TasksPalette.primaryGreenDark)),
                          Text('· ${r.providerCompletedCount} משימות',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color:
                                      TasksPalette.textSecondary)),
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
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: TasksPalette.primaryGreenDark)),
                    if (r.distanceKm != null)
                      Text('~${r.distanceKm!.toStringAsFixed(1)} ק״מ',
                          style: const TextStyle(
                              fontSize: 10,
                              color: TasksPalette.textMuted)),
                  ],
                ),
              ],
            ),
            if (r.message.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('"${r.message}"',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12,
                      color: TasksPalette.textSecondary,
                      height: 1.4)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (r.responseType == 'accept')
                  _Badge(
                      label: '✓ מאשר את המחיר',
                      bg: TasksPalette.primaryGreen
                          .withValues(alpha: 0.1),
                      fg: TasksPalette.primaryGreenDark)
                else
                  _Badge(
                      label: '💰 מציע מחיר חלופי',
                      bg: TasksPalette.amberLight,
                      fg: TasksPalette.amber),
                const Spacer(),
                const Icon(Icons.chevron_left_rounded,
                    color: TasksPalette.textMuted, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _Badge({
    required this.label,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
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

class _KeepSearchingFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: () => Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MyTasksScreen()),
          (r) => false,
        ),
        icon: const Icon(Icons.arrow_back_rounded,
            color: TasksPalette.textSecondary, size: 16),
        label: const Text('נמשיך לחפש ונעדכן בהתראה',
            style: TextStyle(
                fontSize: 12, color: TasksPalette.textSecondary)),
      ),
    );
  }
}
