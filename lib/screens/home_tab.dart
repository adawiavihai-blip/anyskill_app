// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../l10n/app_localizations.dart';
import '../services/visual_fetcher_service.dart';
import 'category_results_screen.dart';
import 'notifications_screen.dart';
import 'help_center_screen.dart';
import 'sub_category_screen.dart';
import 'search_screen/search_page.dart';
import 'search_screen/widgets/stories_row.dart';
import 'community_hub_screen.dart';
import 'community/community_hub_screen_v2.dart';
import 'community/feature_flag.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/community_theme.dart';
import '../features/any_tasks/screens/my_tasks_screen.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/global_search_bar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/category_edit_sheet.dart';
import '../services/opportunity_hunter_service.dart';
import '../services/engagement_service.dart';
import '../services/auth_service.dart';
import '../widgets/daily_drop_modal.dart';
import '../utils/safe_image_provider.dart';
import '../main.dart' show currentAppVersion;
// Banners v2 (§49) — provider_carousel rail injected after the 4th category
// row. Lives separately from the legacy _PromoCarousel (which still owns
// the `home_carousel` placement).
import '../models/banner_model.dart' show ProviderCarouselConfig;
import '../widgets/provider_carousel_banner.dart';

// ─── Public entry point ───────────────────────────────────────────────────────

