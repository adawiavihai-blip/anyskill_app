import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import '../category_results_screen.dart';
import '../sub_category_screen.dart';
import '../notifications_screen.dart';
import '../expert_profile_screen.dart';
import 'package:showcaseview/showcaseview.dart';
import '../help_center_screen.dart';
import '../../services/category_service.dart';
import '../../services/visual_fetcher_service.dart';
import '../../widgets/category_image_card.dart';
import '../../onboarding/app_tour.dart';
import 'widgets/stories_row.dart';

// ─── Discover / Search page ──────────────────────────────────────────────────

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery       = '';
  Timer? _searchLogTimer;
  String _lastLoggedQuery   = '';
  String _lastZeroQuery     = '';

  @override
  void dispose() {
    _searchLogTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _scheduleSearchLog(String query) {
    _searchLogTimer?.cancel();
    if (query.length < 2) return;
    _searchLogTimer = Timer(const Duration(milliseconds: 1500), () {
      if (query != _lastLoggedQuery) {
        _lastLoggedQuery = query;
        FirebaseFirestore.instance.collection('search_logs').add({
          'query':       query.toLowerCase().trim(),
          'userId':      FirebaseAuth.instance.currentUser?.uid,
          'timestamp':   FieldValue.serverTimestamp(),
          'zeroResults': false,
        });
      }
    });
  }

  void _logZeroResult(String query) {
    if (query.length < 2 || query == _lastZeroQuery) return;
    _lastZeroQuery = query;
    FirebaseFirestore.instance.collection('search_logs').add({
      'query':       query.toLowerCase().trim(),
      'userId':      FirebaseAuth.instance.currentUser?.uid,
      'timestamp':   FieldValue.serverTimestamp(),
      'zeroResults': true,
    });
  }

  // ── Time-based greeting ─────────────────────────────────────────────────────

  String _getGreeting() {
    final h = DateTime.now().hour;
    if (h >= 6  && h < 12) return 'בוקר טוב ☀️';
    if (h >= 12 && h < 17) return 'אחה"צ טובות 🌤️';
    if (h >= 17 && h < 22) return 'ערב טוב 🌙';
    return 'לילה טוב ✨';
  }

  String _getGreetingSubtitle() {
    final h = DateTime.now().hour;
    if (h >= 6  && h < 12) return 'מה צריך לסדר הבוקר?';
    if (h >= 12 && h < 17) return 'מחפש מקצוען? זה הזמן';
    if (h >= 17 && h < 22) return 'פינוק בערב? מגיע לך!';
    return 'גלה מומחים מובילים';
  }

  List<Map<String, dynamic>> _getTimeSuggestions() {
    final h = DateTime.now().hour;
    if (h >= 6 && h < 12) {
      return [
        {'label': 'שרברב',  'icon': Icons.plumbing_rounded},
        {'label': 'חשמלאי', 'icon': Icons.electrical_services_rounded},
        {'label': 'ניקיון', 'icon': Icons.cleaning_services_rounded},
        {'label': 'גינון',  'icon': Icons.yard_rounded},
      ];
    }
    if (h >= 12 && h < 17) {
      return [
        {'label': 'שיעורים פרטיים', 'icon': Icons.school_rounded},
        {'label': 'ייעוץ עסקי',     'icon': Icons.business_center_rounded},
        {'label': 'עיצוב',           'icon': Icons.brush_rounded},
        {'label': 'תרגום',           'icon': Icons.translate_rounded},
      ];
    }
    if (h >= 17 && h < 22) {
      return [
        {'label': 'עיסוי',       'icon': Icons.spa_rounded},
        {'label': 'כושר ואימון', 'icon': Icons.fitness_center_rounded},
        {'label': 'יופי',        'icon': Icons.face_retouching_natural_rounded},
        {'label': 'תזונה',       'icon': Icons.restaurant_menu_rounded},
      ];
    }
    return [
      {'label': 'מוסיקה', 'icon': Icons.music_note_rounded},
      {'label': 'ציור',   'icon': Icons.palette_rounded},
      {'label': 'כתיבה',  'icon': Icons.edit_note_rounded},
      {'label': 'תכנות',  'icon': Icons.code_rounded},
    ];
  }

  Widget _buildSuggestedRow() {
    final suggestions = _getTimeSuggestions();
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
      child: SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: suggestions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final s = suggestions[i];
            return GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CategoryResultsScreen(
                      categoryName: s['label'] as String),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F0FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(s['icon'] as IconData,
                        size: 13, color: const Color(0xFF6366F1)),
                    const SizedBox(width: 5),
                    Text(s['label'] as String,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6366F1))),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Search bar ──────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return AnyShowcase(
      tourKey: tourClientSearchKey,
      title: '🔍 חיפוש מומחים',
      description: 'הקלידו שם, קטגוריה, או סוג שירות — AnySkill ימצא את הספק המתאים לכם',
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) {
          setState(() => _searchQuery = v.trim());
          _scheduleSearchLog(v.trim());
        },
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
    ),   // closes Padding
    );   // closes AnyShowcase
  }

  // ── Current user's provider status ─────────────────────────────────────────
  bool _isProvider = false;

  @override
  void initState() {
    super.initState();
    _loadProviderStatus();
  }

  Future<void> _loadProviderStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users').doc(uid).get();
    if (!mounted) return;
    final isProvider = (doc.data() ?? {})['isProvider'] as bool? ?? false;
    if (isProvider != _isProvider) setState(() => _isProvider = isProvider);
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Help Center entry point
                      IconButton(
                        icon: const Icon(Icons.help_outline_rounded, size: 22),
                        color: const Color(0xFF6366F1),
                        tooltip: 'מרכז עזרה',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const HelpCenterScreen()),
                        ),
                      ),
                      NotificationBadge(
                        child: IconButton(
                          icon: const Icon(Icons.notifications_outlined,
                              size: 24),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const NotificationsScreen()),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _getGreeting(),
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _getGreetingSubtitle(),
                          style: const TextStyle(
                              fontSize: 13, color: Colors.grey),
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

            const SizedBox(height: 6),

            // ── Suggested categories (time-based) — client tour step 2 ────────
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOut,
              child: _searchQuery.isEmpty
                  ? AnyShowcase(
                      tourKey: tourClientSuggestionsKey,
                      title: '⚡ קטגוריות מומלצות',
                      description: 'AnySkill מציע שירותים בהתאם לשעה ביום — בוקר לתיקונים, ערב לספא ורווחה',
                      child: _buildSuggestedRow(),
                    )
                  : const SizedBox.shrink(),
            ),

            const SizedBox(height: 6),

            // ── Skills Stories row ─────────────────────────────────────
            // Collapses automatically when empty or when user is typing.
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOut,
              child: _searchQuery.isEmpty
                  ? StoriesRow(isProvider: _isProvider)
                  : const SizedBox.shrink(),
            ),

            // ── Banner carousel — OUTSIDE the categories StreamBuilder/LayoutBuilder ──
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
                    WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _logZeroResult(_searchQuery));
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
                          // ── Credits card + Inspiration feed (search empty) ──
                          if (_searchQuery.isEmpty) ...[
                            const SliverToBoxAdapter(child: _CreditsCard()),
                            // client tour step 3
                            SliverToBoxAdapter(
                              child: AnyShowcase(
                                tourKey: tourClientFeedKey,
                                title: '✨ פיד ההשראה',
                                description: 'עבודות אמיתיות מהאפליקציה — לחצו על כרטיס לפרופיל הספק המלא',
                                tooltipPosition: TooltipPosition.top,
                                child: const _InspirationFeed(),
                              ),
                            ),
                          ],

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

