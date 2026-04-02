import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../repositories/admin_users_repository.dart';

part 'admin_users_provider.g.dart';

// ── Repository provider (singleton — survives tab switches) ──────────────────

@Riverpod(keepAlive: true)
AdminUsersRepository adminUsersRepository(AdminUsersRepositoryRef ref) {
  debugPrint('[Riverpod] AdminUsersRepository created');
  return AdminUsersRepository();
}

// ── State model ──────────────────────────────────────────────────────────────

class AdminUsersState {
  const AdminUsersState({
    this.users = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.totalCustomers = 0,
    this.totalProviders = 0,
    this.searchQuery = '',
    this.error,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> users;
  final bool isLoading;
  final bool hasMore;
  final int totalCustomers;
  final int totalProviders;
  final String searchQuery;
  final String? error;

  /// Filtered view of users matching the current search query.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get filtered {
    if (searchQuery.isEmpty) return users;
    final q = searchQuery.toLowerCase();
    return users.where((doc) {
      final d = doc.data();
      final name = (d['name'] as String? ?? '').toLowerCase();
      final email = (d['email'] as String? ?? '').toLowerCase();
      return name.contains(q) || email.contains(q);
    }).toList();
  }

  /// Subset: customers only.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get customers =>
      filtered.where((d) => (d.data())['isCustomer'] == true).toList();

  /// Subset: providers only.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get providers =>
      filtered.where((d) => (d.data())['isProvider'] == true).toList();

  /// Subset: banned users.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get banned =>
      filtered.where((d) => (d.data())['isBanned'] == true).toList();

  AdminUsersState copyWith({
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? users,
    bool? isLoading,
    bool? hasMore,
    int? totalCustomers,
    int? totalProviders,
    String? searchQuery,
    String? error,
  }) {
    return AdminUsersState(
      users: users ?? this.users,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      totalCustomers: totalCustomers ?? this.totalCustomers,
      totalProviders: totalProviders ?? this.totalProviders,
      searchQuery: searchQuery ?? this.searchQuery,
      error: error,
    );
  }
}

// ── Notifier (autoDispose — GC'd when admin panel closes) ────────────────────

@riverpod
class AdminUsersNotifier extends _$AdminUsersNotifier {
  DocumentSnapshot? _cursor;

  @override
  AdminUsersState build() {
    debugPrint('[Riverpod] AdminUsersNotifier.build() — loading first page');
    Future.microtask(_loadInitialPage);
    return const AdminUsersState(isLoading: true);
  }

  AdminUsersRepository get _repo => ref.read(adminUsersRepositoryProvider);

  /// Initial load — skips the isLoading guard since build() already set it.
  Future<void> _loadInitialPage() async {
    try {
      final snap = await _repo.fetchUsersPage(limit: 50);
      final docs = snap.docs;
      _cursor = docs.isNotEmpty ? docs.last : null;

      debugPrint('[Riverpod] AdminUsers loaded ${docs.length} users '
          '(first: ${docs.isNotEmpty ? (docs.first.data()['name'] ?? "?") : "none"})');

      state = AdminUsersState(
        users: docs,
        isLoading: false,
        hasMore: docs.length == 50,
        totalCustomers:
            docs.where((d) => d.data()['isCustomer'] == true).length,
        totalProviders:
            docs.where((d) => d.data()['isProvider'] == true).length,
      );
    } catch (e) {
      debugPrint('[Riverpod] AdminUsers load error: $e');
      state = AdminUsersState(isLoading: false, error: e.toString());
    }
  }

  /// Fetch the next page of 50 users from Firestore.
  Future<void> loadNextPage() async {
    final current = state;
    if (current.isLoading || !current.hasMore) return;
    state = current.copyWith(isLoading: true);

    try {
      final snap = await _repo.fetchUsersPage(
        startAfter: _cursor,
        limit: 50,
      );
      final allUsers = [...current.users, ...snap.docs];
      _cursor = snap.docs.isNotEmpty ? snap.docs.last : _cursor;

      state = current.copyWith(
        users: allUsers,
        isLoading: false,
        hasMore: snap.docs.length == 50,
        totalCustomers:
            allUsers.where((d) => d.data()['isCustomer'] == true).length,
        totalProviders:
            allUsers.where((d) => d.data()['isProvider'] == true).length,
      );
    } catch (e) {
      state = current.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Update the search filter (UI rebuilds only the filtered list).
  void setSearch(String query) {
    state = state.copyWith(searchQuery: query);
  }

  /// Full reload — clears the list and re-fetches from page 1.
  Future<void> refresh() async {
    _cursor = null;
    state = const AdminUsersState(isLoading: true);
    await _loadInitialPage();
  }

  // ── Admin actions (delegate to repository) ─────────────────────────────

  Future<void> toggleVerified(String uid, bool current) =>
      _repo.toggleVerified(uid, current);

  Future<void> togglePromoted(String uid, bool current) =>
      _repo.togglePromoted(uid, current);

  Future<void> toggleBanned(String uid, bool current) =>
      _repo.toggleBanned(uid, current);

  Future<void> approveProvider(String uid) => _repo.approveProvider(uid);

  Future<void> setAdminNote(String uid, String note) =>
      _repo.setAdminNote(uid, note);

  Future<void> setCustomCommission(String uid, double? rate) =>
      _repo.setCustomCommission(uid, rate);

  Future<void> deleteUser(String uid) => _repo.deleteUser(uid);
}
