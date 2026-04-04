/// AnySkill — Admin Support Inbox Tab (תיבת פניות)
///
/// Lists open support tickets sorted by date. Admins can:
///   - See ticket details (user, category, subject, age)
///   - Open ticket chat to reply
///   - Change status (open/in_progress/resolved)
///   - One-click XP compensation or refund
library;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'support_center_screen.dart';
import '../utils/safe_image_provider.dart';

class AdminSupportInboxTab extends StatelessWidget {
  const AdminSupportInboxTab({super.key});

  static final _db = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          // ── Status filter tabs ──────────────────────────────────────────
          const TabBar(
            labelColor: Color(0xFF6366F1),
            indicatorColor: Color(0xFF6366F1),
            tabs: [
              Tab(text: 'פתוחות'),
              Tab(text: 'בטיפול'),
              Tab(text: 'נפתרו'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildTicketList('open'),
                _buildTicketList('in_progress'),
                _buildTicketList('resolved'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketList(String status) {
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('support_tickets')
          .where('status', isEqualTo: status)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  status == 'resolved'
                      ? Icons.check_circle_outline
                      : Icons.inbox_rounded,
                  size: 48,
                  color: const Color(0xFFD1D5DB),
                ),
                const SizedBox(height: 12),
                Text(
                  status == 'resolved'
                      ? 'אין פניות שנפתרו'
                      : 'אין פניות פתוחות',
                  style: const TextStyle(
                      color: Color(0xFF9CA3AF), fontSize: 14),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final doc = docs[i];
            final d = doc.data() as Map<String, dynamic>? ?? {};
            return _TicketCard(ticketId: doc.id, data: d);
          },
        );
      },
    );
  }
}

class _TicketCard extends StatefulWidget {
  final String ticketId;
  final Map<String, dynamic> data;

  const _TicketCard({required this.ticketId, required this.data});

  @override
  State<_TicketCard> createState() => _TicketCardState();
}

class _TicketCardState extends State<_TicketCard> {
  Map<String, dynamic>? _userProfile;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final userId = widget.data['userId'] as String? ?? '';
    if (userId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      if (mounted && doc.exists) {
        setState(() => _userProfile = doc.data());
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final ticketId = widget.ticketId;
    final resolvedName = _userProfile?['name'] as String? ??
        data['userName'] as String? ?? 'משתמש';
    final userName = resolvedName;
    final profileImg = _userProfile?['profileImage'] as String?;
    final phone = _userProfile?['phone'] as String? ?? '';
    final email = _userProfile?['email'] as String? ?? '';
    final category = data['category'] as String? ?? '';
    final subject = data['subject'] as String? ?? '';
    final status = data['status'] as String? ?? 'open';
    final jobId = data['jobId'] as String?;
    final createdAt = data['createdAt'] as Timestamp?;

    String ageLabel = '';
    if (createdAt != null) {
      final diff = DateTime.now().difference(createdAt.toDate());
      if (diff.inMinutes < 60) {
        ageLabel = 'לפני ${diff.inMinutes} דק\'';
      } else if (diff.inHours < 24) {
        ageLabel = 'לפני ${diff.inHours} שעות';
      } else {
        ageLabel = DateFormat('dd/MM HH:mm').format(createdAt.toDate());
      }
    }

    final categoryLabels = {
      'payments': ('תשלומים', const Color(0xFF6366F1)),
      'volunteer': ('התנדבות', const Color(0xFF10B981)),
      'account': ('חשבון', const Color(0xFF8B5CF6)),
      'other': ('אחר', const Color(0xFFF59E0B)),
    };
    final (catLabel, catColor) =
        categoryLabels[category] ?? (category, Colors.grey);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TicketChatScreen(
            ticketId: ticketId,
            category: category,
            isAdmin: true,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: status == 'open'
                ? const Color(0xFFF59E0B).withValues(alpha: 0.3)
                : const Color(0xFFE5E7EB),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ────────────────────────────────────────────
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      const Color(0xFF6366F1).withValues(alpha: 0.1),
                  backgroundImage: safeImageProvider(profileImg),
                  child: safeImageProvider(profileImg) == null
                      ? Text(
                          userName.isNotEmpty ? userName[0] : '?',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF6366F1),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      if (phone.isNotEmpty || email.isNotEmpty)
                        Text(
                          phone.isNotEmpty ? phone : email,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF6366F1)),
                        )
                      else
                        Text(
                          ageLabel,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF9CA3AF)),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    catLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: catColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Subject ───────────────────────────────────────────────
            Text(
              subject,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF4B5563),
                height: 1.4,
              ),
            ),

            // ── Job link ──────────────────────────────────────────────
            if (jobId != null && jobId.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.link, size: 14, color: Color(0xFF9CA3AF)),
                  const SizedBox(width: 4),
                  Text(
                    'הזמנה #${jobId.substring(0, 8)}',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            ],

            // ── Footer: status + reply arrow ──────────────────────────
            const SizedBox(height: 8),
            Row(
              children: [
                _statusChip(status),
                const Spacer(),
                const Icon(Icons.arrow_back_ios,
                    size: 14, color: Color(0xFF6366F1)),
                const SizedBox(width: 4),
                const Text(
                  'פתח צ\'אט',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6366F1),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final (label, color) = switch (status) {
      'open'        => ('פתוח', const Color(0xFFF59E0B)),
      'in_progress' => ('בטיפול', const Color(0xFF6366F1)),
      'resolved'    => ('נפתר', const Color(0xFF10B981)),
      _             => (status, Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
