// B.2 (§80 follow-up, 2026-05-14): the 13 helper widgets at the bottom of
// this file moved to category_results/widgets/category_results_widgets.dart.
// They stay private (`_XxxWidget`) and reachable thanks to the `part` directive.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/favorite_button.dart';
import '../widgets/pro_badge.dart';
import 'expert_profile_screen.dart';
import '../utils/expert_filter.dart';
import '../services/location_service.dart';
import '../services/search_ranking_service.dart';
import '../services/volunteer_service.dart';
import '../services/category_service.dart';
import '../widgets/community/heart_display_helper.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../widgets/category_specs_widget.dart';
import '../widgets/search_card_price_pill.dart';
import '../services/cached_readers.dart';
import '../widgets/level_badge.dart';
import '../constants/quick_tags.dart';
import '../widgets/provider_category_tags_display.dart';
import '../l10n/app_localizations.dart';
import 'search_screen/widgets/stories_row.dart';
import '../utils/safe_image_provider.dart';
import 'support_center_screen.dart';
import 'chat_screen.dart';
import 'alex_profile_screen.dart';
import '../services/provider_listing_service.dart';
import '../widgets/providers_map_view.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_theme.dart';
import '../widgets/dynamic_filter_sheet.dart';
import '../widgets/subcategory_banner_header.dart';
import '../models/filter_schema.dart';
import '../models/motorcycle_tow_profile.dart';
import '../models/babysitter_profile.dart';
import '../models/delivery_profile.dart';
import '../services/filter_schema_service.dart';
import 'flash_auction/flash_auction_issue_screen.dart';
import 'babysitter_emergency/babysitter_emergency_details_screen.dart';
import 'delivery_express/delivery_express_package_screen.dart';

part 'category_results/widgets/category_results_widgets.dart';

// Brand colours (shared with the rest of the app)
const _kPurple     = Color(0xFF6366F1);
const _kPurpleSoft = Color(0xFFF0F0FF);
const _kGold       = Color(0xFFFBBF24);

/// Synthetic AI teacher injected into the English (אנגלית) category.
const _kAlexAiTeacher = <String, dynamic>{
  'uid':          'ai_teacher_alex',
  'name':         'Alex',
  'aboutMe':      'מורה AI מקצועי לאנגלית מבית D-ID',
  'profileImage': null,
  'rating':       5.0,
  'reviewsCount': 128,
  'pricePerHour': 30,
  'isVerified':   true,
  'isOnline':     true,
  'isAiTeacher':  true,
  'isPromoted':   false,
  'isDemo':       false,
  'serviceType':  'אנגלית',
  'xp':           0,
};

class CategoryResultsScreen extends StatefulWidget {
  final String categoryName;

  /// כאשר true — מציג רק נותני שירות עם isVolunteer==true (קהילה).
  final bool volunteerOnly;

  /// זרם אופציונלי — מוזרק בבדיקות במקום Firestore האמיתי.
  /// בסביבת ייצור תמיד null (נשתמש ב-Firestore).
  final Stream<List<Map<String, dynamic>>>? testStream;

  const CategoryResultsScreen({
    super.key,
    required this.categoryName,
    this.volunteerOnly = false,
    this.testStream,
  });

  @override
  State<CategoryResultsScreen> createState() => _CategoryResultsScreenState();
}

class _CategoryResultsScreenState extends State<CategoryResultsScreen> {
  String _searchQuery    = '';
  bool   _filterUnder100 = false;
  double _minRating      = 0;        // 0 = no filter, 3/4/4.5 = minimum stars
  double? _maxDistanceKm;            // null = no radius limit
  // v12.9.0: Map filter chips
  // "🟢 זמינים עכשיו" — defaults to TRUE so the map only ever shows
  // providers available RIGHT NOW (2026-05-16, user request). The user
  // can still toggle the chip off to also see offline providers.
  bool   _onlineOnly     = true;

  // v12.9.0 (PR-5): Map bottom-sheet carousel state
  final PageController _mapPageCtrl =
      PageController(viewportFraction: 0.88);
  String? _mapSelectedUid;
  LatLng? _mapFocusedLatLng;
  bool   _showAdvancedFilters = false;
  Position? _currentPosition;

  // ── Dynamic filter system (CLAUDE.md §50) ─────────────────────────────────
  // Stage 5: filterExperts() now consumes both the schema (for providerField
  // resolution) and the active filters map. Schema is loaded once on initState
  // and cached for 30 min by FilterSchemaService.
  Map<String, dynamic> _dynamicFilters = {};
  FilterSchema? _filterSchema;

  // v9.9.0: Map/List toggle
  bool _showMap = false;

  /// Returns the display label for community badges on search cards.
  static String _communityBadgeLabel(Map<String, dynamic> data, BuildContext ctx) {
    final badges = data['communityBadges'] as List<dynamic>?;
    final l = AppLocalizations.of(ctx);
    if (badges != null && badges.contains('angel')) return l.catBadgeAngel;
    if (badges != null && badges.contains('pillar')) return l.catBadgePillar;
    return l.catBadgeVolunteer;
  }

  // ── Pagination state ───────────────────────────────────────────────────────
  static const int _kPageSize = 15;

  final List<Map<String, dynamic>> _allExperts = [];
  bool _isLoading     = true;
  bool _isLoadingMore = false;
  bool _hasMore       = true;
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;

