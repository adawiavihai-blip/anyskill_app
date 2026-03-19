// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/category_service.dart';
import '../l10n/app_localizations.dart';
import '../services/visual_fetcher_service.dart';
import '../widgets/category_image_card.dart';
import 'category_results_screen.dart';
import 'notifications_screen.dart';
import 'help_center_screen.dart';
import 'sub_category_screen.dart';
import 'search_screen/search_page.dart';
import 'search_screen/widgets/stories_row.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/category_edit_sheet.dart';
import '../services/settings_service.dart';
import 'academy_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/anyskill_logo.dart';

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
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _settingsStream;

  // ── Avatar press feedback ─────────────────────────────────────────────────
  bool _avatarTapped = false;

  // ── Inline category search ────────────────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // ── Live online status ─────────────────────────────────────────────────────
  // HomeTab lives inside a Navigator route created by _nestedTab(). When
  // home_screen.dart's StreamBuilder rebuilds with a new isOnline value, the
  // route's builder is NOT re-invoked — _isOnline stays frozen at the
  // value from first render. We fix this by owning a Firestore subscription
  // here, making the toggle button always reactive regardless of the prop.
  late bool _isOnline;
  late final StreamSubscription<DocumentSnapshot> _onlineSub;

  @override
  void initState() {
    super.initState();

    // Initialise from the prop so the button shows the correct state
    // immediately on first paint (before Firestore fires).
    _isOnline = widget.isOnline;

    // Subscribe to the live isOnline field from Firestore.
    _onlineSub = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.currentUserId)
        .snapshots()
        .listen((snap) {
      final live = snap.data()?['isOnline'] == true;
      if (mounted && live != _isOnline) {
        setState(() => _isOnline = live);
      }
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
        .snapshots();

    // Urgent banner — providers see open job requests, customers see pending approvals
    final uid        = widget.currentUserId;
    final isProvider = widget.userData['isProvider'] == true;
    final category   = (widget.userData['serviceType'] ?? '') as String;

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
    _notificationsStream = uid.isEmpty
        ? const Stream.empty()
        : FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: uid)
            .where('isRead', isEqualTo: false)
            .limit(20)
            .snapshots();

    // Global card-size settings stream
    _settingsStream = SettingsService.stream;

    // Back-fill missing category images once per app session
    VisualFetcherService.backfillAll();
  }

  @override
  void dispose() {
    _onlineSub.cancel();
    _pulseCtrl.dispose();
    _searchCtrl.dispose();
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
        FirebaseAuth.instance.currentUser?.email == 'adawiavihai@gmail.com';

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
                .where((d) =>
                    ((d.data() as Map)['parentId'] as String? ?? '').isEmpty)
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

            // Inline search filter — empty query shows everything
            final q = _searchQuery.toLowerCase();
            final filteredDocs = q.isEmpty
                ? mainDocs
                : mainDocs.where((d) {
                    final name =
                        ((d.data() as Map)['name'] as String? ?? '')
                            .toLowerCase();
                    return name.contains(q);
                  }).toList();

            final catIdsWithSubs = allDocs
                .where((d) =>
                    ((d.data() as Map)['parentId'] as String? ?? '').isNotEmpty)
                .map((d) => (d.data() as Map)['parentId'] as String)
                .toSet();

            // Top-3 by bookingCount earn the 🔥 trending badge
            final trendingIds = (List.of(mainDocs)
                  ..sort((a, b) {
                    final bA = ((a.data() as Map)['bookingCount'] as num? ?? 0);
                    final bB = ((b.data() as Map)['bookingCount'] as num? ?? 0);
                    return bB.compareTo(bA);
                  }))
                .where((d) =>
                    (((d.data() as Map)['bookingCount'] as num?) ?? 0) > 0)
                .take(3)
                .map((d) => d.id)
                .toSet();

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

                // ── Search bar (tappable → SearchPage) ────────────────────
                SliverToBoxAdapter(
                  child: _buildSearchBar(),
                ),

                // ── Urgent / Pulse banner (only when there is data) ────────
                SliverToBoxAdapter(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _urgentStream,
                    builder: (context, urgSnap) {
                      // Offline providers don't receive the urgent pulse
                      // (aligns with FCM topic logic — no notifications while offline)
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

                // ── No search results ──────────────────────────────────────
                else if (filteredDocs.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.search_off_rounded,
                                size: 48, color: Color(0xFFCBD5E1)),
                            const SizedBox(height: 12),
                            Text(
                              'לא נמצאה קטגוריה עבור "$_searchQuery"',
                              style: TextStyle(
                                  color: Colors.grey[500], fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )

                // ── Full visual category grid ──────────────────────────────
                else ...[
                  // ── AnySkill Community banner ──────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
                      child: GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CategoryResultsScreen(
                              categoryName: 'volunteer',
                              volunteerOnly: true,
                            ),
                          ),
                        ),
                        child: Container(
                          height: 60, // was 80 — 25% reduction
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF10B981), Color(0xFFF59E0B)],
                              begin: Alignment.centerRight,
                              end: Alignment.centerLeft,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF10B981)
                                    .withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 12),
                              const Icon(Icons.volunteer_activism,
                                  color: Colors.white, size: 24), // was 32
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'AnySkill למען הקהילה',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14, // was 16
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'מומחים שמתנדבים מרצונם – ללא עלות',
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.88),
                                        fontSize: 11, // was 12
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_left,
                                  color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Stylized Story Carousel strip ─────────────────────
                  SliverToBoxAdapter(
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8F8F8),
                        border: Border.symmetric(
                          horizontal: BorderSide(
                            color: Color(0xFFE5E7EB),
                            width: 0.8,
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // "Live" header label
                          Padding(
                            padding: const EdgeInsetsDirectional.only(
                                start: 14, bottom: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEF4444),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: const Text(
                                    'לייב',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'עדכונים חיים מהמומחים',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF6B7280),
                                    letterSpacing: 0.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          StoriesRow(isProvider: isProvider),
                        ],
                      ),
                    ),
                  ),

                  // ── Search results count (only when filtering) ─────────
                  if (_searchQuery.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: Text(
                          '${filteredDocs.length} קטגוריות',
                          style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),

                  // ── Responsive category grid — driven by global card scale ──
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _settingsStream,
                    builder: (context, settingsSnap) {
                      final globalScale =
                          SettingsService.cardScaleFrom(settingsSnap.data);
                      final w    = MediaQuery.sizeOf(context).width;
                      // Mobile: 3 cols — compact tiles so 4+ rows fit above
                      // the fold without scrolling.
                      // Tablet: 3 cols — same comfortable density as before.
                      // Desktop: 4 cols — unchanged.
                      final cols    = w >= 900 ? 4 : 3;
                      final spacing = w >= 600 ? 8.0 : 6.0;
                      // Aspect ratio: wider-than-tall for compact mobile tiles.
                      // Scale UP (globalScale > 1) → cards taller → ratio lower.
                      final baseRatio = w >= 900 ? 1.0 : w >= 600 ? 1.0 : 1.05;
                      final adjustedRatio =
                          (baseRatio / globalScale).clamp(0.35, 2.0);

                      return SliverPadding(
                        padding: EdgeInsets.fromLTRB(spacing, 0, spacing, 0),
                        sliver: SliverGrid(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final doc      = filteredDocs[index];
                              final data     = doc.data() as Map<String, dynamic>;
                              final name     = data['name']      as String? ?? '';
                              final imageUrl = data['img']       as String? ?? '';
                              final iconName = data['iconName']  as String? ?? '';
                              final icon     = CategoryService.getIcon(iconName);
                              final hasSubs  = catIdsWithSubs.contains(doc.id);
                              final isTrend  = trendingIds.contains(doc.id);
                              // Per-card scale — visual zoom within fixed grid cell
                              final perCardScale =
                                  (data['cardScale'] as num? ?? 1.0).toDouble();

                              return RepaintBoundary(
                               child: _HomeCategoryCard(
                                docId:        doc.id,
                                name:         name,
                                iconName:     iconName,
                                imageUrl:     imageUrl,
                                icon:         icon,
                                hasSubs:      hasSubs,
                                isTrending:   isTrend,
                                isAdmin:      isAdmin,
                                perCardScale: perCardScale,
                                onTap: () {
                                  if (hasSubs) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => SubCategoryScreen(
                                          parentId:   doc.id,
                                          parentName: name,
                                        ),
                                      ),
                                    );
                                  } else {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => CategoryResultsScreen(
                                            categoryName: name),
                                      ),
                                    );
                                  }
                                },
                              )); // RepaintBoundary
                            },
                            childCount: filteredDocs.length,
                          ),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount:   cols,
                            crossAxisSpacing: 10,
                            mainAxisSpacing:  10,
                            childAspectRatio: adjustedRatio,
                          ),
                        ),
                      );
                    },
                  ),
                ], // end else [...] community + grid

                // ── Bottom padding (clear the FAB) ─────────────────────────
                const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
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
    final profileImage = (widget.userData['profileImage'] ?? '') as String;
    final isAdmin      =
        FirebaseAuth.instance.currentUser?.email == 'adawiavihai@gmail.com';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Left: Bell · AI · Admin ────────────────────────────────────
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildNotificationBell(),

              const SizedBox(width: 8),

              // Academy shortcut
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AcademyScreen()),
                ),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color:
                            const Color(0xFF6366F1).withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.school_rounded,
                      size: 18, color: Color(0xFF6366F1)),
                ),
              ),

              const SizedBox(width: 8),

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
                const SizedBox(width: 8),
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

          // ── Center: Static brand logo — size driven by admin slider ────
          Expanded(
            child: Center(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _settingsStream,
                builder: (context, snap) {
                  final size = ((snap.data?.data() ?? {})['headerLogoSize']
                          as num? ?? 32)
                      .toDouble();
                  return AnySkillBrandIcon(size: size);
                },
              ),
            ),
          ),

          // ── Right: Online toggle (providers) + Avatar ──────────────────
          Row(
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
                const SizedBox(width: 10),
              ],

              // Profile avatar — tap navigates to Profile tab
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
                    // CachedNetworkImageProvider: disk-cached, no re-download
                    // on every build, and gracefully falls back on error.
                    backgroundImage: profileImage.isNotEmpty
                        ? CachedNetworkImageProvider(
                            profileImage,
                            maxWidth:  88, // 44px radius × 2× DPR
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
        ],
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
          const SnackBar(
            content: Text('מייל בדיקה נשלח! בדוק את תיבת הדואר.'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Notification bell with live unread badge ───────────────────────────────

  Widget _buildNotificationBell() {
    if (widget.currentUserId.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot>(
      stream: _notificationsStream,
      builder: (context, snap) {
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

  // ── Search bar ─────────────────────────────────────────────────────────────
  // Real TextField: filters the home category grid in real-time.
  // The 🔍 icon on the right opens the full expert SearchPage.

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: Row(
        children: [
          // ── Inline category filter ─────────────────────────────────────
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: TextField(
                controller: _searchCtrl,
                textAlign: TextAlign.right,
                textAlignVertical: TextAlignVertical.center,
                style: const TextStyle(fontSize: 14),
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 0),
                  hintText: AppLocalizations.of(context).searchPlaceholder,
                  hintStyle:
                      TextStyle(color: Colors.grey[400], fontSize: 14),
                  prefixIcon: _searchQuery.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: AnySkillBrandIcon(size: 20),
                        )
                      : IconButton(
                          icon: const Icon(Icons.close_rounded,
                              size: 18, color: Color(0xFF94A3B8)),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        ),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // ── Expert search button ───────────────────────────────────────
          GestureDetector(
            onTap: _openSearch,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.search_rounded,
                  color: Colors.white, size: 22),
            ),
          ),
        ],
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

// ─── Home category card ───────────────────────────────────────────────────────
//
// Mirrors _CategoryCard from search_page.dart — same press-down animation,
// same CategoryImageBackground, same label / sub-category / trending badge.
// Admin edit is intentionally omitted; editing lives in the Search tab.

class _HomeCategoryCard extends StatefulWidget {
  final String      docId;        // Firestore document ID — needed by edit sheet
  final String      name;
  final String      iconName;     // Raw icon key — needed by edit sheet
  final String      imageUrl;
  final IconData    icon;
  final bool        hasSubs;
  final bool        isTrending;
  final bool        isAdmin;      // When true the edit pencil overlay is shown
  final double      perCardScale; // Visual zoom within fixed grid cell (default 1.0)
  final VoidCallback onTap;

  const _HomeCategoryCard({
    required this.docId,
    required this.name,
    required this.iconName,
    required this.imageUrl,
    required this.icon,
    required this.onTap,
    this.hasSubs      = false,
    this.isTrending   = false,
    this.isAdmin      = false,
    this.perCardScale = 1.0,
  });

  @override
  State<_HomeCategoryCard> createState() => _HomeCategoryCardState();
}

class _HomeCategoryCardState extends State<_HomeCategoryCard> {
  bool _pressed = false;
  bool _hovered = false;

  void _openEditSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,    // lets the sheet resize with the keyboard
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => CategoryEditSheet(
        docId:             widget.docId,
        initialName:       widget.name,
        initialIconName:   widget.iconName,
        initialImageUrl:   widget.imageUrl,
        initialCardScale:  widget.perCardScale,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Card-level transform: subtle press-down only (no hover card-scale).
    // The premium "zoom" lives inside the image layer via AnimatedScale.
    final double cardScale  = _pressed ? 0.97 : 1.0;
    // Image zoom: hover → 1.06 (desktop preview),  press → slight warm-up.
    final double imageScale = _hovered ? 1.06 : (_pressed ? 1.02 : 1.0);

    return Transform.scale(
      scale: widget.perCardScale,
      child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
      onTap: () {
        // Fire-and-forget — FieldValue.increment is atomic, catchError
        // inside the service means a network error never blocks navigation.
        CategoryService.incrementClickCount(widget.docId);
        widget.onTap();
      },
      onTapDown:   (_) => setState(() => _pressed = true),
      onTapUp:     (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        transform: Matrix4.identity()
          ..scaleByDouble(cardScale, cardScale, 1.0, 1.0),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            // Primary shadow — lifts more on hover
            BoxShadow(
              color: Colors.black.withValues(
                  alpha: _hovered ? 0.24 : (_pressed ? 0.18 : 0.10)),
              blurRadius:   _hovered ? 24 : (_pressed ? 14 : 8),
              spreadRadius: _hovered ? 0  : -1,
              offset: Offset(0, _hovered ? 10 : (_pressed ? 5 : 4)),
            ),
            // Subtle indigo tint shadow for the premium glow feel
            if (_hovered)
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.14),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Rich background image with indigo overlay ──────────────
              CategoryImageBackground(
                  imageUrl: widget.imageUrl, imageScale: imageScale),

              // ── Label block ────────────────────────────────────────────
              Positioned(
                bottom: 8,
                left:   8,
                right:  8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Icon(widget.icon, color: Colors.white, size: 15),
                    const SizedBox(height: 3),
                    Text(
                      widget.name,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color:      Colors.white,
                        fontSize:   12,
                        fontWeight: FontWeight.bold,
                        height:     1.2,
                      ),
                    ),
                    if (widget.hasSubs) ...[
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Icon(Icons.keyboard_arrow_left,
                              color: Colors.white70, size: 11),
                          Text(AppLocalizations.of(context).subCategoryPrompt,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 9)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // ── 🔥 Trending badge — top-left ───────────────────────────
              if (widget.isTrending)
                Positioned(
                  top:  10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF6B35), Color(0xFFE8134E)],
                        begin: Alignment.topLeft,
                        end:   Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('🔥', style: TextStyle(fontSize: 11)),
                  ),
                ),

              // ── ✏️ Admin edit button — top-right ───────────────────────
              // Completely invisible to regular users and providers.
              // Inner GestureDetector absorbs the tap before it reaches the
              // outer card GestureDetector, so the card does NOT navigate.
              if (widget.isAdmin)
                Positioned(
                  top:   10,
                  right: 10,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _openEditSheet,
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color:  Colors.black.withValues(alpha: 0.55),
                        shape:  BoxShape.circle,
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
      ),    // close AnimatedContainer
      ),    // close GestureDetector (child: of MouseRegion)
      ),    // close MouseRegion (child: of Transform.scale)
    );      // close Transform.scale + return
  }
}