class HomeTab extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String currentUserId;
  final bool isOnline;
  final void Function(bool) onToggleOnline;
  final VoidCallback onGoToBookings;
  final VoidCallback onGoToChat;
  final VoidCallback onOpenQuickRequest;
  final VoidCallback onGoToProfile;

  const HomeTab({
    super.key,
    required this.userData,
    required this.currentUserId,
    required this.isOnline,
    required this.onToggleOnline,
    required this.onGoToBookings,
    required this.onGoToChat,
    required this.onOpenQuickRequest,
    required this.onGoToProfile,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with SingleTickerProviderStateMixin {
  // ── Pulse animation (urgent banner only) ───────────────────────────────────
  late final AnimationController _pulseCtrl;

  // ── Firestore streams ─────────────────────────────────────────────────────
  late final Stream<QuerySnapshot>                          _categoriesStream;
  late final Stream<QuerySnapshot>                          _urgentStream;
  late final Stream<QuerySnapshot>                          _notificationsStream;
  late final Stream<QuerySnapshot>                          _remindersStream;
  // (AI Deal of the Day banner — REMOVED in v8.9.6, caused navigation/cache loops)

  // ── Avatar press feedback ─────────────────────────────────────────────────
  bool _avatarTapped = false;

  // ── Community banner (volunteer count + facepile — real-time stream) ─────
  int _volunteerCount = 0;
  List<String?> _recentVolunteerAvatars = [];
  StreamSubscription<QuerySnapshot>? _volunteerSub;


  // ── Live online status ─────────────────────────────────────────────────────
  // HomeTab lives inside a Navigator route created by _nestedTab(). When
  // home_screen.dart's StreamBuilder rebuilds with a new isOnline value, the
  // route's builder is NOT re-invoked — _isOnline stays frozen at the
  // value from first render. We fix this by owning a Firestore subscription
  // here, making the toggle button always reactive regardless of the prop.
  late bool   _isOnline;
  String      _profileImageUrl = '';   // live-synced from Firestore
  late final StreamSubscription<DocumentSnapshot> _onlineSub;

  // Per-user category affinity — maps top-level category NAME → tap count.
  // Live-synced from `users/{uid}.categoryTapCounts`. Used by the build
  // method's sort comparator to push the categories THIS user clicks into
  // most to the top of the home grid. Empty for brand-new users → grid
  // falls back to global popularity (clickCount) order.
  Map<String, int> _categoryTapCounts = {};

  @override
  void initState() {
    super.initState();

    // Seed from prop immediately — correct state on first paint.
    _isOnline        = widget.isOnline;
    _profileImageUrl = (widget.userData['profileImage'] as String? ?? '');
    _categoryTapCounts = _parseTapCounts(widget.userData['categoryTapCounts']);

    // Subscribe to the live user doc — updates online status, avatar, AND
    // per-user category affinity (so the home grid re-sorts the moment a
    // tap is recorded, without waiting for a screen rebuild).
    _onlineSub = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.currentUserId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final data = snap.data() ?? {};
      final live = data['isOnline'] == true;
      final img  = data['profileImage'] as String? ?? '';
      final counts = _parseTapCounts(data['categoryTapCounts']);
      setState(() {
        _isOnline          = live;
        _profileImageUrl   = img;
        _categoryTapCounts = counts;
      });
    });

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    // Category grid — NO orderBy and NO limit on the query.
    // Docs are sorted client-side (clickCount DESC → order ASC → name ASC)
    // so new categories added via the admin panel or demo-expert creation
    // appear instantly on the home screen without any code deploy.
    _categoriesStream = FirebaseFirestore.instance
        .collection('categories')
        .limit(100)
        .snapshots();

    // Urgent banner — providers see open job requests, customers see pending approvals
    final uid        = widget.currentUserId;
    final isProvider = widget.userData['isProvider'] == true;
    final category   = (widget.userData['serviceType'] ?? '') as String;

    // Auth guard: all streams below require authenticated Firestore access.
    // If uid is empty (auth not yet resolved), use empty streams to avoid
    // permission-denied errors from stricter v8.9.4 Firestore rules.
    if (uid.isEmpty) {
      _urgentStream        = const Stream.empty();
      _notificationsStream = const Stream.empty();
      _remindersStream     = const Stream.empty();
      // _dealStream removed in v8.9.6
    } else {

    if (isProvider && category.isNotEmpty) {
      _urgentStream = FirebaseFirestore.instance
          .collection('job_requests')
          .where('status',   isEqualTo: 'open')
          .where('category', isEqualTo: category)
          .orderBy('createdAt', descending: true)
          .limit(5)
          .snapshots();
    } else {
      _urgentStream = FirebaseFirestore.instance
          .collection('jobs')
          .where('customerId', isEqualTo: uid)
          .where('status',     isEqualTo: 'expert_completed')
          .limit(3)
          .snapshots();
    }

    // Notifications bell stream — cached here so build() never creates a new subscription
    _notificationsStream = FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: uid)
            .where('isRead', isEqualTo: false)
            .limit(20)
            .snapshots();

    // AI Re-Engagement reminders — active, non-dismissed reminders for this user
    _remindersStream = FirebaseFirestore.instance
            .collection('scheduled_reminders')
            .where('userId',      isEqualTo: uid)
            .where('isDismissed', isEqualTo: false)
            .where('isActive',    isEqualTo: true)
            .limit(3)
            .snapshots();

    } // end uid.isNotEmpty else block

    // Real-time volunteer stream for community banner (count + facepile)
    _startVolunteerStream();

    // Back-fill missing category images once per app session
    VisualFetcherService.backfillAll();

    // ── Engagement: Daily Drop + Streak check (providers only) ────────────
    if (widget.userData['isProvider'] == true &&
        widget.currentUserId.isNotEmpty) {
      _runEngagementChecks();
    }
  }

  /// Real-time stream of volunteers — updates count + facepile whenever
  /// a user toggles isVolunteer on/off or completes a community task.
  /// Uses a single query (no composite index beyond isVolunteer) to avoid
  /// silent empty results on web from missing indexes.
  void _startVolunteerStream() {
    _volunteerSub = FirebaseFirestore.instance
        .collection('users')
        .where('isVolunteer', isEqualTo: true)
        .limit(100)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;

      final docs = snap.docs;

      // Pick top 4 avatars — prefer those with profileImage set.
      // Sort client-side by lastVolunteerTaskAt (may be null) so the
      // most recently active volunteers appear first.
      final sorted = List<QueryDocumentSnapshot>.from(docs);
      sorted.sort((a, b) {
        final aData = a.data() as Map<String, dynamic>? ?? {};
        final bData = b.data() as Map<String, dynamic>? ?? {};
        final aTs = aData['lastVolunteerTaskAt'] as Timestamp?;
        final bTs = bData['lastVolunteerTaskAt'] as Timestamp?;
        if (aTs == null && bTs == null) return 0;
        if (aTs == null) return 1;
        if (bTs == null) return -1;
        return bTs.compareTo(aTs);
      });

      final avatars = sorted
          .take(4)
          .map((d) {
            final data = d.data() as Map<String, dynamic>? ?? {};
            return data['profileImage'] as String?;
          })
          .toList();

      setState(() {
        _volunteerCount = docs.length;
        _recentVolunteerAvatars = avatars;
      });
    }, onError: (e) {
      debugPrint('[HomeTab] volunteerStream error: $e');
    });
  }

  Future<void> _runEngagementChecks() async {
    final uid = widget.currentUserId;

    // Update streak (fire-and-forget — updates Firestore)
    EngagementService.checkAndUpdateStreak(uid);

    // Daily Drop: roll the dice
    final reward = await EngagementService.calculateRandomReward(uid);
    if (reward != null && mounted) {
      // Small delay so the home screen is fully rendered first
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) showDailyDropModal(context, reward);
    }
  }

  @override
  void dispose() {
    _onlineSub.cancel();
    _volunteerSub?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  /// Parses a Firestore `Map<String, dynamic>?` of category → tap count into
  /// a strongly-typed `Map<String, int>`. Tolerates missing fields, non-int
  /// values (e.g. doubles), and entirely missing keys — returns {} on any
  /// shape mismatch instead of throwing.
  Map<String, int> _parseTapCounts(dynamic raw) {
    if (raw is! Map) return {};
    final out = <String, int>{};
    raw.forEach((k, v) {
      if (k == null) return;
      final key = k.toString();
      if (key.isEmpty) return;
      final intVal = (v is num) ? v.toInt() : 0;
      if (intVal > 0) out[key] = intVal;
    });
    return out;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _openSearch({String? preselectedCategory}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, a1, a2) => SearchPage(
          isOnline:        _isOnline,
          onToggleOnline:  () => widget.onToggleOnline(!_isOnline),
          initialCategory: preselectedCategory,
        ),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.04),
              end:   Offset.zero,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: child,
          ),
        ),
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }

  // ── Pull-to-refresh ────────────────────────────────────────────────────────

  Future<void> _handleRefresh() async {
    // The category stream is already real-time — no re-subscription needed.
    // What refresh does:
    //   1. Evict Flutter's in-memory image cache so updated images at the
    //      same URL are re-fetched from CachedNetworkImage's disk cache.
    //   2. Force a rebuild so the UI reflects the latest stream data.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (mounted) setState(() {});
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isProvider = widget.userData['isProvider'] == true;
    final isAdmin =
        widget.userData['isAdmin'] == true;

    // Outer StreamBuilder feeds the category grid without needing shrinkWrap.
    // This lets CustomScrollView use proper SliverGrid for performance.
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ── POC: pastel radial-gradient background (§glassmorphism) ─────
          const Positioned.fill(
            child: IgnorePointer(child: _PastelHomeBackground()),
          ),
          SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: _categoriesStream,
          builder: (context, catSnap) {
            // ── Pre-process category data ─────────────────────────────────
            final allDocs = catSnap.data?.docs ?? [];

            // All top-level categories, sorted into a "breathing" grid:
            //   1. PER-USER affinity DESC   — this user's own tap counts
            //   2. Global clickCount DESC   — platform-wide popularity
            //   3. order ASC                — admin-configured order
            //   4. name ASC                 — stable tie-breaker
            //
            // Sub-cat taps lift the PARENT (see recordCategoryTap call sites
            // below — `affinityKey` is always the parent name), so opening
            // "גרר אופנועים" pushes the whole "תחבורה" card to the top on
            // the next render. For brand-new users _categoryTapCounts is
            // empty, so the grid falls back to the global ordering it always
            // had — no regression for fresh accounts.
            final mainDocs = allDocs
                .where((d) {
                  final data = d.data() as Map;
                  final parentId = (data['parentId'] as String? ?? '');
                  final isHidden = data['isHidden'] as bool? ?? false;
                  return parentId.isEmpty && !isHidden;
                })
                .toList()
              ..sort((a, b) {
                final dataA = a.data() as Map;
                final dataB = b.data() as Map;
                final nameA = (dataA['name'] as String?) ?? '';
                final nameB = (dataB['name'] as String?) ?? '';

                final userA = _categoryTapCounts[nameA] ?? 0;
                final userB = _categoryTapCounts[nameB] ?? 0;
                if (userA != userB) return userB.compareTo(userA);

                final cA = (dataA['clickCount'] as num? ?? 0).toInt();
                final cB = (dataB['clickCount'] as num? ?? 0).toInt();
                if (cA != cB) return cB.compareTo(cA);

                final oA = (dataA['order'] as num? ?? 999).toInt();
                final oB = (dataB['order'] as num? ?? 999).toInt();
                if (oA != oB) return oA.compareTo(oB);

                return nameA.compareTo(nameB);
              });

            final filteredDocs = mainDocs;


            return RefreshIndicator(
              onRefresh:   _handleRefresh,
              color:       const Color(0xFF6366F1),
              strokeWidth: 2.5,
              child: CustomScrollView(
              slivers: [
                // ── Greeting header ────────────────────────────────────────
                SliverToBoxAdapter(
                  child: _buildHeader(isProvider),
                ),

                // ── Global search bar (Airbnb-style) ─────────────────────
                SliverToBoxAdapter(
                  child: GlobalSearchBar(
                    onResultTap: (type, value) {
                      if (type == 'category' || type == 'subcategory') {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => CategoryResultsScreen(categoryName: value),
                        ));
                      }
                      // Provider taps are handled directly in the search bar
                      // via Navigator.push → ExpertProfileScreen.
                    },
                    onOpenFullSearch: () => _openSearch(),
                  ),
                ),

                // ── Urgent / Pulse banner (error-safe) ────────────────────
                SliverToBoxAdapter(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _urgentStream,
                    builder: (context, urgSnap) {
                      if (urgSnap.hasError) return const SizedBox.shrink();
                      // Offline providers don't receive the urgent pulse
                      if (isProvider && !_isOnline) {
                        if (_pulseCtrl.isAnimating) _pulseCtrl.stop();
                        return const SizedBox.shrink();
                      }
                      final docs = urgSnap.data?.docs ?? [];
                      if (docs.isEmpty) {
                        if (_pulseCtrl.isAnimating) _pulseCtrl.stop();
                        return const SizedBox.shrink();
                      }
                      if (!_pulseCtrl.isAnimating) {
                        _pulseCtrl.repeat(reverse: true);
                      }
                      return _buildUrgentBanner(docs, isProvider);
                    },
                  ),
                ),

                // ── Story Carousel (ALWAYS rendered — stable key prevents
                //    state loss when parent StreamBuilder rebuilds) ───────────
                SliverToBoxAdapter(
                  key: const ValueKey('stories_row_slot'),
                  child: StoriesRow(key: const ValueKey('stories_row'), isProvider: isProvider),
                ),

                // ── Banners Studio §51 — provider_carousel rail ─────────────
                // The rail widget owns its own section title and renders
                // nothing at all when no qualifying banner exists, so we
                // never see a stranded "נותני השירות ה-VIP שלנו" header
                // sitting above an empty space.
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: _ProviderCarouselsRail(),
                  ),
                ),

                // ── Loading shimmer ────────────────────────────────────────
                if (catSnap.connectionState == ConnectionState.waiting)
                  const CategoryGridSkeleton()

                // ── Empty state ────────────────────────────────────────────
                else if (mainDocs.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: Center(
                        child: Text(
                          AppLocalizations.of(context).noCategoriesYet,
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                      ),
                    ),
                  )

                // ── Full visual category grid ──────────────────────────────
                else if (filteredDocs.isNotEmpty) ...[
                  // ── AI Re-Engagement offer card (error-safe) ──────────
                  SliverToBoxAdapter(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _remindersStream,
                      builder: (context, remSnap) {
                        if (remSnap.hasError) return const SizedBox.shrink();
                        final remDocs = remSnap.data?.docs ?? [];
                        if (remDocs.isEmpty) return const SizedBox.shrink();
                        final data  = remDocs.first.data() as Map<String, dynamic>;
                        final remId = remDocs.first.id;
                        return _buildReengagementCard(data, remId);
                      },
                    ),
                  ),

                  // ── Airbnb-style horizontal category rows ──────────────
                  // AI Deal banner is injected INSIDE the rows (after 1st row)
                  // ── Airbnb-style horizontal category rows ──────────────
                  ..._buildAirbnbRows(
                    context: context,
                    filteredDocs: filteredDocs,
                    allDocs: allDocs,
                    isAdmin: isAdmin,
                  ),
                ], // end else [...] community + grid

                // ── Footer: logout + version ────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: Column(
                      children: [
                        TextButton.icon(
                          onPressed: () => performSignOut(context),
                          icon: const Icon(Icons.logout, size: 18),
                          label: Text(
                            AppLocalizations.of(context).logoutButton,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            minimumSize: const Size(double.infinity, 48),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'AnySkill v$currentAppVersion',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ],
            ), // CustomScrollView
            ); // RefreshIndicator
          },
        ),
      ),
        ], // Stack children
      ), // Stack
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  // Layout (RTL):  Avatar [· Online toggle] ←——→ [Bell · AI · Admin]
  // The greeting and subtitle have been removed — the clean icon-only header
  // gives more vertical room to the category grid on small phones.

  Widget _buildHeader(bool isProvider) {
    final l10n         = AppLocalizations.of(context);
    // Use the live-synced URL — not the static widget.userData snapshot.
    final profileImage = _profileImageUrl;
    final isAdmin      =
        widget.userData['isAdmin'] == true;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: SizedBox(
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // ── Dead-center logo — always at screen midpoint ────────────
            Center(
              child: Image.asset(
                'assets/images/NEW_LOGO1.png.png',
                height: 42,
                fit: BoxFit.contain,
              ),
            ),

            // ── Left: Logout · Bell · AI · School · [Admin] ────────────
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
              // Notification bell
              _buildNotificationBell(),

              const SizedBox(width: 6),

              // AI Support Assistant
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HelpCenterScreen()),
                ),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.smart_toy_rounded,
                      size: 18, color: Color(0xFF6366F1)),
                ),
              ),

              // Admin: test-email shortcut
              if (isAdmin) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _sendTestEmail,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFFF97316).withValues(alpha: 0.4)),
                    ),
                    child: const Icon(Icons.mail_outline_rounded,
                        size: 18, color: Color(0xFFF97316)),
                  ),
                ),
              ],
            ],
          ),
            ),

            // ── Right: Online toggle (providers) + Profile avatar (far right) ──
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
              // Online / Offline toggle — only visible for providers
              if (isProvider) ...[
                GestureDetector(
                  onTap: () {
                    final newStatus = !_isOnline;
                    setState(() => _isOnline = newStatus);
                    widget.onToggleOnline(newStatus);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _isOnline
                          ? const Color(0xFFDCFCE7)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _isOnline
                            ? const Color(0xFF22C55E)
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: _isOnline
                                ? const Color(0xFF22C55E)
                                : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _isOnline ? l10n.onlineStatus : l10n.offlineStatus,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _isOnline
                                ? const Color(0xFF16A34A)
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],

              // Profile avatar — far right, tap navigates to Profile tab
              GestureDetector(
                onTap: () {
                  setState(() => _avatarTapped = false);
                  widget.onGoToProfile();
                },
                onTapDown: (_) => setState(() => _avatarTapped = true),
                onTapUp:   (_) => setState(() => _avatarTapped = false),
                onTapCancel: () => setState(() => _avatarTapped = false),
                child: AnimatedOpacity(
                  opacity: _avatarTapped ? 0.55 : 1.0,
                  duration: const Duration(milliseconds: 100),
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFFEEF2FF),
                    backgroundImage: profileImage.isNotEmpty
                        ? CachedNetworkImageProvider(
                            profileImage,
                            maxWidth:  88,
                            maxHeight: 88,
                          )
                        : null,
                    child: profileImage.isEmpty
                        ? Text(
                            (widget.userData['name'] as String? ?? '?')
                                .characters
                                .firstOrNull
                                ?.toUpperCase() ??
                                '?',
                            style: const TextStyle(
                              color: Color(0xFF6366F1),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Admin: send a test email via Trigger Email extension ──────────────────

  Future<void> _sendTestEmail() async {
    final uid  = widget.currentUserId;
    final name = (widget.userData['name'] as String? ?? 'Admin');
    try {
      await FirebaseFirestore.instance.collection('mail').add({
        'to': 'adawiavihai@gmail.com',
        'message': {
          'subject': '🧪 [AnySkill] Test Email — Trigger Email Works!',
          'html': '''<div dir="rtl" style="font-family:Arial;padding:16px">
            <h2>✅ מערכת המיילים עובדת!</h2>
            <p>המייל הזה נשלח ידנית מתוך האפליקציה.</p>
            <p><b>UID:</b> $uid</p>
            <p><b>שם:</b> $name</p>
            <p><b>זמן:</b> ${DateTime.now().toIso8601String()}</p>
          </div>''',
        },
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).homeTestEmailSent),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).homeGenericError(e.toString())), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Sandwich grid: top 2 rows → carousel → remaining rows ───────────────────
  //
  // Returns a list of Sliver widgets so it can be spread directly into the
  // ── Airbnb-style: one horizontal scroll row per parent category ──────────
  // Parent categories with sub-categories get a header + scrollable row of
  // sub-cat cards.  Categories without sub-categories get a full-width tile.
  // The promo carousel is injected after the 2nd section.

  List<Widget> _buildAirbnbRows({
    required BuildContext context,
    required List<QueryDocumentSnapshot> filteredDocs,
    required List<QueryDocumentSnapshot> allDocs,
    required bool isAdmin,
  }) {
    // Build parentId → [sub-category docs] lookup map.
    final Map<String, List<QueryDocumentSnapshot>> subsByParent = {};
    for (final doc in allDocs) {
      final d        = doc.data() as Map<String, dynamic>;
      final parentId = d['parentId'] as String? ?? '';
      if (parentId.isNotEmpty) {
        subsByParent.putIfAbsent(parentId, () => []).add(doc);
      }
    }

    final slivers       = <Widget>[];
    bool promoInserted  = false;
    for (int i = 0; i < filteredDocs.length; i++) {
      // Inject legacy promo carousel (`home_carousel` placement only)
      // between 2nd and 3rd parent sections.
      //
      // NOTE: the provider_carousel rail (§49) was moved out of this
      // function — it now renders at the build() top-level, right below
      // the Stories row. See the SliverToBoxAdapter with key
      // 'stories_row_slot' in the build() method.
      if (!promoInserted && i == 2) {
        slivers.add(const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _PromoCarousel(),
          ),
        ));
        promoInserted = true;
      }

      final parentDoc  = filteredDocs[i];
      final parentData = parentDoc.data() as Map<String, dynamic>;
      final parentName = parentData['name']     as String? ?? '';
      final parentImg  = parentData['img']      as String? ?? '';

      // Per-user sub-category affinity — sort each parent's sub-cat strip
      // so the sub-cats THIS user opens most inside this parent appear
      // first (RTL → rightmost). Same 4-tier comparator as the top-level
      // grid: personal taps DESC → global clickCount DESC → order ASC →
      // name ASC. Brand-new users with empty _categoryTapCounts see the
      // strip in the same order it had before this change.
      final subs = List<QueryDocumentSnapshot>.from(
          subsByParent[parentDoc.id] ?? const [])
        ..sort((a, b) {
          final dataA = a.data() as Map;
          final dataB = b.data() as Map;
          final nameA = (dataA['name'] as String?) ?? '';
          final nameB = (dataB['name'] as String?) ?? '';

          final userA = _categoryTapCounts[nameA] ?? 0;
          final userB = _categoryTapCounts[nameB] ?? 0;
          if (userA != userB) return userB.compareTo(userA);

          final cA = (dataA['clickCount'] as num? ?? 0).toInt();
          final cB = (dataB['clickCount'] as num? ?? 0).toInt();
          if (cA != cB) return cB.compareTo(cA);

          final oA = (dataA['order'] as num? ?? 999).toInt();
          final oB = (dataB['order'] as num? ?? 999).toInt();
          if (oA != oB) return oA.compareTo(oB);

          return nameA.compareTo(nameB);
        });
      final hasSubs = subs.isNotEmpty;

      // ── §glassmorphism — wrap EVERY hasSubs category in a glass card ─
      // POC Phase 1 (i==0 only) proved the blur(24) BackdropFilter doesn't
      // trigger the minified TypeError that killed Luxury Glass v3. Phase 2
      // rolls out to all categories with sub-categories. Categories without
      // subs keep the legacy header + full-width-tile path unchanged.
      if (hasSubs) {
        slivers.add(SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: _GlassCategoryCard(
              title: parentName,
              onShowAll: () {
                OpportunityHunterService.recordCategoryTap(
                    widget.currentUserId, parentName,
                    affinityKey: parentName);
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => SubCategoryScreen(
                      parentId: parentDoc.id, parentName: parentName),
                ));
              },
              child: SizedBox(
                height: 126,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: subs.length,
                  itemBuilder: (context, si) {
                    final sub     = subs[si].data() as Map<String, dynamic>;
                    final subName = sub['name'] as String? ?? '';
                    final subImg  = sub['img']  as String? ?? '';
                    return _buildSubCatCard(
                      name:     subName,
                      imageUrl: subImg,
                      isAdmin:  isAdmin,
                      docId:    subs[si].id,
                      onTap: () {
                        OpportunityHunterService.recordCategoryTap(
                            widget.currentUserId, subName,
                            affinityKey: parentName,
                            subAffinityKey: subName);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) =>
                              CategoryResultsScreen(categoryName: subName),
                        ));
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ));
        continue;
      }

      // ── Section header with "הצג הכל" link ──────────────────────────
      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, i == 0 ? 4 : 10, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  parentName,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  OpportunityHunterService.recordCategoryTap(
                      widget.currentUserId, parentName,
                      affinityKey: parentName);
                  if (hasSubs) {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => SubCategoryScreen(
                          parentId: parentDoc.id, parentName: parentName),
                    ));
                  } else {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) =>
                          CategoryResultsScreen(categoryName: parentName),
                    ));
                  }
                },
                child: Text(
                  AppLocalizations.of(context).homeShowAll,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF1A1A2E),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ));

      if (hasSubs) {
        // ── Horizontal sub-category card strip ──────────────────────────
        slivers.add(SliverToBoxAdapter(
          child: SizedBox(
            height: 126,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: subs.length,
              itemBuilder: (context, si) {
                final sub     = subs[si].data() as Map<String, dynamic>;
                final subName = sub['name'] as String? ?? '';
                final subImg  = sub['img']  as String? ?? '';
                return _buildSubCatCard(
                  name:         subName,
                  imageUrl:     subImg,
                  isAdmin:      isAdmin,
                  docId:        subs[si].id,
                  onTap: () {
                    OpportunityHunterService.recordCategoryTap(
                        widget.currentUserId, subName,
                        affinityKey: parentName,
                        subAffinityKey: subName);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) =>
                          CategoryResultsScreen(categoryName: subName),
                    ));
                  },
                );
              },
            ),
          ),
        ));
      } else {
        // ── Full-width tile for top-level categories without sub-cats ───
        slivers.add(SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Stack(
              children: [
                GestureDetector(
                  onTap: () {
                    OpportunityHunterService.recordCategoryTap(
                        widget.currentUserId, parentName,
                        affinityKey: parentName);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) =>
                          CategoryResultsScreen(categoryName: parentName),
                    ));
                  },
                  child: Container(
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: parentImg.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: parentImg,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) =>
                                      _categoryPlaceholder(width: 48, height: 48, label: parentName),
                                )
                              : _categoryPlaceholder(width: 48, height: 48, label: parentName),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            parentName,
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_left,
                            size: 18, color: Color(0xFF9CA3AF)),
                      ],
                    ),
                  ),
                ),
                // ── Admin edit overlay ──────────────────────────────────
                if (isAdmin)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openCategoryEditSheet(
                        context: context,
                        docId: parentDoc.id,
                        name: parentName,
                        iconName: parentData['iconName'] as String? ?? '',
                        imageUrl: parentImg,
                        cardScale: (parentData['cardScale'] as num?)?.toDouble(),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.30)),
                        ),
                        child: const Icon(Icons.edit_rounded,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ));
      }
    }

    // Promo carousel: inject here if fewer than 2 sections existed.
    if (!promoInserted) {
      slivers.add(const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _PromoCarousel(),
        ),
      ));
    }
    // Banners v2 (§49) rail moved to the build() top-level (below Stories
    // row). No fallback needed here any more.

    // ── AnyTasks banner — dark premium "Apple Card" style ──────────
    // TODO(§35): Route providers to ProviderHubScreen, clients to MyTasksScreen
    // — currently all users route to MyTasksScreen.
    slivers.add(SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: _AnyTasksBanner(
          onTap: () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(builder: (_) => const MyTasksScreen())),
        ),
      ),
    ));

    // ── Community tile — Phase D-1 (v15.x) gated swap ─────────────────
    // v2 viewers (whitelist) see the new mockup-10 black card and are
    // routed to [CommunityHubScreenV2]. Everyone else keeps the legacy
    // pink-purple gradient banner that pushes the legacy 3,855-line hub.
    final communityViewerUid = FirebaseAuth.instance.currentUser?.uid;
    if (isCommunityV2EnabledFor(communityViewerUid)) {
      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: _CommunityBannerV2(
            volunteerCount: _volunteerCount,
            recentAvatars: _recentVolunteerAvatars,
            onTap: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                    builder: (_) => const CommunityHubScreenV2())),
          ),
        ),
      ));
      return slivers;
    }

    // Legacy v1 banner — UNCHANGED.
    slivers.add(SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: GestureDetector(
          onTap: () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(builder: (_) => const CommunityHubScreen())),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEF4444), Color(0xFFEC4899), Color(0xFF8B5CF6)],
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Pulsing heart icon
                const _HeartPulse(),
                const SizedBox(width: 12),

                // Title + dynamic subtitle
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context).homeCommunityTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _volunteerCount > 0
                            ? '$_volunteerCount מתנדבים עוזרים עכשיו בקהילה'
                            : AppLocalizations.of(context).homeCommunitySlogan,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                // Facepile — overlapping avatars
                if (_recentVolunteerAvatars.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 20.0 + (_recentVolunteerAvatars.length - 1) * 18.0,
                    height: 28,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (int i = _recentVolunteerAvatars.length - 1;
                            i >= 0;
                            i--)
                          PositionedDirectional(
                            start: i * 18.0,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white, width: 2),
                              ),
                              child: CircleAvatar(
                                radius: 12,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.3),
                                backgroundImage: safeImageProvider(
                                    _recentVolunteerAvatars[i]),
                                child: safeImageProvider(
                                            _recentVolunteerAvatars[i]) ==
                                        null
                                    ? const Icon(Icons.person_rounded,
                                        size: 14, color: Colors.white70)
                                    : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],

                // Arrow hint
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: Colors.white54),
              ],
            ),
          ),
        ),
      ),
    ));

    return slivers;
  }

  // ── Sub-category card (used in horizontal rows) ───────────────────────────
  // Placeholder shown when a category has no image URL.
  static Widget _categoryPlaceholder({
    required double width,
    required double height,
    required String label,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEEF2FF), Color(0xFFE0E7FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(
          label.isNotEmpty ? label[0].toUpperCase() : '?',
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Color(0xFF6366F1),
          ),
        ),
      ),
    );
  }

  Widget _buildSubCatCard({
    required String name,
    required String imageUrl,
    required VoidCallback onTap,
    bool isAdmin = false,
    String docId = '',
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          width: 100,
                          height: 90,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              _categoryPlaceholder(width: 100, height: 90, label: name),
                        )
                      : _categoryPlaceholder(width: 100, height: 90, label: name),
                ),
                // ── Admin edit overlay ──────────────────────────────
                if (isAdmin && docId.isNotEmpty)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openCategoryEditSheet(
                        context: context,
                        docId: docId,
                        name: name,
                        iconName: '',
                        imageUrl: imageUrl,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.30)),
                        ),
                        child: const Icon(Icons.edit_rounded,
                            size: 11, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared edit sheet launcher ─────────────────────────────────────────────
  void _openCategoryEditSheet({
    required BuildContext context,
    required String docId,
    required String name,
    required String iconName,
    required String imageUrl,
    double? cardScale,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => CategoryEditSheet(
        docId:            docId,
        initialName:      name,
        initialIconName:  iconName,
        initialImageUrl:  imageUrl,
        initialCardScale: cardScale,
      ),
    );
  }

  // ── Notification bell with live unread badge ───────────────────────────────

  Widget _buildNotificationBell() {
    if (widget.currentUserId.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot>(
      stream: _notificationsStream,
      builder: (context, snap) {
        if (snap.hasError) return const SizedBox.shrink();
        final unread = snap.data?.docs.length ?? 0;
        // Semantics: bell icon with optional unread count badge.
        // Without an explicit Semantics wrapper, screen readers announce
        // "image" and miss both the action AND the unread count.
        return Semantics(
          button: true,
          label: unread > 0
              ? 'Notifications, $unread unread'
              : 'Notifications',
          child: GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.notifications_none_rounded,
                    size: 20, color: Color(0xFF1A1A2E)),
              ),
              if (unread > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        unread > 9 ? '9+' : '$unread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        );
      },
    );
  }


  // ── AI Re-Engagement Card ─────────────────────────────────────────────────

  Widget _buildReengagementCard(Map<String, dynamic> data, String remId) {
    final l10n = AppLocalizations.of(context);
    final expertName = data['expertName'] as String? ?? l10n.homeDefaultExpert;
    final category   = data['category']  as String? ?? '';
    final message    = data['message']   as String? ?? l10n.homeDefaultReengageMsg;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF3730A3)],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4338CA).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // ── Header: badge + dismiss ─────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => FirebaseFirestore.instance
                      .collection('scheduled_reminders')
                      .doc(remId)
                      .update({'isDismissed': true}),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('✨', style: TextStyle(fontSize: 11)),
                      const SizedBox(width: 4),
                      Text(l10n.homeSmartOffer,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Expert avatar + message ─────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    message,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFF6366F1),
                  child: Text(
                    expertName.isNotEmpty ? expertName[0] : '?',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── CTA ────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () =>
                    _openSearch(preselectedCategory: category),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: Text(l10n.homeBookNow,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Urgent / Pulse banner ──────────────────────────────────────────────────

  Widget _buildUrgentBanner(List<QueryDocumentSnapshot> docs, bool isProvider) {
    final l10n = AppLocalizations.of(context);
    final count = docs.length;
    final first = docs.first.data() as Map<String, dynamic>;
    final description = isProvider
        ? (first['description'] ?? first['title'] ?? l10n.urgentBannerServiceNeeded) as String
        : l10n.urgentBannerCustomerWaiting;

    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) {
        final glow = _pulseCtrl.value;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1C1917), Color(0xFF292524)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF59E0B)
                    .withValues(alpha: 0.15 + glow * 0.18),
                blurRadius: 16 + glow * 6,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: isProvider ? _openSearch : widget.onGoToBookings,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    AppLocalizations.of(context).urgentOpenButton,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  description.length > 48
                      ? '${description.substring(0, 48)}...'
                      : description,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B)
                          .withValues(alpha: 0.5 + glow * 0.5),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF59E0B)
                              .withValues(alpha: glow * 0.8),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$count ${isProvider ? l10n.urgentBannerRequests : l10n.urgentBannerPending}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Wolt-style Promotional Carousel ──────────────────────────────────────────
