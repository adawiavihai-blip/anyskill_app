// lib/widgets/dynamic_filter_sheet.dart
//
// המודאל הראשי. נפתח כ-bottom sheet, טוען schema מ-Firestore, ומרנדר
// את ה-sections לפי הסוג שלהם.
//
// שימוש:
// showModalBottomSheet(
//   context: context,
//   isScrollControlled: true,
//   backgroundColor: Colors.transparent,
//   builder: (_) => DynamicFilterSheet(
//     categoryId: 'pest_control',
//     initialFilters: currentFilters,
//     onApply: (filters) => setState(() => activeFilters = filters),
//   ),
// );

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/filter_schema.dart';
import '../services/filter_schema_service.dart';
import 'filter_components/filter_section_cards.dart';
import 'filter_components/filter_section_chips.dart';
import 'filter_components/filter_section_switches.dart';
import 'filter_components/filter_section_price.dart';
import 'filter_components/filter_section_rating.dart';
import 'filter_components/filter_section_days_time.dart';

class DynamicFilterSheet extends StatefulWidget {
  final String categoryId;
  final Map<String, dynamic> initialFilters;
  final void Function(Map<String, dynamic>) onApply;
  final int? estimatedResultCount;

  const DynamicFilterSheet({
    super.key,
    required this.categoryId,
    required this.onApply,
    this.initialFilters = const {},
    this.estimatedResultCount,
  });

  @override
  State<DynamicFilterSheet> createState() => _DynamicFilterSheetState();
}

class _DynamicFilterSheetState extends State<DynamicFilterSheet> {
  FilterSchema? _schema;
  bool _loading = true;
  late Map<String, dynamic> _filters;
  int _resultCount = 0;

  // Brand colors מ-CLAUDE.md §6.3
  static const Color _indigo = Color(0xFF6366F1);
  static const Color _purple = Color(0xFF8B5CF6);
  static const Color _textPrimary = Color(0xFF0F172A);
  static const Color _borderLight = Color(0xFFF1F5F9);

  @override
  void initState() {
    super.initState();
    _filters = Map<String, dynamic>.from(widget.initialFilters);
    _resultCount = widget.estimatedResultCount ?? 0;
    _loadSchema();
  }

  Future<void> _loadSchema() async {
    final schema = await FilterSchemaService.instance.getSchema(widget.categoryId);
    if (!mounted) return;
    setState(() {
      _schema = schema;
      _loading = false;
    });
  }

  void _updateFilter(String sectionId, dynamic value) {
    HapticFeedback.lightImpact();
    setState(() {
      if (value == null ||
          (value is List && value.isEmpty) ||
          (value is Set && value.isEmpty)) {
        _filters.remove(sectionId);
      } else {
        _filters[sectionId] = value;
      }
      // TODO: כאן תוכל לקרוא ל-API/Firestore כדי לעדכן _resultCount בזמן אמת
      // לעת עתה — אומדן פשוט
      _resultCount = _estimateCount();
    });
  }

  int _estimateCount() {
    // אומדן בסיסי. ההמלצה: לקרוא לפונקציה שמריצה count() על Firestore עם debounce.
    final base = widget.estimatedResultCount ?? 50;
    final reduction = _filters.length * 8;
    return (base - reduction).clamp(0, base);
  }

  void _resetAll() {
    HapticFeedback.mediumImpact();
    setState(() {
      _filters.clear();
      _resultCount = widget.estimatedResultCount ?? 50;
    });
  }

