/// AnyTasks 3.0 — Task Card Widget
///
/// Reusable card for the browse feed. Shows title, category, amount,
/// location, deadline countdown, and status badge. RTL-first layout.
library;

import 'package:flutter/material.dart';
import '../models/anytask.dart';
import '../services/anytask_category_service.dart';
import 'anytask_status_badge.dart';

class AnytaskCard extends StatelessWidget {
  final AnyTask task;
  final VoidCallback? onTap;

  /// If true, shows the creator's name (for provider browse view).
  /// If false, shows the provider's name (for creator's "my tasks" view).
  final bool showCreator;

  const AnytaskCard({
    super.key,
    required this.task,
    this.onTap,
    this.showCreator = true,
  });

  static const _kIndigo = Color(0xFF6366F1);
  static const _kDark   = Color(0xFF1A1A2E);
  static const _kMuted  = Color(0xFF6B7280);
  static const _kGreen  = Color(0xFF10B981);
  static const _kAmber  = Color(0xFFF59E0B);
  static const _kRed    = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
          border: task.isUrgent
              ? Border.all(color: _kRed.withValues(alpha: 0.4), width: 1.5)
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row: category chip + amount badge ──────────────────
              Row(
                children: [
                  // Category chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _kIndigo.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          AnytaskCategoryService.iconFor(task.category),
                          size: 13,
                          color: _kIndigo,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          AnytaskCategoryService.labelHe(task.category),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _kIndigo,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (task.isUrgent) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _kRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'דחוף',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _kRed),
                      ),
                    ),
                  ],
                  const Spacer(),
                  // Amount badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_kGreen, Color(0xFF059669)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '₪${task.amount.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // ── Title ─────────────────────────────────────────────────
              Text(
                task.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _kDark,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),

              // ── Description preview ───────────────────────────────────
              Text(
                task.description,
                style: const TextStyle(fontSize: 13, color: _kMuted, height: 1.3),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),

              // ── Bottom row: metadata + status ─────────────────────────
              Row(
                children: [
                  // Location
                  if (task.locationText != null && task.locationText!.isNotEmpty) ...[
                    Icon(Icons.location_on_outlined, size: 13, color: _kMuted),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        task.locationText!,
                        style: const TextStyle(fontSize: 11, color: _kMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Deadline countdown
                  if (task.deadline != null) ...[
                    Icon(Icons.schedule_rounded, size: 13, color: _kAmber),
                    const SizedBox(width: 2),
                    Text(
                      _deadlineText(task.deadline!),
                      style: TextStyle(
                        fontSize: 11,
                        color: task.deadline!.isBefore(DateTime.now()) ? _kRed : _kAmber,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  const Spacer(),

                  // Status badge
                  if (task.status != AnyTaskStatus.open)
                    AnytaskStatusBadge(status: task.status),
                ],
              ),

              // ── Auto-release countdown (for proof_submitted) ──────────
              if (task.status == AnyTaskStatus.proofSubmitted &&
                  task.hoursUntilAutoRelease != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _kAmber.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_rounded, size: 14, color: _kAmber),
                      const SizedBox(width: 4),
                      Text(
                        'שחרור אוטומטי בעוד ${task.hoursUntilAutoRelease!.toStringAsFixed(0)} שעות',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _kAmber),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _deadlineText(DateTime deadline) {
    final diff = deadline.difference(DateTime.now());
    if (diff.isNegative) return 'פג תוקף';
    if (diff.inDays > 0) return 'עוד ${diff.inDays} ימים';
    if (diff.inHours > 0) return 'עוד ${diff.inHours} שעות';
    return 'עוד ${diff.inMinutes} דקות';
  }
}
