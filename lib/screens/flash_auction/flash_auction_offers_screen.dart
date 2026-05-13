// Flash Auction — Step 4 of 4: "הצעות מגרריסטים".
//
// Streams flash_auctions/{auctionId}/offers, ranks them by
// recommendation score, badges the top one as "המומלץ ביותר", and
// lets the customer pick one to proceed to Pay & Secure.
//
// Customer-side timer (mockup §4): a 60-second on-screen countdown that
// disappears at 0 — the auction itself stays alive until the server-side
// 120s expiry. The disappearing timer reduces decision pressure without
// shortening the actual window.
//
// IMPORTANT — visual fidelity caveat: this is a v1 implementation that
// renders a compact offer row from the snapshot fields stored on each
// offer doc (providerName / rating / image / verified / volunteer / pro
// — frozen at offer-creation time per spec).
//
// The user explicitly asked for the *same* expert card from
// category_results_screen.dart to appear here. That refactor (extracting
// _buildExpertCard → lib/widgets/expert_card.dart) ships in a follow-up
// PR — see todo "Refactor _buildExpertCard". This row is structurally
// equivalent (image + name + stats + rating + auction strip + CTA) and
// will be swapped to ExpertCard once the extraction lands. The auction
// strip + recommendation badge are the Flash-Auction-specific bits that
// will become the `flashAuctionFooter` parameter on ExpertCard.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../constants/flash_auction_constants.dart';
import '../../models/flash_auction.dart';
import '../../services/flash_auction_service.dart';
import '../../utils/safe_image_provider.dart';
import 'flash_auction_palette.dart';

class FlashAuctionOffersScreen extends StatefulWidget {
  final String auctionId;

  const FlashAuctionOffersScreen({super.key, required this.auctionId});

  @override
  State<FlashAuctionOffersScreen> createState() =>
      _FlashAuctionOffersScreenState();
}

