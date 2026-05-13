import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// A small rounded rectangle that displays a keyboard key or
/// key-combination — used in the footer hint strip + command palette.
///
/// Supports multiple keys via [keys]: each key renders in its own
/// pill, with a thin gap (no `+` glyph — cleaner at small sizes).
///
/// Typical usage:
/// ```dart
/// BannerKbd(keys: ['⌘', 'K'])
/// BannerKbd(keys: ['C'])
/// BannerKbd(keys: ['/'], density: BannerKbdDensity.compact)
/// ```
enum BannerKbdDensity { normal, compact }

class BannerKbd extends StatelessWidget {
  const BannerKbd({
    super.key,
    required this.keys,
    this.density = BannerKbdDensity.normal,
  });

  final List<String> keys;
  final BannerKbdDensity density;

  @override
  Widget build(BuildContext context) {
    // Guard against the degenerate empty-list case — without this, a
    // const BannerKbd(keys: []) would render an invisible 0-width Row
    // that still consumes surrounding Wrap spacing and looks like a
    // silent layout bug.
    if (keys.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          _KbdPill(label: keys[i], density: density),
          if (i < keys.length - 1) const SizedBox(width: 3),
        ],
      ],
    );
  }
}

class _KbdPill extends StatelessWidget {
  const _KbdPill({required this.label, required this.density});

  final String label;
  final BannerKbdDensity density;

  @override
  Widget build(BuildContext context) {
    final compact = density == BannerKbdDensity.compact;
    final h = compact ? 16.0 : 18.0;
    final minW = compact ? 16.0 : 20.0;
    final fs = compact ? 10.5 : 11.0;

    return Container(
      constraints: BoxConstraints(minWidth: minW),
      height: h,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        border: Border.all(color: BannersTokens.line2, width: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: fs,
          fontFamily: 'monospace',
          color: BannersTokens.ink2,
          height: 1.0,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
