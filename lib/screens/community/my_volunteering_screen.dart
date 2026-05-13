/// Mockup 07 — "ההתנדבויות שלי" screen.
///
/// **What it shows (top to bottom):**
/// 1. Back-arrow header + "קהילה" title.
/// 2. Hero: total `volunteerTaskCount` + monthly delta.
/// 3. Stats row: `communityXP` + average rating (placeholder per Phase
///    C kickoff שאלה 1 — real avg rating ships in Phase D with mockup 05).
/// 4. Gold-heart 30-day progress card (uses [GoldHeartHelper.progressFraction]).
/// 5. Two tabs: פעילות (in_progress + pending_confirmation) + היסטוריה (completed).
/// 6. Tab body: cards from [CommunityHubService.streamMyVolunteerTasks]
///    or a one-shot history query.
///
/// **Action wiring (Phase C limitations):**
/// - "סיימתי" + "צ'אט" buttons currently show "מגיע ב-Phase D" snackbars.
///   Phase D wires them to the new completion screen (mockup 04) and
///   the chat screen.
///
/// **Navigation TO this screen:** not wired in Phase C — this is a
/// standalone destination Phase D will mount inside the new
/// community_hub_screen tabs. For now you can push it manually via
/// `Navigator.push(MaterialPageRoute(builder: (_) => MyVolunteeringScreen()))`
/// from any debug button.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/community_hub_service.dart';
import '../../theme/community_theme.dart';
import '../../utils/gold_heart_helper.dart';
import '../../widgets/community/section_header.dart';
import '../../widgets/community/stat_block.dart';
import '../chat_screen.dart';
import 'complete_volunteering_screen.dart';

/// Standalone variant — wraps [MyVolunteeringContent] in a Scaffold +
/// header. Use when navigating directly via `Navigator.push`.
class MyVolunteeringScreen extends StatelessWidget {
  const MyVolunteeringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CommunityColors.primaryWhite,
      body: SafeArea(
        child: Column(
          children: [
            _Header(),
            const Expanded(child: MyVolunteeringContent()),
          ],
        ),
      ),
    );
  }
}

/// Embeddable body — used inside the v2 community hub's "ההתנדבויות שלי"
/// tab AND inside [MyVolunteeringScreen] for standalone navigation.
///
/// Owns its own [DefaultTabController] (פעילות / היסטוריה sub-tabs) and
/// its own user-doc stream — drop it anywhere and it works.
class MyVolunteeringContent extends StatefulWidget {
  const MyVolunteeringContent({super.key});

  @override
  State<MyVolunteeringContent> createState() => _MyVolunteeringContentState();
}

