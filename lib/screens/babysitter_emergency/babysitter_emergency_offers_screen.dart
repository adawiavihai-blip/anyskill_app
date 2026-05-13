// Step 4 of the babysitter emergency flow — compare incoming offers
// and select one. Pay & Secure runs inside
// BabysitterEmergencyService.bookFromOffer (single atomic tx).
//
// UX:
//   • 60s on-screen countdown (auction itself runs to 120s)
//   • Top offer tagged "המומלצת ביותר" (recommendationScore)
//   • Each card surfaces the trust signals that matter for childcare:
//     ✅ ביקורת רקע / 🩹 עזרה ראשונה / ⭐ דירוג / 👶 שנות נסיון
//   • On pick → atomic Pay & Secure → pop entire stack with success
//     snackbar
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/babysitter_emergency_constants.dart';
import '../../models/babysitter_emergency.dart';
import '../../services/babysitter_emergency_service.dart';
import '../../utils/safe_image_provider.dart';
import 'babysitter_emergency_palette.dart';

class BabysitterEmergencyOffersScreen extends StatefulWidget {
  final String emergencyId;
  const BabysitterEmergencyOffersScreen(
      {super.key, required this.emergencyId});

  @override
  State<BabysitterEmergencyOffersScreen> createState() =>
      _BabysitterEmergencyOffersScreenState();
}

