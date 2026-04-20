import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/categories_v3_controller.dart';

/// Sticky bottom bar that appears when [SelectionController.count] > 0.
/// Per spec §7.7: black background, white text, RTL — count + cancel on the
/// trailing side, action buttons on the leading side.
///
/// Actions wired in Phase C: hide/unhide, pin/unpin, delete (with confirm).
/// "Move to parent" (העבר להורה) lands in Phase D inside the Edit dialog.
class BulkActionsBar extends ConsumerWidget {
  const BulkActionsBar({
    super.key,
    required this.onBulkHide,
    required this.onBulkPin,
    required this.onBulkDelete,
  });

  final VoidCallback onBulkHide;
  final VoidCallback onBulkPin;
  final VoidCallback onBulkDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(selectionControllerProvider);
    return AnimatedBuilder(
      animation: selection,
      builder: (context, _) {
        final count = selection.count;
        final visible = count > 0;
        return AnimatedSlide(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          offset: visible ? Offset.zero : const Offset(0, 1.2),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: visible ? 1 : 0,
            child: IgnorePointer(
              ignoring: !visible,
              child: Container(
                margin: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Leading: action buttons
                    _ActionBtn(
                      icon: Icons.visibility_off_rounded,
                      label: 'הסתר',
                      onTap: onBulkHide,
                    ),
                    const SizedBox(width: 6),
                    _ActionBtn(
                      icon: Icons.push_pin_rounded,
                      label: 'קדם',
                      onTap: onBulkPin,
                    ),
                    const SizedBox(width: 6),
                    _ActionBtn(
                      icon: Icons.delete_outline_rounded,
                      label: 'מחק',
                      onTap: onBulkDelete,
                      destructive: true,
                    ),

                    const Spacer(),

                    // Trailing: count + cancel
                    Container(
                      padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$count נבחרו',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => ref
                          .read(selectionControllerProvider)
                          .clear(),
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsetsDirectional.all(6),
                        child: Text(
                          'ביטול',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? const Color(0xFFEF4444) : Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding:
              const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
