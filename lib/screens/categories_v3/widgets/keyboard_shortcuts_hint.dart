import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Dismissable strip listing the active keyboard shortcuts. Per spec §7.1
/// row 4 — appears once per session, can be dismissed forever.
///
/// Mobile: hidden entirely (shortcuts don't apply on touch).
class KeyboardShortcutsHint extends StatelessWidget {
  const KeyboardShortcutsHint({
    super.key,
    required this.dismissed,
    required this.onDismiss,
  });

  final bool dismissed;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    if (dismissed) return const SizedBox.shrink();
    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (isMobile) return const SizedBox.shrink();

    final entries = <_ShortcutEntry>[
      _ShortcutEntry('↑↓', 'נווט'),
      _ShortcutEntry('Space', 'בחר'),
      _ShortcutEntry('E', 'ערוך'),
      _ShortcutEntry('H', 'הסתר'),
      _ShortcutEntry('P', 'קדם'),
      _ShortcutEntry('Del', 'מחק'),
      _ShortcutEntry('⌘K', 'פלטה'),
      _ShortcutEntry('⌘Z', 'בטל'),
      _ShortcutEntry('Esc', 'ניקוי'),
      _ShortcutEntry('/', 'חיפוש'),
    ];

    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 12),
      padding:
          const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          const Icon(Icons.keyboard_alt_outlined,
              size: 14, color: Color(0xFF6B7280)),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final e in entries) _ChipPair(entry: e),
              ],
            ),
          ),
          InkWell(
            onTap: onDismiss,
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsetsDirectional.all(4),
              child: Icon(Icons.close_rounded,
                  size: 14, color: Color(0xFF6B7280)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutEntry {
  const _ShortcutEntry(this.key, this.label);
  final String key;
  final String label;
}

class _ChipPair extends StatelessWidget {
  const _ChipPair({required this.entry});
  final _ShortcutEntry entry;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding:
              const EdgeInsetsDirectional.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.black.withValues(alpha: 0.18)),
          ),
          child: Text(
            entry.key,
            style: const TextStyle(
              fontSize: 10.5,
              fontFamily: 'monospace',
              color: Color(0xFF1A1A2E),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          entry.label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF6B7280),
          ),
        ),
      ],
    );
  }
}
