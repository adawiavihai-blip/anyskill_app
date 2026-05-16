import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/banner_model.dart';
import '../screens/expert_profile_screen.dart';
import '../utils/safe_image_provider.dart';

/// Customer-facing runtime widget for a `provider_carousel`-typed
/// banner — rendered inside the home-tab promo carousel slot.
///
/// Responsibilities (§49 Phase-6):
///   1. Fetches the configured providers from `users` (batched in 10s
///      because Firestore `whereIn` caps at 10 values).
///   2. Auto-rotates every `rotationDurationMs` via a single Timer;
///      AnimationController drives the progress bar at 60fps through
///      an AnimatedBuilder scoped to the bar (card itself never
///      rebuilds on animation ticks).
///   3. Cross-fades between providers (350ms). slide/zoom/flip are
///      accepted from the admin config but fall back to fade — full
///      transition set is a future enhancement.
///   4. Interactions:
///        - Tap card      → push [ExpertProfileScreen] for current provider
///        - Long-press    → toggle pause (resumes on release+re-tap)
///        - Horizontal drag → previous / next (resets the timer)
///   5. Honest about data: if zero providers resolve (deleted accounts,
///      hidden users) the widget collapses to an empty SizedBox so the
///      outer carousel doesn't leave a dead tile.
///
/// Smart ordering (§49 Phase-7):
///   When `sortMode == ai`, the widget fires a background call to the
///   `smartProviderOrder` Cloud Function after the initial provider
///   fetch. The CF caches per (uid, bannerId) for 1 hour, so repeat
///   mounts within an hour cost 0 Gemini tokens. The initial render
///   uses the admin-picked order (instant); if the CF returns a valid
///   reordered list, the widget quietly re-lays out into the new
///   order. All failure paths keep the initial order.
class ProviderCarouselBanner extends StatefulWidget {
  const ProviderCarouselBanner({
    super.key,
    required this.config,
    required this.title,
    this.sectionHeading,
    this.bannerId = '',
    this.height = 190,
    this.onImpression,
    this.onClick,
  });

  final ProviderCarouselConfig config;
  final String title;

  /// Optional bold section heading rendered ABOVE the carousel card.
  /// Hidden during loading + empty states so the user never sees an
  /// orphaned "VIP providers" title floating over a grey skeleton box.
  final String? sectionHeading;

  /// Firestore doc id of the owning banner — used as the cache key
  /// for the `smartProviderOrder` CF so the same user + same banner
  /// reuses the AI order within the 1-hour TTL.
  final String bannerId;

  final double height;

  /// Called each time a new card becomes visible. Parent is expected
  /// to increment `banners/{id}.impressions` (batched / debounced).
  final ValueChanged<String>? onImpression;

  /// Called when the user taps through to a profile. Parent should
  /// increment `banners/{id}.clicks`.
  final ValueChanged<String>? onClick;

  @override
  State<ProviderCarouselBanner> createState() =>
      _ProviderCarouselBannerState();
}

