/// Primary CTA button — black pill, full width by default.
///
/// Per `_shared.css .btn-primary` and DESIGN_SYSTEM.md §components.
/// Use one (and only one) per screen — this is the dominant action.
library;

import 'package:flutter/material.dart';

import '../../theme/community_theme.dart';

class CommunityPrimaryButton extends StatelessWidget {
  const CommunityPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.fullWidth = true,
    this.icon,
    this.isLoading = false,
    this.padding = const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
  });

  final String label;
  final VoidCallback? onPressed;
  final bool fullWidth;

  /// Optional leading icon (rendered before the label, RTL-aware via
  /// [Row]'s default reading direction).
  final IconData? icon;

  /// When `true`, replaces the label with a small white spinner and
  /// disables the press handler.
  final bool isLoading;

  /// Override the default vertical/horizontal padding.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null && !isLoading;

    final content = isLoading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor:
                  AlwaysStoppedAnimation<Color>(CommunityColors.primaryWhite),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: CommunityColors.primaryWhite),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                  color: CommunityColors.primaryWhite,
                  fontFamily: CommunityType.fontFamily,
                ),
              ),
            ],
          );

    final button = ElevatedButton(
      onPressed: isEnabled ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: CommunityColors.primaryBlack,
        disabledBackgroundColor:
            CommunityColors.primaryBlack.withValues(alpha: 0.4),
        foregroundColor: CommunityColors.primaryWhite,
        elevation: 0,
        shadowColor: Colors.transparent,
        padding: padding,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(CommunityRadius.pill),
        ),
        minimumSize: Size(fullWidth ? double.infinity : 0, 48),
      ),
      child: content,
    );

    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}
