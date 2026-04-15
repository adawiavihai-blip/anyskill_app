import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_service.dart';

/// WhatsApp-style local outbox for chat messages.
///
/// We can't use Firestore's built-in persistence (Law 23 — permanently disabled
/// on web after 4 crash cycles), so this service does the work manually:
///
///  1. Every send is enqueued LOCALLY FIRST with status='pending' so the UI
///     shows a clock icon immediately, even offline.
///  2. A connectivity listener flushes the queue when the network returns.
///  3. Messages that still fail after [_maxAttempts] are marked 'failed'
///     for manual retry via tap.
///
/// Persistence: a single JSON array under [_prefsKey] in SharedPreferences.
/// Safe on web (no IndexedDB), iOS, Android.
class OfflineMessageQueue extends ChangeNotifier {
  OfflineMessageQueue._();
  static final OfflineMessageQueue instance = OfflineMessageQueue._();

  static const String _prefsKey      = 'offline_msg_queue_v1';
  static const int    _maxAttempts   = 3;
  static const Duration _retryDelay  = Duration(seconds: 2);

  final List<PendingMessage> _queue = [];
  SharedPreferences?          _prefs;
  StreamSubscription?         _connSub;
  bool                        _flushing = false;
  bool                        _initialized = false;

  /// Call once during app startup (after Firebase init is OK).
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      _prefs = await SharedPreferences.getInstance();
      _loadFromDisk();
    } catch (e) {
      debugPrint('[OfflineQueue] init load error: $e');
    }

    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.isNotEmpty &&
          !results.every((r) => r == ConnectivityResult.none);
      if (online && _queue.isNotEmpty) {
        debugPrint('[OfflineQueue] connectivity restored — flushing '
            '${_queue.length} pending');
        // ignore: discarded_futures
        flush();
      }
    });
  }

  // ── Read API (used by the UI) ────────────────────────────────────────────

  /// All pending + failed messages for a given chat room, newest first
  /// (matches the `orderBy('timestamp', descending: true)` Firestore stream).
  List<PendingMessage> pendingFor(String chatRoomId) {
    return _queue
        .where((m) => m.chatRoomId == chatRoomId)
        .toList()
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
  }

  // ── Write API (used by chat_screen._send) ────────────────────────────────

  /// Optimistic enqueue. Returns the created pending message so the caller
  /// can trigger a send attempt without reading the queue back.
  Future<PendingMessage> enqueue({
    required String chatRoomId,
    required String senderId,
    required String receiverId,
    required String content,
    required String type,
  }) async {
    final msg = PendingMessage(
      localId:     _newLocalId(),
      chatRoomId:  chatRoomId,
      senderId:    senderId,
      receiverId:  receiverId,
      message:     content,
      type:        type,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      status:      PendingStatus.pending,
      attempts:    0,
    );
    _queue.add(msg);
    await _persist();
    notifyListeners();
    // Attempt a send right away — if we're offline, it will fail fast
    // and the connectivity listener will retry.
    // ignore: discarded_futures
    _trySend(msg);
    return msg;
  }

  /// Manual retry for a [PendingStatus.failed] message.
  Future<void> retry(String localId) async {
    final msg = _find(localId);
    if (msg == null) return;
    msg.status   = PendingStatus.pending;
    msg.attempts = 0;
    await _persist();
    notifyListeners();
    await _trySend(msg);
  }

  /// Manual delete (user taps "cancel" on a stuck message).
  Future<void> remove(String localId) async {
    _queue.removeWhere((m) => m.localId == localId);
    await _persist();
    notifyListeners();
  }

  /// Flush everything pending. Idempotent + re-entrancy safe.
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      // Copy to avoid mutation during iteration
      final pending = _queue
          .where((m) => m.status == PendingStatus.pending)
          .toList();
      for (final msg in pending) {
        await _trySend(msg);
      }
    } finally {
      _flushing = false;
    }
  }

  // ── Internal ─────────────────────────────────────────────────────────────

  Future<void> _trySend(PendingMessage msg) async {
    msg.attempts += 1;
    final ok = await ChatService.sendMessage(
      chatRoomId: msg.chatRoomId,
      senderId:   msg.senderId,
      receiverId: msg.receiverId,
      content:    msg.message,
      type:       msg.type,
    );

    if (ok) {
      _queue.removeWhere((m) => m.localId == msg.localId);
      await _persist();
      notifyListeners();
      return;
    }

    if (msg.attempts >= _maxAttempts) {
      msg.status = PendingStatus.failed;
      await _persist();
      notifyListeners();
      return;
    }

    // Stay 'pending'; schedule a soft retry. Connectivity listener also
    // triggers flush on reconnect — this is a belt-and-braces backup for
    // intermittent signal where Connectivity doesn't flip state.
    await _persist();
    notifyListeners();
    Future.delayed(_retryDelay, () {
      if (_queue.any((m) => m.localId == msg.localId &&
                             m.status == PendingStatus.pending)) {
        // ignore: discarded_futures
        _trySend(msg);
      }
    });
  }

  PendingMessage? _find(String localId) {
    for (final m in _queue) {
      if (m.localId == localId) return m;
    }
    return null;
  }

  void _loadFromDisk() {
    final raw = _prefs?.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _queue
        ..clear()
        ..addAll(list
            .whereType<Map<String, dynamic>>()
            .map(PendingMessage.fromJson));
      // Resurrect any left in 'pending' after an app crash/close.
      for (final m in _queue) {
        if (m.status == PendingStatus.pending) {
          m.attempts = 0; // give it fresh retries next online flush
        }
      }
    } catch (e) {
      debugPrint('[OfflineQueue] corrupt prefs — discarding: $e');
      _queue.clear();
      _prefs?.remove(_prefsKey);
    }
  }

  Future<void> _persist() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final json = jsonEncode(_queue.map((m) => m.toJson()).toList());
      await prefs.setString(_prefsKey, json);
    } catch (e) {
      debugPrint('[OfflineQueue] persist error: $e');
    }
  }

  String _newLocalId() {
    final ts   = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(1 << 32).toRadixString(36);
    return 'local_${ts}_$rand';
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }
}

