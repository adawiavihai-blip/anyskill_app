// ignore_for_file: use_build_context_synchronously
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/banner_model.dart';
import '../../services/banners_service.dart';
import '../../services/subcategory_banner_service.dart';
import '../../widgets/banners_admin/v3/design_tokens.dart';
import '../../widgets/banners_admin/v3/gradient_picker.dart';
import '../../widgets/banners_admin/v3/icon_emoji_picker.dart';
import '../../widgets/banners_admin/v3/live_preview_phone.dart';
import '../../widgets/banners_admin/v3/provider_picker_section.dart';
import '../../widgets/banners_admin/v3/section_card.dart';
import '../../widgets/banners_admin/v3/weekly_heatmap.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// Banner Edit Screen — Phase 2 of the Banners Studio rewrite.
///
/// Per `docs/ui-specs/Baner/banners-mockup-v3.html` Screen B:
///   - Top app bar with back + page title + breadcrumb
///   - Body: form column (1fr) + sticky live preview (380px)
///   - Form is 6 SectionCard accordions (basic / design / providers /
///     rotation / schedule / targeting). Sections 3 + 4 only render
///     for `provider_carousel` placement.
///   - Sticky save bar at the bottom: LIVE indicator + change count +
///     Discard / Save draft / Publish buttons.
///
/// **Lifecycle:**
///   - `BannerEditScreen()` → new banner (default model values).
///   - `BannerEditScreen(banner: existing)` → edit existing.
///   - On save, calls `BannersService.createBanner` or `updateBanner`,
///     pops with the persisted [BannerModel] as the result.
///
/// **Phase-2 contract**: this screen does NOT touch v1/v2/VIP tabs —
/// they keep working unchanged. The dashboard wires its row-tap +
/// "New" button to push this screen.
/// ═══════════════════════════════════════════════════════════════════════════

class BannerEditScreen extends StatefulWidget {
  const BannerEditScreen({super.key, this.banner});

  /// The banner to edit. Pass null for a new banner.
  final BannerModel? banner;

  @override
  State<BannerEditScreen> createState() => _BannerEditScreenState();
}

class _BannerEditScreenState extends State<BannerEditScreen> {
  // ── Working state ───────────────────────────────────────────────────────
  late BannerModel _draft;
  late final BannerModel _original;
  bool _isSaving = false;
  int _openSection = 1;

  // ── Text controllers (kept in sync with draft) ──────────────────────────
  final _titleCtrl = TextEditingController();
  final _subtitleCtrl = TextEditingController();
  final _imageUrlCtrl = TextEditingController();

  /// A banner is "new" when there is no widget input at all OR when the
  /// caller passed a synthesized draft with an empty doc id (the
  /// subcategory banners admin tab does this — see
  /// `SubcategoryBannersScreen._openEditFor`). Without the empty-id
  /// branch, `_save()` would route to `updateBanner` and Firestore would
  /// throw "A document path must be a non-empty string".
  bool get _isNew => widget.banner == null || widget.banner!.id.isEmpty;

  /// True if any field differs from `_original`. Drives the save bar.
  bool get _isDirty {
    final a = _draft;
    final b = _original;
    return a.title != b.title ||
        a.subtitle != b.subtitle ||
        a.type != b.type ||
        a.isActive != b.isActive ||
        a.order != b.order ||
        a.startDate != b.startDate ||
        a.endDate != b.endDate ||
        a.imageUrl != b.imageUrl ||
        a.color1 != b.color1 ||
        a.color2 != b.color2 ||
        a.iconEmoji != b.iconEmoji ||
        a.designStyle != b.designStyle ||
        _scheduleEq(a.scheduleHours, b.scheduleHours) == false ||
        _carouselEq(a.providerCarousel, b.providerCarousel) == false;
  }

  /// Counts how many high-level field groups changed. Surfaced in the
  /// save bar like "3 שינויים מאז הפרסום".
  int get _changeCount {
    int n = 0;
    final a = _draft;
    final b = _original;
    if (a.title != b.title) n++;
    if (a.subtitle != b.subtitle) n++;
    if (a.type != b.type) n++;
    if (a.imageUrl != b.imageUrl) n++;
    if (a.color1 != b.color1 || a.color2 != b.color2) n++;
    if (a.iconEmoji != b.iconEmoji) n++;
    if (a.startDate != b.startDate || a.endDate != b.endDate) n++;
    if (_scheduleEq(a.scheduleHours, b.scheduleHours) == false) n++;
    if (_carouselEq(a.providerCarousel, b.providerCarousel) == false) n++;
    if (a.order != b.order) n++;
    return n;
  }

