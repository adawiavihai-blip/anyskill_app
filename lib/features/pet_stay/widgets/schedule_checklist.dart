/// AnySkill — Schedule Checklist Widget (Pet Stay Tracker v13.0.0)
///
/// Renders a multi-day grouped checklist from a flat list of
/// [ScheduleItem]s. Tap the circle to toggle completion (provider only —
/// rules enforce).
library;

import 'package:flutter/material.dart';

import '../models/schedule_item.dart';
import '../services/pet_stay_service.dart';

class ScheduleChecklist extends StatelessWidget {
  final String jobId;
  final List<ScheduleItem> items;

  /// When false, checkboxes are read-only (customer view).
  final bool canToggle;

  const ScheduleChecklist({
    super.key,
    required this.jobId,
    required this.items,
    required this.canToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: const Text(
          'אין פריטים בלוח הזמנים',
          style: TextStyle(color: Color(0xFF6B7280)),
        ),
      );
    }

    // Group by dayKey (already sorted by the stream).
    final groups = <String, List<ScheduleItem>>{};
    for (final it in items) {
      groups.putIfAbsent(it.dayKey, () => []).add(it);
    }

    final dayKeys = groups.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < dayKeys.length; i++) ...[
          _dayHeader(dayKeys[i], i + 1, groups[dayKeys[i]]!),
          const SizedBox(height: 8),
          for (final item in groups[dayKeys[i]]!)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ItemRow(
                jobId: jobId,
                item: item,
                canToggle: canToggle,
              ),
            ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _dayHeader(
      String dayKey, int dayNumber, List<ScheduleItem> dayItems) {
    final completed = dayItems.where((i) => i.completed).length;
    final total = dayItems.length;
    final pct = total == 0 ? 0.0 : completed / total;
    final parts = dayKey.split('-');
    final label = parts.length == 3 ? '${parts[2]}/${parts[1]}' : dayKey;

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 14, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF6366F1).withValues(alpha: 0.08),
            const Color(0xFF8B5CF6).withValues(alpha: 0.04),
          ],
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$dayNumber',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'יום $dayNumber · $label',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 4,
                    backgroundColor: const Color(0xFFE5E7EB),
                    valueColor: const AlwaysStoppedAnimation(
                        Color(0xFF10B981)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$completed/$total',
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF10B981),
                fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final String jobId;
  final ScheduleItem item;
  final bool canToggle;

  const _ItemRow({
    required this.jobId,
    required this.item,
    required this.canToggle,
  });

  @override
  Widget build(BuildContext context) {
    final style = _typeStyle(item.type);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: item.completed ? const Color(0xFFECFDF5) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.completed
              ? const Color(0xFF86EFAC)
              : const Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: style.bg,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(style.icon, color: style.fg, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.time,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: item.completed
                              ? const Color(0xFF065F46)
                              : const Color(0xFF1A1A2E),
                          decoration: item.completed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
                if (item.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.description,
                    style: const TextStyle(
                        color: Color(0xFF6B7280), fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _Checkbox(
            completed: item.completed,
            enabled: canToggle && item.id != null,
            onTap: () async {
              if (!canToggle || item.id == null) return;
              try {
                await PetStayService.instance.toggleScheduleItem(
                  jobId: jobId,
                  itemId: item.id!,
                  completed: !item.completed,
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('שגיאה: $e')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  ({Color bg, Color fg, IconData icon}) _typeStyle(String type) {
    switch (type) {
      case 'feed':
        return (
          bg: const Color(0xFFFEF3C7),
          fg: const Color(0xFFD97706),
          icon: Icons.restaurant_rounded,
        );
      case 'walk':
        return (
          bg: const Color(0xFFECFDF5),
          fg: const Color(0xFF059669),
          icon: Icons.directions_walk_rounded,
        );
      case 'medication':
        return (
          bg: const Color(0xFFFEF2F2),
          fg: const Color(0xFFDC2626),
          icon: Icons.medication_rounded,
        );
      case 'play':
        return (
          bg: const Color(0xFFEFF6FF),
          fg: const Color(0xFF2563EB),
          icon: Icons.sports_baseball_rounded,
        );
      case 'sleep':
        return (
          bg: const Color(0xFFF3F4F6),
          fg: const Color(0xFF6B7280),
          icon: Icons.bedtime_rounded,
        );
      default:
        return (
          bg: const Color(0xFFF3F4F6),
          fg: const Color(0xFF6B7280),
          icon: Icons.check_rounded,
        );
    }
  }
}

class _Checkbox extends StatelessWidget {
  final bool completed;
  final bool enabled;
  final VoidCallback onTap;

  const _Checkbox({
    required this.completed,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: completed
              ? const Color(0xFF10B981)
              : Colors.transparent,
          border: Border.all(
            color: completed
                ? const Color(0xFF10B981)
                : (enabled
                    ? const Color(0xFF6366F1)
                    : const Color(0xFFD1D5DB)),
            width: 2,
          ),
        ),
        child: completed
            ? const Icon(Icons.check_rounded,
                color: Colors.white, size: 18)
            : null,
      ),
    );
  }
}
