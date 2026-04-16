// ignore_for_file: use_build_context_synchronously
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'chat_modules/location_module.dart';
import '../services/cache_service.dart';
import 'chat_modules/image_module.dart';
import 'chat_modules/chat_logic_module.dart';
import 'chat_modules/safety_module.dart';
import '../l10n/app_localizations.dart';
import '../services/chat_guard_service.dart';
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

  // ── Provider state (determines if "Send Quote" chip is shown) ─────────────
  bool   _isProvider           = false;

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
    WidgetsBinding.instance.addObserver(this);
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
        'title':      '🔥 ביקוש אמיתי! משתמש פנה למומחה דמו',
        'detail':
            'משתמש (${widget.currentUserName ?? currentUserId}) ניסה לפנות '
            'למומחה דמו בקטגוריה "$category" — שקול לגייס ספק אמיתי בתחום זה!',
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

  Future<void> _sendOfficialQuote(double amount, String description) async {
    if (!await SafetyModule.hasInternet()) {
      if (mounted) SafetyModule.showError(context, AppLocalizations.of(context).chatNoInternet);
      return;
    }
    final db    = FirebaseFirestore.instance;
    final batch = db.batch();

    // 1. Create quote document
    final quoteRef = db.collection('quotes').doc();
    batch.set(quoteRef, {
      'providerId':  currentUserId,
      'clientId':    widget.receiverId,
      'chatRoomId':  chatRoomId,
      'description': description,
      'amount':      amount,
      'status':      'pending',
      'createdAt':   FieldValue.serverTimestamp(),
    });

    // 2. Create chat message with quoteId embedded
    final msgRef = db
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .doc();
    final senderName = await _currentUserName();
    batch.set(msgRef, {
      'senderId':    currentUserId,
      'senderName':  senderName,
      'receiverId':  widget.receiverId,
      'message':     description,
      'amount':      amount,
      'quoteId':     quoteRef.id,
      'messageId':   msgRef.id,
      'quoteStatus': 'pending',
      'type':        'official_quote',
      'isRead':      false,
      'timestamp':   FieldValue.serverTimestamp(),
    });

    // v9.5.9: Parent doc is ensured in initState — do NOT write it here.
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

  void _showQuoteDialog() {
    final amountCtrl = TextEditingController();
    final descCtrl   = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
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
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white54),
                    onPressed: () => Navigator.pop(ctx),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  Row(children: [
                    const Icon(Icons.receipt_long_rounded,
                        color: Color(0xFFA5B4FC), size: 20),
                    const SizedBox(width: 8),
                    Text(AppLocalizations.of(context).chatOfficialQuote,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold)),
                  ]),
                ],
              ),
              const SizedBox(height: 20),

              // Amount field
              TextField(
                controller: amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).chatAmountLabel,
                  labelStyle: const TextStyle(color: Colors.white54),
                  prefixText: '₪ ',
                  prefixStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: Color(0xFF6366F1), width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Description field
              TextField(
                controller: descCtrl,
                textAlign: TextAlign.right,
                maxLines: 3,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).chatServiceDescLabel,
                  labelStyle: const TextStyle(color: Colors.white54),
                  hintText: AppLocalizations.of(context).chatQuoteDescHint,
                  hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 13),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: Color(0xFF6366F1), width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Trust note
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.shield_rounded,
                      size: 11,
                      color: Colors.white.withValues(alpha: 0.4)),
                  const SizedBox(width: 4),
                  Text(AppLocalizations.of(context).chatEscrowNote,
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.4))),
                ],
              ),
              const SizedBox(height: 20),

              // Send button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: Text(AppLocalizations.of(context).chatSendQuote,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  onPressed: () {
                    final amount =
                        double.tryParse(amountCtrl.text.replaceAll(',', '.')) ??
                            0;
                    if (amount <= 0) return;
                    Navigator.pop(ctx);
                    _sendOfficialQuote(
                      amount,
                      descCtrl.text.trim().isEmpty
                          ? AppLocalizations.of(context).chatQuoteLabel
                          : descCtrl.text.trim(),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F8),
      appBar: ChatAppBarWidget(
        receiverId: widget.receiverId,
        receiverName: widget.receiverName,
      ),
      body: Column(
        children: [
          const ChatSafetyBanner(),
          ChatGuardBanner(
            showBanner: _showGuardBanner,
            onDismiss: () => setState(() => _showGuardBanner = false),
          ),
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
              final url = await LocationModule.getMapUrl();
              if (url != null) _send(url, 'location');
            },
            onSendImage: () async {
              setState(() => _isUploading = true);
              final url = await ImageModule.uploadImage(chatRoomId);
              if (url != null) _send(url, 'image');
              if (mounted) setState(() => _isUploading = false);
            },
            onIAmOnTheWay: () => _send(AppLocalizations.of(context).chatOnMyWay, 'text'),
            onIFinished: () => _send(AppLocalizations.of(context).chatWorkDone, 'text'),
            onShowQuoteDialog: _showQuoteDialog,
            onShowRequestPaymentDialog: _showRequestPaymentDialog,
          ),
        ],
      ),
    );
  }

  Future<void> _handleSendButton() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;

    // ── Chat Guard: mask sensitive data before sending ──────
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

    _msgCtrl.clear();
    _onTypingChanged('');
    if (mounted) setState(() => _guardFlagged = false);
  }
}
