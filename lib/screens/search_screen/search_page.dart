import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:async';
import 'dart:math' as math;
import '../category_results_screen.dart';
import '../sub_category_screen.dart';
import '../notifications_screen.dart';
import '../expert_profile_screen.dart';
import '../help_center_screen.dart';
import '../../services/category_service.dart';
import '../../services/visual_fetcher_service.dart';
import '../../widgets/category_image_card.dart';
import '../../onboarding/app_tour.dart';
import '../../l10n/app_localizations.dart';

// ─── Discover / Search page ──────────────────────────────────────────────────

class SearchPage extends StatefulWidget {
  final bool isOnline;
  final VoidCallback? onToggleOnline;
  final String? initialCategory;

  const SearchPage({
    super.key,
    this.isOnline = false,
    this.onToggleOnline,
    this.initialCategory,
  });

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

  String _getGreeting(AppLocalizations l10n) {
    final h = DateTime.now().hour;
    if (h >= 6  && h < 12) return '${l10n.greetingMorning} ☀️';
    if (h >= 12 && h < 17) return '${l10n.greetingAfternoon} 🌤️';
    if (h >= 17 && h < 22) return '${l10n.greetingEvening} 🌙';
    return '${l10n.greetingNight} ✨';
  }

  String _getGreetingSubtitle(AppLocalizations l10n) {
    final h = DateTime.now().hour;
    if (h >= 6  && h < 12) return l10n.greetingSubMorning;
    if (h >= 12 && h < 17) return l10n.greetingSubAfternoon;
    if (h >= 17 && h < 22) return l10n.greetingSubEvening;
    return l10n.greetingSubNight;
  }

  List<Map<String, dynamic>> _getTimeSuggestions(AppLocalizations l10n) {
    // Suggestion labels are category names that are used for Firestore queries
    // and are always stored/queried in Hebrew — keep them as-is.
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

  Widget _buildSuggestedRow(AppLocalizations l10n) {
    final suggestions = _getTimeSuggestions(l10n);
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
  Widget _buildSearchBar(AppLocalizations l10n) {
    return AnyShowcase(
      tourKey: tourClientSearchKey,
      title: l10n.searchTourSearchTitle,
      description: l10n.searchTourSearchDesc,
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
          hintText: l10n.searchHintExperts,
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
    if (widget.initialCategory != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CategoryResultsScreen(categoryName: widget.initialCategory!),
          ),
        );
      });
    }
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
    final l10n = AppLocalizations.of(context);
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
                      // ── Online/Offline status toggle (providers only) ──────
                      if (_isProvider && widget.onToggleOnline != null)
                        _OnlineToggle(
                          isOnline: widget.isOnline,
                          onTap: widget.onToggleOnline!,
                        ),
                      // Help Center entry point
                      IconButton(
                        icon: const Icon(Icons.help_outline_rounded, size: 22),
                        color: const Color(0xFF6366F1),
                        tooltip: l10n.helpCenterTooltip,
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
                          _getGreeting(l10n),
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _getGreetingSubtitle(l10n),
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
            _buildSearchBar(l10n),

            const SizedBox(height: 6),

            // ── Suggested categories (time-based) — client tour step 2 ────────
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOut,
              child: _searchQuery.isEmpty
                  ? AnyShowcase(
                      tourKey: tourClientSuggestionsKey,
                      title: l10n.searchTourSuggestionsTitle,
                      description: l10n.searchTourSuggestionsDesc,
                      child: _buildSuggestedRow(l10n),
                    )
                  : const SizedBox.shrink(),
            ),

