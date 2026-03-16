// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import 'search_screen/search_page.dart';

// ─── Public entry point ───────────────────────────────────────────────────────

class HomeTab extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String currentUserId;
  final bool isOnline;
  final VoidCallback onToggleOnline;
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
  // ── Pulse animation ────────────────────────────────────────────────────────
  late final AnimationController _pulseCtrl;

  // ── Firestore streams ─────────────────────────────────────────────────────
  late Stream<QuerySnapshot> _activityStream;
  late Stream<QuerySnapshot> _urgentStream;
  late Stream<QuerySnapshot> _chatStream;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _initStreams();
  }

  void _initStreams() {
    final uid = widget.currentUserId;
    final isProvider = widget.userData['isProvider'] == true;
    final category   = (widget.userData['serviceType'] ?? '') as String;

    // Recent transactions (activity hub)
    _activityStream = FirebaseFirestore.instance
        .collection('transactions')
        .where(Filter.or(
          Filter('senderId',   isEqualTo: uid),
          Filter('receiverId', isEqualTo: uid),
        ))
        .orderBy('timestamp', descending: true)
        .limit(3)
        .snapshots();

    // Latest chat rooms (for "new message" activity items)
    _chatStream = FirebaseFirestore.instance
        .collection('chats')
        .where('users', arrayContains: uid)
        .orderBy('lastMessageTime', descending: true)
        .limit(2)
        .snapshots();

    // Urgent banner: provider sees open job_requests; customer sees active jobs
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
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _openSearch({String? preselectedCategory}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, a1, a2) => SearchPage(
          isOnline: widget.isOnline,
          onToggleOnline: widget.onToggleOnline,
          initialCategory: preselectedCategory,
        ),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.04), end: Offset.zero)
                .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: child,
          ),
        ),
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }

  // ── XP helpers ─────────────────────────────────────────────────────────────
  static const _kLevels = [
    (0,    100,  '⭐ מתחיל',   Color(0xFF94A3B8)),
    (100,  300,  '🔥 מקצוען',  Color(0xFF6366F1)),
    (300,  700,  '💎 מומחה',   Color(0xFF0EA5E9)),
    (700,  1500, '🏆 אלוף',    Color(0xFFF59E0B)),
    (1500, 9999, '🌟 אגדה',    Color(0xFFEC4899)),
  ];

  ({String label, Color color, double progress, int toNext}) _xpInfo(int xp) {
    for (final (min, max, label, color) in _kLevels) {
      if (xp < max) {
        return (
          label: label,
          color: color,
          progress: (xp - min) / (max - min),
          toNext: max - xp,
        );
      }
    }
    final last = _kLevels.last;
    return (label: last.$3, color: last.$4, progress: 1.0, toNext: 0);
  }

  // ── Greeting ───────────────────────────────────────────────────────────────
  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'בוקר טוב';
    if (h < 17) return 'צהריים טובים';
    if (h < 21) return 'ערב טוב';
    return 'לילה טוב';
  }

  String get _firstName {
    final name = (widget.userData['name'] ?? '') as String;
    return name.contains(' ') ? name.split(' ').first : name;
  }

  // ── Category metadata ──────────────────────────────────────────────────────
  static const _catMeta = <String, (String emoji, Color bg, Color fg)>{
    'ספורט וכושר':   ('🏋️', Color(0xFFFFF7ED), Color(0xFFEA580C)),
    'ניקיון':         ('🧹', Color(0xFFF0FFF4), Color(0xFF16A34A)),
    'מחשבים וטכנולוגיה': ('💻', Color(0xFFEFF6FF), Color(0xFF2563EB)),
    'שיפוצים':        ('🔨', Color(0xFFFFF5F5), Color(0xFFDC2626)),
    'תירגום':         ('🌐', Color(0xFFF5F3FF), Color(0xFF7C3AED)),
    'צילום':          ('📸', Color(0xFFFFF0F5), Color(0xFFDB2777)),
    'שיעורים פרטיים':('📚', Color(0xFFFFFBEB), Color(0xFFD97706)),
    'עיצוב גרפי':    ('🎨', Color(0xFFF0FDFA), Color(0xFF0D9488)),
    'משפטי':         ('⚖️', Color(0xFFF8F9FF), Color(0xFF6366F1)),
    'בישול':          ('👨‍🍳', Color(0xFFFEF9EE), Color(0xFFC05621)),
    'כלבנות':        ('🐕', Color(0xFFF0FFF4), Color(0xFF15803D)),
    'אחר':            ('✨', Color(0xFFF8FAFC), Color(0xFF64748B)),
  };

  (String, Color, Color) _metaFor(String cat) =>
      _catMeta[cat] ?? ('✨', const Color(0xFFF8FAFC), const Color(0xFF64748B));

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final data       = widget.userData;
    final isProvider = data['isProvider'] == true;
    final xp         = ((data['xp'] ?? (data['orderCount'] ?? 0)) as num).toInt();
    final info       = _xpInfo(xp);
    final balance    = (data['balance'] ?? 0.0 as dynamic).toDouble();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: CustomScrollView(
        slivers: [
          // ── SliverAppBar: greeting header (collapsible) ──────────────────
          SliverToBoxAdapter(
            child: _buildGreetingCard(info, xp, balance, isProvider),
          ),

          // ── Tappable search bar ──────────────────────────────────────────
          SliverToBoxAdapter(child: _buildSearchBar()),

          // ── Urgent / Pulse banner ────────────────────────────────────────
          SliverToBoxAdapter(
            child: StreamBuilder<QuerySnapshot>(
              stream: _urgentStream,
              builder: (context, snap) {
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  if (_pulseCtrl.isAnimating) _pulseCtrl.stop();
                  return const SizedBox.shrink();
                }
                if (!_pulseCtrl.isAnimating) _pulseCtrl.repeat(reverse: true);
                return _buildUrgentBanner(docs, isProvider);
              },
            ),
          ),

          // ── Section title: categories ────────────────────────────────────
          SliverToBoxAdapter(child: _buildSectionTitle('קטגוריות', 'כל הקטגוריות', onSeeAll: () => _openSearch())),

          // ── Category tiles ───────────────────────────────────────────────
          SliverToBoxAdapter(child: _buildCategoryRow()),

          // ── Section title: activity hub ──────────────────────────────────
          SliverToBoxAdapter(
            child: _buildSectionTitle('פעילות אחרונה', '', onSeeAll: null),
          ),

          // ── Activity hub ─────────────────────────────────────────────────
          SliverToBoxAdapter(child: _buildActivityHub()),

          // ── Stats row (provider only) ────────────────────────────────────
          if (isProvider)
            SliverToBoxAdapter(child: _buildProviderStats(data)),

          // ── Bottom padding (for FAB) ─────────────────────────────────────
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
    );
  }

  // ── Greeting card ──────────────────────────────────────────────────────────
  Widget _buildGreetingCard(_$XpInfo info, int xp, double balance, bool isProvider) {
    final profileImage = (widget.userData['profileImage'] ?? '') as String;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 52, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF312E81), Color(0xFF4338CA)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: avatar + greeting ──────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _firstName.isNotEmpty ? _firstName : 'משתמש',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              // Balance chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.account_balance_wallet_rounded,
                        color: Colors.white70, size: 14),
                    const SizedBox(width: 5),
                    Text(
                      '₪${balance.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Avatar
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                backgroundImage: profileImage.isNotEmpty
                    ? NetworkImage(profileImage)
                    : null,
                child: profileImage.isEmpty
                    ? Text(
                        _firstName.isNotEmpty ? _firstName[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      )
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── XP level badge ──────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: info.color.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: info.color.withValues(alpha: 0.40)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(info.label,
                      style: TextStyle(
                        color: info.color,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      )),
                  const SizedBox(width: 6),
                  Text('$xp XP',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.60),
                        fontSize: 11,
                      )),
                ]),
              ),
              if (info.toNext > 0)
                Text(
                  'עוד ${info.toNext} XP לרמה הבאה',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // ── XP progress bar ──────────────────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: info.progress.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(info.color),
            ),
          ),
          const SizedBox(height: 14),

          // ── Daily goal strip (providers only) ────────────────────────────
          if (isProvider)
            _DailyGoalStrip(uid: widget.currentUserId, isProvider: isProvider),
        ],
      ),
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: GestureDetector(
        onTap: _openSearch,
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, color: Color(0xFF6366F1), size: 20),
              const SizedBox(width: 10),
              Text(
                'חפש מקצוען, שירות...',
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'חיפוש',
                  style: TextStyle(
                    color: Color(0xFF6366F1),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Urgent / Pulse banner ──────────────────────────────────────────────────
  Widget _buildUrgentBanner(List<QueryDocumentSnapshot> docs, bool isProvider) {
    final count = docs.length;
    final first = docs.first.data() as Map<String, dynamic>;
    final description = isProvider
        ? (first['description'] ?? first['title'] ?? 'שירות נדרש') as String
        : 'הלקוח מחכה לאישורך';

    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) {
        final glow = _pulseCtrl.value;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1C1917), Color(0xFF292524)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15 + glow * 0.18),
                blurRadius: 16 + glow * 6,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: isProvider ? () => _openSearch() : widget.onGoToBookings,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'פתח',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      description.length > 48
                          ? '${description.substring(0, 48)}...'
                          : description,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.40)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 6,
                        height: 6,
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
                      const SizedBox(width: 5),
                      Text(
                        isProvider ? 'Pulse' : 'דחוף',
                        style: const TextStyle(
                          color: Color(0xFFF59E0B),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$count ${isProvider ? "בקשות" : "ממתינות"}',
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

  // ── Section title ──────────────────────────────────────────────────────────
  Widget _buildSectionTitle(String title, String seeAll,
      {VoidCallback? onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (onSeeAll != null && seeAll.isNotEmpty)
            GestureDetector(
              onTap: onSeeAll,
              child: Text(
                seeAll,
                style: const TextStyle(
                  color: Color(0xFF6366F1),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            const SizedBox.shrink(),
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ],
      ),
    );
  }

  // ── Category tiles ─────────────────────────────────────────────────────────
  Widget _buildCategoryRow() {
    final cats = APP_CATEGORIES
        .map((c) => c['name'] as String)
        .toList();
    // Mark first 3 as trending
    const trendingSet = {'ספורט וכושר', 'מחשבים וטכנולוגיה', 'ניקיון'};

    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final cat = cats[i];
          final (emoji, bg, fg) = _metaFor(cat);
          final isTrending = trendingSet.contains(cat);

          return GestureDetector(
            onTap: () => _openSearch(preselectedCategory: cat),
            child: SizedBox(
              width: 82,
              child: Column(
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: fg.withValues(alpha: 0.15),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: fg.withValues(alpha: 0.10),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(emoji,
                              style: const TextStyle(fontSize: 28)),
                        ),
                      ),
                      if (isTrending)
                        Positioned(
                          top: 0,
                          left: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '🔥',
                              style: TextStyle(fontSize: 9),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cat,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Activity hub ───────────────────────────────────────────────────────────
  Widget _buildActivityHub() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Transactions
          StreamBuilder<QuerySnapshot>(
            stream: _activityStream,
            builder: (context, txSnap) {
              return StreamBuilder<QuerySnapshot>(
                stream: _chatStream,
                builder: (context, chatSnap) {
                  final txDocs   = txSnap.data?.docs ?? [];
                  final chatDocs = chatSnap.data?.docs ?? [];

                  if (txDocs.isEmpty && chatDocs.isEmpty) {
                    return _buildEmptyActivity();
                  }

                  final items = <Widget>[];

                  // Chat items first (most urgent)
                  for (final doc in chatDocs) {
                    final d = doc.data() as Map<String, dynamic>;
                    final lastMsg = d['lastMessage'] as String? ?? '';
                    final unread  = ((d['unreadCount_${widget.currentUserId}'] ?? 0) as num).toInt();
                    final otherName = d['otherName_${widget.currentUserId}'] as String?
                        ?? d['lastSenderName'] as String?
                        ?? 'משתמש';

                    if (lastMsg.isNotEmpty) {
                      items.add(_ActivityCard(
                        icon: Icons.chat_bubble_outline_rounded,
                        iconBg: const Color(0xFFEEF2FF),
                        iconColor: const Color(0xFF6366F1),
                        title: unread > 0
                            ? 'הודעה חדשה מ-$otherName ($unread)'
                            : 'שיחה עם $otherName',
                        subtitle: lastMsg.length > 42
                            ? '${lastMsg.substring(0, 42)}...'
                            : lastMsg,
                        badge: unread > 0 ? '$unread' : null,
                        badgeColor: const Color(0xFF6366F1),
                        onTap: widget.onGoToChat,
                      ));
                    }
                  }

                  // Transaction items
                  for (final doc in txDocs) {
                    final tx       = doc.data() as Map<String, dynamic>;
                    final isIncome = tx['receiverId'] == widget.currentUserId;
                    final amount   = (tx['amount'] ?? 0.0 as dynamic).toDouble();
                    final type     = tx['type'] as String? ?? '';
                    final ts       = tx['timestamp'] as Timestamp?;

                    String title;
                    IconData iconData;
                    Color iconBg, iconColor;

                    if (type == 'withdrawal_pending') {
                      title    = 'בקשת משיכה בטיפול';
                      iconData = Icons.savings_rounded;
                      iconBg   = const Color(0xFFF0FFF4);
                      iconColor = const Color(0xFF16A34A);
                    } else if (isIncome) {
                      title    = 'קיבלת ₪${amount.toStringAsFixed(0)}';
                      iconData = Icons.arrow_downward_rounded;
                      iconBg   = const Color(0xFFF0FFF4);
                      iconColor = const Color(0xFF16A34A);
                    } else {
                      title    = 'שילמת ₪${amount.toStringAsFixed(0)}';
                      iconData = Icons.arrow_upward_rounded;
                      iconBg   = const Color(0xFFFFF5F5);
                      iconColor = const Color(0xFFEF4444);
                    }

                    final dateStr = ts != null
                        ? DateFormat('dd/MM HH:mm').format(ts.toDate())
                        : '';

                    items.add(_ActivityCard(
                      icon: iconData,
                      iconBg: iconBg,
                      iconColor: iconColor,
                      title: title,
                      subtitle: dateStr,
                      onTap: widget.onGoToBookings,
                    ));
                  }

                  if (items.isEmpty) return _buildEmptyActivity();

                  return Column(
                    children: [
                      for (int i = 0; i < items.length; i++) ...[
                        items[i],
                        if (i < items.length - 1) const SizedBox(height: 8),
                      ],
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyActivity() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Icon(Icons.bolt_rounded, color: Color(0xFFCBD5E1), size: 38),
          const SizedBox(height: 8),
          Text(
            'אין פעילות עדיין',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: widget.onOpenQuickRequest,
            child: const Text(
              'פרסם בקשה ראשונה →',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF6366F1),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Provider stats row ─────────────────────────────────────────────────────
  Widget _buildProviderStats(Map<String, dynamic> data) {
    final orderCount = ((data['orderCount'] ?? 0) as num).toInt();
    final rating     = (data['rating'] ?? 5.0 as dynamic).toDouble();
    final reviews    = ((data['reviewsCount'] ?? 0) as num).toInt();
    final balance    = (data['balance'] ?? 0.0 as dynamic).toDouble();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(
        children: [
          Expanded(child: _StatTile(label: 'הזמנות', value: '$orderCount', icon: Icons.check_circle_outline_rounded, color: const Color(0xFF6366F1))),
          const SizedBox(width: 8),
          Expanded(child: _StatTile(label: 'דירוג', value: rating.toStringAsFixed(1), icon: Icons.star_rounded, color: const Color(0xFFF59E0B))),
          const SizedBox(width: 8),
          Expanded(child: _StatTile(label: 'ביקורות', value: '$reviews', icon: Icons.rate_review_outlined, color: const Color(0xFF10B981))),
          const SizedBox(width: 8),
          Expanded(child: _StatTile(label: 'יתרה', value: '₪${balance.toStringAsFixed(0)}', icon: Icons.account_balance_wallet_outlined, color: const Color(0xFF0EA5E9))),
        ],
      ),
    );
  }
}

// ─── Type alias for XP info (Dart 3 record) ─────────────────────────────────
typedef _$XpInfo = ({String label, Color color, double progress, int toNext});

// ─── Daily Goal Strip ─────────────────────────────────────────────────────────

class _DailyGoalStrip extends StatelessWidget {
  final String uid;
  final bool   isProvider;
  const _DailyGoalStrip({required this.uid, required this.isProvider});

  @override
  Widget build(BuildContext context) {
    // Query today's earnings
    final today = DateTime.now();
    final todayStart = Timestamp.fromDate(
        DateTime(today.year, today.month, today.day));
    const double kGoal = 200.0;

    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('transactions')
          .where('receiverId', isEqualTo: uid)
          .where('timestamp', isGreaterThan: todayStart)
          .limit(20)
          .get(),
      builder: (context, snap) {
        double todayEarned = 0;
        if (snap.hasData) {
          for (final d in snap.data!.docs) {
            final tx = d.data() as Map<String, dynamic>;
            todayEarned += (tx['amount'] ?? 0.0 as dynamic).toDouble();
          }
        }

        final progress = (todayEarned / kGoal).clamp(0.0, 1.0);
        final remaining = (kGoal - todayEarned).clamp(0, kGoal);
        final done = todayEarned >= kGoal;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Icon(
                      done ? Icons.emoji_events_rounded : Icons.track_changes_rounded,
                      color: done
                          ? const Color(0xFFF59E0B)
                          : Colors.white.withValues(alpha: 0.65),
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      done
                          ? '🎉 השגת את יעד היום!'
                          : 'עוד ₪${remaining.toStringAsFixed(0)} ליעד היומי',
                      style: TextStyle(
                        color: done
                            ? const Color(0xFFF59E0B)
                            : Colors.white.withValues(alpha: 0.65),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ]),
                  Text(
                    '₪${todayEarned.toStringAsFixed(0)} / ₪${kGoal.toInt()}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.50),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    done
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFF34D399),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Activity card ────────────────────────────────────────────────────────────

class _ActivityCard extends StatelessWidget {
  final IconData icon;
  final Color    iconBg;
  final Color    iconColor;
  final String   title;
  final String   subtitle;
  final String?  badge;
  final Color?   badgeColor;
  final VoidCallback? onTap;

  const _ActivityCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.badge,
    this.badgeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // ── Action indicator ──────────────────────────────────────────
            const Icon(Icons.chevron_left_rounded,
                color: Color(0xFFCBD5E1), size: 18),
            const Spacer(),
            // ── Text ──────────────────────────────────────────────────────
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            // ── Icon ─────────────────────────────────────────────────────
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                if (badge != null)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: badgeColor ?? const Color(0xFF6366F1),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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

// ─── Stat tile ────────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  final String   label;
  final String   value;
  final IconData icon;
  final Color    color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
