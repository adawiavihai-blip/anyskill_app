import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/banner_model.dart';
import 'provider_carousel_banner.dart';

/// Renders banners pinned to a single subcategory at the top of
/// `CategoryResultsScreen`. A single banner doc can render in three
/// styles based on `designStyle`:
///
/// - `'gradient'` (default) — colored gradient promo card
/// - `'image'` — full-bleed image promo card
/// - `'provider_carousel'` — rotating provider rail (same widget as the
///   VIP rail on the home tab, but scoped to this subcategory page)
///
/// Falls back to the global default subcategory banner (the one with
/// `isDefaultGlobalSubcat: true`) when no pinned banner exists. Renders
/// nothing when nothing qualifies (Law 4 §9b — sliver must collapse to
/// zero height on empty/error so the cards list stays at the top).
///
/// **ID resolution gotcha (CLAUDE.md §31):** the `categories` collection
/// has mixed doc-id schemes — categories created by the legacy admin tab
/// use the Hebrew name as their doc id, while categories created by
/// newer paths (`category_repository.add` etc.) get auto-generated IDs.
/// The admin banner picker stores `subcategoryId == doc.id`, but
/// `CategoryResultsScreen` only knows the display **name**. To match
/// banners across both schemes we resolve the categoryName → set of
/// candidate ids ONCE on init (the name itself + any matching doc id
/// found via a `where('name', isEqualTo: name)` lookup) and query banners
/// with `subcategoryId IN [...]`.
class SubcategoryBannerHeader extends StatefulWidget {
  const SubcategoryBannerHeader({super.key, required this.subcategoryId});

  /// The display name of the subcategory (passed in as `categoryName`
  /// from the navigator). NOT necessarily the Firestore doc id.
  final String subcategoryId;

  @override
  State<SubcategoryBannerHeader> createState() =>
      _SubcategoryBannerHeaderState();
}

class _SubcategoryBannerHeaderState extends State<SubcategoryBannerHeader> {
  late final Future<List<String>> _candidateIdsFuture;

  @override
  void initState() {
    super.initState();
    _candidateIdsFuture = _resolveCandidateIds(widget.subcategoryId);
  }

  /// Returns every value that admins might have stored on
  /// `banners/{id}.subcategoryId` to refer to this subcategory:
  /// always includes the name itself + every Firestore doc id found
  /// via a name-equality lookup. Deduped + ≤10 items so it fits inside
  /// a single `whereIn` (Firestore caps at 30 but we don't need more
  /// than a couple in practice).
  Future<List<String>> _resolveCandidateIds(String name) async {
    final candidates = <String>{if (name.isNotEmpty) name};
    try {
      final snap = await FirebaseFirestore.instance
          .collection('categories')
          .where('name', isEqualTo: name)
          .limit(5)
          .get();
      for (final d in snap.docs) {
        candidates.add(d.id);
      }
    } catch (_) {
      // Silent fall-through — at worst we still match the name itself.
    }
    return candidates.toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.subcategoryId.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<List<String>>(
      future: _candidateIdsFuture,
      builder: (context, idSnap) {
        if (!idSnap.hasData) return const SizedBox.shrink();
        final ids = idSnap.data!;
        if (ids.isEmpty) return const SizedBox.shrink();
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('banners')
              .where('placement', isEqualTo: 'subcategory')
              .where('subcategoryId', whereIn: ids)
              .limit(20)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              // Permission / missing-index error → never break the page.
              return const SizedBox.shrink();
            }
            if (!snap.hasData) return const SizedBox.shrink();

            final now = DateTime.now();
            final pinned = snap.data!.docs.where((d) {
              final m = d.data();
              if (m['isActive'] != true) return false;
              final exp = (m['expiresAt'] as Timestamp?)?.toDate();
              if (exp != null && !exp.isAfter(now)) return false;
              if (!_subcatScheduleAllowsNow(m['scheduleHours'], now)) {
                return false;
              }
              return true;
            }).toList()
              ..sort((a, b) {
                final ao = (a.data()['order'] as num?)?.toInt() ?? 999;
                final bo = (b.data()['order'] as num?)?.toInt() ?? 999;
                return ao.compareTo(bo);
              });

            if (pinned.isNotEmpty) {
              return _SubcatBannerColumn(docs: pinned);
            }
            return const _GlobalDefaultSubcategoryBanner();
          },
        );
      },
    );
  }
}

// ─── Global default fallback (one-shot, memoized) ─────────────────────────

class _GlobalDefaultSubcategoryBanner extends StatefulWidget {
  const _GlobalDefaultSubcategoryBanner();

  @override
  State<_GlobalDefaultSubcategoryBanner> createState() =>
      _GlobalDefaultSubcategoryBannerState();
}

class _GlobalDefaultSubcategoryBannerState
    extends State<_GlobalDefaultSubcategoryBanner> {
  late final Future<QuerySnapshot<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    // Memoized in initState so parent setState (search query etc.)
    // doesn't refire the read on every keystroke.
    _future = FirebaseFirestore.instance
        .collection('banners')
        .where('placement', isEqualTo: 'subcategory')
        .where('isDefaultGlobalSubcat', isEqualTo: true)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError || !snap.hasData || snap.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        return _SubcatBannerColumn(docs: snap.data!.docs);
      },
    );
  }
}

// ─── Render a stack of qualifying banners ─────────────────────────────────

