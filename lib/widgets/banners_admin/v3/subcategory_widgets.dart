import 'package:flutter/material.dart';

import '../../../models/banner_model.dart';
import '../../../services/subcategory_banner_service.dart';
import 'design_tokens.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// Subcategory banners admin — supporting widgets (Phase 4).
///
/// Three building blocks for `SubcategoryBannersScreen`:
///   - [StudioDefaultBannerCard] — dashed-border card pinned at the top
///     for the global default subcategory banner. If absent, prompts
///     the admin to create one.
///   - [StudioCategoryAccordion] — root category that expands to reveal
///     its subcategories (each rendered as a [StudioSubcategoryRow]).
///   - [StudioSubcategoryRow] — single subcategory row with mini-thumbs
///     of any pinned banners + status chip + action button.
///
/// All three pull layout/colour from `design_tokens.dart` and follow the
/// banner v3 visual language (cream background, gold accents).
/// ═══════════════════════════════════════════════════════════════════════════

// ─── DefaultBannerCard ───────────────────────────────────────────────────────

class StudioDefaultBannerCard extends StatelessWidget {
  const StudioDefaultBannerCard({
    super.key,
    required this.defaultBanner,
    required this.subcategoriesUsingDefault,
    required this.onEdit,
    required this.onCreate,
  });

  /// The single global default banner. Null = not configured yet.
  final BannerModel? defaultBanner;

  /// Count of subcategories that fall back to the default (i.e. have no
  /// dedicated banner of their own).
  final int subcategoriesUsingDefault;

  /// Tapped when the admin wants to edit the existing default.
  final VoidCallback onEdit;

  /// Tapped when no default exists yet — the admin needs to create one.
  final VoidCallback onCreate;

  Color _hex(String hex) {
    final h = hex.replaceAll('#', '');
    final v = int.tryParse(h, radix: 16);
    if (v == null) return StudioColors.ink5;
    if (h.length == 6) return Color(0xFF000000 | v);
    return Color(v);
  }

  @override
  Widget build(BuildContext context) {
    final has = defaultBanner != null;
    return Container(
      padding: const EdgeInsets.all(StudioSpacing.s5),
      decoration: BoxDecoration(
        color: StudioColors.bgElevated,
        border: Border.all(
          color: has ? StudioColors.gold : StudioColors.ink5,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(StudioRadius.lg),
      ),
      child: Row(
        children: [
          // Mini preview
          Container(
            width: 140,
            height: 80,
            decoration: BoxDecoration(
              gradient: has
                  ? LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [
                        _hex(defaultBanner!.color1),
                        _hex(defaultBanner!.color2),
                      ],
                    )
                  : const LinearGradient(
                      colors: [
                        StudioColors.bgSubtle,
                        StudioColors.bgTonal,
                      ],
                    ),
              borderRadius: BorderRadius.circular(StudioRadius.sm),
            ),
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 0),
            child: has
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        defaultBanner!.title.isEmpty
                            ? 'ברירת מחדל'
                            : defaultBanner!.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.rtl,
                      ),
                      if (defaultBanner!.subtitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            defaultBanner!.subtitle,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 9.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.rtl,
                          ),
                        ),
                    ],
                  )
                : Center(
                    child: Icon(Icons.image_outlined,
                        size: 24, color: StudioColors.ink4),
                  ),
          ),
          const SizedBox(width: StudioSpacing.s5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: StudioColors.goldSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '⚡ ברירת מחדל גלובלית',
                    style: StudioText.chip(color: StudioColors.goldDeep),
                    textDirection: TextDirection.rtl,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  has
                      ? (defaultBanner!.title.isEmpty
                          ? '(ללא כותרת)'
                          : defaultBanner!.title)
                      : 'ברירת מחדל לא הוגדרה עדיין',
                  style: StudioText.h3(),
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 4),
                Text(
                  has
                      ? '$subcategoriesUsingDefault תת-קטגוריות מציגות את הבאנר הזה (אין להן באנר ייעודי)'
                      : 'באנר זה יוצג בכל תת-קטגוריה שאין לה באנר ייעודי. צור אחד עכשיו.',
                  style: StudioText.body(color: StudioColors.ink3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
          ),
          const SizedBox(width: StudioSpacing.s4),
          if (has)
            FilledButton.tonal(
              onPressed: onEdit,
              style: FilledButton.styleFrom(
                backgroundColor: StudioColors.bgSubtle,
                foregroundColor: StudioColors.ink2,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(StudioRadius.sm)),
              ),
              child: const Text('ערוך ברירת מחדל'),
            )
          else
            FilledButton(
              onPressed: onCreate,
              style: FilledButton.styleFrom(
                backgroundColor: StudioColors.goldDeep,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(StudioRadius.sm)),
              ),
              child: const Text('צור ברירת מחדל'),
            ),
        ],
      ),
    );
  }
}

// ─── CategoryAccordion ──────────────────────────────────────────────────────

class StudioCategoryAccordion extends StatefulWidget {
  const StudioCategoryAccordion({
    super.key,
    required this.category,
    required this.subcategoryBanners,
    required this.onTapSubcategory,
    this.initiallyOpen = false,
  });

  final CategoryNode category;

