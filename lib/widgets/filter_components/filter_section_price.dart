// lib/widgets/filter_components/filter_section_price.dart
//
// בלוק טווח מחיר — RangeSlider עם היסטוגרמת התפלגות מחירים מעל.
// extra צריך לכלול: {min, max, histogram[], defaultRange[from, to]}

import 'package:flutter/material.dart';
import '../../models/filter_schema.dart';

class FilterSectionPrice extends StatefulWidget {
  final FilterSection section;
  final Map<String, double>? value; // {from, to}
  final ValueChanged<Map<String, double>?> onChanged;

  const FilterSectionPrice({
    super.key,
    required this.section,
    required this.value,
    required this.onChanged,
  });

  @override
  State<FilterSectionPrice> createState() => _FilterSectionPriceState();
}

class _FilterSectionPriceState extends State<FilterSectionPrice> {
  late RangeValues _range;
  late double _min;
  late double _max;
  List<double> _histogram = [];

  static const _indigo = Color(0xFF6366F1);
  static const _purple = Color(0xFF8B5CF6);

  @override
  void initState() {
    super.initState();
    final extra = widget.section.extra ?? const {};
    _min = (extra['min'] as num?)?.toDouble() ?? 0;
    _max = (extra['max'] as num?)?.toDouble() ?? 500;
    _histogram = (extra['histogram'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        _defaultHistogram();

    final defaultRange = extra['defaultRange'] as List?;
    final from = widget.value?['from'] ??
        (defaultRange != null ? (defaultRange[0] as num).toDouble() : _min);
    final to = widget.value?['to'] ??
        (defaultRange != null ? (defaultRange[1] as num).toDouble() : _max);
    _range = RangeValues(from.clamp(_min, _max), to.clamp(_min, _max));
  }

  List<double> _defaultHistogram() => List.generate(15, (i) {
        final mid = 7;
        final dist = (i - mid).abs();
        return (100 - dist * 12).clamp(5, 100).toDouble();
      });

  void _commit() {
    widget.onChanged({'from': _range.start, 'to': _range.end});
  }

  @override
  Widget build(BuildContext context) {
    final maxBar = _histogram.reduce((a, b) => a > b ? a : b);
    final activeFromIdx =
        ((_range.start - _min) / (_max - _min) * _histogram.length).floor();
    final activeToIdx =
        ((_range.end - _min) / (_max - _min) * _histogram.length).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF0FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '₪${_range.start.round()} — ₪${_range.end.round()}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4338CA),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 48,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(_histogram.length, (i) {
              final isActive = i >= activeFromIdx && i < activeToIdx;
              final h = (_histogram[i] / maxBar) * 48;
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  height: h,
                  decoration: BoxDecoration(
                    gradient: isActive
                        ? const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [_purple, _indigo],
                          )
                        : null,
                    color: isActive ? null : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: _indigo,
            inactiveTrackColor: const Color(0xFFF1F5F9),
            thumbColor: Colors.white,
            overlayColor: _indigo.withValues(alpha: 0.1),
            rangeThumbShape: const RoundRangeSliderThumbShape(
              enabledThumbRadius: 11,
              elevation: 2,
            ),
          ),
          child: RangeSlider(
            values: _range,
            min: _min,
            max: _max,
            divisions: ((_max - _min) / 10).round(),
            onChanged: (v) => setState(() => _range = v),
            onChangeEnd: (_) => _commit(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('₪${_min.round()}',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
              const Text(
                '73% מהספקים בטווח',
                style: TextStyle(
                  fontSize: 10,
                  color: Color(0xFF10B981),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text('₪${_max.round()}+',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
            ],
          ),
        ),
      ],
    );
  }
}
