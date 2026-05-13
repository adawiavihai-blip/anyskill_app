import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// 8-swatch gradient picker for Section 2 (Design) of the banner edit screen.
///
/// Each swatch is a 1:1 rounded rectangle showing the gradient. Selected
/// swatch has an `ink` border + 1.05x scale + a centered check overlay.
///
/// The 8 presets match the mockup `.banner-thumb.gradient-N` styles
/// ([banners-mockup-v3.html:241-249](docs/ui-specs/Baner/banners-mockup-v3.html))
/// — the same colours used in the Phase-1 table thumbs, so picking a
/// swatch here makes the table row visually identical instantly.
class StudioGradientPicker extends StatelessWidget {
  const StudioGradientPicker({
    super.key,
    required this.color1,
    required this.color2,
    required this.onChanged,
  });

  /// Currently-selected start colour as a 6-char hex (no `#`).
  final String color1;
  final String color2;

  /// Called with `(c1, c2)` (hex strings, no `#`) when a swatch is tapped.
  final void Function(String color1, String color2) onChanged;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 8,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final preset in studioGradientPresets)
          _Swatch(
            preset: preset,
            selected: preset.color1.toLowerCase() == color1.toLowerCase() &&
                preset.color2.toLowerCase() == color2.toLowerCase(),
            onTap: () => onChanged(preset.color1, preset.color2),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.preset,
    required this.selected,
    required this.onTap,
  });
  final StudioGradientPreset preset;
  final bool selected;
  final VoidCallback onTap;

  Color _hex(String hex) {
    final h = hex.replaceAll('#', '');
    final v = int.tryParse(h, radix: 16);
    if (v == null) return StudioColors.ink5;
    if (h.length == 6) return Color(0xFF000000 | v);
    return Color(v);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(StudioRadius.sm),
      onTap: onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 150),
        scale: selected ? 1.05 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [_hex(preset.color1), _hex(preset.color2)],
            ),
            borderRadius: BorderRadius.circular(StudioRadius.sm),
            border: Border.all(
              color: selected ? StudioColors.ink : Colors.transparent,
              width: 2,
            ),
          ),
          child: selected
              ? const Center(
                  child: Icon(Icons.check_rounded,
                      size: 18, color: Colors.white),
                )
              : null,
        ),
      ),
    );
  }
}

/// One preset gradient (start + end hex, no `#`).
class StudioGradientPreset {
  final String label;
  final String color1;
  final String color2;
  const StudioGradientPreset({
    required this.label,
    required this.color1,
    required this.color2,
  });
}

/// 8 hand-picked presets.
const List<StudioGradientPreset> studioGradientPresets = [
  StudioGradientPreset(label: 'Indigo', color1: '6B4FA8', color2: '4A3580'),
  StudioGradientPreset(label: 'Forest', color1: '1A6B5B', color2: '2A8F77'),
  StudioGradientPreset(label: 'Plum', color1: '4A2A6E', color2: '6B3A8F'),
  StudioGradientPreset(label: 'Sunset', color1: 'B85A2A', color2: 'D67A3A'),
  StudioGradientPreset(label: 'Ocean', color1: '2C5BA8', color2: '4A7BCF'),
  StudioGradientPreset(label: 'Rose', color1: 'B83A2A', color2: 'D9614F'),
  StudioGradientPreset(label: 'Slate', color1: '3A3A38', color2: '6B6B68'),
  StudioGradientPreset(label: 'Gold', color1: 'B89855', color2: '8C6F36'),
];
