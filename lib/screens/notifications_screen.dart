import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../services/volunteer_service.dart';
import '../services/job_broadcast_service.dart';
import 'chat_screen.dart';
import 'provider_ai_insights_screen.dart';
import 'support/csat_survey_modal.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  bool _isClearing = false;   // prevents double-tap on "Clear All"

  late final Stream<QuerySnapshot> _stream;

  @override
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: _uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();

    // Mark all as read when the screen opens so the badge resets immediately
    WidgetsBinding.instance.addPostFrameCallback((_) => _markAllRead());
  }

  Future<void> _markAllRead() async {
    if (_uid.isEmpty) return;
    final unread = await FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: _uid)
        .where('isRead', isEqualTo: false)
        .get();
    if (unread.docs.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  Future<void> _markRead(String docId) async {
    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(docId)
        .update({'isRead': true});
  }

  /// Permanently deletes every notification document for the current user.
  /// The Firestore stream emits an empty list immediately, so the UI
  /// transitions to the empty state without any manual setState call.
  Future<void> _clearAll() async {
    if (_uid.isEmpty || _isClearing) return;
    setState(() => _isClearing = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: _uid)
          .limit(500)
          .get();
      if (snap.docs.isEmpty) return;
      // Firestore batches are capped at 500 operations — the limit(500) above
      // keeps us inside that ceiling for any realistic notification count.
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).notifGenericError(e.toString())),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  /// Marks the notification as read, then navigates to the relevant screen
  /// based on [type] or keywords in [title].
  void _handleTap(String docId, Map<String, dynamic> data) {
    _markRead(docId);
    final type = data['type'] as String? ?? 'general';
    final title = data['title'] as String? ?? '';
    _navigate(type, title, data);
  }

  void _navigate(String type, String title, Map<String, dynamic> data) {
    final titleLower = title.toLowerCase();
    final isAiNotif  = type == 'ai_insight' ||
        type == 'ai_suggestion' ||
        type == 'pro_granted'   ||
        titleLower.contains('ai') ||
        title.contains('בינה') ||
        title.contains('מצא דרך') ||
        title.contains('Pro');

    if (isAiNotif) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const ProviderAiInsightsScreen(),
        ),
      );
      return;
    }

    // ── Volunteer flow notifications ──────────────────────────────────────
    final relatedUserId = data['relatedUserId'] as String? ?? '';
    final category = data['category'] as String? ?? '';

    if (type == 'help_request' && relatedUserId.isNotEmpty) {
      // Volunteer received a help request → show accept sheet
      _showVolunteerAcceptSheet(relatedUserId, category);
      return;
    }

    if ((type == 'volunteer_accepted' || type == 'volunteer_completed')
        && relatedUserId.isNotEmpty) {
      // Open chat with the related user
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            receiverId: relatedUserId,
            receiverName: data['body'] as String? ?? '',
          ),
        ),
      );
      return;
    }

    // ── Broadcast urgent → show claim sheet ────────────────────────────────
    if (type == 'broadcast_urgent') {
      final broadcastId = data['broadcastId'] as String? ?? '';
      if (broadcastId.isNotEmpty) {
        _showBroadcastClaimSheet(broadcastId);
      }
      return;
    }

    // ── Broadcast claimed → open chat with provider ───────────────────────
    if (type == 'broadcast_claimed' && relatedUserId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            receiverId: relatedUserId,
            receiverName: '',
          ),
        ),
      );
      return;
    }

    // ── CSAT survey → show rating modal (v11.9.x) ─────────────────────────
    if (type == 'csat_survey') {
      // Notification's `data` field can contain the ticketId, OR (legacy)
      // it might be at the top level. Check both.
      final nestedData = data['data'] as Map<String, dynamic>? ?? {};
      final ticketId = (nestedData['ticketId'] as String?) ??
          (data['ticketId'] as String?) ??
          '';
      if (ticketId.isNotEmpty) {
        showCsatSurveyModal(context: context, ticketId: ticketId);
      }
      return;
    }
  }

  // ── Broadcast Claim Sheet ──────────────────────────────────────────────────

  void _showBroadcastClaimSheet(String broadcastId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StreamBuilder<DocumentSnapshot>(
        stream: JobBroadcastService.streamBroadcast(broadcastId),
        builder: (context, snap) {
          if (!snap.hasData || !snap.data!.exists) {
            return const SizedBox.shrink();
          }

          final d = snap.data!.data() as Map<String, dynamic>? ?? {};
          final status = d['status'] as String? ?? '';
          final category = d['category'] as String? ?? '';
          final description = d['description'] as String? ?? '';
          final l10n = AppLocalizations.of(context);
          final clientName = d['clientName'] as String? ?? l10n.notifDefaultClient;
          final isOpen = status == 'open';
          final isClaimed = status == 'claimed';
          final claimedByName = d['claimedByName'] as String? ?? '';

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 20),
                Icon(
                  isOpen ? Icons.bolt : isClaimed ? Icons.lock : Icons.timer_off,
                  color: isOpen
                      ? const Color(0xFFF97316)
                      : const Color(0xFF9CA3AF),
                  size: 36,
                ),
                const SizedBox(height: 12),
                Text(
                  isOpen ? l10n.notifUrgentJobAvailable : isClaimed ? l10n.notifJobTaken : l10n.notifJobExpired,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '$clientName • $category',
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF6B7280)),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(description,
                        textAlign: TextAlign.start,
                        style: const TextStyle(fontSize: 13, height: 1.5)),
                  ),
                ],
                const SizedBox(height: 20),
                if (isOpen)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.bolt, size: 18),
                      label: Text(l10n.notifGrabNow,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF97316),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        final nav = Navigator.of(ctx);
                        final messenger = ScaffoldMessenger.of(context);
                        nav.pop();
                        final result = await JobBroadcastService.claimJob(
                          broadcastId: broadcastId,
                          providerId: _uid,
                          providerName: '',
                        );
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(result.message),
                            backgroundColor: result.isSuccess
                                ? const Color(0xFF10B981)
                                : const Color(0xFFF59E0B),
                          ),
                        );
                        if (result.isSuccess && result.clientId != null) {
                          Navigator.push(
                            // ignore: use_build_context_synchronously
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                receiverId: result.clientId!,
                                receiverName: clientName,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  )
                else if (isClaimed)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      l10n.notifTakenBy(claimedByName),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 14, color: Color(0xFF6B7280)),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Volunteer Accept Sheet ──────────────────────────────────────────────

  void _showVolunteerAcceptSheet(String clientId, String category) async {
    // Fetch client info
    final clientDoc = await FirebaseFirestore.instance
        .collection('users').doc(clientId).get();
    final clientData = clientDoc.data() ?? {};
    final clientName = clientData['name'] as String? ?? AppLocalizations.of(context).notifDefaultClient;

    // Find the open help_request from this client in this category
    final helpSnap = await FirebaseFirestore.instance
        .collection('help_requests')
        .where('userId', isEqualTo: clientId)
        .where('category', isEqualTo: category)
        .where('status', isEqualTo: 'open')
        .limit(1)
        .get();

    final helpRequestId = helpSnap.docs.isNotEmpty ? helpSnap.docs.first.id : null;
    final description = helpSnap.docs.isNotEmpty
        ? (helpSnap.docs.first.data()['description'] as String? ?? '')
        : '';
    final clientLat = (clientData['latitude'] as num?)?.toDouble();
    final clientLng = (clientData['longitude'] as num?)?.toDouble();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.volunteer_activism,
                  color: Color(0xFF10B981), size: 28),
            ),
            const SizedBox(height: 16),
            Text(AppLocalizations.of(context).notifCommunityHelpTitle,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('$clientName צריך/ה עזרה בקטגוריית "$category"',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14)),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(description,
                    textAlign: TextAlign.start,
                    style: const TextStyle(fontSize: 13, height: 1.5)),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(AppLocalizations.of(context).notifNotNow),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle, size: 18),
                    label: Text(AppLocalizations.of(context).notifWantToHelp,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final taskId = await VolunteerService.createTask(
                        clientId: clientId,
                        providerId: _uid,
                        category: category,
                        description: description,
                        helpRequestId: helpRequestId,
                        clientLat: clientLat,
                        clientLng: clientLng,
                      );
                      if (!mounted) return;
                      if (taskId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(AppLocalizations.of(context).notifCantAccept),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(AppLocalizations.of(context).notifAccepted),
                          backgroundColor: Colors.green,
                        ),
                      );
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            receiverId: clientId,
                            receiverName: clientName,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).notificationsTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          _isClearing
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : TextButton(
                  onPressed: _clearAll,
                  child: Text(AppLocalizations.of(context).notifClearAll,
                      style: const TextStyle(
                          color: Colors.red, fontWeight: FontWeight.w600)),
                ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(AppLocalizations.of(context).notifLoadError, style: TextStyle(color: Colors.grey[600])),
              ],
            ));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmpty();
          }

          final docs = snapshot.data!.docs;
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final n = doc.data() as Map<String, dynamic>;
              final isRead = n['isRead'] ?? false;
              final title = n['title'] ?? '';
              final body = n['body'] ?? '';
              final type = n['type'] ?? 'general';
              final ts = (n['createdAt'] as Timestamp?)?.toDate();

              return InkWell(
                onTap: () => _handleTap(doc.id, n),
                child: Container(
                  color: isRead ? Colors.white : Colors.blue.shade50,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _NotifIcon(type: type),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    style: TextStyle(
                                      fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                if (!isRead)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Colors.blue,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              body,
                              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (ts != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _formatTime(ts),
                                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
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
    );
  }

  String _formatTime(DateTime dt) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return l10n.timeNow;
    if (diff.inMinutes < 60) return l10n.timeMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n.timeHoursAgo(diff.inHours);
    return DateFormat('dd/MM HH:mm').format(dt);
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/NEW_LOGO1.png.png',
            width: 140,
            height: 140,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
              child: Icon(Icons.notifications_none_outlined, size: 56, color: Colors.grey[400]),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            AppLocalizations.of(context).notifEmptyNow,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotifIcon extends StatelessWidget {
  final String type;
  const _NotifIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (type) {
      'new_booking'   => (Icons.calendar_today_rounded,    Colors.purple),
      'job_status'    => (Icons.check_circle_outline,      Colors.green),
      'chat'          => (Icons.chat_bubble_outline,       Colors.blue),
      'interest'      => (Icons.flash_on_rounded,          Colors.orange),
      'verified'      => (Icons.verified_rounded,          Colors.blue),
      'review'        => (Icons.star_rounded,              const Color(0xFFF59E0B)),
      'vip_expiry'    => (Icons.workspace_premium_rounded, const Color(0xFFD97706)),
      'payment'       => (Icons.account_balance_wallet,    Colors.green),
      'ai_insight'    => (Icons.auto_awesome_rounded,        const Color(0xFF6366F1)),
      'ai_suggestion' => (Icons.auto_awesome_rounded,        const Color(0xFF6366F1)),
      'pro_granted'   => (Icons.workspace_premium_rounded,   const Color(0xFFFBBF24)),
      _               => (Icons.notifications_outlined,      Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

// ── Static helper: stream unread count for a given uid ─────────────────────
class NotificationBadge extends StatelessWidget {
  final Widget child;
  const NotificationBadge({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: uid)
          .where('isRead', isEqualTo: false)
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return Badge(
          label: Text(count.toString()),
          isLabelVisible: count > 0,
          child: child,
        );
      },
    );
  }
}
