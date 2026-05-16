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
  /// Stream cached so a parent rebuild (RefreshIndicator pull, search-bar
  /// state, filter change) does NOT recreate the subscription and
  /// momentarily blink the banner out. Set after `_resolveCandidateIds`
  /// completes with non-empty ids. May be REPLACED later if a background
  /// retry resolves a richer set of candidate IDs (see [_maybeUpgrade]).
  Stream<QuerySnapshot<Map<String, dynamic>>>? _bannersStream;
  /// Last successful snapshot — rendered during any transient re-emit
  /// window so the banner never disappears between snapshots.
  QuerySnapshot<Map<String, dynamic>>? _lastSnap;
  /// Snapshot of the candidate ids the stream is currently using. Used
  /// by the background-upgrade loop to decide whether a fresh
  /// resolution yields MORE ids — if so, we rebuild the stream with the
  /// richer set.
  List<String> _currentIds = const [];

  @override
  void initState() {
    super.initState();
    // Fire the initial resolve immediately. Even if it fails or returns
    // the minimal name-only seed, we set up the stream with that seed
    // so the banner has at least a chance to appear (legacy docs that
    // stored `subcategoryId == name` will match).
    _resolveAndAttach(initial: true);
  }

  /// Resolves candidate ids and (re)attaches `_bannersStream` if the
  /// resolved set differs from the currently-used set. Called once on
  /// init AND from a background retry loop — on cold WebChannel the
  /// FIRST resolution can fall through to name-only, and the categories
  /// lookup later succeeds with the real doc-id, giving us a richer
  /// candidate set. When that happens we rebuild the stream so the
  /// banner that was previously invisible (because its
  /// `subcategoryId == doc-id`, not the name) finally renders.
  Future<void> _resolveAndAttach({required bool initial}) async {
    final ids = await _resolveCandidateIds(widget.subcategoryId);
    if (!mounted) return;
    if (_setEquals(ids, _currentIds)) {
      // No change — the existing stream already covers these ids.
      if (initial) _maybeScheduleUpgradeRetry();
      return;
    }
    if (ids.isEmpty) {
      if (initial) _maybeScheduleUpgradeRetry();
      return;
    }
    setState(() {
      _currentIds = ids;
      _bannersStream = FirebaseFirestore.instance
          .collection('banners')
          .where('placement', isEqualTo: 'subcategory')
          .where('subcategoryId', whereIn: ids)
          .limit(20)
          .snapshots();
      // Reset _lastSnap so we don't render stale data from an old stream
      // for a transient moment after the swap.
      _lastSnap = null;
    });
    if (initial) _maybeScheduleUpgradeRetry();
    // §15 Law 15 — `.get()` fallback. On a stalled WebChannel the
    // `.snapshots()` listener may never deliver → banner never shows
    // until browser refresh. Fire a one-shot `.get()` with the SAME
    // query; if the stream hasn't delivered, populate `_lastSnap`
    // from the `.get()` result.
    _kickBannerGetFallback(List<String>.from(ids));
  }

  void _kickBannerGetFallback(List<String> ids) {
    Future.delayed(const Duration(seconds: 1), () async {
      if (!mounted || _lastSnap != null) return;
      // Only run if the ids we'd query still match the active stream's.
      if (!_setEquals(ids, _currentIds)) return;
      try {
        final snap = await FirebaseFirestore.instance
            .collection('banners')
            .where('placement', isEqualTo: 'subcategory')
            .where('subcategoryId', whereIn: ids)
            .limit(20)
            .get()
            .timeout(const Duration(seconds: 8));
        if (!mounted || _lastSnap != null) return;
        setState(() => _lastSnap = snap);
        debugPrint(
            '[SubcategoryBannerHeader] .get() fallback delivered ${snap.docs.length} banner doc(s)');
      } catch (e) {
        debugPrint('[SubcategoryBannerHeader] .get() fallback failed: $e');
      }
    });
  }

  bool _setEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final sa = a.toSet();
    return b.every(sa.contains);
  }

  /// If the initial resolution returned ONLY the name (categories
  /// lookup failed/timed out), schedule a few background retries — the
  /// admin probably saved the banner with the doc-id, so name-only
  /// won't match anything. Spreads the retries over ~30s so we don't
  /// keep hammering an offline network.
  ///
  /// Live bug (רועי צברי, 2026-05-15): "the VIP banner on גרר אופנועים
  /// disappeared." Root cause: cold WebChannel → categories query
  /// timed out → only name in candidates → banner doc's `subcategoryId`
  /// was the auto-gen doc-id, not the name → `whereIn` query returned
  /// 0 → banner hidden silently.
  void _maybeScheduleUpgradeRetry() {
    // If we already have multiple candidates (name + doc-ids) the
    // resolution succeeded — no need to retry.
    if (_currentIds.length > 1) return;
    const retryDelays = [
      Duration(seconds: 3),
      Duration(seconds: 8),
      Duration(seconds: 20),
    ];
    for (final delay in retryDelays) {
      Future.delayed(delay, () {
        if (!mounted) return;
        if (_currentIds.length > 1) return; // already upgraded
        _resolveAndAttach(initial: false);
      });
    }
  }

  /// Returns every value that admins might have stored on
  /// `banners/{id}.subcategoryId` to refer to this subcategory:
  /// always includes the name itself + every Firestore doc id found
  /// via a name-equality lookup. Deduped + ≤10 items so it fits inside
  /// a single `whereIn` (Firestore caps at 30 but we don't need more
  /// than a couple in practice).
  ///
  /// 2026-05-15: bumped to 8s timeout + 1 retry. The original 4s was
  /// too tight on cold WebChannel — the categories query consistently
  /// timed out, leaving only the name as a candidate, and admins
  /// configure `subcategoryId == doc-id`, not the name, so the banner
  /// query returned 0 docs.
  Future<List<String>> _resolveCandidateIds(String name) async {
    final candidates = <String>{if (name.isNotEmpty) name};
    if (name.isEmpty) return candidates.toList(growable: false);
    // Two attempts: 8s primary + 5s retry. With the Firestore pre-warm
    // in main.dart Step 4b, the WebChannel SHOULD be warm before this
    // runs — but if the user navigated very fast post-login, the
    // handshake might still be completing. The retry covers that race.
    const timeouts = [Duration(seconds: 8), Duration(seconds: 5)];
    for (int attempt = 0; attempt < timeouts.length; attempt++) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('categories')
            .where('name', isEqualTo: name)
            .limit(5)
            .get()
            .timeout(timeouts[attempt]);
        for (final d in snap.docs) {
          candidates.add(d.id);
        }
        debugPrint(
            '[SubcategoryBannerHeader] Resolved $name → ${candidates.length} candidate(s) on attempt ${attempt + 1}');
        return candidates.toList(growable: false);
      } catch (e) {
        debugPrint(
            '[SubcategoryBannerHeader] Candidates resolve attempt ${attempt + 1} failed: $e');
        // Try the next timeout / give up.
      }
    }
    // Both attempts failed — fall through to name-only seed. The
    // background-retry loop will keep trying for ~30s.
    return candidates.toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.subcategoryId.isEmpty) return const SizedBox.shrink();
    // Wait for either (a) `_bannersStream` ready post-ids-resolve, or
    // (b) the candidate-ids future to surface an empty set. Both end
    // states return SizedBox.shrink — only the active stream path
    // renders content. During the brief setup window (ids resolving,
    // ~5-50ms typically), return shrink rather than blocking the page.
    final stream = _bannersStream;
    if (stream == null) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          // Permission / missing-index error → log it so we can see
          // it in the console + Firebase logs, but never break the
          // page. Most common cause: missing composite index for
          // (placement, subcategoryId). Run `firebase deploy --only
          // firestore:indexes` to fix.
          debugPrint(
              '[SubcategoryBannerHeader] banners query error '
              '(check firestore.indexes.json for placement+subcategoryId '
              'composite index): ${snap.error}');
          return const SizedBox.shrink();
        }
        // Cache the latest non-error snapshot so the banner never
        // momentarily blinks out between snapshot events (e.g. when
        // a doc field is updated and Firestore re-emits the QuerySnap).
        if (snap.hasData) _lastSnap = snap.data;
        final activeSnap = snap.data ?? _lastSnap;
        if (activeSnap == null) return const SizedBox.shrink();

        final now = DateTime.now();
        // (See "Schedule-hours filter" note removed 2026-05-14 —
        // admins control visibility via isActive + expiresAt only.)
        final pinned = activeSnap.docs.where((d) {
          final m = d.data();
          if (m['isActive'] != true) return false;
          final exp = (m['expiresAt'] as Timestamp?)?.toDate();
          if (exp != null && !exp.isAfter(now)) return false;
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
        // 2026-05-15 (live bug, רועי צברי "VIP banner missing on
        // motorcycle towing AGAIN"): even after the candidate-IDs
        // race fix, the `whereIn` query can return 0 banners if the
        // admin saved with a doc-id that's not in our resolved
        // candidates (e.g. category was deleted/recreated with a new
        // auto-gen id, banner still points at the old id). Final
        // safety net: scan ALL active subcategory banners (limit 50,
        // ~one Firestore read) and filter client-side by checking if
        // any has subcategoryName matching this page. Only used when
        // the primary path returned nothing.
        return _LastResortSubcategoryBanner(
          subcategoryName: widget.subcategoryId,
        );
      },
    );
  }
}

