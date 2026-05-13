import 'package:flutter/material.dart';

import '../../../models/banner_model.dart';
import 'design_tokens.dart';

/// Sticky right-rail iPhone preview for the banner edit screen.
///
/// Mockup spec ([banners-mockup-v3.html:405-440](docs/ui-specs/Baner/banners-mockup-v3.html)):
///   - 280px wide phone frame, 9/19 aspect ratio
///   - Black bezel + notch + status bar
///   - Inside: search bar, stories row, the LIVE banner preview, mock
///     tiles, mock promo banner
///   - Updates instantly as the user edits (driven by the [banner] prop)
class StudioLivePreviewPhone extends StatelessWidget {
  const StudioLivePreviewPhone({
    super.key,
    required this.banner,
    this.providerCount,
  });

  final BannerModel banner;

  /// Optional override — for VIP placement, used to display "X ספקים"
  /// in the preview info card. Defaults to the banner's own list size.
  final int? providerCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'תצוגה מקדימה חיה',
            textAlign: TextAlign.center,
            style: StudioText.overline()
                .copyWith(letterSpacing: 1.26, fontWeight: FontWeight.w700),
            textDirection: TextDirection.rtl,
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: AspectRatio(
              aspectRatio: 9 / 19,
              child: _PhoneFrame(banner: banner),
            ),
          ),
        ),
        const SizedBox(height: StudioSpacing.s4),
        _PreviewInfo(
          banner: banner,
          providerCount: providerCount ??
              (banner.providerCarousel?.providerIds.length ?? 0),
        ),
      ],
    );
  }
}

// ─── Phone frame ────────────────────────────────────────────────────────────

class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.banner});
  final BannerModel banner;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(36),
        boxShadow: StudioShadows.sh4,
      ),
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Container(
          color: StudioColors.bg,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status bar
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                        22, 14, 22, 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text('9:41',
                            style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1A1A))),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.signal_cellular_alt_rounded,
                                size: 10, color: Color(0xFF1A1A1A)),
                            SizedBox(width: 4),
                            Icon(Icons.wifi_rounded,
                                size: 10, color: Color(0xFF1A1A1A)),
                            SizedBox(width: 4),
                            Icon(Icons.battery_full_rounded,
                                size: 10, color: Color(0xFF1A1A1A)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Content
                  Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsets.fromLTRB(12, 6, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _MockSearch(),
                          const SizedBox(height: 8),
                          _MockStories(),
                          const SizedBox(height: 8),
                          // ── Live banner ──
                          _LiveBannerPreview(banner: banner),
                          const SizedBox(height: 8),
                          _SectionTitleBlock(),
                          const SizedBox(height: 6),
                          _TileGrid(),
                          const Spacer(),
                          _PromoFooter(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // Notch
              const Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: _Notch(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notch extends StatelessWidget {
  const _Notch();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 18,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _MockSearch extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: AlignmentDirectional.centerStart,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StudioColors.line),
      ),
      child: Text(
        'חפש נותן שירות...',
        style: TextStyle(fontSize: 9, color: StudioColors.ink4),
        textDirection: TextDirection.rtl,
      ),
    );
  }
}

class _MockStories extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (int i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [Color(0xFFB89855), Color(0xFF4A2A6E)],
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

class _SectionTitleBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 10,
      width: 100,
      decoration: BoxDecoration(
        color: StudioColors.bgTonal,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _TileGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (int i = 0; i < 4; i++)
          Container(
            decoration: BoxDecoration(
              color: StudioColors.bgSubtle,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
      ],
    );
  }
}

class _PromoFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF1A6B5B), Color(0xFF2A8F77)],
        ),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

// ─── The live banner ────────────────────────────────────────────────────────

class _LiveBannerPreview extends StatelessWidget {
  const _LiveBannerPreview({required this.banner});
  final BannerModel banner;

  @override
  Widget build(BuildContext context) {
    if (banner.type == BannerType.providerCarousel) {
      return _VipPreviewCard(banner: banner);
    }
    return _GradientPreviewCard(banner: banner);
  }
}

class _GradientPreviewCard extends StatelessWidget {
  const _GradientPreviewCard({required this.banner});
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
    final useImage = banner.imageUrl.isNotEmpty;
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: useImage
            ? null
            : LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [_hex(banner.color1), _hex(banner.color2)],
              ),
        image: useImage
            ? DecorationImage(
                image: NetworkImage(banner.imageUrl),
                fit: BoxFit.cover,
              )
            : null,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          if (banner.iconEmoji != null && banner.iconEmoji!.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: Text(
                banner.iconEmoji!,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  banner.title.isEmpty ? 'כותרת הבאנר' : banner.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.rtl,
                ),
                if (banner.subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      banner.subtitle,
                      style: const TextStyle(
                        color: Color(0xD9FFFFFF),
                        fontSize: 9,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.rtl,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VipPreviewCard extends StatelessWidget {
  const _VipPreviewCard({required this.banner});
  final BannerModel banner;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF1F1B14), Color(0xFF2A2317)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: StudioColors.gold, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4DB89855),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Gold tag
          PositionedDirectional(
            top: 0,
            start: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: StudioColors.gold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '⭐ VIP',
                style: TextStyle(
                  fontSize: 7.5,
                  color: StudioColors.gold,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: StudioColors.goldGradient,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.person,
                      size: 22, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        banner.title.isEmpty
                            ? 'נותני שירות מובילים'
                            : banner.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.rtl,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        banner.subtitle.isEmpty
                            ? 'הקליקו לבחירה'
                            : banner.subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 8,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.rtl,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₪150 / שעה',
                        style: TextStyle(
                          color: StudioColors.gold,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Pagination dots
          PositionedDirectional(
            bottom: 5,
            start: 0,
            end: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < 4; i++)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 2),
                    child: Container(
                      width: i == 0 ? 8 : 3,
                      height: 3,
                      decoration: BoxDecoration(
                        color: i == 0
                            ? StudioColors.gold
                            : StudioColors.gold.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Info card under the phone ──────────────────────────────────────────────

class _PreviewInfo extends StatelessWidget {
  const _PreviewInfo({required this.banner, required this.providerCount});
  final BannerModel banner;
  final int providerCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(StudioSpacing.s4),
      decoration: studioCard(radius: StudioRadius.md),
      child: Column(
        children: [
          _row('מיקום', banner.type.hebrewLabel),
          if (banner.type == BannerType.providerCarousel) ...[
            const _Divider(),
            _row('ספקים', '$providerCount / 30'),
            const _Divider(),
            _row(
              'סיבוב',
              banner.providerCarousel != null
                  ? 'כל ${(banner.providerCarousel!.rotationDurationMs / 1000).toStringAsFixed(1)}שנ׳'
                  : '—',
            ),
          ],
          const _Divider(),
          _row('סטטוס', banner.status.hebrewLabel),
          if (banner.startDate != null) ...[
            const _Divider(),
            _row('מתחיל ב-', _fmtDate(banner.startDate!)),
          ],
          if (banner.endDate != null) ...[
            const _Divider(),
            _row('מסתיים ב-', _fmtDate(banner.endDate!)),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(label,
              style: StudioText.captionSm(),
              textDirection: TextDirection.rtl),
          const Spacer(),
          Text(
            value,
            style: StudioText.bodyMedium(color: StudioColors.ink2),
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      color: StudioColors.line,
    );
  }
}
