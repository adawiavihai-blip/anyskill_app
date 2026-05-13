import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// 10-emoji picker for Section 2 (Design) of the banner edit screen.
///
/// Each cell is a 1:1 square. Selected cell has the dark `ink` background
/// + dark border. Pass `null` to clear the selection.
class StudioIconEmojiPicker extends StatelessWidget {
  const StudioIconEmojiPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  /// Currently-selected emoji, or null if no emoji is set.
  final String? selected;

  /// Called with the new emoji when a cell is tapped (re-tapping the
  /// selected cell clears it — passes null).
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 10,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final emoji in studioBannerEmojis)
          _Cell(
            emoji: emoji,
            selected: emoji == selected,
            onTap: () => onChanged(emoji == selected ? null : emoji),
          ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(StudioRadius.xs),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: selected ? StudioColors.ink : StudioColors.bgSubtle,
          borderRadius: BorderRadius.circular(StudioRadius.xs),
          border: Border.all(
            color: selected ? StudioColors.ink : Colors.transparent,
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          emoji,
          style: const TextStyle(fontSize: 18, height: 1),
        ),
      ),
    );
  }
}

/// Hand-picked emoji set for banners. Keep at exactly 10 — the picker
/// renders in a fixed 10-col grid (single row at typical card width).
const List<String> studioBannerEmojis = [
  '⭐',
  '🔥',
  '🎁',
  '🚀',
  '💡',
  '📣',
  '🎯',
  '💎',
  '🛠️',
  '🌟',
];
