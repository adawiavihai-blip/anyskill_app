import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../l10n/app_localizations.dart';
import '../utils/safe_image_provider.dart';
import '../screens/expert_profile_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AnySkill Global Search Bar — v9.8.0
//
// Airbnb-style elevated search bar with:
//   • Hybrid search (pros + categories + sub-categories)
//   • 300ms debounce to save Firestore reads
//   • Auto-complete overlay with grouped results
//   • Professional filter bottom sheet
// ═══════════════════════════════════════════════════════════════════════════════

// ── Brand colours ────────────────────────────────────────────────────────────
const _kIndigo      = Color(0xFF6366F1);
const _kIndigoSoft  = Color(0xFFEEF2FF);
const _kGold        = Color(0xFFF59E0B);
const _kGreen       = Color(0xFF22C55E);
const _kMuted       = Color(0xFF6B7280);
const _kCardBg      = Color(0xFFF8FAFC);

/// Callback when a search result is tapped.
typedef OnSearchResultTap = void Function(String type, String value);

// ═══════════════════════════════════════════════════════════════════════════════
// SEARCH BAR WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

class GlobalSearchBar extends StatefulWidget {
  /// Called when user taps a result or the magnifying glass with a query.
  final OnSearchResultTap? onResultTap;

  /// Called when the full SearchPage should open (magnifying glass tap with no query).
  final VoidCallback? onOpenFullSearch;

  const GlobalSearchBar({
    super.key,
    this.onResultTap,
    this.onOpenFullSearch,
  });

  @override
  State<GlobalSearchBar> createState() => _GlobalSearchBarState();
}