// ─── Featured Provider Card ───────────────────────────────────────────────────
//
// Replaces the banner carousel. Queries Firestore for the top-rated provider,
// then renders a high-conversion card: story-ring avatar, live online status,
// service badges, date picker, "Order Now" CTA, and an urgency nudge.

class _FeaturedProviderCard extends StatefulWidget {
  const _FeaturedProviderCard();

  @override
  State<_FeaturedProviderCard> createState() => _FeaturedProviderCardState();
}

class _FeaturedProviderCardState extends State<_FeaturedProviderCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ringCtrl;

  StreamSubscription<QuerySnapshot>? _sub;
  Map<String, dynamic>? _data;
  String? _uid;
  bool _loading = true;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    // Back-fill missing category images (runs once per app session).
    VisualFetcherService.backfillAll();

    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _sub = FirebaseFirestore.instance
        .collection('users')
        .where('isProvider', isEqualTo: true)
        .orderBy('rating', descending: true)
        .limit(1)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          if (snap.docs.isEmpty) { setState(() => _loading = false); return; }
          setState(() {
            _uid     = snap.docs.first.id;
            _data    = snap.docs.first.data();
            _loading = false;
          });
        }, onError: (_) {
          if (mounted) setState(() => _loading = false);
        });
  }

  @override
  void dispose() {
    _ringCtrl.dispose();
    _sub?.cancel();
    super.dispose();
  }

  String _urgencyText() {
    final h = DateTime.now().hour;
    if (h >= 6  && h < 13) return '🔴 נותר מקום 1 בלבד להיום!';
    if (h >= 13 && h < 20) return '⚡ נותרו 2 מקומות לשבוע זה';
    return '⏰ בדרך כלל מוזמן 3 ימים מראש';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (picked != null && mounted) setState(() => _selectedDate = picked);
  }

  void _goToProfile() {
    if (_uid == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExpertProfileScreen(
          expertId: _uid!,
          expertName: _data?['name'] as String? ?? '',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading && _data == null) return const SizedBox.shrink();
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _BannerShimmer(height: 185),
      );
    }
    return _buildCard();
  }

  Widget _buildCard() {
    final d        = _data!;
    final name     = d['name']         as String? ?? 'מומחה';
    final title    = d['serviceType']  as String? ?? 'מומחה מוסמך';
    final price    = (d['pricePerHour'] as num? ?? 100).toInt();
    final rating   = (d['rating']       as num? ?? 5.0);
    final city     = d['city']          as String? ?? 'שכונתך';
    final photo    = d['profileImage']  as String? ?? '';
    final online   = d['isOnline']      as bool? ?? false;
    final verified = d['isVerified']    as bool? ?? false;

    final dateLabel = _selectedDate == null
        ? 'מתי פנוי?'
        : '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}';

    return GestureDetector(
      onTap: _goToProfile,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFF0F0FF)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.10),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                // ── Top row: story avatar + provider info ─────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Story-style avatar (visually left)
                    _StoryAvatar(imageUrl: photo, ringCtrl: _ringCtrl),
                    const SizedBox(width: 12),

                    // Info block (RTL — right-aligned text)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [

                          // Name row + badges
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Gold "Recommended" badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text('⭐ מומלץ',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 6),
                              // Verified icon + name
                              Flexible(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (verified) ...[
                                      const Icon(Icons.verified_rounded,
                                          size: 14, color: Color(0xFF007AFF)),
                                      const SizedBox(width: 3),
                                    ],
                                    Flexible(
                                      child: Text(name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0F172A),
                                          )),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),

                          // Professional title
                          Text(title,
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF6366F1))),
                          const SizedBox(height: 4),

                          // Stars + location
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('📍 $city',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500)),
                              const SizedBox(width: 8),
                              const Icon(Icons.star_rounded,
                                  size: 13, color: Color(0xFFFBBF24)),
                              const SizedBox(width: 2),
                              Text(rating.toStringAsFixed(1),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A))),
                            ],
                          ),
                          const SizedBox(height: 4),

                          // Price + online status
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Online indicator
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7, height: 7,
                                    decoration: BoxDecoration(
                                      color: online
                                          ? const Color(0xFF10B981)
                                          : Colors.grey.shade300,
                                      shape: BoxShape.circle,
                                      boxShadow: online ? [
                                        BoxShadow(
                                          color: const Color(0xFF10B981)
                                              .withValues(alpha: 0.5),
                                          blurRadius: 4,
                                          spreadRadius: 1,
                                        ),
                                      ] : null,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    online ? 'זמין עכשיו' : 'לא זמין',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: online
                                            ? const Color(0xFF10B981)
                                            : Colors.grey),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 10),
                              // Price
                              RichText(
                                text: TextSpan(
                                  style: const TextStyle(
                                      color: Color(0xFF0F172A)),
                                  children: [
                                    TextSpan(
                                      text: '₪$price',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900),
                                    ),
                                    const TextSpan(
                                      text: ' / שעה',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                          fontWeight: FontWeight.normal),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 9),

                // ── Service badges ────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _ServiceChip(
                      icon: Icons.calendar_month_rounded,
                      label: 'זמין בסופ"ש',
                      color: const Color(0xFF8B5CF6),
                    ),
                    const SizedBox(width: 6),
                    _ServiceChip(
                      icon: Icons.home_rounded,
                      label: 'ביקור בית',
                      color: const Color(0xFF007AFF),
                    ),
                  ],
                ),

                const SizedBox(height: 9),
                Container(height: 1, color: const Color(0xFFF1F5F9)),
                const SizedBox(height: 9),

                // ── Bottom row: date picker + CTA button ──────────────────────
                Row(
                  children: [
                    // "הזמן עכשיו" button
                    Expanded(
                      flex: 5,
                      child: GestureDetector(
                        onTap: _goToProfile,
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF2563EB), Color(0xFF007AFF)],
                              begin: Alignment.centerRight,
                              end: Alignment.centerLeft,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF007AFF)
                                    .withValues(alpha: 0.30),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: const Text('הזמן עכשיו',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Date picker pill
                    Expanded(
                      flex: 4,
                      child: GestureDetector(
                        onTap: _pickDate,
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F8FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF6366F1)
                                  .withValues(alpha: 0.22),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.calendar_today_rounded,
                                  size: 13,
                                  color: _selectedDate != null
                                      ? const Color(0xFF6366F1)
                                      : Colors.grey),
                              const SizedBox(width: 5),
                              Text(dateLabel,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _selectedDate != null
                                          ? const Color(0xFF6366F1)
                                          : Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                // ── Urgency nudge ─────────────────────────────────────────────
                Text(
                  _urgencyText(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFDC2626)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Story-style animated avatar ──────────────────────────────────────────────

class _StoryAvatar extends StatelessWidget {
  const _StoryAvatar({required this.imageUrl, required this.ringCtrl});

  final String           imageUrl;
  final AnimationController ringCtrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Rotating gradient ring
          AnimatedBuilder(
            animation: ringCtrl,
            builder: (_, __) => CustomPaint(
              size: const Size(76, 76),
              painter: _StoryRingPainter(ringCtrl.value),
            ),
          ),

          // Profile photo with white border gap
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            padding: const EdgeInsets.all(2.5),
            child: ClipOval(
              child: imageUrl.isNotEmpty
                  ? Image.network(imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder())
                  : _placeholder(),
            ),
          ),

          // Play button badge (bottom-right corner)
          Positioned(
            bottom: 3,
            right: 3,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(Icons.play_arrow_rounded,
                  size: 13, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        color: const Color(0xFFF0F0FF),
        child: const Icon(Icons.person_rounded,
            color: Color(0xFF6366F1), size: 28),
      );
}

// ─── Rotating rainbow ring painter ────────────────────────────────────────────

class _StoryRingPainter extends CustomPainter {
  const _StoryRingPainter(this.progress);

  final double progress;

  static const _kColors = [
    Color(0xFF6366F1),
    Color(0xFF8B5CF6),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF10B981),
    Color(0xFF6366F1),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cx     = size.width  / 2;
    final cy     = size.height / 2;
    final radius = cx - 2.5;
    final angle  = progress * math.pi * 2;
    final rect   = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    final paint = Paint()
      ..shader = SweepGradient(
        startAngle: angle,
        endAngle: angle + math.pi * 2,
        colors: _kColors,
      ).createShader(rect)
      ..style      = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap  = StrokeCap.round;

    canvas.drawCircle(Offset(cx, cy), radius, paint);
  }

  @override
  bool shouldRepaint(_StoryRingPainter old) => old.progress != progress;
}

// ─── Service chip badge ────────────────────────────────────────────────────────

class _ServiceChip extends StatelessWidget {
  const _ServiceChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String   label;
  final Color    color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
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

        final now = DateTime.now();
        final newList = snap.docs
            .map((d) => {
                  ...d.data(),
                  '_id': d.id,
                })
            .where((b) {
              if (b['isActive'] != true) return false;
              final expires = (b['expiresAt'] as Timestamp?)?.toDate();
              return expires == null || expires.isAfter(now);
            })
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

    final b           = widget.data;
    final color1      = widget.hexToColor(b['color1'] as String? ?? '667eea');
    final color2      = widget.hexToColor(b['color2'] as String? ?? '764ba2');
    final icon        = widget.icons[b['iconName'] as String? ?? 'stars'] ??
        Icons.stars_rounded;
    final title       = b['title']      as String? ?? '';
    final subtitle    = b['subtitle']   as String? ?? '';
    final providerId  = b['providerId'] as String?;
    final providerName = b['providerName'] as String? ?? '';

    void onTap() {
      if (providerId != null && providerId.isNotEmpty) {
        // Track click (fire-and-forget)
        final bannerId = b['_id'] as String?;
        if (bannerId != null && bannerId.isNotEmpty) {
          FirebaseFirestore.instance
              .collection('banners')
              .doc(bannerId)
              .update({'clicks': FieldValue.increment(1)});
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ExpertProfileScreen(
              expertId: providerId,
              expertName: providerName,
            ),
          ),
        );
      }
    }

    return GestureDetector(
      onTap: providerId != null ? onTap : null,
      child: Container(
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

              // "View profile" badge — shown only for featured-provider banners
              if (providerId != null)
                Positioned(
                  bottom: 10,
                  left: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("לפרופיל",
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            )),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios_rounded,
                            size: 10, color: Colors.white.withValues(alpha: 0.95)),
                      ],
                    ),
                  ),
                ),

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
    ),   // end Container (child of GestureDetector)
    );   // end GestureDetector
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
        transform: Matrix4.identity()..scaleByDouble(_pressed ? 0.97 : 1.0, _pressed ? 0.97 : 1.0, 1.0, 1.0),
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
              CategoryImageBackground(imageUrl: widget.imageUrl),
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