// ─── Last-resort scan (one-shot, memoized) ────────────────────────────────
//
// Triggered ONLY when the candidate-IDs whereIn query returned zero
// pinned banners for this subcategory. Scans every active subcategory
// banner (limit 50, cheap) and filters client-side by `subcategoryName`.
// If a match is found, render it. Otherwise fall through to the global
// default. This handles the data-drift case where the admin-saved
// `subcategoryId` no longer matches any candidate we can resolve from
// the name on the client side.

class _LastResortSubcategoryBanner extends StatefulWidget {
  const _LastResortSubcategoryBanner({required this.subcategoryName});

  final String subcategoryName;

  @override
  State<_LastResortSubcategoryBanner> createState() =>
      _LastResortSubcategoryBannerState();
}

class _LastResortSubcategoryBannerState
    extends State<_LastResortSubcategoryBanner> {
  late final Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _findMatchingBanners();
  }

  /// Two-step scan:
  ///   1. Query ALL active subcategory banners (limit 50).
  ///   2. For each banner whose `subcategoryId` is set but not already
  ///      filtered, do a categories/{subcategoryId}.get() reverse
  ///      lookup. If the resolved category name matches our target,
  ///      this banner is the one the admin intended.
  ///   3. Cap at 25 reverse lookups so we don't burn unbounded reads
  ///      on a giant banner set.
  /// Also matches the future-friendly `subcategoryName` field
  /// (cheap, no extra read) — if admin tooling starts saving the
  /// name alongside the id, future scans short-circuit immediately.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _findMatchingBanners() async {
    final target = widget.subcategoryName.trim();
    if (target.isEmpty) return const [];
    final db = FirebaseFirestore.instance;
    try {
      final allActive = await db
          .collection('banners')
          .where('placement', isEqualTo: 'subcategory')
          .where('isActive', isEqualTo: true)
          .limit(50)
          .get()
          .timeout(const Duration(seconds: 6));
      final now = DateTime.now();
      final candidates =
          <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      final needsReverseLookup =
          <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final d in allActive.docs) {
        final m = d.data();
        if (m['isDefaultGlobalSubcat'] == true) continue; // global default handled later
        final exp = (m['expiresAt'] as Timestamp?)?.toDate();
        if (exp != null && !exp.isAfter(now)) continue;
        // Fast match: future-friendly `subcategoryName` field (free, no
        // extra read). If empty/missing, queue for reverse lookup.
        final name = (m['subcategoryName'] as String?)?.trim() ?? '';
        if (name == target) {
          candidates.add(d);
          continue;
        }
        final subId = (m['subcategoryId'] as String?)?.trim() ?? '';
        if (subId.isNotEmpty) {
          needsReverseLookup.add(d);
        }
      }
      // Reverse-lookup pass — cap at 25 to bound the read cost.
      final lookupBudget =
          needsReverseLookup.length.clamp(0, 25);
      for (var i = 0; i < lookupBudget; i++) {
        final banner = needsReverseLookup[i];
        final subId = banner.data()['subcategoryId'] as String;
        try {
          final cat = await db
              .collection('categories')
              .doc(subId)
              .get()
              .timeout(const Duration(seconds: 3));
          final catName = (cat.data()?['name'] as String?)?.trim() ?? '';
          if (catName == target) {
            candidates.add(banner);
          }
        } catch (_) {
          // Reverse-lookup blip — skip this banner.
        }
      }
      candidates.sort((a, b) {
        final ao = (a.data()['order'] as num?)?.toInt() ?? 999;
        final bo = (b.data()['order'] as num?)?.toInt() ?? 999;
        return ao.compareTo(bo);
      });
      if (candidates.isNotEmpty) {
        debugPrint(
            '[SubcategoryBannerHeader] Last-resort scan found ${candidates.length} banner(s) for "$target" (after reverse lookup)');
      } else {
        debugPrint(
            '[SubcategoryBannerHeader] Last-resort scan: no banner matched "$target" out of ${allActive.docs.length} active subcategory banners');
      }
      return candidates;
    } catch (e) {
      debugPrint('[SubcategoryBannerHeader] Last-resort scan failed: $e');
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          // While we're scanning, show NOTHING (no skeleton blink).
          // The scan only runs when primary path returned 0 so it's
          // already past the initial perceived-load window.
          return const SizedBox.shrink();
        }
        if (snap.hasError || !snap.hasData || snap.data!.isEmpty) {
          return const _GlobalDefaultSubcategoryBanner();
        }
        return _SubcatBannerColumn(docs: snap.data!);
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
    // doesn't refire the read on every keystroke. Timeout-bounded so
    // a stuck WebChannel can't leave the fallback hanging — better to
    // surface no banner than to hold the user on a forever-pending
    // FutureBuilder.
    _future = FirebaseFirestore.instance
        .collection('banners')
        .where('placement', isEqualTo: 'subcategory')
        .where('isDefaultGlobalSubcat', isEqualTo: true)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get()
        .timeout(const Duration(seconds: 5));
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

// ─── Schedule helper (legacy — kept for reference) ────────────────────────
//
// REMOVED from active use 2026-05-14 after live user report (רועי צברי):
// the schedule-hours filter was silently hiding the VIP banner on the
// גרר אופנועים sub-category because the admin had set scheduleHours but
// the current hour fell outside the configured buckets (or in the 0-7am
// dead zone the filter rejects by default).
//
// The function is unused now — the filter call site in `build()` was
// removed in the same change. Admins should rely on `isActive` and
// `expiresAt` to control visibility; the time-of-day scheduling adds
// surprise and we'd rather show the banner consistently than hide it
// for opaque reasons.
//
// If a future use case requires time-of-day restrictions, re-enable
// the filter ONLY with the "single-banner fallback" rule: if only one
// banner matches the (placement, subcategoryId) query, ignore the
// schedule filter so the user never sees an empty section where a
// banner exists in Firestore.
//
// ignore: unused_element
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