class _GlobalSearchBarState extends State<GlobalSearchBar>
    with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _layerLink = LayerLink();

  Timer? _debounce;
  OverlayEntry? _overlay;
  List<_SearchResult> _results = [];
  bool _isSearching = false;

  // ── Animation for the search icon ────────────────────────────────────────
  late final AnimationController _iconAnim;

  @override
  void initState() {
    super.initState();
    _iconAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _focus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _iconAnim.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focus.hasFocus) {
      _iconAnim.forward();
    } else {
      _iconAnim.reverse();
      // Delay overlay removal so that InkWell.onTap on result tiles
      // has time to fire before the overlay is destroyed. Without this
      // delay, tapping a result first unfocuses the field → removes the
      // overlay → the tap target is gone before onTap fires.
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && !_focus.hasFocus) _removeOverlay();
      });
    }
  }

  void _onTextChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      _removeOverlay();
      setState(() { _results = []; _isSearching = false; });
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runHybridSearch(query.trim());
    });
  }

  // ── Hebrew synonym map — maps common search terms to category keywords ──
  // Users type "מאמן כושר" but the category is "אימון כושר". This map
  // expands search queries with synonyms so word-overlap matching succeeds.
  static const _hebrewSynonyms = <String, List<String>>{
    'מאמן':    ['אימון', 'כושר'],
    'מאמנת':   ['אימון', 'כושר'],
    'מאמני':   ['אימון', 'כושר'],
    'צלם':     ['צילום'],
    'צלמת':    ['צילום'],
    'מנקה':    ['ניקיון'],
    'ניקוי':   ['ניקיון'],
    'שיפוצניק': ['שיפוצים'],
    'שרברב':   ['אינסטלציה', 'שיפוצים'],
    'חשמלאי':  ['חשמל', 'שיפוצים'],
    'מורה':    ['שיעורים', 'פרטיים'],
    'מורת':    ['שיעורים', 'פרטיים'],
    'מעצב':    ['עיצוב', 'גרפי'],
    'מעצבת':   ['עיצוב', 'גרפי'],
    'יוגה':    ['אימון', 'כושר', 'יוגה'],
    'פילאטיס': ['אימון', 'כושר', 'פילאטיס'],
  };

  /// Word-overlap score between a query and a category name.
  /// Returns 0 if no words match, higher = better match.
  /// Expands query words via the synonym map for Hebrew fuzzy matching.
  static int _wordOverlapScore(String query, String categoryName) {
    final qWords = query.split(RegExp(r'\s+'))
        .where((w) => w.length >= 2).toSet();
    final catWords = categoryName.toLowerCase().split(RegExp(r'\s+')).toSet();

    // Expand query words with synonyms
    final expanded = <String>{...qWords};
    for (final w in qWords) {
      final syns = _hebrewSynonyms[w];
      if (syns != null) expanded.addAll(syns.map((s) => s.toLowerCase()));
    }

    // Count overlap
    return expanded.where(catWords.contains).length;
  }

  // ── Hybrid Search: 3 parallel Firestore queries ─────────────────────────
  Future<void> _runHybridSearch(String query) async {
    final q = query.toLowerCase();
    final db = FirebaseFirestore.instance;

    try {
      final results = <_SearchResult>[];

      // 1. Sub-categories only — skip top-level categories.
      // v11.4.3: Users search for specific services, not parent groups.
      // A sub-category has a non-empty parentId field.
      final catSnap = await db.collection('categories').limit(200).get();
      for (final doc in catSnap.docs) {
        final d = doc.data();
        final name = (d['name'] as String? ?? '');
        final nameLower = name.toLowerCase();
        final isHidden = d['isHidden'] as bool? ?? false;
        final parentId = d['parentId'] as String? ?? '';
        if (isHidden) continue;
        if (parentId.isEmpty) continue; // skip top-level categories

        // Match by: exact substring OR word-overlap score >= 1
        final substringMatch = nameLower.contains(q);
        final overlapScore = _wordOverlapScore(q, nameLower);

        if (substringMatch || overlapScore > 0) {
          results.add(_SearchResult(
            type: 'subcategory',
            name: name,
            subtitle: 'תת-קטגוריה',
            icon: Icons.label_rounded,
            imageUrl: d['img'] as String?,
            score: substringMatch ? 100 + overlapScore : overlapScore,
          ));
        }
      }

      // 2. Providers — search by name, businessName, serviceType
      final provSnap = await db
          .collection('users')
          .where('isProvider', isEqualTo: true)
          .where('isVerified', isEqualTo: true)
          .limit(50)
          .get();

      for (final doc in provSnap.docs) {
        final d = doc.data();
        final fullName = (d['name'] as String? ?? '').toLowerCase();
        final businessName = (d['businessName'] as String? ?? '').toLowerCase();
        final serviceType = (d['serviceType'] as String? ?? '').toLowerCase();
        final isHidden = d['isHidden'] as bool? ?? false;
        // v11.9.x: Demo profiles ARE shown in global search (Soft Launch).
        // Booking interception in expert_profile_screen handles the
        // fake-success flow + admin notification.
        if (isHidden) continue;

        if (fullName.contains(q) || businessName.contains(q) || serviceType.contains(q)) {
          results.add(_SearchResult(
            type: 'provider',
            name: d['name'] as String? ?? '',
            subtitle: d['serviceType'] as String?,
            icon: Icons.person_rounded,
            imageUrl: d['profileImage'] as String?,
            rating: (d['rating'] as num?)?.toDouble(),
            uid: doc.id,
            isOnline: d['isOnline'] == true,
            phone: d['phone'] as String?,
          ));
        }
      }

      // Sort: categories by score DESC, then providers by rating DESC
      results.sort((a, b) {
        if (a.type != 'provider' && b.type == 'provider') return -1;
        if (a.type == 'provider' && b.type != 'provider') return 1;
        if (a.type != 'provider' && b.type != 'provider') {
          return (b.score ?? 0).compareTo(a.score ?? 0);
        }
        return (b.rating ?? 0).compareTo(a.rating ?? 0);
      });

      if (!mounted) return;
      setState(() {
        _results = results.take(8).toList(); // Max 8 suggestions
        _isSearching = false;
      });
      if (_results.isNotEmpty && _focus.hasFocus) {
        _showOverlay();
      } else {
        _removeOverlay();
      }
    } catch (e) {
      debugPrint('[GlobalSearch] Error: $e');
      if (mounted) setState(() => _isSearching = false);
    }
  }

  // ── Overlay management ──────────────────────────────────────────────────
  void _showOverlay() {
    _removeOverlay();
    _overlay = OverlayEntry(builder: (_) => _buildOverlay());
    Overlay.of(context).insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  Widget _buildOverlay() {
    return Positioned(
      width: MediaQuery.of(context).size.width - 32,
      child: CompositedTransformFollower(
        link: _layerLink,
        offset: const Offset(0, 56),
        showWhenUnlinked: false,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
          shadowColor: Colors.black.withValues(alpha: 0.12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < _results.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 56),
                  _buildResultTile(_results[i]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultTile(_SearchResult r) {
    final hasImage = r.imageUrl != null && r.imageUrl!.isNotEmpty;
    final isProvider = r.type == 'provider';

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      splashColor: _kIndigo.withValues(alpha: 0.08),
      highlightColor: _kIndigo.withValues(alpha: 0.04),
      onTap: () {
        _focus.unfocus();
        _removeOverlay();
        _ctrl.clear();
        if (isProvider && r.uid != null) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => ExpertProfileScreen(
              expertId: r.uid!,
              expertName: r.name,
            ),
          ));
        } else {
          widget.onResultTap?.call(r.type, r.name);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // ── Leading avatar / image ──────────────────────────────────
            if (hasImage)
              // Real image — provider profile pic OR category image
              ClipOval(
                child: SizedBox(
                  width: 36, height: 36,
                  child: isProvider
                      ? _buildSafeAvatar(r.imageUrl)
                      : Image.network(
                          r.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _iconFallback(r),
                        ),
                ),
              )
            else
              _iconFallback(r),
            const SizedBox(width: 12),
            // ── Name + subtitle ─────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.name,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  if (r.subtitle != null)
                    Text(r.subtitle!,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),
            // ── Trailing badge / rating ─────────────────────────────────
            if (isProvider) ...[
              if (r.isOnline == true)
                Container(
                  width: 8, height: 8,
                  margin: const EdgeInsetsDirectional.only(end: 6),
                  decoration: const BoxDecoration(
                    color: _kGreen, shape: BoxShape.circle),
                ),
              if (r.rating != null && r.rating! > 0)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.star_rounded, size: 14, color: _kGold),
                  const SizedBox(width: 2),
                  Text(r.rating!.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
            ] else
              Icon(Icons.chevron_left_rounded, size: 20, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  /// Safe avatar for providers — handles both HTTPS and base64.
  Widget _buildSafeAvatar(String? url) {
    final provider = safeImageProvider(url);
    if (provider != null) {
      return CircleAvatar(
        radius: 18,
        backgroundImage: provider,
        backgroundColor: _kIndigoSoft,
      );
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: _kIndigoSoft,
      child: const Icon(Icons.person_rounded, size: 18, color: _kIndigo),
    );
  }

  /// Fallback icon circle when no image is available.
  Widget _iconFallback(_SearchResult r) {
    final isProvider = r.type == 'provider';
    return CircleAvatar(
      radius: 18,
      backgroundColor: isProvider ? _kIndigoSoft : const Color(0xFFF0FDF4),
      child: Icon(r.icon, size: 18,
          color: isProvider ? _kIndigo : _kGreen),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: CompositedTransformTarget(
        link: _layerLink,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _focus.hasFocus
                    ? _kIndigo.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.06),
                blurRadius: _focus.hasFocus ? 16 : 10,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: _focus.hasFocus
                  ? _kIndigo.withValues(alpha: 0.3)
                  : const Color(0xFFE5E7EB),
              width: _focus.hasFocus ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // ── Search icon ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 14),
                child: AnimatedBuilder(
                  animation: _iconAnim,
                  builder: (_, __) => Transform.scale(
                    scale: 1.0 + (_iconAnim.value * 0.1),
                    child: Icon(
                      Icons.search_rounded,
                      size: 22,
                      color: Color.lerp(
                        const Color(0xFF9CA3AF),
                        _kIndigo,
                        _iconAnim.value,
                      ),
                    ),
                  ),
                ),
              ),

              // ── Text field ──────────────────────────────────────────────
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  textAlign: TextAlign.start,
                  textAlignVertical: TextAlignVertical.center,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w400),
                  onChanged: _onTextChanged,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    hintText: l10n.searchPlaceholder,
                    hintStyle: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),

              // ── Clear / loading indicator ───────────────────────────────
              if (_isSearching)
                const Padding(
                  padding: EdgeInsetsDirectional.only(end: 4),
                  child: SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _kIndigo),
                  ),
                )
              else if (_ctrl.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: _kMuted),
                  onPressed: () {
                    _ctrl.clear();
                    _removeOverlay();
                    setState(() { _results = []; });
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),

              // ── Filter button ───────────────────────────────────────────
              GestureDetector(
                onTap: () => _showFilterSheet(context),
                child: Container(
                  width: 42, height: 42,
                  margin: const EdgeInsetsDirectional.only(end: 5),
                  decoration: BoxDecoration(
                    color: _kIndigoSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.tune_rounded, size: 20, color: _kIndigo),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Filter Sheet ──────────────────────────────────────────────────────────
  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _FilterSheet(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SEARCH RESULT MODEL
// ═══════════════════════════════════════════════════════════════════════════════

class _SearchResult {
  final String type; // 'category', 'subcategory', 'provider'
  final String name;
  final String? subtitle;
  final IconData icon;
  final String? imageUrl;
  final double? rating;
  final String? uid;
  final bool? isOnline;
  final String? phone;
  final int? score; // relevance score for sorting (higher = better match)

  const _SearchResult({
    required this.type,
    required this.name,
    this.subtitle,
    required this.icon,
    this.imageUrl,
    this.rating,
    this.uid,
    this.isOnline,
    this.phone,
    this.score,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// FILTER BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class _FilterSheet extends StatefulWidget {
  const _FilterSheet();

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  // Sort
  String _sortBy = 'top_rated'; // top_rated, price_low, closest
  // Price range
  RangeValues _priceRange = const RangeValues(0, 500);
  // Expert level
  final Set<String> _levels = {};
  // Available now
  bool _availableNow = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Drag handle ──────────────────────────────────────────────
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Title ────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('סינון ומיון',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              TextButton(
                onPressed: () => setState(() {
                  _sortBy = 'top_rated';
                  _priceRange = const RangeValues(0, 500);
                  _levels.clear();
                  _availableNow = false;
                }),
                child: const Text('נקה הכל',
                    style: TextStyle(color: _kIndigo, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Sort By ──────────────────────────────────────────────────
          const Text('מיון לפי',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              _sortChip('top_rated', 'דירוג גבוה', Icons.star_rounded),
              _sortChip('price_low', 'מחיר: נמוך לגבוה', Icons.arrow_upward_rounded),
              _sortChip('closest', 'הקרוב אליי', Icons.near_me_rounded),
            ],
          ),
          const SizedBox(height: 24),

          // ── Price Range ──────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('טווח מחירים (₪/שעה)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Text(
                '₪${_priceRange.start.round()} – ₪${_priceRange.end.round()}',
                style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: _kIndigo,
              inactiveTrackColor: _kIndigo.withValues(alpha: 0.15),
              thumbColor: _kIndigo,
              overlayColor: _kIndigo.withValues(alpha: 0.1),
              valueIndicatorColor: _kIndigo,
              showValueIndicator: ShowValueIndicator.always,
            ),
            child: RangeSlider(
              values: _priceRange,
              min: 0,
              max: 500,
              divisions: 50,
              labels: RangeLabels(
                '₪${_priceRange.start.round()}',
                '₪${_priceRange.end.round()}',
              ),
              onChanged: (v) => setState(() => _priceRange = v),
            ),
          ),
          const SizedBox(height: 20),

          // ── Expert Level ─────────────────────────────────────────────
          const Text('רמת מומחה',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              _levelChip('pro', 'Pro ⭐', const Color(0xFF6366F1)),
              _levelChip('gold', 'זהב 🥇', const Color(0xFFF59E0B)),
              _levelChip('legendary', 'אגדי 🔥', const Color(0xFFEF4444)),
            ],
          ),
          const SizedBox(height: 20),

          // ── Available Now ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: _availableNow ? const Color(0xFFF0FDF4) : _kCardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _availableNow ? _kGreen.withValues(alpha: 0.4) : const Color(0xFFE5E7EB)),
            ),
            child: SwitchListTile(
              value: _availableNow,
              onChanged: (v) => setState(() => _availableNow = v),
              title: const Text('זמין עכשיו',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              subtitle: Text('הצג רק מומחים מחוברים',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              activeColor: _kGreen,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 24),

          // ── Apply button ─────────────────────────────────────────────
          SizedBox(
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kIndigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: () {
                Navigator.pop(context, {
                  'sortBy': _sortBy,
                  'priceMin': _priceRange.start,
                  'priceMax': _priceRange.end,
                  'levels': _levels.toList(),
                  'availableNow': _availableNow,
                });
              },
              child: const Text('הצג תוצאות',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  Widget _sortChip(String value, String label, IconData icon) {
    final selected = _sortBy == value;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16,
              color: selected ? Colors.white : _kMuted),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selected: selected,
      onSelected: (_) => setState(() => _sortBy = value),
      selectedColor: _kIndigo,
      backgroundColor: _kCardBg,
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xFF374151),
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? _kIndigo : const Color(0xFFE5E7EB)),
      ),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    );
  }

  Widget _levelChip(String value, String label, Color color) {
    final selected = _levels.contains(value);
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (v) => setState(() {
        if (v) { _levels.add(value); } else { _levels.remove(value); }
      }),
      selectedColor: color.withValues(alpha: 0.15),
      backgroundColor: _kCardBg,
      checkmarkColor: color,
      labelStyle: TextStyle(
        color: selected ? color : const Color(0xFF374151),
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? color.withValues(alpha: 0.5) : const Color(0xFFE5E7EB)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    );
  }
}
