import 'package:flutter/material.dart';

import '../../../models/banner_model.dart';
import 'design_tokens.dart';

/// One row in the banners table on Screen A.
///
/// Mockup spec ([banners-mockup-v3.html:228-281, 1080-1102](docs/ui-specs/Baner/banners-mockup-v3.html)):
/// 9 columns: checkbox · banner thumb+title · placement chip · status
/// (toggle + label) · impressions · clicks · CTR (with mini bar) · revenue
/// · row-actions (only on hover).
///
/// **Phase 1 wires real data**:
///   - thumb: rendered from gradient `color1`/`color2` for gradient
///     banners, or `imageUrl` for image banners (defers actual image
///     loading until Phase 2 — Phase 1 always shows the gradient fallback).
///   - placement chip: 4 colored variants matching the 4 placements.
///   - toggle: hits `BannersService.setActive` immediately.
///   - status label: derived from `BannerStatus`.
///   - impressions/clicks/CTR/revenue: from `BannerModel` fields directly.
///   - row-actions ⎘ (duplicate) and ⋯ (more): hooked via callbacks.
///   - tap-on-row: callback (Phase 1 shows snackbar; Phase 2 opens edit).
class StudioBannerTableRow extends StatefulWidget {
  const StudioBannerTableRow({
    super.key,
    required this.banner,
    required this.selected,
    required this.onToggleSelect,
    required this.onTap,
    required this.onToggleActive,
    required this.onDuplicate,
    required this.onMore,
    this.dense = false,
  });

  final BannerModel banner;
  final bool selected;
  final ValueChanged<bool> onToggleSelect;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggleActive;
  final VoidCallback onDuplicate;
  final VoidCallback onMore;
  final bool dense;

  @override
  State<StudioBannerTableRow> createState() => _StudioBannerTableRowState();
}

