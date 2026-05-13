// lib/widgets/filter_components/filter_section_switches.dart
//
// בלוק של "מתגים" — שורות עם אייקון, כותרת, תיאור ארוך + Switch.
// לאופציות שדורשות הסבר (אישורים, אחריות, תכונות).

import 'package:flutter/material.dart';
import '../../models/filter_schema.dart';

class FilterSectionSwitches extends StatelessWidget {
  final FilterSection section;
  final Set<String>? value;
  final ValueChanged<Set<String>> onChanged;

  const FilterSectionSwitches({
    super.key,
    required this.section,
    required this.value,
    required this.onChanged,
  });

  static const _indigo = Color(0xFF6366F1);
  static const _purple = Color(0xFF8B5CF6);
  static const _textPrimary = Color(0xFF0F172A);
  static const _textMuted = Color(0xFF64748B);
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
    return Column(
      children: section.options.map((opt) {
        final active = value?.contains(opt.value) ?? false;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _buildRow(opt, active),
        );
      }).toList(),
    );
  }

  Widget _buildRow(FilterOption opt, bool active) {
    return GestureDetector(
      onTap: () => _toggle(opt.value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFAFBFF) : Colors.white,
          border: Border.all(
            color: active ? const Color(0xFFC7D2FE) : _borderLight,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            _iconBox(opt),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    opt.label,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                    ),
                  ),
                  if (opt.meta != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      opt.meta!,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: _textMuted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _switch(active),
          ],
        ),
      ),
    );
  }

  Widget _iconBox(FilterOption opt) {
    final bg = _parseColor(opt.bgColor) ?? _indigo;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        opt.emoji ?? '•',
        style: const TextStyle(fontSize: 15, color: Colors.white),
      ),
    );
  }

  Widget _switch(bool active) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 38,
      height: 22,
      decoration: BoxDecoration(
        gradient: active
            ? const LinearGradient(colors: [_indigo, _purple])
            : null,
        color: active ? null : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: 2,
            right: active ? 18 : 2,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color? _parseColor(String? hex) {
    if (hex == null || !hex.startsWith('#')) return null;
    try {
      return Color(int.parse('FF${hex.substring(1)}', radix: 16));
    } catch (_) {
      return null;
    }
  }
}
