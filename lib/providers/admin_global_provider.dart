import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'admin_global_provider.g.dart';

// ── Global Admin Metrics ─────────────────────────────────────────────────────
//
// A single real-time state object tracking system-wide KPIs that appear in
// multiple admin tabs (header badges, section titles, etc.).
//
// Uses `keepAlive: true` so the data persists as long as the admin panel is
// mounted — switching between tabs does NOT re-query Firestore.
//
// Individual widgets use `ref.watch(adminGlobalProvider.select((s) => s.onlineUsers))`
// to rebuild only when that specific field changes.

class AdminGlobalState {
  const AdminGlobalState({
    this.onlineUsers = 0,
    this.pendingDisputes = 0,
    this.pendingVerifications = 0,
    this.openSupportTickets = 0,
    this.activeEscrows = 0,
    this.dailyActiveUsers = 0,
    this.loaded = false,
  });

  final int onlineUsers;
  final int pendingDisputes;
  final int pendingVerifications;
  final int openSupportTickets;
  final int activeEscrows;
  final int dailyActiveUsers;
  final bool loaded;

  AdminGlobalState copyWith({
    int? onlineUsers,
    int? pendingDisputes,
    int? pendingVerifications,
    int? openSupportTickets,
    int? activeEscrows,
    int? dailyActiveUsers,
    bool? loaded,
  }) {
    return AdminGlobalState(
      onlineUsers: onlineUsers ?? this.onlineUsers,
      pendingDisputes: pendingDisputes ?? this.pendingDisputes,
      pendingVerifications:
          pendingVerifications ?? this.pendingVerifications,
      openSupportTickets: openSupportTickets ?? this.openSupportTickets,
      activeEscrows: activeEscrows ?? this.activeEscrows,
      dailyActiveUsers: dailyActiveUsers ?? this.dailyActiveUsers,
      loaded: loaded ?? this.loaded,
    );
  }
}

@Riverpod(keepAlive: true)
class AdminGlobal extends _$AdminGlobal {
  final _db = FirebaseFirestore.instance;

  @override
  AdminGlobalState build() {
    _startStreams();
    ref.onDispose(_cancelAll);
    return const AdminGlobalState();
  }

  // ── Internal stream management ─────────────────────────────────────────

  final List<dynamic> _subs = [];

  void _cancelAll() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
  }

  void _startStreams() {
    // 1. Online users
    _subs.add(
      _db
          .collection('users')
          .where('isOnline', isEqualTo: true)
          .limit(200)
          .snapshots()
          .listen(
        (snap) => state =
            state.copyWith(onlineUsers: snap.docs.length, loaded: true),
        onError: (_) {},
      ),
    );

    // 2. Pending disputes
    _subs.add(
      _db
          .collection('jobs')
          .where('status', isEqualTo: 'disputed')
          .snapshots()
          .listen(
        (snap) => state = state.copyWith(pendingDisputes: snap.docs.length),
        onError: (_) {},
      ),
    );

    // 3. Pending verifications
    _subs.add(
      _db
          .collection('users')
          .where('isPendingExpert', isEqualTo: true)
          .limit(100)
          .snapshots()
          .listen(
        (snap) =>
            state = state.copyWith(pendingVerifications: snap.docs.length),
        onError: (_) {},
      ),
    );

    // 4. Open support tickets
    _subs.add(
      _db
          .collection('support_tickets')
          .where('status', isEqualTo: 'open')
          .limit(200)
          .snapshots()
          .listen(
        (snap) =>
            state = state.copyWith(openSupportTickets: snap.docs.length),
        onError: (_) {},
      ),
    );

    // 5. Active escrows
    _subs.add(
      _db
          .collection('jobs')
          .where('status', isEqualTo: 'paid_escrow')
          .snapshots()
          .listen(
        (snap) => state = state.copyWith(activeEscrows: snap.docs.length),
        onError: (_) {},
      ),
    );

    // 6. DAU
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    _subs.add(
      _db
          .collection('users')
          .where('lastOnlineAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
          .limit(200)
          .snapshots()
          .listen(
        (snap) =>
            state = state.copyWith(dailyActiveUsers: snap.docs.length),
        onError: (_) {},
      ),
    );
  }

  /// Force refresh all streams (e.g., on admin panel pull-to-refresh).
  void forceRefresh() {
    _cancelAll();
    state = const AdminGlobalState();
    _startStreams();
  }
}
