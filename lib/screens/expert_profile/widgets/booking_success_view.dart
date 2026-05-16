import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// Bottom-sheet content shown after a successful "Pay & Secure" booking,
/// or after a demo-profile booking that's routed to the admin desk.
///
/// Extracted from `expert_profile_screen.dart` in §80 (file-splitting
/// refactor). The view is purely presentational — no Firestore, no
/// setState. The single side-effect is `Navigator.of(ctx).pop()` from
/// the "Got it" button.
///
/// `isDemo` switches:
///   • Icon: hourglass (demo) vs. check circle (real)
///   • Color: indigo (demo) vs. green (real)
///   • Title + subtitle: l10n keys differ
///   • Adds an "we'll notify you" pill for demo flow
class BookingSuccessView extends StatelessWidget {
  const BookingSuccessView({
    super.key,
    required this.isDemo,
  });

  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accentColor = isDemo
        ? const Color(0xFF6366F1) // indigo for demo
        : const Color(0xFF22C55E); // green for real bookings

    final title = isDemo
        ? l10n.expBookingReceivedDemo
        : l10n.expBookingSuccess;

    final subtitle = isDemo
        ? l10n.expBookingDemoBody
        : l10n.expertEscrowSuccess;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Animated icon circle ─────────────────────────────────────────
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isDemo
                    ? Icons.hourglass_top_rounded
                    : Icons.check_circle_rounded,
                color: accentColor,
                size: 64,
              ),
            ),
          ),
          const SizedBox(height: 28),
          // ── Title ────────────────────────────────────────────────────────
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E1B4B),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: const TextStyle(
                fontSize: 14, color: Colors.grey, height: 1.5),
            textAlign: TextAlign.center,
          ),
          if (isDemo) ...[
            const SizedBox(height: 16),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.notifications_active_outlined,
                      color: Color(0xFF6366F1), size: 16),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      l10n.expWillNotify,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 36),
          // ── Done button — only place pop() is called ─────────────────────
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              l10n.expGotIt,
              style: const TextStyle(
                  fontSize: 17,
                  color: Colors.white,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
