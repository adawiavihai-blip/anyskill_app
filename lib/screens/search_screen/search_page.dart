import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:async';
import 'dart:ui';
import '../category_results_screen.dart';
import '../sub_category_screen.dart';
import '../notifications_screen.dart';
import '../../services/category_service.dart';

// ─── Discover / Search page ──────────────────────────────────────────────────

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Search bar ──────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _searchQuery = v.trim()),
        textAlign: TextAlign.right,
        textDirection: TextDirection.rtl,
        decoration: InputDecoration(
          hintText: 'מה תרצה ללמוד היום?',
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
          suffixIcon: const Padding(
            padding: EdgeInsets.only(left: 14),
            child: Icon(Icons.search_rounded, color: Colors.grey),
          ),
          prefixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.grey, size: 20),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: const Color(0xFFF5F6FA),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide:
                const BorderSide(color: Color(0xFF007AFF), width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isAdmin =
        FirebaseAuth.instance.currentUser?.email == 'adawiavihai@gmail.com';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NotificationBadge(
                    child: IconButton(
                      icon: const Icon(Icons.notifications_outlined, size: 24),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const NotificationsScreen()),
                      ),
                    ),
                  ),
                  const Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          "גלה מומחים",
                          style: TextStyle(
                              fontSize: 26, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        SizedBox(height: 2),
                        Text(
                          "בחר תחום ומצא את המומחה המושלם",
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── Search bar ────────────────────────────────────────────────
            _buildSearchBar(),

            const SizedBox(height: 8),

            // ── Banner — OUTSIDE the categories StreamBuilder/LayoutBuilder ──
            // AnimatedSize collapses it smoothly when search is active.
            // _BannerCarousel has a const constructor so it is never rebuilt
            // by _SearchPageState.setState — it owns its own state/timer/sub.
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOut,
              child: _searchQuery.isEmpty
                  ? const _BannerCarousel()
                  : const SizedBox.shrink(),
            ),

            // ── Categories ────────────────────────────────────────────────
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('categories')
                    .orderBy('order')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(
                      child: Text(
                        "לא נמצאו קטגוריות.\nבצע אתחול מלוח הניהול.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 15),
                      ),
                    );
                  }

                  final allDocs = snapshot.data!.docs;
                  final mainDocs = allDocs
                      .where((d) =>
                          ((d.data() as Map)['parentId'] as String? ?? '')
                              .isEmpty)
                      .toList();
                  final catIdsWithSubs = allDocs
                      .where((d) =>
                          ((d.data() as Map)['parentId'] as String? ?? '')
                              .isNotEmpty)
                      .map((d) => (d.data() as Map)['parentId'] as String)
                      .toSet();

                  // Top-3 categories by bookingCount → get "Trending" badge
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

                  final filtered = _searchQuery.isEmpty
                      ? mainDocs
                      : mainDocs.where((d) {
                          final n = ((d.data() as Map)['name'] as String? ?? '')
                              .toLowerCase();
                          return n.contains(_searchQuery.toLowerCase());
                        }).toList();

                  if (_searchQuery.isNotEmpty && filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off_rounded,
                              size: 60, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          Text(
                            'לא נמצאו תוצאות עבור "$_searchQuery"',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 15),
                          ),
                        ],
                      ),
                    );
                  }

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final cols = w >= 900 ? 4 : w >= 600 ? 3 : 2;
                      final ratio =
                          w >= 900 ? 1.1 : w >= 600 ? 1.0 : 1.0;

                      return CustomScrollView(
                        slivers: [
                          // Section label
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                              child: Text(
                                _searchQuery.isEmpty
                                    ? "קטגוריות"
                                    : 'תוצאות עבור "$_searchQuery"',
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ),

                          // Category grid
                          SliverPadding(
                            padding:
                                const EdgeInsets.fromLTRB(12, 0, 12, 100),
                            sliver: SliverGrid(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final doc = filtered[index];
                                  final data =
                                      doc.data() as Map<String, dynamic>;
                                  final name =
                                      data['name'] as String? ?? '';
                                  final imageUrl =
                                      data['img'] as String? ?? '';
                                  final iconName =
                                      data['iconName'] as String? ?? '';
                                  final icon =
                                      CategoryService.getIcon(iconName);
                                  final hasSubs =
                                      catIdsWithSubs.contains(doc.id);

                                  return _CategoryCard(
                                    docId: doc.id,
                                    name: name,
                                    imageUrl: imageUrl,
                                    icon: icon,
                                    isAdmin: isAdmin,
                                    hasSubs: hasSubs,
                                    isTrending: trendingIds.contains(doc.id),
                                    onTap: () {
                                      if (hasSubs) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                SubCategoryScreen(
                                              parentId: doc.id,
                                              parentName: name,
                                            ),
                                          ),
                                        );
                                      } else {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                CategoryResultsScreen(
                                                    categoryName: name),
                                          ),
                                        );
                                      }
                                    },
                                  );
                                },
                                childCount: filtered.length,
                              ),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: ratio,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Banner carousel — completely isolated StatefulWidget ─────────────────────
