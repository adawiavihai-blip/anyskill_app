// Delivery Express — provider-side card for the Opportunities tab.
//
// Mounted by `opportunities_screen.dart` for every delivery_express where
// this courier was notified by the dispatch CF. Renders:
//   • Anonymous package type + pickup distance + dropoff distance
//   • Optional photos
//   • System-computed price (provider does NOT enter it)
//   • Vehicle picker (scooter / car) — limited to eligible types for the
//     package size, per DeliveryExpressPackageType.eligibleVehicles
//   • Single ETA input — the only number the provider chooses
//   • "אשר ושלח הצעה" CTA → calls DeliveryExpressService.submitOffer
//   • Status overlay when an offer is already submitted (pending /
//     selected / rejected)
//
// Anonymity: the card never shows the customer's name, phone, or any
// chat affordance. Provider sees only the package context until they're
// matched.
//
// Pricing: pre-computed via DeliveryExpressPricingService.priceForProvider
// using the provider's stored deliveryProfile. Re-runs on every rebuild
// — pure math, cheap.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../constants/delivery_express_constants.dart';
import '../../models/delivery_express.dart';
import '../../models/delivery_profile.dart';
import '../../services/delivery_express_pricing_service.dart';
import '../../services/delivery_express_service.dart';
import '../../widgets/primary_cta.dart';
import '../../widgets/wolt_tile_layer.dart';
import 'delivery_express_palette.dart';

class DeliveryExpressProviderCard extends StatefulWidget {
  final DeliveryExpress auction;
  final DeliveryProfile providerProfile;
  /// Distance from the provider's last-known location to the auction's
  /// pickup. Computed by opportunities_screen via LocationService.cached.
  /// Null when either side lacks coordinates.
  final double? distanceFromProviderKm;

  const DeliveryExpressProviderCard({
    super.key,
    required this.auction,
    required this.providerProfile,
    this.distanceFromProviderKm,
  });

  @override
  State<DeliveryExpressProviderCard> createState() =>
      _DeliveryExpressProviderCardState();
}