// ─── Credits Card — isolated StatefulWidget ────────────────────────────────────
//
// Reads the current user's `credits` field from Firestore.
// Shows a branded progress bar toward the next discount milestone.
// Hidden when credits == 0.

class _CreditsCard extends StatefulWidget {
  const _CreditsCard();
  @override
  State<_CreditsCard> createState() => _CreditsCardState();
}

class _CreditsCardState extends State<_CreditsCard> {
  static const int _milestone = 200; // credits per discount tier

  StreamSubscription<DocumentSnapshot>? _sub;
  int  _credits = 0;
  bool _loaded  = false;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { _loaded = true; return; }
    _sub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          final data = snap.data() ?? {};
          setState(() {
            _credits = (data['credits'] as num? ?? 0).toInt();
            _loaded  = true;
          });
        }, onError: (_) {
          if (mounted) setState(() => _loaded = true);
        });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _credits == 0) return const SizedBox.shrink();

    final progress   = (_credits % _milestone) / _milestone;
    final remaining  = _milestone - (_credits % _milestone);
    final tierNumber = _credits ~/ _milestone;
    final discount   = tierNumber * 10; // 10% per milestone tier

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (discount > 0) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBBF24),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('$discount% הנחה זמינה!',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      'עוד $remaining להנחה הבאה',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 11),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text('$_credits',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(width: 4),
                    const Text('קרדיטים',
                        style: TextStyle(
                            color: Colors.white70, fontSize: 12)),
                    const SizedBox(width: 6),
                    const Icon(Icons.stars_rounded,
                        color: Color(0xFFFBBF24), size: 20),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFFFBBF24)),
              ),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$_milestone',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 9)),
                Text('0',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 9)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Inspiration Feed — isolated StatefulWidget ────────────────────────────────
