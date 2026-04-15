/// Shared reusable widgets for the bookings/orders screens.
///
/// Extracted from my_bookings_screen.dart (Phase 1 refactor).
/// All widgets are pure display — zero coupling to parent state.
library;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/safe_image_provider.dart';

// ── Profile avatar ─────────────────────────────────────────────────────────

class BookingProfileAvatar extends StatelessWidget {
  final String uid;
  final String name;
  final double size;

  const BookingProfileAvatar(
      {super.key, required this.uid, required this.name, this.size = 52});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snap) {
        final data =
            snap.data?.data() as Map<String, dynamic>? ?? {};
        final url = data['profileImage'] as String?;
        final img = safeImageProvider(url);
        return CircleAvatar(
          radius: size / 2,
          backgroundColor: const Color(0xFFEEF2FF),
          backgroundImage: img,
          child: img == null
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                      fontSize: size * 0.36,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF6366F1)),
                )
              : null,
        );
      },
    );
  }
}

// ── Status badge ──────────────────────────────────────────────────────────

class BookingStatusBadge extends StatelessWidget {
  final String status;

  const BookingStatusBadge(this.status, {super.key});

  static const _map = <String, (Color, Color, String)>{
    'paid_escrow':             (Color(0xFFFFF7ED), Color(0xFFF97316), 'בנאמנות'),
    'expert_completed':        (Color(0xFFEFF6FF), Color(0xFF3B82F6), 'ממתין לאישור'),
    'completed':               (Color(0xFFF0FFF4), Color(0xFF16A34A), 'הושלם'),
    'cancelled':               (Color(0xFFFFF5F5), Color(0xFFEF4444), 'בוטל'),
    'cancelled_with_penalty':  (Color(0xFFFFF5F5), Color(0xFFEF4444), 'בוטל+קנס'),
    'disputed':                (Color(0xFFFEF2F2), Color(0xFFDC2626), 'במחלוקת'),
    'refunded':                (Color(0xFFF0FDFA), Color(0xFF0D9488), 'הוחזר'),
    'split_resolved':          (Color(0xFFFAF5FF), Color(0xFF9333EA), 'פשרה'),
  };

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) =
        _map[status] ?? (const Color(0xFFF8FAFC), const Color(0xFF94A3B8), 'בטיפול');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              color: fg, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

// ── Keep alive wrapper ──────────────────────────────────────────────────────
//
// Flutter's TabBarView normally disposes non-visible tabs, which destroys
// the StreamBuilder state and forces a full Firestore re-fetch on every
// switch. This wrapper keeps the entire subtree alive in memory.

class BookingKeepAlivePage extends StatefulWidget {
  final Widget child;
  const BookingKeepAlivePage({super.key, required this.child});

  @override
  State<BookingKeepAlivePage> createState() => _BookingKeepAlivePageState();
}

class _BookingKeepAlivePageState extends State<BookingKeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by the mixin
    return widget.child;
  }
}

// ── Bookings shimmer skeleton ──────────────────────────────────────────────

class BookingsShimmer extends StatefulWidget {
  const BookingsShimmer({super.key});

  @override
  State<BookingsShimmer> createState() => _BookingsShimmerState();
}

class _BookingsShimmerState extends State<BookingsShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final opacity = 0.4 + _anim.value * 0.4;
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
          itemCount: 4,
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (_, __) => Opacity(
            opacity: opacity,
            child: Container(
              height: 110,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Container(height: 14, width: 120, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(6))),
                          Container(height: 10, width: 80,  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(6))),
                          Container(height: 10, width: 100, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(6))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Shared button widgets ──────────────────────────────────────────────────

class BookingPrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const BookingPrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(double.infinity, 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14)),
        onPressed: onPressed,
      ),
    );
  }
}

class BookingSecondaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const BookingSecondaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          minimumSize: const Size(double.infinity, 44),
          side: BorderSide(color: color.withValues(alpha: 0.40)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        icon: Icon(icon, size: 16),
        label: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        onPressed: onPressed,
      ),
    );
  }
}

class BookingQuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final VoidCallback? onPressed;

  const BookingQuickActionChip({
    super.key,
    required this.icon,
    required this.label,
    this.color = const Color(0xFFEEF2FF),
    this.iconColor = const Color(0xFF6366F1),
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
            color: onPressed == null
                ? const Color(0xFFF8FAFC)
                : color,
            borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 15,
                color: onPressed == null
                    ? const Color(0xFF94A3B8)
                    : iconColor),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: onPressed == null
                        ? const Color(0xFF94A3B8)
                        : iconColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
