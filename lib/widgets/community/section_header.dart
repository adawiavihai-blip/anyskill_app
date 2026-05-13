/// Two row-types used everywhere in the community module:
///
/// - [CommunitySectionLabel] — the tiny tertiary uppercase line
///   ("המומלצים החודש", "החודש האחרון", "9 השבועות האחרונים").
/// - [CommunitySectionHeader] — full row with a bold title on one side
///   and an optional "הצג הכל" trailing link.
library;

import 'package:flutter/material.dart';

import '../../theme/community_theme.dart';

/// Tiny tertiary-color label — used as a vertical separator between
/// content blocks (mockups 01, 07, 12, 14, 17). Always +0.2 letter-spacing
/// — that's the design system's rule for tiny captions.
class CommunitySectionLabel extends StatelessWidget {
  const CommunitySectionLabel(
    this.text, {
    super.key,
    this.padding = EdgeInsets.zero,
  });

  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
          color: CommunityColors.textTertiary,
          fontFamily: CommunityType.fontFamily,
        ),
      ),
    );
  }
}

/// Bigger section header — bold title + optional trailing link.
/// Mockup 01: "המומלצים החודש" with "הצג הכל" on the trailing edge.
class CommunitySectionHeader extends StatelessWidget {
  const CommunitySectionHeader({
    super.key,
    required this.title,
    this.trailingLabel,
    this.onTrailingTap,
    this.padding = EdgeInsets.zero,
  });

  final String title;

  /// Optional "הצג הכל" / "ערוך" trailing link.
  final String? trailingLabel;
  final VoidCallback? onTrailingTap;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: CommunityColors.textPrimary,
                fontFamily: CommunityType.fontFamily,
              ),
            ),
          ),
          if (trailingLabel != null)
            InkWell(
              onTap: onTrailingTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 2),
                child: Text(
                  trailingLabel!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: CommunityColors.textTertiary,
                    fontFamily: CommunityType.fontFamily,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
