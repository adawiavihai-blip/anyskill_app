// Provider-side card for the babysitter emergency strip in the
// opportunities screen.
//
// CRITICAL anonymity rules (matches Flash Auction):
//   • Customer name + address NEVER shown until match
//   • Provider sees: # children + age groups + duration + start time +
//     general distance (computed from their location, not customer's)
//   • Single ETA input — price is auto-computed from provider's pricing
//
// Trust the existing ChatScreen + bookings flow for everything post-match.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../constants/babysitter_emergency_constants.dart';
import '../../models/babysitter_emergency.dart';
import '../../models/babysitter_profile.dart';
import '../../services/babysitter_emergency_pricing_service.dart';
import '../../services/babysitter_emergency_service.dart';
import 'babysitter_emergency_palette.dart';

class BabysitterEmergencyProviderCard extends StatefulWidget {
  final BabysitterEmergency emergency;
  final BabysitterProfile providerProfile;

  /// Optional pre-computed distance from the provider's known location.
  /// Helps the provider judge whether to commit to a small ETA.
  final double? distanceFromProviderKm;

  const BabysitterEmergencyProviderCard({
    super.key,
    required this.emergency,
    required this.providerProfile,
    this.distanceFromProviderKm,
  });

  @override
  State<BabysitterEmergencyProviderCard> createState() =>
      _BabysitterEmergencyProviderCardState();
}

class _BabysitterEmergencyProviderCardState
    extends State<BabysitterEmergencyProviderCard> {
  final _etaCtrl = TextEditingController(text: '20');
  bool _submitting = false;

  @override
  void dispose() {
    _etaCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final eta = int.tryParse(_etaCtrl.text.trim());
    if (eta == null || eta < 5 || eta > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('זמן הגעה צריך להיות בין 5 ל-180 דקות'),
          backgroundColor: BabyEmergencyPalette.amber500,
        ),
      );
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _submitting = true);
    final result = await BabysitterEmergencyService.submitOffer(
      emergencyId: widget.emergency.id,
      etaMinutes: eta,
      providerProfile: widget.providerProfile,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result == 'duplicate') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('כבר שלחת הצעה לקריאה זו'),
          backgroundColor: BabyEmergencyPalette.amber500,
        ),
      );
      return;
    }
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הקריאה כבר נסגרה או נתפסה'),
          backgroundColor: BabyEmergencyPalette.textSecondary,
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ ההצעה נשלחה — ההורה רואה אותה עכשיו'),
        backgroundColor: BabyEmergencyPalette.green500,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final emergency = widget.emergency;
    // Compute the price the provider would charge if they accept.
    final breakdown = BabysitterEmergencyPricingService.priceForProvider(
      pricing: widget.providerProfile.pricing,
      numChildren: emergency.numChildren,
      agreedStart: emergency.agreedStartTime,
      agreedEnd: emergency.agreedEndTime,
      isHoliday: emergency.isHoliday,
    );

    return StreamBuilder<BabysitterEmergencyOffer?>(
      stream: BabysitterEmergencyService.watchMyOffer(
        emergencyId: emergency.id,
        providerId:
            widget.providerProfile.experience.hashCode.toString().isEmpty
                ? ''
                : '__current__',
      ),
      builder: (context, snap) {
        // We don't actually use the snapshot's data field — we re-render
        // based on whether the provider has submitted an offer (the main
        // card is built around their UI input).
        return _buildCard(context, emergency, breakdown);
      },
    );
  }

  Widget _buildCard(
    BuildContext context,
    BabysitterEmergency emergency,
    BabysitterEmergencyPriceBreakdown breakdown,
  ) {
    final start = emergency.agreedStartTime;
    final end = emergency.agreedEndTime;
    final duration = end.difference(start).inMinutes / 60.0;
    final formatHour = DateFormat('HH:mm', 'he');
    final ageEmojis = emergency.childrenAgeGroups
        .map(BabysitterEmergencyAgeGroup.emojiOf)
        .join(' ');

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: BabyEmergencyPalette.bgPrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: BabyEmergencyPalette.pink400,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: BabyEmergencyPalette.pink400.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: BabyEmergencyPalette.pink400,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.bolt_rounded,
                          color: Colors.white, size: 12),
                      SizedBox(width: 3),
                      Text(
                        'בייביסיטר חירום',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (widget.distanceFromProviderKm != null)
                  Text(
                    '~${widget.distanceFromProviderKm!.toStringAsFixed(1)} ק"מ',
                    style: const TextStyle(
                      color: BabyEmergencyPalette.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Children + age summary
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: BabyEmergencyPalette.purple50,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    emergency.numChildren == 1 ? '👶' : '👨‍👩‍👧',
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        emergency.numChildren == 1
                            ? 'ילד אחד'
                            : '${emergency.numChildren} ילדים',
                        style: const TextStyle(
                          color: BabyEmergencyPalette.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (ageEmojis.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            ageEmojis,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Time row
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: BabyEmergencyPalette.bgSecondary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded,
                      size: 14, color: BabyEmergencyPalette.purple500),
                  const SizedBox(width: 6),
                  Text(
                    '${formatHour.format(start)} → ${formatHour.format(end)}  ·  ${duration.toStringAsFixed(1)} ש',
                    style: const TextStyle(
                      color: BabyEmergencyPalette.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Reason
            Row(
              children: [
                Icon(
                  BabysitterEmergencyReason.iconOf(emergency.reason),
                  size: 14,
                  color: BabyEmergencyPalette.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    BabysitterEmergencyReason.labelOf(emergency.reason),
                    style: const TextStyle(
                      color: BabyEmergencyPalette.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (emergency.specialNotes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '"${emergency.specialNotes}"',
                style: const TextStyle(
                  color: BabyEmergencyPalette.textSecondary,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            // Auto-priced pill
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: BabyEmergencyPalette.green50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: BabyEmergencyPalette.green500,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payments_rounded,
                      size: 16, color: BabyEmergencyPalette.green700),
                  const SizedBox(width: 6),
                  const Text(
                    'מחיר אוטומטי:',
                    style: TextStyle(
                      color: BabyEmergencyPalette.green700,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '₪${breakdown.total.round()}',
                    style: const TextStyle(
                      color: BabyEmergencyPalette.green700,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // ETA input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _etaCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(3),
                    ],
                    decoration: InputDecoration(
                      labelText: 'אגיע ב…',
                      suffixText: 'דק׳',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BabyEmergencyPalette.purple500,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.2, color: Colors.white),
                        )
                      : const Text(
                          'שלחי הצעה',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
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
}
