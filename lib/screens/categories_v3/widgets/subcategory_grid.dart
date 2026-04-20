import 'package:flutter/material.dart';

import '../models/category_v3_model.dart';
import 'subcategory_thumb.dart';

/// Inline expanded panel showing a category's sub-categories. Per spec §7.4
/// the background is a soft tertiary tint, the grid is auto-fill 110px min.
class SubcategoryGrid extends StatelessWidget {
  const SubcategoryGrid({
    super.key,
    required this.parentId,
    required this.subcategories,
    this.onTapSub,
    this.onEditSub,
    this.onAdd,
  });

  final String parentId;
  final List<CategoryV3Model> subcategories;
  final void Function(CategoryV3Model)? onTapSub;
  final void Function(CategoryV3Model)? onEditSub;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: subcategories.isEmpty && onAdd == null
          ? _emptyState()
          : LayoutBuilder(builder: (context, c) {
              // 110px minimum per spec — compute cols dynamically
              final cols = (c.maxWidth / 118).floor().clamp(2, 8);
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.78,
                ),
                itemCount: subcategories.length + (onAdd != null ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == subcategories.length) {
                    return AddSubcategoryThumb(onTap: onAdd!);
                  }
                  final sub = subcategories[i];
                  return SubcategoryThumb(
                    sub: sub,
                    onTap: onTapSub == null ? null : () => onTapSub!(sub),
                    onEdit:
                        onEditSub == null ? null : () => onEditSub!(sub),
                  );
                },
              );
            }),
    );
  }

  Widget _emptyState() {
    return const Padding(
      padding: EdgeInsetsDirectional.symmetric(vertical: 18),
      child: Center(
        child: Text(
          'אין תתי-קטגוריות עדיין',
          style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
        ),
      ),
    );
  }
}
