// lib/widgets/filter_components/filter_section_chips.dart
//
// בלוק של "צ'יפים" — בחירה מרובה קומפקטית.
// טוב לרשימות ארוכות (סוגי מזיקים, התמחויות, סגנונות).

import 'package:flutter/material.dart';
import '../../models/filter_schema.dart';

class FilterSectionChips extends StatelessWidget {
  final FilterSection section;
  final Set<String>? value;
  final ValueChanged<Set<String>> onChanged;

  const FilterSectionChips({
    super.key,
    required this.section,
    required this.value,
    required this.onChanged,
  });

  static const _indigo = Color(0xFF6366F1);
  static const _textMuted = Color(0xFF475569);
  static const _borderLight = Color(0xFFF1F5F9);

  void _toggle(String optValue) {
    final current = value?.toSet() ?? <String>{};
    if (current.contains(optValue)) {
      current.remove(optValue);
    } else {
      current.add(optValue);
    }
    onChanged(current);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: section.options.map((opt) {
        final active = value?.contains(opt.value) ?? false;
        return _buildChip(opt, active);
      }).toList(),
    );
  }

  Widget _buildChip(FilterOption opt, bool active) {
    return GestureDetector(
      onTap: () => _toggle(opt.value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEEF0FF) : Colors.white,
          border: Border.all(
            color: active ? _indigo : _borderLight,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (opt.emoji != null) ...[
              Text(opt.emoji!, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 5),
            ],
            Text(
              opt.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: active ? const Color(0xFF4338CA) : _textMuted,
              ),
            ),
            if (opt.meta != null) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: active
                      ? _indigo.withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  opt.meta!,
                  style: TextStyle(
                    fontSize: 9,
                    color: active ? const Color(0xFF4338CA) : _textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
