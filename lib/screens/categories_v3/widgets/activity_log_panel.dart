import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/categories_v3_controller.dart';
import '../models/activity_log_entry.dart';

/// Slide-in activity log panel rendered as an overlay on the v3 tab.
///
/// Per spec §7.9:
///   - Slides in from the visual end side (= start side in RTL = visually
///     left for Hebrew). 360px on desktop, full-screen on mobile.
///   - List of log entries with a colored dot per action type.
///   - Each entry: dot · "{admin} {verb} {target}" · time-ago · undo link.
///   - Lazy-load older entries on scroll (Phase D ships limit=50; "load more"
///     deferred unless QA shows it's needed).
class ActivityLogPanel extends ConsumerStatefulWidget {
  const ActivityLogPanel({
    super.key,
    required this.open,
    required this.onClose,
  });

  final bool open;
  final VoidCallback onClose;

  @override
  ConsumerState<ActivityLogPanel> createState() => _ActivityLogPanelState();
}

class _ActivityLogPanelState extends ConsumerState<ActivityLogPanel> {
  ActivityTargetType? _filter;

  @override
  Widget build(BuildContext context) {
    final mediaWidth = MediaQuery.sizeOf(context).width;
    final isMobile = mediaWidth < 720;
    final width = isMobile ? mediaWidth : 360.0;

    return IgnorePointer(
      ignoring: !widget.open,
      child: Stack(
        children: [
          // Scrim
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: widget.open ? 0.35 : 0,
            child: GestureDetector(
              onTap: widget.onClose,
              child: Container(color: Colors.black),
            ),
          ),
          // Panel — slides from start side (visual right→left in LTR; in RTL
          // the slide visually appears from the LEFT, which is the "end" of
          // the RTL flow. Per spec §7.9 "slide in from right (RTL = from left
          // visually)" — exactly what AnimatedPositionedDirectional does.
          AnimatedPositionedDirectional(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            top: 0,
            bottom: 0,
            start: widget.open ? 0 : -width,
            width: width,
            child: Material(
              elevation: 12,
              color: Colors.white,
              child: SafeArea(
                child: Column(
                  children: [
                    _Header(onClose: widget.onClose),
                    _FilterStrip(
                      current: _filter,
                      onChange: (f) => setState(() => _filter = f),
                    ),
                    Expanded(
                      child: _ActivityList(filter: _filter),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsetsDirectional.fromSTEB(14, 12, 8, 12),
      child: Row(
        children: [
          const Icon(Icons.history_rounded,
              size: 20, color: Color(0xFF6366F1)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'יומן פעולות',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 20),
            tooltip: 'סגור (Esc)',
          ),
        ],
      ),
    );
  }
}

class _FilterStrip extends StatelessWidget {
  const _FilterStrip({required this.current, required this.onChange});
  final ActivityTargetType? current;
  final ValueChanged<ActivityTargetType?> onChange;

  @override
  Widget build(BuildContext context) {
    final entries = <(ActivityTargetType?, String)>[
      (null, 'הכל'),
      (ActivityTargetType.category, 'קטגוריות'),
      (ActivityTargetType.subcategory, 'תתי'),
      (ActivityTargetType.banner, 'באנרים'),
    ];
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 14),
      child: Wrap(
        spacing: 6,
        children: entries.map((e) {
          final selected = current == e.$1;
          return ChoiceChip(
            label: Text(e.$2, style: const TextStyle(fontSize: 11.5)),
            selected: selected,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onSelected: (_) => onChange(e.$1),
            selectedColor: const Color(0xFF6366F1).withValues(alpha: 0.18),
            backgroundColor: const Color(0xFFF7F7F2),
            labelStyle: TextStyle(
              color: selected
                  ? const Color(0xFF6366F1)
                  : const Color(0xFF6B7280),
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            side: BorderSide(
              color: selected
                  ? const Color(0xFF6366F1).withValues(alpha: 0.4)
                  : Colors.transparent,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ActivityList extends ConsumerWidget {
  const _ActivityList({required this.filter});
  final ActivityTargetType? filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use the unfiltered live stream and apply the target-type filter
    // client-side. The CategoriesV3Service exposes a server-filtered stream
    // (`watchByTarget`) — we'll wire that as a separate provider in Phase E
    // if performance becomes an issue. With limit=50 client-side filtering
    // is negligible.
    final stream = ref.watch(activityLogStreamProvider());

    return stream.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(16),
          child: Text(
            'שגיאה בטעינת היומן: $e',
            style: const TextStyle(color: Color(0xFFEF4444)),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (allEntries) {
        final entries = filter == null
            ? allEntries
            : allEntries.where((e) => e.targetType == filter).toList();
        if (entries.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsetsDirectional.all(24),
              child: Text(
                'אין פעולות עדיין.\nכל שינוי שתעשה יופיע כאן.',
                style: TextStyle(color: Color(0xFF9CA3AF)),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 14, vertical: 8),
          itemCount: entries.length,
          separatorBuilder: (_, __) => const SizedBox(height: 4),
          itemBuilder: (_, i) => _LogTile(entry: entries[i]),
        );
      },
    );
  }
}

class _LogTile extends ConsumerWidget {
  const _LogTile({required this.entry});
  final ActivityLogEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reversed = entry.isReversed;
    return Container(
      padding:
          const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: reversed ? const Color(0xFFF9FAFB) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Colored dot
          Container(
            margin: const EdgeInsetsDirectional.only(top: 5, end: 8),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: reversed
                  ? const Color(0xFF9CA3AF)
                  : entry.dotColor,
              shape: BoxShape.circle,
            ),
          ),
          // Body
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF1A1A2E),
                      height: 1.3,
                    ),
                    children: [
                      TextSpan(
                        text: entry.adminName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: ' ${entry.hebrewVerb} '),
                      TextSpan(
                        text: entry.targetName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      _relative(entry.createdAt),
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                    if (entry.isReversible && !reversed) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () =>
                            ref.read(activityLogServiceProvider).undo(entry),
                        child: const Padding(
                          padding: EdgeInsetsDirectional.all(2),
                          child: Text(
                            'בטל',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF6366F1),
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (reversed) ...[
                      const SizedBox(width: 8),
                      const Text(
                        '✓ בוטלה',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF9CA3AF),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _relative(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'לפני כמה שניות';
    if (diff.inMinutes < 60) return 'לפני ${diff.inMinutes} דק׳';
    if (diff.inHours < 24) return 'לפני ${diff.inHours} שעות';
    if (diff.inDays < 7) return 'לפני ${diff.inDays} ימים';
    return 'לפני ${(diff.inDays / 7).floor()} שבועות';
  }
}
