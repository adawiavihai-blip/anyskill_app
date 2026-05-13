// Flash Auction — Step 3 of 4: "מחפשים גרריסט" (live radar).
//
// Shown immediately after auction creation. Streams the auction doc and
// switches to FlashAuctionOffersScreen the moment the first offer lands
// (status flips searching → has_offers, OR offerCount > 0). Also handles
// the terminal states:
//   • status='matched'  — auction resolved before this screen mounted
//                         (rare race) → push offers screen.
//   • status='cancelled'/'expired' — pop back with a friendly message.
//
// Layout per mockup §3 (customer-flow.html lines 232-250): 180×180 radar
// with 3 staggered breathing rings + animated dots + live stats grid.
// The "X גרריסטים קיבלו" / "Y בודקים" / "Z ק"מ רדיוס" trio reads from
// the auction doc's `notifiedProviderIds.length` / `offerCount` /
// `currentRadiusKm` fields.
import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../constants/flash_auction_constants.dart';
import '../../models/flash_auction.dart';
import '../../services/flash_auction_service.dart';
import 'flash_auction_offers_screen.dart';
import 'flash_auction_palette.dart';

class FlashAuctionSearchingScreen extends StatefulWidget {
  final String auctionId;
  // ── Original broadcast details — captured at the location screen.
  // Required so the "נסה שנית" CTA on the expired state can re-broadcast
  // with the same data without sending the user back through 4 screens.
  final String issueType;
  final FlashAuctionLocation pickup;
  final FlashAuctionLocation dropoff;
  final double distanceKm;
  final List<String> photoUrls;

  const FlashAuctionSearchingScreen({
    super.key,
    required this.auctionId,
    required this.issueType,
    required this.pickup,
    required this.dropoff,
    required this.distanceKm,
    required this.photoUrls,
  });

  @override
  State<FlashAuctionSearchingScreen> createState() =>
      _FlashAuctionSearchingScreenState();
}