            const SizedBox(height: 6),

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
                    return Center(
                      child: Text(
                        l10n.searchNoCategoriesBody,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey, fontSize: 15),
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
                            l10n.searchNoResultsFor(_searchQuery),
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
                          // ── Credits card (search empty) ──────────────────
                          if (_searchQuery.isEmpty)
                            const SliverToBoxAdapter(child: _CreditsCard()),

                          // Section label
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                              child: Text(
                                _searchQuery.isEmpty
                                    ? l10n.searchSectionCategories
                                    : l10n.searchSectionResultsFor(_searchQuery),
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

  String _urgencyText(AppLocalizations l10n) {
    final h = DateTime.now().hour;
    if (h >= 6  && h < 13) return l10n.searchUrgencyMorning;
    if (h >= 13 && h < 20) return l10n.searchUrgencyAfternoon;
    return l10n.searchUrgencyEvening;
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
        child: Container(
          height: 185,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      );
    }
    return _buildCard();
  }

  Widget _buildCard() {
    final l10n     = AppLocalizations.of(context);
    final d        = _data!;
    final name     = d['name']         as String? ?? l10n.searchDefaultExpert;
    final title    = d['serviceType']  as String? ?? l10n.searchDefaultTitle;
    final price    = (d['pricePerHour'] as num? ?? 100).toInt();
    final rating   = (d['rating']       as num? ?? 5.0);
    final city     = d['city']          as String? ?? l10n.searchDefaultCity;
    final photo    = d['profileImage']  as String? ?? '';
    final online   = d['isOnline']      as bool? ?? false;
    final verified = d['isVerified']    as bool? ?? false;

    final dateLabel = _selectedDate == null
        ? l10n.searchDatePickerHint
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
                                child: Text(l10n.searchRecommendedBadge,
                                    style: const TextStyle(
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
                                    online ? l10n.onlineStatus : l10n.offlineStatus,
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
                                    TextSpan(
                                      text: l10n.searchPerHour,
                                      style: const TextStyle(
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
                      label: l10n.searchChipWeekend,
                      color: const Color(0xFF8B5CF6),
                    ),
                    const SizedBox(width: 6),
                    _ServiceChip(
                      icon: Icons.home_rounded,
                      label: l10n.searchChipHomeVisit,
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
                          child: Text(l10n.bookNow,
                              style: const TextStyle(
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
                  _urgencyText(l10n),
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
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _placeholder())
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Icon(Icons.keyboard_arrow_left,
                              color: Colors.white70, size: 14),
                          Text(AppLocalizations.of(context).subCategoryPrompt,
                              style: const TextStyle(
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("🔥", style: TextStyle(fontSize: 11)),
                        const SizedBox(width: 3),
                        Text(
                          AppLocalizations.of(context).trendingBadge,
                          style: const TextStyle(
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
              content: Text(AppLocalizations.of(context).editCategorySaveError('$e')),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
          Text(
            l10n.editCategoryTitle,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
                      : CachedNetworkImage(
                          imageUrl: widget.currentImg,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              Container(height: 160, color: Colors.grey[200])),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_photo_alternate_outlined,
                            color: Colors.white, size: 34),
                        const SizedBox(height: 6),
                        Text(l10n.editCategoryChangePic,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13)),
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
              labelText: l10n.editCategoryNameLabel,
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
                : Text(l10n.saveChanges,
                    style: const TextStyle(
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

    final l10n       = AppLocalizations.of(context);
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
                        child: Text(l10n.creditsDiscountAvailable(discount),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      l10n.creditsToNextDiscount(remaining),
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
                    Text(l10n.creditsLabel,
                        style: const TextStyle(
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


// ─── Compact online/offline status toggle ────────────────────────────────────

class _OnlineToggle extends StatelessWidget {
  final bool isOnline;
  final VoidCallback onTap;

  const _OnlineToggle({required this.isOnline, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Tooltip(
      message: isOnline ? l10n.onlineToggleOff : l10n.onlineToggleOn,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: isOnline ? Colors.green[50] : Colors.grey[100],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isOnline ? Colors.green[300]! : Colors.grey[300]!,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _GlowDot(isOnline: isOnline),
              const SizedBox(width: 5),
              Text(
                isOnline ? l10n.onlineStatus : l10n.offlineStatus,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isOnline ? Colors.green[700] : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Animated glowing dot
class _GlowDot extends StatefulWidget {
  final bool isOnline;
  const _GlowDot({required this.isOnline});

  @override
  State<_GlowDot> createState() => _GlowDotState();
}

class _GlowDotState extends State<_GlowDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.isOnline) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_GlowDot old) {
    super.didUpdateWidget(old);
    if (widget.isOnline && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.isOnline && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOnline) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: Colors.grey[400],
          shape: BoxShape.circle,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: Colors.green,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.green.withValues(alpha: _anim.value * 0.6),
              blurRadius: 6,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}

