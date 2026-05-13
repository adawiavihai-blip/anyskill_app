import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Accordion card used by all 6 sections of the Banner Edit screen.
///
/// Mockup spec ([banners-mockup-v3.html:303-318](docs/ui-specs/Baner/banners-mockup-v3.html)):
///   - 20px radius, 1px line border, white surface
///   - Head: numbered circle (28x28) + title + description + status pill
///     + chevron arrow that rotates 180° when open
///   - Body: only renders when open; 24px padding
///   - Whole-head tap toggles open/closed; soft `bgSubtle` hover.
class StudioSectionCard extends StatelessWidget {
  const StudioSectionCard({
    super.key,
    required this.number,
    required this.title,
    required this.description,
    required this.open,
    required this.onToggle,
    required this.body,
    this.statusLabel,
    this.statusVariant = StudioSectionStatus.gray,
  });

  /// 1-based section number (1..6).
  final int number;
  final String title;
  final String description;
  final bool open;
  final VoidCallback onToggle;
  final Widget body;

  /// Optional pill on the head row, e.g. "מוגדר", "חסר נתונים".
  final String? statusLabel;

  /// Pill colour scheme.
  final StudioSectionStatus statusVariant;

  @override
  Widget build(BuildContext context) {
    final bg = open ? StudioColors.ink : StudioColors.bgSubtle;
    final fg = open ? Colors.white : StudioColors.ink3;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: studioCard(radius: StudioRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ── Head ────────────────────────────────────────────────────
          InkWell(
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsetsDirectional.fromSTEB(
                StudioSpacing.s6,
                StudioSpacing.s4,
                StudioSpacing.s6,
                StudioSpacing.s4,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: open ? StudioColors.line : Colors.transparent,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Numbered circle
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: bg,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$number',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: fg,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: StudioSpacing.s4),
                  // Title + description
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: StudioText.h3(),
                          textDirection: TextDirection.rtl,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          description,
                          style: StudioText.captionSm(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.rtl,
                        ),
                      ],
                    ),
                  ),
                  // Status pill
                  if (statusLabel != null) ...[
                    const SizedBox(width: StudioSpacing.s3),
                    _StatusPill(
                      label: statusLabel!,
                      variant: statusVariant,
                    ),
                  ],
                  // Arrow
                  const SizedBox(width: StudioSpacing.s3),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 180),
                    turns: open ? 0.5 : 0.0,
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: StudioColors.ink4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Body ────────────────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: open
                ? Padding(
                    padding: const EdgeInsets.all(StudioSpacing.s6),
                    child: body,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

enum StudioSectionStatus { success, warn, gray, info }

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.variant});
  final String label;
  final StudioSectionStatus variant;

  @override
  Widget build(BuildContext context) {
    final spec = _spec(variant);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: spec.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: StudioText.chip(color: spec.fg),
        textDirection: TextDirection.rtl,
      ),
    );
  }

  static _PillSpec _spec(StudioSectionStatus v) => switch (v) {
        StudioSectionStatus.success =>
          const _PillSpec(StudioColors.successBg, StudioColors.success),
        StudioSectionStatus.warn =>
          const _PillSpec(StudioColors.warnBg, StudioColors.warn),
        StudioSectionStatus.info =>
          const _PillSpec(StudioColors.infoBg, StudioColors.info),
        StudioSectionStatus.gray =>
          const _PillSpec(StudioColors.bgTonal, StudioColors.ink4),
      };
}

class _PillSpec {
  final Color bg;
  final Color fg;
  const _PillSpec(this.bg, this.fg);
}

// ─────────────────────────────────────────────────────────────────────────────
// Common form field building blocks — kept in this file so all 6 sections
// don't each invent their own input style.
// ─────────────────────────────────────────────────────────────────────────────

/// A styled labelled text field. RTL-safe.
class StudioField extends StatelessWidget {
  const StudioField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.help,
    this.maxLines = 1,
    this.maxLength,
    this.helperEnd,
    this.onChanged,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? help;
  final int maxLines;
  final int? maxLength;
  final String? helperEnd;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: StudioColors.ink2,
                ),
                textDirection: TextDirection.rtl,
              ),
              const Spacer(),
              if (helperEnd != null)
                Text(
                  helperEnd!,
                  style: StudioText.captionSm(),
                  textDirection: TextDirection.rtl,
                ),
            ],
          ),
        ),
        TextField(
          controller: controller,
          onChanged: onChanged,
          maxLines: maxLines,
          maxLength: maxLength,
          keyboardType: keyboardType,
          textDirection: TextDirection.rtl,
          style: StudioText.body(color: StudioColors.ink),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: StudioText.body(color: StudioColors.ink4),
            counterText: '',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            filled: true,
            fillColor: StudioColors.bgElevated,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(StudioRadius.sm),
              borderSide: const BorderSide(color: StudioColors.line2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(StudioRadius.sm),
              borderSide: const BorderSide(color: StudioColors.line2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(StudioRadius.sm),
              borderSide: const BorderSide(
                  color: StudioColors.ink3, width: 1.4),
            ),
          ),
        ),
        if (help != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              help!,
              style: StudioText.captionSm(),
              textDirection: TextDirection.rtl,
            ),
          ),
      ],
    );
  }
}

/// Segmented control — a row of equal-width tappable pills, exactly one
/// of which is "active" (white surface + shadow).
class StudioSegmented<T> extends StatelessWidget {
  const StudioSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<StudioSegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: StudioColors.bgSubtle,
        borderRadius: BorderRadius.circular(StudioRadius.sm),
      ),
      child: Row(
        children: [
          for (final o in options)
            Expanded(child: _opt(o)),
        ],
      ),
    );
  }

  Widget _opt(StudioSegmentOption<T> o) {
    final active = o.value == selected;
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: () => onChanged(o.value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: active ? StudioShadows.sh1 : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (o.icon != null) ...[
              Icon(
                o.icon,
                size: 13,
                color: active ? StudioColors.ink : StudioColors.ink3,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              o.label,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: active ? StudioColors.ink : StudioColors.ink3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StudioSegmentOption<T> {
  final T value;
  final String label;
  final IconData? icon;
  const StudioSegmentOption({
    required this.value,
    required this.label,
    this.icon,
  });
}

/// A row with title + description on the left, switch on the right.
class StudioSwitchRow extends StatelessWidget {
  const StudioSwitchRow({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: StudioColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: StudioText.bodyMedium(color: StudioColors.ink),
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: StudioText.captionSm(),
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
          ),
          const SizedBox(width: StudioSpacing.s3),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: StudioColors.ink,
            inactiveTrackColor: StudioColors.ink5,
            inactiveThumbColor: Colors.white,
          ),
        ],
      ),
    );
  }
}