  static bool _scheduleEq(
      Map<String, List<int>>? a, Map<String, List<int>>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      final av = a[k] ?? const [];
      final bv = b[k] ?? const [];
      if (av.length != bv.length) return false;
      for (int i = 0; i < av.length; i++) {
        if (av[i] != bv[i]) return false;
      }
    }
    return true;
  }

  static bool _carouselEq(
      ProviderCarouselConfig? a, ProviderCarouselConfig? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.providerIds.length != b.providerIds.length) return false;
    for (int i = 0; i < a.providerIds.length; i++) {
      if (a.providerIds[i] != b.providerIds[i]) return false;
    }
    return a.rotationDurationMs == b.rotationDurationMs &&
        a.sortMode == b.sortMode &&
        a.transition == b.transition;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _draft = widget.banner ?? _newBlankBanner();
    _original = _draft;
    _titleCtrl.text = _draft.title;
    _subtitleCtrl.text = _draft.subtitle;
    _imageUrlCtrl.text = _draft.imageUrl;
  }

  static BannerModel _newBlankBanner() {
    return const BannerModel(
      id: '',
      title: '',
      subtitle: '',
      type: BannerType.homeCarousel,
      isActive: false, // new banners start as drafts
      designStyle: 'gradient',
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _imageUrlCtrl.dispose();
    super.dispose();
  }

  void _patch(BannerModel Function(BannerModel) f) {
    setState(() => _draft = f(_draft));
  }

  // ── Save flows ─────────────────────────────────────────────────────────

  Future<void> _save({required bool publish}) async {
    if (_isSaving) return;

    // Validation
    if (_draft.title.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('כותרת נדרשת לפני שמירה')),
      );
      setState(() => _openSection = 1);
      return;
    }
    // Carousel-config validation applies whenever providers are rendered:
    // - VIP `providerCarousel` placement (always)
    // - `subcategory` placement with designStyle == 'provider_carousel'
    final needsCarouselValidation =
        _draft.type == BannerType.providerCarousel ||
            (_draft.type == BannerType.subcategory &&
                _draft.designStyle == 'provider_carousel');
    if (needsCarouselValidation) {
      final cfg = _draft.providerCarousel;
      final err = cfg?.validate();
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err)),
        );
        setState(() => _openSection = 3);
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final toPersist = _draft.copyWith(
        isActive: publish,
        createdBy: _draft.createdBy ?? uid,
      );
      if (_isNew) {
        await BannersService.instance.createBanner(toPersist);
      } else {
        await BannersService.instance.updateBanner(toPersist);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(publish
              ? (_isNew ? 'הבאנר פורסם!' : 'השינויים פורסמו')
              : (_isNew ? 'הטיוטה נשמרה' : 'נשמר כטיוטה')),
        ),
      );
      // Dashboard re-streams from Firestore so we don't need to return
      // the saved model — popping is enough.
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה בשמירה: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _onDiscard() async {
    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('לבטל את כל השינויים?'),
        content: const Text(
            'יש שינויים שלא נשמרו. אם תצא — הם יאבדו לצמיתות.',
            textDirection: TextDirection.rtl),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('המשך לערוך'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: StudioColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('בטל ויצא'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _onDiscard();
      },
      child: Scaffold(
        backgroundColor: StudioColors.bg,
        appBar: AppBar(
          backgroundColor: StudioColors.bgElevated,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: StudioColors.ink),
            onPressed: _onDiscard,
          ),
          title: Row(
            children: [
              Text(
                _isNew ? 'באנר חדש' : (_draft.title.isEmpty
                    ? '(ללא כותרת)'
                    : _draft.title),
                style: StudioText.h3(),
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(width: 12),
              if (!_isNew)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: StudioColors.bgSubtle,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _draft.status.hebrewLabel,
                    style: StudioText.captionSm(),
                  ),
                ),
            ],
          ),
        ),
        body: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 980;
          if (wide) {
            return _buildWideLayout();
          }
          return _buildNarrowLayout();
        }),
        bottomNavigationBar: _SaveBar(
          isDirty: _isDirty,
          changeCount: _changeCount,
          isSaving: _isSaving,
          isNew: _isNew,
          onDiscard: _onDiscard,
          onSaveDraft: () => _save(publish: false),
          onPublish: () => _save(publish: true),
        ),
      ),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(StudioSpacing.s7),
            child: _buildForm(),
          ),
        ),
        Container(
          width: 380,
          padding: const EdgeInsets.fromLTRB(0, StudioSpacing.s7,
              StudioSpacing.s7, StudioSpacing.s7),
          child: StudioLivePreviewPhone(banner: _draft),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(StudioSpacing.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StudioLivePreviewPhone(banner: _draft),
          const SizedBox(height: StudioSpacing.s6),
          _buildForm(),
        ],
      ),
    );
  }

  Widget _buildForm() {
    final isVip = _draft.type == BannerType.providerCarousel;
    // Subcategory banners can ALSO carry a provider carousel — the admin
    // chooses via the design-style picker (gradient / image / providers).
    // See `SubcategoryBannerHeader` runtime + `_designSection` UI.
    final isSubcatProviderCarousel =
        _draft.type == BannerType.subcategory &&
            _draft.designStyle == 'provider_carousel';
    final showProviderSections = isVip || isSubcatProviderCarousel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _basicSection(),
        const SizedBox(height: StudioSpacing.s4),
        _designSection(),
        if (showProviderSections) ...[
          const SizedBox(height: StudioSpacing.s4),
          _providersSection(),
          const SizedBox(height: StudioSpacing.s4),
          _rotationSection(),
        ],
        const SizedBox(height: StudioSpacing.s4),
        _scheduleSection(),
        const SizedBox(height: StudioSpacing.s4),
        _targetingSection(),
      ],
    );
  }

  // ─── Section 1 — Basic ─────────────────────────────────────────────────
  Widget _basicSection() {
    final hasTitle = _draft.title.trim().isNotEmpty;
    return StudioSectionCard(
      number: 1,
      title: 'פרטים בסיסיים',
      description: 'כותרת, תת-כותרת, מיקום וסדר תצוגה',
      open: _openSection == 1,
      onToggle: () => setState(() => _openSection = _openSection == 1 ? 0 : 1),
      statusLabel: hasTitle ? 'מוגדר' : 'חסר כותרת',
      statusVariant: hasTitle
          ? StudioSectionStatus.success
          : StudioSectionStatus.warn,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StudioField(
            label: 'כותרת',
            controller: _titleCtrl,
            hint: 'לדוגמה: נותני השירות שלנו · VIP',
            maxLength: 60,
            helperEnd: '${_titleCtrl.text.length}/60',
            onChanged: (v) => _patch((d) => d.copyWith(title: v)),
          ),
          const SizedBox(height: StudioSpacing.s5),
          StudioField(
            label: 'תת-כותרת',
            controller: _subtitleCtrl,
            hint: 'לדוגמה: 30 ספקים מובילים · קליק לבחירה',
            maxLength: 90,
            helperEnd: '${_subtitleCtrl.text.length}/90',
            onChanged: (v) => _patch((d) => d.copyWith(subtitle: v)),
          ),
          const SizedBox(height: StudioSpacing.s5),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'מיקום הצגה',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: StudioColors.ink2,
              ),
              textDirection: TextDirection.rtl,
            ),
          ),
          StudioSegmented<BannerType>(
            options: const [
              StudioSegmentOption(
                  value: BannerType.providerCarousel,
                  label: 'VIP',
                  icon: Icons.star_rounded),
              StudioSegmentOption(
                  value: BannerType.homeCarousel,
                  label: 'בית',
                  icon: Icons.home_outlined),
              StudioSegmentOption(
                  value: BannerType.subcategory,
                  label: 'תת-קט׳',
                  icon: Icons.folder_open_rounded),
              StudioSegmentOption(
                  value: BannerType.wallet,
                  label: 'ארנק',
                  icon: Icons.account_balance_wallet_outlined),
            ],
            selected: _draft.type == BannerType.providerCarousel ||
                    _draft.type == BannerType.homeCarousel ||
                    _draft.type == BannerType.subcategory ||
                    _draft.type == BannerType.wallet
                ? _draft.type
                : BannerType.homeCarousel,
            onChanged: (t) {
              _patch((d) {
                // Preserve providerCarousel config when switching between
                // VIP and subcategory placements (both can render it).
                final keepCarousel = t == BannerType.providerCarousel ||
                    t == BannerType.subcategory;
                return d.copyWith(
                  type: t,
                  providerCarousel: keepCarousel
                      ? (d.providerCarousel ??
                          const ProviderCarouselConfig())
                      : null,
                  // Subcategory-specific fields cleared when switching away.
                  subcategoryId:
                      t == BannerType.subcategory ? d.subcategoryId : null,
                  isDefaultGlobalSubcat: t == BannerType.subcategory
                      ? d.isDefaultGlobalSubcat
                      : false,
                );
              });
            },
          ),
          // ── Subcategory-specific fields (shown only for subcategory placement) ──
          if (_draft.type == BannerType.subcategory) ...[
            const SizedBox(height: StudioSpacing.s4),
            _SubcategoryConfigSection(
              selectedSubcategoryId: _draft.subcategoryId,
              isDefault: _draft.isDefaultGlobalSubcat,
              onChanged: (subId, isDefault) {
                _patch((d) => d.copyWith(
                      subcategoryId: isDefault ? null : subId,
                      isDefaultGlobalSubcat: isDefault,
                    ));
              },
            ),
          ],
          const SizedBox(height: StudioSpacing.s5),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'סדר הצגה',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: StudioColors.ink2),
                      textDirection: TextDirection.rtl,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton.outlined(
                          icon: const Icon(Icons.remove_rounded, size: 16),
                          onPressed: () => _patch((d) =>
                              d.copyWith(order: (d.order - 1).clamp(0, 999))),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            '${_draft.order}',
                            style: StudioText.metricMd(),
                          ),
                        ),
                        IconButton.outlined(
                          icon: const Icon(Icons.add_rounded, size: 16),
                          onPressed: () => _patch((d) =>
                              d.copyWith(order: (d.order + 1).clamp(0, 999))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'מספר נמוך = מוצג ראשון',
                      style: StudioText.captionSm(),
                      textDirection: TextDirection.rtl,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Section 2 — Design ────────────────────────────────────────────────
  Widget _designSection() {
    final designStyle = _draft.designStyle ??
        (_draft.imageUrl.isNotEmpty ? 'image' : 'gradient');
    // Only `subcategory` placement currently exposes the third "providers"
    // design option — VIP `providerCarousel` placement always uses the
    // provider rail by definition.
    final allowProviderCarouselStyle =
        _draft.type == BannerType.subcategory;
    final isProviderCarousel = designStyle == 'provider_carousel';
    final statusLabel = isProviderCarousel
        ? 'נותני שירות'
        : (designStyle == 'image' ? 'תמונה' : 'גרדיאנט');
    return StudioSectionCard(
      number: 2,
      title: 'עיצוב ומראה',
      description: 'גרדיאנט, תמונה, או קרוסלת נותני שירות',
      open: _openSection == 2,
      onToggle: () => setState(() => _openSection = _openSection == 2 ? 0 : 2),
      statusLabel: statusLabel,
      statusVariant: StudioSectionStatus.info,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'סגנון רקע',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: StudioColors.ink2),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 8),
          StudioSegmented<String>(
            options: [
              const StudioSegmentOption(
                  value: 'gradient',
                  label: 'גרדיאנט',
                  icon: Icons.gradient_rounded),
              const StudioSegmentOption(
                  value: 'image',
                  label: 'תמונה',
                  icon: Icons.image_outlined),
              if (allowProviderCarouselStyle)
                const StudioSegmentOption(
                    value: 'provider_carousel',
                    label: 'נותני שירות',
                    icon: Icons.people_alt_outlined),
            ],
            selected: designStyle,
            onChanged: (v) {
              _patch((d) {
                // When switching INTO provider_carousel, seed an empty
                // ProviderCarouselConfig so the providers section can
                // render immediately. When switching OUT, keep any
                // existing config (admin can switch back without losing
                // the provider list).
                final ensureCarousel = v == 'provider_carousel'
                    ? (d.providerCarousel ??
                        const ProviderCarouselConfig())
                    : d.providerCarousel;
                return d.copyWith(
                  designStyle: v,
                  providerCarousel: ensureCarousel,
                );
              });
            },
          ),
          const SizedBox(height: StudioSpacing.s5),

          if (isProviderCarousel) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: StudioColors.bgSubtle,
                borderRadius:
                    BorderRadius.circular(StudioRadius.xs),
                border: Border.all(color: StudioColors.line2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 16, color: StudioColors.ink3),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'הבאנר יציג קרוסלת נותני שירות (כמו ה-VIP בלשונית בית) בראש עמוד תת-הקטגוריה. בחר נותני שירות והגדר סיבוב בסעיפים הבאים.',
                      style: StudioText.captionSm(),
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (designStyle == 'gradient') ...[
            Text(
              'בחר גרדיאנט',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: StudioColors.ink2),
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 8),
            StudioGradientPicker(
              color1: _draft.color1,
              color2: _draft.color2,
              onChanged: (c1, c2) =>
                  _patch((d) => d.copyWith(color1: c1, color2: c2)),
            ),
          ] else ...[
            StudioField(
              label: 'כתובת תמונה',
              controller: _imageUrlCtrl,
              hint: 'https://...',
              onChanged: (v) => _patch((d) => d.copyWith(imageUrl: v)),
            ),
            const SizedBox(height: 6),
            Text(
              'הדבק URL תמונה (PWA קיים — תמיכת העלאה תתווסף בפאזה 6)',
              style: StudioText.captionSm(),
              textDirection: TextDirection.rtl,
            ),
          ],

          // Emoji icon doesn't apply to provider-carousel rendering — hide it.
          if (!isProviderCarousel) ...[
            const SizedBox(height: StudioSpacing.s5),
            Text(
              'אייקון אימוג׳י',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: StudioColors.ink2),
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 8),
            StudioIconEmojiPicker(
              selected: _draft.iconEmoji,
              onChanged: (v) => _patch((d) => d.copyWith(iconEmoji: v)),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Section 3 — Providers (VIP only) ──────────────────────────────────
  Widget _providersSection() {
    final ids = _draft.providerCarousel?.providerIds ?? const <String>[];
    final ok = ids.length >= 2 && ids.length <= 20;
    return StudioSectionCard(
      number: 3,
      title: 'ספקים בקרוסלה',
      description: 'בחר 2-20 נותני שירות שיופיעו בכרטיס המתחלף',
      open: _openSection == 3,
      onToggle: () => setState(() => _openSection = _openSection == 3 ? 0 : 3),
      statusLabel: '${ids.length}/30',
      statusVariant: ok ? StudioSectionStatus.success : StudioSectionStatus.warn,
      body: StudioProviderPickerSection(
        selectedIds: ids,
        onChanged: (newIds) {
          _patch((d) => d.copyWith(
                providerCarousel:
                    (d.providerCarousel ?? const ProviderCarouselConfig())
                        .copyWith(providerIds: newIds),
              ));
        },
      ),
    );
  }

  // ─── Section 4 — Rotation (VIP only) ───────────────────────────────────
  Widget _rotationSection() {
    final cfg =
        _draft.providerCarousel ?? const ProviderCarouselConfig();
    return StudioSectionCard(
      number: 4,
      title: 'סיבוב והצגה',
      description: 'מהירות החלפה, סדר וסגנון מעבר',
      open: _openSection == 4,
      onToggle: () => setState(() => _openSection = _openSection == 4 ? 0 : 4),
      statusLabel: '${(cfg.rotationDurationMs / 1000).toStringAsFixed(1)}שנ׳',
      statusVariant: StudioSectionStatus.info,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'משך הצגה לכל כרטיס',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: StudioColors.ink2),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: StudioColors.ink,
                    inactiveTrackColor: StudioColors.bgTonal,
                    thumbColor: StudioColors.ink,
                    overlayColor: StudioColors.ink.withValues(alpha: 0.1),
                  ),
                  child: Slider(
                    value: cfg.rotationDurationMs.toDouble(),
                    min: 2000,
                    max: 8000,
                    divisions: 12,
                    onChanged: (v) => _patch((d) => d.copyWith(
                          providerCarousel: cfg.copyWith(
                              rotationDurationMs: v.round()),
                        )),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 60,
                child: Text(
                  '${(cfg.rotationDurationMs / 1000).toStringAsFixed(1)}שנ׳',
                  style: StudioText.metricMd(),
                  textAlign: TextAlign.start,
                  textDirection: TextDirection.rtl,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (final preset in const [2000, 3000, 4000, 5000, 6000, 8000])
                InkWell(
                  borderRadius: BorderRadius.circular(StudioRadius.xs),
                  onTap: () => _patch((d) => d.copyWith(
                        providerCarousel:
                            cfg.copyWith(rotationDurationMs: preset),
                      )),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: cfg.rotationDurationMs == preset
                          ? StudioColors.ink
                          : StudioColors.bgSubtle,
                      borderRadius: BorderRadius.circular(StudioRadius.xs),
                    ),
                    child: Text(
                      '${(preset / 1000).toStringAsFixed(0)}שנ׳',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: cfg.rotationDurationMs == preset
                            ? Colors.white
                            : StudioColors.ink3,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: StudioSpacing.s5),
          Text(
            'סדר תצוגה',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: StudioColors.ink2),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 8),
          StudioSegmented<ProviderSortMode>(
            options: const [
              StudioSegmentOption(
                  value: ProviderSortMode.ai, label: 'AI חכם'),
              StudioSegmentOption(
                  value: ProviderSortMode.random, label: 'אקראי'),
              StudioSegmentOption(
                  value: ProviderSortMode.rating, label: 'דירוג'),
              StudioSegmentOption(
                  value: ProviderSortMode.manual, label: 'ידני'),
            ],
            selected: cfg.sortMode,
            onChanged: (m) => _patch((d) => d.copyWith(
                  providerCarousel: cfg.copyWith(sortMode: m),
                )),
          ),

          const SizedBox(height: StudioSpacing.s5),
          Text(
            'אנימציית מעבר',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: StudioColors.ink2),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 8),
          StudioSegmented<CarouselTransition>(
            options: const [
              StudioSegmentOption(
                  value: CarouselTransition.fade, label: 'עמעום'),
              StudioSegmentOption(
                  value: CarouselTransition.slide, label: 'החלקה'),
              StudioSegmentOption(
                  value: CarouselTransition.zoom, label: 'הגדלה'),
              StudioSegmentOption(
                  value: CarouselTransition.flip, label: 'היפוך'),
            ],
            selected: cfg.transition,
            onChanged: (t) => _patch((d) => d.copyWith(
                  providerCarousel: cfg.copyWith(transition: t),
                )),
          ),
          const SizedBox(height: 8),
          Text(
            'הערה: רק "עמעום" מיושם בזמן ריצה כיום. שאר האנימציות יתווספו בפאזה 6.',
            style: StudioText.captionSm(),
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
    );
  }

  // ─── Section 5 — Schedule ──────────────────────────────────────────────
  Widget _scheduleSection() {
    final hasSchedule = _draft.scheduleHours != null &&
        _draft.scheduleHours!.isNotEmpty;
    final scheduledTotal = _draft.scheduleHours == null
        ? 0
        : _draft.scheduleHours!.values
            .fold<int>(0, (acc, list) => acc + list.length);
    return StudioSectionCard(
      number: 5,
      title: 'תזמון ופרסום',
      description: 'תאריכי הצגה ושעות יום בשבוע',
      open: _openSection == 5,
      onToggle: () => setState(() => _openSection = _openSection == 5 ? 0 : 5),
      statusLabel: hasSchedule ? '$scheduledTotal משבצות' : 'תמיד פעיל',
      statusVariant: hasSchedule
          ? StudioSectionStatus.info
          : StudioSectionStatus.gray,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _DatePickerField(
                  label: 'מתחיל ב-',
                  value: _draft.startDate,
                  onChanged: (d) => _patch((m) => m.copyWith(startDate: d)),
                ),
              ),
              const SizedBox(width: StudioSpacing.s4),
              Expanded(
                child: _DatePickerField(
                  label: 'מסתיים ב-',
                  value: _draft.endDate,
                  onChanged: (d) => _patch((m) => m.copyWith(endDate: d)),
                ),
              ),
            ],
          ),
          const SizedBox(height: StudioSpacing.s5),
          Row(
            children: [
              Expanded(
                child: Text(
                  'שעות פעילות בשבוע',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: StudioColors.ink2),
                  textDirection: TextDirection.rtl,
                ),
              ),
              if (hasSchedule)
                TextButton(
                  onPressed: () => _patch((d) => d.copyWith(
                        scheduleHours: null,
                      )),
                  child: const Text('נקה תזמון'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: StudioColors.bgElevated,
              border: Border.all(color: StudioColors.line2),
              borderRadius: BorderRadius.circular(StudioRadius.sm),
            ),
            child: StudioWeeklyHeatmap(
              schedule: _draft.scheduleHours ?? const {},
              onChanged: (m) => _patch(
                  (d) => d.copyWith(scheduleHours: m.isEmpty ? null : m)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'הערה: סינון שעות-יום בזמן ריצה ייכנס לפעולה בפאזה 6 (כרגע נשמר כסכמה בלבד).',
            style: StudioText.captionSm(),
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
    );
  }

  // ─── Section 6 — Targeting (info-only in Phase 2) ──────────────────────
  Widget _targetingSection() {
    return StudioSectionCard(
      number: 6,
      title: 'טירגוט ו-A/B Testing',
      description: 'הצגה לקהל יעד וניסויים מבוקרים',
      open: _openSection == 6,
      onToggle: () => setState(() => _openSection = _openSection == 6 ? 0 : 6),
      statusLabel: 'בקרוב',
      statusVariant: StudioSectionStatus.gray,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StudioSwitchRow(
            title: 'הצג לכל המשתמשים',
            description: 'ללא סינון לפי קטגוריה, מיקום או היסטוריה',
            value: true,
            onChanged: (_) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content:
                        Text('טירגוט מתקדם — יבנה בפאזה 6')),
              );
            },
          ),
          StudioSwitchRow(
            title: 'הפעל A/B Test',
            description: 'הצג שתי גרסאות במקביל ובחן ביצועים',
            value: _draft.hasAbTest,
            onChanged: (_) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content:
                        Text('A/B Testing — יבנה בפאזה 6')),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SAVE BAR
// ─────────────────────────────────────────────────────────────────────────────

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.isDirty,
    required this.changeCount,
    required this.isSaving,
    required this.isNew,
    required this.onDiscard,
    required this.onSaveDraft,
    required this.onPublish,
  });

  final bool isDirty;
  final int changeCount;
  final bool isSaving;
  final bool isNew;
  final VoidCallback onDiscard;
  final VoidCallback onSaveDraft;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: StudioColors.bgElevated,
        border: Border(top: BorderSide(color: StudioColors.line)),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: StudioSpacing.s7, vertical: 14),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: isDirty ? StudioColors.warn : StudioColors.success,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isSaving
                    ? 'שומר...'
                    : isDirty
                        ? '$changeCount שינויים שלא נשמרו'
                        : (isNew
                            ? 'באנר חדש · עוד לא נוצר'
                            : 'הכל מסונכרן'),
                style: StudioText.bodyMedium(
                  color: isDirty ? StudioColors.warn : StudioColors.ink3,
                ),
                textDirection: TextDirection.rtl,
              ),
            ),
            TextButton(
              onPressed: isSaving ? null : onDiscard,
              child: Text(isDirty ? 'בטל' : 'סגור',
                  style: StudioText.bodyMedium(color: StudioColors.ink3),
                  textDirection: TextDirection.rtl),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: isSaving ? null : onSaveDraft,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: StudioColors.line2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(StudioRadius.sm)),
              ),
              child: Text('שמור כטיוטה',
                  style: StudioText.bodyMedium(color: StudioColors.ink2),
                  textDirection: TextDirection.rtl),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: isSaving ? null : onPublish,
              style: FilledButton.styleFrom(
                backgroundColor: StudioColors.ink,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(StudioRadius.sm)),
              ),
              child: isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      isNew ? 'פרסם' : (isDirty ? 'פרסם שינויים' : 'הכל פעיל'),
                      style: StudioText.bodyMedium(color: Colors.white),
                      textDirection: TextDirection.rtl,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUBCATEGORY CONFIG SECTION (Phase 4)
