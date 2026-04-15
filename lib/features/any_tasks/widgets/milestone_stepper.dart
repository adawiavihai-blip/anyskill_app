/// AnySkill — Milestone Stepper widget (AnyTasks v14.1.0)
///
/// Vertical timeline used by both the provider's Active Task screen and
/// the client's Task Tracking screen. Visual rules per design spec:
///   • Completed step: green circle (28px) + white check, line under: green
///   • Current step:   blue circle (28px), 2.5px blue border, light bg + dot
///   • Pending step:   empty circle, 0.5px border, gray title
///
/// Lines connect circles vertically (gap collapsed by overlapping rows).
library;

import 'package:flutter/material.dart';

import '../models/task_milestone.dart';
import '../theme/any_tasks_palette.dart';

class MilestoneStepper extends StatelessWidget {
  final List<TaskMilestone> items;

  /// Optional per-step trailing widget (e.g. provider "סמן כהושלם" button).
  final Widget? Function(TaskMilestone m, int idx)? trailingBuilder;

  const MilestoneStepper({
    super.key,
    required this.items,
    this.trailingBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text('אין שלבים',
          style: TextStyle(
              fontSize: 12, color: TasksPalette.textSecondary));
    }
    // Determine the "current" step = the first non-done step.
    final currentIdx = items.indexWhere((m) => !m.isDone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < items.length; i++)
          _StepRow(
            milestone: items[i],
            isCurrent: i == currentIdx,
            isLast: i == items.length - 1,
            trailing: trailingBuilder?.call(items[i], i),
          ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final TaskMilestone milestone;
  final bool isCurrent;
  final bool isLast;
  final Widget? trailing;

  const _StepRow({
    required this.milestone,
    required this.isCurrent,
    required this.isLast,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final done = milestone.isDone;
    final completedAt = milestone.completedAt;

    final Color circleBg;
    final Color circleBorder;
    final Widget? circleChild;
    final Color lineColor;
    final Color titleColor;
    final FontWeight titleWeight;
    final TextDecoration titleDecoration;

    if (done) {
      circleBg = TasksPalette.successGreen;
      circleBorder = TasksPalette.successGreen;
      circleChild = const Icon(Icons.check_rounded,
          size: 16, color: Colors.white);
      lineColor = TasksPalette.successGreen;
      titleColor = TasksPalette.textSecondary;
      titleWeight = FontWeight.w400;
      titleDecoration = TextDecoration.lineThrough;
    } else if (isCurrent) {
      circleBg = TasksPalette.escrowBlueLight;
      circleBorder = TasksPalette.escrowBlue;
      circleChild = Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
            color: TasksPalette.escrowBlue, shape: BoxShape.circle),
      );
      lineColor = TasksPalette.borderLight;
      titleColor = TasksPalette.textPrimary;
      titleWeight = FontWeight.w500;
      titleDecoration = TextDecoration.none;
    } else {
      circleBg = TasksPalette.cardWhite;
      circleBorder = TasksPalette.borderLight;
      circleChild = null;
      lineColor = TasksPalette.borderLight;
      titleColor = TasksPalette.textHint;
      titleWeight = FontWeight.w400;
      titleDecoration = TextDecoration.none;
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Circle + connecting line column ─────────────────────
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: circleBg,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: circleBorder, width: isCurrent ? 2.5 : 0.5),
                ),
                alignment: Alignment.center,
                child: circleChild,
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: lineColor),
                ),
            ],
          ),
          const SizedBox(width: 12),
          // ── Title + meta + trailing ─────────────────────────────
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(milestone.title,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: titleWeight,
                                color: titleColor,
                                decoration: titleDecoration,
                                decorationColor: titleColor)),
                      ),
                      if (trailing != null) trailing!,
                    ],
                  ),
                  if (isCurrent) ...[
                    const SizedBox(height: 2),
                    const Text('שלב נוכחי',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: TasksPalette.escrowBlue)),
                  ],
                  if (done && completedAt != null) ...[
                    const SizedBox(height: 2),
                    Text(_formatTime(completedAt),
                        style: const TextStyle(
                            fontSize: 10, color: TasksPalette.textHint)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final today = DateTime.now();
    final isToday =
        today.year == dt.year && today.month == dt.month && today.day == dt.day;
    return isToday ? 'הושלם ב-$h:$m' : 'הושלם ב-${dt.day}/${dt.month} $h:$m';
  }
}