class _SubcatBannerColumn extends StatelessWidget {
  const _SubcatBannerColumn({required this.docs});

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[];
    for (final doc in docs) {
      final card = _renderOne(doc);
      if (card == null) continue;
      if (cards.isNotEmpty) {
        cards.add(const SizedBox(height: 12));
      }
      cards.add(card);
    }
    if (cards.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: cards,
      ),
    );
  }

  Widget? _renderOne(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data();
    final designStyle = (m['designStyle'] as String?) ?? '';
    final title = (m['title'] as String?) ?? '';
    final subtitle = (m['subtitle'] as String?) ?? '';

    // ── Detect provider-carousel mode robustly ──────────────────────────
    // Triggered when EITHER:
    //   • admin explicitly picked the "נותני שירות" design style, OR
    //   • the doc carries valid `providerCarousel` data with ≥1 provider
    //     (covers banners created before designStyle was wired up).
    //
    // ProviderCarouselBanner requires a `title` arg but never paints it
    // (see widgets/provider_carousel_banner.dart — `widget.title` is
    // unused inside the build). Mirrors the home rail's
    // "נותני השירות ה-VIP שלנו" pattern: render the title ABOVE.
    final pcRaw = m['providerCarousel'];
    final hasCarouselData = pcRaw is Map<String, dynamic> &&
        (((pcRaw['providerIds'] as List?) ?? const [])
            .whereType<String>()
            .isNotEmpty);
    final isCarousel = designStyle == 'provider_carousel' || hasCarouselData;

    Widget? inner;
    if (isCarousel && pcRaw is Map<String, dynamic>) {
      final config = ProviderCarouselConfig.fromMap(pcRaw);
      inner = SizedBox(
        height: 200,
        child: ProviderCarouselBanner(
          config: config,
          title: title,
          bannerId: doc.id,
          height: 200,
          onClick: (_) {
            FirebaseFirestore.instance
                .collection('banners')
                .doc(doc.id)
                .update({'clicks': FieldValue.increment(1)})
                .catchError((_) {});
          },
        ),
      );
    } else {
      // ── Subcategory promo (gradient / image) ──────────────────────────
      final imageUrl = (m['imageUrl'] as String?) ?? '';
      if (title.isEmpty && subtitle.isEmpty && imageUrl.isEmpty) return null;
      inner = _SubcategoryPromoCard(
        bannerId: doc.id,
        title: title,
        subtitle: subtitle,
        imageUrl: imageUrl,
        color1: (m['color1'] as String?) ?? '6366F1',
        color2: (m['color2'] as String?) ?? '8B5CF6',
        iconEmoji: m['iconEmoji'] as String?,
      );
    }

    // ── Always render the admin-set title ABOVE the card ────────────────
    // The user explicitly asked for this — same pattern as the home tab's
    // VIP rail header. Applies to BOTH carousels and gradient/image banners
    // (gradient banners keep their inner title for visual richness; the
    // header label up top is the customer's primary cue).
    if (title.isEmpty && subtitle.isEmpty) return inner;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(title: title, subtitle: subtitle),
        inner,
      ],
    );
  }
}

// ─── Section heading (used above the provider carousel) ──────────────────

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    // Force RTL so `CrossAxisAlignment.start` resolves to RIGHT regardless
    // of the surrounding directionality (e.g. an LTR parent during locale
    // testing). `Align(centerRight)` would also work but `Directionality`
    // also makes the Text widgets pick the correct text-align by default.
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(2, 0, 2, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title.isNotEmpty)
              Text(
                title,
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827),
                  height: 1.2,
                ),
              ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6B7280),
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Single gradient/image card ───────────────────────────────────────────

class _SubcategoryPromoCard extends StatelessWidget {
  const _SubcategoryPromoCard({
    required this.bannerId,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.color1,
    required this.color2,
    this.iconEmoji,
  });

  final String bannerId;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String color1;
  final String color2;
  final String? iconEmoji;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FirebaseFirestore.instance
            .collection('banners')
            .doc(bannerId)
            .update({'clicks': FieldValue.increment(1)})
            .catchError((_) {});
      },
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [_hex(color1), _hex(color2)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _hex(color1).withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              if (imageUrl.isNotEmpty)
                Positioned.fill(
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              if (imageUrl.isNotEmpty)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [
                          _hex(color1).withValues(alpha: 0.55),
                          _hex(color2).withValues(alpha: 0.65),
                        ],
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (title.isNotEmpty)
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                height: 1.25,
                              ),
                            ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.88),
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (iconEmoji != null && iconEmoji!.isNotEmpty) ...[
                      const SizedBox(width: 16),
                      Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          iconEmoji!,
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _hex(String h) {
    final clean = h.replaceAll('#', '').padLeft(6, '0');
    return Color(int.parse('FF$clean', radix: 16));
  }
}

// ─── Schedule helper (mirrors home_tab.dart `_studioScheduleAllowsNow`) ──
//
// Duplicated intentionally — both call sites are tiny and decoupling them
// would require promoting a private helper to a shared utility (4 imports
// touched). If the schedule logic ever changes, update BOTH.
bool _subcatScheduleAllowsNow(dynamic raw, DateTime now) {
  if (raw == null) return true;
  if (raw is! Map) return true;
  if (raw.isEmpty) return true;
  const dayKeys = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
  final dayIdx = now.weekday == 7 ? 0 : now.weekday;
  final key = dayKeys[dayIdx];
  final list = raw[key];
  if (list is! List) return false;
  if (list.isEmpty) return false;
  final h = now.hour;
  int? bucket;
  if (h >= 8 && h < 12) {
    bucket = 8;
  } else if (h >= 12 && h < 16) {
    bucket = 12;
  } else if (h >= 16 && h < 20) {
    bucket = 16;
  } else if (h >= 20 && h < 24) {
    bucket = 20;
  }
  if (bucket == null) return false;
  for (final v in list) {
    if (v is num && v.toInt() == bucket) return true;
  }
  return false;
}
