/// AnySkill — Task Lifecycle Stepper (AnyTasks v14.3.0)
///
/// 6-stage Uber-style timeline used on the client Task Tracking screen
/// to replace the per-category milestone stepper. Derives the current
/// stage from the task's status + timestamp fields; each stage can be
/// done (green check), current (pulsing dot), or pending (grey).
library;

import 'package:flutter/material.dart';

import '../models/any_task.dart';
import '../theme/any_tasks_palette.dart';

class TaskLifecycleStepper extends StatelessWidget {
  final AnyTask task;
  const TaskLifecycleStepper({super.key, required this.task});

  /// Returns the highest reached stage index (0..5).
  int _currentStage() {
    // 5: both reviews submitted
    if (task.status == 'completed' &&
        task.clientReviewDone &&
        task.providerReviewDone) {
      return 5;
    }
    // 4: proof submitted or task completed
    if (task.proofSubmittedAt != null ||
        task.status == 'proof_submitted' ||
        task.status == 'completed') {
      return 4;
    }
    // 3: provider tapped "התחלתי"
    if (task.workStartedAt != null) return 3;
    // 2: provider tapped "בדרך"
    if (task.expertOnWayAt != null) return 2;
    // 1: provider was picked (escrow charged)
    if (task.acceptedAt != null || task.status == 'in_progress') return 1;
    // 0: task was published
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentStage();
    final stages = _stages();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < stages.length; i++)
          _StageRow(
            stage: stages[i],
            isDone: i < current,
            isCurrent: i == current,
            isLast: i == stages.length - 1,
            timestamp: _timestampFor(i),
          ),
      ],
    );
  }

  DateTime? _timestampFor(int i) {
    switch (i) {
      case 0: return task.createdAt;
      case 1: return task.acceptedAt;
      case 2: return task.expertOnWayAt;
      case 3: return task.workStartedAt;
      case 4: return task.proofSubmittedAt ?? task.completedAt;
      case 5: return task.completedAt;
      default: return null;
    }
  }

  List<_StageSpec> _stages() => const [
    _StageSpec('📢', 'פורסמה', 'המשימה פורסמה ומחכה להצעות'),
    _StageSpec('🤝', 'נותן שירות נבחר',
        'בחרת נותן שירות — הכסף הועבר לאסקרו'),
    _StageSpec('🚗', 'בדרך אליך',
        'נותן השירות יצא לדרך'),
    _StageSpec('⚡', 'בביצוע',
        'המשימה מתבצעת כרגע'),
    _StageSpec('✅', 'בוצע',
        'נותן השירות סיים ושלח הוכחת השלמה'),
    _StageSpec('⭐', 'דורג',
        'שני הצדדים דירגו'),
  ];
}

class _StageSpec {
  final String emoji;
  final String title;
  final String subtitle;
  const _StageSpec(this.emoji, this.title, this.subtitle);
}

class _StageRow extends StatelessWidget {
  final _StageSpec stage;
  final bool isDone;
  final bool isCurrent;
  final bool isLast;
  final DateTime? timestamp;

  const _StageRow({
    required this.stage,
    required this.isDone,
    required this.isCurrent,
    required this.isLast,
    required this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    final Color bubbleColor;
    final Color bubbleBorder;
    final Widget bubbleChild;
    final Color lineColor;
    final Color titleColor;
    final FontWeight titleWeight;
    final double opacity;

    if (isDone) {
      bubbleColor = TasksPalette.primaryGreen;
      bubbleBorder = TasksPalette.primaryGreen;
      bubbleChild = const Icon(Icons.check_rounded,
          color: Colors.white, size: 18);
      lineColor = TasksPalette.primaryGreen;
      titleColor = TasksPalette.darkNavy;
      titleWeight = FontWeight.w500;
      opacity = 1.0;
    } else if (isCurrent) {
      bubbleColor = TasksPalette.escrowBlueLight;
      bubbleBorder = TasksPalette.escrowBlue;
      bubbleChild = const _PulsingDot();
      lineColor = TasksPalette.borderLight;
      titleColor = TasksPalette.darkNavy;
      titleWeight = FontWeight.w700;
      opacity = 1.0;
    } else {
      bubbleColor = TasksPalette.cardWhite;
      bubbleBorder = TasksPalette.borderLight;
      bubbleChild = Text(stage.emoji,
          style: const TextStyle(fontSize: 16));
      lineColor = TasksPalette.borderLight;
      titleColor = TasksPalette.textSecondary;
      titleWeight = FontWeight.w400;
      opacity = 0.4;
    }

    return Opacity(
      opacity: opacity,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: bubbleBorder,
                        width: isCurrent ? 2.5 : 1),
                    boxShadow: isCurrent
                        ? [
                            BoxShadow(
                                color: TasksPalette.escrowBlue
                                    .withValues(alpha: 0.25),
                                blurRadius: 10,
                                spreadRadius: 2),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: bubbleChild,
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                        width: 2, color: lineColor),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(stage.title,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: titleWeight,
                                  color: titleColor)),
                        ),
                        if (isCurrent)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                                color: TasksPalette.escrowBlueLight,
                                borderRadius:
                                    BorderRadius.circular(10)),
                            child: const Text('עכשיו',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: TasksPalette.escrowBlue)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(stage.subtitle,
                        style: const TextStyle(
                            fontSize: 12,
                            color: TasksPalette.textSecondary,
                            height: 1.3)),
                    if (timestamp != null && (isDone || isCurrent)) ...[
                      const SizedBox(height: 4),
                      Text(_formatTs(timestamp!),
                          style: const TextStyle(
                              fontSize: 11,
                              color: TasksPalette.textMuted)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTs(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'הרגע';
    if (diff.inMinutes < 60) return 'לפני ${diff.inMinutes}ד׳';
    if (diff.inHours < 24) return 'לפני ${diff.inHours} שעות';
    return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return Container(
          width: 12 + 2 * _c.value,
          height: 12 + 2 * _c.value,
          decoration: BoxDecoration(
            color: TasksPalette.escrowBlue,
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
