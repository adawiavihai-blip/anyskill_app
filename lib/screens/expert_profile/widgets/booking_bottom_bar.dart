import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/pricing_model.dart';
import '../../chat_screen.dart';
import 'tokens.dart';

/// Sticky bottom action bar with a Chat button + "Book Now" CTA.
///
/// Extracted from `expert_profile_screen.dart` in §80. Stateless: receives
/// all reactive state from the parent (selected service tier, selected
/// add-ons, selected day/time, processing flag) and emits taps via
/// [onBookPressed].
///
/// The CTA shows three different states depending on `(selectedDay,
/// selectedTimeSlot, isSelf)`:
///   • idle (no date/time picked) → "Select date & time" + "Starting from"
///   • ready & not self           → "Book for {time}" + total price
///   • viewing own profile        → "Can't book self" with block icon
///   • isProcessing               → spinner overlay
class BookingBottomBar extends StatelessWidget {
  const BookingBottomBar({
    super.key,
    required this.data,
    required this.expertId,
    required this.expertName,
    required this.services,
    required this.selectedServiceIndex,
    required this.selectedAddOnIndices,
    required this.selectedDay,
    required this.selectedTimeSlot,
    required this.isProcessing,
    required this.onBookPressed,
  });

  final Map<String, dynamic> data;
  final String expertId;
  final String expertName;
  final List<Map<String, dynamic>> services;
  final int selectedServiceIndex;
  final Set<int> selectedAddOnIndices;
  final DateTime? selectedDay;
  final String? selectedTimeSlot;
  final bool isProcessing;

  /// Called when the user taps the CTA and the booking is ready (date +
  /// time picked, not viewing own profile). The parent computes the
  /// final price + opens the booking summary sheet.
  final void Function(double totalPrice, List<AddOn> addOns) onBookPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pricing = PricingModel.fromFirestore(data);
    final svcPrice = services[selectedServiceIndex]['price'] as double;
    final addOnTotal = selectedAddOnIndices.fold<double>(
        0.0,
        (acc, idx) =>
            acc + (idx < pricing.addOns.length ? pricing.addOns[idx].price : 0.0));
    final totalPrice = svcPrice + addOnTotal;
    final isReady = selectedDay != null && selectedTimeSlot != null;
    final isSelf =
        (FirebaseAuth.instance.currentUser?.uid ?? '') == expertId;
    final canBook = isReady && !isSelf;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, -5)),
              ],
            ),
            child: Row(
              children: [
                // ── Chat button ──────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: ExpertProfileTokens.purple
                            .withValues(alpha: 0.35)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.chat_bubble_outline_rounded,
                        color: ExpertProfileTokens.purple),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ChatScreen(
                                receiverId: expertId,
                                receiverName: expertName))),
                  ),
                ),
                const SizedBox(width: 12),
                // ── Book Now ─────────────────────────────────────────
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ExpertProfileTokens.purple,
                      disabledBackgroundColor: Colors.grey[300],
                      disabledForegroundColor: Colors.white,
                      minimumSize: const Size(0, 54),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: canBook
                        ? () => onBookPressed(totalPrice, pricing.addOns)
                        : null,
                    child: isProcessing
                        ? const CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5)
                        : isSelf
                            ? Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.block_rounded,
                                      color: Colors.white, size: 16),
                                  const SizedBox(width: 6),
                                  Text(l10n.expCantBookSelf,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                ],
                              )
                            : isReady
                                ? Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Icon(
                                          Icons.arrow_back_ios_new_rounded,
                                          color: Colors.white,
                                          size: 14),
                                      Text(
                                        l10n.expertBookForTime(
                                            selectedTimeSlot ?? ''),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16),
                                      ),
                                      Text(
                                        '₪${totalPrice.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16),
                                      ),
                                    ],
                                  )
                                : Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        l10n.expertStartingFrom(pricing
                                            .basePrice
                                            .toStringAsFixed(0)),
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11),
                                      ),
                                      Text(
                                        l10n.expertSelectDateTime,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15),
                                      ),
                                    ],
                                  ),
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
