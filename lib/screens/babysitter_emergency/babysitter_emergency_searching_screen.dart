// Step 3 of the babysitter emergency flow — radar / live stats while
// providers are notified and submit offers.
//
// Mirrors FlashAuctionSearchingScreen (CLAUDE.md §57) with babysitter
// copy + softer pink/purple radar colors.
//
// State transitions (driven by BabysitterEmergencyService.watchEmergency):
//   • status='has_offers' OR offerCount > 0 → push offers screen
//   • status='matched' (rare race) → push offers screen (it pops itself)
//   • status='expired' → in-place panel + "נסה שוב" CTA
//   • status='cancelled' → pop with friendly message
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/babysitter_emergency_constants.dart';
import '../../models/babysitter_emergency.dart';
import '../../services/babysitter_emergency_service.dart';
import 'babysitter_emergency_offers_screen.dart';
import 'babysitter_emergency_palette.dart';

class BabysitterEmergencySearchingScreen extends StatefulWidget {
  final String emergencyId;
  final String reason;
  final int numChildren;
  final DateTime agreedStartTime;
  final DateTime agreedEndTime;

  const BabysitterEmergencySearchingScreen({
    super.key,
    required this.emergencyId,
    required this.reason,
    required this.numChildren,
    required this.agreedStartTime,
    required this.agreedEndTime,
  });

  @override
  State<BabysitterEmergencySearchingScreen> createState() =>
      _BabysitterEmergencySearchingScreenState();
}