//
// Has a `const` constructor so the parent's setState never rebuilds it.
// Owns its own PageController, Timer, and Firestore subscription.
// The PageView therefore never gets torn down by unrelated rebuilds.

class _BannerCarousel extends StatefulWidget {
  const _BannerCarousel();

  @override
  State<_BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<_BannerCarousel> {
  // Fixed dimensions — never change, so no layout jumps
  static const double _cardH  = 118.0;
  static const double _totalH = 141.0; // cardH + 10 gap + 7 dots + 6 padding

  final PageController _ctrl = PageController();
  int  _currentPage = 0;
  bool _loading     = true;
  Timer? _timer;
  StreamSubscription<QuerySnapshot>? _sub;

  List<Map<String, dynamic>> _liveBanners  = [];
  // Only update _memoKey when doc IDs actually change, to skip no-op rebuilds
  String _memoKey = '';

  // ── Fallback shown while Firestore loads or collection is empty ─────────────
  static const _fallback = <Map<String, dynamic>>[
    {'title': 'מצא מומחים מובילים', 'subtitle': 'אלפי מומחים מחכים לך',      'color1': '667eea', 'color2': '764ba2', 'iconName': 'stars'},
    {'title': 'שיעורים פרטיים',      'subtitle': 'ממש מהמקום שאתה נמצא',    'color1': '11998e', 'color2': '38ef7d', 'iconName': 'school'},
    {'title': 'פתח את הפוטנציאל שלך','subtitle': 'עם המומחים הטובים ביותר','color1': 'f953c6', 'color2': 'b91d73', 'iconName': 'emoji_events'},
  ];

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
  };

  static Color _hex(String h) {
    final c = h.replaceAll('#', '').replaceAll('0x', '');
    return Color(int.parse(c.length == 6 ? 'FF$c' : c, radix: 16));
  }

  List<Map<String, dynamic>> get _banners =>
      _liveBanners.isNotEmpty ? _liveBanners : _fallback;

