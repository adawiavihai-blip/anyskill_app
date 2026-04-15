/// AnySkill — Provider Category Tags Display
///
/// Read-only chip row for rendering the provider's selected category
/// tags on search cards and the public profile. Complements the
/// existing `quickTags` row — this widget ONLY renders category-specific
/// tags from `users/{uid}.categoryTags` + the category catalog.
///
/// On cards: `maxVisible: 3` with an "+N עוד" overflow pill.
/// On profile: `maxVisible: null` shows everything.
library;

import 'package:flutter/material.dart';

import '../models/category_tag.dart';
import '../services/category_tags_service.dart';

class ProviderCategoryTagsDisplay extends StatefulWidget {
  final String category;
  final List<String> tagIds;
  final int? maxVisible;
  final bool compact;

  const ProviderCategoryTagsDisplay({
    super.key,
    required this.category,
    required this.tagIds,
    this.maxVisible = 3,
    this.compact = true,
  });

  @override
  State<ProviderCategoryTagsDisplay> createState() =>
      _ProviderCategoryTagsDisplayState();
}

class _ProviderCategoryTagsDisplayState
    extends State<ProviderCategoryTagsDisplay> {
  static const _kPurple = Color(0xFF6366F1);
  static const _kPurpleSoft = Color(0xFFF0F0FF);

  List<CategoryTag>? _catalog;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ProviderCategoryTagsDisplay old) {
    super.didUpdateWidget(old);
    if (old.category != widget.category) _load();
  }

  Future<void> _load() async {
    final list =
        await CategoryTagsService.instance.loadFor(widget.category);
    if (!mounted) return;
    setState(() => _catalog = list);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tagIds.isEmpty) return const SizedBox.shrink();
    final catalog = _catalog;
    if (catalog == null) return const SizedBox.shrink();
    final byId = {for (final t in catalog) t.id: t};
    final resolved = widget.tagIds
        .map((id) => byId[id])
        .whereType<CategoryTag>()
        .toList();
    if (resolved.isEmpty) return const SizedBox.shrink();

    final limit = widget.maxVisible;
    final showAll = _expanded || limit == null;
    final visible = showAll ? resolved : resolved.take(limit).toList();
    final overflow = resolved.length - visible.length;

    final spacing = widget.compact ? 6.0 : 8.0;
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        ...visible.map(_buildChip),
        if (overflow > 0) _buildMoreChip(overflow),
      ],
    );
  }

  Widget _buildChip(CategoryTag tag) {
    final fontSize = widget.compact ? 11.0 : 12.0;
    final iconSize = widget.compact ? 12.0 : 14.0;
    final padH = widget.compact ? 8.0 : 10.0;
    final padV = widget.compact ? 4.0 : 6.0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: BoxDecoration(
        color: _kPurpleSoft,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: _kPurple.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tag.icon, size: iconSize, color: _kPurple),
          const SizedBox(width: 4),
          Text(
            tag.label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: _kPurple,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoreChip(int n) {
    final fontSize = widget.compact ? 11.0 : 12.0;
    final padH = widget.compact ? 8.0 : 10.0;
    final padV = widget.compact ? 4.0 : 6.0;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => _expanded = true),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFCBD5E1), width: 1),
        ),
        child: Text(
          '+$n עוד',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF475569),
          ),
        ),
      ),
    );
  }
}