// Picks the target subcategory OR the "global default" toggle.
// ─────────────────────────────────────────────────────────────────────────────

class _SubcategoryConfigSection extends StatefulWidget {
  const _SubcategoryConfigSection({
    required this.selectedSubcategoryId,
    required this.isDefault,
    required this.onChanged,
  });
  final String? selectedSubcategoryId;
  final bool isDefault;

  /// Called with `(subcategoryId, isDefault)`. When `isDefault==true`,
  /// `subcategoryId` is ignored.
  final void Function(String? subcategoryId, bool isDefault) onChanged;

  @override
  State<_SubcategoryConfigSection> createState() =>
      _SubcategoryConfigSectionState();
}

class _SubcategoryConfigSectionState
    extends State<_SubcategoryConfigSection> {
  bool _loading = true;
  String? _error;
  CategoryTree? _tree;

  /// The parent-category id currently shown in the FIRST dropdown.
  /// Derived from [widget.selectedSubcategoryId] at load + on
  /// external updates (didUpdateWidget); otherwise admin-controlled
  /// via the parent dropdown directly.
  String? _selectedParentId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _SubcategoryConfigSection old) {
    super.didUpdateWidget(old);
    // If parent state changed the subcategoryId externally (e.g. discard
    // → reload), re-resolve which parent it belongs to so the first
    // dropdown stays in sync.
    if (widget.selectedSubcategoryId != old.selectedSubcategoryId &&
        _tree != null) {
      final newParent = _findParentFor(widget.selectedSubcategoryId);
      if (newParent != _selectedParentId) {
        setState(() => _selectedParentId = newParent);
      }
    }
  }

  Future<void> _load() async {
    try {
      final tree = await SubcategoryBannerService.instance.loadCategoryTree();
      if (mounted) {
        setState(() {
          _tree = tree;
          _loading = false;
          // Pre-select the parent that owns the existing subcategoryId
          // so the cascading picker opens to the right place when
          // editing an existing banner.
          _selectedParentId = _findParentFor(widget.selectedSubcategoryId);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Walks the loaded tree to find which parent category owns the given
  /// subcategory id. Returns null if not found or input is null.
  String? _findParentFor(String? subId) {
    if (subId == null || subId.isEmpty || _tree == null) return null;
    for (final cat in _tree!.categories) {
      for (final sub in cat.subcategories) {
        if (sub.id == subId) return cat.id;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: StudioColors.subcatBg.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(StudioRadius.sm),
        border: Border.all(color: StudioColors.subcatBg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.folder_open_rounded,
                  size: 16, color: StudioColors.subcatInk),
              const SizedBox(width: 8),
              Text(
                'הגדרת באנר תת-קטגוריה',
                style: StudioText.bodyMedium(color: StudioColors.subcatInk),
                textDirection: TextDirection.rtl,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Default toggle
          InkWell(
            borderRadius: BorderRadius.circular(StudioRadius.xs),
            onTap: () => widget.onChanged(
                widget.selectedSubcategoryId, !widget.isDefault),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: widget.isDefault
                    ? StudioColors.goldSoft
                    : StudioColors.bgElevated,
                border: Border.all(
                  color: widget.isDefault
                      ? StudioColors.gold
                      : StudioColors.line2,
                ),
                borderRadius: BorderRadius.circular(StudioRadius.xs),
              ),
              child: Row(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: widget.isDefault
                          ? StudioColors.gold
                          : Colors.transparent,
                      border: Border.all(
                        color: widget.isDefault
                            ? StudioColors.gold
                            : StudioColors.ink5,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: widget.isDefault
                        ? const Icon(Icons.check_rounded,
                            size: 13, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '⚡ ברירת מחדל גלובלית',
                          style: StudioText.bodyMedium(
                              color: StudioColors.ink),
                          textDirection: TextDirection.rtl,
                        ),
                        Text(
                          'יוצג בכל תת-קטגוריה ללא באנר ייעודי',
                          style: StudioText.captionSm(),
                          textDirection: TextDirection.rtl,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!widget.isDefault) ...[
            const SizedBox(height: 10),
            if (_loading)
              const SizedBox(
                  height: 36,
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2)))
            else if (_error != null)
              Text('שגיאה בטעינת קטגוריות: $_error',
                  style: StudioText.captionSm(),
                  textDirection: TextDirection.rtl)
            else ...[
              // ── Dropdown 1 — pick the parent category ─────────────────
              Text(
                'בחר קטגוריה',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: StudioColors.ink2,
                ),
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(height: 6),
              _buildCategoryDropdown(),
              if (_selectedParentId != null) ...[
                const SizedBox(height: 12),
                // ── Dropdown 2 — pick the subcategory under that parent ─
                Text(
                  'בחר תת-קטגוריה',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: StudioColors.ink2,
                  ),
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 6),
                _buildSubcategoryDropdown(),
              ],
            ],
          ],
        ],
      ),
    );
  }

  // ─── Parent-category dropdown ─────────────────────────────────────────
  Widget _buildCategoryDropdown() {
    final cats = _tree?.categories ?? const [];
    // Only pass `value` if the current parent is one of the options —
    // otherwise the framework crashes on "no item matches the value".
    final hasValue = _selectedParentId != null &&
        cats.any((c) => c.id == _selectedParentId);
    return DropdownButtonFormField<String>(
      value: hasValue ? _selectedParentId : null,
      isExpanded: true,
      hint: Text(
        'בחר קטגוריה...',
        style: StudioText.body(color: StudioColors.ink4),
        textDirection: TextDirection.rtl,
      ),
      decoration: _dropdownDecoration(),
      items: [
        for (final c in cats)
          DropdownMenuItem<String>(
            value: c.id,
            child: Text(
              '${c.emoji} ${c.name}',
              textDirection: TextDirection.rtl,
              overflow: TextOverflow.ellipsis,
              style: StudioText.body(color: StudioColors.ink),
            ),
          ),
      ],
      onChanged: (v) {
        if (v == _selectedParentId) return;
        setState(() => _selectedParentId = v);
        // Switching the parent invalidates the previous subcategory
        // selection — clear it so the customer-facing query doesn't
        // point at a sub that no longer matches the picked parent.
        widget.onChanged(null, false);
      },
    );
  }

  // ─── Subcategory dropdown (filtered to the selected parent) ──────────
  Widget _buildSubcategoryDropdown() {
    final subs = _tree == null || _selectedParentId == null
        ? const <SubcategoryNode>[]
        : _tree!.categories
            .firstWhere(
              (c) => c.id == _selectedParentId,
              orElse: () => const CategoryNode(
                id: '',
                name: '',
                emoji: '',
                subcategories: [],
              ),
            )
            .subcategories;

    final hasValue = widget.selectedSubcategoryId != null &&
        subs.any((s) => s.id == widget.selectedSubcategoryId);

    if (subs.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: StudioColors.bgElevated,
          border: Border.all(color: StudioColors.line2),
          borderRadius: BorderRadius.circular(StudioRadius.xs),
        ),
        child: Text(
          'אין תת-קטגוריות בקטגוריה זו',
          style: StudioText.captionSm(),
          textDirection: TextDirection.rtl,
        ),
      );
    }

    return DropdownButtonFormField<String>(
      value: hasValue ? widget.selectedSubcategoryId : null,
      isExpanded: true,
      hint: Text(
        'בחר תת-קטגוריה...',
        style: StudioText.body(color: StudioColors.ink4),
        textDirection: TextDirection.rtl,
      ),
      decoration: _dropdownDecoration(),
      items: [
        for (final s in subs)
          DropdownMenuItem<String>(
            value: s.id,
            child: Text(
              '${s.emoji} ${s.name}',
              textDirection: TextDirection.rtl,
              overflow: TextOverflow.ellipsis,
              style: StudioText.body(color: StudioColors.ink),
            ),
          ),
      ],
      onChanged: (v) => widget.onChanged(v, false),
    );
  }

  InputDecoration _dropdownDecoration() {
    return InputDecoration(
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      filled: true,
      fillColor: StudioColors.bgElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(StudioRadius.xs),
        borderSide: const BorderSide(color: StudioColors.line2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(StudioRadius.xs),
        borderSide: const BorderSide(color: StudioColors.line2),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATE PICKER FIELD
// ─────────────────────────────────────────────────────────────────────────────

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 2)),
      locale: const Locale('he'),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final txt = value == null
        ? 'בחר תאריך'
        : '${value!.day.toString().padLeft(2, '0')}/'
            '${value!.month.toString().padLeft(2, '0')}/'
            '${value!.year}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: StudioColors.ink2),
            textDirection: TextDirection.rtl,
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(StudioRadius.sm),
          onTap: () => _pick(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: StudioColors.bgElevated,
              border: Border.all(color: StudioColors.line2),
              borderRadius: BorderRadius.circular(StudioRadius.sm),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_month_outlined,
                    size: 16, color: StudioColors.ink3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    txt,
                    style: StudioText.body(
                        color: value == null
                            ? StudioColors.ink4
                            : StudioColors.ink),
                    textDirection: TextDirection.rtl,
                  ),
                ),
                if (value != null)
                  InkWell(
                    onTap: () => onChanged(null),
                    child: const Icon(Icons.close_rounded,
                        size: 14, color: StudioColors.ink4),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