class _StudioBannerTableRowState extends State<StudioBannerTableRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final b = widget.banner;
    final active = b.isActive;
    final status = b.status;
    final hasMetrics = b.impressions > 0 || b.clicks > 0;

    final rowBg = widget.selected
        ? StudioColors.bgTonal
        : (_hover ? StudioColors.bgSubtle : StudioColors.bgElevated);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: StudioSpacing.s5,
            vertical: widget.dense ? StudioSpacing.s2 : StudioSpacing.s3,
          ),
          decoration: BoxDecoration(
            color: rowBg,
            border: Border(
              bottom: BorderSide(color: StudioColors.line),
            ),
          ),
          child: Row(
            children: [
              // ── Checkbox (36) ─────────────────────────────────────
              SizedBox(
                width: 36,
                child: GestureDetector(
                  onTap: () => widget.onToggleSelect(!widget.selected),
                  child: _Check(checked: widget.selected),
                ),
              ),

              // ── Banner cell (flex 1.5) ────────────────────────────
              Expanded(
                flex: 30,
                child: Row(
                  children: [
                    _Thumb(banner: b),
                    const SizedBox(width: StudioSpacing.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.title.isEmpty ? '(ללא כותרת)' : b.title,
                            style: StudioText.bodyMedium(
                                color: StudioColors.ink),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.rtl,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _meta(b),
                            style: StudioText.captionSm(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.rtl,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Placement chip (90) ───────────────────────────────
              SizedBox(
                width: 90,
                child: _PlacementChip(type: b.type),
              ),

              // ── Status (120) ──────────────────────────────────────
              SizedBox(
                width: 120,
                child: Row(
                  children: [
                    _Toggle(
                      on: active,
                      onChanged: widget.onToggleActive,
                    ),
                    const SizedBox(width: StudioSpacing.s2),
                    Flexible(
                      child: Text(
                        status.hebrewLabel,
                        style: StudioText.body(
                          color: _statusColor(status),
                        ).copyWith(fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.rtl,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Impressions (100) ─────────────────────────────────
              SizedBox(
                width: 100,
                child: _MetricCell(
                  value: hasMetrics ? _compact(b.impressions) : '—',
                  sub: hasMetrics ? '7 ימים' : null,
                ),
              ),

              // ── Clicks (100) ──────────────────────────────────────
              SizedBox(
                width: 100,
                child: _MetricCell(
                  value: hasMetrics ? _compact(b.clicks) : '—',
                  sub: null,
                ),
              ),

              // ── CTR with bar (100) ────────────────────────────────
              SizedBox(
                width: 100,
                child: _CtrCell(
                  ctr: hasMetrics ? b.ctr : null,
                ),
              ),

              // ── Revenue (100) ─────────────────────────────────────
              SizedBox(
                width: 100,
                child: _MetricCell(
                  value: b.attributedRevenue > 0
                      ? '₪${_compactMoney(b.attributedRevenue)}'
                      : (hasMetrics ? '₪0' : '—'),
                  sub: null,
                ),
              ),

              // ── Actions (80) ──────────────────────────────────────
              SizedBox(
                width: 80,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _hover ? 1 : 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _ActionBtn(
                        icon: Icons.copy_outlined,
                        tooltip: 'שכפל',
                        onPressed: widget.onDuplicate,
                      ),
                      _ActionBtn(
                        icon: Icons.more_horiz_rounded,
                        tooltip: 'עוד',
                        onPressed: widget.onMore,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _meta(BannerModel b) {
    final bits = <String>[];
    if (b.type == BannerType.providerCarousel) {
      final n = b.providerCarousel?.providerIds.length ?? 0;
      final ms = b.providerCarousel?.rotationDurationMs ?? 4000;
      bits.add('$n ספקים');
      bits.add('מתחלף כל ${(ms / 1000).round()} שנ׳');
    }
    if (b.subtitle.isNotEmpty && b.type != BannerType.providerCarousel) {
      bits.add(b.subtitle);
    }
    if (b.createdAt != null) {
      bits.add('נוצר ${_dmY(b.createdAt!)}');
    }
    return bits.join(' · ');
  }

  static String _dmY(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}';
  }

  static String _compact(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) {
      final k = n / 1000;
      return k >= 100
          ? '${k.toStringAsFixed(0)}k'
          : '${k.toStringAsFixed(k >= 10 ? 0 : 1)}k';
    }
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }

  static String _compactMoney(double v) {
    if (v < 1000) return v.toStringAsFixed(0);
    if (v < 10000) return '${(v / 1000).toStringAsFixed(1)}k';
    if (v < 1000000) return '${(v / 1000).toStringAsFixed(0)}k';
    return '${(v / 1000000).toStringAsFixed(1)}M';
  }

  static Color _statusColor(BannerStatus s) => switch (s) {
        BannerStatus.active => StudioColors.success,
        BannerStatus.scheduled => StudioColors.info,
        BannerStatus.draft => StudioColors.warn,
        BannerStatus.expired => StudioColors.ink4,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER ROW
// ─────────────────────────────────────────────────────────────────────────────

class StudioBannerTableHeader extends StatelessWidget {
  const StudioBannerTableHeader({
    super.key,
    required this.allSelected,
    required this.someSelected,
    required this.onToggleAll,
  });

  final bool allSelected;
  final bool someSelected;
  final ValueChanged<bool> onToggleAll;

  @override
  Widget build(BuildContext context) {
    final labelStyle = StudioText.overline().copyWith(
      fontSize: 11,
      letterSpacing: 0.66,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: StudioSpacing.s5,
        vertical: StudioSpacing.s3,
      ),
      decoration: const BoxDecoration(
        color: StudioColors.bgSubtle,
        border: Border(bottom: BorderSide(color: StudioColors.line2)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: GestureDetector(
              onTap: () => onToggleAll(!allSelected),
              child: _Check(
                checked: allSelected,
                indeterminate: someSelected && !allSelected,
              ),
            ),
          ),
          Expanded(
              flex: 30,
              child: Text('באנר',
                  style: labelStyle, textDirection: TextDirection.rtl)),
          SizedBox(
              width: 90,
              child: Text('מיקום',
                  style: labelStyle, textDirection: TextDirection.rtl)),
          SizedBox(
              width: 120,
              child: Text('סטטוס',
                  style: labelStyle, textDirection: TextDirection.rtl)),
          SizedBox(
              width: 100,
              child: Text('חשיפות',
                  style: labelStyle, textDirection: TextDirection.rtl)),
          SizedBox(
              width: 100,
              child: Text('הקלקות',
                  style: labelStyle, textDirection: TextDirection.rtl)),
          SizedBox(
              width: 100,
              child: Text('CTR',
                  style: labelStyle, textDirection: TextDirection.rtl)),
          SizedBox(
              width: 100,
              child: Text('הכנסה',
                  style: labelStyle, textDirection: TextDirection.rtl)),
          const SizedBox(width: 80),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUB-WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _Thumb extends StatelessWidget {
  const _Thumb({required this.banner});
  final BannerModel banner;

  Color _hex(String hex) {
    final h = hex.replaceAll('#', '');
    final v = int.tryParse(h, radix: 16);
    if (v == null) return StudioColors.ink5;
    if (h.length == 6) return Color(0xFF000000 | v);
    return Color(v);
  }

  @override
  Widget build(BuildContext context) {
    final isVip = banner.type == BannerType.providerCarousel;

    return Container(
      width: 56,
      height: 36,
      decoration: BoxDecoration(
        gradient: isVip
            ? const LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [Color(0xFF1F1B14), Color(0xFF2A2317)],
              )
            : LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [_hex(banner.color1), _hex(banner.color2)],
              ),
        borderRadius: BorderRadius.circular(StudioRadius.xs),
        border: Border.all(
          color: isVip
              ? StudioColors.gold.withValues(alpha: 0.3)
              : StudioColors.line,
        ),
      ),
      alignment: Alignment.center,
      child: isVip
          ? const Text('⭐', style: TextStyle(fontSize: 13))
          : null,
    );
  }
}

class _PlacementChip extends StatelessWidget {
  const _PlacementChip({required this.type});
  final BannerType type;

  @override
  Widget build(BuildContext context) {
    final spec = _spec(type);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: spec.bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          spec.label,
          style: StudioText.chip(color: spec.fg),
          textDirection: TextDirection.rtl,
        ),
      ),
    );
  }

  static _ChipSpec _spec(BannerType type) {
    return switch (type) {
      BannerType.providerCarousel => const _ChipSpec(
          label: '⭐ VIP',
          bg: StudioColors.goldSoft,
          fg: StudioColors.goldDeep,
        ),
      BannerType.homeCarousel => const _ChipSpec(
          label: 'בית',
          bg: StudioColors.infoBg,
          fg: StudioColors.info,
        ),
      BannerType.wallet => const _ChipSpec(
          label: 'ארנק',
          bg: StudioColors.walletBg,
          fg: StudioColors.walletInk,
        ),
      BannerType.popup => const _ChipSpec(
          label: 'פופ-אפ',
          bg: StudioColors.bgSubtle,
          fg: StudioColors.ink2,
        ),
      BannerType.topBar => const _ChipSpec(
          label: 'עליון',
          bg: StudioColors.bgSubtle,
          fg: StudioColors.ink2,
        ),
      BannerType.subcategory => const _ChipSpec(
          label: '📁 תת-קט׳',
          bg: StudioColors.subcatBg,
          fg: StudioColors.subcatInk,
        ),
    };
  }
}

class _ChipSpec {
  final String label;
  final Color bg;
  final Color fg;
  const _ChipSpec({required this.label, required this.bg, required this.fg});
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.on, required this.onChanged});
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!on),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 32,
        height: 18,
        decoration: BoxDecoration(
          color: on ? StudioColors.success : StudioColors.ink5,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Stack(
          children: [
            AnimatedPositionedDirectional(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              top: 2,
              start: on ? 16 : 2,
              child: Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.value, required this.sub});
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: StudioText.metricSm(),
          textDirection: TextDirection.rtl,
        ),
        if (sub != null && sub!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(sub!,
                style: StudioText.captionSm(),
                textDirection: TextDirection.rtl),
          ),
      ],
    );
  }
}

class _CtrCell extends StatelessWidget {
  const _CtrCell({required this.ctr});
  final double? ctr;

  @override
  Widget build(BuildContext context) {
    if (ctr == null) {
      return const _MetricCell(value: '—', sub: null);
    }
    final pct = ctr!.clamp(0, 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${pct.toStringAsFixed(1)}%',
          style: StudioText.metricSm(),
          textDirection: TextDirection.rtl,
        ),
        const SizedBox(height: 4),
        Container(
          height: 4,
          decoration: BoxDecoration(
            color: StudioColors.bgSubtle,
            borderRadius: BorderRadius.circular(999),
          ),
          // ⚠️ The fill is rendered ONLY when pct > 0. A `widthFactor: 0`
          // FractionallySizedBox paints its gradient child at a zero-width
          // rect — the gradient's begin/end points collapse to the same
          // coordinate and CanvasKit's `MakeLinearGradient` returns null
          // for that zero-length gradient. The next frame's rasterizer
          // then crashes with "Cannot read properties of null (reading
          // 'toString')". A 0% CTR bar should be empty anyway, so we just
          // skip the fill entirely.
          child: pct <= 0
              ? null
              : FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: (pct / 12).clamp(0.0, 1.0).toDouble(),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: StudioColors.ctrBarGradient,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 28,
        height: 28,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(StudioRadius.xs),
          child: InkWell(
            borderRadius: BorderRadius.circular(StudioRadius.xs),
            onTap: onPressed,
            child: Icon(icon, size: 14, color: StudioColors.ink3),
          ),
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.checked, this.indeterminate = false});
  final bool checked;
  final bool indeterminate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: (checked || indeterminate)
            ? StudioColors.ink
            : Colors.transparent,
        border: Border.all(
          color: (checked || indeterminate)
              ? StudioColors.ink
              : StudioColors.ink5,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: indeterminate
          ? const Center(
              child: SizedBox(
                width: 8,
                height: 1.5,
                child: ColoredBox(color: Colors.white),
              ),
            )
          : checked
              ? const Icon(Icons.check, color: Colors.white, size: 12)
              : null,
    );
  }
}
