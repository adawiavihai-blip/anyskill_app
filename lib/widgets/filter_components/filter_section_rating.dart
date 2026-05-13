// lib/widgets/filter_components/filter_section_rating.dart
//
// בלוק דירוג מינימלי — 4 כפתורים: הכל / 4.0+ / 4.5+ / 4.8+

import 'package:flutter/material.dart';
import '../../models/filter_schema.dart';

class FilterSectionRating extends StatelessWidget {
  final FilterSection section;
  final double? value;
  final ValueChanged<double?> onChanged;

  const FilterSectionRating({
    super.key,
    required this.section,
    required this.value,
    required this.onChanged,
  });

  static const _options = [
    {'value': 0.0, 'label': 'הכל'},
    {'value': 4.0, 'label': '★ 4.0+'},
    {'value': 4.5, 'label': '★ 4.5+'},
    {'value': 4.8, 'label': '★ 4.8+'},
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _options.map((opt) {
        final v = opt['value'] as double;
        final active = (value ?? 0) == v;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.5),
            child: GestureDetector(
              onTap: () => onChanged(v == 0 ? null : v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: active ? const Color(0xFFFEF3C7) : Colors.white,
                  border: Border.all(
                    color: active
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFFF1F5F9),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  opt['label'] as String,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: active
                        ? const Color(0xFF92400E)
                        : const Color(0xFF475569),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