  /// Map: subcategoryId → list of pinned banners.
  final Map<String, List<BannerModel>> subcategoryBanners;
  final void Function(SubcategoryNode sub, List<BannerModel> banners)
      onTapSubcategory;
  final bool initiallyOpen;

  @override
  State<StudioCategoryAccordion> createState() =>
      _StudioCategoryAccordionState();
}

class _StudioCategoryAccordionState extends State<StudioCategoryAccordion> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final c = widget.category;
    final withBanner = c.subcategories
        .where((s) =>
            (widget.subcategoryBanners[s.id] ?? const []).isNotEmpty)
        .length;
    final total = c.subcategories.length;

    return Container(
      decoration: studioCard(radius: StudioRadius.md),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: StudioSpacing.s5, vertical: 14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: _open ? StudioColors.line : Colors.transparent,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: StudioColors.bgSubtle,
                      borderRadius: BorderRadius.circular(StudioRadius.sm),
                    ),
                    child: Text(
                      c.emoji,
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(c.name,
                            style: StudioText.h3(),
                            textDirection: TextDirection.rtl),
                        const SizedBox(height: 2),
                        Text(
                          '$total תתי-קטגוריות',
                          style: StudioText.captionSm(),
                          textDirection: TextDirection.rtl,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: withBanner > 0
                          ? StudioColors.successBg
                          : StudioColors.bgSubtle,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      withBanner > 0
                          ? '✓ $withBanner / $total עם באנר'
                          : '— ללא באנרים',
                      style: StudioText.chip(
                        color: withBanner > 0
                            ? StudioColors.success
                            : StudioColors.ink4,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 180),
                    turns: _open ? 0.5 : 0.0,
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
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: _open && c.subcategories.isNotEmpty
                ? Column(
                    children: [
                      for (final sub in c.subcategories)
                        StudioSubcategoryRow(
                          subcategory: sub,
                          banners: widget.subcategoryBanners[sub.id] ??
                              const [],
                          onTap: () => widget.onTapSubcategory(
                              sub,
                              widget.subcategoryBanners[sub.id] ??
                                  const []),
                        ),
                    ],
                  )
                : _open
                    ? Padding(
                        padding: const EdgeInsets.all(StudioSpacing.s5),
                        child: Text(
                          'אין תת-קטגוריות בקטגוריה זו',
                          style: StudioText.captionSm(),
                          textDirection: TextDirection.rtl,
                        ),
                      )
                    : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ─── SubcategoryRow ─────────────────────────────────────────────────────────

class StudioSubcategoryRow extends StatelessWidget {
  const StudioSubcategoryRow({
    super.key,
    required this.subcategory,
    required this.banners,
    required this.onTap,
  });

  final SubcategoryNode subcategory;
  final List<BannerModel> banners;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasBanners = banners.isNotEmpty;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: StudioSpacing.s5, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
              bottom: BorderSide(color: StudioColors.line)),
        ),
        child: Row(
          children: [
            // Emoji icon
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: StudioColors.bgSubtle,
                borderRadius: BorderRadius.circular(StudioRadius.xs),
              ),
              child: Text(subcategory.emoji,
                  style: const TextStyle(fontSize: 14)),
            ),
            const SizedBox(width: 10),
            // Name + meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    subcategory.name,
                    style: StudioText.bodyMedium(color: StudioColors.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    hasBanners
                        ? '${banners.length} ${banners.length == 1 ? 'באנר ייעודי' : 'באנרים ייעודיים'}'
                        : 'משתמש בברירת מחדל',
                    style: StudioText.captionSm(),
                    textDirection: TextDirection.rtl,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Mini-thumbs (up to 3 overlapping)
            if (hasBanners) _MiniThumbs(banners: banners),
            const SizedBox(width: 12),
            // Status chip
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: hasBanners
                    ? StudioColors.successBg
                    : StudioColors.bgSubtle,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                hasBanners ? '✓ ${banners.length} באנרים' : '⚡ ברירת מחדל',
                style: StudioText.chip(
                  color: hasBanners
                      ? StudioColors.success
                      : StudioColors.ink4,
                ),
                textDirection: TextDirection.rtl,
              ),
            ),
            const SizedBox(width: 12),
            // Action button
            FilledButton.tonal(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: hasBanners
                    ? StudioColors.bgSubtle
                    : StudioColors.ink,
                foregroundColor:
                    hasBanners ? StudioColors.ink2 : Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(StudioRadius.xs)),
              ),
              child: Text(
                hasBanners ? '✏️ ערוך' : '+ הוסף באנר',
                textDirection: TextDirection.rtl,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniThumbs extends StatelessWidget {
  const _MiniThumbs({required this.banners});
  final List<BannerModel> banners;

  Color _hex(String hex) {
    final h = hex.replaceAll('#', '');
    final v = int.tryParse(h, radix: 16);
    if (v == null) return StudioColors.ink5;
    if (h.length == 6) return Color(0xFF000000 | v);
    return Color(v);
  }

  @override
  Widget build(BuildContext context) {
    final shown = banners.take(3).toList();
    return SizedBox(
      width: 24 + (shown.length - 1) * 12,
      height: 24,
      child: Stack(
        children: [
          for (int i = 0; i < shown.length; i++)
            PositionedDirectional(
              end: i * 12.0,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      _hex(shown[i].color1),
                      _hex(shown[i].color2),
                    ],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
