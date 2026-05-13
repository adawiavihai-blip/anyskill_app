// Flash Auction — provider-side card for the Opportunities tab.
//
// Mounted by `opportunities_screen.dart` for every flash auction where
// this provider was notified (via the dispatch CF). Renders:
//   • Anonymous issue + pickup distance + dropoff distance + photos
//   • System-computed price (provider does NOT enter it)
//   • Single ETA input — the only thing the provider chooses
//   • "אשר ושלח הצעה" CTA → calls FlashAuctionService.submitOffer
//   • Status overlay when an offer is already submitted (pending /
//     selected / rejected)
//
// Anonymity (per spec §motorcycle / Motorcycle 2): the card never shows
// the customer's name, phone, or any chat affordance. Provider sees only
// distance + issue + photos until they're matched.
//
// Pricing: pre-computed via FlashAuctionPricingService.priceForProvider
// using the provider's stored motorcycleTowProfile. Re-runs on every
// rebuild — pure math, cheap.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../constants/flash_auction_constants.dart';
import '../../models/flash_auction.dart';
import '../../models/motorcycle_tow_profile.dart';
import '../../services/flash_auction_pricing_service.dart';
import '../../services/flash_auction_service.dart';
import '../../widgets/primary_cta.dart';
import '../../widgets/wolt_tile_layer.dart';
import 'flash_auction_palette.dart';

class FlashAuctionProviderCard extends StatefulWidget {
  final FlashAuction auction;
  final MotorcycleTowProfile providerProfile;
  /// Customer's distance from provider — computed by opportunities_screen
  /// using LocationService.cached + auction.pickup. Null when either
  /// side lacks coordinates.
  final double? distanceFromProviderKm;

  const FlashAuctionProviderCard({
    super.key,
    required this.auction,
    required this.providerProfile,
    this.distanceFromProviderKm,
  });

  @override
  State<FlashAuctionProviderCard> createState() =>
      _FlashAuctionProviderCardState();
}

class _FlashAuctionProviderCardState extends State<FlashAuctionProviderCard> {
  final _etaCtrl = TextEditingController(text: '15');
  bool _submitting = false;

  String get _providerId =>
      FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void dispose() {
    _etaCtrl.dispose();
    super.dispose();
  }

  FlashAuctionPriceBreakdown _breakdown() =>
      FlashAuctionPricingService.priceForProvider(
        providerProfile: widget.providerProfile,
        distanceKm: widget.auction.distanceKm,
      );

  Future<void> _submit() async {
    if (_submitting) return;
    final eta = int.tryParse(_etaCtrl.text.trim());
    if (eta == null || eta < 1 || eta > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הזן זמן הגעה תקין (1-180 דקות)'),
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FlashAuctionService.submitOffer(
        auctionId: widget.auction.id,
        etaMinutes: eta,
        providerProfile: widget.providerProfile,
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      if (result == 'duplicate') {
        messenger.showSnackBar(
          const SnackBar(content: Text('כבר שלחת הצעה לקריאה הזו')),
        );
        return;
      }
      if (result == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('שגיאה בשליחה — נסה שוב')),
        );
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('ההצעה נשלחה ✓')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(SnackBar(content: Text('שגיאה: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<FlashAuctionOffer?>(
      stream: FlashAuctionService.watchMyOffer(
        auctionId: widget.auction.id,
        providerId: _providerId,
      ),
      builder: (_, snap) {
        final myOffer = snap.data;
        return _buildCard(myOffer);
      },
    );
  }

  // ── Build ────────────────────────────────────────────────────────────

  Widget _buildCard(FlashAuctionOffer? myOffer) {
    final breakdown = _breakdown();
    final issueLabel =
        FlashAuctionIssueType.labelOf(widget.auction.issueType);
    final issueIcon =
        FlashAuctionIssueType.iconOf(widget.auction.issueType);

    return Container(
      decoration: BoxDecoration(
        color: FlashPalette.bgPrimary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: FlashPalette.red500.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: FlashPalette.red500.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _UrgentRibbon(),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(issueIcon, issueLabel),
                const SizedBox(height: 12),
                _buildLocations(),
                if (widget.auction.pickup.hasCoords &&
                    widget.auction.dropoff.hasCoords &&
                    widget.auction.distanceKm > 0) ...[
                  const SizedBox(height: 10),
                  _buildRouteMap(),
                ],
                if (widget.auction.photoUrls.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildPhotos(),
                ],
                const SizedBox(height: 14),
                _buildPriceBlock(breakdown),
                const SizedBox(height: 12),
                if (myOffer != null)
                  _OfferStatusBlock(offer: myOffer)
                else
                  _buildEtaInput(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(IconData issueIcon, String issueLabel) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: FlashPalette.red50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(issueIcon, color: FlashPalette.red500, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                issueLabel,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: FlashPalette.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.distanceFromProviderKm == null
                    ? 'קריאת גרר דחופה'
                    : '${widget.distanceFromProviderKm!.toStringAsFixed(1)} ק"מ ממך',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: FlashPalette.textSecondary,
                ),
              ),
            ],
          ),
        ),
        // Anti-clock — counts down to expiry. Helpful for urgency cue.
        _ExpiryChip(expiresAt: widget.auction.expiresAt),
      ],
    );
  }

