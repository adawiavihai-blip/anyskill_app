// ignore_for_file: use_build_context_synchronously
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/skeleton_loader.dart';

import 'chat_modules/location_module.dart';
import 'chat_modules/image_module.dart';
import 'chat_modules/payment_module.dart';
import 'chat_modules/chat_ui_helper.dart';
import 'chat_modules/chat_logic_module.dart';
import 'chat_modules/safety_module.dart';
import 'chat_modules/chat_stream_module.dart';
import 'expert_profile_screen.dart';
import '../l10n/app_localizations.dart';
import '../services/chat_guard_service.dart';
import '../widgets/anyskill_logo.dart';

class ChatScreen extends StatefulWidget {
  final String receiverId;
  final String receiverName;
  final String? currentUserName;

  final String? initialMessage;

  const ChatScreen({
    super.key,
    required this.receiverId,
    required this.receiverName,
    this.currentUserName,
    this.initialMessage,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgCtrl    = TextEditingController();
  final ScrollController       _scrollCtrl = ScrollController();

  final String currentUserId =
      FirebaseAuth.instance.currentUser?.uid ?? '';

  late final String chatRoomId;

  bool   _isUploading        = false;
  bool   _isReceiverTyping   = false;

  // ── Chat Guard state ──────────────────────────────────────────────────────
  bool      _guardFlagged      = false;   // true while current input is flagged
  bool      _showGuardBanner   = true;    // dismissible anti-bypass info banner
  int       _bypassAttempts    = 0;       // counts flagged sends this session
  DateTime? _lastGuardWarnTime;           // prevents SnackBar spam
  Timer?    _guardDebounce;               // delays detection until typing pauses

  // ── Demo Expert alert (fired once per session) ─────────────────────────────

  Timer? _markReadDebounce;
  Timer? _typingClearTimer;
  StreamSubscription<DocumentSnapshot>? _chatDocSub;

  @override
  void initState() {
    super.initState();
    final ids = [currentUserId, widget.receiverId]..sort();
    chatRoomId = ids.join('_');

    // Reset unread badge immediately
    FirebaseFirestore.instance
        .collection('chats')
        .doc(chatRoomId)
        .update({'unreadCount_$currentUserId': 0})
        .catchError((_) {});

    _handleMarkAsRead();
    _listenToTyping();
    _checkDemoExpert();
    if (widget.initialMessage?.isNotEmpty == true) {
      _msgCtrl.text = widget.initialMessage!;
    }
  }

  /// One-time check: if the receiver is a demo expert, log a high-priority
  /// alert to the admin Activity Log so demand in this category is surfaced.
  Future<void> _checkDemoExpert() async {
    if (currentUserId.isEmpty || widget.receiverId.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.receiverId)
          .get();
      final d = snap.data() ?? {};
      if (d['isDemo'] != true) return;

      // Deduplicate: don't log if already logged today for this pair
      final dedupId = 'demo_${currentUserId}_${widget.receiverId}';
      final existing = await FirebaseFirestore.instance
          .collection('activity_log')
          .doc(dedupId)
          .get();
      if (existing.exists) return;

      final category = d['serviceType'] as String? ?? d['name'] as String? ?? 'לא ידוע';
      await FirebaseFirestore.instance
          .collection('activity_log')
          .doc(dedupId)
          .set({
        'type':       'demo_contact',
        'priority':   'high',
        'title':      '🔥 ביקוש אמיתי! משתמש פנה למומחה דמו',
        'detail':
            'משתמש (${widget.currentUserName ?? currentUserId}) ניסה לפנות '
            'למומחה דמו בקטגוריה "$category" — שקול לגייס ספק אמיתי בתחום זה!',
        'userId':     currentUserId,
        'receiverId': widget.receiverId,
        'category':   category,
        'createdAt':  FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Non-fatal — don't interrupt the chat UX
    }
  }

  @override
  void dispose() {
    _markReadDebounce?.cancel();
    _typingClearTimer?.cancel();
    _guardDebounce?.cancel();
    _chatDocSub?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    // Clear own typing indicator on exit
    FirebaseFirestore.instance
        .collection('chats')
        .doc(chatRoomId)
        .set({'isTyping_$currentUserId': false}, SetOptions(merge: true))
        .catchError((_) {});
    super.dispose();
  }

  // ── Typing indicator logic ────────────────────────────────────────────────

  void _listenToTyping() {
    _chatDocSub = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatRoomId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final d      = snap.data() ?? {};
      final typing = d['isTyping_${widget.receiverId}'] as bool? ?? false;
      if (typing != _isReceiverTyping) {
        setState(() => _isReceiverTyping = typing);
      }
    });
  }

  void _onTypingChanged(String text) {
    final isTyping = text.isNotEmpty;
    FirebaseFirestore.instance
        .collection('chats')
        .doc(chatRoomId)
        .set({'isTyping_$currentUserId': isTyping}, SetOptions(merge: true))
        .catchError((_) {});

    _typingClearTimer?.cancel();
    if (isTyping) {
      _typingClearTimer = Timer(const Duration(seconds: 3), () {
        FirebaseFirestore.instance
            .collection('chats')
            .doc(chatRoomId)
            .set({'isTyping_$currentUserId': false}, SetOptions(merge: true))
            .catchError((_) {});
      });
    }
  }

  // ── Chat Guard — real-time detection ─────────────────────────────────────

  /// Called on every keystroke.  Debounced 500 ms to avoid mid-word false
  /// positives (e.g. partial phone numbers while still typing).
  void _checkChatGuard(String text) {
    _guardDebounce?.cancel();
    if (text.isEmpty) {
      if (_guardFlagged) setState(() => _guardFlagged = false);
      return;
    }
    _guardDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final result = ChatGuardService.check(text);
      // Update border highlight
      if (result.isFlagged != _guardFlagged) {
        setState(() => _guardFlagged = result.isFlagged);
      }
      // Show SnackBar at most once every 6 seconds (prevents spam)
      if (result.isFlagged) {
        final now = DateTime.now();
        final lastWarn = _lastGuardWarnTime;
        if (lastWarn == null ||
            now.difference(lastWarn).inSeconds >= 6) {
          _lastGuardWarnTime = now;
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.security_rounded,
                        color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'שימו לב: למען ביטחונכם, אין להחליף מספרי טלפון '
                        'או לסגור עסקאות מחוץ לאפליקציה.',
                        style: TextStyle(fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
                backgroundColor: const Color(0xFFDC2626),
                behavior:        SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                duration: const Duration(seconds: 5),
              ),
            );
        }
      }
    });
  }

  // ── Messaging ─────────────────────────────────────────────────────────────

  void _handleMarkAsRead() {
    _markReadDebounce?.cancel();
    _markReadDebounce = Timer(const Duration(seconds: 1), () {
      ChatLogicModule.markMessagesAsRead(chatRoomId, currentUserId);
    });
  }

  Future<void> _send(String content, String type) async {
    if (!await SafetyModule.hasInternet()) {
      if (mounted) SafetyModule.showError(context, 'אין חיבור לאינטרנט.');
      return;
    }
    ChatLogicModule.sendMessage(
      chatRoomId: chatRoomId,
      senderId:   currentUserId,
      receiverId: widget.receiverId,
      content:    content,
      type:       type,
    );
  }

  Future<void> _sendPaymentRequest(
      double amount, String description) async {
    if (!await SafetyModule.hasInternet()) {
      if (mounted) SafetyModule.showError(context, 'אין חיבור לאינטרנט.');
      return;
    }
    final db  = FirebaseFirestore.instance;
    final batch = db.batch();

    final msgRef = db
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .doc();
    batch.set(msgRef, {
      'senderId':   currentUserId,
      'receiverId': widget.receiverId,
      'message':    description,
      'amount':     amount,
      'type':       'payment_request',
      'isRead':     false,
      'timestamp':  FieldValue.serverTimestamp(),
    });

    final chatRef = db.collection('chats').doc(chatRoomId);
    batch.set(chatRef, {
      'users':           [currentUserId, widget.receiverId],
      'lastMessage':     'בקשת תשלום ₪${amount.toInt()}',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unreadCount_${widget.receiverId}': FieldValue.increment(1),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  Future<String> _currentUserName() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .get();
      final name = (doc.data() ?? {})['name'] as String? ?? '';
      if (name.isNotEmpty) return name;
    } catch (_) {}
    return widget.currentUserName ?? 'לקוח';
  }

  // ── Request payment dialog ─────────────────────────────────────────────────

  void _showRequestPaymentDialog() {
    final amountCtrl = TextEditingController();
    final descCtrl   = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.payments_rounded, color: Color(0xFFF59E0B)),
          SizedBox(width: 8),
          Text('בקשת תשלום',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                labelText: 'סכום',
                prefixText: '₪ ',
                filled: true,
                fillColor: const Color(0xFFF5F6FA),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                labelText: 'תיאור השירות',
                filled: true,
                fillColor: const Color(0xFFF5F6FA),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(context).cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final amount = double.tryParse(
                      amountCtrl.text.replaceAll(',', '.')) ??
                  0;
              if (amount <= 0) return;
              Navigator.pop(ctx);
              _sendPaymentRequest(
                amount,
                descCtrl.text.isEmpty ? 'בקשת תשלום' : descCtrl.text,
              );
            },
            child: const Text('שלח',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F8),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildSafetyBanner(),
          _buildGuardBanner(),
          _buildJobStatusBanner(),
          Expanded(child: _buildMessagesList()),
          if (_isReceiverTyping) _buildTypingBubble(),
          _buildQuickActions(),
          _buildInputArea(),
        ],
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    // Stream for online status — shared by title + subtitle
    final userStream = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.receiverId)
        .snapshots();

    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
      titleSpacing: 0,
      title: Row(
        children: [
          // Avatar with live online dot
          StreamBuilder<DocumentSnapshot>(
            stream: userStream,
            builder: (_, snap) {
              final d        = snap.data?.data() as Map<String, dynamic>? ?? {};
              final isOnline = d['isOnline'] as bool? ?? false;
              final photo    = d['profileImage'] as String? ?? '';

              return Stack(children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: const Color(0xFFEDE9FE),
                  backgroundImage: photo.isNotEmpty
                      ? CachedNetworkImageProvider(photo)
                      : null,
                  child: photo.isEmpty
                      ? Text(
                          widget.receiverName.isNotEmpty
                              ? widget.receiverName[0]
                              : '?',
                          style: const TextStyle(
                              color: Color(0xFF6366F1),
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: isOnline ? Colors.green : Colors.grey[300],
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ]);
            },
          ),

          const SizedBox(width: 10),

          // Name + last-seen subtitle
          StreamBuilder<DocumentSnapshot>(
            stream: userStream,
            builder: (_, snap) {
              final d        = snap.data?.data() as Map<String, dynamic>? ?? {};
              final isOnline = d['isOnline']  as bool?      ?? false;
              final lastSeen = d['lastSeen']  as Timestamp?;
              final subtitle = isOnline
                  ? 'מחובר עכשיו'
                  : _lastSeenLabel(lastSeen);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.receiverName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(
                    subtitle,
                    style: TextStyle(
                        fontSize: 11,
                        color: isOnline ? Colors.green : Colors.grey[400]),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: Colors.grey.shade100),
      ),
    );
  }

  String _lastSeenLabel(Timestamp? ts) {
    if (ts == null) return 'לא פעיל';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 5)  return 'נראה לאחרונה הרגע';
    if (diff.inHours  < 1)   return "נראה לפני ${diff.inMinutes} דק'";
    if (diff.inHours  < 24)  return "נראה לפני ${diff.inHours} שע'";
    return "נראה לפני ${diff.inDays} ימים";
  }

  // ── Safety banner ─────────────────────────────────────────────────────────

  Widget _buildSafetyBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FFF4),
        border: Border(
            bottom: BorderSide(
                color: const Color(0xFF22C55E).withValues(alpha: 0.20))),
      ),
      child: Row(children: [
        const Icon(Icons.shield_rounded,
            size: 13, color: Color(0xFF16A34A)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'התשלום שלך מוגן על ידי AnySkill עד לאישורך על סיום העבודה',
            style: TextStyle(
                fontSize: 11,
                color: Colors.green[700],
                fontWeight: FontWeight.w500),
          ),
        ),
      ]),
    );
  }

  // ── Anti-bypass info banner — dismissible amber strip ────────────────────

  Widget _buildGuardBanner() {
    if (!_showGuardBanner) return const SizedBox.shrink();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border(
          bottom: BorderSide(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.30)),
          right: const BorderSide(color: Color(0xFFF59E0B), width: 3),
        ),
      ),
      child: Row(
        children: [
          // Dismiss
          GestureDetector(
            onTap: () => setState(() => _showGuardBanner = false),
            child: Icon(Icons.close_rounded,
                size: 14, color: Colors.amber[700]),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.lock_rounded,
              size: 13, color: Color(0xFFD97706)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'שמירה על התשלום בתוך AnySkill מבטיחה לכם ביטוח והגנה על העבודה',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 11,
                  color:    Colors.amber[800],
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  // ── Job status banner (existing logic, premium visual) ───────────────────

  Widget _buildJobStatusBanner() {
    return StreamBuilder<QuerySnapshot>(
      stream: ChatStreamModule.getJobStatusStream(chatRoomId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final jobDoc  = snapshot.data!.docs.first;
        final jobData = jobDoc.data() as Map<String, dynamic>;
        final status  = jobData['status'] as String? ?? '';

        if (status == 'completed') return const SizedBox.shrink();

        final isExpert = jobData['expertId'] == currentUserId;

        if (isExpert && status == 'paid_escrow') {
          return _StatusBanner(
            color:       const Color(0xFFFFFBEB),
            borderColor: const Color(0xFFF59E0B),
            icon:        Icons.lock_clock_rounded,
            iconColor:   const Color(0xFFD97706),
            text:        'התשלום מוגן בנאמנות — סמן כשתסיים',
            buttonText:  'סיימתי ✅',
            buttonColor: Colors.green,
            onTap: () async {
              await FirebaseFirestore.instance
                  .collection('jobs')
                  .doc(jobDoc.id)
                  .update({
                'status':            'expert_completed',
                'expertCompletedAt': FieldValue.serverTimestamp(),
              });
              await FirebaseFirestore.instance
                  .collection('chats')
                  .doc(chatRoomId)
                  .collection('messages')
                  .add({
                'senderId':  'system',
                'message':   '✅ המומחה סיים את העבודה! לחץ על "אשר ושחרר" כדי לשחרר את התשלום.',
                'type':      'text',
                'timestamp': FieldValue.serverTimestamp(),
              });
            },
          );
        }

        if (!isExpert && status == 'expert_completed') {
          return _StatusBanner(
            color:       const Color(0xFFF0FFF4),
            borderColor: const Color(0xFF22C55E),
            icon:        Icons.check_circle_rounded,
            iconColor:   const Color(0xFF16A34A),
            text:        'המומחה סיים! אשר לשחרור התשלום.',
            buttonText:  'אשר ושחרר 💚',
            buttonColor: const Color(0xFF16A34A),
            onTap: () async {
              // Capture the dialog's own context so we always pop exactly
              // this route — not a parent route that may have changed.
              BuildContext? loadingCtx;

              void hideLoading() {
                debugPrint('QA: Dismissing loading dialog');
                final ctx = loadingCtx;
                loadingCtx = null;
                if (ctx != null && ctx.mounted && Navigator.canPop(ctx)) {
                  Navigator.of(ctx).pop();
                }
              }

              debugPrint('QA: Opening loading dialog');
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (ctx) {
                  loadingCtx = ctx;
                  return const PopScope(
                    canPop: false,
                    child: Center(
                      child: Material(
                        color: Colors.transparent,
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                  );
                },
              );

              String? error;
              try {
                final realName = await _currentUserName();
                error = await PaymentModule.releaseEscrowFundsWithError(
                  jobId:        jobDoc.id,
                  expertId:     jobData['expertId'] ?? widget.receiverId,
                  expertName:   widget.receiverName,
                  customerName: realName,
                  totalAmount:  (jobData['totalAmount'] ??
                          jobData['totalPaidByCustomer'] ??
                          0.0)
                      .toDouble(),
                );

                // Safety: verify Firestore actually shows 'completed' before
                // showing success. Guards against stream-update race conditions.
                if (error == null) {
                  final snap = await FirebaseFirestore.instance
                      .collection('jobs')
                      .doc(jobDoc.id)
                      .get();
                  final confirmedStatus =
                      (snap.data() ?? {})['status'] as String? ?? '';
                  debugPrint('QA: Firestore job status after release = $confirmedStatus');
                  if (confirmedStatus != 'completed') {
                    error = 'הסטטוס לא עודכן — נסה שוב (status: $confirmedStatus)';
                  }
                }
              } catch (e) {
                debugPrint('QA: Unexpected error in releaseEscrow: $e');
                error = e.toString();
              } finally {
                hideLoading();
              }

              if (!context.mounted) return;

              if (error == null) {
                showDialog(
                  context: context,
                  builder: (c) => AlertDialog(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72, height: 72,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(14),
                            child: AnySkillBrandIcon(size: 44),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('התשלום שוחרר בהצלחה! 🎉',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('הכסף הועבר למומחה.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Color(0xFF64748B), fontSize: 13)),
                        const SizedBox(height: 20),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('סגור',
                            style: TextStyle(color: Color(0xFF6366F1))),
                      ),
                    ],
                  ),
                );
              } else {
                showDialog(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('שגיאה בשחרור התשלום'),
                    content: SelectableText(error!),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: Text(AppLocalizations.of(context).close)),
                    ],
                  ),
                );
              }
            },
          );
        }

        // Any other active status
        return _StatusBanner(
          color:       const Color(0xFFFFFBEB),
          borderColor: const Color(0xFFF59E0B),
          icon:        Icons.security_rounded,
          iconColor:   const Color(0xFFD97706),
          text:        'התשלום מוגן בחשבון נאמנות',
        );
      },
    );
  }

  // ── Messages list ─────────────────────────────────────────────────────────

  Widget _buildMessagesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: ChatStreamModule.getMessagesStream(chatRoomId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return _buildMessagesSkeleton();
        }
        final docs = snapshot.data!.docs;
        if (docs.isNotEmpty) _handleMarkAsRead();

        return ListView.builder(
          controller: _scrollCtrl,
          reverse: true,
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d     = docs[i].data() as Map<String, dynamic>;
            final isMe  = d['senderId'] == currentUserId;
            final isSys = d['senderId'] == 'system' ||
                d['type'] == 'system_alert';

            if (isSys) {
              return ChatUIHelper.buildSystemAlert(d['message'] ?? '');
            }

            return ChatUIHelper.buildMessageBubble(
              context: context,
              data:    d,
              isMe:    isMe,
              onPaymentTap: isMe
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ExpertProfileScreen(
                            expertId:   widget.receiverId,
                            expertName: widget.receiverName,
                          ),
                        ),
                      ),
            );
          },
        );
      },
    );
  }

  // ── Messages skeleton ─────────────────────────────────────────────────────
  // Shown while the first Firestore page loads. Bubbles alternate me/other
  // with realistic widths so the layout doesn't jump when real data arrives.

  Widget _buildMessagesSkeleton() {
    final double w = MediaQuery.sizeOf(context).width;
    final bubbles = <(double, bool)>[
      (w * 0.55, true),
      (w * 0.40, false),
      (w * 0.68, true),
      (w * 0.32, false),
      (w * 0.50, true),
      (w * 0.62, false),
    ];
    return ListView(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
      children: bubbles.map((item) {
        final (double width, bool isMe) = item;
        return Padding(
          padding: EdgeInsets.only(
              top: 4, bottom: 4,
              left:  isMe ? 60 : 10,
              right: isMe ? 10 : 60),
          child: Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: SizedBox(
              width: width, height: 40,
              child: const SkeletonBox(borderRadius: 18),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Typing bubble ─────────────────────────────────────────────────────────

  Widget _buildTypingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 60, 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft:     Radius.circular(18),
            topRight:    Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft:  Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.receiverName} מקליד',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            const SizedBox(width: 8),
            const _TypingDots(),
          ],
        ),
      ),
    );
  }

  // ── Quick actions ─────────────────────────────────────────────────────────

  Widget _buildQuickActions() {
    return Container(
      height: 44,
      color: Colors.white,
      child: ListView(
        scrollDirection: Axis.horizontal,
        reverse: true, // RTL: first chip on the right
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          _chip(Icons.location_on_rounded, 'שלח מיקום', () async {
            final url = await LocationModule.getMapUrl();
            if (url != null) _send(url, 'location');
          }, chipColor: Colors.redAccent),
          _chip(Icons.payments_rounded, 'בקש תשלום',
              _showRequestPaymentDialog,
              chipColor: const Color(0xFFD97706)),
          _chip(Icons.directions_car_rounded, 'אני בדרך 🚗',
              () => _send('אני בדרך! 🚗 אגיע בקרוב.', 'text'),
              chipColor: const Color(0xFF16A34A)),
          _chip(Icons.check_circle_outline_rounded, 'סיימתי ✅',
              () => _send('סיימתי את העבודה! ✅', 'text'),
              chipColor: const Color(0xFF0EA5E9)),
          _chip(Icons.image_outlined, 'שלח תמונה', () async {
            setState(() => _isUploading = true);
            final url = await ImageModule.uploadImage(chatRoomId);
            if (url != null) _send(url, 'image');
            if (mounted) setState(() => _isUploading = false);
          }, chipColor: const Color(0xFF6366F1)),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, VoidCallback onTap,
      {Color chipColor = const Color(0xFF6366F1)}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: chipColor.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: chipColor.withValues(alpha: 0.28)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: chipColor),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: chipColor,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ── Input area ────────────────────────────────────────────────────────────

  Widget _buildInputArea() {
    final hasText = _msgCtrl.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          if (_isUploading) ...[
            const LinearProgressIndicator(color: Color(0xFF6366F1)),
            const SizedBox(height: 6),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Text field
              Expanded(
                child: Container(
                  constraints:
                      const BoxConstraints(minHeight: 44, maxHeight: 120),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F6FA),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _guardFlagged
                          ? const Color(0xFFDC2626)
                          : Colors.grey.shade200,
                      width: _guardFlagged ? 1.5 : 1.0,
                    ),
                  ),
                  child: TextField(
                    controller: _msgCtrl,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textAlign: TextAlign.right,
                    textDirection: TextDirection.rtl,
                    onChanged: (v) {
                      _onTypingChanged(v);
                      _checkChatGuard(v);
                      setState(() {});
                    },
                    decoration: InputDecoration(
                      hintText: 'הקלד הודעה...',
                      hintStyle: TextStyle(
                          color: Colors.grey[400], fontSize: 14),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Send button — animates color
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: hasText
                      ? const Color(0xFF6366F1)
                      : Colors.grey[200],
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.send_rounded,
                    size: 18,
                    color: hasText ? Colors.white : Colors.grey[400],
                  ),
                  onPressed: () async {
                    final text = _msgCtrl.text.trim();
                    if (text.isEmpty) return;

                    // ── Chat Guard: mask sensitive data before sending ──────
                    final guard = ChatGuardService.check(text);
                    if (guard.isFlagged) {
                      _bypassAttempts++;
                      // Log admin alert after threshold is reached
                      if (_bypassAttempts >= ChatGuardService.attemptThreshold) {
                        final senderName = await _currentUserName();
                        ChatGuardService.logBypassAttempt(
                          userId:       currentUserId,
                          userName:     senderName,
                          chatRoomId:   chatRoomId,
                          flagType:     guard.flagType,
                          attemptCount: _bypassAttempts,
                        ).catchError((_) {});
                      }
                      _send(guard.maskedText, 'text');
                    } else {
                      _send(text, 'text');
                    }

                    _msgCtrl.clear();
                    _onTypingChanged('');
                    if (mounted) setState(() => _guardFlagged = false);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Job status banner component ───────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final Color    color;
  final Color    borderColor;
  final IconData icon;
  final Color    iconColor;
  final String   text;
  final String?  buttonText;
  final Color?   buttonColor;
  final VoidCallback? onTap;

  const _StatusBanner({
    required this.color,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.text,
    this.buttonText,
    this.buttonColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: color,
        border: Border(
          bottom: BorderSide(color: borderColor.withValues(alpha: 0.30)),
          right:  BorderSide(color: borderColor, width: 3),
        ),
      ),
      child: Row(
        children: [
          if (buttonText != null && onTap != null) ...[
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: buttonColor ?? const Color(0xFF6366F1),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
              ),
              onPressed: onTap,
              child: Text(buttonText!,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 12),
                textAlign: TextAlign.right),
          ),
          const SizedBox(width: 8),
          Icon(icon, color: iconColor, size: 18),
        ],
      ),
    );
  }
}

// ── Animated typing dots ──────────────────────────────────────────────────────

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;
  late final List<Animation<double>>   _anims;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(3, (i) {
      final c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
      );
      // Stagger each dot by 160 ms
      Future.delayed(Duration(milliseconds: i * 160), () {
        if (mounted) c.repeat(reverse: true);
      });
      return c;
    });
    _anims = _ctrls
        .map((c) => Tween<double>(begin: 0, end: -5).animate(
              CurvedAnimation(parent: c, curve: Curves.easeInOut),
            ))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _ctrls) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        3,
        (i) => AnimatedBuilder(
          animation: _anims[i],
          builder: (_, __) => Transform.translate(
            offset: Offset(0, _anims[i].value),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width:  5,
              height: 5,
              decoration: const BoxDecoration(
                color: Color(0xFF6366F1),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
