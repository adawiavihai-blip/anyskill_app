/// AnySkill — Category Tags Selector
///
/// Multi-select chip grid shown in the edit-profile screen for providers.
/// Loads the catalog for the provider's category via [CategoryTagsService]
/// and persists selections via [onChanged]. Hard cap of 5 selections
/// (complements the existing `quickTags` max-3 → 8 total differentiators).
///
/// Hidden entirely when the category has no seeded catalog (returns
/// [SizedBox.shrink]). The host screen doesn't need to pre-check.
library;

import 'package:flutter/material.dart';

import '../models/category_tag.dart';
import '../services/category_tags_service.dart';

class CategoryTagsSelector extends StatefulWidget {
  final String category;
  final Set<String> initialSelected;
  final ValueChanged<Set<String>> onChanged;

  const CategoryTagsSelector({
    super.key,
    required this.category,
    required this.initialSelected,
    required this.onChanged,
  });

  @override
  State<CategoryTagsSelector> createState() => _CategoryTagsSelectorState();
}

class _CategoryTagsSelectorState extends State<CategoryTagsSelector> {
  static const int _maxSelected = CategoryTagsService.maxSelectedTags;
  static const _kPurple = Color(0xFF6366F1);
  static const _kPurpleSoft = Color(0xFFF0F0FF);

  late Set<String> _selected;
  List<CategoryTag>? _catalog;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initialSelected);
    _load();
  }

  @override
  void didUpdateWidget(CategoryTagsSelector old) {
    super.didUpdateWidget(old);
    if (old.category != widget.category) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list =
        await CategoryTagsService.instance.loadFor(widget.category);
    if (!mounted) return;
    setState(() {
      _catalog = list;
      _loading = false;
      // Drop any selections that are no longer in the catalog (e.g. if the
      // provider changed category) so we never write orphan IDs.
      final validIds = list.map((t) => t.id).toSet();
      _selected = _selected.where(validIds.contains).toSet();
    });
    widget.onChanged(_selected);
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        if (_selected.length >= _maxSelected) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ניתן לבחור עד $_maxSelected תגים לקטגוריה'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }
        _selected.add(id);
      }
    });
    widget.onChanged(_selected);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: _kPurple),
            ),
            SizedBox(width: 10),
            Text('טוען תגים…',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          ],
        ),
      );
    }
    final catalog = _catalog ?? const [];
    if (catalog.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _kPurpleSoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome_rounded,
                      size: 12, color: _kPurple),
                  SizedBox(width: 4),
                  Text(
                    'תגים לקטגוריה שלך',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _kPurple,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Text(
              'נבחרו ${_selected.length}/$_maxSelected',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: catalog.map(_buildChip).toList(),
        ),
      ],
    );
  }

  Widget _buildChip(CategoryTag tag) {
    final selected = _selected.contains(tag.id);
    return AnimatedScale(
      scale: selected ? 1.02 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: Material(
        color: selected ? _kPurple : Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _toggle(tag.id),
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? _kPurple : const Color(0xFFE5E7EB),
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  tag.icon,
                  size: 15,
                  color: selected ? Colors.white : _kPurple,
                ),
                const SizedBox(width: 6),
                Text(
                  tag.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? Colors.white
                        : const Color(0xFF1A1A2E),
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.check_rounded,
                      size: 14, color: Colors.white),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
