// Delivery Express — Step 3 of 4: "מחפשים שליח" (live radar).
//
// Shown immediately after auction creation. Streams the auction doc and
// switches to DeliveryExpressOffersScreen the moment the first offer
// lands. Also handles terminal states:
//   • status='matched'   — auction resolved before this screen mounted →
//                          push offers screen.
//   • status='cancelled' — pop back with a friendly snackbar.
//   • status='expired'   — show in-place "לא נמצא שליח" + "נסה שנית" CTA
//                          that re-broadcasts with the same package +
//                          locations + photos (no need to re-walk the wizard).
//
// Layout per CLAUDE.md §57 pattern: 200×200 radar with 3 staggered
// breathing rings + animated dots + "X שליחים קיבלו / Y בודקים / Z ק"מ
// רדיוס" stats. Centre disc shows a delivery icon (motorcycle box icon)
// instead of the motorcycle one — visual cue that this is the delivery
// flow even on the same screen template.
import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../constants/delivery_express_constants.dart';
import '../../models/delivery_express.dart';
import '../../services/delivery_express_service.dart';
import 'delivery_express_offers_screen.dart';
import 'delivery_express_palette.dart';

class DeliveryExpressSearchingScreen extends StatefulWidget {
  final String auctionId;
  // ── Original broadcast details — captured at the location screen.
  // Forwarded to the "נסה שנית" CTA on the expired panel so the customer
  // can re-broadcast without re-walking through 4 screens.
  final String packageType;
  final String urgencyReason;
  final String packageDescription;
  final String recipientName;
  final String recipientPhone;
  final DeliveryExpressLocation pickup;
  final DeliveryExpressLocation dropoff;
  final double distanceKm;
  final List<String> photoUrls;

  const DeliveryExpressSearchingScreen({
    super.key,
    required this.auctionId,
    required this.packageType,
    required this.urgencyReason,
    required this.packageDescription,
    required this.recipientName,
    required this.recipientPhone,
    required this.pickup,
    required this.dropoff,
    required this.distanceKm,
    required this.photoUrls,
  });

  @override
  State<DeliveryExpressSearchingScreen> createState() =>
      _DeliveryExpressSearchingScreenState();
}