  @override
  void initState() {
    super.initState();

    // Firestore subscription — no where() to avoid composite-index requirement;
    // filter isActive client-side.
    _sub = FirebaseFirestore.instance
        .collection('banners')
        .orderBy('order')
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;

        final newList = snap.docs
            .map((d) => d.data() as Map<String, dynamic>)
            .where((b) => b['isActive'] == true)
            .toList();

        // Memoize by doc-ID string — skip setState if nothing changed
        final newKey = snap.docs.map((d) => d.id).join(',');
        if (!_loading && newKey == _memoKey) return;

        // Clamp the current page if the list shrank
        final clamped = (newList.isNotEmpty && _currentPage >= newList.length)
            ? 0
            : _currentPage;
        final needsJump = clamped != _currentPage;

        setState(() {
          _loading      = false;
          _liveBanners  = newList;
          _currentPage  = clamped;
          _memoKey      = newKey;
        });

        // Sync PageController after frame if the index was clamped
        if (needsJump) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _ctrl.hasClients) _ctrl.jumpToPage(0);
          });
        }
      },
      onError: (_) {
        if (mounted) setState(() => _loading = false);
      },
    );

    // Auto-advance timer
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_ctrl.hasClients) return;
      final count = _banners.length;
      if (count <= 1) return; // nothing to cycle

      // Skip tick if the page is not yet settled (mid-swipe / mid-animation)
      final pos = _ctrl.page ?? 0.0;
      if ((pos - pos.round()).abs() > 0.01) return;

      _ctrl.animateToPage(
        (_currentPage + 1) % count,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ── Fixed-height wrapper prevents ANY layout shift ───────────────────────
    return SizedBox(
      height: _totalH,
      child: _loading ? _buildShimmer() : _buildCarousel(),
    );
  }

  // ── Shimmer skeleton ────────────────────────────────────────────────────────
  Widget _buildShimmer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: _BannerShimmer(height: _cardH),
    );
  }

  // ── Live carousel ───────────────────────────────────────────────────────────
  Widget _buildCarousel() {
    final banners = _banners;
    return Column(
      children: [
        // ── PageView ─────────────────────────────────────────────────────────
        SizedBox(
          height: _cardH,
          child: PageView.builder(
            controller: _ctrl,
            // allowImplicitScrolling keeps the previous & next page alive in
            // memory so there is no widget rebuild on swipe-back.
            allowImplicitScrolling: true,
            physics: const PageScrollPhysics(),
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: banners.length,
            itemBuilder: (context, i) => _BannerPage(
              key: ValueKey(banners[i]['title'] ?? i),
              data: banners[i],
              icons: _icons,
              hexToColor: _hex,
            ),
          ),
        ),

        // ── Dot indicator ─────────────────────────────────────────────────────
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            banners.length,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width:  _currentPage == i ? 20 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: _currentPage == i
                    ? const Color(0xFF007AFF)
                    : Colors.grey[300],
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Individual banner page — kept alive by AutomaticKeepAliveClientMixin ─────
//
// This prevents Flutter from rebuilding a page when it slides back into view
// after being paged past. Without this, each page is torn down & recreated
// during every swipe, causing visible flicker.

class _BannerPage extends StatefulWidget {
  final Map<String, dynamic> data;
  final Map<String, IconData> icons;
  final Color Function(String) hexToColor;

  const _BannerPage({
    super.key,
    required this.data,
    required this.icons,
    required this.hexToColor,
  });

  @override
  State<_BannerPage> createState() => _BannerPageState();
}

class _BannerPageState extends State<_BannerPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin

    final b        = widget.data;
    final color1   = widget.hexToColor(b['color1'] as String? ?? '667eea');
    final color2   = widget.hexToColor(b['color2'] as String? ?? '764ba2');
    final icon     = widget.icons[b['iconName'] as String? ?? 'stars'] ??
        Icons.stars_rounded;
    final title    = b['title']    as String? ?? '';
    final subtitle = b['subtitle'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: color2.withValues(alpha: 0.30),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color1, color2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              // Decorative circles
              Positioned(left: -25, top: -25,
                child: Container(width: 120, height: 120,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.12)))),
              Positioned(left: 40, bottom: -35,
                child: Container(width: 90, height: 90,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08)))),
              Positioned(right: -15, top: -15,
                child: Container(width: 70, height: 70,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.07)))),

              // Content row
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Glass icon box
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.35),
                                width: 1,
                              ),
                            ),
                            child: Icon(icon, color: Colors.white, size: 24),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Text block
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              title,
                              textAlign: TextAlign.right,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                height: 1.25,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 5),
                            // Glass subtitle pill
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.28),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.92),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Banner shimmer placeholder ───────────────────────────────────────────────

class _BannerShimmer extends StatefulWidget {
  final double height;
  const _BannerShimmer({required this.height});

  @override
  State<_BannerShimmer> createState() => _BannerShimmerState();
}