//
// Auto-plays every 5 seconds. Swipeable. Dot indicators at the bottom.
// Banners are defined inline as gradient cards — no network dependency.

// ── Promo banner data model ───────────────────────────────────────────────────
//
// [imageUrl] — if non-empty, renders a network image as background.
//              If empty, falls back to the gradient + icon layout.

class _PromoBanner {
  final List<Color> gradient;
  final String title;
  final String subtitle;
  final IconData icon;
  final String imageUrl;
  const _PromoBanner({
    required this.gradient,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.imageUrl = '',
  });
}

// ── Carousel ──────────────────────────────────────────────────────────────────
//
// ── Pulsing heart icon for the community banner ────────────────────────────

class _HeartPulse extends StatefulWidget {
  const _HeartPulse();

  @override
  State<_HeartPulse> createState() => _HeartPulseState();
}

class _HeartPulseState extends State<_HeartPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _scale = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: const Icon(
        Icons.favorite_rounded,
        color: Color(0xFFD4AF37), // metallic gold heart
        size: 26,
      ),
    );
  }
}

// ── Pastel radial-gradient background for the Home tab ─────────────────────
//
// Base white + 4 soft radial blobs (lavender/pink/violet/sky) anchored at
// corners. Translates the CSS:
//   radial-gradient(circle at X% Y%, rgba(...), transparent 50%) × 4
// into 4 stacked Positioned.fill DecoratedBox layers with RadialGradient
// decorations, each fading to 00-alpha at radius 0.5 — so they compose
// additively rather than clobbering each other.
//
// Important: this is static — no ImageFilter, no ColorFilter.matrix, no
// saturate. Only pure decoration paint. Zero known release-build risk.
class _PastelHomeBackground extends StatelessWidget {
  const _PastelHomeBackground();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.white,
      child: Stack(
        children: [
          // Blob 1 — top-left @ 20% 20%, lavender bright
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.6, -0.6),
                  radius: 0.5,
                  colors: [Color(0x8CC4B5FD), Color(0x00C4B5FD)],
                  stops: [0.0, 1.0],
                ),
              ),
            ),
          ),
          // Blob 2 — top-right @ 80% 15%, soft lavender
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.6, -0.8),
                  radius: 0.5,
                  colors: [Color(0x99DDD6FE), Color(0x00DDD6FE)],
                  stops: [0.0, 1.0],
                ),
              ),
            ),
          ),
          // Blob 3 — bottom-center @ 50% 85%, medium purple
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.0, 0.6),
                  radius: 0.5,
                  colors: [Color(0x66A78BFA), Color(0x00A78BFA)],
                  stops: [0.0, 1.0],
                ),
              ),
            ),
          ),
          // Blob 4 — bottom-left @ 15% 85%, purplish lavender
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.8, 0.8),
                  radius: 0.5,
                  colors: [Color(0x80E9D5FF), Color(0x00E9D5FF)],
                  stops: [0.0, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Glass category card (POC — §glassmorphism phase 1) ─────────────────────
//
// Wraps a category row (header + horizontal sub-strip) in a frosted-glass
// card. Direct Flutter translation of the CSS reference:
//   background: rgba(255, 255, 255, 0.45)
//   backdrop-filter: blur(24px)          ← NO saturate per user decision
//   border: 0.5px solid rgba(255,255,255, 0.9)
//   border-radius: 22px
//   box-shadow: 0 8px 28px rgba(60,40,120,.12), 0 2px 6px rgba(0,0,0,.05)
//
// CSS `inset 0 1px 0 rgba(255,255,255,.95)` (top highlight) isn't natively
// supported by Flutter BoxShadow — approximated via a thin white top border
// through the standard `border`. Bottom inset highlight skipped.
class _GlassCategoryCard extends StatelessWidget {
  const _GlassCategoryCard({
    required this.title,
    required this.onShowAll,
    required this.child,
  });

  final String title;
  final VoidCallback onShowAll;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.9),
              width: 0.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(60, 40, 120, 0.12),
                blurRadius: 28,
                offset: Offset(0, 8),
              ),
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.05),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row: RTL = title on right, "הצג הכל" on left
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E1B4B),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: onShowAll,
                    child: Text(
                      AppLocalizations.of(context).homeShowAll,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF1A1A2E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

// ── AnyTasks banner — Apple Card style (dark premium) ───────────────────────
//
// Dark gradient + subtle purple radial glow + glass-feel icon tile + 2-line
// content block + thin RTL-forward arrow. `AnimatedScale(0.98, 150ms)` on
// tap-down gives the "responsive press" feel. The outer Container clips
// children to its 18px rounded-rect via `clipBehavior: Clip.hardEdge`, so
// the glow at `Positioned(left: -40, top: -40)` is cleanly wedged into the
// top-left corner instead of spilling out.
class _AnyTasksBanner extends StatefulWidget {
  const _AnyTasksBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_AnyTasksBanner> createState() => _AnyTasksBannerState();
}

class _AnyTasksBannerState extends State<_AnyTasksBanner> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1E1B3A),
                Color(0xFF2D1B4E),
                Color(0xFF4A2B7A),
              ],
              stops: [0.0, 0.5, 1.0],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4A2B7A).withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // ── Soft purple radial glow anchored near the top-left corner.
              // Clipped by the Container's rounded rect, so it reads as a
              // diffuse wedge rather than a floating circle.
              Positioned(
                left: -40,
                top: -40,
                width: 140,
                height: 140,
                child: IgnorePointer(
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Color(0x668B5CF6), // #8B5CF6 @ 40%
                          Color(0x008B5CF6), // transparent
                        ],
                        stops: [0.0, 0.7],
                      ),
                    ),
                  ),
                ),
              ),
              // ── Content row: [icon tile] [title + tag + description] [arrow]
              Padding(
                padding:
                    const EdgeInsetsDirectional.fromSTEB(22, 20, 22, 20),
                child: Row(
                  children: [
                    // Glass CTA tile — rounded 14, subtle blur, "פרסם עכשיו"
                    // text instead of an icon. Auto-sizes around its label.
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: BackdropFilter(
                        filter:
                            ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          height: 48,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                              width: 0.5,
                            ),
                          ),
                          child: const Text(
                            '+ פרסם עכשיו',
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    // Title + tag + description
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'AnyTasks',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white
                                      .withValues(alpha: 0.1),
                                  borderRadius:
                                      BorderRadius.circular(8),
                                ),
                                child: Text(
                                  l10n.anyTasksBannerTag,
                                  style: TextStyle(
                                    color: Colors.white
                                        .withValues(alpha: 0.6),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l10n.anyTasksBannerDescription,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              height: 1.45,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Forward arrow — in RTL, visually pointing LEFT = "next"
                    Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Listens to Firestore 'banners' where placement == 'home_carousel'.
// Falls back to 3 hardcoded gradient banners when Firestore returns 0 items.

/// Banners Studio Phase 6 — schedule-hours runtime filter.
///
/// Returns true iff the banner should render at [now] given its
/// `scheduleHours` map (`{sun: [8,12,16], mon: [...], ...}` — 4-hour
/// buckets at 8/12/16/20). Empty/missing map = always-on.
///
/// Bucket assignment:
///   hour 0-7   → none      (banner is OFF unless an admin picks 8 AND
///                            we extend the schema later — for now,
///                            schedule-hours providers off-hours always)
///   hour 8-11  → bucket 8
///   hour 12-15 → bucket 12
///   hour 16-19 → bucket 16
///   hour 20-23 → bucket 20
bool _studioScheduleAllowsNow(dynamic raw, DateTime now) {
  if (raw == null) return true;
  if (raw is! Map) return true;
  if (raw.isEmpty) return true;
  const dayKeys = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
  // DateTime.weekday: Mon=1..Sun=7. Map to our keys (sun-first).
  final dayIdx = now.weekday == 7 ? 0 : now.weekday;
  final key = dayKeys[dayIdx];
  final list = raw[key];
  if (list is! List) return false;
  if (list.isEmpty) return false;
  // Bucket the current hour
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

class _PromoCarousel extends StatefulWidget {
  const _PromoCarousel();

  @override
  State<_PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<_PromoCarousel> {
  final PageController _ctrl = PageController();
  int _currentPage = 0;
  Timer? _timer;

  StreamSubscription<QuerySnapshot>? _bannerSub;
  List<_PromoBanner> _liveBanners = const [];
  bool _firestoreLoaded = false;

  // Icon name → IconData (mirrors the admin _iconLabels map)
  static const _icons = <String, IconData>{
    'stars':             Icons.stars_rounded,
    'school':            Icons.school_rounded,
    'emoji_events':      Icons.emoji_events_rounded,
    'favorite':          Icons.favorite_rounded,
    'bolt':              Icons.bolt_rounded,
    'local_offer':       Icons.local_offer_rounded,
    'rocket_launch':     Icons.rocket_launch_rounded,
    'workspace_premium': Icons.workspace_premium_rounded,
    'celebration':       Icons.celebration_rounded,
    'trending_up':       Icons.trending_up_rounded,
    'handshake':         Icons.handshake_outlined,
    'monetization_on':   Icons.monetization_on_outlined,
  };

  // Localized fallback — resolved at build time so language switches apply
  List<_PromoBanner> _fallbackBanners(BuildContext ctx) {
    final l = AppLocalizations.of(ctx);
    return [
      _PromoBanner(
        gradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
        title: l.homeWelcomeTitle,
        subtitle: l.homeWelcomeSubtitle,
        icon: Icons.handshake_outlined,
      ),
      _PromoBanner(
        gradient: const [Color(0xFF0EA5E9), Color(0xFF6366F1)],
        title: l.homeServiceTitle,
        subtitle: l.homeServiceSubtitle,
        icon: Icons.bolt_outlined,
      ),
      _PromoBanner(
        gradient: const [Color(0xFFF97316), Color(0xFFEC4899)],
        title: l.homeBecomeExpertTitle,
        subtitle: l.homeBecomeExpertSubtitle,
        icon: Icons.trending_up_rounded,
      ),
    ];
  }

  List<_PromoBanner> _getBanners(BuildContext ctx) =>
      (_firestoreLoaded && _liveBanners.isNotEmpty) ? _liveBanners : _fallbackBanners(ctx);

  @override
  void initState() {
    super.initState();
    _startTimer();
    _bannerSub = FirebaseFirestore.instance
        .collection('banners')
        .where('placement', isEqualTo: 'home_carousel')
        .limit(20)
        .snapshots()
        .listen(_onBannerSnapshot);
  }

  void _onBannerSnapshot(QuerySnapshot snap) {
    if (!mounted) return;
    final now = DateTime.now();
    final docs = snap.docs.where((d) {
      final m = d.data() as Map<String, dynamic>;
      final active    = m['isActive']  as bool?      ?? true;
      final expiresAt = (m['expiresAt'] as Timestamp?)?.toDate();
      if (!active) return false;
      if (expiresAt != null && !expiresAt.isAfter(now)) return false;
      // Banners Studio Phase 6 — schedule-hours runtime filter.
      // Admin can pin a banner to specific day-of-week + 4-hour windows.
      // Empty/null = always-on (default behaviour).
      if (!_studioScheduleAllowsNow(m['scheduleHours'], now)) return false;
      return true;
    }).toList()
      ..sort((a, b) {
        final oa = (a.data() as Map<String, dynamic>)['order'] as int? ?? 999;
        final ob = (b.data() as Map<String, dynamic>)['order'] as int? ?? 999;
        return oa.compareTo(ob);
      });

    final parsed = docs.map((d) {
      final m = d.data() as Map<String, dynamic>;
      return _PromoBanner(
        gradient: [
          _hexToColor(m['color1'] as String? ?? '6366F1'),
          _hexToColor(m['color2'] as String? ?? '8B5CF6'),
        ],
        title:    m['title']    as String? ?? '',
        subtitle: m['subtitle'] as String? ?? '',
        icon:     _icons[m['iconName'] as String? ?? 'stars'] ?? Icons.stars_rounded,
        imageUrl: m['imageUrl'] as String? ?? '',
      );
    }).toList();

    setState(() {
      _firestoreLoaded = true;
      _liveBanners = parsed;
      // When switching from fallback (3 items) to live data, reset page
      // if necessary. We use a safe fallback count of 3 (matches fallback list).
      final effectiveCount = _liveBanners.isNotEmpty ? _liveBanners.length : 3;
      if (_currentPage >= effectiveCount) {
        _currentPage = 0;
        if (_ctrl.hasClients) _ctrl.jumpToPage(0);
      }
    });
  }

  static Color _hexToColor(String hex) {
    final clean = hex.replaceAll('#', '').padLeft(6, '0');
    return Color(int.parse('FF$clean', radix: 16));
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final count = _liveBanners.isNotEmpty ? _liveBanners.length : 3;
      if (count == 0) return;
      final next = (_currentPage + 1) % count;
      _ctrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bannerSub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banners = _getBanners(context);
    return SizedBox(
      height: 190,
      child: Stack(
        children: [
          PageView.builder(
            controller: _ctrl,
            itemCount: banners.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (_, i) => _BannerCard(banner: banners[i]),
          ),

          // ── Dot indicators ──────────────────────────────────────────────
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(banners.length, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  final _PromoBanner banner;
  const _BannerCard({required this.banner});

  @override
  Widget build(BuildContext context) {
    // ── Network image banner (Admin-controlled) ──────────────────────────
    if (banner.imageUrl.isNotEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xFFEEEBFF),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.network(
            banner.imageUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            errorBuilder: (_, __, ___) => _GradientBannerContent(banner: banner),
          ),
        ),
      );
    }

    // ── Gradient fallback banner ─────────────────────────────────────────
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: banner.gradient,
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: _GradientBannerContent(banner: banner),
    );
  }
}

class _GradientBannerContent extends StatelessWidget {
  final _PromoBanner banner;
  const _GradientBannerContent({required this.banner});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Text block ──────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  banner.title,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  banner.subtitle,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          // ── Icon ────────────────────────────────────────────────────
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(banner.icon, size: 32, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

// ─── Provider Carousel Rail (Banners v2 §49) ────────────────────────────────
//
// Streams `banners` where placement == 'provider_carousel', filters to
// active + non-expired + has ≥2 providerIds, sorts by `order` client-side
// (no orderBy = no composite index needed), and renders the first
// qualifying banner via the existing ProviderCarouselBanner widget.
//
// The legacy `_PromoCarousel` keeps owning `placement == 'home_carousel'`
// — the two surfaces are deliberately separate (user decision).

class _ProviderCarouselsRail extends StatelessWidget {
  const _ProviderCarouselsRail();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('banners')
          .where('placement', isEqualTo: 'provider_carousel')
          .limit(10)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint('[ProviderCarouselsRail] stream error: ${snap.error}');
          return const SizedBox.shrink();
        }
        if (!snap.hasData) return const SizedBox.shrink();

        final now = DateTime.now();
        final qualifying = snap.data!.docs.where((d) {
          final m = d.data();
          final active = m['isActive'] as bool? ?? true;
          if (!active) return false;
          final expiresAt = (m['expiresAt'] as Timestamp?)?.toDate();
          if (expiresAt != null && !expiresAt.isAfter(now)) return false;
          // Banners Studio Phase 6 schedule-hours filter
          if (!_studioScheduleAllowsNow(m['scheduleHours'], now)) return false;
          final pc = m['providerCarousel'];
          if (pc is! Map<String, dynamic>) return false;
          final ids = (pc['providerIds'] as List?) ?? const [];
          // Banners Studio §51 — allow even a single VIP. Going from 2→1
          // shouldn't make the whole banner vanish from the home tab; the
          // ProviderCarouselBanner widget handles 1-provider mode by
          // rendering a single static card (no rotation animation).
          return ids.whereType<String>().isNotEmpty;
        }).toList()
          ..sort((a, b) {
            final ao = (a.data()['order'] as num?)?.toInt() ?? 999;
            final bo = (b.data()['order'] as num?)?.toInt() ?? 999;
            return ao.compareTo(bo);
          });

        if (qualifying.isEmpty) return const SizedBox.shrink();

        final doc = qualifying.first;
        final data = doc.data();
        final pc = data['providerCarousel'] as Map<String, dynamic>;
        final config = ProviderCarouselConfig.fromMap(pc);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Section title — bundled with the rail so it disappears
            // automatically when no qualifying banner exists (the
            // SizedBox.shrink branch above hides everything).
            const Padding(
              padding: EdgeInsetsDirectional.fromSTEB(0, 10, 0, 4),
              child: Text(
                'נותני השירות ה-VIP שלנו',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827),
                ),
              ),
            ),
            SizedBox(
              height: 190,
              child: ProviderCarouselBanner(
                config: config,
                title: (data['title'] as String?) ?? '',
                bannerId: doc.id,
                height: 190,
                // Both events go through `recordVipBannerEvent` so the
                // banner-level totals AND the per-provider VIP subscription
                // counters stay in sync — the provider's profile VIP card
                // reads `vip_subscriptions/{id}.totalImpressions / .totalClicks`
                // and was stuck on "—" until this CF wired the analytics
                // (§51 follow-up).
                onImpression: (providerId) async {
                  try {
                    await FirebaseFunctions.instance
                        .httpsCallable('recordVipBannerEvent')
                        .call({
                      'providerId': providerId,
                      'eventType': 'impression',
                      'bannerId': doc.id,
                    });
                  } catch (_) {
                    // Fire-and-forget — never block the UI on analytics.
                  }
                },
                onClick: (providerId) async {
                  try {
                    await FirebaseFunctions.instance
                        .httpsCallable('recordVipBannerEvent')
                        .call({
                      'providerId': providerId,
                      'eventType': 'click',
                      'bannerId': doc.id,
                    });
                  } catch (_) {
                    // Fire-and-forget — never block the UI on analytics.
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mockup 10 — Community banner (v2). Black card with gold heart accent +
// 3-stat strip below. Gated by [isCommunityV2EnabledFor] in the parent
// sliver — non-whitelist users render the legacy gradient banner above.
//
// Counts:
// - "8 פתוחות" + "8 בקשות התנדבות פעילות" — one-shot query for
//   `community_requests where status==open` (limit 200).
// - "147 החודש" — one-shot query for completed-this-month (limit 500).
// - "42 מתנדבים" — comes from parent state ([_HomeTabState._volunteerCount]).
//
// Both queries are .get() not .snapshots() so we don't blow read costs
// on a banner-level surface that the user glances at and moves on.
// ─────────────────────────────────────────────────────────────────────────────
class _CommunityBannerV2 extends StatefulWidget {
  const _CommunityBannerV2({
    required this.volunteerCount,
    required this.recentAvatars,
    required this.onTap,
  });

  final int volunteerCount;
  final List<String?> recentAvatars;
  final VoidCallback onTap;

  @override
  State<_CommunityBannerV2> createState() => _CommunityBannerV2State();
}

class _CommunityBannerV2State extends State<_CommunityBannerV2>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  // Convenience getters so the helper methods below can stay almost
  // identical to the pre-refactor StatelessWidget version.
  int get volunteerCount => widget.volunteerCount;
  List<String?> get recentAvatars => widget.recentAvatars;

  @override
  void initState() {
    super.initState();
    // Soft red breathing aura — 2.2 s per half-cycle.
    // CLAUDE.md §49 memory rule: single AnimationController per instance,
    // AnimatedBuilder scoped to the outer glow only, disposed in dispose().
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_pulseCtrl.value);
          // Outer red glow — alpha + blur + spread all breathe together.
          final pulseAlpha = 0.20 + 0.28 * t; // 0.20 → 0.48
          final blur = 18.0 + 18.0 * t;       // 18 → 36
          final spread = 0.0 + 4.0 * t;       // 0 → 4
          return Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(CommunityRadius.panel),
              boxShadow: [
                BoxShadow(
                  color:
                      const Color(0xFFEF4444).withValues(alpha: pulseAlpha),
                  blurRadius: blur,
                  spreadRadius: spread,
                ),
              ],
            ),
            child: child,
          );
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: CommunityColors.primaryWhite,
            borderRadius: const BorderRadius.all(CommunityRadius.panel),
            border: Border.all(
                color: CommunityColors.borderSubtle, width: 0.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F000000), // 6% black
                blurRadius: 48,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildBlackCard(context),
              _buildStatStrip(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlackCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        // Deep red — pairs with the lighter red breathing aura around
        // the outer card. Local override only; the global
        // CommunityColors.darkSurface stays unchanged for other surfaces.
        color: Color(0xFFB91C1C),
        borderRadius: BorderRadius.all(CommunityRadius.cardLg),
      ),
      child: Stack(
        children: [
          // Top-end gold heart icon (RTL-aware via PositionedDirectional).
          const PositionedDirectional(
            top: -4, end: -4,
            child: Opacity(
              opacity: 0.9,
              child: Icon(
                Icons.favorite,
                size: 20,
                color: CommunityColors.goldHeart,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'הכוח לעזור בידיים שלך',
                style: TextStyle(
                  fontFamily: CommunityType.fontFamily,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                  height: 1.2,
                  color: CommunityColors.whiteHigh,
                ),
              ),
              const SizedBox(height: 4),
              FutureBuilder<int>(
                future: _countOpenRequests(),
                builder: (context, snap) {
                  final n = snap.data;
                  return Text(
                    n == null
                        ? 'בקשות התנדבות פעילות באזורך'
                        : '$n בקשות התנדבות פעילות באזורך כעת',
                    style: const TextStyle(
                      fontFamily: CommunityType.fontFamily,
                      fontSize: 12,
                      color: CommunityColors.whiteMid,
                      height: 1.5,
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  if (recentAvatars.isNotEmpty)
                    _Facepile(
                      avatars: recentAvatars,
                      extraCount: volunteerCount > recentAvatars.length
                          ? volunteerCount - recentAvatars.length
                          : 0,
                    ),
                  const Spacer(),
                  // CTA square — translucent white-on-red, matches the
                  // AnyTasks "+ פרסם עכשיו" pill style for consistency.
                  Container(
                    height: 36,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.28),
                        width: 0.5,
                      ),
                    ),
                    child: const Text(
                      '+ אני רוצה להתנדב',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontFamily: CommunityType.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: CommunityColors.whiteHigh,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatStrip(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
      child: FutureBuilder<int>(
        future: _countMonthlyCompletions(),
        builder: (context, snap) {
          final monthly = snap.data;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _miniStat(
                value: monthly == null ? '—' : '$monthly',
                label: 'החודש',
                color: CommunityColors.textPrimary,
              ),
              _miniDivider(),
              _miniStat(
                value: '$volunteerCount',
                label: 'מתנדבים',
                color: CommunityColors.goldHeart,
              ),
              _miniDivider(),
              FutureBuilder<int>(
                future: _countOpenRequests(),
                builder: (context, openSnap) {
                  final open = openSnap.data;
                  return _miniStat(
                    value: open == null ? '—' : '$open',
                    label: 'פתוחות',
                    color: CommunityColors.success,
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  static Widget _miniStat({
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: CommunityType.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: const TextStyle(
            fontFamily: CommunityType.fontFamily,
            fontSize: 10,
            color: CommunityColors.textTertiary,
          ),
        ),
      ],
    );
  }

  static Widget _miniDivider() => Container(
        width: 0.5,
        height: 22,
        color: CommunityColors.borderSubtle,
      );

  // ── Cheap one-shot count queries ────────────────────────────────────
  static Future<int> _countOpenRequests() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('community_requests')
          .where('status', isEqualTo: 'open')
          .limit(200)
          .get();
      return snap.docs.length;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> _countMonthlyCompletions() async {
    try {
      final startOfMonth = Timestamp.fromDate(
        DateTime(DateTime.now().year, DateTime.now().month, 1),
      );
      final snap = await FirebaseFirestore.instance
          .collection('community_requests')
          .where('status', isEqualTo: 'completed')
          .where('completedAt', isGreaterThanOrEqualTo: startOfMonth)
          .limit(500)
          .get();
      return snap.docs.length;
    } catch (_) {
      return 0;
    }
  }
}

class _Facepile extends StatelessWidget {
  const _Facepile({required this.avatars, required this.extraCount});

  final List<String?> avatars;
  final int extraCount;

  @override
  Widget build(BuildContext context) {
    final visible = avatars.take(3).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 26.0 + (visible.length - 1) * 18.0,
          height: 26,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (int i = visible.length - 1; i >= 0; i--)
                PositionedDirectional(
                  start: i * 18.0,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: CommunityColors.darkSurface,
                        width: 1.5,
                      ),
                    ),
                    child: ClipOval(
                      child: () {
                        final img = safeImageProvider(visible[i]);
                        if (img != null) {
                          return Image(
                            image: img,
                            fit: BoxFit.cover,
                          );
                        }
                        return Container(
                          color: const Color(0xFF4F46E5),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.person_rounded,
                            size: 14,
                            color: Color(0xB3FFFFFF),
                          ),
                        );
                      }(),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (extraCount > 0) ...[
          const SizedBox(width: 10),
          Text(
            '+$extraCount פעילים',
            style: const TextStyle(
              fontFamily: CommunityType.fontFamily,
              fontSize: 11,
              color: CommunityColors.whiteAlt,
            ),
          ),
        ],
      ],
    );
  }
}
