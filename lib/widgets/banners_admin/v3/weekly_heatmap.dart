import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// 7-day × 4-hour heatmap for Section 5 (Schedule) of the banner edit
/// screen. Picks coarse 4-hour buckets (8 / 12 / 16 / 20).
///
/// Mockup spec ([banners-mockup-v3.html:392-399](docs/ui-specs/Baner/banners-mockup-v3.html)):
///   - 8-col grid: leading column = hour labels, then 7 day columns
///   - Each cell ~18px tall, 3px gap
///   - On state: `ink` (dark)
///   - "peak" hour 16:00 has gold accent when on (visual marker —
///     16:00 is empirically the highest-CTR hour for promotional banners)
///   - Click toggles a single cell
///
/// State shape: `{sun: [8, 12, 16], mon: [16, 20], ...}` — the user's
/// `BannerModel.scheduleHours` field. Empty map = always-on (no schedule
/// gating); the screen shows that as an info banner above the grid.
class StudioWeeklyHeatmap extends StatelessWidget {
  const StudioWeeklyHeatmap({
    super.key,
    required this.schedule,
    required this.onChanged,
  });

  /// Per-day list of selected hours. Days use the keys
  /// `sun, mon, tue, wed, thu, fri, sat` — RTL-natural ordering.
  final Map<String, List<int>> schedule;

  /// Called with a fresh map after every cell toggle.
  final ValueChanged<Map<String, List<int>>> onChanged;

  static const _days = <_DaySpec>[
    _DaySpec(key: 'sun', label: 'א'),
    _DaySpec(key: 'mon', label: 'ב'),
    _DaySpec(key: 'tue', label: 'ג'),
    _DaySpec(key: 'wed', label: 'ד'),
    _DaySpec(key: 'thu', label: 'ה'),
    _DaySpec(key: 'fri', label: 'ו'),
    _DaySpec(key: 'sat', label: 'ש'),
  ];

  // Top-to-bottom: 20:00, 16:00, 12:00, 8:00 (visually descending hour
  // makes "peak" 16:00 sit naturally near the top).
  static const _hours = [20, 16, 12, 8];

  void _toggle(String dayKey, int hour) {
    final next = <String, List<int>>{};
    schedule.forEach((k, v) => next[k] = List<int>.from(v));
    final list = (next[dayKey] ?? <int>[]).toList();
    if (list.contains(hour)) {
      list.remove(hour);
    } else {
      list.add(hour);
    }
    if (list.isEmpty) {
      next.remove(dayKey);
    } else {
      list.sort();
      next[dayKey] = list;
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Day labels row
        Row(
          children: [
            const SizedBox(width: 36),
            for (final d in _days)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    d.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: StudioColors.ink3,
                    ),
                  ),
                ),
              ),
          ],
        ),

        // Grid rows (one per hour)
        for (final hour in _hours)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    '${hour.toString().padLeft(2, '0')}:00',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      color: StudioColors.ink4,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                for (final d in _days)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 3),
                      child: _Cell(
                        on: (schedule[d.key] ?? const []).contains(hour),
                        peak: hour == 16,
                        onTap: () => _toggle(d.key, hour),
                      ),
                    ),
                  ),
              ],
            ),
          ),

        const SizedBox(height: 8),

        // Helper row
        Row(
          children: [
            _LegendChip(color: StudioColors.ink, label: 'מופעל'),
            const SizedBox(width: 12),
            _LegendChip(color: StudioColors.gold, label: 'שעת שיא'),
            const SizedBox(width: 12),
            _LegendChip(color: StudioColors.bgSubtle, label: 'מושבת'),
          ],
        ),
      ],
    );
  }
}

class _DaySpec {
  final String key;
  final String label;
  const _DaySpec({required this.key, required this.label});
}

class _Cell extends StatelessWidget {
  const _Cell({required this.on, required this.peak, required this.onTap});
  final bool on;
  final bool peak;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = on
        ? (peak ? StudioColors.gold : StudioColors.ink)
        : StudioColors.bgSubtle;
    return InkWell(
      borderRadius: BorderRadius.circular(3),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 18,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: StudioColors.line, width: 1),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: StudioText.captionSm(),
          textDirection: TextDirection.rtl,
        ),
      ],
    );
  }
}