class _BabysitterEmergencySearchingScreenState
    extends State<BabysitterEmergencySearchingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _radarCtrl;
  StreamSubscription<BabysitterEmergency?>? _emergencySub;
  bool _navigatedToOffers = false;
  int _elapsedSeconds = 0;
  Timer? _tickTimer;
  bool _expired = false;
  bool _cancelled = false;
  String? _expiredReasonHebrew;

  BabysitterEmergency? _latest;

  @override
  void initState() {
    super.initState();
    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
    });

    _emergencySub = BabysitterEmergencyService.watchEmergency(
      widget.emergencyId,
    ).listen((doc) {
      if (!mounted || doc == null) return;
      _latest = doc;
      // Offer arrived → push offers screen.
      if (!_navigatedToOffers &&
          (doc.status == BabysitterEmergencyStatus.hasOffers ||
              doc.offerCount > 0 ||
              doc.status == BabysitterEmergencyStatus.matched)) {
        _navigatedToOffers = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => BabysitterEmergencyOffersScreen(
                emergencyId: widget.emergencyId,
              ),
            ),
          );
        });
        return;
      }
      if (doc.status == BabysitterEmergencyStatus.expired) {
        setState(() {
          _expired = true;
          _expiredReasonHebrew = doc.expiredReasonHebrew ??
              'לא נמצאה מטפלת זמינה ב-2 הדקות הקרובות';
        });
      }
      if (doc.status == BabysitterEmergencyStatus.cancelled) {
        setState(() => _cancelled = true);
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _radarCtrl.dispose();
    _tickTimer?.cancel();
    _emergencySub?.cancel();
    super.dispose();
  }

  Future<void> _cancelAndExit() async {
    HapticFeedback.lightImpact();
    try {
      await BabysitterEmergencyService.cancelEmergency(
        emergencyId: widget.emergencyId,
        reason: 'customer_cancelled_searching',
      );
    } catch (_) {
      // Even if cancellation write fails, return — UX matters more
      // than perfect server state. The CF will expire it eventually.
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _retry() async {
    HapticFeedback.lightImpact();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: BabyEmergencyPalette.bgPrimary,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Header
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: BabyEmergencyPalette.textPrimary),
                      onPressed: _cancelAndExit,
                    ),
                    const Spacer(),
                    if (!_expired && !_cancelled)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: BabyEmergencyPalette.purple50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: BabyEmergencyPalette.purple500
                                .withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.timer_outlined,
                                size: 14,
                                color: BabyEmergencyPalette.purple700),
                            const SizedBox(width: 4),
                            Text(
                              '${_elapsedSeconds}s',
                              style: const TextStyle(
                                color: BabyEmergencyPalette.purple700,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _expired
                      ? _ExpiredPanel(
                          reason: _expiredReasonHebrew,
                          onRetry: _retry,
                        )
                      : _cancelled
                          ? _CancelledPanel(onClose: () =>
                              Navigator.pop(context))
                          : _SearchingBody(
                              radarCtrl: _radarCtrl,
                              numChildren: widget.numChildren,
                              latest: _latest,
                              elapsedSeconds: _elapsedSeconds,
                            ),
                ),
                if (!_expired && !_cancelled)
                  TextButton.icon(
                    onPressed: _cancelAndExit,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('בטלי את הקריאה'),
                    style: TextButton.styleFrom(
                      foregroundColor: BabyEmergencyPalette.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Body widgets (private)
// ═════════════════════════════════════════════════════════════════════════

class _SearchingBody extends StatelessWidget {
  final AnimationController radarCtrl;
  final int numChildren;
  final BabysitterEmergency? latest;
  final int elapsedSeconds;

  const _SearchingBody({
    required this.radarCtrl,
    required this.numChildren,
    required this.latest,
    required this.elapsedSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final notified = latest?.notifiedProviderIds.length ?? 0;
    final offers = latest?.offerCount ?? 0;
    final radius = latest?.currentRadiusKm
            .toStringAsFixed(0) ??
        BabysitterEmergencyConfig.initialRadiusKm.toStringAsFixed(0);

    final stage = elapsedSeconds < BabysitterEmergencyConfig.expandToTier2After
        ? 'בודקים מטפלות בקרבת מקום'
        : elapsedSeconds < BabysitterEmergencyConfig.expandToTier3After
            ? 'מרחיבים את החיפוש'
            : 'מאריכים אזור החיפוש';

    return Column(
      children: [
        const SizedBox(height: 16),
        // Radar
        SizedBox(
          width: 220,
          height: 220,
          child: AnimatedBuilder(
            animation: radarCtrl,
            builder: (_, __) => CustomPaint(
              painter: _RadarPainter(progress: radarCtrl.value),
              child: Center(
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [
                        BabyEmergencyPalette.pink400,
                        BabyEmergencyPalette.purple500,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: BabyEmergencyPalette.purple500
                            .withValues(alpha: 0.4),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      numChildren == 1 ? '👶' : '👨‍👩‍👧‍👦',
                      style: const TextStyle(fontSize: 38),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'מחפשות לך בייביסיטר',
          style: TextStyle(
            color: BabyEmergencyPalette.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          stage,
          style: const TextStyle(
            color: BabyEmergencyPalette.textSecondary,
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        // Live stats grid
        Row(
          children: [
            Expanded(
              child: _StatCard(
                value: '$notified',
                label: 'מטפלות קיבלו התראה',
                accent: BabyEmergencyPalette.purple500,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                value: '$offers',
                label: 'הצעות התקבלו',
                accent: BabyEmergencyPalette.pink400,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                value: '$radius ק"מ',
                label: 'רדיוס חיפוש',
                accent: BabyEmergencyPalette.amber500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color accent;
  const _StatCard({
    required this.value,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: BoxDecoration(
        color: BabyEmergencyPalette.bgPrimary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: BabyEmergencyPalette.borderTertiary,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: BabyEmergencyPalette.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ExpiredPanel extends StatelessWidget {
  final String? reason;
  final VoidCallback onRetry;
  const _ExpiredPanel({required this.reason, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: BabyEmergencyPalette.amber50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.timer_off_rounded,
                  size: 48, color: BabyEmergencyPalette.amber700),
            ),
            const SizedBox(height: 18),
            const Text(
              'לא נמצאה בייביסיטר זמינה',
              style: TextStyle(
                color: BabyEmergencyPalette.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              reason ?? 'נסי שוב, או חפשי בקטגוריה הרגילה.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: BabyEmergencyPalette.textSecondary,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: BabyEmergencyPalette.purple500,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'חזרי לפרטים',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CancelledPanel extends StatelessWidget {
  final VoidCallback onClose;
  const _CancelledPanel({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline_rounded,
              size: 56, color: BabyEmergencyPalette.green500),
          const SizedBox(height: 12),
          const Text(
            'הקריאה בוטלה',
            style: TextStyle(
              color: BabyEmergencyPalette.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          TextButton(onPressed: onClose, child: const Text('סגרי')),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Radar painter — 3 staggered breathing rings
// ═════════════════════════════════════════════════════════════════════════

class _RadarPainter extends CustomPainter {
  final double progress;
  _RadarPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // 3 rings, staggered
    for (int i = 0; i < 3; i++) {
      final phase = (progress + i * 0.33) % 1.0;
      final radius = maxRadius * phase;
      final opacity = (1 - phase).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = BabyEmergencyPalette.purple500.withValues(alpha: opacity * 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius, paint);
    }

    // Decorative dots that orbit slowly
    final dotPaint = Paint()
      ..color = BabyEmergencyPalette.pink400.withValues(alpha: 0.7);
    for (int i = 0; i < 6; i++) {
      final angle = (progress * 2 * math.pi) + (i * math.pi / 3);
      final r = maxRadius * 0.85;
      final dx = center.dx + r * math.cos(angle);
      final dy = center.dy + r * math.sin(angle);
      canvas.drawCircle(Offset(dx, dy), 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.progress != progress;
}
