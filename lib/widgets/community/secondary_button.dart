/// Secondary CTA button — white pill with a 0.5px border.
///
/// Per `_shared.css .btn-secondary`. Pairs with [CommunityPrimaryButton]
/// in cancel/secondary roles (mockups 04, 05, 06, 08).
library;

import 'package:flutter/material.dart';

import '../../theme/community_theme.dart';

class CommunitySecondaryButton extends StatelessWidget {
  const CommunitySecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.fullWidth = false,
    this.icon,
    this.padding = const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
  });

  final String label;
  final VoidCallback? onPressed;
  final bool fullWidth;
  final IconData? icon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: CommunityColors.textPrimary),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.1,
            color: CommunityColors.textPrimary,
            fontFamily: CommunityType.fontFamily,
          ),
        ),
      ],
    );

    final button = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: CommunityColors.primaryWhite,
        foregroundColor: CommunityColors.textPrimary,
        side: const BorderSide(
          color: Color(0x1F000000), // ~12% per spec
          width: 0.5,
        ),
        padding: padding,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(CommunityRadius.pill),
        ),
        minimumSize: Size(fullWidth ? double.infinity : 0, 44),
      ),
      child: content,
    );

    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}
