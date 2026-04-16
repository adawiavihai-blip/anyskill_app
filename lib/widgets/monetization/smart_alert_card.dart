import 'package:flutter/material.dart';
import 'design_tokens.dart';

enum MonetizationAlertType { anomaly, churn, growth }

/// A single alert card for section 4. Three color variants map to the three
/// alert types — anomaly (red), churn (pink), growth (green).
class SmartAlertCard extends StatelessWidget {
  const SmartAlertCard({
    super.key,
    required this.type,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.icon,
  });

  final MonetizationAlertType type;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final IconData? icon;

  _AlertPalette get _p => switch (type) {
        MonetizationAlertType.anomaly => const _AlertPalette(
            border: MonetizationTokens.dangerBorder,
            bg: MonetizationTokens.dangerLight,
            iconStroke: MonetizationTokens.dangerDeep,
            title: MonetizationTokens.dangerText,
            button: MonetizationTokens.dangerText,
          ),
        MonetizationAlertType.churn => const _AlertPalette(
            border: MonetizationTokens.churnBorder,
            bg: MonetizationTokens.churnLight,
            iconStroke: MonetizationTokens.churnDeep,
            title: MonetizationTokens.churnText,
            button: MonetizationTokens.churnText,
          ),
        MonetizationAlertType.growth => const _AlertPalette(
            border: MonetizationTokens.successBorder,
            bg: MonetizationTokens.successLight,
            iconStroke: MonetizationTokens.successText,
            title: MonetizationTokens.successText,
            button: MonetizationTokens.successText,
          ),
      };

  IconData get _defaultIcon => switch (type) {
        MonetizationAlertType.anomaly => Icons.warning_amber_rounded,
        MonetizationAlertType.churn   => Icons.notifications_active_outlined,
        MonetizationAlertType.growth  => Icons.trending_up_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final palette = _p;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: MonetizationTokens.cardDecoration(borderColor: palette.border),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: palette.bg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon ?? _defaultIcon,
                size: 14, color: palette.iconStroke),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: palette.title,
                    )),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 11,
                    color: MonetizationTokens.textSecondary,
                    height: 1.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onAction,
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.button,
              side: BorderSide(color: palette.border, width: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            child: Text(actionLabel,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _AlertPalette {
  final Color border;
  final Color bg;
  final Color iconStroke;
  final Color title;
  final Color button;
  const _AlertPalette({
    required this.border,
    required this.bg,
    required this.iconStroke,
    required this.title,
    required this.button,
  });
}
