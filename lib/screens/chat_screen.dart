// ignore_for_file: use_build_context_synchronously
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'chat_modules/location_module.dart';
import '../services/cache_service.dart';
import '../services/chat_theme_controller.dart';
import 'chat_modules/image_module.dart';
import 'chat_modules/video_module.dart';
import 'chat_modules/chat_logic_module.dart';
import 'chat_modules/safety_module.dart';
import '../l10n/app_localizations.dart';
import '../services/chat_guard_service.dart';
import '../services/chat_guard_client.dart';
import '../services/chat_service.dart';
import '../services/offline_message_queue.dart';
import 'chat_helpers/chat_app_bar.dart';
import 'chat_helpers/chat_banners.dart';
import 'chat_helpers/chat_message_list.dart';
import 'chat_helpers/chat_input_bar.dart';

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

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _msgCtrl    = TextEditingController();
  final ScrollController       _scrollCtrl = ScrollController();

  final String currentUserId =
      FirebaseAuth.instance.currentUser?.uid ?? '';

  late final String chatRoomId;

  bool   _isUploading        = false;
  bool   _isReceiverTyping   = false;

  // ── Avatar URLs (loaded once for message bubble display) ──────────────────
  String _receiverImageUrl     = '';
  String _currentUserImageUrl  = '';

  // ── Provider state (drives the attach-menu offer-item label: provider
  // sees "הצעת מחיר" + offer dialog, customer sees "בקש תשלום" + payment-
  // request dialog) ────────────────────────────────────────────────────────
  bool   _isProvider           = false;

  // ── Chat Guard state ──────────────────────────────────────────────────────
  bool      _guardFlagged      = false;   // true while current input is flagged
  int       _bypassAttempts    = 0;       // counts flagged sends this session
  DateTime? _lastGuardWarnTime;           // prevents SnackBar spam
  Timer?    _guardDebounce;               // delays detection until typing pauses

  // ── Demo Expert alert (fired once per session) ─────────────────────────────

  Timer? _markReadDebounce;
  Timer? _typingClearTimer;
  StreamSubscription<DocumentSnapshot>? _chatDocSub;

  // ── Failed-message visibility (Fix 4) ─────────────────────────────────
  // Tracks the local IDs of messages we've already shown a failure
  // SnackBar for in this session, so a single failed message doesn't
  // spam every queue tick.
  final Set<String> _failureNotified = {};
  VoidCallback? _queueListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // PR-3a: bootstrap chat-local theme controller (persists across
    // sessions + ticks every minute in auto mode). Safe to call on every
    // chat screen — the controller is a singleton and no-ops after first
    // init.
    unawaited(ChatThemeController.instance.init());
    // v9.6.1: Use centralized deterministic room ID
    chatRoomId = ChatService.getRoomId(currentUserId, widget.receiverId);
    debugPrint('[ChatScreen] Room=$chatRoomId me=$currentUserId other=${widget.receiverId}');

    // Ensure parent doc exists BEFORE any listener or message send.
    // sendMessage also calls ensureRoom, but this pre-warms the cache.
    ChatService.ensureRoom(
      chatRoomId: chatRoomId,
      userId: currentUserId,
      otherUserId: widget.receiverId,
    ).then((ok) {
      if (ok) {
        ChatLogicModule.markMessagesAsRead(chatRoomId, currentUserId);
      } else {
        debugPrint('[ChatScreen] WARNING: ensureRoom failed — messages may not send');
      }
    });

    _handleMarkAsRead();
    _listenToTyping();
    _checkDemoExpert();
    _loadAvatarImages();
    if (widget.initialMessage?.isNotEmpty == true) {
      _msgCtrl.text = widget.initialMessage!;
    }
    _attachQueueFailureListener();
  }

  /// Subscribe to the offline outbox and surface a SnackBar the first time
  /// any message in THIS room transitions to `failed`. Without this,
  /// failed messages render with a small red icon at the bottom of the
  /// thread that's easy to miss when the user has scrolled — the customer
  /// just thinks "I sent a message, why doesn't anything appear?".
  void _attachQueueFailureListener() {
    _queueListener = () {
      if (!mounted) return;
      final pending =
          OfflineMessageQueue.instance.pendingFor(chatRoomId);
      for (final m in pending) {
        if (m.status == PendingStatus.failed &&
            !_failureNotified.contains(m.localId)) {
          _failureNotified.add(m.localId);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red.shade600,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
              content: const Text(
                'ההודעה לא נשלחה — בדוק חיבור או הקש על הבועה האדומה לנסות שוב',
                textAlign: TextAlign.right,
                style: TextStyle(color: Colors.white),
              ),
              action: SnackBarAction(
                label: 'נסה שוב',
                textColor: Colors.white,
                onPressed: () => OfflineMessageQueue.instance.retry(m.localId),
              ),
            ),
          );
          // Only one SnackBar per tick — others queue normally.
          break;
        }
      }
    };
    OfflineMessageQueue.instance.addListener(_queueListener!);
  }

  /// Load both parties' profile images once so message bubbles can show avatars.
  Future<void> _loadAvatarImages() async {
    if (widget.receiverId.isNotEmpty) {
      try {
        final d = await CacheService.getDoc(
            'users', widget.receiverId, ttl: CacheService.kUserProfile);
        if (mounted) {
          setState(() =>
              _receiverImageUrl = d['profileImage'] as String? ?? '');
        }
      } catch (_) {}
    }
    if (currentUserId.isNotEmpty) {
      try {
        final d = await CacheService.getDoc(
            'users', currentUserId, ttl: CacheService.kUserProfile);
        if (mounted) {
          setState(() {
            _currentUserImageUrl = d['profileImage'] as String? ?? '';
            _isProvider          = d['isProvider'] == true;
          });
        }
      } catch (_) {}
    }
  }

  /// One-time check: if the receiver is a demo expert, log a high-priority
  /// alert to the admin Activity Log so demand in this category is surfaced.
  Future<void> _checkDemoExpert() async {
    if (currentUserId.isEmpty || widget.receiverId.isEmpty) return;
    try {
      // CacheService: receiver profile is read once per chat open.
      // Caching for 5 min eliminates redundant Firestore reads when the user
      // navigates away and back (common pattern).
      final d = await CacheService.getDoc(
        'users', widget.receiverId, ttl: CacheService.kUserProfile);
      if (d['isDemo'] != true) return;

      // Deduplicate: don't log if already logged today for this pair
      final dedupId = 'demo_${currentUserId}_${widget.receiverId}';
      final existing = await FirebaseFirestore.instance
          .collection('activity_log')
          .doc(dedupId)
          .get();
      if (existing.exists) return;

      final category = d['serviceType'] as String? ?? d['name'] as String? ?? 'unknown';
      await FirebaseFirestore.instance
          .collection('activity_log')
          .doc(dedupId)
          .set({
        'type':       'demo_contact',
        'priority':   'high',
        'title':      '🔥 ביקוש אמיתי! משתמש פנה לנותן השירות דמו',
        'detail':
            'משתמש (${widget.currentUserName ?? currentUserId}) ניסה לפנות '
            'לנותן השירות דמו בקטגוריה "$category" — שקול לגייס ספק אמיתי בתחום זה!',
        'userId':     currentUserId,
        'receiverId': widget.receiverId,
        'category':   category,
        'createdAt':  FieldValue.serverTimestamp(),
        'expireAt':   Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 30))),
      });
    } catch (_) {
      // Non-fatal — don't interrupt the chat UX
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Hard-reset typing when app goes to background/inactive
    if (state != AppLifecycleState.resumed) {
      _clearTypingIndicator();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _markReadDebounce?.cancel();
    _typingClearTimer?.cancel();
    _guardDebounce?.cancel();
    _chatDocSub?.cancel();
    if (_queueListener != null) {
      OfflineMessageQueue.instance.removeListener(_queueListener!);
    }
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _clearTypingIndicator();
    super.dispose();
  }

  void _clearTypingIndicator() {
    _typingClearTimer?.cancel();
    // v9.5.5: Typing indicators live in a SEPARATE subcollection
    // (chats/{roomId}/typing/{uid}) — never touch the parent doc.
    // This eliminates the AsyncQueue deadlock where a snapshot listener
    // and a writer on the same document crash the Firestore web SDK.
    FirebaseFirestore.instance
        .collection('chats')
        .doc(chatRoomId)
        .collection('typing')
        .doc(currentUserId)
        .set({'isTyping': false}, SetOptions(merge: true))
        .catchError((_) {});
  }

  // ── Typing indicator logic ────────────────────────────────────────────────
  // v9.5.5: Moved from parent chat doc fields to subcollection
  // chats/{roomId}/typing/{uid} to prevent AsyncQueue deadlock.

  void _listenToTyping() {
    _chatDocSub = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatRoomId)
        .collection('typing')
        .doc(widget.receiverId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final d      = snap.data() ?? {};
      final typing = d['isTyping'] as bool? ?? false;
      // Safety: if the typing timestamp is stale (>15s ago), ignore it.
      if (typing) {
        final ts = d['isTypingAt'] as Timestamp?;
        if (ts != null) {
          final age = DateTime.now().difference(ts.toDate());
          if (age.inSeconds > 15) {
            if (_isReceiverTyping) setState(() => _isReceiverTyping = false);
            return;
          }
        }
        if (ts == null) {
          if (_isReceiverTyping) setState(() => _isReceiverTyping = false);
          return;
        }
      }
      if (typing != _isReceiverTyping) {
        setState(() => _isReceiverTyping = typing);
      }
    }, onError: (_) {
      // If typing listener fails, just disable the indicator — not critical
      if (mounted && _isReceiverTyping) setState(() => _isReceiverTyping = false);
    });
  }

  void _onTypingChanged(String text) {
    final isTyping = text.isNotEmpty;
    // v9.5.5: Write to subcollection, NOT the parent chat doc
    FirebaseFirestore.instance
        .collection('chats')
        .doc(chatRoomId)
        .collection('typing')
        .doc(currentUserId)
        .set({
          'isTyping': isTyping,
          'isTypingAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true))
        .catchError((_) {});

    _typingClearTimer?.cancel();
    if (isTyping) {
      // Auto-clear after 5s of no keystrokes — prevents ghost typing
      _typingClearTimer = Timer(const Duration(seconds: 5), () {
        _clearTypingIndicator();
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
                content: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.security_rounded,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context).chatSafetyWarning,
                        style: const TextStyle(fontSize: 12, height: 1.4),
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
    // Optimistic: enqueue locally, render immediately with a clock icon.
    // The queue handles the Firestore write + retries + connectivity recovery.
    await OfflineMessageQueue.instance.enqueue(
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
      if (mounted) SafetyModule.showError(context, AppLocalizations.of(context).chatNoInternet);
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

    // v9.5.9: Parent doc is ensured in initState — do NOT write it here.
    // Writing to the parent doc in a batch triggers the AsyncQueue deadlock.
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
    if (!mounted) return widget.currentUserName ?? 'Customer';
    return widget.currentUserName ?? AppLocalizations.of(context).chatDefaultCustomer;
  }

  // ── Request payment dialog ─────────────────────────────────────────────────
  // Customer-side action surfaced via the attach menu (💰 בקש תשלום).
  // PR-2b will redesign the payment-request UX; for now this is the legacy
  // dialog with no breaking changes.
  void _showRequestPaymentDialog() {
    final amountCtrl = TextEditingController();
    final descCtrl   = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.payments_rounded, color: Color(0xFFF59E0B)),
          const SizedBox(width: 8),
          Text(AppLocalizations.of(context).chatPaymentRequest,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
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
                labelText: AppLocalizations.of(context).chatAmountLabel,
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
                labelText: AppLocalizations.of(context).chatServiceDescLabel,
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
                descCtrl.text.isEmpty ? AppLocalizations.of(context).chatPaymentRequest : descCtrl.text,
              );
            },
            child: Text(AppLocalizations.of(context).chatSend,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Official Quote — send to Firestore + chat message ─────────────────────
  // Customer pays `amount = regularPrice - discount` (option A locked
  // 2026-04-21 in messages-upgrade memory). Platform commission is NEVER
  // shown to either side; it's deducted from the provider's payout
  // server-side via `processPaymentRelease` (see CLAUDE.md §4.3).

  Future<void> _sendOfficialQuote({
    required double regularPrice,
    required double discount,
    required Duration expiry,
    required String description,
  }) async {
    if (!await SafetyModule.hasInternet()) {
      if (mounted) {
        SafetyModule.showError(
            context, AppLocalizations.of(context).chatNoInternet);
      }
      return;
    }

    final amount = double.parse((regularPrice - discount).toStringAsFixed(2));
    final expiresAt =
        Timestamp.fromDate(DateTime.now().toUtc().add(expiry));

    final db = FirebaseFirestore.instance;
    final batch = db.batch();

    // 1. Create quote document with PR-2b fields
    final quoteRef = db.collection('quotes').doc();
    batch.set(quoteRef, {
      'providerId':  currentUserId,
      'clientId':    widget.receiverId,
      'chatRoomId':  chatRoomId,
      'description': description,
      'regularPrice': regularPrice,
      'discount':    discount,
      'amount':      amount,
      'expiresAt':   expiresAt,
      'status':      'pending',
      'createdAt':   FieldValue.serverTimestamp(),
    });

    // 2. Create chat message with quoteId embedded — denormalize the new
    // fields onto the message so the card renders without an extra
    // Firestore read per message.
    final msgRef = db
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .doc();
    final senderName = await _currentUserName();
    batch.set(msgRef, {
      'senderId':     currentUserId,
      'senderName':   senderName,
      'receiverId':   widget.receiverId,
      'message':      description,
      'amount':       amount,
      'regularPrice': regularPrice,
      'discount':     discount,
      'expiresAt':    expiresAt,
      'quoteId':      quoteRef.id,
      'messageId':    msgRef.id,
      'quoteStatus':  'pending',
      'type':         'official_quote',
      'isRead':       false,
      'timestamp':    FieldValue.serverTimestamp(),
    });

    try {
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).chatQuoteSent),
          backgroundColor: const Color(0xFF22C55E),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).chatQuoteError),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ));
      }
    }
  }

  // ── Official Quote dialog ──────────────────────────────────────────────────
  // Provider-side modal opened from the attach menu (💰 הצעת מחיר).
  // PR-2b — Airbnb-style 3 fields + 4 expiry chips per
  // docs/ui-specs/messagesS spec. The provider sees ONLY the gross price
  // and discount they're offering — the platform commission is hidden
  // (deducted from payout, not from customer's bill — option A locked).
  void _showQuoteDialog() {
    final descCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final discountCtrl = TextEditingController(text: '0');
    Duration selectedExpiry = const Duration(hours: 1);

    showDialog(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(context);
        final expiryChips = <(Duration, String)>[
          (const Duration(minutes: 30), l10n.chatQuoteExpiry30m),
          (const Duration(hours: 1), l10n.chatQuoteExpiry1h),
          (const Duration(hours: 6), l10n.chatQuoteExpiry6h),
          (const Duration(hours: 24), l10n.chatQuoteExpiry24h),
        ];

        InputDecoration darkInput(String label, {String? hint, String? prefix}) {
          return InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white54),
            hintText: hint,
            hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
            prefixText: prefix,
            prefixStyle: const TextStyle(color: Colors.white70),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.08),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                  color: Color(0xFF6366F1), width: 1.5),
            ),
          );
        }

        return Dialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24)),
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              return Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1A0E3C), Color(0xFF2D1A6B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // ── Header ─────────────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.white54),
                          onPressed: () => Navigator.pop(ctx),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        Row(children: [
                          const Icon(Icons.receipt_long_rounded,
                              color: Color(0xFFA5B4FC), size: 20),
                          const SizedBox(width: 8),
                          Text(l10n.chatOfficialQuote,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold)),
                        ]),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Field 1: service description ───────────────────────
                    TextField(
                      controller: descCtrl,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: darkInput(
                        l10n.chatServiceDescLabel,
                        hint: l10n.chatQuoteServiceHint,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Field 2: regular (gross) price ─────────────────────
                    TextField(
                      controller: priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      textAlign: TextAlign.right,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: darkInput(
                        l10n.chatQuoteRegularPrice,
                        prefix: '₪ ',
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Field 3: customer discount ─────────────────────────
                    TextField(
                      controller: discountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      textAlign: TextAlign.right,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: darkInput(
                        l10n.chatQuoteDiscount,
                        prefix: '₪ ',
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ── 4 expiry chips ─────────────────────────────────────
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        l10n.chatQuoteExpiryTitle,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      textDirection: TextDirection.rtl,
                      children: [
                        for (final (duration, label) in expiryChips)
                          _ExpiryChip(
                            label: label,
                            selected: selectedExpiry == duration,
                            onTap: () =>
                                setLocal(() => selectedExpiry = duration),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Trust note
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(Icons.shield_rounded,
                            size: 11,
                            color: Colors.white.withValues(alpha: 0.4)),
                        const SizedBox(width: 4),
                        Text(l10n.chatEscrowNote,
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.white.withValues(alpha: 0.4))),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Send button ───────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.send_rounded, size: 16),
                        label: Text(l10n.chatQuoteSendOffer,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        onPressed: () {
                          final regularPrice = double.tryParse(
                                  priceCtrl.text.trim().replaceAll(',', '.')) ??
                              0;
                          final discount = double.tryParse(
                                  discountCtrl.text.trim().replaceAll(',', '.')) ??
                              0;
                          if (regularPrice <= 0 ||
                              discount < 0 ||
                              discount >= regularPrice) {
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                              content: Text(l10n.chatQuoteValidation),
                              backgroundColor: Colors.red,
                              duration: const Duration(seconds: 3),
                            ));
                            return;
                          }
                          Navigator.pop(ctx);
                          _sendOfficialQuote(
                            regularPrice: regularPrice,
                            discount: discount,
                            expiry: selectedExpiry,
                            description: descCtrl.text.trim().isEmpty
                                ? l10n.chatQuoteLabel
                                : descCtrl.text.trim(),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // PR-3a: chat-screen-LOCAL dark mode. Everything below listens to the
    // controller via the InheritedWidget [ChatThemeScope], and the 500ms
    // TweenAnimationBuilder smooths the palette swap so tapping
    // light/dark/auto doesn't flash.
    return AnimatedBuilder(
      animation: ChatThemeController.instance,
      builder: (ctx, _) {
        final isDark = ChatThemeController.instance.isDark;
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: isDark ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          builder: (ctx, t, __) {
            final palette =
                ChatPalette.lerp(ChatPalette.light, ChatPalette.dark, t);
            return ChatThemeScope(
              palette: palette,
              isDark: isDark,
              child: _buildScaffold(palette),
            );
          },
        );
      },
    );
  }

  Widget _buildScaffold(ChatPalette p) {
    return Scaffold(
      backgroundColor: p.background,
      appBar: ChatAppBarWidget(
        receiverId: widget.receiverId,
        receiverName: widget.receiverName,
      ),
      body: Column(
        children: [
          ChatJobStatusBanner(
            chatRoomId: chatRoomId,
            currentUserId: currentUserId,
            receiverId: widget.receiverId,
            receiverName: widget.receiverName,
            getCurrentUserName: _currentUserName,
          ),
          ChatVolunteerBanner(
            currentUserId: currentUserId,
            receiverId: widget.receiverId,
          ),
          Expanded(
            child: ChatMessageList(
              chatRoomId: chatRoomId,
              currentUserId: currentUserId,
              receiverId: widget.receiverId,
              receiverName: widget.receiverName,
              currentUserName: widget.currentUserName ?? '',
              currentUserImageUrl: _currentUserImageUrl,
              receiverImageUrl: _receiverImageUrl,
              scrollController: _scrollCtrl,
              onMessagesLoaded: _handleMarkAsRead,
            ),
          ),
          if (_isReceiverTyping)
            ChatTypingBubble(receiverName: widget.receiverName),
          ChatInputBar(
            controller: _msgCtrl,
            isUploading: _isUploading,
            guardFlagged: _guardFlagged,
            isProvider: _isProvider,
            onTextChanged: (v) {
              _onTypingChanged(v);
              _checkChatGuard(v);
              setState(() {});
            },
            onSend: _handleSendButton,
            onSendLocation: () async {
              final url = await LocationModule.getMapUrl(context);
              if (!mounted) return;
              if (url != null) {
                _send(url, 'location');
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      'לא הצלחנו לאתר את המיקום שלך. בדוק הרשאות ונסה שוב.'),
                  duration: Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                ));
              }
            },
            onSendImage: () async {
              setState(() => _isUploading = true);
              final url = await ImageModule.uploadImage(chatRoomId);
              if (url != null) _send(url, 'image');
              if (mounted) setState(() => _isUploading = false);
            },
            onSendVideoComingSoon: () async {
              setState(() => _isUploading = true);
              final url = await VideoModule.uploadVideo(chatRoomId);
              if (!mounted) return;
              setState(() => _isUploading = false);
              if (url != null) {
                _send(url, 'video');
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('לא הצלחנו להעלות את הווידאו. נסה שוב.'),
                  duration: Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                ));
              }
            },
            onShowOfferDialog: _isProvider
                ? _showQuoteDialog
                : _showRequestPaymentDialog,
          ),
        ],
      ),
    );
  }

  Future<void> _handleSendButton() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;

    // Clear input + typing indicator IMMEDIATELY so the user gets instant
    // feedback that their tap registered. Even if the guard check below
    // takes a moment, the message is already enqueued in the offline outbox
    // (which renders the pending bubble), so the input is now safe to clear.
    // Previously the input stayed full while the CF was in-flight, making
    // the UI feel frozen and pushing users to retap "send" repeatedly.
    _msgCtrl.clear();
    _onTypingChanged('');
    if (mounted) setState(() => _guardFlagged = false);

    // ── Phase 3 Chat Guard (server-side CF) ──────────────────────────────
    // Respects the admin kill-switch: when disabled, returns `skipped: true`
    // instantly and we fall through to the legacy regex masking below.
    // Failure-open on network error or cold-start (see ChatGuardClient
    // — 4s hard timeout). The whole block is wrapped in try/catch so a
    // bug in the guard never blocks an otherwise-valid message from
    // reaching the queue.
    ChatGuardCheckResult cfResult;
    try {
      cfResult = await ChatGuardClient.check(
        message: text,
        chatId: chatRoomId,
        receiverId: widget.receiverId,
      );
    } catch (e) {
      debugPrint('[ChatScreen] guard check threw — failing open: $e');
      cfResult = const ChatGuardCheckResult.allowed(skipped: true);
    }

    if (!cfResult.skipped) {
      switch (cfResult.action) {
        case ChatGuardAction.blocked:
        case ChatGuardAction.suspended:
          if (mounted) {
            // Restore the input so the user can edit + try again.
            _msgCtrl.text = text;
            _showGuardBlockedDialog(cfResult);
          }
          return; // do NOT send
        case ChatGuardAction.rewritten:
          final useRewrite = await _askGuardRewrite(cfResult);
          if (useRewrite == null) {
            // User cancelled — restore input.
            if (mounted) _msgCtrl.text = text;
            return;
          }
          final toSend = useRewrite ? (cfResult.rewrite ?? text) : text;
          _send(toSend, 'text');
          return;
        case ChatGuardAction.warned:
          // Send as-is but show a discreet tip.
          if (mounted) _showGuardTip(cfResult);
          _send(text, 'text');
          return;
        case ChatGuardAction.allowed:
          // Clean — fall through to legacy regex mask (defense in depth).
          break;
      }
    }

    // ── Legacy local regex mask (always-on defense-in-depth) ────────────
    final guard = ChatGuardService.check(text);
    if (guard.isFlagged) {
      _bypassAttempts++;
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
  }

  // ── Phase 3 Chat Guard UI helpers ─────────────────────────────────────

  /// Red modal — message fully blocked. User must tap OK to dismiss.
  void _showGuardBlockedDialog(ChatGuardCheckResult r) {
    final suspended = r.action == ChatGuardAction.suspended;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.block_rounded,
                color: suspended
                    ? const Color(0xFF991B1B)
                    : const Color(0xFFEF4444),
                size: 24),
            const SizedBox(width: 8),
            Text(suspended ? 'חשבונך מוגבל' : 'ההודעה נחסמה'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              r.reason ?? 'ההודעה מפרה את מדיניות הצ\'אט',
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: const Text(
                'ניתן לבצע תשלומים, תיאום ופרטי קשר אך ורק דרך האפליקציה. '
                'שיתוף פרטי חוץ פוגע בהגנת העסקה שלך.',
                style: TextStyle(fontSize: 12, color: Color(0xFF7F1D1D)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('הבנתי'),
          ),
        ],
      ),
    );
  }

  /// Bottom sheet offering the rewritten version vs the original.
  Future<bool?> _askGuardRewrite(ChatGuardCheckResult r) async {
    final rewrite = r.rewrite;
    if (rewrite == null || rewrite.isEmpty) return false;
    return showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_fix_high_rounded,
                    color: Color(0xFF3B82F6), size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('נוסח מוצע לשליחה בטוחה',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (r.reason != null && r.reason!.isNotEmpty)
              Text(r.reason!,
                  style: const TextStyle(
                      fontSize: 12.5, color: Color(0xFF6B7280))),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Text(rewrite,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF1E3A8A), height: 1.4)),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('שלח את המקור'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('שלח מוצע'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
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

  /// Amber snackbar — message was sent but contained a borderline pattern.
  void _showGuardTip(ChatGuardCheckResult r) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              r.reason ?? 'שים לב — ההודעה נשלחה אך זוהה דפוס חשוד',
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF59E0B),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 4),
    ));
  }
}

// ── Provider quote-modal expiry chip ───────────────────────────────────────
// Filled indigo when selected, ghost-outline white when idle. Used inside
// the Wrap of 4 expiry options in `_showQuoteDialog`.
class _ExpiryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ExpiryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF6366F1)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? const Color(0xFF818CF8)
                  : Colors.white.withValues(alpha: 0.18),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
