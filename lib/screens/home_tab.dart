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

// ─── Public entry point ───────────────────────────────────────────────────────

class HomeTab extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String currentUserId;
  final bool isOnline;
  final void Function(bool) onToggleOnline;
  final VoidCallback onGoToBookings;
  final VoidCallback onGoToChat;
  final VoidCallback onOpenQuickRequest;

  const HomeTab({
    super.key,
    required this.userData,
    required this.currentUserId,
    required this.isOnline,
    required this.onToggleOnline,
    required this.onGoToBookings,
    required this.onGoToChat,
    required this.onOpenQuickRequest,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with SingleTickerProviderStateMixin {
  // ── Pulse animation (urgent banner only) ───────────────────────────────────
  late final AnimationController _pulseCtrl;

  // ── Firestore streams ─────────────────────────────────────────────────────
  late final Stream<QuerySnapshot> _categoriesStream;
  late final Stream<QuerySnapshot> _urgentStream;
  late final Stream<QuerySnapshot> _notificationsStream;

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

    // Category grid — top-level categories ordered by admin-defined order
    _categoriesStream = FirebaseFirestore.instance
        .collection('categories')
        .orderBy('order')
        .limit(50)
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

    // Back-fill missing category images once per app session
    VisualFetcherService.backfillAll();
  }

  @override
  void dispose() {
    _onlineSub.cancel();
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

  String _greeting(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final h = DateTime.now().hour;
    if (h < 12) return '${l10n.greetingMorning} ☀️';
    if (h < 17) return '${l10n.greetingAfternoon} 🌤️';
    if (h < 21) return '${l10n.greetingEvening} 🌙';
    return '${l10n.greetingNight} ✨';
  }

  String get _firstName {
    final name = (widget.userData['name'] ?? '') as String;
    return name.contains(' ') ? name.split(' ').first : name;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isProvider = widget.userData['isProvider'] == true;

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

            final mainDocs = allDocs
                .where((d) =>
                    ((d.data() as Map)['parentId'] as String? ?? '').isEmpty)
                .toList();

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

            return CustomScrollView(
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

                // ── Stories row (always visible, independent of search) ────
                SliverToBoxAdapter(
                  child: StoriesRow(isProvider: isProvider),
                ),

                // ── "Discover categories" section title ────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                    child: Text(
                      AppLocalizations.of(context).discoverCategories,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
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
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final doc      = mainDocs[index];
                          final data     = doc.data() as Map<String, dynamic>;
                          final name     = data['name']     as String? ?? '';
                          final imageUrl = data['img']      as String? ?? '';
                          final iconName = data['iconName'] as String? ?? '';
                          final icon     = CategoryService.getIcon(iconName);
                          final hasSubs  = catIdsWithSubs.contains(doc.id);
                          final isTrend  = trendingIds.contains(doc.id);

                          return _HomeCategoryCard(
                            name:       name,
                            imageUrl:   imageUrl,
                            icon:       icon,
                            hasSubs:    hasSubs,
                            isTrending: isTrend,
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
                                    builder: (_) =>
                                        CategoryResultsScreen(categoryName: name),
                                  ),
                                );
                              }
                            },
                          );
                        },
                        childCount: mainDocs.length,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount:   4,
                        crossAxisSpacing: 6,
                        mainAxisSpacing:  6,
                        childAspectRatio: 0.82,
                      ),
                    ),
                  ),

                // ── Bottom padding (clear the FAB) ─────────────────────────
                const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Greeting header ────────────────────────────────────────────────────────

  Widget _buildHeader(bool isProvider) {
    final l10n = AppLocalizations.of(context);
    final profileImage = (widget.userData['profileImage'] ?? '') as String;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Left actions ───────────────────────────────────────────────
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Online / Offline toggle for providers
              if (isProvider)
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

              if (isProvider) const SizedBox(width: 8),

              // ── Notifications bell with unread badge ──────────────────
              _buildNotificationBell(),

              const SizedBox(width: 6),

              // ── AI Support Assistant ──────────────────────────────────
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

              // ── Admin: test email button ───────────────────────────────
              if (FirebaseAuth.instance.currentUser?.email ==
                  'adawiavihai@gmail.com') ...[
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

          // ── Right: greeting + avatar ───────────────────────────────────
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_greeting(context)}, $_firstName',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  Text(
                    isProvider ? l10n.homeProviderGreetingSub : l10n.homeCustomerGreetingSub,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFEEF2FF),
                backgroundImage: profileImage.isNotEmpty
                    ? NetworkImage(profileImage)
                    : null,
                child: profileImage.isEmpty
                    ? Text(
                        _firstName.isNotEmpty
                            ? _firstName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Color(0xFF6366F1),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      )
                    : null,
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

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: GestureDetector(
        onTap: _openSearch,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded,
                  color: Color(0xFF6366F1), size: 20),
              const SizedBox(width: 10),
              Text(
                AppLocalizations.of(context).searchPlaceholder,
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
            ],
          ),
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