class _FlashAuctionOffersScreenState
    extends State<FlashAuctionOffersScreen> {
  Timer? _displayTimer;
  int _displayCountdown = FlashAuctionConfig.customerOffersDisplayTimeoutSec;
  bool _selecting = false;

  @override
  void initState() {
    super.initState();
    _displayTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_displayCountdown <= 0) {
        t.cancel();
        return;
      }
      setState(() => _displayCountdown -= 1);
    });
  }

  @override
  void dispose() {
    _displayTimer?.cancel();
    super.dispose();
  }

  /// Customer tapped "בחר" on an offer card. Runs the direct-book service —
  /// no more detour through ExpertProfileScreen + auto-Pay & Secure. One
  /// atomic transaction creates the paid_escrow job, debits the wallet,
  /// flips the auction → matched + offer → selected, and credits the
  /// provider's pendingBalance.
  ///
  /// On success: pop the entire Flash Auction stack back to wherever the
  /// flow was launched from (CategoryResultsScreen / HomeScreen) and show
  /// a green Hebrew snackbar. Customer + provider both see the new booking
  /// in their "הזמנות" tab — the provider's task stream (`jobs where
  /// expertId == self`) auto-picks it up.
  Future<void> _selectOffer(FlashAuctionOffer offer) async {
    if (_selecting) return;
    setState(() => _selecting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      // Need the latest auction snapshot (distance, pickup/dropoff, photos)
      // for the job doc — the stream's `first` returns the current value
      // immediately.
      final auction =
          await FlashAuctionService.watchAuction(widget.auctionId).first;
      if (!mounted) return;
      if (auction == null) {
        setState(() => _selecting = false);
        messenger.showSnackBar(
          const SnackBar(content: Text('שגיאה — הקריאה לא נמצאה')),
        );
        return;
      }

      final result = await FlashAuctionService.bookFromOffer(
        auction: auction,
        offer: offer,
      );
      if (!mounted) return;

      if (result.error != null) {
        setState(() => _selecting = false);
        messenger.showSnackBar(SnackBar(
          content: Text(result.error!),
          backgroundColor: FlashPalette.red500,
        ));
        return;
      }

      // Success — pop everything back to whatever screen launched the
      // Flash Auction flow (HomeScreen / CategoryResultsScreen).
      navigator.popUntil((r) => r.isFirst);
      messenger.showSnackBar(SnackBar(
        backgroundColor: FlashPalette.green500,
        content: Text(
          'ההזמנה נוצרה — ${offer.providerName} בדרך אליך '
          '(ETA: ${offer.etaMinutes} דק׳). אפשר לראות אותה תחת "הזמנות".',
        ),
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _selecting = false);
      messenger.showSnackBar(SnackBar(content: Text('שגיאה: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: FlashPalette.bgSecondary,
        appBar: AppBar(
          backgroundColor: FlashPalette.bgPrimary,
          surfaceTintColor: FlashPalette.bgPrimary,
          elevation: 0.5,
          centerTitle: false,
          iconTheme: const IconThemeData(color: FlashPalette.textPrimary),
          title: const Text(
            'הצעות מגרריסטים',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: FlashPalette.textPrimary,
            ),
          ),
        ),
        body: SafeArea(
          child: StreamBuilder<List<FlashAuctionOffer>>(
            stream: FlashAuctionService.watchOffers(widget.auctionId),
            builder: (_, snap) {
              final offers = snap.data ?? const <FlashAuctionOffer>[];
              return Column(
                children: [
                  _OffersHeader(
                    offerCount: offers.length,
                    countdownSec: _displayCountdown,
                  ),
                  Expanded(
                    child: offers.isEmpty
                        ? const _WaitingForOffers()
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(
                                14, 12, 14, 24),
                            itemCount: offers.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final offer = offers[i];
                              final recommended = i == 0; // already sorted
                              return _OfferCard(
                                offer: offer,
                                recommended: recommended,
                                disabled: _selecting,
                                onSelect: () => _selectOffer(offer),
                              );
                            },
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
// HEADER + EMPTY STATE
// ═══════════════════════════════════════════════════════════════════════

class _OffersHeader extends StatelessWidget {
  final int offerCount;
  final int countdownSec;

  const _OffersHeader({
    required this.offerCount,
    required this.countdownSec,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: FlashPalette.purple50,
        border: Border(
          bottom: BorderSide(color: FlashPalette.purple200, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              offerCount == 0
                  ? 'ממתינים להצעות...'
                  : '$offerCount הצעות הגיעו',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: FlashPalette.purple700,
              ),
            ),
          ),
          if (countdownSec > 0)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.access_time_rounded,
                  size: 13,
                  color: FlashPalette.purple500,
                ),
                const SizedBox(width: 4),
                Text(
                  '$countdownSec שניות נותרו',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: FlashPalette.purple500,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _WaitingForOffers extends StatelessWidget {
  const _WaitingForOffers();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(
              Icons.hourglass_top_rounded,
              size: 36,
              color: FlashPalette.purple500,
            ),
            SizedBox(height: 12),
            Text(
              'ממתינים שהגרריסטים יגיבו',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: FlashPalette.textPrimary,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'ברגע שתגיע ההצעה הראשונה תוכל לבחור כאן',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: FlashPalette.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// OFFER CARD (v1 — will be swapped to ExpertCard in follow-up PR)
// ═══════════════════════════════════════════════════════════════════════

class _OfferCard extends StatelessWidget {
  final FlashAuctionOffer offer;
  final bool recommended;
  final bool disabled;
  final VoidCallback onSelect;

  const _OfferCard({
    required this.offer,
    required this.recommended,
    required this.disabled,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final imgProvider = safeImageProvider(offer.providerImageUrl);
    return Container(
      decoration: BoxDecoration(
        color: FlashPalette.bgPrimary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: recommended
              ? FlashPalette.green500
              : FlashPalette.borderTertiary,
          width: recommended ? 1.2 : 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: recommended
                ? FlashPalette.green500.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: recommended ? 14 : 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (recommended) const _RecommendedBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: FlashPalette.purple50,
                      backgroundImage: imgProvider,
                      child: imgProvider == null
                          ? Text(
                              offer.providerName.isNotEmpty
                                  ? offer.providerName[0]
                                  : '?',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: FlashPalette.purple700,
                              ),
                            )
                          : null,
                    ),
                    if (offer.providerIsVolunteer)
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.favorite_rounded,
                            color: Color(0xFFD4AF37),
                            size: 13,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              offer.providerName.isNotEmpty
                                  ? offer.providerName
                                  : '—',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: FlashPalette.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (offer.providerIsVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified,
                              color: Color(0xFF1877F2),
                              size: 13,
                            ),
                          ],
                          if (offer.providerIsPro) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.workspace_premium_rounded,
                              color: Color(0xFFD4AF37),
                              size: 13,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'גרר אופנועים',
                        style: TextStyle(
                          fontSize: 11,
                          color: FlashPalette.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 13,
                            color: Color(0xFFFBBF24),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            offer.providerRating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: FlashPalette.textPrimary,
                            ),
                          ),
                          if (offer.providerJobsCount > 0) ...[
                            const SizedBox(width: 6),
                            const Text('·',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: FlashPalette.textTertiary)),
                            const SizedBox(width: 6),
                            Text(
                              '${offer.providerJobsCount} גרירות',
                              style: const TextStyle(
                                fontSize: 11,
                                color: FlashPalette.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: FlashPalette.bgSecondary,
              border: Border(
                top: BorderSide(
                  color: FlashPalette.borderTertiary,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'זמן הגעה',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: FlashPalette.textTertiary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${offer.etaMinutes} דקות',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: FlashPalette.green500,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'מחיר סופי',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: FlashPalette.textTertiary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₪${offer.totalPrice.round()}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: FlashPalette.purple700,
                        ),
                      ),
                    ],
                  ),
                ),
                _SelectButton(
                  recommended: recommended,
                  disabled: disabled,
                  onTap: onSelect,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendedBanner extends StatelessWidget {
  const _RecommendedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: FlashPalette.green500,
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.star_rounded, color: Colors.white, size: 13),
          SizedBox(width: 4),
          Text(
            'המומלץ ביותר — מחיר טוב + הגעה מהירה',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectButton extends StatelessWidget {
  final bool recommended;
  final bool disabled;
  final VoidCallback onTap;

  const _SelectButton({
    required this.recommended,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        recommended ? FlashPalette.green500 : FlashPalette.purple500;
    return Material(
      color: disabled ? color.withValues(alpha: 0.55) : color,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: const Padding(
          padding:
              EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'בחר',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.arrow_back_rounded,
                  size: 14, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