enum PendingStatus { pending, failed }

class PendingMessage {
  PendingMessage({
    required this.localId,
    required this.chatRoomId,
    required this.senderId,
    required this.receiverId,
    required this.message,
    required this.type,
    required this.createdAtMs,
    required this.status,
    required this.attempts,
  });

  final String  localId;
  final String  chatRoomId;
  final String  senderId;
  final String  receiverId;
  final String  message;
  final String  type;
  final int     createdAtMs;
  PendingStatus status;
  int           attempts;

  /// Shape that matches a Firestore message doc map, so the existing bubble
  /// builder can render it without a dedicated code path. Callers add the
  /// two extra UI-only fields (`__isPending`, `__localId`) themselves.
  Map<String, dynamic> toDocMap() => {
        'senderId':   senderId,
        'receiverId': receiverId,
        'message':    message,
        'type':       type,
        'timestamp':  null, // no serverTimestamp yet — UI falls back to createdAtMs
        'isRead':     false,
        '__isPending':     true,
        '__localId':       localId,
        '__pendingStatus': status == PendingStatus.failed ? 'failed' : 'pending',
        '__createdAtMs':   createdAtMs,
      };

  Map<String, dynamic> toJson() => {
        'localId':     localId,
        'chatRoomId':  chatRoomId,
        'senderId':    senderId,
        'receiverId':  receiverId,
        'message':     message,
        'type':        type,
        'createdAtMs': createdAtMs,
        'status':      status.name,
        'attempts':    attempts,
      };

  static PendingMessage fromJson(Map<String, dynamic> j) => PendingMessage(
        localId:     j['localId']     as String,
        chatRoomId:  j['chatRoomId']  as String,
        senderId:    j['senderId']    as String,
        receiverId:  j['receiverId']  as String,
        message:     j['message']     as String? ?? '',
        type:        j['type']        as String? ?? 'text',
        createdAtMs: (j['createdAtMs'] as num).toInt(),
        status: (j['status'] == 'failed')
            ? PendingStatus.failed
            : PendingStatus.pending,
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
      );
}