// ─── Home category card ───────────────────────────────────────────────────────
//
// Mirrors _CategoryCard from search_page.dart — same press-down animation,
// same CategoryImageBackground, same label / sub-category / trending badge.
// Admin edit is intentionally omitted; editing lives in the Search tab.

class _HomeCategoryCard extends StatefulWidget {
  final String      name;
  final String      imageUrl;
  final IconData    icon;
  final bool        hasSubs;
  final bool        isTrending;
  final VoidCallback onTap;

  const _HomeCategoryCard({
    required this.name,
    required this.imageUrl,
    required this.icon,
    required this.onTap,
    this.hasSubs    = false,
    this.isTrending = false,
  });

  @override
  State<_HomeCategoryCard> createState() => _HomeCategoryCardState();
}

class _HomeCategoryCardState extends State<_HomeCategoryCard> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final double scale = _pressed ? 0.97 : (_hovered ? 1.04 : 1.0);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
      onTap: widget.onTap,
      onTapDown:  (_) => setState(() => _pressed = true),
      onTapUp:    (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        transform: Matrix4.identity()
          ..scaleByDouble(scale, scale, 1.0, 1.0),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                  alpha: _pressed ? 0.22 : (_hovered ? 0.20 : 0.10)),
              blurRadius:  _pressed ? 16 : (_hovered ? 22 : 8),
              spreadRadius: _pressed ? 0  : (_hovered ? 2  : -2),
              offset: Offset(0, _pressed ? 6 : (_hovered ? 8 : 4)),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Rich background image with indigo overlay ──────────────
              CategoryImageBackground(imageUrl: widget.imageUrl),

              // ── Label block — bottom of card ───────────────────────────
              Positioned(
                bottom: 5,
                left:   5,
                right:  5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Icon(widget.icon, color: Colors.white, size: 11),
                    const SizedBox(height: 2),
                    Text(
                      widget.name,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color:      Colors.white,
                        fontSize:   10,
                        fontWeight: FontWeight.bold,
                        height:     1.2,
                      ),
                    ),
                    if (widget.hasSubs) ...[
                      const SizedBox(height: 1),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Icon(Icons.keyboard_arrow_left,
                              color: Colors.white70, size: 9),
                          Text(AppLocalizations.of(context).subCategoryPrompt,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 8)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // ── 🔥 Trending badge — top-left ───────────────────────────
              if (widget.isTrending)
                Positioned(
                  top:  4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF6B35), Color(0xFFE8134E)],
                        begin: Alignment.topLeft,
                        end:   Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('🔥', style: TextStyle(fontSize: 9)),
                  ),
                ),
            ],
          ),
        ),
      ),    // close AnimatedContainer
      ),    // close GestureDetector (child: of MouseRegion)
    );      // close MouseRegion + return
  }
}
