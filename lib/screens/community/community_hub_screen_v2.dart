/// Mockup 01 — Community Hub v2 main screen.
///
/// **Replaces** the legacy 3,855-line [community_hub_screen.dart] for v2
/// viewers (gated via [isCommunityV2EnabledFor]). The legacy screen is
/// untouched and continues to render for non-whitelisted users.
///
/// **Layout** (top to bottom):
/// 1. Header (back arrow + "קהילה" title + search icon).
/// 2. Hero stat: "{X} התנדבויות" this month.
/// 3. Social proof bar: facepile of recent active volunteers.
/// 4. "המומלצים החודש" — horizontal carousel of 3 active-heart volunteers.
/// 5. Two tabs:
///    - "בקשות פתוחות" — vertical feed of `community_requests where status==open`.
///    - "ההתנדבויות שלי" — embeds [MyVolunteeringContent] from Phase C.
/// 6. Filter pills below tab 1: הכל / קרוב אליי / קשישים / חיילים / משפחות.
/// 7. Bottom CTA: "פרסם בקשה להתנדבות".
///
/// **Phase D-1 stubs** (resolved in D-2 / E):
/// - Tap on a request card → snackbar "מסך הפרטים מגיע ב-Phase D-2".
/// - Tap on "פרסם בקשה להתנדבות" → snackbar "הטופס מגיע ב-Phase E".
/// - Tap on a recommended volunteer card → push existing PublicProfileScreen.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../theme/community_theme.dart';
import '../../utils/gold_heart_helper.dart';
import '../../widgets/community/avatar_with_gold_heart.dart';
import '../../widgets/community/pill_chip.dart';
import '../../widgets/community/section_header.dart';
import '../public_profile_screen.dart';
import 'map_view_screen.dart';
import 'my_volunteering_screen.dart';
import 'onboarding_intro_screen.dart';
import 'request_detail_screen.dart';
import 'request_form_screen.dart';

class CommunityHubScreenV2 extends StatefulWidget {
  const CommunityHubScreenV2({super.key});

  @override
  State<CommunityHubScreenV2> createState() => _CommunityHubScreenV2State();
}

class _CommunityHubScreenV2State extends State<CommunityHubScreenV2>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  /// Currently selected pill in tab 1's filter row. `null` == "הכל".
  String? _filterRequesterType;

  @override
  void initState() {
    super.initState();
    // Phase E (v15.x): show the 3-slide onboarding (mockup 11) once on
    // first community visit. Gate uses SharedPreferences — no network
    // call, fails silent if storage unavailable.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final shouldShow = await CommunityV2OnboardingGate.shouldShow();
      if (!mounted || !shouldShow) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const OnboardingIntroScreen(),
          fullscreenDialog: true,
        ),
      );
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CommunityColors.primaryWhite,
      body: SafeArea(
        child: Column(
          children: [
            _Header(),
            Expanded(
              child: NestedScrollView(
                headerSliverBuilder: (context, _) => [
                  SliverToBoxAdapter(child: _Hero()),
                  const SliverToBoxAdapter(child: _SocialProofBar()),
                  const SliverToBoxAdapter(child: _RecommendedRow()),
                  SliverToBoxAdapter(child: _Tabs(controller: _tabController)),
                ],
                body: TabBarView(
                  controller: _tabController,
                  children: [
                    _OpenRequestsTab(
                      filter: _filterRequesterType,
                      onFilterChanged: (f) =>
                          setState(() => _filterRequesterType = f),
                    ),
                    const MyVolunteeringContent(),
                  ],
                ),
              ),
            ),
            _BottomCta(),
          ],
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: CommunityColors.borderSofter, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            iconSize: 18,
            color: CommunityColors.textPrimary,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_forward_rounded), // RTL: visual-back
          ),
          const Expanded(
            child: Center(
              child: Text(
                'קהילה',
                style: TextStyle(
                  fontFamily: CommunityType.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1,
                  color: CommunityColors.textPrimary,
                ),
              ),
            ),
          ),
          IconButton(
            iconSize: 18,
            color: CommunityColors.textPrimary,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const CommunityMapViewScreen(),
              ),
            ),
            tooltip: 'מפה',
            icon: const Icon(Icons.map_outlined),
          ),
          IconButton(
            iconSize: 18,
            color: CommunityColors.textPrimary,
            // Skills search (mockup 14) is deferred to V2 per user
            // decision in Phase plan kickoff (אופציה 4 = "דחוי").
            onPressed: () => _phaseStub(
                context, 'חיפוש מיומנויות יגיע בעדכון עתידי'),
            icon: const Icon(Icons.search_rounded),
          ),
        ],
      ),
    );
  }
}

