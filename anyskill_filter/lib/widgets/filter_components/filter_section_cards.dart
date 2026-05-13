// lib/widgets/filter_components/filter_section_cards.dart
//
// בלוק של "כרטיסים" — לבחירה ראשית עם אייקון בולט.
// תומך בבחירה יחידה (singleSelect=true) או מרובה.

import 'package:flutter/material.dart';
import '../../models/filter_schema.dart';

class FilterSectionCards extends StatelessWidget {
  final FilterSection section;
  final dynamic value; // String לבחירה יחידה, Set<String> למרובה
  final ValueChanged<dynamic> onChanged;

  const FilterSectionCards({
    super.key,
    required this.section,
    required this.value,
    required this.onChanged,
  });

  static const _indigo = Color(0xFF6366F1);
  static const _textPrimary = Color(0xFF0F172A);
  static const _textMuted = Color(0xFF64748B);
  static const _borderLight = Color(0xFFF1F5F9);

  bool _isActive(String optValue) {
    if (section.singleSelect) return value == optValue;
    if (value is Set) return (value as Set).contains(optValue);
    return false;
  }

  void _toggle(String optValue) {
    if (section.singleSelect) {
      onChanged(value == optValue ? null : optValue);
    } else {
      final current = (value as Set<String>?)?.toSet() ?? <String>{};
      if (current.contains(optValue)) {
        current.remove(optValue);
      } else {
        current.add(optValue);
      }
      onChanged(current);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cols = section.options.length == 3 ? 3 : 2;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: section.options.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        mainAxisExtent: 72,
      ),
      itemBuilder: (_, i) {
        final opt = section.options[i];
        final active = _isActive(opt.value);
        return _buildCard(opt, active);
      },
    );
  }

  Widget _buildCard(FilterOption opt, bool active) {
    return GestureDetector(
      onTap: () => _toggle(opt.value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFAFBFF) : Colors.white,
          border: Border.all(
            color: active ? _indigo : _borderLight,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: _indigo.withValues(alpha: 0.06),
                    blurRadius: 0,
                    spreadRadius: 4,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            _iconBox(opt),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    opt.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                    ),
                  ),
                  if (opt.meta != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      opt.meta!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: _textMuted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBox(FilterOption opt) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _parseColor(opt.bgColor) ?? const Color(0xFFEEF0FF),
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child: Text(
        opt.emoji ?? '•',
        style: const TextStyle(fontSize: 18),
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