class _BannerShimmerState extends State<_BannerShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.5, end: 1.0).animate(
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
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(height: 16, width: double.infinity,
                        decoration: BoxDecoration(color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(8))),
                    const SizedBox(height: 10),
                    Container(height: 12, width: 140,
                        decoration: BoxDecoration(color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(8))),
                  ],
                ),
              ),
              const SizedBox(width: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Category card — StatefulWidget for press-elevation feedback ──────────────

class _CategoryCard extends StatefulWidget {
  final String docId;
  final String name;
  final String imageUrl;
  final IconData icon;
  final bool isAdmin;
  final bool hasSubs;
  final bool isTrending;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.docId,
    required this.name,
    required this.imageUrl,
    required this.icon,
    required this.isAdmin,
    required this.onTap,
    this.hasSubs    = false,
    this.isTrending = false,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _pressed = false;

  void _openEditSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditCategorySheet(
        docId: widget.docId,
        currentName: widget.name,
        currentImg: widget.imageUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        transform: Matrix4.identity()..scale(_pressed ? 0.97 : 1.0),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _pressed ? 0.20 : 0.10),
              blurRadius: _pressed ? 20 : 10,
              spreadRadius: _pressed ? 0 : -2,
              offset: Offset(0, _pressed ? 8 : 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                widget.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(color: Colors.grey[200]),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(color: Colors.grey[100]);
                },
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.68),
                    ],
                    stops: const [0.4, 1.0],
                  ),
                ),
              ),
              Positioned(
                bottom: 10, left: 10, right: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Icon(widget.icon, color: Colors.white, size: 18),
                    const SizedBox(height: 3),
                    Text(
                      widget.name,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (widget.hasSubs) ...[
                      const SizedBox(height: 4),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Icon(Icons.keyboard_arrow_left,
                              color: Colors.white70, size: 14),
                          Text("בחר התמחות",
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.isAdmin)
                Positioned(
                  top: 10, right: 10,
                  child: GestureDetector(
                    onTap: () => _openEditSheet(context),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.edit,
                          color: Colors.white, size: 16),
                    ),
                  ),
                ),

              // 🔥 Trending badge — top-left, only on top-3 by bookingCount
              if (widget.isTrending)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF6B35), Color(0xFFE8134E)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE8134E)
                              .withValues(alpha: 0.45),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("🔥", style: TextStyle(fontSize: 11)),
                        SizedBox(width: 3),
                        Text(
                          "טרנד",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Bottom Sheet — edit category ─────────────────────────────────────────────

class _EditCategorySheet extends StatefulWidget {
  final String docId;
  final String currentName;
  final String currentImg;

  const _EditCategorySheet({
    required this.docId,
    required this.currentName,
    required this.currentImg,
  });

  @override
  State<_EditCategorySheet> createState() => _EditCategorySheetState();
}

class _EditCategorySheetState extends State<_EditCategorySheet> {
  late TextEditingController _nameController;
  Uint8List? _newImageBytes;
  String? _newImageName;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 80,
    );
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() {
        _newImageBytes = bytes;
        _newImageName = file.name;
      });
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      String imgUrl = widget.currentImg;

      if (_newImageBytes != null) {
        final ext = _newImageName?.split('.').last ?? 'jpg';
        final ref = FirebaseStorage.instance
            .ref('categories/${widget.docId}/image.$ext');
        await ref.putData(
          _newImageBytes!,
          SettableMetadata(contentType: 'image/$ext'),
        );
        imgUrl = await ref.getDownloadURL();
      }

      await FirebaseFirestore.instance
          .collection('categories')
          .doc(widget.docId)
          .update({'name': name, 'img': imgUrl});

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("שגיאה בשמירה: $e"),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10)),
          ),
          const SizedBox(height: 22),
          const Text(
            "עריכת קטגוריה",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _pickImage,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _newImageBytes != null
                      ? Image.memory(_newImageBytes!,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover)
                      : Image.network(widget.currentImg,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(height: 160, color: Colors.grey[200])),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            color: Colors.white, size: 34),
                        SizedBox(height: 6),
                        Text("לחץ להחלפת תמונה",
                            style:
                                TextStyle(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              labelText: "שם קטגוריה",
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              prefixIcon: const Icon(Icons.label_outline),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _isSaving
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text("שמור שינויים",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