// ── Hero "החודש בקהילה" stat ─────────────────────────────────────────────
class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final startOfMonth = Timestamp.fromDate(
      DateTime(DateTime.now().year, DateTime.now().month, 1),
    );
    final query = FirebaseFirestore.instance
        .collection('community_requests')
        .where('status', isEqualTo: 'completed')
        .where('completedAt', isGreaterThanOrEqualTo: startOfMonth)
        .limit(500);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
      child: FutureBuilder<QuerySnapshot>(
        future: query.get(),
        builder: (context, snap) {
          final count = snap.data?.docs.length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'החודש בקהילה',
                style: TextStyle(
                  fontFamily: CommunityType.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                  color: CommunityColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                count == null ? '— התנדבויות' : '$count התנדבויות',
                style: const TextStyle(
                  fontFamily: CommunityType.fontFamily,
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.8,
                  height: 1.1,
                  color: CommunityColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Row(
                children: [
                  // Monthly delta — "+23%" in mockup. Computing it requires
                  // a 2nd query (prior month). Leave as graceful placeholder
                  // until Phase H rollup; same pattern as mockup 07's hero.
                  Text(
                    '—',
                    style: TextStyle(
                      fontFamily: CommunityType.fontFamily,
                      fontSize: 13,
                      color: CommunityColors.textTertiary,
                    ),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'מהחודש שעבר',
                    style: TextStyle(
                      fontFamily: CommunityType.fontFamily,
                      fontSize: 13,
                      color: CommunityColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Social proof bar ──────────────────────────────────────────────────────
class _SocialProofBar extends StatelessWidget {
  const _SocialProofBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: FutureBuilder<List<_VolunteerCardData>>(
        future: _loadActiveVolunteers(limit: 5),
        builder: (context, snap) {
          if (snap.hasError) return const SizedBox.shrink();
          final list = snap.data ?? const <_VolunteerCardData>[];
          if (list.isEmpty) return const SizedBox.shrink();
          final pile = list.take(3).toList();
          final firstName = pile.first.name.split(RegExp(r'\s+')).first;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: CommunityDecorations.cardSoft,
            child: Row(
              children: [
                SizedBox(
                  width: 28.0 + (pile.length - 1) * 20.0,
                  height: 28,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (int i = pile.length - 1; i >= 0; i--)
                        PositionedDirectional(
                          start: i * 20.0,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: CommunityColors.surface,
                                width: 2,
                              ),
                            ),
                            child: AvatarWithGoldHeart(
                              imageUrl: pile[i].imageUrl,
                              name: pile[i].name,
                              size: 28,
                              // No heart badge in the facepile — would
                              // be visual noise at 28px.
                              goldHeartExpiresAt: null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontFamily: CommunityType.fontFamily,
                        fontSize: 12,
                        color: CommunityColors.textPrimary,
                        height: 1.45,
                        letterSpacing: -0.1,
                      ),
                      children: [
                        TextSpan(
                          text: pile.length > 1
                              ? '$firstName ועוד ${pile.length - 1} שכנים'
                              : firstName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const TextSpan(text: ' שלך התנדבו השבוע'),
                      ],
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_left_rounded, // RTL-visual: trailing
                  size: 14,
                  color: CommunityColors.textTertiary,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Recommended row (horizontal carousel) ─────────────────────────────────
class _RecommendedRow extends StatelessWidget {
  const _RecommendedRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CommunitySectionHeader(
            title: 'המומלצים החודש',
            trailingLabel: 'הצג הכל',
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 110,
            child: FutureBuilder<List<_VolunteerCardData>>(
              future: _loadActiveVolunteers(limit: 8),
              builder: (context, snap) {
                if (snap.hasError) return const SizedBox.shrink();
                if (!snap.hasData) {
                  return const Center(
                    child: SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                final list = snap.data!;
                if (list.isEmpty) {
                  return const SizedBox.shrink();
                }
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => _RecommendedCard(data: list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendedCard extends StatelessWidget {
  const _RecommendedCard({required this.data});
  final _VolunteerCardData data;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PublicProfileScreen(userId: data.uid),
        ),
      ),
      borderRadius: const BorderRadius.all(CommunityRadius.card),
      child: Container(
        width: 152,
        padding: const EdgeInsets.all(14),
        decoration: CommunityDecorations.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                AvatarWithGoldHeart(
                  imageUrl: data.imageUrl,
                  name: data.name,
                  size: 36,
                  goldHeartExpiresAt: data.goldHeartExpiresAt,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        data.name.split(RegExp(r'\s+')).first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: CommunityType.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: CommunityColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        data.serviceType ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: CommunityType.fontFamily,
                          fontSize: 11,
                          color: CommunityColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded,
                        size: 11, color: CommunityColors.starGold),
                    const SizedBox(width: 4),
                    Text(
                      data.rating == null
                          ? '—'
                          : data.rating!.toStringAsFixed(1),
                      style: const TextStyle(
                        fontFamily: CommunityType.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: CommunityColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${data.taskCount} התנדבויות',
                  style: const TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 11,
                    color: CommunityColors.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Two tabs ──────────────────────────────────────────────────────────────
class _Tabs extends StatelessWidget {
  const _Tabs({required this.controller});
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: CommunityColors.borderSubtle, width: 0.5),
        ),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorColor: CommunityColors.primaryBlack,
        indicatorWeight: 1.5,
        indicatorSize: TabBarIndicatorSize.label,
        indicatorPadding: const EdgeInsets.only(top: 6),
        dividerColor: Colors.transparent,
        labelPadding: const EdgeInsets.symmetric(horizontal: 14),
        labelColor: CommunityColors.textPrimary,
        unselectedLabelColor: CommunityColors.textMuted,
        labelStyle: const TextStyle(
          fontFamily: CommunityType.fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: CommunityType.fontFamily,
          fontSize: 13,
          letterSpacing: -0.1,
        ),
        tabs: const [
          Tab(text: 'בקשות פתוחות'),
          Tab(text: 'ההתנדבויות שלי'),
        ],
      ),
    );
  }
}

// ── Open requests tab ─────────────────────────────────────────────────────
class _OpenRequestsTab extends StatelessWidget {
  const _OpenRequestsTab({required this.filter, required this.onFilterChanged});
  final String? filter;
  final ValueChanged<String?> onFilterChanged;

  static const _filters = <Map<String, String?>>[
    {'id': null, 'label': 'הכל'},
    {'id': 'nearby', 'label': 'קרוב אליי'},
    {'id': 'elderly', 'label': 'קשישים'},
    {'id': 'lone_soldier', 'label': 'חיילים'},
    {'id': 'struggling_family', 'label': 'משפחות'},
  ];

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('community_requests')
        .where('status', isEqualTo: 'open')
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots();

    return Column(
      children: [
        // Filter pill row
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: SizedBox(
            height: 30,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final f = _filters[i];
                final id = f['id'];
                return CommunityPillChip(
                  label: f['label']!,
                  selected: filter == id,
                  onTap: () => onFilterChanged(id),
                );
              },
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: stream,
            builder: (context, snap) {
              if (snap.hasError) {
                return _empty('שגיאה בטעינת הבקשות. נסה שוב.');
              }
              if (!snap.hasData) {
                return const Center(
                  child: SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final docs = snap.data!.docs.where((d) {
                final data = (d.data() as Map<String, dynamic>?) ?? const {};
                if (filter == null) return true;
                if (filter == 'nearby') {
                  // No real geo filter yet — show all. Phase E (mockup 13)
                  // will wire this to the map service's distance helper.
                  return true;
                }
                return data['requesterType'] == filter;
              }).toList();
              if (docs.isEmpty) {
                return _empty('אין כרגע בקשות פתוחות באזור הזה');
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d = docs[i];
                  return _RequestRow(
                    data: (d.data() as Map<String, dynamic>?) ?? const {},
                    requestId: d.id,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _empty(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: CommunityType.fontFamily,
              fontSize: 13,
              color: CommunityColors.textTertiary,
            ),
          ),
        ),
      );
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.data, required this.requestId});
  final Map<String, dynamic> data;
  final String requestId;

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String? ?? 'בקשת התנדבות';
    final desc  = data['description'] as String? ?? '';
    final urgency = data['urgency'] as String? ?? 'normal';
    final reqType = data['requesterType'] as String? ?? '';
    final ts = data['createdAt'] as Timestamp?;

    return InkWell(
      // Phase D-2: tap routes to the request detail screen (mockup 02).
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RequestDetailScreen(requestId: requestId),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(
                color: CommunityColors.borderSubtle, width: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (urgency == 'high') ...[
              _urgentChip(),
              const SizedBox(height: 8),
            ],
            Text(title, style: CommunityType.title15),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: CommunityType.body13,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      _metaIcon(Icons.location_on_outlined),
                      const SizedBox(width: 4),
                      const Flexible(
                        child: Text(
                          'השכונה שלך',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: CommunityType.fontFamily,
                            fontSize: 12,
                            color: CommunityColors.textTertiary,
                          ),
                        ),
                      ),
                      if (reqType.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 2, height: 2,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: CommunityColors.textMuted,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _requesterTypeLabel(reqType),
                          style: const TextStyle(
                            fontFamily: CommunityType.fontFamily,
                            fontSize: 12,
                            color: CommunityColors.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  _relativeShort(ts),
                  style: const TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 11,
                    color: CommunityColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget _urgentChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: CommunityColors.dangerBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.access_time_rounded,
              size: 9, color: CommunityColors.danger),
          SizedBox(width: 5),
          Text(
            'דחוף',
            style: TextStyle(
              fontFamily: CommunityType.fontFamily,
              fontSize: 11,
              color: CommunityColors.danger,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _metaIcon(IconData icon) =>
      Icon(icon, size: 11, color: CommunityColors.textTertiary);

  static String _requesterTypeLabel(String id) {
    switch (id) {
      case 'elderly':            return 'קשישים';
      case 'lone_soldier':       return 'חייל בודד';
      case 'struggling_family':  return 'משפחה';
      case 'general':            return 'כללי';
      default:                   return id;
    }
  }

  static String _relativeShort(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 60) return "${diff.inMinutes} דק'";
    if (diff.inHours   < 24) return '${diff.inHours} שע';
    return '${diff.inDays} ימים';
  }
}

// ── Bottom CTA ────────────────────────────────────────────────────────────
class _BottomCta extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: CommunityColors.primaryWhite,
        border: Border(
          top: BorderSide(color: CommunityColors.borderSubtle, width: 0.5),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const RequestFormScreen(),
              fullscreenDialog: true,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: CommunityColors.primaryBlack,
            foregroundColor: CommunityColors.primaryWhite,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(CommunityRadius.pill),
            ),
            minimumSize: const Size(double.infinity, 48),
          ),
          child: const Text(
            'פרסם בקשה להתנדבות',
            style: TextStyle(
              fontFamily: CommunityType.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

void _phaseStub(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text,
          style: const TextStyle(fontFamily: CommunityType.fontFamily)),
      backgroundColor: CommunityColors.primaryBlack,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

class _VolunteerCardData {
  _VolunteerCardData({
    required this.uid,
    required this.name,
    required this.imageUrl,
    required this.taskCount,
    required this.goldHeartExpiresAt,
    this.rating,
    this.serviceType,
  });
  final String uid;
  final String name;
  final String? imageUrl;
  final int taskCount;
  final Timestamp? goldHeartExpiresAt;
  final double? rating;
  final String? serviceType;
}

/// Shared loader for the social-proof bar + recommended row. Returns
/// active-heart volunteers sorted by completion count, capped at [limit].
/// Fail-safe: returns an empty list on any error.
Future<List<_VolunteerCardData>> _loadActiveVolunteers({
  required int limit,
}) async {
  try {
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(GoldHeartHelper.goldHeartDuration),
    );
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('lastVolunteerTaskAt', isGreaterThan: cutoff)
        .orderBy('lastVolunteerTaskAt', descending: true)
        .limit(limit)
        .get();
    final out = <_VolunteerCardData>[];
    for (final d in snap.docs) {
      final m = d.data();
      // Skip self — facepile shouldn't include the viewer.
      if (d.id == FirebaseAuth.instance.currentUser?.uid) continue;
      out.add(_VolunteerCardData(
        uid: d.id,
        name: (m['name'] as String? ?? '').trim().isEmpty
            ? 'מתנדב'
            : m['name'] as String,
        imageUrl: m['profileImage'] as String?,
        taskCount: (m['volunteerTaskCount'] as num? ?? 0).toInt(),
        goldHeartExpiresAt: m['goldHeartExpiresAt'] as Timestamp?,
        rating: (m['rating'] is num) ? (m['rating'] as num).toDouble() : null,
        serviceType: m['serviceType'] as String?,
      ));
    }
    return out;
  } catch (_) {
    return const [];
  }
}
