import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'design_tokens.dart';

/// Section 8 (right column) — live activity stream for monetization events.
/// Streams `activity_log` where `category == 'monetization'` limit 5.
class ActivityTimeline extends StatelessWidget {
  const ActivityTimeline({super.key, required this.stream});

  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return _empty('שגיאה בטעינת היומן');
        }
        if (!snap.hasData) {
          return const SizedBox(
            height: 120,
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) return _empty('אין פעילות אחרונה');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: docs.map((d) {
            final data = d.data();
            final action = (data['action'] ?? data['type'] ?? '').toString();
            final detail =
                (data['detail'] ?? data['title'] ?? data['message'] ?? '')
                    .toString();
            final ts = data['timestamp'] ?? data['createdAt'];
            return _buildRow(action: action, detail: detail, ts: ts);
          }).toList(),
        );
      },
    );
  }

  Widget _empty(String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
                fontSize: 12, color: MonetizationTokens.textTertiary),
          ),
        ),
      );

  Widget _buildRow({
    required String action,
    required String detail,
    required dynamic ts,
  }) {
    final (icon, color) = _iconFor(action);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 13, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.isEmpty ? _actionLabel(action) : detail,
                  style: const TextStyle(
                      fontSize: 12, color: MonetizationTokens.textPrimary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(_relativeTime(ts),
                    style: const TextStyle(
                        fontSize: 10,
                        color: MonetizationTokens.textTertiary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color) _iconFor(String action) {
    if (action.contains('release') || action.contains('completed')) {
      return (Icons.check_circle_rounded, MonetizationTokens.success);
    }
    if (action.contains('refund')) {
      return (Icons.undo_rounded, MonetizationTokens.danger);
    }
    if (action.contains('commission_updated')) {
      return (Icons.percent_rounded, MonetizationTokens.primary);
    }
    if (action.contains('escrow') || action.contains('paid')) {
      return (Icons.lock_clock_rounded, MonetizationTokens.warning);
    }
    if (action.contains('vip')) {
      return (Icons.star_rounded, MonetizationTokens.warningVivid);
    }
    if (action.contains('insight') || action.contains('ai_')) {
      return (Icons.auto_awesome_rounded, MonetizationTokens.primaryDark);
    }
    return (Icons.circle_outlined, MonetizationTokens.textTertiary);
  }

  String _actionLabel(String action) {
    return switch (action) {
      'commission_updated_global'      => 'עמלה גלובלית עודכנה',
      'commission_updated_category'    => 'עמלת קטגוריה עודכנה',
      'commission_updated_for_user'    => 'עמלה פרטנית עודכנה',
      'smart_rules_updated'            => 'כללים חכמים עודכנו',
      _ => action,
    };
  }

  String _relativeTime(dynamic ts) {
    if (ts is! Timestamp) return '—';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1) return 'עכשיו';
    if (diff.inHours < 1) return 'לפני ${diff.inMinutes} דקות';
    if (diff.inDays < 1) return 'לפני ${diff.inHours} שעות';
    return 'לפני ${diff.inDays} ימים';
  }
}