class _MyVolunteeringContentState extends State<MyVolunteeringContent> {
  late final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  // Activity statuses considered "active" for the volunteer's queue.
  static const Set<String> _activeStatuses = {
    'accepted',
    'in_progress',
    'pending_confirmation',
  };

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return const Center(
        child: Text(
          'יש להתחבר כדי לראות את ההתנדבויות שלך',
          style: TextStyle(
            fontFamily: CommunityType.fontFamily,
            color: CommunityColors.textSecondary,
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .snapshots(),
        builder: (context, userSnap) {
          if (userSnap.hasError) return const SizedBox.shrink();
          final userData = userSnap.data?.data() ?? const <String, dynamic>{};
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Hero(userData: userData)),
              SliverToBoxAdapter(child: _StatsRow(userData: userData)),
              SliverToBoxAdapter(child: _GoldHeartProgressCard(userData: userData)),
              SliverToBoxAdapter(child: _Tabs(uid: _uid)),
              SliverFillRemaining(
                hasScrollBody: true,
                child: TabBarView(
                  children: [
                    _ActiveTab(uid: _uid, activeStatuses: _activeStatuses),
                    _HistoryTab(uid: _uid),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Header ─────────────────────────────────────────────────────────────────
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
            color: CommunityColors.textTertiary,
            onPressed: () {},
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ],
      ),
    );
  }
}

// ── Hero stat ──────────────────────────────────────────────────────────────
class _Hero extends StatelessWidget {
  const _Hero({required this.userData});
  final Map<String, dynamic> userData;

  @override
  Widget build(BuildContext context) {
    final count = (userData['volunteerTaskCount'] as num? ?? 0).toInt();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'השפעה כוללת',
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
            '$count התנדבויות',
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
          // Monthly delta — computed from history below would be ideal,
          // but for Phase C we leave a graceful placeholder. Phase D can
          // compute it from the history query once that feed is wired
          // into a stream.
          const Row(
            children: [
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
                'החודש',
                style: TextStyle(
                  fontFamily: CommunityType.fontFamily,
                  fontSize: 13,
                  color: CommunityColors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Stats row ──────────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.userData});
  final Map<String, dynamic> userData;

  @override
  Widget build(BuildContext context) {
    final xp = (userData['communityXP'] as num? ?? 0).toInt();
    final formatted = _thousands(xp);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: CommunityStatRow(
        gap: 24,
        withTopBorder: true,
        withBottomBorder: false,
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        children: [
          CommunityStatBlock(
            value: formatted,
            label: 'XP קהילתי',
          ),
          const CommunityStatBlock(
            // Placeholder per Phase C kickoff — real average ships
            // alongside rating capture in Phase D.
            value: '—',
            label: 'דירוג ממוצע',
            valueIcon: Icons.star_rounded,
            valueIconColor: CommunityColors.starGold,
          ),
        ],
      ),
    );
  }

  static String _thousands(int n) {
    if (n < 1000) return '$n';
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ── Gold heart 30-day progress card ───────────────────────────────────────
class _GoldHeartProgressCard extends StatelessWidget {
  const _GoldHeartProgressCard({required this.userData});
  final Map<String, dynamic> userData;

  @override
  Widget build(BuildContext context) {
    final expiresAt = userData['goldHeartExpiresAt'] as Timestamp?
        ?? _legacyExpiry(userData);
    final daysLeft  = GoldHeartHelper.daysUntilExpiry(expiresAt);
    final fraction  = GoldHeartHelper.progressFraction(expiresAt);
    final dateShort = GoldHeartHelper.expiryDateHebrewShort(expiresAt);

    if (daysLeft == null || fraction == null) {
      // No active heart — render an empty state card with a soft hint.
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: _NoHeartCard(),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: CommunityDecorations.cardSoft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.favorite,
                        size: 14, color: CommunityColors.goldHeart),
                    SizedBox(width: 8),
                    Text(
                      'לב זהב פעיל',
                      style: TextStyle(
                        fontFamily: CommunityType.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                        color: CommunityColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                Text(
                  'עוד $daysLeft ימים',
                  style: const TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: CommunityColors.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Progress bar — fills LEFT-to-right in RTL the same way the
            // mockup renders: trailing edge fades.
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(height: 4, color: const Color(0x0F000000)),
                  FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: fraction,
                    child: Container(
                      height: 4,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: AlignmentDirectional.centerStart,
                          end: AlignmentDirectional.centerEnd,
                          colors: [Color(0xFFB8860B), Color(0xFFD4AF37)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  dateShort != null ? 'פג תוקף ב-$dateShort' : '',
                  style: const TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 11,
                    color: CommunityColors.textTertiary,
                  ),
                ),
                Text(
                  '$daysLeft / ${GoldHeartHelper.goldHeartDuration.inDays}',
                  style: const TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: CommunityColors.textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// During the v15.x rollout, fall back to the legacy
  /// `lastVolunteerTaskAt + 30d` computation for users who haven't yet
  /// triggered a v2-era completion. Same semantics as
  /// [GoldHeartHelper.hasActiveFromUserData].
  Timestamp? _legacyExpiry(Map<String, dynamic> userData) {
    final last = userData['lastVolunteerTaskAt'];
    if (last is! Timestamp) return null;
    return Timestamp.fromMillisecondsSinceEpoch(
      last.millisecondsSinceEpoch +
          GoldHeartHelper.goldHeartDuration.inMilliseconds,
    );
  }
}

class _NoHeartCard extends StatelessWidget {
  const _NoHeartCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: CommunityDecorations.cardSoft,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0x14A87F2A), // gold @ 8%
            ),
            child: const Icon(Icons.favorite_outline_rounded,
                size: 16, color: Color(0x99A87F2A)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'אין לך עדיין לב זהב פעיל. ההתנדבות הבאה תעניק לך לב ל-30 יום.',
              style: TextStyle(
                fontFamily: CommunityType.fontFamily,
                fontSize: 12,
                color: CommunityColors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tabs ───────────────────────────────────────────────────────────────────
class _Tabs extends StatelessWidget {
  const _Tabs({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    // Stream the volunteer's tasks once for the tab badge counts.
    return StreamBuilder<QuerySnapshot>(
      stream: CommunityHubService.streamMyVolunteerTasks(uid),
      builder: (context, snap) {
        final activeCount = snap.data?.docs.length ?? 0;
        return Container(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(
                  color: CommunityColors.borderSubtle, width: 0.5),
            ),
          ),
          child: TabBar(
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
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('פעילות'),
                    if (activeCount > 0) ...[
                      const SizedBox(width: 4),
                      _CountPill(count: activeCount),
                    ],
                  ],
                ),
              ),
              const Tab(text: 'היסטוריה'),
            ],
          ),
        );
      },
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: const BoxDecoration(
        color: CommunityColors.primaryBlack,
        borderRadius: BorderRadius.all(CommunityRadius.pill),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontFamily: CommunityType.fontFamily,
          fontSize: 10,
          color: CommunityColors.primaryWhite,
        ),
      ),
    );
  }
}

// ── Active tab body ────────────────────────────────────────────────────────
class _ActiveTab extends StatelessWidget {
  const _ActiveTab({required this.uid, required this.activeStatuses});
  final String uid;
  final Set<String> activeStatuses;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: CommunityHubService.streamMyVolunteerTasks(uid),
      builder: (context, snap) {
        if (snap.hasError) {
          return _emptyState('שגיאה בטעינה. נסה שוב.');
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
          final m = (d.data() as Map<String, dynamic>?) ?? const {};
          final status = m['status'] as String? ?? '';
          return activeStatuses.contains(status);
        }).toList();
        if (docs.isEmpty) {
          return _emptyState('אין כרגע התנדבויות פעילות');
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          itemCount: docs.length,
          itemBuilder: (_, i) => _ActiveTaskCard(
            taskId: docs[i].id,
            data: (docs[i].data() as Map<String, dynamic>?) ?? const {},
          ),
        );
      },
    );
  }

  Widget _emptyState(String text) => Center(
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

class _ActiveTaskCard extends StatelessWidget {
  const _ActiveTaskCard({required this.taskId, required this.data});
  final String taskId;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final title  = data['title'] as String? ?? 'התנדבות';
    final reqName = data['requesterName'] as String? ?? '';
    final status  = data['status'] as String? ?? '';

    final statusColor = _statusColor(status);
    final statusLabel = _statusLabel(status);
    final relTime    = _relativeFrom(data);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: CommunityColors.borderSubtle, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: statusColor,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                statusLabel,
                style: TextStyle(
                  fontFamily: CommunityType.fontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: _statusTextColor(status),
                ),
              ),
              if (relTime != null) ...[
                const SizedBox(width: 6),
                Text(
                  '· $relTime',
                  style: const TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 11,
                    color: CommunityColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: CommunityType.title15,
          ),
          const SizedBox(height: 4),
          Text(
            reqName,
            style: const TextStyle(
              fontFamily: CommunityType.fontFamily,
              fontSize: 13,
              color: CommunityColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          if (status == 'in_progress')
            _inProgressActions(context)
          else if (status == 'pending_confirmation')
            _pendingConfirmationCard(reqName)
          else
            _acceptedCard(),
        ],
      ),
    );
  }

  // Phase D-2: wired to the new completion + chat screens.
  Widget _inProgressActions(BuildContext context) {
    final requesterId = (data['requesterId'] as String? ?? '').trim();
    final requesterName = (data['requesterName'] as String? ?? '').trim();
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    CompleteVolunteeringScreen(requestId: taskId),
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: CommunityColors.primaryBlack,
              foregroundColor: CommunityColors.primaryWhite,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(CommunityRadius.pill),
              ),
            ),
            child: const Text('סיימתי',
                style: TextStyle(
                  fontFamily: CommunityType.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                )),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: requesterId.isEmpty
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        receiverId: requesterId,
                        receiverName: requesterName,
                      ),
                    ),
                  ),
          style: OutlinedButton.styleFrom(
            backgroundColor: CommunityColors.primaryWhite,
            foregroundColor: CommunityColors.textPrimary,
            side: const BorderSide(color: Color(0x1F000000), width: 0.5),
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 16),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(CommunityRadius.pill),
            ),
          ),
          child: const Text("צ'אט",
              style: TextStyle(
                fontFamily: CommunityType.fontFamily,
                fontSize: 13,
                letterSpacing: -0.1,
              )),
        ),
      ],
    );
  }

  Widget _pendingConfirmationCard(String reqName) {
    final who = reqName.isEmpty ? 'הפונה' : reqName;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: CommunityColors.warningBg,
        borderRadius: const BorderRadius.all(CommunityRadius.alert),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 14, color: CommunityColors.warningText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'ממתין ש$who יאשר את הסיום',
              style: const TextStyle(
                fontFamily: CommunityType.fontFamily,
                fontSize: 12,
                color: CommunityColors.goldHeartText,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _acceptedCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: CommunityColors.surface,
        borderRadius: const BorderRadius.all(CommunityRadius.alert),
      ),
      child: const Text(
        'ממתין שהפונה יאשר את ההתחלה',
        style: TextStyle(
          fontFamily: CommunityType.fontFamily,
          fontSize: 12,
          color: CommunityColors.textSecondary,
        ),
      ),
    );
  }

  static String _statusLabel(String s) {
    switch (s) {
      case 'accepted':            return 'אושר';
      case 'in_progress':         return 'בתהליך';
      case 'pending_confirmation':return 'ממתין לאישור';
      default:                    return s;
    }
  }

  static Color _statusColor(String s) {
    switch (s) {
      case 'in_progress':         return CommunityColors.success;
      case 'pending_confirmation':return CommunityColors.warning;
      default:                    return CommunityColors.textTertiary;
    }
  }

  static Color _statusTextColor(String s) {
    switch (s) {
      case 'in_progress':         return CommunityColors.success;
      case 'pending_confirmation':return CommunityColors.warningText;
      default:                    return CommunityColors.textTertiary;
    }
  }

  static String? _relativeFrom(Map<String, dynamic> data) {
    Timestamp? ts = data['startedAt'] as Timestamp?;
    ts ??= data['markedDoneAt'] as Timestamp?;
    ts ??= data['claimedAt']    as Timestamp?;
    if (ts == null) return null;
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1) return 'התחיל זה עתה';
    if (diff.inMinutes < 60) return 'התחיל לפני ${diff.inMinutes} דקות';
    if (diff.inHours   < 24) return 'התחיל לפני ${diff.inHours} שעות';
    return 'התחיל לפני ${diff.inDays} ימים';
  }
}

