/// Filter / category pill — used in the horizontal filter rows in mockups
/// 01 ("הכל / קרוב אליי / קשישים …"), 08 (category picker), 14 (popular
/// searches), and the chat-input quick replies.
///
/// Per `_shared.css .pill` and `.pill-active`.
library;

import 'package:flutter/material.dart';

import '../../theme/community_theme.dart';

class CommunityPillChip extends StatelessWidget {
  const CommunityPillChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.dense = false,
    this.leadingIcon,
    this.trailingIcon,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Tighter horizontal padding — used when many pills are squeezed in
  /// (e.g., the 7-day streak grid in mockup 17).
  final bool dense;

  final IconData? leadingIcon;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? CommunityColors.primaryWhite
        : CommunityColors.textSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(CommunityRadius.pill),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 10 : 12,
          vertical: dense ? 5 : 6,
        ),
        decoration: BoxDecoration(
          color: selected ? CommunityColors.primaryBlack : Colors.transparent,
          border: selected
              ? null
              : Border.all(
                  color: const Color(0x1F000000), // ~12%
                  width: 0.5,
                ),
          borderRadius: const BorderRadius.all(CommunityRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingIcon != null) ...[
              Icon(leadingIcon, size: 12, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: fg,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                letterSpacing: -0.1,
                fontFamily: CommunityType.fontFamily,
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 6),
              Icon(trailingIcon, size: 9, color: fg),
            ],
          ],
        ),
      ),
    );
  }
}