  Widget _buildLocations() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: FlashPalette.bgSecondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          _LocationRow(
            icon: Icons.my_location_rounded,
            iconColor: FlashPalette.green500,
            label: 'מאיפה',
            value: widget.auction.pickup.address.isNotEmpty
                ? widget.auction.pickup.address
                : 'מסומן על המפה',
          ),
          const SizedBox(height: 8),
          _LocationRow(
            icon: Icons.place_rounded,
            iconColor: FlashPalette.purple500,
            label: 'לאן',
            value: widget.auction.dropoff.address.isNotEmpty
                ? widget.auction.dropoff.address
                : 'לא צוין',
          ),
          if (widget.auction.distanceKm > 0) ...[
            const Divider(
              height: 14,
              thickness: 0.5,
              color: FlashPalette.borderTertiary,
            ),
            Row(
              children: [
                const Icon(
                  Icons.straighten_rounded,
                  size: 13,
                  color: FlashPalette.textSecondary,
                ),
                const SizedBox(width: 5),
                Text(
                  'מסלול: ~${widget.auction.distanceKm.toStringAsFixed(1)} ק"מ',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: FlashPalette.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRouteMap() {
    final pickup = LatLng(
      widget.auction.pickup.lat!,
      widget.auction.pickup.lng!,
    );
    final dropoff = LatLng(
      widget.auction.dropoff.lat!,
      widget.auction.dropoff.lng!,
    );
    final bounds = LatLngBounds.fromPoints([pickup, dropoff]);

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 150,
        child: FlutterMap(
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.all(28),
            ),
            minZoom: 6,
            maxZoom: 18,
            // Non-interactive — the card sits inside a horizontal strip
            // in opportunities_screen, and an interactive map would
            // steal the swipe gesture between cards.
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            // Unified Wolt-style tiles with OSM fallback — see §78 in
            // CLAUDE.md. WoltTileLayer keeps the route preview visually
            // consistent with the rest of the app's maps.
            WoltTileLayer.forContext(context, maxZoom: 19),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: [pickup, dropoff],
                  strokeWidth: 3.5,
                  color: FlashPalette.purple500,
                  pattern: StrokePattern.dashed(segments: const [6, 4]),
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: pickup,
                  width: 26,
                  height: 26,
                  child: Container(
                    decoration: BoxDecoration(
                      color: FlashPalette.green500,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.my_location_rounded,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ),
                Marker(
                  point: dropoff,
                  width: 26,
                  height: 26,
                  child: Container(
                    decoration: BoxDecoration(
                      color: FlashPalette.purple500,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.place_rounded,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotos() {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.auction.photoUrls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            widget.auction.photoUrls[i],
            width: 64,
            height: 64,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 64,
              height: 64,
              color: FlashPalette.bgSecondary,
              child: const Icon(
                Icons.broken_image_outlined,
                size: 18,
                color: FlashPalette.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPriceBlock(FlashAuctionPriceBreakdown b) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: FlashPalette.amber50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: FlashPalette.amber600.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: FlashPalette.amber800,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'מחיר מחושב אוטומטית',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: FlashPalette.amber800,
                  ),
                ),
              ),
              Text(
                '₪${b.total.round()}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: FlashPalette.purple700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _PriceLine(label: 'מחיר בסיס', value: '₪${b.basePrice.round()}'),
          if (b.kmFee > 0)
            _PriceLine(
              label: 'תוספת ק"מ (${b.kmCharged.toStringAsFixed(1)} ק"מ)',
              value: '₪${b.kmFee.round()}',
            ),
          if (b.nightSurcharge > 0)
            _PriceLine(
              label: 'תוספת לילה / שבת',
              value: '₪${b.nightSurcharge.round()}',
            ),
          if (b.emergencySurcharge > 0)
            _PriceLine(
              label: 'תוספת חירום',
              value: '₪${b.emergencySurcharge.round()}',
            ),
        ],
      ),
    );
  }

  Widget _buildEtaInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.timer_outlined,
              size: 14,
              color: FlashPalette.textPrimary,
            ),
            const SizedBox(width: 6),
            const Text(
              'תוך כמה זמן תגיע?',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: FlashPalette.textPrimary,
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 92,
              child: TextField(
                controller: _etaCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  suffixText: 'דק׳',
                  suffixStyle: const TextStyle(
                    fontSize: 11,
                    color: FlashPalette.textSecondary,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: FlashPalette.borderSecondary,
                      width: 0.5,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: FlashPalette.borderSecondary,
                      width: 0.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: FlashPalette.purple500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        PrimaryCTA(
          label: 'אשר ושלח הצעה',
          icon: Icons.send_rounded,
          variant: PrimaryCTAVariant.success,
          loading: _submitting,
          dense: true,
          onPressed: _submitting ? null : _submit,
          semanticHint: 'שולח הצעה ללקוח עם זמן הגעה ומחיר אוטומטי',
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════════

class _UrgentRibbon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: FlashPalette.red500,
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bolt_rounded,
            color: Colors.white,
            size: 13,
          ),
          SizedBox(width: 4),
          Text(
            'קריאת גרר דחופה',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpiryChip extends StatefulWidget {
  final DateTime expiresAt;
  const _ExpiryChip({required this.expiresAt});

  @override
  State<_ExpiryChip> createState() => _ExpiryChipState();
}

class _ExpiryChipState extends State<_ExpiryChip> {
  late int _seconds;

  @override
  void initState() {
    super.initState();
    _refresh();
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      _refresh();
      return _seconds > 0;
    });
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _seconds = widget.expiresAt
          .difference(DateTime.now())
          .inSeconds
          .clamp(0, 600);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mm = (_seconds ~/ 60).toString();
    final ss = (_seconds % 60).toString().padLeft(2, '0');
    final urgent = _seconds <= 30;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: urgent
            ? FlashPalette.red50
            : FlashPalette.purple50,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_rounded,
            size: 11,
            color: urgent
                ? FlashPalette.red500
                : FlashPalette.purple700,
          ),
          const SizedBox(width: 3),
          Text(
            '$mm:$ss',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: urgent
                  ? FlashPalette.red500
                  : FlashPalette.purple700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _LocationRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: FlashPalette.textTertiary,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: FlashPalette.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PriceLine extends StatelessWidget {
  final String label;
  final String value;
  const _PriceLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: FlashPalette.amber800,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: FlashPalette.amber800,
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferStatusBlock extends StatelessWidget {
  final FlashAuctionOffer offer;
  const _OfferStatusBlock({required this.offer});

  @override
  Widget build(BuildContext context) {
    final (color, icon, title, sub) = _statusViz();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: color.withValues(alpha: 0.85),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${offer.etaMinutes} ד׳',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  (Color, IconData, String, String) _statusViz() {
    switch (offer.status) {
      case FlashAuctionOfferStatus.selected:
        return (
          FlashPalette.green500,
          Icons.check_circle_rounded,
          'נבחרת!',
          'הלקוח בחר בך — ייפתח לך מסך מעקב מיד',
        );
      case FlashAuctionOfferStatus.rejected:
        return (
          FlashPalette.textTertiary,
          Icons.close_rounded,
          'הלקוח בחר אחר',
          'אפשר לחזור ולקבל קריאות חדשות',
        );
      case FlashAuctionOfferStatus.pending:
      default:
        return (
          FlashPalette.purple500,
          Icons.hourglass_top_rounded,
          'הצעה נשלחה — ממתינה ללקוח',
          'תקבל התראה ברגע שמישהו ייבחר',
        );
    }
  }
}
