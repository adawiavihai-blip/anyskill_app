import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Live Activity Feed — Admin-only tab that streams the `activity_log`
/// collection in real-time so the admin can see platform activity as it
/// happens.
///
/// Each document is written by Cloud Functions when key events occur:
///   • New quick/job request     type: 'job_request'
///   • Job accepted (escrow)     type: 'job_accepted'
///   • New volunteer request     type: 'volunteer_request'
///   • New user registration     type: 'registration'
class LiveActivityTab extends StatelessWidget {
  const LiveActivityTab({super.key});

  // ── Type → icon / color ───────────────────────────────────────────────────
  static const Map<String, IconData> _icons = {
    'job_request':          Icons.bolt_rounded,
    'job_accepted':         Icons.handshake_rounded,
    'volunteer_request':    Icons.volunteer_activism_rounded,
    'registration':         Icons.person_add_alt_1_rounded,
    'broadcast':            Icons.campaign_rounded,
    'demo_booking_attempt': Icons.local_fire_department_rounded,
    'demo_contact':         Icons.smart_toy_rounded,
    'bypass_attempt':       Icons.shield_rounded,
  };

  static const Map<String, Color> _colors = {
    'job_request':          Color(0xFF6366F1),
    'job_accepted':         Color(0xFF10B981),
    'volunteer_request':    Color(0xFFF59E0B),
    'registration':         Color(0xFF3B82F6),
    'broadcast':            Color(0xFFEC4899),
    'demo_booking_attempt': Color(0xFFEF4444),
    'demo_contact':         Color(0xFF8B5CF6),
    'bypass_attempt':       Color(0xFFF97316),
  };

  // ── Time-ago helper ───────────────────────────────────────────────────────
  static String _timeAgo(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inSeconds < 60)  return 'עכשיו';
    if (diff.inMinutes < 60)  return 'לפני ${diff.inMinutes} דק\'';
    if (diff.inHours < 24)    return 'לפני ${diff.inHours} שע\'';
    return 'לפני ${diff.inDays} ימים';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        Container(
          color: const Color(0xFF0F172A),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF22C55E),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'לייב פיד — פעילות בזמן אמת',
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
                  final total =
                      snap.data?.docs.isEmpty == false ? '●' : '—';
                  return Text(total,
                      style: const TextStyle(
                          color: Color(0xFF22C55E), fontSize: 18));
                },
              ),
            ],
          ),
        ),

        // ── Feed ────────────────────────────────────────────────────────────
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('activity_log')
                .orderBy('createdAt', descending: true)
                .limit(100)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.radar_rounded,
                          size: 56, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      const Text('אין פעילות עדיין',
                          style: TextStyle(
                              color: Colors.grey, fontSize: 16)),
                      const SizedBox(height: 8),
                      const Text(
                        'הפעילות תופיע כאן בזמן אמת',
                        style:
                            TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final d        = docs[i].data()! as Map<String, dynamic>;
                  final type     = d['type']     as String? ?? '';
                  final title    = d['title']    as String? ?? type;
                  final detail   = d['detail']   as String? ?? '';
                  final ts       = d['createdAt'] as Timestamp?;
                  final priority = d['priority'] as String? ?? '';
                  final icon     = _icons[type]  ?? Icons.circle_outlined;
                  final color    = _colors[type] ?? Colors.grey;

                  final isDemo     = type == 'demo_booking_attempt';
                  final isBypass   = type == 'bypass_attempt';
                  final isHighPrio = priority == 'high' || isDemo || isBypass;

                  return Container(
                    decoration: BoxDecoration(
                      color: isDemo
                          ? const Color(0xFFFFF1F2) // red tint for demo
                          : isBypass
                              ? const Color(0xFFFFF7ED) // orange tint for bypass
                              : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isHighPrio
                            ? color.withValues(alpha: 0.35)
                            : Colors.grey.shade100,
                        width: isHighPrio ? 1.5 : 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isHighPrio
                              ? color.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.03),
                          blurRadius: isHighPrio ? 8 : 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Time (left)
                        Column(
                          children: [
                            Text(
                              _timeAgo(ts),
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[500]),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        // Icon
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: color, size: 18),
                        ),
                        const SizedBox(width: 12),
                        // Text + badge
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (isDemo) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEF4444),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'DEMO',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
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
                                        color: isHighPrio
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
                            ],
                          ),
                        ),
                      ],
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
