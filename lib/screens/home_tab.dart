// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../l10n/app_localizations.dart';
import '../services/visual_fetcher_service.dart';
import 'category_results_screen.dart';
import 'notifications_screen.dart';
import 'help_center_screen.dart';
import 'sub_category_screen.dart';
import 'search_screen/search_page.dart';
import 'search_screen/widgets/stories_row.dart';
import 'community_hub_screen.dart';
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

  @override
  void initState() {
    super.initState();

    // Seed from prop immediately — correct state on first paint.
    _isOnline        = widget.isOnline;
    _profileImageUrl = (widget.userData['profileImage'] as String? ?? '');

    // Subscribe to the live user doc — updates both online status AND avatar.
    _onlineSub = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.currentUserId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final data = snap.data() ?? {};
      final live = data['isOnline'] == true;
      final img  = data['profileImage'] as String? ?? '';
      setState(() {
        _isOnline        = live;
        _profileImageUrl = img;
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
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: _categoriesStream,
          builder: (context, catSnap) {
            // ── Pre-process category data ─────────────────────────────────
            final allDocs = catSnap.data?.docs ?? [];

            // All top-level categories, sorted by popularity:
            //   1. clickCount DESC  2. order ASC  3. name ASC
            final mainDocs = allDocs
                .where((d) {
                  final data = d.data() as Map;
                  final parentId = (data['parentId'] as String? ?? '');
                  final isHidden = data['isHidden'] as bool? ?? false;
                  return parentId.isEmpty && !isHidden;
                })
                .toList()
              ..sort((a, b) {
                final cA =
                    ((a.data() as Map)['clickCount'] as num? ?? 0).toInt();
                final cB =
                    ((b.data() as Map)['clickCount'] as num? ?? 0).toInt();
                if (cA != cB) return cB.compareTo(cA);
                final oA =
                    ((a.data() as Map)['order'] as num? ?? 999).toInt();
                final oB =
                    ((b.data() as Map)['order'] as num? ?? 999).toInt();
                if (oA != oB) return oA.compareTo(oB);
                return (((a.data() as Map)['name'] as String?) ?? '')
                    .compareTo(((b.data() as Map)['name'] as String?) ?? '');
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
      // Inject promo carousel between 2nd and 3rd parent sections.
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
      final subs       = subsByParent[parentDoc.id] ?? [];
      final hasSubs    = subs.isNotEmpty;

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
                      widget.currentUserId, parentName);
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
                    color: Color(0xFF6366F1),
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
                        widget.currentUserId, subName);
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
                        widget.currentUserId, parentName);
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

    // ── AnyTasks banner — "משימות מיקרו" gig marketplace entry ──────
    slivers.add(SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: GestureDetector(
          onTap: () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(builder: (_) => const MyTasksScreen())),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFFA855F7)],
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.rocket_launch_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AnyTasks',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppLocalizations.of(context).homeMicroTasks,
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: Colors.white54),
              ],
            ),
          ),
        ),
      ),
    ));

    // ── Community tile — "נתינה מהלב" with facepile + pulse ─────────
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
        return GestureDetector(
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

// Listens to Firestore 'banners' where placement == 'home_carousel'.
// Falls back to 3 hardcoded gradient banners when Firestore returns 0 items.

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
      return active && (expiresAt == null || expiresAt.isAfter(now));
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
