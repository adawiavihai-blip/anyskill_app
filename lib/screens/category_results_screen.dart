import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/favorite_button.dart';
import '../widgets/pro_badge.dart';
import 'expert_profile_screen.dart';
import '../utils/expert_filter.dart';
import '../services/location_service.dart';
import '../services/search_ranking_service.dart';
import '../services/category_service.dart';
import '../widgets/level_badge.dart';
import '../constants/quick_tags.dart';
import '../l10n/app_localizations.dart';
import 'search_screen/widgets/stories_row.dart';

// Brand colours (shared with the rest of the app)
const _kPurple     = Color(0xFF6366F1);
const _kPurpleSoft = Color(0xFFF0F0FF);
const _kGold       = Color(0xFFFBBF24);

class CategoryResultsScreen extends StatefulWidget {
  final String categoryName;

  /// כאשר true — מציג רק מומחים עם isVolunteer==true (קהילה).
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
  Position? _currentPosition;

  // ── Pagination state ───────────────────────────────────────────────────────
  static const int _kPageSize = 15;

  final List<Map<String, dynamic>> _allExperts = [];
  bool _isLoading     = true;
  bool _isLoadingMore = false;
  bool _hasMore       = true;
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;

  late final ScrollController _scrollCtrl;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController()..addListener(_onScroll);
    _loadInitial();
    // Use cached position instantly; fall back to a dialog-based request
    final cached = LocationService.cached;
    if (cached != null) {
      _currentPosition = cached;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final pos = await LocationService.requestAndGet(context);
        if (mounted && pos != null) setState(() => _currentPosition = pos);
      });
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent * 0.85) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isLoading = true;
      _allExperts.clear();
      _lastDoc = null;
      _hasMore = true;
    });
    final page = await _fetchPage();
    if (!mounted) return;
    setState(() {
      _allExperts.addAll(page);
      _isLoading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _isLoading) return;
    setState(() => _isLoadingMore = true);
    final page = await _fetchPage();
    if (!mounted) return;
    setState(() {
      _allExperts.addAll(page);
      _isLoadingMore = false;
    });
  }

  /// Fetches the next page of experts using Firestore cursor pagination.
  /// Applies isVerified / isHidden client-side filters to each page.
  Future<List<Map<String, dynamic>>> _fetchPage() async {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('users')
        .where('isProvider', isEqualTo: true);

    if (widget.volunteerOnly) {
      q = q.where('isVolunteer', isEqualTo: true);
    } else {
      q = q.where('serviceType', isEqualTo: widget.categoryName);
    }

    if (_lastDoc != null) q = q.startAfterDocument(_lastDoc!);
    q = q.limit(_kPageSize);

    final snap = await q.get();
    if (snap.docs.length < _kPageSize) {
      if (mounted) setState(() => _hasMore = false);
    }
    if (snap.docs.isNotEmpty) _lastDoc = snap.docs.last;

    return snap.docs.map((d) {
      final map = d.data();
      map['uid'] = d.id;
      return map;
    })
    .where((m) => m['isVerified'] != false)
    .where((m) => m['isHidden']   != true)
    .toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Availability bottom sheet
  // ─────────────────────────────────────────────────────────────────────────

  void _showAvailabilitySheet(
      BuildContext context, Map<String, dynamic> data, String expertId) {
    final l10n = AppLocalizations.of(context);

    // Parse the provider's blocked dates (ISO-8601 strings: 'YYYY-MM-DD')
    final blocked = ((data['unavailableDates'] as List?) ?? [])
        .map((d) => d.toString().substring(0, 10))
        .toSet();

    // Compute the next 7 calendar days, then keep only the 3 first available
    final today = DateTime.now();
    final slots = <DateTime>[];
    for (int i = 1; i <= 14 && slots.length < 3; i++) {
      final day = today.add(Duration(days: i));
      final key = '${day.year.toString().padLeft(4, '0')}-'
          '${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}';
      if (!blocked.contains(key)) slots.add(day);
    }

    // Fixed time options shown for each available day
    const times = ['09:00', '11:00', '14:00', '16:00'];
    final dayLabels = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת'];
    final monthLabels = [
      'ינו׳', 'פבר׳', 'מרץ', 'אפר׳', 'מאי', 'יוני',
      'יולי', 'אוג׳', 'ספט׳', 'אוק׳', 'נוב׳', 'דצמ׳',
    ];

    final expertDefaultName = l10n.catResultsExpertDefault;
    final availableSlotsTitle = l10n.catResultsAvailableSlots;
    final noAvailabilityMsg = l10n.catResultsNoAvailability;
    final fullBookingLabel = l10n.catResultsFullBooking;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  data['name'] ?? expertDefaultName,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                Text(
                  availableSlotsTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (slots.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(noAvailabilityMsg,
                      style: const TextStyle(color: Colors.grey, fontSize: 14)),
                ),
              )
            else
              SizedBox(
                height: 130,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  reverse: true,             // RTL scroll feels natural
                  itemCount: slots.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (ctx, i) {
                    final day = slots[i];
                    final dayName  = dayLabels[day.weekday % 7];
                    final dateStr  = '${day.day} ${monthLabels[day.month - 1]}';
                    return Container(
                      width: 130,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: _kPurpleSoft,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _kPurple.withValues(alpha: 0.25)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(dayName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _kPurple,
                                  fontSize: 14)),
                          Text(dateStr,
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 12)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            alignment: WrapAlignment.end,
                            children: times.map((t) => GestureDetector(
                              onTap: () {
                                Navigator.pop(ctx);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ExpertProfileScreen(
                                      expertId: expertId,
                                      expertName: data['name'] ?? expertDefaultName,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: _kPurple.withValues(alpha: 0.4)),
                                ),
                                child: Text(t,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: _kPurple,
                                        fontWeight: FontWeight.w600)),
                              ),
                            )).toList(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPurple,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ExpertProfileScreen(
                        expertId: expertId,
                        expertName: data['name'] ?? expertDefaultName,
                      ),
                    ),
                  );
                },
                child: Text(fullBookingLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Card: Action Image (left 38%)
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns true when the expert has an active story uploaded in the last 24h.
  bool _isStoryActive(Map<String, dynamic> data) {
    if (data['hasActiveStory'] != true) return false;
    final ts = (data['storyTimestamp'] as Timestamp?)?.toDate();
    if (ts == null) return false;
    return DateTime.now().difference(ts).inHours < 24;
  }

  Widget _buildActionImage(Map<String, dynamic> data, bool isOnline) {
    final l10n        = AppLocalizations.of(context);
    final hasStory    = _isStoryActive(data);
    final profileImg  = data['profileImage'] as String? ?? '';
    final hasImg      = profileImg.isNotEmpty;

    // Trust badges
    final orderCount   = (data['orderCount'] as num?)?.toInt() ?? 0;
    final respTime     = (data['responseTimeMinutes'] as num?)?.toInt() ?? 0;
    final rating       = (data['rating'] as num?)?.toDouble() ?? 0;
    final reviewsCount = (data['reviewsCount'] as num?)?.toInt() ?? 0;

    final badges = <String>[];
    if (orderCount >= 5) badges.add(l10n.catResultsOrderCount(orderCount));
    if (respTime > 0 && respTime <= 10) badges.add(l10n.catResultsResponseTime(respTime));
    if (rating >= 4.8 && reviewsCount >= 3) badges.add(l10n.catResultsTopRated);

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topRight: Radius.circular(16),
        bottomRight: Radius.circular(16),
      ),
      child: SizedBox(
        width: 130,
        child: Stack(
          children: [
            // ── Background + centered CircleAvatar ───────────────────────
            Positioned.fill(
              child: Container(color: _kPurpleSoft),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                final expertId = data['uid'] as String? ?? '';
                if (data['hasActiveStory'] != true || expertId.isEmpty) return;
                final doc = await FirebaseFirestore.instance
                    .collection('stories')
                    .doc(expertId)
                    .get();
                if (!mounted || !doc.exists) return;
                openStoryViewer(context, expertId, doc.data()!);
              },
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: hasStory
                          ? null
                          : Border.all(color: _kPurple.withValues(alpha: 0.18), width: 2),
                      gradient: hasStory
                          ? const LinearGradient(
                              colors: [Color(0xFF6366F1), Color(0xFFEC4899), Color(0xFFF59E0B)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                    ),
                    padding: hasStory ? const EdgeInsets.all(3) : EdgeInsets.zero,
                    child: CircleAvatar(
                      radius: 46,
                      backgroundColor: const Color(0xFFEEEBFF),
                      backgroundImage: hasImg ? NetworkImage(profileImg) : null,
                      child: hasImg
                          ? null
                          : Icon(Icons.person, size: 40,
                              color: _kPurple.withValues(alpha: 0.5)),
                    ),
                  ),
                ),
              ),
            ),

            // ── Badge row (top, clean — no overlap with avatar) ───────────
            Positioned(
              top: 6,
              left: 4,
              right: 4,
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 3,
                children: [
                  if (isOnline)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.50),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.circle, color: Color(0xFF22C55E), size: 7),
                          const SizedBox(width: 3),
                          Text(l10n.onlineStatus,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  if (reviewsCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.50),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded,
                              color: Color(0xFFFBBF24), size: 10),
                          const SizedBox(width: 2),
                          Text(rating.toStringAsFixed(1),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  if (hasStory)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFFEC4899)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_circle_fill_rounded,
                              color: Colors.white, size: 9),
                          SizedBox(width: 2),
                          Text('STORY',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3)),
                        ],
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

  // ─────────────────────────────────────────────────────────────────────────
  // Quick Tags row (shown in the details panel)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildQuickTagsRow(List<String> tagKeys) {
    // Resolve keys → display data, ignore unknown keys, cap at 2
    final resolved = tagKeys
        .map(quickTagByKey)
        .whereType<Map<String, String>>()
        .take(2)
        .toList();
    if (resolved.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 5,
      runSpacing: 4,
      alignment: WrapAlignment.end,
      children: resolved.map((t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: _kPurpleSoft,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kPurple.withValues(alpha: 0.18)),
        ),
        child: Text(
          '${t['emoji']} ${t['label']}',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: _kPurple.withValues(alpha: 0.85),
          ),
        ),
      )).toList(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Card: Details panel (right 62%)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildExpertDetails(
    Map<String, dynamic> data,
    bool isVerified,
    bool isPromoted,
    bool isOnline,
    String expertId,
  ) {
    final l10n        = AppLocalizations.of(context);
    final isPro       = data['isAnySkillPro'] == true;
    final name        = data['name'] as String? ?? l10n.catResultsExpertDefault;
    final price       = data['pricePerHour'] ?? 100;
    final rating      = (data['rating'] as num?)?.toDouble() ?? 5.0;
    final reviewsCount = (data['reviewsCount'] as num?)?.toInt() ?? 0;
    final bio         = data['aboutMe'] as String? ?? '';
    final tagKeys     = ((data['quickTags'] as List?) ?? []).cast<String>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      // mainAxisAlignment.spaceBetween pushes the CTA buttons to the card
      // bottom without using Spacer(). Spacer inside IntrinsicHeight has
      // zero intrinsic height, causing 1 px overflows on some text sizes.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ── Top content group ────────────────────────────────────────────
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // ── Price (top-right, most prominent) ─────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Level badge on the left
                  if ((data['xp'] as num? ?? 0) > 0)
                    LevelBadge(xp: (data['xp'] as num).toInt(), size: 16),

                  // Price
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontFamily: 'Heebo'),
                      children: [
                        TextSpan(
                          text: '₪$price',
                          style: const TextStyle(
                              color: _kPurple,
                              fontWeight: FontWeight.w900,
                              fontSize: 18),
                        ),
                        TextSpan(
                          text: l10n.catResultsPerHour,
                          style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                              fontWeight: FontWeight.normal),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // ── Name + verification + promoted ───────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isPromoted)
                    Container(
                      margin: const EdgeInsets.only(left: 5),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber[50],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded,
                              color: Colors.amber[700], size: 10),
                          const SizedBox(width: 3),
                          Text(l10n.catResultsRecommended,
                              style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.amber[800],
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  if (isVerified) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.verified,
                        color: Color(0xFF1877F2), size: 15),
                  ],
                  if (data['isVolunteer'] == true) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.favorite, color: Colors.red, size: 15),
                  ],
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ],
              ),
              if (isPro) ...[
                const SizedBox(height: 5),
                const Align(
                  alignment: Alignment.centerRight,
                  child: ProBadge(),
                ),
              ],
              const SizedBox(height: 4),

              // ── Bio (1 line) ───────────────────────────────────────────
              if (bio.isNotEmpty)
                Text(
                  bio,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              if (bio.isNotEmpty) const SizedBox(height: 4),

              // ── Quick Tags ─────────────────────────────────────────────
              _buildQuickTagsRow(tagKeys),
              if (tagKeys.isNotEmpty) const SizedBox(height: 4),

              // ── Rating + location ──────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_currentPosition != null) ...() {
                    final lat = (data['latitude']  as num?)?.toDouble();
                    final lng = (data['longitude'] as num?)?.toDouble();
                    if (lat == null || lng == null) return <Widget>[];
                    final label = LocationService.distanceLabel(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                        lat, lng);
                    return [
                      const Icon(Icons.location_on_rounded,
                          size: 11, color: Colors.grey),
                      const SizedBox(width: 2),
                      Text(label,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                      const SizedBox(width: 8),
                    ];
                  }(),
                  Icon(Icons.star_rounded, color: _kGold, size: 14),
                  const SizedBox(width: 2),
                  Text(
                    rating.toStringAsFixed(1),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '($reviewsCount)',
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                ],
              ),
            ],
          ),

          // ── Bottom CTA group (pinned to card bottom by spaceBetween) ─────
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── "When are they free?" ghost button ───────────────────
              SizedBox(
                height: 32,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    side: BorderSide(color: _kPurple.withValues(alpha: 0.45)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    foregroundColor: _kPurple,
                  ),
                  icon: const Icon(Icons.calendar_today_rounded, size: 13),
                  label: Text(l10n.catResultsWhenFree,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  onPressed: () =>
                      _showAvailabilitySheet(context, data, expertId),
                ),
              ),
              const SizedBox(height: 6),

              // ── Book Now — primary CTA ─────────────────────────────
              SizedBox(
                height: 36,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPurple,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ExpertProfileScreen(
                        expertId: expertId,
                        expertName: name,
                      ),
                    ),
                  ),
                  child: Text(l10n.bookNow,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Full expert card
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildExpertCard(Map<String, dynamic> data) {
    final l10n       = AppLocalizations.of(context);
    final isVerified = data['isVerified'] as bool? ?? false;
    final isOnline   = data['isOnline']   as bool? ?? false;
    final isPromoted = data['isPromoted'] as bool? ?? false;
    final expertId   = data['uid'] as String? ?? '';

    return GestureDetector(
      // Tap anywhere on card = open profile
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ExpertProfileScreen(
            expertId: expertId,
            expertName: data['name'] ?? l10n.catResultsExpertDefault,
          ),
        ),
      ),
      child: Stack(
        children: [
          Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isPromoted
              ? Border.all(color: Colors.amber.shade300, width: 1.5)
              : Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: isPromoted
                  ? Colors.amber.withValues(alpha: 0.18)
                  : Colors.black.withValues(alpha: 0.07),
              blurRadius: isPromoted ? 20 : 12,
              spreadRadius: isPromoted ? 1 : 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        // IntrinsicHeight lets the image column match the details column height
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Action image (left ~38%) ─────────────────────────────────
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 185, maxWidth: 130),
                child: SizedBox(
                  width: 130,
                  child: _buildActionImage(data, isOnline),
                ),
              ),
              // ── Details (right ~62%) ──────────────────────────────────────
              Expanded(
                child: _buildExpertDetails(
                    data, isVerified, isPromoted, isOnline, expertId),
              ),
            ],
          ),
        ),
          ),
          // ── Favorite heart ────────────────────────────────────────────────
          Positioned(
            bottom: 24,
            right: 12,
            child: FavoriteButton(providerId: expertId),
          ),
        ],
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
      ),
      floatingActionButton: widget.volunteerOnly
          ? _WhatsAppSosButton()
          : null,
      body: Column(
        children: [
          if (widget.volunteerOnly) _buildVolunteerHeader(),
          _buildSearchAndFilter(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadInitial,
              color: _kPurple,
              strokeWidth: 2.5,
              child: _buildList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Volunteer Hub Header ──────────────────────────────────────────────────

  static const String _kCoordinatorPhone = '972501234567'; // ← replace with real number

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
          const Text(
            'שירות קהילתי ללא עלות — 100% חינם ❤️',
            textAlign: TextAlign.center,
            style: TextStyle(
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
                  label: 'אני צריך עזרה',
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
                  label: 'עזרה עבור מישהו אחר',
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
            child: const Text(
              'AnySkill מחבר אתכם עם מומחים בעלי לב טוב. '
              'אנא כבדו את זמנם והשתמשו בשירות לצרכים אמיתיים בלבד.',
              textAlign: TextAlign.right,
              style: TextStyle(
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

          // פילטר מחיר
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => setState(() => _filterUnder100 = !_filterUnder100),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _filterUnder100 ? _kPurple : Colors.white,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                    color: _filterUnder100
                        ? _kPurple
                        : Colors.grey.shade300,
                  ),
                  boxShadow: _filterUnder100
                      ? [
                          BoxShadow(
                            color: _kPurple.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.attach_money,
                        size: 14,
                        color: _filterUnder100 ? Colors.white : Colors.grey[600]),
                    const SizedBox(width: 6),
                    Text(
                      l10n.catResultsUnder100,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _filterUnder100 ? Colors.white : Colors.grey[800],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
      return const Center(child: CircularProgressIndicator());
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
    );

    return _renderExperts(context, experts);
  }

  Widget _renderExperts(BuildContext context, List<Map<String, dynamic>> experts) {
    final l10n = AppLocalizations.of(context);
    if (experts.isEmpty && !_isLoadingMore && !_hasMore) {
      final hasFilters = _searchQuery.isNotEmpty || _filterUnder100;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
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
                    : l10n.catResultsBeFirst,
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
                  }),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // +1 sentinel item for the load-more spinner / "all loaded" indicator
    final sentinelCount = (_isLoadingMore || _hasMore) ? 1 : 0;
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: experts.length + sentinelCount,
      itemBuilder: (_, index) {
        if (index == experts.length) {
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
        return RepaintBoundary(child: _buildExpertCard(experts[index]));
      },
    );
  }
}

// ── Community action button ───────────────────────────────────────────────────
class _CommunityActionButton extends StatelessWidget {
  const _CommunityActionButton({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });
  final String       label;
  final IconData     icon;
  final LinearGradient gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: gradient.colors.first.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ── WhatsApp SOS FAB ──────────────────────────────────────────────────────────
class _WhatsAppSosButton extends StatelessWidget {
  static const _phone = _CategoryResultsScreenState._kCoordinatorPhone;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      backgroundColor: const Color(0xFF25D366),
      elevation: 6,
      icon: const Icon(Icons.chat_rounded, color: Colors.white),
      label: const Text(
        'דברו עם רכז קהילה',
        style: TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
      ),
      onPressed: () async {
        const msg = 'שלום, אני צריך עזרה בפרסום בקשת התנדבות ב-AnySkill';
        final uri = Uri.parse('https://wa.me/$_phone?text=${Uri.encodeComponent(msg)}');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
    );
  }
}

// ── Help request form sheet ───────────────────────────────────────────────────
class _HelpRequestSheet extends StatefulWidget {
  const _HelpRequestSheet({required this.forOther});
  final bool forOther;

  @override
  State<_HelpRequestSheet> createState() => _HelpRequestSheetState();
}

class _HelpRequestSheetState extends State<_HelpRequestSheet> {
  final _descCtrl        = TextEditingController();
  final _locationCtrl    = TextEditingController();
  final _phoneCtrl       = TextEditingController();
  final _beneficiaryCtrl = TextEditingController();

  String? _selectedCategory;
  bool    _iAmContact  = true;
  bool    _submitting  = false;

  List<Map<String, dynamic>> _mainCategories = [];

  @override
  void initState() {
    super.initState();
    // Load category list once for the picker
    // .first throws "Bad state: No element" if the stream closes empty.
    // .catchError silently ignores that case — the picker just stays empty.
    CategoryService.streamMainCategories().first.then((cats) {
      if (mounted) setState(() => _mainCategories = cats);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _phoneCtrl.dispose();
    _beneficiaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedCategory == null ||
        _descCtrl.text.trim().isEmpty ||
        _phoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('נא למלא קטגוריה, תיאור ומספר טלפון'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    final nav       = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final uid      = FirebaseAuth.instance.currentUser?.uid ?? '';
      final category = _selectedCategory!;
      final db       = FirebaseFirestore.instance;

      // 1. Save the volunteer request
      await db.collection('volunteer_requests').add({
        'requesterId':     uid,
        'forOther':        widget.forOther,
        'beneficiaryName': widget.forOther ? _beneficiaryCtrl.text.trim() : null,
        'contactIsRequester': widget.forOther ? _iAmContact : true,
        'category':        category,
        'description':     _descCtrl.text.trim(),
        'location':        _locationCtrl.text.trim(),
        'contactPhone':    _phoneCtrl.text.trim(),
        'status':          'open',
        'createdAt':       FieldValue.serverTimestamp(),
      });

      // 2. Notify matching volunteers (fire-and-forget batch)
      _notifyVolunteers(category, _descCtrl.text.trim());

      nav.pop();
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'הבקשה נשלחה! מתנדבים מתאימים יקבלו התראה.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Queries all volunteer providers in [category] and writes an in-app
  /// notification for each (capped at 30 to stay within free Firestore quota).
  Future<void> _notifyVolunteers(String category, String description) async {
    try {
      final db   = FirebaseFirestore.instance;
      final snap = await db
          .collection('users')
          .where('isProvider',  isEqualTo: true)
          .where('isVolunteer', isEqualTo: true)
          .where('serviceType', isEqualTo: category)
          .limit(30)
          .get();

      final batch = db.batch();
      for (final doc in snap.docs) {
        final ref = db.collection('notifications').doc();
        batch.set(ref, {
          'userId':    doc.id,
          'title':    '❤️ בקשת התנדבות חדשה',
          'body':     'יש בקשת עזרה בתחום $category: "${description.length > 60 ? '${description.substring(0, 60)}…' : description}"',
          'type':     'volunteer_request',
          'isRead':   false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (_) {
      // Best-effort — a notification failure must never affect the request post
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),

              // Title + free badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('100% חינם ❤️',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                  Text(
                    widget.forOther ? 'עזרה עבור מישהו אחר' : 'אני צריך עזרה',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Category picker ──────────────────────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: Text('קטגוריה',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.grey[700])),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: _selectedCategory,
                hint: const Text('בחר תחום עזרה', textAlign: TextAlign.right),
                items: _mainCategories
                    .map((c) => DropdownMenuItem(
                          value: c['name'] as String,
                          child: Text(c['name'] as String? ?? '',
                              textAlign: TextAlign.right),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedCategory = v),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF5F6FA),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFF10B981))),
                ),
              ),
              const SizedBox(height: 16),

              // ── Description ──────────────────────────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: Text('תיאור הבקשה',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.grey[700])),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _descCtrl,
                maxLines: 3,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  hintText: 'תאר/י מה צריך לעשות...',
                  filled: true,
                  fillColor: const Color(0xFFF5F6FA),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFF10B981))),
                ),
              ),
              const SizedBox(height: 16),

              // ── Location ─────────────────────────────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: Text('מיקום',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.grey[700])),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _locationCtrl,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  hintText: 'עיר / שכונה',
                  prefixIcon: const Icon(Icons.location_on_outlined,
                      color: Color(0xFF10B981)),
                  filled: true,
                  fillColor: const Color(0xFFF5F6FA),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFF10B981))),
                ),
              ),
              const SizedBox(height: 16),

              // ── Contact phone ─────────────────────────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: Text('טלפון ליצירת קשר',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.grey[700])),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  hintText: '05X-XXXXXXX',
                  prefixIcon: const Icon(Icons.phone_outlined,
                      color: Color(0xFF10B981)),
                  filled: true,
                  fillColor: const Color(0xFFF5F6FA),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFF10B981))),
                ),
              ),

              // ── For-other extras ──────────────────────────────────────────
              if (widget.forOther) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('שם המוטב',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700])),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _beneficiaryCtrl,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    hintText: 'שם האדם שצריך עזרה',
                    filled: true,
                    fillColor: const Color(0xFFF5F6FA),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Color(0xFF10B981))),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  value: _iAmContact,
                  onChanged: (v) => setState(() => _iAmContact = v),
                  activeColor: const Color(0xFF10B981),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('אני איש הקשר',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                      'אני זה שיתואם מול המתנדב',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 12)),
                ),
              ],

              const SizedBox(height: 24),

              // ── Submit button ─────────────────────────────────────────────
              ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 54),
                  backgroundColor: const Color(0xFF10B981),
                  disabledBackgroundColor:
                      const Color(0xFF10B981).withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : const Text(
                        'שלח בקשת עזרה',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