// ── History tab body ───────────────────────────────────────────────────────
class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    final since = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(days: 30)),
    );
    final query = FirebaseFirestore.instance
        .collection('community_requests')
        .where('volunteerId', isEqualTo: uid)
        .where('status', isEqualTo: 'completed')
        .where('completedAt', isGreaterThan: since)
        .orderBy('completedAt', descending: true)
        .limit(50);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'שגיאה בטעינת ההיסטוריה',
                style: TextStyle(
                  fontFamily: CommunityType.fontFamily,
                  color: CommunityColors.textTertiary,
                ),
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(
            child: SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'עדיין אין התנדבויות בהיסטוריה',
                style: TextStyle(
                  fontFamily: CommunityType.fontFamily,
                  fontSize: 13,
                  color: CommunityColors.textTertiary,
                ),
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          children: [
            const CommunitySectionLabel('החודש האחרון'),
            const SizedBox(height: 12),
            for (final d in docs) _HistoryRow(data: d.data()),
          ],
        );
      },
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final title    = data['title']         as String? ?? 'התנדבות';
    final reqName  = data['requesterName'] as String? ?? '';
    final ts       = data['completedAt']   as Timestamp?;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: CommunityColors.borderSubtle, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: CommunityColors.successBg,
            ),
            child: const Icon(Icons.check_rounded,
                size: 14, color: CommunityColors.success),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1,
                    color: CommunityColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${reqName.isEmpty ? 'הפונה' : reqName} · '
                  '${_dateHebrew(ts)} · +${CommunityHubService.communityXpReward} XP',
                  style: const TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 11,
                    color: CommunityColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          // Per-request rating (if/when capture lands in Phase D);
          // until then, we render nothing — no fake stars.
        ],
      ),
    );
  }

  static String _dateHebrew(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    const months = [
      'ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני',
      'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר',
    ];
    return '${d.day} ב${months[d.month - 1]}';
  }
}
