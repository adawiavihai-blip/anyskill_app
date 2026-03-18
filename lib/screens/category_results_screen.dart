import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:geolocator/geolocator.dart';
import 'expert_profile_screen.dart';
import '../utils/expert_filter.dart';
import '../services/location_service.dart';
import '../services/search_ranking_service.dart';
import '../widgets/level_badge.dart';
import '../constants/quick_tags.dart';
import '../l10n/app_localizations.dart';

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
  int    _refreshTrigger = 0;
  Future<List<Map<String, dynamic>>>? _expertsFuture;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _expertsFuture = _fetchExperts();
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

  /// חד-פעמי — מונע את באג ה-Firestore web SDK שמתרחש כאשר
  /// מאזין real-time מתבטל באמצע עדכון (assertion ve:-1).
  Future<List<Map<String, dynamic>>> _fetchExperts() async {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('users')
        .where('isProvider', isEqualTo: true);

    if (widget.volunteerOnly) {
      q = q.where('isVolunteer', isEqualTo: true);
    } else {
      q = q.where('serviceType', isEqualTo: widget.categoryName);
    }

    final snap = await q.limit(50).get();
    return snap.docs.map((d) {
      final map = d.data();
      map['uid'] = d.id;
      return map;
    }).toList();
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

  Widget _buildActionImage(Map<String, dynamic> data, bool isOnline) {
    final l10n = AppLocalizations.of(context);
    final gallery = (data['gallery'] as List?)?.cast<String>() ?? [];
    final actionImg =
        gallery.isNotEmpty ? gallery.first : (data['profileImage'] as String? ?? '');
    final hasImg = actionImg.isNotEmpty;

    // Trust badges to overlay on the image
    final orderCount  = (data['orderCount'] as num?)?.toInt() ?? 0;
    final respTime    = (data['responseTimeMinutes'] as num?)?.toInt() ?? 0;
    final rating      = (data['rating'] as num?)?.toDouble() ?? 0;
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
          fit: StackFit.expand,
          children: [
            // ── Image or placeholder ──────────────────────────────────────
            hasImg
                ? CachedNetworkImage(
                    imageUrl:       actionImg,
                    fit:            BoxFit.cover,
                    // Expert card is 130 px wide × ~200 px tall; 2× DPR cap.
                    memCacheWidth:  260,
                    memCacheHeight: 400,
                    fadeInDuration: const Duration(milliseconds: 220),
                    placeholder:    (_, __) => _ImageShimmer(),
                    errorWidget:    (_, __, ___) => _imagePlaceholder(),
                  )
                : _imagePlaceholder(),

            // ── Dark gradient for text readability ────────────────────────
            if (badges.isNotEmpty || isOnline)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.55),
                      ],
                      stops: const [0.45, 1.0],
                    ),
                  ),
                ),
              ),

            // ── Online dot ────────────────────────────────────────────────
            if (isOnline)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
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
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),

            // ── Trust badges (bottom of image) ────────────────────────────
            if (badges.isNotEmpty)
              Positioned(
                bottom: 8,
                left: 6,
                right: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: badges.map((b) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          color: Colors.black.withValues(alpha: 0.40),
                          child: Text(
                            b,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  )).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Branded placeholder shown when the provider hasn't uploaded a portfolio image.
  Widget _imagePlaceholder() {
    final l10n = AppLocalizations.of(context);
    return Container(
      color: _kPurpleSoft,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate_outlined,
              size: 32, color: _kPurple.withValues(alpha: 0.5)),
          const SizedBox(height: 6),
          Text(
            l10n.catResultsAddPhoto,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 10,
                color: _kPurple.withValues(alpha: 0.6),
                height: 1.4),
          ),
        ],
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
    final name        = data['name'] as String? ?? l10n.catResultsExpertDefault;
    final price       = data['pricePerHour'] ?? 100;
    final rating      = (data['rating'] as num?)?.toDouble() ?? 5.0;
    final reviewsCount = (data['reviewsCount'] as num?)?.toInt() ?? 0;
    final bio         = data['aboutMe'] as String? ?? '';
    final tagKeys     = ((data['quickTags'] as List?) ?? []).cast<String>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── Price (top-right, most prominent) ───────────────────────────
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

          // ── Name + verification + promoted ──────────────────────────────
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
          const SizedBox(height: 4),

          // ── Bio (1 line) ─────────────────────────────────────────────────
          if (bio.isNotEmpty)
            Text(
              bio,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          if (bio.isNotEmpty) const SizedBox(height: 4),

          // ── Quick Tags ───────────────────────────────────────────────────
          _buildQuickTagsRow(tagKeys),
          if (tagKeys.isNotEmpty) const SizedBox(height: 4),

          // ── Rating + location ────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Distance (leftmost — least important)
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
              // Stars
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

          const Spacer(),

          // ── "When are they free?" ghost button ──────────────────────────
          SizedBox(
            width: double.infinity,
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

          // ── Book Now — primary CTA ───────────────────────────────────────
          SizedBox(
            width: double.infinity,
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
      child: Container(
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
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Scaffold & list
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
            widget.volunteerOnly
                ? 'AnySkill למען הקהילה ❤️'
                : l10n.catResultsPageTitle(widget.categoryName),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Column(
        children: [
          _buildSearchAndFilter(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                setState(() {
                  _refreshTrigger++;
                  _expertsFuture = _fetchExperts();
                });
              },
              color: _kPurple,
              strokeWidth: 2.5,
              child: _buildList(),
            ),
          ),
        ],
      ),
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
    // בדיקות מזריקות Stream; ייצור משתמש ב-Future (מונע באג Firestore web SDK)
    if (widget.testStream != null) {
      return StreamBuilder<List<Map<String, dynamic>>>(
        stream: widget.testStream,
        builder: (context, snapshot) => _buildContent(context, snapshot),
      );
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(_refreshTrigger),
      future: _expertsFuture,
      builder: (context, snapshot) => _buildContent(context, snapshot),
    );
  }

  Widget _buildContent(
      BuildContext context, AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
    final l10n = AppLocalizations.of(context);
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    if (snapshot.hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(l10n.catResultsLoadError,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: Text(l10n.retryButton),
              onPressed: () => setState(() {
                _refreshTrigger++;
                _expertsFuture = _fetchExperts();
              }),
            ),
          ],
        ),
      );
    }

    final all = (snapshot.data ?? []).toList();
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

    if (experts.isEmpty) {
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

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: experts.length,
      itemBuilder: (_, index) => _buildExpertCard(experts[index]),
    );
  }
}

// ── Shimmer placeholder for expert card images ────────────────────────────────
class _ImageShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor:      const Color(0xFFE2E8F0),
      highlightColor: const Color(0xFFF8FAFC),
      child: Container(color: const Color(0xFFE2E8F0)),
    );
  }
}