class _BabysitterEmergencyOffersScreenState
    extends State<BabysitterEmergencyOffersScreen> {
  Timer? _displayTimer;
  int _displayCountdown =
      BabysitterEmergencyConfig.customerOffersDisplayTimeoutSec;
  bool _selecting = false;
  String? _busyOfferId;

  BabysitterEmergency? _emergency;

  @override
  void initState() {
    super.initState();
    _displayTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_displayCountdown > 0) _displayCountdown--;
      });
    });
    BabysitterEmergencyService.watchEmergency(widget.emergencyId).listen((
      doc,
    ) {
      if (!mounted) return;
      setState(() => _emergency = doc);
    });
  }

  @override
  void dispose() {
    _displayTimer?.cancel();
    super.dispose();
  }

  Future<void> _onSelectOffer(BabysitterEmergencyOffer offer) async {
    if (_selecting || _emergency == null) return;
    HapticFeedback.lightImpact();
    setState(() {
      _selecting = true;
      _busyOfferId = offer.id;
    });
    final result = await BabysitterEmergencyService.bookFromOffer(
      emergency: _emergency!,
      offer: offer,
    );
    if (!mounted) return;
    if (result.error != null) {
      setState(() {
        _selecting = false;
        _busyOfferId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error!),
          backgroundColor: BabyEmergencyPalette.red500,
        ),
      );
      return;
    }
    // Success: pop back to root.
    Navigator.popUntil(context, (route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '✅ הוזמנה ${offer.providerName}. תגיע בעוד ${offer.etaMinutes} דק׳.'),
        backgroundColor: BabyEmergencyPalette.green500,
      ),
    );
  }

  Future<void> _cancelAndExit() async {
    HapticFeedback.lightImpact();
    try {
      await BabysitterEmergencyService.cancelEmergency(
        emergencyId: widget.emergencyId,
        reason: 'customer_cancelled_offers',
      );
    } catch (_) {}
    if (!mounted) return;
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: BabyEmergencyPalette.bgSecondary,
        appBar: AppBar(
          backgroundColor: BabyEmergencyPalette.bgPrimary,
          elevation: 0,
          title: const Text(
            'בחרי בייביסיטר',
            style: TextStyle(
              color: BabyEmergencyPalette.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          iconTheme: const IconThemeData(
              color: BabyEmergencyPalette.textPrimary),
          actions: [
            if (_displayCountdown > 0)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _displayCountdown <= 15
                          ? BabyEmergencyPalette.red50
                          : BabyEmergencyPalette.purple50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 14,
                          color: _displayCountdown <= 15
                              ? BabyEmergencyPalette.red700
                              : BabyEmergencyPalette.purple700,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$_displayCountdown',
                          style: TextStyle(
                            color: _displayCountdown <= 15
                                ? BabyEmergencyPalette.red700
                                : BabyEmergencyPalette.purple700,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: StreamBuilder<List<BabysitterEmergencyOffer>>(
          stream: BabysitterEmergencyService.watchOffers(widget.emergencyId),
          builder: (context, snap) {
            if (snap.hasError) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('שגיאה בטעינת הצעות. אנא נסי שוב.'),
                ),
              );
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final offers = snap.data!;
            if (offers.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'ממתינות להצעות…',
                    style: TextStyle(
                      color: BabyEmergencyPalette.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              itemCount: offers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final offer = offers[i];
                return _OfferCard(
                  offer: offer,
                  isRecommended: i == 0,
                  isBusy: _busyOfferId == offer.id,
                  isAnyBusy: _selecting,
                  onSelect: () => _onSelectOffer(offer),
                );
              },
            );
          },
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            color: BabyEmergencyPalette.bgPrimary,
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
            child: TextButton.icon(
              onPressed: _selecting ? null : _cancelAndExit,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('בטלי את הקריאה'),
              style: TextButton.styleFrom(
                foregroundColor: BabyEmergencyPalette.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Offer card
// ═════════════════════════════════════════════════════════════════════════

class _OfferCard extends StatelessWidget {
  final BabysitterEmergencyOffer offer;
  final bool isRecommended;
  final bool isBusy;
  final bool isAnyBusy;
  final VoidCallback onSelect;

  const _OfferCard({
    required this.offer,
    required this.isRecommended,
    required this.isBusy,
    required this.isAnyBusy,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final imageProvider =
        safeImageProvider(offer.providerImageUrl);
    final initials = offer.providerName.isNotEmpty
        ? offer.providerName.characters.first.toUpperCase()
        : '?';

    return Container(
      decoration: BoxDecoration(
        color: BabyEmergencyPalette.bgPrimary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isRecommended
              ? BabyEmergencyPalette.green500
              : BabyEmergencyPalette.borderTertiary,
          width: isRecommended ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          if (isRecommended)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: const BoxDecoration(
                color: BabyEmergencyPalette.green500,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(17)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.star_rounded, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text(
                    'המומלצת ביותר',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    // Avatar
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: BabyEmergencyPalette.purple50,
                        border: Border.all(
                          color: BabyEmergencyPalette.purple200,
                          width: 1.5,
                        ),
                        image: imageProvider != null
                            ? DecorationImage(
                                image: imageProvider,
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: imageProvider == null
                          ? Center(
                              child: Text(
                                initials,
                                style: const TextStyle(
                                  color: BabyEmergencyPalette.purple700,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 22,
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    // Name + rating
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  offer.providerName.isEmpty
                                      ? 'מטפלת'
                                      : offer.providerName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color:
                                        BabyEmergencyPalette.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (offer.providerIsVerified) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.verified_rounded,
                                  size: 16,
                                  color:
                                      BabyEmergencyPalette.purple500,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.star_rounded,
                                  size: 14,
                                  color: BabyEmergencyPalette.amber500),
                              const SizedBox(width: 2),
                              Text(
                                offer.providerRating > 0
                                    ? offer.providerRating.toStringAsFixed(1)
                                    : 'חדשה',
                                style: const TextStyle(
                                  color:
                                      BabyEmergencyPalette.textSecondary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (offer.providerReviewsCount > 0)
                                Text(
                                  ' (${offer.providerReviewsCount})',
                                  style: const TextStyle(
                                    color:
                                        BabyEmergencyPalette.textTertiary,
                                    fontSize: 12,
                                  ),
                                ),
                              if (offer.providerYearsExperience > 0) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: BabyEmergencyPalette.purple50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${offer.providerYearsExperience} שנות נסיון',
                                    style: const TextStyle(
                                      color:
                                          BabyEmergencyPalette.purple700,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // ETA + price column
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: BabyEmergencyPalette.purple500,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${offer.etaMinutes} דק׳',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₪${offer.totalPrice.round()}',
                          style: const TextStyle(
                            color: BabyEmergencyPalette.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Trust badges
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (offer.providerIsBackgroundChecked)
                      const _TrustBadge(
                        icon: Icons.verified_user_rounded,
                        label: 'ביקורת רקע',
                        bg: BabyEmergencyPalette.green50,
                        fg: BabyEmergencyPalette.green700,
                      ),
                    if (offer.providerHasFirstAid)
                      const _TrustBadge(
                        icon: Icons.local_hospital_rounded,
                        label: 'עזרה ראשונה',
                        bg: BabyEmergencyPalette.red50,
                        fg: BabyEmergencyPalette.red700,
                      ),
                    if (offer.providerIsPro)
                      const _TrustBadge(
                        icon: Icons.workspace_premium_rounded,
                        label: 'AnySkill Pro',
                        bg: BabyEmergencyPalette.amber50,
                        fg: BabyEmergencyPalette.amber700,
                      ),
                    if (offer.providerJobsCount > 0)
                      _TrustBadge(
                        icon: Icons.history_rounded,
                        label: '${offer.providerJobsCount} משמרות',
                        bg: BabyEmergencyPalette.bgTertiary,
                        fg: BabyEmergencyPalette.textSecondary,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // Price breakdown explainer
                _PriceBreakdownRow(breakdown: offer.priceBreakdown),
                const SizedBox(height: 12),
                // CTA
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: isAnyBusy ? null : onSelect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isRecommended
                          ? BabyEmergencyPalette.green500
                          : BabyEmergencyPalette.purple500,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          BabyEmergencyPalette.borderSecondary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: isBusy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'בחרי ושלמי ₪${offer.totalPrice.round()}',
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;

  const _TrustBadge({
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceBreakdownRow extends StatelessWidget {
  final BabysitterEmergencyPriceBreakdown breakdown;
  const _PriceBreakdownRow({required this.breakdown});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (breakdown.regularHours > 0) {
      parts.add(
          '${breakdown.regularHours.toStringAsFixed(1)}ש רגילות · ₪${breakdown.regularAmount.round()}');
    }
    if (breakdown.nightHours > 0) {
      parts.add(
          '${breakdown.nightHours.toStringAsFixed(1)}ש לילה · ₪${breakdown.nightAmount.round()}');
    }
    if (breakdown.lastMinuteSurcharge > 0) {
      parts.add('תוספת חירום: ₪${breakdown.lastMinuteSurcharge.round()}');
    }
    if (breakdown.holidaySurcharge > 0) {
      parts.add('תוספת חג: ₪${breakdown.holidaySurcharge.round()}');
    }
    if (parts.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: BabyEmergencyPalette.bgSecondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        parts.join('  •  '),
        style: const TextStyle(
          color: BabyEmergencyPalette.textTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      ),
    );
  }
}