class _ProviderCarouselBannerState extends State<ProviderCarouselBanner>
    with SingleTickerProviderStateMixin {
  late final Future<List<_RuntimeProvider>> _providersFuture;
  late AnimationController _progressCtrl;
  Timer? _rotationTimer;

  int _index = 0;
  bool _paused = false;
  bool _started = false;

  /// When the `smartProviderOrder` CF returns a valid (non-fallback)
  /// permutation, this holds the uid-ordered list. `null` means no
  /// override — caller should use the natural `_fetchProviders` order.
  List<String>? _aiOverrideIds;

  /// The uids that are ACTUALLY rendered on screen (in display order
  /// after sortMode + ai override). Set from `_syncResolvedIds` after
  /// the FutureBuilder lands. This is the single source of truth for
  /// both rotation math and impression firing — using
  /// `widget.config.providerIds` directly was a bug: if admin configured
  /// 5 providers but only 1 exists in `users`, the carousel always
  /// shows that 1 but `_advance` would still cycle `_index` 0..4 and
  /// fire impressions for ghost uids that were never displayed.
  List<String> _resolvedIds = const [];

  /// In-memory dedup: each uid gets AT MOST ONE impression per widget
  /// mount. Without this, the rotation timer fires `_fireImpression`
  /// every `rotationDurationMs` (default 3s) — a user who keeps the
  /// home tab open for 30s would inflate impressions ~10x even for the
  /// same provider. Clicks were always accurate (1:1 with taps),
  /// impressions were not — this restores symmetry.
  final Set<String> _firedImpressions = {};

  @override
  void initState() {
    super.initState();
    _providersFuture = _fetchProviders(widget.config.providerIds);
    _progressCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.config.rotationDurationMs),
    );
  }

  @override
  void didUpdateWidget(covariant ProviderCarouselBanner old) {
    super.didUpdateWidget(old);
    if (old.config.rotationDurationMs !=
        widget.config.rotationDurationMs) {
      _progressCtrl.duration =
          Duration(milliseconds: widget.config.rotationDurationMs);
      if (_started && !_paused) _restart();
    }
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _progressCtrl.dispose();
    super.dispose();
  }

  // ── Data fetching (whereIn batched in 10s) ───────────────────────

  Future<List<_RuntimeProvider>> _fetchProviders(
      List<String> ids) async {
    if (ids.isEmpty) return const [];
    try {
      final out = <String, _RuntimeProvider>{};
      // §15 Law 15 — each `.get()` chunk gets a 5s timeout. Without it,
      // a zombie WebChannel on iOS Safari would leave the FutureBuilder
      // in waiting state indefinitely → `_skeleton()` 190px grey square
      // visible forever where the VIP banner should be. With timeout,
      // a hung chunk throws and the catch below returns an empty list,
      // which collapses the banner to SizedBox.shrink (build line 387).
      for (var i = 0; i < ids.length; i += 10) {
        final chunk = ids.sublist(i, (i + 10).clamp(0, ids.length));
        final qs = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get()
            .timeout(const Duration(seconds: 5));
        for (final d in qs.docs) {
          out[d.id] = _RuntimeProvider.fromDoc(d);
        }
      }

      // 2026-05-15 — Roi's report: "providers with gallery images
      // should sync into the banner — 3 slots". For providers whose
      // user-doc gallery is empty (legacy dual-identity providers
      // who only saved via the listings path, or pre-§10.8.0
      // accounts), fall back to `provider_listings`. Batched query —
      // 1 extra round-trip per chunk-of-10, only when needed.
      final missingGalleryUids = out.entries
          .where((e) => e.value.galleryUrls.isEmpty)
          .map((e) => e.key)
          .toList();
      if (missingGalleryUids.isNotEmpty) {
        try {
          for (var i = 0; i < missingGalleryUids.length; i += 10) {
            final chunk = missingGalleryUids.sublist(
                i, (i + 10).clamp(0, missingGalleryUids.length));
            final lqs = await FirebaseFirestore.instance
                .collection('provider_listings')
                .where('uid', whereIn: chunk)
                .where('identityIndex', isEqualTo: 0)
                .limit(10)
                .get()
                .timeout(const Duration(seconds: 4));
            for (final d in lqs.docs) {
              final data = d.data();
              final uid = data['uid'] as String? ?? '';
              if (uid.isEmpty) continue;
              final existing = out[uid];
              if (existing == null || existing.galleryUrls.isNotEmpty) continue;
              final rawGallery = (data['gallery'] as List?) ?? const [];
              final urls = rawGallery.whereType<String>().toList();
              if (urls.isEmpty) continue;
              // Replace the runtime provider with one that includes
              // the listing's gallery — keep all other fields.
              out[uid] = existing.copyWithGallery(urls);
            }
          }
          debugPrint(
              '[ProviderCarouselBanner] Listing-gallery fallback filled ${missingGalleryUids.length} provider(s)');
        } catch (e) {
          debugPrint(
              '[ProviderCarouselBanner] Listing-gallery fallback failed (continuing without): $e');
        }
      }

      // Preserve the admin-picked order BEFORE any sortMode transform.
      final ordered = [
        for (final id in ids)
          if (out[id] != null) out[id]!,
      ];
      final base = _applySortMode(ordered);
      // Fire-and-forget AI reorder when sortMode==ai. The UI renders
      // `base` first; if the CF returns a valid permutation, the
      // widget re-lays out into the override list (see build flow).
      if (widget.config.sortMode == ProviderSortMode.ai &&
          base.length >= 2) {
        // Don't block the future on this — the initial render should
        // be instant on the admin-picked order.
        unawaited(_requestAiOrder(base.map((p) => p.uid).toList()));
      }
      return base;
    } catch (e) {
      debugPrint('[ProviderCarouselBanner] _fetchProviders failed: $e');
      return const [];
    }
  }

  List<_RuntimeProvider> _applySortMode(List<_RuntimeProvider> list) {
    switch (widget.config.sortMode) {
      case ProviderSortMode.manual:
      case ProviderSortMode.ai:
        // `ai` uses the admin-picked order as the initial render.
        // The `_requestAiOrder` background call replaces it with the
        // Gemini-resolved permutation when it lands — see
        // `_applyAiOverride` in the build flow.
        return list;
      case ProviderSortMode.random:
        final shuffled = [...list]..shuffle();
        return shuffled;
      case ProviderSortMode.rating:
        return [...list]..sort((a, b) => b.rating.compareTo(a.rating));
    }
  }

  /// Calls the `smartProviderOrder` Cloud Function with the signed-in
  /// user's context and applies the returned permutation on success.
  ///
  /// Silent on every failure — the widget keeps the admin-picked order
  /// so the Gemini integration never breaks the user experience.
  Future<void> _requestAiOrder(List<String> baseIds) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return; // Anonymous viewers skip AI personalization.

      final result = await FirebaseFunctions.instance
          .httpsCallable('smartProviderOrder')
          .call({
        'providerIds': baseIds,
        'bannerId': widget.bannerId,
      });
      final data = (result.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['fallback'] == true) return;
      final raw = (data['orderedIds'] as List?) ?? const [];
      final orderedIds = raw.whereType<String>().toList();

      // Integrity: must be a permutation of baseIds (same set, same length).
      if (orderedIds.length != baseIds.length) return;
      final baseSet = baseIds.toSet();
      for (final id in orderedIds) {
        if (!baseSet.contains(id)) return;
      }

      if (!mounted) return;
      // Reset index to 0 so the user sees the new "best match" first,
      // and restart the progress bar cleanly on the new head card.
      setState(() {
        _aiOverrideIds = orderedIds;
        _index = 0;
      });
      if (_started && !_paused) {
        _progressCtrl
          ..reset()
          ..forward();
        // The reorder swapped the visible head card — count it as an
        // impression for the new top provider. Deferred to post-frame
        // so `_syncResolvedIds` (which runs in build) has updated
        // `_resolvedIds` to the new order before we read from it.
        // Without this, `_fireImpression` would fire for the OLD
        // resolved[0] uid.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fireImpression();
        });
      }
    } catch (_) {
      // Swallow — CF errors are logged server-side; the UX stays
      // on the initial admin-picked order.
    }
  }

  /// Applies the AI-supplied permutation over a resolved provider list.
  /// Returns the input unchanged when no override is set or the
  /// override doesn't cover the same set (cache race, etc.).
  List<_RuntimeProvider> _applyAiOverride(List<_RuntimeProvider> list) {
    final override = _aiOverrideIds;
    if (override == null || override.length != list.length) return list;
    final byId = {for (final p in list) p.uid: p};
    final out = <_RuntimeProvider>[];
    for (final id in override) {
      final p = byId[id];
      if (p == null) return list; // unexpected mismatch → keep base
      out.add(p);
    }
    return out;
  }

  // ── Rotation control ─────────────────────────────────────────────

  /// Re-syncs `_resolvedIds` from the FutureBuilder's resolved `data`.
  /// Must be called in build (before the post-frame callback) so that
  /// `_fireImpression` + `_advance` see the correct uid list, including
  /// after an AI reorder swap.
  void _syncResolvedIds(List<_RuntimeProvider> data) {
    if (data.length != _resolvedIds.length) {
      _resolvedIds = data.map((p) => p.uid).toList(growable: false);
      return;
    }
    for (var i = 0; i < data.length; i++) {
      if (data[i].uid != _resolvedIds[i]) {
        _resolvedIds = data.map((p) => p.uid).toList(growable: false);
        return;
      }
    }
  }

  void _maybeStart(int count) {
    if (_started || count < 1) return;
    _started = true;
    // Fire impression for the FIRST visible provider too — without this,
    // single-provider banners and the very first card of a multi-card
    // banner never get counted (§51 follow-up: VIP stats stuck at 0).
    _fireImpression();
    _restart();
  }

  /// Records one impression for the currently-visible provider, DEDUPED
  /// per widget mount. Each uid fires AT MOST ONCE per mount — without
  /// this, the rotation timer inflated counts ~10x because every
  /// rotation tick (every 3s by default) refired for the same provider.
  /// Uses `_resolvedIds` (actually-rendered uids), not
  /// `widget.config.providerIds` — ghost uids that don't exist in
  /// `users` are never displayed, so they must never be counted.
  void _fireImpression() {
    if (widget.onImpression == null) return;
    final ids = _resolvedIds;
    if (ids.isEmpty) return;
    final uid = ids[_index % ids.length];
    if (_firedImpressions.contains(uid)) return;
    _firedImpressions.add(uid);
    widget.onImpression!(uid);
  }

  void _restart() {
    _rotationTimer?.cancel();
    _progressCtrl.reset();
    if (_paused) return;
    // Banners Studio §51 — when only 1 RESOLVED provider, skip rotation
    // entirely. The static card stays visible. Using `_resolvedIds`
    // (not `config.providerIds`) so a banner with ghost uids — admin
    // configured 5, only 1 exists in `users` — also goes static instead
    // of spinning through invisible cards.
    if (_resolvedIds.length < 2) return;
    _progressCtrl.forward();
    _rotationTimer = Timer.periodic(
      Duration(milliseconds: widget.config.rotationDurationMs),
      (_) {
        if (!mounted) return;
        _advance(1);
      },
    );
  }

  void _advance(int delta) {
    // Count is the resolved (actually-rendered) list, not the admin's
    // configured list — see `_syncResolvedIds` doc on _resolvedIds.
    final count = _resolvedIds.length;
    if (count < 2) return;
    setState(() {
      _index = (_index + delta + count) % count;
    });
    _progressCtrl
      ..reset()
      ..forward();
    // Notify parent — dedupe inside `_fireImpression` ensures a single
    // user can never inflate the same provider's impressions past 1
    // per mount, no matter how long the rotation runs.
    _fireImpression();
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (_paused) {
      _rotationTimer?.cancel();
      _progressCtrl.stop();
    } else {
      _restart();
    }
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_RuntimeProvider>>(
      future: _providersFuture,
      builder: (context, snap) {
        // Apply any AI permutation on top of the resolved list.
        final data = _applyAiOverride(snap.data ?? const <_RuntimeProvider>[]);

        // Keep _resolvedIds in sync with whatever's actually on screen.
        // Safe to mutate state directly here (not via setState) because
        // _resolvedIds doesn't drive the visual tree — it's bookkeeping
        // for rotation math + impression firing.
        if (snap.connectionState == ConnectionState.done) {
          _syncResolvedIds(data);
        }

        // Start the timer once we know the count.
        if (snap.connectionState == ConnectionState.done) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _maybeStart(_resolvedIds.length);
          });
        }

        // While loading OR no resolved providers, collapse the entire
        // section (title + card) so the home tab never shows a stranded
        // section heading above an empty placeholder. The user reported
        // a "grey square" in this slot — that was the legacy skeleton
        // sitting under the title with no content. SizedBox.shrink fixes
        // both loading and empty states cleanly.
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        if (data.isEmpty) {
          return const SizedBox.shrink();
        }

        final current = data[_index % data.length];

        final card = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _onCardTap(current),
          onLongPress: _togglePause,
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v == 0) return;
            // RTL: swipe → right in logical LTR is "back" for RTL
            // readers, but users expect forward to dismiss. We honor
            // finger direction: +velocity (right swipe in LTR, which
            // is left-to-right finger motion) → next in the RTL
            // reading direction.
            _advance(v > 0 ? 1 : -1);
          },
          child: Container(
            height: widget.height,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _content(current, data.length)),
              ],
            ),
          ),
        );

        // Wrap with section heading only when data resolved successfully,
        // so the title is in lockstep with content visibility.
        final heading = widget.sectionHeading;
        if (heading == null || heading.isEmpty) return card;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(0, 10, 0, 4),
              child: Text(
                heading,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827),
                ),
              ),
            ),
            SizedBox(height: widget.height, child: card),
          ],
        );
      },
    );
  }

  Widget _content(_RuntimeProvider current, int total) {
    final display = widget.config.display;
    final showGallery =
        display.showGallery && widget.height >= 190 && display.galleryCount > 0;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: Column(
        key: ValueKey(current.uid),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _headerRow(current),
          if (showGallery) ...[
            const SizedBox(height: 8),
            Flexible(child: _gallery(current)),
          ],
          const SizedBox(height: 8),
          _cta(),
          const SizedBox(height: 6),
          _dots(total),
        ],
      ),
    );
  }

  Widget _headerRow(_RuntimeProvider p) {
    final display = widget.config.display;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (display.showProfilePic) ...[
          _avatar(p),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      p.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A2E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (p.isVerified) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.verified_rounded,
                      size: 12,
                      color: Color(0xFF3B82F6),
                    ),
                  ],
                ],
              ),
              if (display.showCategory && p.serviceType.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(
                  p.serviceType,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF6B7280)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (display.showRating || display.showAvailability) ...[
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (display.showRating) ...[
                      const Icon(Icons.star_rounded,
                          size: 12, color: Color(0xFFBA7517)),
                      const SizedBox(width: 2),
                      Text(
                        p.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      if (p.reviewsCount > 0) ...[
                        const SizedBox(width: 3),
                        Text(
                          '(${p.reviewsCount})',
                          style: const TextStyle(
                              fontSize: 10, color: Color(0xFFA1A1AA)),
                        ),
                      ],
                    ],
                    if (display.showRating && display.showAvailability)
                      const SizedBox(width: 6),
                    if (display.showAvailability)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5EE),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          p.isOnline ? 'זמין עכשיו' : 'זמין היום',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F7A4D),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _avatar(_RuntimeProvider p) {
    final img = safeImageProvider(p.profileImage);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFE4E4E7),
            image: img == null
                ? null
                : DecorationImage(image: img, fit: BoxFit.cover),
          ),
          alignment: Alignment.center,
          child: img == null
              ? Text(
                  p.initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : null,
        ),
        if (p.isOnline)
          PositionedDirectional(
            bottom: -1,
            end: -1,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF22C55E),
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _gallery(_RuntimeProvider p) {
    final count = widget.config.display.galleryCount.clamp(1, 3);
    return Row(
      children: [
        for (int i = 0; i < count; i++) ...[
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: _galleryTile(p, i),
            ),
          ),
          if (i < count - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }

  Widget _galleryTile(_RuntimeProvider p, int i) {
    final url = i < p.galleryUrls.length ? p.galleryUrls[i] : '';
    final img = safeImageProvider(url);
    return Container(
      decoration: BoxDecoration(
        color: _galleryFallback(i),
        image: img == null
            ? null
            : DecorationImage(image: img, fit: BoxFit.cover),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }

  Color _galleryFallback(int i) {
    const palette = [
      Color(0xFFEDE9FE),
      Color(0xFFFCE7F3),
      Color(0xFFDCFCE7),
    ];
    return palette[i % palette.length];
  }

  // Glass pill CTA — mirrors the "חיפוש דחוף" bottom-nav button styling:
  // ClipRRect + BackdropFilter.blur(20) + white-tinted bg + white border +
  // black-indigo text + soft drop shadow + inner top highlight. On a white
  // parent card the blur is effectively cosmetic but the border+shadow
  // still read as a crisp pill. Padding/font-weight match the urgent-search
  // button; font-size is kept at 13 (same as search).
  Widget _cta() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 22,
            vertical: 11,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.55),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          // inner top highlight (CSS: inset 0 1px 0 rgba(255,255,255,.2))
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: const Border(
              top: BorderSide(color: Color(0x33FFFFFF), width: 1),
            ),
          ),
          child: const Text(
            'צפה בפרופיל ←',
            textDirection: TextDirection.rtl,
            style: TextStyle(
              color: Color(0xFF1E1B4B),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _dots(int count) {
    if (count < 2) return const SizedBox(height: 4);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < count; i++) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            width: i == (_index % count) ? 14 : 3,
            height: 3,
            decoration: BoxDecoration(
              color: i == (_index % count)
                  ? const Color(0xFF1A1A2E)
                  : const Color(0x240A0A0A),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (i < count - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }

  // Note: legacy `_skeleton()` (light-grey 190px placeholder) removed
  // 2026-05-14 — it was the "grey square" users reported seeing in
  // place of the VIP banner when `_fetchProviders` hung on a zombie
  // WebChannel. Loading + empty states now both return SizedBox.shrink
  // so the entire section (title + card) collapses cleanly.

  // ── Navigation ───────────────────────────────────────────────────

  void _onCardTap(_RuntimeProvider p) {
    if (widget.onClick != null) widget.onClick!(p.uid);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExpertProfileScreen(
          expertId: p.uid,
          expertName: p.name,
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
//  Internal: runtime provider view
// ═════════════════════════════════════════════════════════════════════

class _RuntimeProvider {
  const _RuntimeProvider({
    required this.uid,
    required this.name,
    required this.serviceType,
    required this.profileImage,
    required this.rating,
    required this.reviewsCount,
    required this.isVerified,
    required this.isOnline,
    required this.galleryUrls,
  });

  final String uid;
  final String name;
  final String serviceType;
  final String profileImage;
  final double rating;
  final int reviewsCount;
  final bool isVerified;
  final bool isOnline;
  final List<String> galleryUrls;

  factory _RuntimeProvider.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final rawGallery = (d['gallery'] as List?) ?? const [];
    return _RuntimeProvider(
      uid: doc.id,
      name: (d['name'] as String?) ?? '(ללא שם)',
      serviceType: (d['serviceType'] as String?) ?? '',
      profileImage: (d['profileImage'] as String?) ?? '',
      rating: (d['rating'] as num?)?.toDouble() ?? 0,
      reviewsCount: (d['reviewsCount'] as num?)?.toInt() ?? 0,
      isVerified: d['isVerified'] as bool? ?? false,
      isOnline: d['isOnline'] as bool? ?? false,
      galleryUrls: rawGallery.whereType<String>().toList(),
    );
  }

  /// Returns a copy with replacement gallery — used by the listings
  /// fallback in `_fetchProviders` to fill in gallery URLs for
  /// providers whose user-doc gallery is empty (post-§10.1.0
  /// dual-identity providers who only saved via the listings path).
  _RuntimeProvider copyWithGallery(List<String> newGallery) {
    return _RuntimeProvider(
      uid: uid,
      name: name,
      serviceType: serviceType,
      profileImage: profileImage,
      rating: rating,
      reviewsCount: reviewsCount,
      isVerified: isVerified,
      isOnline: isOnline,
      galleryUrls: newGallery,
    );
  }

  String get initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0].characters.take(2).toString();
    return '${parts[0].characters.first}${parts.last.characters.first}';
  }
}