class _FlashAuctionSearchingScreenState
    extends State<FlashAuctionSearchingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _radarCtrl;
  StreamSubscription<FlashAuction?>? _auctionSub;

  /// Tracks whether we already navigated to the offers screen so we don't
  /// double-push when the stream fires multiple events at the boundary.
  bool _navigatedToOffers = false;

  /// Local count of seconds since createdAt — re-rendered every second
  /// for the elapsed-time display. Primary source of truth is still the
  /// server-side `expiresAt`; this is just for the UI counter.
  int _elapsedSeconds = 0;
  Timer? _tickTimer;

  // ── Expired state ───────────────────────────────────────────────────
  // When the CF flips status to 'expired', we no longer pop straight to
  // root — instead we show an in-place "לא נמצאו גרריסטים" panel with a
  // "נסה שנית" CTA that re-broadcasts with the same data.
  bool _expired = false;
  String? _expiredReasonHebrew;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds += 1);
    });
    _auctionSub =
        FlashAuctionService.watchAuction(widget.auctionId).listen(_onAuction);
  }

  void _onAuction(FlashAuction? a) {
    if (!mounted || a == null) return;

    // Race: customer cancelled, expired, or already matched in another tab.
    if (a.status == FlashAuctionStatus.cancelled) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('הקריאה בוטלה')),
      );
      return;
    }
    if (a.status == FlashAuctionStatus.expired) {
      // In-place expired state — stops the radar + tick timer and shows
      // a "Try Again" panel. The customer can re-broadcast without
      // re-walking through 4 screens.
      _tickTimer?.cancel();
      _radarCtrl.stop();
      setState(() {
        _expired = true;
        _expiredReasonHebrew = a.expiredReasonHebrew;
      });
      return;
    }

    // First offer arrived OR auction was already matched when we mounted —
    // jump to the offers screen.
    final shouldNavigate = a.offerCount > 0 ||
        a.status == FlashAuctionStatus.hasOffers ||
        a.status == FlashAuctionStatus.matched;
    if (shouldNavigate && !_navigatedToOffers) {
      _navigatedToOffers = true;
      // Replace so back-button on the offers screen lands the user back
      // on the category page (not on this radar).
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => FlashAuctionOffersScreen(
            auctionId: widget.auctionId,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _radarCtrl.dispose();
    _tickTimer?.cancel();
    _auctionSub?.cancel();
    super.dispose();
  }

  /// Re-broadcasts the SAME auction details (same pickup/dropoff/issue/
  /// photos) when the customer taps "נסה שנית" on the expired panel.
  /// Uses pushReplacement so the new attempt starts with a fresh radar
  /// and the back-button still lands on the category screen.
  Future<void> _retry() async {
    if (_retrying) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _retrying = true);
    try {
      final newAuctionId = await FlashAuctionService.createAuction(
        customerId: user.uid,
        customerName: user.displayName ?? '',
        issueType: widget.issueType,
        pickup: widget.pickup,
        dropoff: widget.dropoff,
        distanceKm: widget.distanceKm,
        photoUrls: widget.photoUrls,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => FlashAuctionSearchingScreen(
            auctionId: newAuctionId,
            issueType: widget.issueType,
            pickup: widget.pickup,
            dropoff: widget.dropoff,
            distanceKm: widget.distanceKm,
            photoUrls: widget.photoUrls,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _retrying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה בשליחה חוזרת: $e')),
      );
    }
  }

  Future<void> _confirmCancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('ביטול הקריאה'),
          content: const Text(
            'הקריאה שלך תיסגר ולא יישלחו עוד התראות. אפשר לפרסם קריאה חדשה בכל עת.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('חזור'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: FlashPalette.red500,
              ),
              child: const Text('בטל קריאה'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await FlashAuctionService.cancelAuction(auctionId: widget.auctionId);
      // The stream will hit `cancelled` and pop back to root; nothing else
      // to do here.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה בביטול: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: FlashPalette.bgPrimary,
        body: SafeArea(
          child: StreamBuilder<FlashAuction?>(
            stream:
                FlashAuctionService.watchAuction(widget.auctionId),
            builder: (_, snap) {
              final a = snap.data;
              return Column(
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: _expired ? null : _confirmCancel,
                          icon: const Icon(Icons.close_rounded),
                          color: FlashPalette.textSecondary,
                          tooltip: _expired ? 'סגור' : 'בטל קריאה',
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _expired
                          ? _ExpiredPanel(
                              reasonHebrew: _expiredReasonHebrew,
                              notifiedCount:
                                  a?.notifiedProviderIds.length ?? 0,
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _Radar(controller: _radarCtrl),
                                const SizedBox(height: 24),
                                const Text(
                                  'מחפשים גרריסט',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: FlashPalette.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'בדרך כלל אנחנו מוצאים תוך 60–90 שניות',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: FlashPalette.textSecondary,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _ElapsedChip(seconds: _elapsedSeconds),
                                const SizedBox(height: 24),
                                _StatsGrid(auction: a),
                              ],
                            ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: _expired
                        ? _ExpiredCtaRow(
                            retrying: _retrying,
                            onRetry: _retry,
                            onBack: () => Navigator.of(context)
                                .popUntil((r) => r.isFirst),
                          )
                        : SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _confirmCancel,
                              icon: const Icon(Icons.close_rounded, size: 16),
                              label: const Text('בטל קריאה'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: FlashPalette.textSecondary,
                                side: const BorderSide(
                                  color: FlashPalette.borderSecondary,
                                ),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// RADAR
// ═══════════════════════════════════════════════════════════════════════

class _Radar extends StatelessWidget {
  final AnimationController controller;
  const _Radar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, __) {
          final t = controller.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              // 3 staggered rings — each does a 0→1 ease-out scale + fade.
              _radarRing(t),
              _radarRing((t + 0.33) % 1.0),
              _radarRing((t + 0.66) % 1.0),
              // Centre purple disc with motorcycle icon.
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: FlashPalette.purple500,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color:
                          FlashPalette.purple500.withValues(alpha: 0.35),
                      blurRadius: 18,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.two_wheeler_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              // Decorative dots (provider markers) orbiting at fixed offsets.
              ..._dots(t),
            ],
          );
        },
      ),
    );
  }

  Widget _radarRing(double t) {
    final eased = Curves.easeOut.transform(t);
    final scale = 0.3 + 0.95 * eased; // 0.3 → 1.25
    final opacity =
        t < 0.3 ? (t / 0.3) : (1.0 - (t - 0.3) / 0.7).clamp(0.0, 1.0);
    return IgnorePointer(
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: FlashPalette.purple300.withValues(alpha: opacity),
              width: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _dots(double t) {
    // 3 fixed dots at offsets — gives the impression of providers being
    // "scanned" without actually positioning real provider locations.
    final dots = <Widget>[];
    final angles = [math.pi * 0.25, math.pi * 0.95, math.pi * 1.55];
    final radii = [60.0, 80.0, 70.0];
    for (var i = 0; i < angles.length; i++) {
      final dx = radii[i] * math.cos(angles[i]);
      final dy = radii[i] * math.sin(angles[i]);
      final pulse = 0.4 + 0.6 * (math.sin((t + i * 0.33) * math.pi * 2));
      dots.add(
        Transform.translate(
          offset: Offset(dx, dy),
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: FlashPalette.green500
                  .withValues(alpha: pulse.clamp(0.4, 1.0)),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      );
    }
    return dots;
  }
}

class _ElapsedChip extends StatelessWidget {
  final int seconds;
  const _ElapsedChip({required this.seconds});

  @override
  Widget build(BuildContext context) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: FlashPalette.purple50,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.access_time_rounded,
              size: 13, color: FlashPalette.purple700),
          const SizedBox(width: 5),
          Text(
            'עברו $m:$s',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: FlashPalette.purple700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final FlashAuction? auction;
  const _StatsGrid({required this.auction});

  @override
  Widget build(BuildContext context) {
    final notified = auction?.notifiedProviderIds.length ?? 0;
    final offers = auction?.offerCount ?? 0;
    // "Reviewing now" = notified that haven't responded yet.
    // (Some may have ignored — we can't tell from Firestore — but this
    // is the best proxy we have without read receipts.)
    final reviewing = (notified - offers).clamp(0, notified);
    final radius = auction?.currentRadiusKm.round() ?? 5;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: FlashPalette.bgSecondary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _StatCell(value: '$notified', label: 'גרריסטים קיבלו'),
          _Divider(),
          _StatCell(value: '$reviewing', label: 'בודקים עכשיו'),
          _Divider(),
          _StatCell(
            value: '$radius ק"מ',
            label: 'רדיוס',
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String value;
  final String label;
  const _StatCell({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: FlashPalette.purple700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: FlashPalette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      color: FlashPalette.borderTertiary,
    );
  }
}


// ═══════════════════════════════════════════════════════════════════════
// EXPIRED STATE (no providers found / 120s timeout / missing pickup coords)
// ═══════════════════════════════════════════════════════════════════════

class _ExpiredPanel extends StatelessWidget {
  final String? reasonHebrew;
  final int notifiedCount;
  const _ExpiredPanel({
    required this.reasonHebrew,
    required this.notifiedCount,
  });

  @override
  Widget build(BuildContext context) {
    // Pick a sensible body line based on the CF-supplied reason.
    final body = reasonHebrew?.trim().isNotEmpty == true
        ? reasonHebrew!
        : (notifiedCount == 0
            ? "לא נמצאו גרריסטים זמינים באזור שלך כרגע. נסה שוב בעוד רגע — או הגדל את הרדיוס בהמשך."
            : "שלחנו את הקריאה ל-$notifiedCount גרריסטים, אבל אף אחד מהם לא הגיב בזמן. אפשר לנסות שוב.");
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: FlashPalette.purple50,
            shape: BoxShape.circle,
            border: Border.all(
              color: FlashPalette.purple200,
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.search_off_rounded,
            size: 56,
            color: FlashPalette.purple500,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          "לא נמצא גרריסט",
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: FlashPalette.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13.5,
            color: FlashPalette.textSecondary,
            height: 1.55,
          ),
        ),
      ],
    );
  }
}

class _ExpiredCtaRow extends StatelessWidget {
  final bool retrying;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  const _ExpiredCtaRow({
    required this.retrying,
    required this.onRetry,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: retrying ? null : onRetry,
            icon: retrying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
            label: Text(retrying ? "שולח שוב..." : "נסה שנית"),
            style: FilledButton.styleFrom(
              backgroundColor: FlashPalette.purple500,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: retrying ? null : onBack,
            style: TextButton.styleFrom(
              foregroundColor: FlashPalette.textSecondary,
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            child: const Text("חזור"),
          ),
        ),
      ],
    );
  }
}