class _DeliveryExpressSearchingScreenState
    extends State<DeliveryExpressSearchingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _radarCtrl;
  StreamSubscription<DeliveryExpress?>? _auctionSub;

  bool _navigatedToOffers = false;
  int _elapsedSeconds = 0;
  Timer? _tickTimer;

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
    _auctionSub = DeliveryExpressService.watchAuction(widget.auctionId)
        .listen(_onAuction);
  }

  void _onAuction(DeliveryExpress? a) {
    if (!mounted || a == null) return;

    if (a.status == DeliveryExpressStatus.cancelled) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('הקריאה בוטלה')),
      );
      return;
    }
    if (a.status == DeliveryExpressStatus.expired) {
      _tickTimer?.cancel();
      _radarCtrl.stop();
      setState(() {
        _expired = true;
        _expiredReasonHebrew = a.expiredReasonHebrew;
      });
      return;
    }

    final shouldNavigate = a.offerCount > 0 ||
        a.status == DeliveryExpressStatus.hasOffers ||
        a.status == DeliveryExpressStatus.matched;
    if (shouldNavigate && !_navigatedToOffers) {
      _navigatedToOffers = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DeliveryExpressOffersScreen(
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

  Future<void> _retry() async {
    if (_retrying) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _retrying = true);
    try {
      final newAuctionId = await DeliveryExpressService.createAuction(
        customerId: user.uid,
        customerName: user.displayName ?? '',
        packageType: widget.packageType,
        urgencyReason: widget.urgencyReason,
        packageDescription: widget.packageDescription,
        recipientName: widget.recipientName,
        recipientPhone: widget.recipientPhone,
        pickup: widget.pickup,
        dropoff: widget.dropoff,
        distanceKm: widget.distanceKm,
        photoUrls: widget.photoUrls,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DeliveryExpressSearchingScreen(
            auctionId: newAuctionId,
            packageType: widget.packageType,
            urgencyReason: widget.urgencyReason,
            packageDescription: widget.packageDescription,
            recipientName: widget.recipientName,
            recipientPhone: widget.recipientPhone,
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
                backgroundColor: DeliveryExpressPalette.red500,
              ),
              child: const Text('בטל קריאה'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await DeliveryExpressService.cancelAuction(auctionId: widget.auctionId);
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
        backgroundColor: DeliveryExpressPalette.bgPrimary,
        body: SafeArea(
          child: StreamBuilder<DeliveryExpress?>(
            stream:
                DeliveryExpressService.watchAuction(widget.auctionId),
            builder: (_, snap) {
              final a = snap.data;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: _expired ? null : _confirmCancel,
                          icon: const Icon(Icons.close_rounded),
                          color: DeliveryExpressPalette.textSecondary,
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
                                  'מחפשים שליח',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: DeliveryExpressPalette.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'בדרך כלל אנחנו מוצאים תוך 60–90 שניות',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: DeliveryExpressPalette.textSecondary,
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
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 16,
                              ),
                              label: const Text('בטל קריאה'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor:
                                    DeliveryExpressPalette.textSecondary,
                                side: const BorderSide(
                                  color:
                                      DeliveryExpressPalette.borderSecondary,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
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
              _radarRing(t),
              _radarRing((t + 0.33) % 1.0),
              _radarRing((t + 0.66) % 1.0),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: DeliveryExpressPalette.gold500,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: DeliveryExpressPalette.gold500
                          .withValues(alpha: 0.35),
                      blurRadius: 18,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.delivery_dining_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              ..._dots(t),
            ],
          );
        },
      ),
    );
  }

  Widget _radarRing(double t) {
    final eased = Curves.easeOut.transform(t);
    final scale = 0.3 + 0.95 * eased;
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
              color: DeliveryExpressPalette.gold200
                  .withValues(alpha: opacity),
              width: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _dots(double t) {
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
              color: DeliveryExpressPalette.green500
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
        color: DeliveryExpressPalette.gold50,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.access_time_rounded,
            size: 13,
            color: DeliveryExpressPalette.gold900,
          ),
          const SizedBox(width: 5),
          Text(
            'עברו $m:$s',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DeliveryExpressPalette.gold900,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final DeliveryExpress? auction;
  const _StatsGrid({required this.auction});

  @override
  Widget build(BuildContext context) {
    final notified = auction?.notifiedProviderIds.length ?? 0;
    final offers = auction?.offerCount ?? 0;
    final reviewing = (notified - offers).clamp(0, notified);
    final radius = auction?.currentRadiusKm.round() ?? 5;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: DeliveryExpressPalette.bgSecondary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _StatCell(value: '$notified', label: 'שליחים קיבלו'),
          _Divider(),
          _StatCell(value: '$reviewing', label: 'בודקים עכשיו'),
          _Divider(),
          _StatCell(value: '$radius ק"מ', label: 'רדיוס'),
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
              color: DeliveryExpressPalette.gold900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: DeliveryExpressPalette.textSecondary,
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
      color: DeliveryExpressPalette.borderTertiary,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// EXPIRED STATE (no providers found / 120s timeout / missing coords)
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
    final body = reasonHebrew?.trim().isNotEmpty == true
        ? reasonHebrew!
        : (notifiedCount == 0
            ? "לא נמצאו שליחים זמינים באזור שלך כרגע. נסה שוב בעוד רגע — או הגדל את הרדיוס בהמשך."
            : "שלחנו את הקריאה ל-$notifiedCount שליחים, אבל אף אחד מהם לא הגיב בזמן. אפשר לנסות שוב.");
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: DeliveryExpressPalette.gold50,
            shape: BoxShape.circle,
            border: Border.all(
              color: DeliveryExpressPalette.gold200,
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.search_off_rounded,
            size: 56,
            color: DeliveryExpressPalette.gold700,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          "לא נמצא שליח",
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: DeliveryExpressPalette.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13.5,
            color: DeliveryExpressPalette.textSecondary,
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
              backgroundColor: DeliveryExpressPalette.gold500,
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
              foregroundColor: DeliveryExpressPalette.textSecondary,
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            child: const Text("חזור"),
          ),
        ),
      ],
    );
  }
}