  void _apply() {
    HapticFeedback.mediumImpact();
    widget.onApply(_filters);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.92;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: _loading
            ? const SizedBox(
                height: 400,
                child: Center(
                  child: CircularProgressIndicator(color: _indigo),
                ),
              )
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHandle(),
        _buildHeader(),
        if (_filters.isNotEmpty) _buildActiveFiltersBar(),
        Flexible(child: _buildScrollContent()),
        _buildFooter(),
      ],
    );
  }

  Widget _buildHandle() => Padding(
        padding: const EdgeInsets.only(top: 9, bottom: 4),
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFD1D5DB),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _buildHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(22, 6, 22, 16),
        child: Row(
          children: [
            _circleButton(
              icon: Icons.close,
              onTap: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Column(
                children: [
                  const Text(
                    'סינון',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF0FF),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: _indigo,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _schema?.categoryLabel ?? '',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF4338CA),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _filters.isEmpty ? null : _resetAll,
              style: TextButton.styleFrom(
                foregroundColor: _indigo,
                disabledForegroundColor: const Color(0xFFCBD5E1),
              ),
              child: const Text(
                'איפוס',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

  Widget _circleButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: Color(0xFFF3F4F6),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: const Color(0xFF6B7280)),
      ),
    );
  }

  Widget _buildActiveFiltersBar() {
    final pills = <Widget>[];
    _filters.forEach((sectionId, value) {
      final section = _schema?.sections.firstWhere(
        (s) => s.id == sectionId,
        orElse: () => const FilterSection(
          id: '',
          title: '',
          type: FilterSectionType.chips,
        ),
      );
      if (section == null || section.id.isEmpty) return;

      String label;
      if (value is List || value is Set) {
        final items = value is Set ? value.toList() : (value as List);
        label = '${section.title} (${items.length})';
      } else if (value is Map) {
        label = section.title;
      } else {
        label = '${section.title}: $value';
      }

      pills.add(_buildActivePill(label, () {
        setState(() {
          _filters.remove(sectionId);
          _resultCount = _estimateCount();
        });
      }));
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, right: 4),
              child: Text(
                'פעיל:',
                style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
            ),
            ...pills,
          ],
        ),
      ),
    );
  }

  Widget _buildActivePill(String label, VoidCallback onRemove) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.fromLTRB(11, 5, 6, 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEEF0FF), Color(0xFFF5F0FF)],
        ),
        border: Border.all(color: const Color(0xFFC7D2FE)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF4338CA),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: _indigo.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 11, color: Color(0xFF4338CA)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _schema!.sections.map(_buildSection).toList(),
      ),
    );
  }

  Widget _buildSection(FilterSection section) {
    Widget child;

    switch (section.type) {
      case FilterSectionType.cards:
        child = FilterSectionCards(
          section: section,
          value: _filters[section.id],
          onChanged: (v) => _updateFilter(section.id, v),
        );
        break;
      case FilterSectionType.chips:
        child = FilterSectionChips(
          section: section,
          value: _filters[section.id] as Set<String>?,
          onChanged: (v) => _updateFilter(section.id, v),
        );
        break;
      case FilterSectionType.switches:
        child = FilterSectionSwitches(
          section: section,
          value: _filters[section.id] as Set<String>?,
          onChanged: (v) => _updateFilter(section.id, v),
        );
        break;
      case FilterSectionType.price:
        child = FilterSectionPrice(
          section: section,
          value: _filters[section.id] as Map<String, double>?,
          onChanged: (v) => _updateFilter(section.id, v),
        );
        break;
      case FilterSectionType.rating:
        child = FilterSectionRating(
          section: section,
          value: _filters[section.id] as double?,
          onChanged: (v) => _updateFilter(section.id, v),
        );
        break;
      case FilterSectionType.daysTime:
        child = FilterSectionDaysTime(
          section: section,
          value: _filters[section.id] as Map<String, dynamic>?,
          onChanged: (v) => _updateFilter(section.id, v),
        );
        break;
      case FilterSectionType.banner:
        return _buildBanner(section);
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borderLight, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHead(section),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _sectionHead(FilterSection section) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _textPrimary,
                ),
              ),
              if (section.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  section.subtitle!,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
              ],
            ],
          ),
        ),
        if (section.required)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'חובה',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFF92400E),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBanner(FilterSection section) {
    final html = section.extra?['html'] as String? ?? section.subtitle ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        html,
        style: const TextStyle(
          fontSize: 11.5,
          color: Color(0xFF78350F),
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _borderLight, width: 1)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () {
                  // TODO: שמור חיפוש (Phase 2)
                },
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEEF0FF),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.favorite_border,
                          size: 11, color: _indigo),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'שמור חיפוש',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF475569),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(_resultCount * 0.49).round()} מחוברים',
                    style: const TextStyle(
                      fontSize: 11,
                      color: _textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _apply,
            child: Container(
              width: double.infinity,
              height: 54,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_indigo, _purple],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          '$_resultCount',
                          key: ValueKey(_resultCount),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'תוצאות',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const Row(
                    children: [
                      Text(
                        'הצג',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_back, size: 14, color: Colors.white),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
