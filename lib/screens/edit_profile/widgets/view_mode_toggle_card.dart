import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/view_mode_service.dart';

/// Tri-state view-mode toggle (Admin / Provider / Customer).
///
/// Extracted from `edit_profile_screen.dart` in §81 (C.6). The widget is
/// stateful because it reads `ViewModeService.instance.mode` directly +
/// auto-corrects a stuck `providerOnly` mode for non-admins. The
/// [isAdmin] flag comes from the parent (which has the role-check logic).
///
/// Tapping a chip:
///   1. Persists the new mode via `ViewModeService.setMode`
///   2. Pops the navigator to root (so the home tab re-evaluates the
///      effective role and re-renders the right shell)
///   3. Shows a Hebrew success snackbar
class ViewModeToggleCard extends StatefulWidget {
  const ViewModeToggleCard({super.key, required this.isAdmin});

  final bool isAdmin;

  @override
  State<ViewModeToggleCard> createState() => _ViewModeToggleCardState();
}

class _ViewModeToggleCardState extends State<ViewModeToggleCard> {
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    var current = ViewModeService.instance.mode;

    // Auto-correct a stuck providerOnly mode for non-admins.
    if (!widget.isAdmin && current == ViewMode.providerOnly) {
      // ignore: discarded_futures
      ViewModeService.instance.setMode(uid: uid, mode: ViewMode.normal);
      current = ViewMode.normal;
    }

    Future<void> apply(ViewMode target, String successMsg) async {
      await ViewModeService.instance.setMode(uid: uid, mode: target);
      if (!context.mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMsg),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    final l = AppLocalizations.of(context);
    final chips = <Widget>[
      if (widget.isAdmin)
        _ModeChip(
          label: l.editManagement,
          icon: Icons.admin_panel_settings_rounded,
          selected: current == ViewMode.normal,
          gradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          onTap: () => apply(ViewMode.normal, l.editAdminModeActive),
        ),
      _ModeChip(
        label: l.editServiceProvider,
        icon: Icons.work_outline_rounded,
        selected: widget.isAdmin
            ? current == ViewMode.providerOnly
            : current == ViewMode.normal,
        gradient: const [Color(0xFF0EA5E9), Color(0xFF3B82F6)],
        onTap: () => apply(
          widget.isAdmin ? ViewMode.providerOnly : ViewMode.normal,
          l.editProviderModeActive,
        ),
      ),
      _ModeChip(
        label: l.editCustomer,
        icon: Icons.visibility_rounded,
        selected: current == ViewMode.customer,
        gradient: const [Color(0xFF10B981), Color(0xFF22C55E)],
        onTap: () => apply(ViewMode.customer, l.editCustomerModeActive),
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 2, bottom: 8),
            child: Text(
              l.editViewMode,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
          Row(
            textDirection: TextDirection.rtl,
            children: [
              for (int i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: chips[i]),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.gradient,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding:
              const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: gradient,
                  )
                : null,
            color: selected ? null : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : const Color(0xFFE5E7EB),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: gradient.first.withValues(alpha: 0.30),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? Colors.white : const Color(0xFF6B7280),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color:
                      selected ? Colors.white : const Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