//
// Reads `completed_works` collection (written by Cloud Function on job completion).
// Shows a horizontally scrollable feed of recently completed works.
// Hidden when the collection is empty.

class _InspirationFeed extends StatefulWidget {
  const _InspirationFeed();
  @override
  State<_InspirationFeed> createState() => _InspirationFeedState();
}

class _InspirationFeedState extends State<_InspirationFeed> {
  static const double _cardW = 155.0;
  static const double _cardH = 195.0;

  StreamSubscription<QuerySnapshot>? _sub;
  List<Map<String, dynamic>> _works   = [];
  bool                        _loading = true;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseFirestore.instance
        .collection('completed_works')
        .orderBy('completedAt', descending: true)
        .limit(10)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          setState(() {
            _works   = snap.docs
                .map((d) => d.data())
                .toList();
            _loading = false;
          });
        }, onError: (_) {
          if (mounted) setState(() => _loading = false);
        });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _works.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('חדש',
                      style: TextStyle(
                          color: Color(0xFF065F46),
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
                const Text('השראה — עבודות שהושלמו',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
          ),

          // ── Horizontal cards ─────────────────────────────────────────────
          SizedBox(
            height: _cardH,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _works.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final work        = _works[i];
                final coverImage  = work['coverImage']  as String? ?? '';
                final expertName  = work['expertName']  as String? ?? 'מומחה';
                final serviceType = work['serviceType'] as String? ?? '';
                final city        = work['city']        as String? ?? '';
                final expertId    = work['expertId']    as String? ?? '';

                return GestureDetector(
                  onTap: () {
                    if (expertId.isEmpty) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExpertProfileScreen(
                          expertId: expertId,
                          expertName: expertName,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    width: _cardW,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: const Color(0xFFF0F0FF),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Cover image
                        coverImage.isNotEmpty
                            ? Image.network(coverImage,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _InspirationFeedState._placeholder())
                            : _InspirationFeedState._placeholder(),

                        // Gradient overlay
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black
                                      .withValues(alpha: 0.78)
                                ],
                                stops: const [0.4, 1.0],
                              ),
                            ),
                          ),
                        ),

                        // Expert info (bottom)
                        Positioned(
                          bottom: 10,
                          left: 8,
                          right: 8,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(expertName,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              if (serviceType.isNotEmpty)
                                Text(serviceType,
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.75),
                                        fontSize: 10),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),

                        // City badge (top-left)
                        if (city.isNotEmpty)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.location_on_rounded,
                                      color: Colors.white, size: 9),
                                  const SizedBox(width: 2),
                                  Text(city,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9)),
                                ],
                              ),
                            ),
                          ),

                        // "Completed" badge (top-right)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.green.shade600
                                  .withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('הושלם ✓',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static Widget _placeholder() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Icon(Icons.work_rounded, color: Colors.white54, size: 40),
      );
}
