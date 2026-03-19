// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'expert_profile_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LiveActivityTab — Admin Control Tower
// ─────────────────────────────────────────────────────────────────────────────

class LiveActivityTab extends StatefulWidget {
  const LiveActivityTab({super.key});

  @override
  State<LiveActivityTab> createState() => _LiveActivityTabState();
}

class _LiveActivityTabState extends State<LiveActivityTab> {
  String _filter = 'הכל';

  // ── Filter definitions ────────────────────────────────────────────────────
  static const _kFilters = ['הכל', 'מחלוקות 🛡️', 'כסף 💰', 'משתמשים 👤'];

  static const _kFilterTypes = <String, Set<String>>{
    'מחלוקות 🛡️': {'new_dispute'},
    'כסף 💰':     {'job_accepted', 'payment', 'commission', 'job_request'},
    'משתמשים 👤': {
      'registration', 'story_upload', 'story_liked',
      'demo_contact', 'demo_booking_attempt',
    },
  };

  // ── Type → icon ───────────────────────────────────────────────────────────
  static const Map<String, IconData> _icons = {
    'job_request':          Icons.bolt_rounded,
    'job_accepted':         Icons.handshake_rounded,
    'volunteer_request':    Icons.volunteer_activism_rounded,
    'registration':         Icons.person_add_alt_1_rounded,
    'broadcast':            Icons.campaign_rounded,
    'demo_booking_attempt': Icons.local_fire_department_rounded,
    'demo_contact':         Icons.smart_toy_rounded,
    'bypass_attempt':       Icons.shield_rounded,
    'new_dispute':          Icons.gavel_rounded,
    'story_upload':         Icons.video_camera_back_rounded,
    'story_liked':          Icons.favorite_rounded,
    'reengagement_sent':    Icons.mark_email_read_rounded,
  };

  // ── Type → accent color ───────────────────────────────────────────────────
  static const Map<String, Color> _colors = {
    'job_request':          Color(0xFF6366F1),
    'job_accepted':         Color(0xFF10B981),
    'volunteer_request':    Color(0xFFF59E0B),
    'registration':         Color(0xFF3B82F6),
    'broadcast':            Color(0xFFEC4899),
    'demo_booking_attempt': Color(0xFFEF4444),
    'demo_contact':         Color(0xFF8B5CF6),
    'bypass_attempt':       Color(0xFFF97316),
    'new_dispute':          Color(0xFFEF4444),
    'story_upload':         Color(0xFF8B5CF6),
    'story_liked':          Color(0xFFEC4899),
    'reengagement_sent':    Color(0xFF10B981),
  };

  // ── Priority helpers ──────────────────────────────────────────────────────

  static bool _isHigh(String type, String priority) =>
      priority == 'high' ||
      const {'new_dispute', 'demo_booking_attempt', 'bypass_attempt'}.contains(type);

  static bool _isSuccess(String type) =>
      const {'job_accepted', 'registration', 'reengagement_sent'}.contains(type);

  static Color _bgFor(String type, String priority) {
    if (_isHigh(type, priority)) return const Color(0xFFFFF1F2); // red tint
    if (_isSuccess(type))        return const Color(0xFFF0FDF4); // green tint
    return Colors.white;
  }

  static String _badgeLabel(String type, String priority) {
    if (type == 'new_dispute')          return 'דחוף';
    if (type == 'demo_booking_attempt') return 'DEMO';
    if (type == 'bypass_attempt')       return 'ALERT';
    if (priority == 'high')             return 'HIGH';
    return '';
  }

