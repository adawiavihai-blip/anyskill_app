/// Inline stat blocks separated by a 0.5px vertical divider.
/// Used in mockups 07 (XP + rating), 09 (rating + count + tenure), and 10
/// (the home banner footer with 3 mini-stats).
library;

import 'package:flutter/material.dart';

import '../../theme/community_theme.dart';

/// One stat (value + label) — pair multiple inside a [CommunityStatRow].
class CommunityStatBlock extends StatelessWidget {
  const CommunityStatBlock({
    super.key,
    required this.value,
    required this.label,
    this.valueColor = CommunityColors.textPrimary,
    this.valueIcon,
    this.valueIconColor,
  });

  final String value;
  final String label;
  final Color valueColor;

  /// Optional small leading icon (e.g., a star next to a "4.9" rating).
  final IconData? valueIcon;
  final Color? valueIconColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (valueIcon != null) ...[
              Icon(
                valueIcon,
                size: 13,
                color: valueIconColor ?? CommunityColors.starGold,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
                color: valueColor,
                fontFamily: CommunityType.fontFamily,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: CommunityColors.textTertiary,
            fontFamily: CommunityType.fontFamily,
          ),
        ),
      ],
    );
  }
}

/// Horizontal row of [CommunityStatBlock] separated by 0.5px vertical
/// dividers — matches the `.divider` class in `_shared.css`.
class CommunityStatRow extends StatelessWidget {
  const CommunityStatRow({
    super.key,
    required this.children,
    this.gap = 14,
    this.padding = const EdgeInsets.symmetric(vertical: 14),
    this.withTopBorder = true,
    this.withBottomBorder = true,
  });

  final List<CommunityStatBlock> children;
  final double gap;
  final EdgeInsetsGeometry padding;
  final bool withTopBorder;
  final bool withBottomBorder;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i < children.length - 1) {
        items.add(SizedBox(width: gap));
        items.add(_VerticalDivider(height: 32));
        items.add(SizedBox(width: gap));
      }
    }

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        border: Border(
          top: withTopBorder
              ? const BorderSide(
                  color: CommunityColors.borderSubtle, width: 0.5)
              : BorderSide.none,
          bottom: withBottomBorder
              ? const BorderSide(
                  color: CommunityColors.borderSubtle, width: 0.5)
              : BorderSide.none,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: items,
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 0.5,
      height: height,
      color: CommunityColors.borderSubtle,
    );
  }
}
