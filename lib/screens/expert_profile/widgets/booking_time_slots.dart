import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'tokens.dart';

/// Horizontal scrollable list of time-slot chips for the booking flow.
///
/// Extracted from `expert_profile_screen.dart` in §81 (C.3). Stateless:
/// receives `selectedSlot` + `bookedSlots` + a callback. The parent owns
/// the selection because the bottom bar reads it to compute the CTA state.
///
/// Booked slots are rendered grey with strikethrough (`Semantics.enabled=false`).
/// Tapping a booked slot is a no-op.
class BookingTimeSlots extends StatelessWidget {
  const BookingTimeSlots({
    super.key,
    required this.expertData,
    required this.selectedDay,
    required this.legacyTimeSlots,
    required this.selectedSlot,
    required this.bookedSlots,
    required this.loading,
    required this.onSlotSelected,
    required this.onSelectionInvalidated,
  });

  final Map<String, dynamic> expertData;
  final DateTime? selectedDay;
  /// Fallback slot list when the provider has no `workingHours` configured.
  final List<String> legacyTimeSlots;
  final String? selectedSlot;
  final Set<String> bookedSlots;
  final bool loading;
  final ValueChanged<String> onSlotSelected;

  /// Called via `addPostFrameCallback` when the previously-selected slot
  /// is no longer in the resolved list (e.g. user picked a different day).
  /// The parent's State should clear its `_selectedTimeSlot`.
  final VoidCallback onSelectionInvalidated;

  /// Pure helper — derives the time-slot list from the provider's
  /// `workingHours` map. Falls back to [legacyTimeSlots] when the map is
  /// missing or empty.
  static List<String> resolveTimeSlots({
    required Map<String, dynamic> expertData,
    required DateTime? selectedDay,
    required List<String> legacyTimeSlots,
  }) {
    final rawHours = expertData['workingHours'] as Map<String, dynamic>?;
    if (rawHours == null || rawHours.isEmpty || selectedDay == null) {
      return legacyTimeSlots;
    }
    // DateTime.weekday: 1=Mon..7=Sun. Schema: 0=Sun..6=Sat.
    final dayIndex = selectedDay.weekday == 7 ? 0 : selectedDay.weekday;
    final dayEntry = rawHours['$dayIndex'] as Map<String, dynamic>?;
    if (dayEntry == null) return [];
    final from = dayEntry['from']?.toString() ?? '09:00';
    final to = dayEntry['to']?.toString() ?? '17:00';
    final fromHour = int.tryParse(from.split(':').first) ?? 9;
    final toHour = int.tryParse(to.split(':').first) ?? 17;
    return [
      for (int h = fromHour; h < toHour; h++)
        '${h.toString().padLeft(2, '0')}:00',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final slots = resolveTimeSlots(
      expertData: expertData,
      selectedDay: selectedDay,
      legacyTimeSlots: legacyTimeSlots,
    );
    if (slots.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          l10n.expProviderDayOff,
          style: TextStyle(color: Colors.grey[500], fontSize: 14),
          textAlign: TextAlign.center,
        ),
      );
    }
    // Invalidate stale selection on the next frame.
    if (selectedSlot != null && !slots.contains(selectedSlot)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onSelectionInvalidated();
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (loading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: ExpertProfileTokens.purple),
              ),
            Text(l10n.expertSelectTime,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            reverse: true,
            itemCount: slots.length,
            itemBuilder: (context, index) {
              final slot = slots[index];
              final isBooked = bookedSlots.contains(slot);
              final isSelected = selectedSlot == slot;
              return Semantics(
                button: !isBooked,
                selected: isSelected,
                enabled: !isBooked,
                label: isBooked
                    ? '$slot — already booked'
                    : (isSelected ? '$slot, selected' : slot),
                child: GestureDetector(
                  onTap: isBooked ? null : () => onSlotSelected(slot),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: isBooked
                          ? Colors.grey.shade200
                          : isSelected
                              ? ExpertProfileTokens.purple
                              : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isBooked
                              ? Colors.grey.shade300
                              : isSelected
                                  ? ExpertProfileTokens.purple
                                  : Colors.grey.shade300),
                      boxShadow: isSelected && !isBooked
                          ? [
                              BoxShadow(
                                  color: ExpertProfileTokens.purple
                                      .withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2))
                            ]
                          : [],
                    ),
                    child: Center(
                      child: isBooked
                          ? Text(slot,
                              style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w500,
                                  decoration:
                                      TextDecoration.lineThrough))
                          : Text(slot,
                              style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.black87,
                                  fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
