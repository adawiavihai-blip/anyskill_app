// ignore_for_file: unused_element
//
// ⚠️  DEV-ONLY gallery for the v15.x admin-banners design system.
//
// This file exists purely for Phase-3 visual review and is NOT wired
// into any production route. Open it temporarily by pushing
// [BannersWidgetsGallery] from a debug menu:
//
//   Navigator.push(
//     context,
//     MaterialPageRoute(
//       builder: (_) => const BannersWidgetsGallery(),
//     ),
//   );
//
// Delete this file (or move it under a `test/` folder) once the
// system-wide Phase-4 integration lands.

import 'package:flutter/material.dart';

import 'banner_chip.dart';
import 'banner_kbd.dart';
import 'banner_metric_card.dart';
import 'banner_sparkline.dart';
import 'banner_toggle.dart';
import 'design_tokens.dart';

class BannersWidgetsGallery extends StatefulWidget {
  const BannersWidgetsGallery({super.key});

  @override
  State<BannersWidgetsGallery> createState() => _BannersWidgetsGalleryState();
}

class _BannersWidgetsGalleryState extends State<BannersWidgetsGallery> {
  // Fake state so the gallery demonstrates the interactive widgets
  // (toggle, hover, etc.) without needing Firestore.
  bool _toggleA = true;
  bool _toggleB = false;
  bool _sparklineHover = false;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: BannersTokens.bg,
        appBar: AppBar(
          title: const Text('Banners Widgets — Dev Gallery'),
          backgroundColor: BannersTokens.surface,
          foregroundColor: BannersTokens.ink,
          elevation: 0,
          shape: const Border(
            bottom: BorderSide(color: BannersTokens.line, width: 0.5),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(BannersTokens.spaceXl),
          children: [
            // ── KPI strip (4 metric cards in one group) ──────────────
            _Section(
              title: '1 · BannerMetricStrip — 4 KPIs',
              child: BannerMetricStrip(
                cards: [
                  BannerMetricCard(
                    label: 'חשיפות · 7 ימים',
                    valueText: '48,219',
                    trendPercent: 12.4,
                    trailing: BannerSparkline(
                      values: const [3, 5, 4, 6, 5, 7, 8, 9, 8, 10, 9, 11],
                      color: BannersTokens.ink3,
                    ),
                  ),
                  BannerMetricCard(
                    label: 'הקלקות',
                    valueText: '3,104',
                    trendPercent: 6.1,
                    trailing: BannerSparkline(
                      values: const [10, 9, 11, 10, 12, 11, 13, 12, 14, 13, 15],
                      color: BannersTokens.ink3,
                    ),
                  ),
                  BannerMetricCard(
                    label: 'CTR',
                    valueText: '6.44%',
                    trendPercent: -0.3,
                    trailing: BannerSparkline(
                      values: const [7, 6, 8, 5, 6, 7, 5, 6, 5, 7, 6, 5],
                      color: BannersTokens.danger,
                    ),
                  ),
                  BannerMetricCard(
                    label: 'הכנסה מיוחסת',
                    valueText: '₪47.3K',
                    trendPercent: 18.2,
                    accent: true,
                    trailing: BannerSparkline(
                      values: const [2, 4, 3, 6, 5, 8, 7, 10, 9, 12, 11, 14],
                      color: BannersTokens.accent,
                    ),
                  ),
                ],
              ),
            ),

            // ── Sparklines in every degenerate state ─────────────────
            _Section(
              title: '2 · BannerSparkline — edge cases',
              child: BannersCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LabeledRow(
                      label: '0 points (empty)',
                      child: BannerSparkline(values: const []),
                    ),
                    _LabeledRow(
                      label: '1 point (dot)',
                      child: BannerSparkline(values: const [5]),
                    ),
                    _LabeledRow(
                      label: '2+ points (line, 1.2px)',
                      child: BannerSparkline(
                        values: const [3, 5, 4, 6, 5, 8, 7, 10],
                        color: BannersTokens.accent,
                      ),
                    ),
                    _LabeledRow(
                      label: 'hovered (2px stroke) — tap to toggle',
                      child: GestureDetector(
                        onTap: () => setState(
                            () => _sparklineHover = !_sparklineHover),
                        child: BannerSparkline(
                          values: const [3, 5, 4, 6, 5, 8, 7, 10],
                          color: BannersTokens.accent,
                          isHovered: _sparklineHover,
                        ),
                      ),
                    ),
                    _LabeledRow(
                      label: 'flat input (all 5s)',
                      child: BannerSparkline(
                        values: const [5, 5, 5, 5, 5],
                        color: BannersTokens.ink3,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── BannerChip variants ─────────────────────────────────
            _Section(
              title: '3 · BannerChip — 6 variants × dot/icon combos',
              child: BannersCard(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 10,
                  children: const [
                    BannerChip(
                      label: 'פעיל עכשיו',
                      variant: BannerChipVariant.success,
                      hasDot: true,
                    ),
                    BannerChip(
                      label: 'מתוזמן',
                      variant: BannerChipVariant.warn,
                    ),
                    BannerChip(
                      label: 'טיוטה',
                      variant: BannerChipVariant.draft,
                    ),
                    BannerChip(
                      label: 'הסתיים',
                      variant: BannerChipVariant.danger,
                    ),
                    BannerChip(
                      label: 'AI · Gemini',
                      variant: BannerChipVariant.accent,
                      icon: Icons.auto_awesome_rounded,
                    ),
                    BannerChip(
                      label: 'קרוסלה',
                      variant: BannerChipVariant.neutral,
                    ),
                    BannerChip(
                      label: 'ארנק',
                      variant: BannerChipVariant.neutral,
                    ),
                    BannerChip(
                      label: 'dense · 16px',
                      variant: BannerChipVariant.neutral,
                      dense: true,
                    ),
                    BannerChip(
                      label: 'A/B',
                      variant: BannerChipVariant.accent,
                      dense: true,
                    ),
                  ],
                ),
              ),
            ),

            // ── BannerToggle — optimistic update playground ──────────
            _Section(
              title: '4 · BannerToggle — optimistic updates',
              child: BannersCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LabeledRow(
                      label: 'Fast success (200ms)',
                      child: BannerToggle(
                        value: _toggleA,
                        onChanged: (next) async {
                          await Future<void>.delayed(
                              const Duration(milliseconds: 200));
                          if (mounted) setState(() => _toggleA = next);
                        },
                      ),
                    ),
                    _LabeledRow(
                      label: 'Slow success (1.5s)',
                      child: BannerToggle(
                        value: _toggleB,
                        onChanged: (next) async {
                          await Future<void>.delayed(
                              const Duration(milliseconds: 1500));
                          if (mounted) setState(() => _toggleB = next);
                        },
                      ),
                    ),
                    _LabeledRow(
                      label: 'Always fails (rolls back + SnackBar)',
                      child: BannerToggle(
                        value: false,
                        onChanged: (_) async {
                          await Future<void>.delayed(
                              const Duration(milliseconds: 400));
                          throw Exception('שגיאה מדומה');
                        },
                      ),
                    ),
                    _LabeledRow(
                      label: 'Disabled',
                      child: BannerToggle(
                        value: true,
                        enabled: false,
                        onChanged: (_) async {},
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── BannerKbd — keyboard shortcut pills ──────────────────
            _Section(
              title: '5 · BannerKbd — shortcut pills',
              child: BannersCard(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: const [
                    BannerKbd(keys: ['C']),
                    BannerKbd(keys: ['/']),
                    BannerKbd(keys: ['⌘', 'K']),
                    BannerKbd(keys: ['G', 'A']),
                    BannerKbd(keys: ['E']),
                    BannerKbd(keys: ['?']),
                    BannerKbd(
                      keys: ['⌘', 'Shift', 'P'],
                      density: BannerKbdDensity.compact,
                    ),
                  ],
                ),
              ),
            ),

            // ── Palette swatches (quick eyeball) ─────────────────────
            _Section(
              title: '6 · Palette swatches',
              child: BannersCard(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    _Swatch('accent', BannersTokens.accent),
                    _Swatch('accentInk', BannersTokens.accentInk),
                    _Swatch('accentWash', BannersTokens.accentWash),
                    _Swatch('success', BannersTokens.success),
                    _Swatch('successWash', BannersTokens.successWash),
                    _Swatch('warn', BannersTokens.warn),
                    _Swatch('warnWash', BannersTokens.warnWash),
                    _Swatch('danger', BannersTokens.danger),
                    _Swatch('ink', BannersTokens.ink),
                    _Swatch('ink2', BannersTokens.ink2),
                    _Swatch('ink3', BannersTokens.ink3),
                    _Swatch('ink4', BannersTokens.ink4),
                    _Swatch('bg', BannersTokens.bg),
                    _Swatch('surface', BannersTokens.surface),
                  ],
                ),
              ),
            ),

            const SizedBox(height: BannersTokens.spaceXxl),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
//  Gallery-only helper widgets
// ─────────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BannersTokens.spaceXxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: BannersTokens.h2),
          const SizedBox(height: BannersTokens.spaceMd),
          child,
        ],
      ),
    );
  }
}

class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 240,
            child: Text(label, style: BannersTokens.bodyMuted),
          ),
          const SizedBox(width: BannersTokens.spaceMd),
          child,
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.name, this.color);
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: BannersTokens.line, width: 0.5),
        borderRadius: BorderRadius.circular(BannersTokens.radiusSm),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: BannersTokens.line2, width: 0.5),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name, style: BannersTokens.captionSm),
          ),
        ],
      ),
    );
  }
}
