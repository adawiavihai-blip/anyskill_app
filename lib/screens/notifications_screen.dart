import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../services/cached_readers.dart';
import '../services/notification_router.dart';
import '../services/volunteer_service.dart';
import '../services/job_broadcast_service.dart';
import 'chat_screen.dart';
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

  /// §15 Law 15 supervisor — the snapshot stream can stall on iOS Safari
  /// WebChannel zombies and never deliver a first event. After 8s with no
  /// data we flip this flag so the build path falls through to an empty
  /// state with a retry CTA instead of the indefinite spinner that users
  /// reported as "bell opens, gets stuck forever".
  bool _streamTimedOut = false;
  bool _streamResolved = false;
  /// One-shot `.get()` fallback fired 1s after open if the snapshot stream
  /// hasn't emitted yet. Lets the screen render REAL notifications even
  /// when the stream is slow — the live stream wins when it eventually
  /// fires (real-time updates).
  List<QueryDocumentSnapshot>? _fallbackDocs;

  @override
  void initState() {
    super.initState();
    // IMPORTANT: do NOT wrap the snapshot stream in `.timeout()` —
    // Stream.timeout() puts the stream into a permanent error state
    // when it fires, so even when the connection recovers the user
    // stays stuck on the error screen. This was the "bell stuck"
    // root cause: the 8s Stream.timeout() fired before the first
    // snapshot arrived on slow connections, the StreamBuilder went
    // to hasError, and subsequent snapshot events couldn't unstick
    // it. Replaced with a manual supervisor + .get() fallback below.
    _stream = FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: _uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();

    // ⚠️ DO NOT add a second `_stream.listen()` probe here.
    //
    // Root cause of the recurring "bell opens empty / stuck on spinner"
    // bug (fixed 2026-05-16): a Firestore `.snapshots()` stream is a
    // BROADCAST stream. A probe `.listen()` here AND the `StreamBuilder`
    // in build() are two independent subscribers. Broadcast streams do
    // NOT replay past events to a late subscriber — so if the probe
    // received the first snapshot before the StreamBuilder subscribed,
    // the StreamBuilder missed it permanently. Worse, the probe set
    // `_streamResolved = true`, which SUPPRESSED the `.get()` fallback
    // below — leaving the bell on an infinite spinner with no recovery
    // until a notification doc happened to change.
    //
    // `_streamResolved` is now set from INSIDE the StreamBuilder builder
    // (the one and only subscriber), so it reflects what is actually
    // on screen — see build().

    // §15 Law 15 supervisors — timeouts bumped after live user reports
    // (רועי צברי, 2026-05-14) that the bell tap was showing "stuck
    // spinner" → retry scaffold on a working internet connection. The
    // previous 8s Tier-2 was firing on legitimate cold-start handshakes.
    if (_uid.isNotEmpty) {
      Future<void> kickFallback(Duration getTimeout) async {
        if (!mounted || _streamResolved) return;
        try {
          final snap = await FirebaseFirestore.instance
              .collection('notifications')
              .where('userId', isEqualTo: _uid)
              .orderBy('createdAt', descending: true)
              .limit(50)
              .get()
              .timeout(getTimeout);
          if (!mounted || _streamResolved) return;
          setState(() => _fallbackDocs = snap.docs);
        } catch (_) {/* next tier retries */}
      }

      // Tier 1 (2s) — first .get() fallback attempt.
      Future.delayed(const Duration(seconds: 2),
          () => kickFallback(const Duration(seconds: 6)));
      // Tier 1.5 (10s) — silent auto-retry, no UI noise.
      Future.delayed(const Duration(seconds: 10), () {
        if (!mounted || _streamResolved || _fallbackDocs != null) return;
        kickFallback(const Duration(seconds: 8));
      });
      // Tier 2 (25s) — only after this much patience do we surface the
      // retry scaffold. Until then we keep the spinner so the user
      // doesn't get a false-positive "בעיית חיבור" warning.
      Future.delayed(const Duration(seconds: 25), () {
        if (!mounted || _streamResolved) return;
        if (_fallbackDocs != null) return;
        setState(() => _streamTimedOut = true);
      });
    }

    // Mark all as read when the screen opens so the badge resets immediately
    WidgetsBinding.instance.addPostFrameCallback((_) => _markAllRead());
  }

  /// User-initiated retry — resets supervisor flags + re-fires the .get()
  /// fallback so the next attempt actually retries instead of immediately
  /// re-tripping the timeout flag.
  Future<void> _retry() async {
    if (!mounted) return;
    setState(() {
      _streamTimedOut = false;
      _fallbackDocs = null;
    });
    // Re-arm Tier 2 supervisor (8s).
    Future.delayed(const Duration(seconds: 8), () {
      if (!mounted || _streamResolved) return;
      if (_fallbackDocs != null) return;
      setState(() => _streamTimedOut = true);
    });
    if (_uid.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: _uid)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get()
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      setState(() => _fallbackDocs = snap.docs);
    } catch (_) {/* timeout flag will eventually fire */}
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

  Future<void> _navigate(
      String type, String title, Map<String, dynamic> data) async {
    // Legacy heuristic: older notifications sometimes only had a Hebrew
    // title and no explicit type for AI insights. Normalize to 'ai_insight'
    // so the router recognises them.
    final titleLower = title.toLowerCase();
    final looksLikeAi = titleLower.contains('ai') ||
        title.contains('בינה') ||
        title.contains('מצא דרך') ||
        title.contains('Pro');
    final effectiveType = (type == 'general' && looksLikeAi)
        ? 'ai_insight'
        : type;
    final payload =
        Map<String, dynamic>.from(data)..['type'] = effectiveType;

    // ── Screen-local modals (router returns false for these) ─────────────
    // Broadcast claim sheet + volunteer accept sheet + CSAT modal all need
    // this screen's services (JobBroadcastService, VolunteerService, the
    // local BuildContext) — keep them here, not in the router.
    if (effectiveType == 'broadcast_urgent') {
      final broadcastId = _readField(data, ['broadcastId']);
      if (broadcastId != null && broadcastId.isNotEmpty) {
        _showBroadcastClaimSheet(broadcastId);
      }
      return;
    }
    if (effectiveType == 'help_request') {
      final relatedUserId =
          _readField(data, ['relatedUserId', 'senderId']) ?? '';
      final category = _readField(data, ['category']) ?? '';
      if (relatedUserId.isNotEmpty) {
        _showVolunteerAcceptSheet(relatedUserId, category);
      }
      return;
    }
    if (effectiveType == 'csat_survey') {
      final ticketId = _readField(data, ['ticketId']) ?? '';
      if (ticketId.isNotEmpty) {
        showCsatSurveyModal(context: context, ticketId: ticketId);
      }
      return;
    }

    // ── Everything else → shared smart router ────────────────────────────
    final handled = await NotificationRouter.route(context, payload);
    if (!handled && mounted) {
      // Unknown type — show a gentle toast so the user knows the tap did
      // something (vs silent no-op which feels broken).
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ההתראה נפתחה. ניתן לחזור מאוחר יותר.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Reads a field from EITHER the top level OR the nested `data` map —
  /// same semantics as NotificationRouter._extractField, but local here
  /// so the 3 modal branches above don't depend on the router.
  String? _readField(Map<String, dynamic> raw, List<String> keys) {
    for (final k in keys) {
      final v = raw[k];
      if (v is String && v.isNotEmpty) return v;
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    final nested = raw['data'];
    if (nested is Map) {
      for (final k in keys) {
        final v = nested[k];
        if (v is String && v.isNotEmpty) return v;
        if (v != null && v.toString().isNotEmpty) return v.toString();
      }
    }
    return null;
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
    // Capture localized strings BEFORE async gaps (Section 9 async-safe pattern)
    final defaultClientName = AppLocalizations.of(context).notifDefaultClient;
    // §66: cached read — 5min TTL via §61. Notification taps for the
    // same client (multiple urgent broadcasts during a busy hour) reuse
    // the same fetch instead of paying network round-trip per tap.
    final clientData = await CachedReaders.providerProfile(clientId);
    final clientName = clientData['name'] as String? ?? defaultClientName;

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
          // ── §15 Law 15 supervisor — resolution logic ────────────────
          // The StreamBuilder is the SOLE subscriber to `_stream`. The
          // first time it actually receives data we record
          // `_streamResolved` (post-frame — setState is illegal during
          // build). The `.get()` fallback timers read this flag; keeping
          // it driven by the real renderer (not a separate probe
          // listener) is what fixes the "bell opens empty" race.
          if (snapshot.hasData && !_streamResolved) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_streamResolved) {
                setState(() => _streamResolved = true);
              }
            });
          }

          // Branch priority:
          //   1. live stream data        → render it (real-time path)
          //   2. `.get()` fallback docs  → render them (stream stalled
          //      OR errored, but the one-shot read still succeeded)
          //   3. stream error / timeout  → retry scaffold
          //   4. otherwise (early)       → spinner
          final List<QueryDocumentSnapshot> docs;
          if (snapshot.hasData) {
            docs = snapshot.data!.docs;
          } else if (_fallbackDocs != null) {
            // `.get()` fallback delivered REAL notifications even though
            // the live stream stalled or errored — render them so the
            // bell is never stuck on a spinner with data available.
            docs = _fallbackDocs!;
          } else if (snapshot.hasError || _streamTimedOut) {
            return _buildRetryScaffold(context);
          } else {
            return const Center(child: CircularProgressIndicator());
          }

          if (docs.isEmpty) {
            return _buildEmpty();
          }
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
    return DateFormat('dd/MM HH:mm', 'he').format(dt);
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

  /// §15 Law 15 retry scaffold — shown when the snapshot stream errored
  /// OR the 8s Tier-2 supervisor timed out before any data arrived.
  /// Tap "נסה שוב" → `_retry()` re-fires the .get() fallback and re-arms
  /// the timeout flag, so the user can recover without leaving the
  /// screen.
  Widget _buildRetryScaffold(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Color(0xFFFEE2E2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wifi_off_rounded,
                  size: 48, color: Color(0xFFEF4444)),
            ),
            const SizedBox(height: 20),
            const Text('בעיית חיבור',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('לא הצלחנו לטעון את ההתראות. נסה שוב.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('נסה שוב',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _retry,
            ),
          ],
        ),
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