  /// Background retry timer — fires every 10s after a failed fetch so
  /// the screen self-heals when the user's network recovers, WITHOUT
  /// ever showing them an alarming error scaffold. Cancelled on dispose
  /// and on successful load.
  Timer? _backgroundRetryTimer;

  /// True once the one-time failed/empty-load retry has run — guards the
  /// periodic 10s background retry from re-retrying in a tight loop.
  bool _bounceUsed = false;

  /// Full v2 ServiceSchema (depositPercent / priceLocked / bundles /
  /// surcharge / fields). Used by [SearchCardPricePill] to render the
  /// price + transparency badges below it (§62). Cached for 30 min via
  /// CachedReaders.
  ///
  /// Replaced the legacy `_categorySchema` v1 fields-list — `_serviceSchema.fields`
  /// is the same data and works for both v1 and v2 schema shapes.
  ServiceSchema _serviceSchema = ServiceSchema.empty();

  late final ScrollController _scrollCtrl;

  /// When true, [_fetchPage] skips the `isVerified == false` and
  /// `isHidden == true` filters — admins must be able to see every
  /// provider in a sub-category (including pending verifications and
  /// hidden demos) so they can verify / manage them from the listing.
  bool _isAdminViewer = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController()..addListener(_onScroll);
    // Resolve the admin flag BEFORE the first page load so the page-
    // level filter decisions are correct from the very first paint.
    // Cached 5 min by CachedReaders, so this is typically <1ms on
    // any tab return.
    _detectAdminAndLoad();
    // §62: load the full v2 schema so the price pill can show transparency
    // badges (depositPercent / priceLocked / bundles / surcharge) below
    // the price. Cached 30 min via CachedReaders. Replaces the prior
    // `loadSchemaForCategory` v1-only call which only loaded fields[].
    CachedReaders.serviceSchemaForCategory(widget.categoryName).then((s) {
      if (mounted) setState(() => _serviceSchema = s);
    });
    // Load FilterSchema for DynamicFilterSheet (CLAUDE.md §50, stage 5).
    // 30-min cache via FilterSchemaService — fire-and-forget is safe.
    FilterSchemaService.instance
        .getSchema(widget.categoryName)
        .then((schema) {
      if (mounted) setState(() => _filterSchema = schema);
    });
    // Use cached position instantly; fall back to a dialog-based request,
    // and retry once after 1.5s if the first attempt returns null (web
    // browsers sometimes need a beat to resolve permission state).
    final cached = LocationService.cached;
    if (cached != null) {
      _currentPosition = cached;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        Position? pos;
        try {
          pos = await LocationService.requestAndGet(context);
          // ignore: avoid_print
          print('[CategoryResults/distance] requestAndGet (attempt 1) = '
              '${pos == null ? "null" : "(${pos.latitude}, ${pos.longitude})"}');
        } catch (e) {
          // ignore: avoid_print
          print('[CategoryResults/distance] requestAndGet threw: $e');
        }
        if (pos == null && mounted) {
          await Future.delayed(const Duration(milliseconds: 1500));
          if (!mounted) return;
          try {
            pos = await LocationService.getIfGranted();
            // ignore: avoid_print
            print('[CategoryResults/distance] getIfGranted (attempt 2) = '
                '${pos == null ? "null" : "(${pos.latitude}, ${pos.longitude})"}');
          } catch (_) {/* swallowed — keep null */}
        }
        if (mounted && pos != null) setState(() => _currentPosition = pos);
      });
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _mapPageCtrl.dispose();
    _backgroundRetryTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent * 0.85) {
      _loadMore();
    }
  }

  /// Resolves the viewer's `isAdmin` flag IN PARALLEL with the first
  /// page load. The race-safe pattern (replacing v15.x serial-await):
  ///
  ///   1. Kick off `_loadInitial()` IMMEDIATELY with `_isAdminViewer =
  ///      false` so the page never blocks on a slow network read.
  ///   2. Concurrently fire the admin-detection read with a 2-second
  ///      hard timeout (Firestore SDK has NO built-in timeout — a
  ///      zombie WebChannel on iOS Safari / flaky network would
  ///      otherwise hang here forever).
  ///   3. If admin status flips to true AFTER the first page rendered,
  ///      `_loadInitial()` is called again to re-fetch with the admin
  ///      filter set (so demos / unverified providers materialize).
  ///
  /// Previously this was a serial `await detect → setState → load`.
  /// On a slow first-time visit (cold cache) the page either hung on
  /// the spinner forever (no timeout) OR silently fell through to
  /// `_isAdminViewer = false` on a transient throw — which hid every
  /// demo / pending-verification provider from admin view. The
  /// inconsistency-by-network-quality is what produced the user-
  /// visible "sometimes I see them, sometimes I don't" symptom.
  Future<void> _detectAdminAndLoad() async {
    // Phase 1 — start the page load immediately so the user gets
    // SOMETHING on screen within the network's first response, even
    // if admin status hasn't resolved yet.
    unawaited(_loadInitial());

    // Phase 2 — race the admin-detection read against a 2s timeout.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    Map<String, dynamic> data;
    try {
      data = await CachedReaders.providerProfile(uid).timeout(
        const Duration(seconds: 2),
      );
    } catch (_) {
      // Network timeout / permission-denied / etc. → re-fetch with a
      // longer timeout in the background. We DON'T re-throw; the
      // first-page render is already safe with `_isAdminViewer = false`.
      try {
        data = await CachedReaders.providerProfile(uid).timeout(
          const Duration(seconds: 8),
        );
      } catch (_) {
        // Both attempts failed — admin will see the non-admin filter
        // until they pull-to-refresh. Acceptable degradation.
        return;
      }
    }
    if (!mounted) return;
    if (data['isAdmin'] == true && !_isAdminViewer) {
      setState(() {
        _isAdminViewer = true;
        // Reset pagination so [_loadInitial] re-fetches the FIRST page
        // with the admin filter set (demos + unverified providers now
        // visible). The currently-rendered list is wiped before the
        // refetch via the setState inside [_loadInitial] itself.
        _lastDoc = null;
        _hasMore = true;
      });
      unawaited(_loadInitial());
    }
  }

  Future<void> _loadInitial() async {
    // CRITICAL UX: only show the spinner overlay when we have NO data
    // yet. On pull-to-refresh, keep the existing providers visible so
    // the user never sees a blank screen + spinner — they keep seeing
    // the old list and it replaces in-place when the new fetch resolves.
    // This was the root of the "stuck on spinner" complaint from
    // רועי צברי (2026-05-14): every refresh wiped the visible providers
    // and showed a centered spinner over an empty screen.
    final bool firstLoad = _allExperts.isEmpty;
    setState(() {
      if (firstLoad) _isLoading = true;
      _lastDoc = null;
      _hasMore = true;
    });
    // Cancel any pending background retry — a new explicit load
    // supersedes it.
    _backgroundRetryTimer?.cancel();
    // Single attempt with 12s timeout, then a brief retry. Total ~25s.
    const backoffs = [Duration(seconds: 0), Duration(seconds: 3)];
    List<Map<String, dynamic>>? successPage;
    for (int attempt = 0; attempt < backoffs.length; attempt++) {
      if (attempt > 0) {
        await Future.delayed(backoffs[attempt]);
        if (!mounted) return;
      }
      try {
        final page = await _fetchPage();
        successPage = page;
        break;
      } catch (e) {
        debugPrint('⚠️ _loadInitial attempt ${attempt + 1} error: $e');
        if (!mounted) return;
        _lastDoc = null;
      }
    }
    if (!mounted) return;

    // ── Failed/empty first-load retry (2026-05-15, רועי צברי) ───────────
    // A sub-category that comes back empty/stalled on the first try is
    // often a transient strained-channel read, not a genuinely empty
    // category — so retry the fetch ONCE.
    //
    // ⚠️ This used to disableNetwork()/enableNetwork() before the retry.
    // REMOVED 2026-05-16 — that "bounce" is GLOBAL (it kills every
    // Firestore listener in the whole app) and, fired from this and two
    // other screens on independent timers, cascaded across provider/
    // admin sessions: each bounce broke notifications, banners and every
    // other screen's streams. See home_screen.dart for the full
    // rationale. A plain re-fetch is the safe replacement.
    final loadFailed =
        successPage == null || (firstLoad && successPage.isEmpty);
    if (loadFailed && !_bounceUsed) {
      _bounceUsed = true;
      try {
        _lastDoc = null;
        successPage = await _fetchPage();
        debugPrint(
            '[CategoryResults] Retry fetch: ${successPage.length} result(s)');
      } catch (e) {
        debugPrint('[CategoryResults] Retry fetch error: $e');
        if (!mounted) return;
      }
    }

    if (successPage != null) {
      setState(() {
        // Replace the old list ATOMICALLY with the new one — no flash
        // of "empty" between clear() and addAll().
        _allExperts
          ..clear()
          ..addAll(successPage!);
        _isLoading = false;
      });
      // Safety net: if the FIRST fetch (even after the bounce) came
      // back empty, schedule ONE quick background re-check at ~4s.
      // Genuinely-empty sub-categories are unaffected (the retry
      // re-reads and stays empty, silently). Providers briefly
      // invisible due to a strained channel materialize WITHOUT the
      // user having to manually refresh.
      if (firstLoad && successPage.isEmpty) {
        _backgroundRetryTimer?.cancel();
        _backgroundRetryTimer = Timer(const Duration(seconds: 4), () {
          if (!mounted) return;
          if (_allExperts.isEmpty) _loadInitial();
        });
      }
      return;
    }
    // Both attempts failed. Don't show a scary "בעיית חיבור" error.
    // Just leave _allExperts empty + _hasMore=false so the neutral
    // "no providers in this category" copy renders, AND schedule a
    // SILENT background retry every 10s so the screen self-heals
    // when the user's network recovers.
    setState(() {
      _isLoading = false;
      if (firstLoad) _hasMore = false;
    });
    _backgroundRetryTimer = Timer.periodic(const Duration(seconds: 10),
        (_) {
      if (!mounted) {
        _backgroundRetryTimer?.cancel();
        return;
      }
      // Try once silently. On success the timer is cancelled at the
      // top of _loadInitial (so no double-fire) and the list updates.
      _loadInitial();
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _isLoading) return;
    setState(() => _isLoadingMore = true);
    try {
      final page = await _fetchPage();
      if (!mounted) return;
      setState(() {
        _allExperts.addAll(page);
        _isLoadingMore = false;
      });
    } catch (e) {
      debugPrint('⚠️ _loadMore error: $e');
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  /// Fetches the next page of experts using Firestore cursor pagination.
  /// Applies isVerified / isHidden client-side filters to each page.
  ///
  /// Two-query strategy (v9.4.1):
  ///   1. Primary: `serviceType == categoryName` (exact match)
  ///   2. Fallback: `parentCategory == categoryName` (sub-cat providers
  ///      whose serviceType is the sub-cat name, not the parent name)
  ///
  /// This ensures tapping a PARENT category shows providers registered
  /// under any of its sub-categories, as well as directly under the parent.
  Future<List<Map<String, dynamic>>> _fetchPage() async {
    try {
      // ── v10.5.1: Query provider_listings instead of users ─────────────
      // Each listing is a separate professional identity. A provider with
      // 2 identities appears as 2 separate cards, each with its own
      // rating/reviewsCount/serviceType. Uses listingId as unique key.
      final db = FirebaseFirestore.instance;
      final seenListings = <String>{};
      final results = <Map<String, dynamic>>[];
      // Admins see every provider in the sub-category, including those
      // pending verification (isVerified==false) and hidden demos
      // (isHidden==true). Resolved before the first page load by
      // [_detectAdminAndLoad]. Non-admins keep the production filter.
      final isAdmin = _isAdminViewer;

      // ── Primary: listings query ──────────────────────────────────────
      if (!widget.volunteerOnly) {
        Query<Map<String, dynamic>> q = db
            .collection('provider_listings')
            .where('serviceType', isEqualTo: widget.categoryName);

        if (_lastDoc != null) q = q.startAfterDocument(_lastDoc!);
        q = q.limit(_kPageSize);

        // Server-only fetch. Reduced from 20s → 12s after the user
        // reported (2026-05-14) that 20s + retry = 43s of unblocking
        // spinner was unusable. 12s + 3s backoff + 12s = 27s max, and
        // most healthy connections complete in 1-3s anyway.
        final snap = await q.get().timeout(const Duration(seconds: 12));
        debugPrint('[CategoryResults] Listings: ${snap.docs.length} for "${widget.categoryName}"');

        if (snap.docs.length < _kPageSize) {
          if (mounted) setState(() => _hasMore = false);
        }
        if (snap.docs.isNotEmpty) _lastDoc = snap.docs.last;

        for (final d in snap.docs) {
          final map = d.data();
          // SOFT LAUNCH: per user request 2026-05-15, every user sees
          // ALL providers (including demos AND pending-verification
          // providers). Only `isHidden: true` records (admin spam
          // blocks) are filtered for non-admins. Demos write
          // `isVerified: true, isHidden: false` so they pass through.
          if (!isAdmin && map['isHidden'] == true) continue;
          // v11.9.x: Demo profiles ARE shown in search (Soft Launch).
          // Booking interception in expert_profile_screen handles the
          // fake-success flow + admin notification. To filter them out,
          // toggle isHidden in the admin demo experts tab instead.
          map['listingId'] = d.id;
          // uid comes from the listing doc (denormalized owner UID)
          map['uid'] = map['uid'] ?? '';
          if (seenListings.add(d.id)) results.add(map);
        }

        // ── Fallback: parentCategory match ────────────────────────────
        // Bumped to 15s (was 10s) after live user reports of premature
        // timeouts. Failure here is silently swallowed because the
        // primary serviceType query is the canonical match — parent-
        // Category is just a safety net for legacy listings.
        if (results.isEmpty && _lastDoc == null) {
          try {
            final parentSnap = await db
                .collection('provider_listings')
                .where('parentCategory', isEqualTo: widget.categoryName)
                .limit(_kPageSize)
                .get()
                .timeout(const Duration(seconds: 15),
                    onTimeout: () => throw TimeoutException('parentCategory'));
            for (final d in parentSnap.docs) {
              if (seenListings.contains(d.id)) continue;
              final map = d.data();
              // Soft Launch: only filter `isHidden`. See primary
              // listings loop above for full rationale.
              if (!isAdmin && map['isHidden'] == true) continue;
              map['listingId'] = d.id;
              map['uid'] = map['uid'] ?? '';
              if (seenListings.add(d.id)) results.add(map);
            }
            debugPrint('[CategoryResults] parentCategory fallback: ${parentSnap.docs.length}');
          } catch (e) {
            debugPrint('[CategoryResults] parentCategory fallback error: $e');
          }
        }
      }

      // ── Volunteer-only path (still queries users — volunteers don't have listings) ─
      if (widget.volunteerOnly) {
        Query<Map<String, dynamic>> q = db
            .collection('users')
            .where('isProvider', isEqualTo: true)
            .where('isVolunteer', isEqualTo: true);
        if (_lastDoc != null) q = q.startAfterDocument(_lastDoc!);
        q = q.limit(_kPageSize);
        final snap = await q.get().timeout(const Duration(seconds: 8));
        if (snap.docs.length < _kPageSize) {
          if (mounted) setState(() => _hasMore = false);
        }
        if (snap.docs.isNotEmpty) _lastDoc = snap.docs.last;
        for (final d in snap.docs) {
          final map = d.data();
          map['uid'] = d.id;
          // SOFT LAUNCH: per user request 2026-05-15, every user sees
          // ALL providers (including demos AND pending-verification
          // providers). Only `isHidden: true` records (admin spam
          // blocks) are filtered for non-admins. Demos write
          // `isVerified: true, isHidden: false` so they pass through.
          if (!isAdmin && map['isHidden'] == true) continue;
          if (seenListings.add(d.id)) results.add(map);
        }
      }

      // ── Auto-repair: if 0 listings found, fall back to users collection
      // and auto-create missing listings (the "ghost" fix) ─────────────
      if (results.isEmpty && !widget.volunteerOnly && _lastDoc == null) {
        debugPrint('[CategoryResults] No listings found — trying users fallback + auto-repair');
        // 15s timeout — same reasoning as the parentCategory fallback
        // above. Without this, a stuck connection could hang here
        // indefinitely since this is the LAST fallback before returning
        // an empty list.
        final userSnap = await db
            .collection('users')
            .where('isProvider', isEqualTo: true)
            .where('serviceType', isEqualTo: widget.categoryName)
            .limit(_kPageSize)
            .get()
            .timeout(const Duration(seconds: 15));
        for (final d in userSnap.docs) {
          final map = d.data();
          // SOFT LAUNCH: per user request 2026-05-15, every user sees
          // ALL providers (including demos AND pending-verification
          // providers). Only `isHidden: true` records (admin spam
          // blocks) are filtered for non-admins. Demos write
          // `isVerified: true, isHidden: false` so they pass through.
          if (!isAdmin && map['isHidden'] == true) continue;
          map['uid'] = d.id;
          results.add(map);
          // Fire-and-forget: auto-create listing for this provider
          ProviderListingService.migrateIfNeeded(d.id).catchError((_) => null);
        }
        if (userSnap.docs.length < _kPageSize) {
          if (mounted) setState(() => _hasMore = false);
        }
      }

      debugPrint('[CategoryResults] After filters: ${results.length} experts visible');
      return results;
    } catch (e) {
      debugPrint('[CategoryResults] _fetchPage ERROR: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Availability bottom sheet
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns display time slots for a given [day] based on provider's
  /// [workingHours]. Falls back to 4 fixed slots if no hours are configured.


  // ─────────────────────────────────────────────────────────────────────────
  // Bottom FAB
  // ─────────────────────────────────────────────────────────────────────────

  /// Floating action button for the list view. As of 2026-05-16 the "מפה"
  /// pill moved to the AppBar (see [build] → AppBar.actions), so the bottom
  /// FAB is reserved purely for CSM-specific urgent-dispatch pills
  /// (motorcycle towing §57, babysitter §76, delivery §78). Returns null for
  /// ordinary categories — no bottom FAB at all.
  Widget? _buildBottomFab() {
    if (isMotorcycleTowingCategory(widget.categoryName)) {
      return _UrgentTowSearchPillFab(
        label: 'מצא גרר דחוף',
        onTap: _onUrgentTowSearchPressed,
      );
    }
    if (isBabysitterCategory(widget.categoryName)) {
      return _UrgentTowSearchPillFab(
        // Same visual primitive — different label + handler. The
        // pill is intentionally generic so future CSMs reuse it.
        label: 'מצאי בייביסיטר עכשיו',
        onTap: _onUrgentBabysitterPressed,
        icon: Icons.child_care_rounded,
      );
    }
    if (isDeliveryCategory(widget.categoryName)) {
      return _UrgentTowSearchPillFab(
        // Same visual primitive — different label + handler. The
        // pill is intentionally generic so future CSMs reuse it.
        label: 'מצא שליח דחוף',
        onTap: _onUrgentDeliveryPressed,
        icon: Icons.delivery_dining_rounded,
      );
    }
    return null;
  }

  /// The pill rendered in the AppBar actions slot. It SWAPS in place
  /// (2026-05-16): in list mode it shows "מפה" (opens the map); once the
  /// map is open the SAME slot shows the list-view toggle (back to the
  /// list) — so the two controls feel like a single in-position toggle.
  Widget _buildMapAppBarAction() {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Center(
        child: _showMap
            ? _OpenMapPillFab(
                label: l10n.catListView,
                icon: Icons.view_list_rounded,
                onTap: () => setState(() => _showMap = false),
              )
            : _OpenMapPillFab(
                label: l10n.catMapButtonShort,
                onTap: () => setState(() => _showMap = true),
              ),
      ),
    );
  }

  /// Pushes the Flash Auction flow (CLAUDE.md §57 — see
  /// docs/ui-specs/Motorcycle/Motorcycle 2/). The 4-step flow handles
  /// everything from issue diagnosis through offer selection. After a
  /// match the customer lands on the existing Pay & Secure flow.
  void _onUrgentTowSearchPressed() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const FlashAuctionIssueScreen(),
      ),
    );
  }

  /// Pushes the Babysitter Emergency Dispatch flow (CLAUDE.md §76).
  /// Same 4-step pattern as Flash Auction but tuned for childcare —
  /// children + duration drive pricing, single home address, providers
  /// must be background-checked + accept-last-minute.
  void _onUrgentBabysitterPressed() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BabysitterEmergencyDetailsScreen(),
      ),
    );
  }

  /// Pushes the Delivery Express Dispatch flow (CLAUDE.md §78).
  /// Same 4-step pattern as Flash Auction but tuned for couriers —
  /// package type + pickup/dropoff drive pricing, courier picks vehicle
  /// + ETA. Filters: online + has deliveryProfile + eligible vehicle.
  void _onUrgentDeliveryPressed() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const DeliveryExpressPackageScreen(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Scaffold & list
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
            widget.volunteerOnly
                ? 'AnySkill למען הקהילה ❤️'
                : widget.categoryName,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        // 2026-05-16: the map/list toggle pill lives here in the AppBar
        // actions — top-left in RTL, right next to the centred title.
        // The single slot swaps "מפה" ⇄ "רשימה" depending on _showMap
        // (see _buildMapAppBarAction). Hidden only on the volunteer screen.
        actions: widget.volunteerOnly ? null : [_buildMapAppBarAction()],
      ),
      floatingActionButton: widget.volunteerOnly
          ? _WhatsAppSosButton()
          : (_showMap ? null : _buildBottomFab()),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: Column(
        children: [
          if (widget.volunteerOnly) _buildVolunteerHeader(),
          if (!_showMap) _buildSearchAndFilter(),
          Expanded(
            child: _showMap
                ? LayoutBuilder(
                    builder: (ctx, c) {
                      // v15.x — responsive map layout per user request:
                      //   wide  (≥720): map on RIGHT, cards list on LEFT (Row, RTL)
                      //   narrow (<720): existing full-screen map + bottom sheet
                      if (c.maxWidth >= 720) {
                        return _libBuildMapSideBySideLayout(this);
                      }
                      return Stack(
                        children: [
                          Positioned.fill(child: _libBuildMapView(this)),
                          _libBuildMapCarouselSheet(this),
                          const Positioned(
                            top: 0, left: 0, right: 0,
                            child: IgnorePointer(child: _MapTopGradient()),
                          ),
                          Positioned(
                            top: 0, left: 0, right: 0,
                            child: SafeArea(
                              bottom: false,
                              child: _libBuildMapOverlayHeader(this),
                            ),
                          ),
                        ],
                      );
                    },
                  )
                : RefreshIndicator(
                    onRefresh: _loadInitial,
                    color: _kPurple,
                    strokeWidth: 2.5,
                    // The subcategory VIP/promo banner is the FIRST item
                    // of the scroll view built by `_renderExperts` (and
                    // the empty-state list) — NOT pinned above it. This
                    // makes the whole page scroll as ONE continuous
                    // surface: scrolling down hides the banner and reveals
                    // more cards, instead of a fixed top half + a
                    // separately-scrollable bottom half. `_renderExperts`
                    // renders the banner in BOTH the populated list and
                    // the empty-state list, so it no longer vanishes when
                    // the experts list is empty.
                    child: _buildList(),
                  ),
          ),
        ],
      ),
    );
  }

  // ── v12.9.0: Map overlay — top bar + fade ────────────────────────────────

  // ── Volunteer Hub Header ──────────────────────────────────────────────────

  // Coordinator phone removed in v9.0.8 — support is now internal via SupportCenterScreen

  Widget _buildVolunteerHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF064E3B), Color(0xFF065F46)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Tag line ──────────────────────────────────────────────────────
          Text(
            AppLocalizations.of(context).catFreeCommunityBadge,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Color(0xFF6EE7B7),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3),
          ),
          const SizedBox(height: 14),

          // ── Two CTA buttons ───────────────────────────────────────────────
          Row(
            children: [
              // Button A — I need help
              Expanded(
                child: _CommunityActionButton(
                  label: AppLocalizations.of(context).catNeedHelp,
                  icon: Icons.volunteer_activism_rounded,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                  ),
                  onTap: () => _showHelpRequestSheet(forOther: false),
                ),
              ),
              const SizedBox(width: 10),
              // Button B — Help someone else
              Expanded(
                child: _CommunityActionButton(
                  label: AppLocalizations.of(context).catHelpForOther,
                  icon: Icons.people_alt_rounded,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                  ),
                  onTap: () => _showHelpRequestSheet(forOther: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Community rules ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              AppLocalizations.of(context).catRespectTime,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: Color(0xFFD1FAE5), fontSize: 11, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  // ── Help request bottom sheet ─────────────────────────────────────────────

  void _showHelpRequestSheet({required bool forOther}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HelpRequestSheet(forOther: forOther),
    );
  }

  Widget _buildSearchAndFilter() {
    final l10n = AppLocalizations.of(context);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        children: [
          // שורת חיפוש
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                hintText: l10n.catResultsSearchHint,
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── Filter chips row ──────────────────────────────────────────
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              reverse: true, // RTL
              children: [
                // Price < 100
                _buildFilterChip(
                  label: l10n.catResultsUnder100,
                  icon: Icons.attach_money,
                  active: _filterUnder100,
                  onTap: () => setState(() => _filterUnder100 = !_filterUnder100),
                ),
                const SizedBox(width: 8),
                // Rating filter — opens unified DynamicFilterSheet (CLAUDE.md §50)
                _buildFilterChip(
                  label: _minRating > 0 ? '⭐ ${_minRating.toStringAsFixed(1)}+' : AppLocalizations.of(context).catFilterRating,
                  icon: Icons.star_rounded,
                  active: _minRating > 0,
                  onTap: _showDynamicFilterSheet,
                ),
                const SizedBox(width: 8),
                // Distance filter — opens unified DynamicFilterSheet (CLAUDE.md §50)
                _buildFilterChip(
                  label: _maxDistanceKm != null ? '${_maxDistanceKm!.toInt()} ${AppLocalizations.of(context).catFilterKm}' : AppLocalizations.of(context).catFilterDistance,
                  icon: Icons.location_on_outlined,
                  active: _maxDistanceKm != null,
                  onTap: _showDynamicFilterSheet,
                ),
                const SizedBox(width: 8),
                // Advanced toggle
                _buildFilterChip(
                  label: AppLocalizations.of(context).catFilterMore,
                  icon: Icons.tune_rounded,
                  active: _showAdvancedFilters,
                  onTap: () => setState(() => _showAdvancedFilters = !_showAdvancedFilters),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? _kPurple : Colors.white,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: active ? _kPurple : Colors.grey.shade300),
          boxShadow: active
              ? [BoxShadow(color: _kPurple.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3))]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: active ? Colors.white : Colors.grey[600]),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: active ? Colors.white : Colors.grey[800])),
          ],
        ),
      ),
    );
  }

  // ── Dynamic filter sheet (CLAUDE.md §50 — replaces legacy rating + ─────────
  // distance modals with a per-category schema-driven sheet). The legacy
  // `_showRatingFilterSheet` and `_showDistanceFilterSheet` below are kept
  // intact for the map view (lines 2239/2288 still call them) and will be
  // removed in stage 7 once the map view is migrated.
  void _showDynamicFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,        // חובה — בלי זה המודאל ייחתך
      backgroundColor: Colors.transparent,
      builder: (_) => DynamicFilterSheet(
        categoryId: widget.categoryName,
        initialFilters: _dynamicFilters,
        estimatedResultCount: _allExperts.length,
        onApply: (filters) {
          setState(() {
            _dynamicFilters = filters;
            // Stage 4 back-fill: map known section IDs into the legacy
            // state vars so `expert_filter.dart` keeps working unchanged.
            // Stage 5 will extend `expert_filter.dart` to consume the full
            // map and these back-fills will go away.
            final ratingVal = filters['rating'];
            _minRating = ratingVal is num ? ratingVal.toDouble() : 0;

            final priceVal = filters['price'];
            if (priceVal is Map) {
              final to = priceVal['to'];
              _filterUnder100 = to is num && to <= 100;
            } else {
              _filterUnder100 = false;
            }
          });
        },
      ),
    );
  }


  // ── v9.9.0: Map View ────────────────────────────────────────────────────────

  // ── v12.9.0: Map filter helpers ──────────────────────────────────────────

  /// Single source of truth for the map: markers, carousel cards and count
  /// badge all read from this — guarantees perfect sync.
  List<Map<String, dynamic>> _mapFilteredExperts() {
    final all = List<Map<String, dynamic>>.from(_allExperts);
    SearchRankingService.sortExperts(
      all,
      myLat: _currentPosition?.latitude,
      myLng: _currentPosition?.longitude,
      distanceFn: (myLat, myLng, lat, lng) =>
          LocationService.distanceMeters(myLat, myLng, lat, lng),
    );
    return filterExperts(
      all,
      query: _searchQuery,
      underHundred: _filterUnder100,
      minRating: _minRating,
      maxDistanceKm: _maxDistanceKm,
      myPosition: _currentPosition,
      onlineOnly: _onlineOnly,
      schema: _filterSchema,
      dynamicFilters: _dynamicFilters,
    );
  }

  /// Count for the "$N {category} באזור שלך" badge. Counts ONLY providers
  /// that actually appear as pins on the map — i.e. those with valid GPS
  /// coordinates. `_mapFilteredExperts()` also returns coordinate-less
  /// providers (they can never be pinned), so counting its raw length
  /// overstated the badge. With `_onlineOnly` defaulting to true, this is
  /// the true number of currently-available, mappable providers — and it
  /// matches the marker / carousel count exactly.
  int _mapFilteredCount() => _mapFilteredExperts().where((e) {
        final lat = (e['latitude'] as num?)?.toDouble();
        final lng = (e['longitude'] as num?)?.toDouble();
        return lat != null && lng != null;
      }).length;

  bool _mapAnyFilterActive() =>
      _searchQuery.isNotEmpty ||
      _filterUnder100 ||
      _minRating > 0 ||
      _maxDistanceKm != null ||
      _onlineOnly;

  Future<void> _pickMapDistance() async {
    final options = <double?>[null, 2, 5, 10, 20, 50];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      useSafeArea: true,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(AppLocalizations.of(context).catMaxDistance,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: MapPalette.textPrimary)),
              ),
              for (final opt in options)
                ListTile(
                  title: Text(
                    opt == null
                        ? AppLocalizations.of(context).catNoLimit
                        : AppLocalizations.of(context).catUpToKm(opt.toInt()),
                    textDirection: TextDirection.rtl,
                  ),
                  trailing: _maxDistanceKm == opt
                      ? const Icon(Icons.check_rounded,
                          color: MapPalette.primary)
                      : null,
                  onTap: () {
                    setState(() => _maxDistanceKm = opt);
                    Navigator.of(ctx).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickMapRating() async {
    final options = <double>[0, 4.0, 4.5, 5.0];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      useSafeArea: true,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(AppLocalizations.of(context).catMinRating,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: MapPalette.textPrimary)),
              ),
              for (final opt in options)
                ListTile(
                  title: Text(
                    opt == 0
                        ? AppLocalizations.of(context).catNoLimit
                        : '${opt.toStringAsFixed(opt == 5 ? 0 : 1)}+ ⭐',
                    textDirection: TextDirection.rtl,
                  ),
                  trailing: _minRating == opt
                      ? const Icon(Icons.check_rounded,
                          color: MapPalette.primary)
                      : null,
                  onTap: () {
                    setState(() => _minRating = opt);
                    Navigator.of(ctx).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    // Test injection path — kept for unit tests
    if (widget.testStream != null) {
      return StreamBuilder<List<Map<String, dynamic>>>(
        stream: widget.testStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          return _renderExperts(context, snapshot.data ?? []);
        },
      );
    }
    return _buildContent(context);
  }

  Widget _buildContent(BuildContext context) {
    if (_isLoading) {
      // More informative spinner — shows the user we're still working
      // and reassures them on slow connections. The previous unlabeled
      // CircularProgressIndicator was giving the impression the app
      // was frozen (רועי צברי report 2026-05-14).
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2.5, color: _kPurple),
            const SizedBox(height: 16),
            Text(
              'טוען נותני שירות...',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    final all = List<Map<String, dynamic>>.from(_allExperts);
    // ── Unified weighted ranking formula ──────────────────────────────────
    // Score = (XP × 0.6) + (Distance_Score × 0.2) + (ActiveStoryBonus × 0.2)
    //         + Promoted_Add (200 if isPromoted — always floats above non-promoted)
    //
    // All component scores are normalised 0–100 before weighting.
    // See SearchRankingService for full documentation.
    SearchRankingService.sortExperts(
      all,
      myLat:      _currentPosition?.latitude,
      myLng:      _currentPosition?.longitude,
      distanceFn: (myLat, myLng, lat, lng) =>
          LocationService.distanceMeters(myLat, myLng, lat, lng),
    );
    final experts = filterExperts(
      all,
      query: _searchQuery,
      underHundred: _filterUnder100,
      minRating: _minRating,
      maxDistanceKm: _maxDistanceKm,
      myPosition: _currentPosition,
      schema: _filterSchema,
      dynamicFilters: _dynamicFilters,
    );

    // ── Inject Alex AI teacher into English category ───────────────────────
    if (widget.categoryName == 'אנגלית') {
      experts.insert(0, Map<String, dynamic>.from(_kAlexAiTeacher));
    }

    return _renderExperts(context, experts);
  }

  Widget _renderExperts(BuildContext context, List<Map<String, dynamic>> experts) {
    final l10n = AppLocalizations.of(context);
    // The subcategory VIP/promo banner is the FIRST item of the scroll
    // view — it scrolls together with the provider cards so the page
    // reads as ONE continuous surface (scrolling down hides the banner),
    // instead of a fixed top half + a separately-scrollable bottom half.
    // volunteerOnly screens have no provider listings to promote.
    final showBanner = !widget.volunteerOnly;
    final headerCount = showBanner ? 1 : 0;

    if (experts.isEmpty && !_isLoadingMore && !_hasMore) {
      final hasFilters = _searchQuery.isNotEmpty || _filterUnder100 || _minRating > 0 || _maxDistanceKm != null;
      // 2026-05-14 — ROOT FIX after the user's frustration:
      // STOP showing "בעיית חיבור" scaffolds. They were generating
      // false alarms on every slow connection and confusing the user.
      // ALWAYS show the neutral "no providers" copy — the
      // RefreshIndicator (parent) and the auto-retry inside
      // `_loadInitial` already handle the failed-load case
      // silently. If providers genuinely arrive later, the
      // StreamBuilder rebuilds and they appear.
      //
      // The empty state is itself a ListView so (a) the subcategory
      // banner still renders + scrolls with the page, and (b)
      // pull-to-refresh keeps working (RefreshIndicator needs a
      // scrollable child).
      return ListView(
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (showBanner)
            SubcategoryBannerHeader(subcategoryId: widget.categoryName),
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                          color: _kPurpleSoft, shape: BoxShape.circle),
                      child: Icon(Icons.person_search_outlined,
                          size: 56, color: _kPurple.withValues(alpha: 0.5)),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      hasFilters
                          ? l10n.catResultsNoResults
                          : l10n.catResultsNoExperts(widget.categoryName),
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hasFilters
                          ? l10n.catResultsNoResultsHint
                          : 'משוך מטה לרענון',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    ),
                    if (hasFilters) ...[
                      const SizedBox(height: 28),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.filter_alt_off),
                        label: Text(l10n.catResultsClearFilters),
                        onPressed: () => setState(() {
                          _searchQuery = '';
                          _filterUnder100 = false;
                          _minRating = 0;
                          _maxDistanceKm = null;
                        }),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // The subcategory banner header lives at index 0 of this ListView so
    // it scrolls together with the cards. A trailing +1 sentinel item
    // drives the load-more spinner / "all loaded" indicator.
    final sentinelCount = (_isLoadingMore || _hasMore) ? 1 : 0;
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: headerCount + experts.length + sentinelCount,
      itemBuilder: (_, index) {
        // Index 0 → subcategory banner (scrolls with the list).
        if (showBanner && index == 0) {
          return SubcategoryBannerHeader(subcategoryId: widget.categoryName);
        }
        final expertIdx = index - headerCount;
        if (expertIdx == experts.length) {
          // Bottom sentinel
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: _isLoadingMore
                  ? const SizedBox(
                      width: 28, height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : TextButton.icon(
                      onPressed: _loadMore,
                      icon: const Icon(Icons.expand_more_rounded),
                      label: Text(l10n.catResultsLoadMore),
                    ),
            ),
          );
        }
        return RepaintBoundary(
          child: _libBuildExpertCard(
            context,
            experts[expertIdx],
            _serviceSchema,
            _currentPosition,
          ),
        );
      },
    );
  }
}

