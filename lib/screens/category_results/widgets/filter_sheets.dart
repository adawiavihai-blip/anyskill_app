import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../l10n/app_localizations.dart';

const _kPurple = Color(0xFF6366F1);

/// Bottom-sheet filter helpers shared by [CategoryResultsScreen] (list view)
/// and the map overlay header.
///
/// Extracted from `category_results_screen.dart` in §81 (C.5). Each
/// method takes the current value + an `onApply(newValue)` callback —
/// the parent State holds the canonical filter state.
class FilterSheets {
  FilterSheets._();

  /// Min-rating picker: 0 / 3 / 3.5 / 4 / 4.5 chips.
  /// `0.0` represents "all" (no rating filter).
  static void showRating({
    required BuildContext context,
    required double current,
    required ValueChanged<double> onApply,
  }) {
    double temp = current;
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.catFilterRatingTitle,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final r in [0.0, 3.0, 3.5, 4.0, 4.5])
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(r == 0
                            ? l10n.catFilterAll
                            : '${r.toStringAsFixed(1)}+'),
                        selected: temp == r,
                        selectedColor: _kPurple,
                        labelStyle: TextStyle(
                            color: temp == r
                                ? Colors.white
                                : Colors.black87,
                            fontSize: 13),
                        onSelected: (_) => setLocal(() => temp = r),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _kPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  onPressed: () {
                    Navigator.pop(ctx);
                    onApply(temp);
                  },
                  child: Text(l10n.catFilterApply,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Max-distance slider (1-50 km). Disabled when [currentPosition] is null.
  /// Pass `null` to onApply to clear the filter.
  static void showDistance({
    required BuildContext context,
    required double? currentKm,
    required Position? currentPosition,
    required ValueChanged<double?> onApply,
  }) {
    double tempKm = currentKm ?? 15;
    final hasLocation = currentPosition != null;
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.catFilterDistanceTitle,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              if (!hasLocation)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(l10n.catFilterNeedLocation,
                      style: TextStyle(
                          color: Colors.orange[700], fontSize: 13)),
                ),
              Text('${tempKm.toInt()} ק"מ',
                  style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: _kPurple)),
              Slider(
                value: tempKm,
                min: 1,
                max: 50,
                divisions: 49,
                activeColor: _kPurple,
                label: '${tempKm.toInt()} ק"מ',
                onChanged: hasLocation
                    ? (v) => setLocal(() => tempKm = v)
                    : null,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('50 ק"מ',
                      style: TextStyle(
                          color: Colors.grey[500], fontSize: 12)),
                  Text('1 ק"מ',
                      style: TextStyle(
                          color: Colors.grey[500], fontSize: 12)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(12))),
                      onPressed: () {
                        Navigator.pop(ctx);
                        onApply(null);
                      },
                      child: Text(l10n.catFilterClear),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _kPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(12))),
                      onPressed: hasLocation
                          ? () {
                              Navigator.pop(ctx);
                              onApply(tempKm);
                            }
                          : null,
                      child: Text(l10n.catFilterApply,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