  // ── Time-ago helper ───────────────────────────────────────────────────────
  static String _timeAgo(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inSeconds < 60) return 'עכשיו';
    if (diff.inMinutes < 60) return 'לפני ${diff.inMinutes}ד\'';
    if (diff.inHours   < 24) return 'לפני ${diff.inHours}ש\'';
    return 'לפני ${diff.inDays}ימים';
  }

  // ── Deep-link handler ─────────────────────────────────────────────────────
  void _onTap(BuildContext ctx, Map<String, dynamic> d, String type) {
    switch (type) {
      case 'new_dispute':
        // Disputes tab is index 4 in the admin's first TabBarView
        DefaultTabController.of(ctx).animateTo(4);

      case 'registration':
        final uid  = d['userId']       as String? ?? '';
        final name = (d['providerName'] ?? d['title'] ?? 'מומחה') as String;
        if (uid.isNotEmpty) {
          Navigator.push(ctx, MaterialPageRoute(
            builder: (_) =>
                ExpertProfileScreen(expertId: uid, expertName: name),
          ));
        }

      case 'demo_contact':
        final uid  = d['receiverId']   as String? ?? '';
        final name = d['providerName'] as String? ?? 'מומחה';
        if (uid.isNotEmpty) {
          Navigator.push(ctx, MaterialPageRoute(
            builder: (_) =>
                ExpertProfileScreen(expertId: uid, expertName: name),
          ));
        }
    }
  }

  bool _matchesFilter(String type) {
    if (_filter == 'הכל') return true;
    return _kFilterTypes[_filter]?.contains(type) ?? false;
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Dark header bar ──────────────────────────────────────────────
        Container(
          color: const Color(0xFF0F172A),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              const _PulseDot(),
              const SizedBox(width: 8),
              const Text(
                'לייב פיד — מרכז שליטה',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
              const Spacer(),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('activity_log')
                    .limit(1)
                    .snapshots(),
                builder: (_, snap) {
                  final live = snap.data?.docs.isNotEmpty == true;
                  return Text(
                    live ? '●' : '—',
                    style: const TextStyle(
                        color: Color(0xFF22C55E), fontSize: 18),
                  );
                },
              ),
            ],
          ),
        ),

        // ── Filter chip row ──────────────────────────────────────────────
        Container(
          color: const Color(0xFF1E293B),
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            children: _kFilters.map((label) {
              final sel = _filter == label;
              return GestureDetector(
                onTap: () => setState(() => _filter = label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsetsDirectional.only(end: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: sel
                        ? const Color(0xFF6366F1)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel
                          ? const Color(0xFF6366F1)
                          : Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: sel
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.65),
                      fontSize: 12,
                      fontWeight:
                          sel ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // ── Live feed list ───────────────────────────────────────────────
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('activity_log')
                .orderBy('createdAt', descending: true)
                .limit(150)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final allDocs = snap.data?.docs ?? [];
              final docs = _filter == 'הכל'
                  ? allDocs
                  : allDocs.where((doc) {
                      final t =
                          (doc.data() as Map)['type'] as String? ?? '';
                      return _matchesFilter(t);
                    }).toList();

              // ── Empty state ──────────────────────────────────────────
              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('☕', style: TextStyle(fontSize: 60)),
                      const SizedBox(height: 18),
                      const Text(
                        'הכל שקט ב-AnySkill...',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'בינתיים! ☕',
                        style: TextStyle(
                            fontSize: 15, color: Colors.grey[500]),
                      ),
                      if (_filter != 'הכל') ...[
                        const SizedBox(height: 20),
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _filter = 'הכל'),
                          icon: const Icon(Icons.filter_alt_off_rounded,
                              size: 16),
                          label: const Text('הצג הכל'),
                        ),
                      ],
                    ],
                  ),
                );
              }

              // ── Entry list ───────────────────────────────────────────
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final d        = docs[i].data()! as Map<String, dynamic>;
                  final type     = d['type']     as String? ?? '';
                  final title    = d['title']    as String? ?? type;
                  final detail   = d['detail']   as String? ?? '';
                  final ts       = d['createdAt'] as Timestamp?;
                  final priority = d['priority'] as String? ?? '';
                  final icon     = _icons[type]  ?? Icons.circle_outlined;
                  final color    = _colors[type] ?? Colors.grey;
                  final isHigh   = _isHigh(type, priority);
                  final isOk     = _isSuccess(type);
                  final bg       = _bgFor(type, priority);
                  final badge    = _badgeLabel(type, priority);
                  final tappable = const {
                    'new_dispute', 'registration', 'demo_contact'
                  }.contains(type);

                  return GestureDetector(
                    onTap: tappable
                        ? () => _onTap(context, d, type)
                        : null,
                    child: Container(
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: isHigh
                              ? color.withValues(alpha: 0.40)
                              : isOk
                                  ? const Color(0xFF10B981)
                                      .withValues(alpha: 0.25)
                                  : Colors.grey.shade100,
                          width: isHigh ? 1.5 : 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isHigh
                                ? color.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.03),
                            blurRadius: isHigh ? 10 : 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Timestamp ──────────────────────────────
                          SizedBox(
                            width: 42,
                            child: Text(
                              _timeAgo(ts),
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[500]),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(width: 10),

                          // ── Icon bubble ────────────────────────────
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, color: color, size: 18),
                          ),
                          const SizedBox(width: 10),

                          // ── Title + detail + tap hint ──────────────
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.end,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.end,
                                  children: [
                                    // Badge pill
                                    if (badge.isNotEmpty) ...[
                                      Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2),
                                        decoration: BoxDecoration(
                                          color: color,
                                          borderRadius:
                                              BorderRadius.circular(5),
                                        ),
                                        child: Text(
                                          badge,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    Flexible(
                                      child: Text(
                                        title,
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          color: isHigh
                                              ? color
                                              : const Color(0xFF1E293B),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (detail.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    detail,
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600]),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                // Deep-link hint row
                                if (tappable) ...[
                                  const SizedBox(height: 5),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.end,
                                    children: [
                                      Icon(
                                        Icons.touch_app_rounded,
                                        size: 11,
                                        color: color.withValues(
                                            alpha: 0.65),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        type == 'new_dispute'
                                            ? 'עבור למחלוקות ←'
                                            : 'פתח פרופיל ←',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: color.withValues(
                                              alpha: 0.85),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pulsing green live-indicator dot
// ─────────────────────────────────────────────────────────────────────────────

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.25, end: 1.0).animate(_ctrl),
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF22C55E),
            shape: BoxShape.circle,
          ),
        ),
      );
}