class _DeliveryExpressProviderCardState
    extends State<DeliveryExpressProviderCard> {
  final _etaCtrl = TextEditingController(text: '15');
  bool _submitting = false;

  /// 'scooter' | 'car' — selected vehicle for this offer. Defaults to
  /// the FIRST eligible vehicle the provider has enabled in their
  /// profile. The picker only renders when the package type allows BOTH
  /// vehicles AND the provider has both enabled.
  late String _selectedVehicle;

  String get _providerId =>
      FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _selectedVehicle = _defaultVehicle();
  }

  /// Pick the default vehicle: first eligible-for-package vehicle that
  /// the provider has enabled. Falls back to scooter if the profile is
  /// missing vehicle data.
  String _defaultVehicle() {
    final eligible =
        DeliveryExpressPackageType.eligibleVehicles(widget.auction.packageType);
    final enabled = widget.providerProfile.vehicles
        .where((v) => v.enabled)
        .map((v) => v.type)
        .toSet();
    for (final id in eligible) {
      if (enabled.contains(id)) return id;
    }
    return eligible.isNotEmpty ? eligible.first : 'scooter';
  }

  /// True when the provider has BOTH a scooter and a car enabled AND the
  /// package allows both → show a 2-way picker so the courier can choose.
  bool get _showVehiclePicker {
    final eligible =
        DeliveryExpressPackageType.eligibleVehicles(widget.auction.packageType);
    if (eligible.length < 2) return false;
    final enabled = widget.providerProfile.vehicles
        .where((v) => v.enabled)
        .map((v) => v.type)
        .toSet();
    return eligible.every(enabled.contains);
  }

  @override
  void dispose() {
    _etaCtrl.dispose();
    super.dispose();
  }

  DeliveryExpressPriceBreakdown _breakdown() =>
      DeliveryExpressPricingService.priceForProvider(
        providerProfile: widget.providerProfile,
        packageType: widget.auction.packageType,
        distanceKm: widget.auction.distanceKm,
      );

  Future<void> _submit() async {
    if (_submitting) return;
    final eta = int.tryParse(_etaCtrl.text.trim());
    if (eta == null || eta < 1 || eta > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('הזן זמן הגעה תקין (1-180 דקות)')),
      );
      return;
    }
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await DeliveryExpressService.submitOffer(
        auctionId: widget.auction.id,
        etaMinutes: eta,
        vehicleType: _selectedVehicle,
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
    return StreamBuilder<DeliveryExpressOffer?>(
      stream: DeliveryExpressService.watchMyOffer(
        auctionId: widget.auction.id,
        providerId: _providerId,
      ),
      builder: (_, snap) {
        final myOffer = snap.data;
        return _buildCard(myOffer);
      },
    );
  }

  Widget _buildCard(DeliveryExpressOffer? myOffer) {
    final breakdown = _breakdown();
    final packageLabel =
        DeliveryExpressPackageType.labelOf(widget.auction.packageType);
    final packageIcon =
        DeliveryExpressPackageType.iconOf(widget.auction.packageType);
    final packageWeight =
        DeliveryExpressPackageType.weightSpecOf(widget.auction.packageType);
    final urgencyLabel =
        DeliveryExpressUrgencyReason.labelOf(widget.auction.urgencyReason);

    return Container(
      decoration: BoxDecoration(
        color: DeliveryExpressPalette.bgPrimary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: DeliveryExpressPalette.red500.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: DeliveryExpressPalette.red500.withValues(alpha: 0.10),
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
                _buildHeader(packageIcon, packageLabel, packageWeight),
                const SizedBox(height: 8),
                _UrgencyChip(label: urgencyLabel),
                const SizedBox(height: 12),
                _buildLocations(),
                if (widget.auction.pickup.hasCoords &&
                    widget.auction.dropoff.hasCoords &&
                    widget.auction.distanceKm > 0) ...[
                  const SizedBox(height: 10),
                  _buildRouteMap(),
                ],
                if (widget.auction.packageDescription.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildDescriptionBlock(),
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
                else ...[
                  if (_showVehiclePicker) ...[
                    _buildVehiclePicker(),
                    const SizedBox(height: 10),
                  ],
                  _buildEtaInput(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    IconData packageIcon,
    String packageLabel,
    String packageWeight,
  ) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: DeliveryExpressPalette.red50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            packageIcon,
            color: DeliveryExpressPalette.red500,
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                packageLabel,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: DeliveryExpressPalette.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    packageWeight,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: DeliveryExpressPalette.textSecondary,
                    ),
                  ),
                  if (widget.distanceFromProviderKm != null) ...[
                    const SizedBox(width: 6),
                    const Text(
                      '·',
                      style: TextStyle(
                        fontSize: 11,
                        color: DeliveryExpressPalette.textTertiary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${widget.distanceFromProviderKm!.toStringAsFixed(1)} ק"מ ממך',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: DeliveryExpressPalette.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        _ExpiryChip(expiresAt: widget.auction.expiresAt),
      ],
    );
  }

  Widget _buildLocations() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: DeliveryExpressPalette.bgSecondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          _LocationRow(
            icon: Icons.my_location_rounded,
            iconColor: DeliveryExpressPalette.green500,
            label: 'איסוף',
            value: widget.auction.pickup.address.isNotEmpty
                ? widget.auction.pickup.address
                : 'מסומן על המפה',
          ),
          const SizedBox(height: 8),
          _LocationRow(
            icon: Icons.place_rounded,
            iconColor: DeliveryExpressPalette.gold700,
            label: 'מסירה',
            value: widget.auction.dropoff.address.isNotEmpty
                ? widget.auction.dropoff.address
                : 'לא צוין',
          ),
          if (widget.auction.distanceKm > 0) ...[
            const Divider(
              height: 14,
              thickness: 0.5,
              color: DeliveryExpressPalette.borderTertiary,
            ),
            Row(
              children: [
                const Icon(
                  Icons.straighten_rounded,
                  size: 13,
                  color: DeliveryExpressPalette.textSecondary,
                ),
                const SizedBox(width: 5),
                Text(
                  'מסלול: ~${widget.auction.distanceKm.toStringAsFixed(1)} ק"מ',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DeliveryExpressPalette.textSecondary,
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
            // Non-interactive — the card sits in a horizontal/vertical
            // strip and an interactive map would steal scroll gestures.
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            WoltTileLayer.forContext(context, maxZoom: 19),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: [pickup, dropoff],
                  strokeWidth: 3.5,
                  color: DeliveryExpressPalette.gold700,
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
                      color: DeliveryExpressPalette.green500,
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
                      color: DeliveryExpressPalette.gold700,
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

  Widget _buildDescriptionBlock() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: DeliveryExpressPalette.bgSecondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.notes_rounded,
            size: 14,
            color: DeliveryExpressPalette.textSecondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.auction.packageDescription,
              style: const TextStyle(
                fontSize: 12,
                color: DeliveryExpressPalette.textPrimary,
                height: 1.5,
              ),
            ),
          ),
        ],
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
              color: DeliveryExpressPalette.bgSecondary,
              child: const Icon(
                Icons.broken_image_outlined,
                size: 18,
                color: DeliveryExpressPalette.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPriceBlock(DeliveryExpressPriceBreakdown b) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: DeliveryExpressPalette.amber50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: DeliveryExpressPalette.amber600.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: DeliveryExpressPalette.amber800,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'מחיר מחושב אוטומטית',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: DeliveryExpressPalette.amber800,
                  ),
                ),
              ),
              Text(
                '₪${b.total.round()}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: DeliveryExpressPalette.gold900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _PriceLine(label: 'מחיר בסיס', value: '₪${b.base.round()}'),
          if (b.immediateSurcharge > 0)
            _PriceLine(
              label: 'תוספת משלוח מיידי',
              value: '₪${b.immediateSurcharge.round()}',
            ),
          if (b.kmAfter5 > 0)
            _PriceLine(
              label: 'תוספת ק"מ (מעבר ל-5 ק"מ)',
              value: '₪${b.kmAfter5.round()}',
            ),
        ],
      ),
    );
  }

  Widget _buildVehiclePicker() {
    return Row(
      children: [
        const Icon(
          Icons.directions_outlined,
          size: 14,
          color: DeliveryExpressPalette.textPrimary,
        ),
        const SizedBox(width: 6),
        const Text(
          'באיזה כלי רכב?',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: DeliveryExpressPalette.textPrimary,
          ),
        ),
        const Spacer(),
        _VehicleChip(
          id: 'scooter',
          label: 'קטנוע',
          icon: Icons.two_wheeler_rounded,
          selected: _selectedVehicle == 'scooter',
          onTap: () => setState(() => _selectedVehicle = 'scooter'),
        ),
        const SizedBox(width: 6),
        _VehicleChip(
          id: 'car',
          label: 'רכב',
          icon: Icons.directions_car_rounded,
          selected: _selectedVehicle == 'car',
          onTap: () => setState(() => _selectedVehicle = 'car'),
        ),
      ],
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
              color: DeliveryExpressPalette.textPrimary,
            ),
            const SizedBox(width: 6),
            const Text(
              'תוך כמה זמן תאסוף?',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: DeliveryExpressPalette.textPrimary,
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
                    color: DeliveryExpressPalette.textSecondary,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: DeliveryExpressPalette.borderSecondary,
                      width: 0.5,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: DeliveryExpressPalette.borderSecondary,
                      width: 0.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: DeliveryExpressPalette.gold500,
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
        color: DeliveryExpressPalette.red500,
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bolt_rounded, color: Colors.white, size: 13),
          SizedBox(width: 4),
          Text(
            'משלוח דחוף',
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

class _UrgencyChip extends StatelessWidget {
  final String label;
  const _UrgencyChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: DeliveryExpressPalette.gold50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: DeliveryExpressPalette.gold900,
        ),
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
            ? DeliveryExpressPalette.red50
            : DeliveryExpressPalette.gold50,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_rounded,
            size: 11,
            color: urgent
                ? DeliveryExpressPalette.red500
                : DeliveryExpressPalette.gold900,
          ),
          const SizedBox(width: 3),
          Text(
            '$mm:$ss',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: urgent
                  ? DeliveryExpressPalette.red500
                  : DeliveryExpressPalette.gold900,
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
                  color: DeliveryExpressPalette.textTertiary,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: DeliveryExpressPalette.textPrimary,
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
                color: DeliveryExpressPalette.amber800,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: DeliveryExpressPalette.amber800,
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleChip extends StatelessWidget {
  final String id;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _VehicleChip({
    required this.id,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? DeliveryExpressPalette.gold50
              : DeliveryExpressPalette.bgPrimary,
          border: Border.all(
            color: selected
                ? DeliveryExpressPalette.gold500
                : DeliveryExpressPalette.borderTertiary,
            width: selected ? 1.2 : 0.5,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected
                  ? DeliveryExpressPalette.gold700
                  : DeliveryExpressPalette.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: selected
                    ? DeliveryExpressPalette.gold900
                    : DeliveryExpressPalette.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferStatusBlock extends StatelessWidget {
  final DeliveryExpressOffer offer;
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
      case DeliveryExpressOfferStatus.selected:
        return (
          DeliveryExpressPalette.green500,
          Icons.check_circle_rounded,
          'נבחרת!',
          'הלקוח בחר בך — ייפתח לך מסך מעקב מיד',
        );
      case DeliveryExpressOfferStatus.rejected:
        return (
          DeliveryExpressPalette.textTertiary,
          Icons.close_rounded,
          'הלקוח בחר אחר',
          'אפשר לחזור ולקבל קריאות חדשות',
        );
      case DeliveryExpressOfferStatus.pending:
      default:
        return (
          DeliveryExpressPalette.gold700,
          Icons.hourglass_top_rounded,
          'הצעה נשלחה — ממתינה ללקוח',
          'תקבל התראה ברגע שמישהו ייבחר',
        );
    }
  }
}
