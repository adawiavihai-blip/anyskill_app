import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/service_provider.dart';
import '../repositories/provider_repository.dart';

enum ProviderAction { none, loading, saving, approving, rejecting }

/// Global state for the Service Providers (experts) system.
///
/// Manages search results, verification queue, and admin actions.
class ServiceProviderNotifier extends ChangeNotifier {
  ServiceProviderNotifier({ProviderRepository? repository})
      : _repo = repository ?? ProviderRepository();

  @visibleForTesting
  ServiceProviderNotifier.test() : _repo = _DummyProvRepo();

  final ProviderRepository _repo;

  // ── State ─────────────────────────────────────────────────────────────

  List<ServiceProvider> _searchResults  = [];
  List<ServiceProvider> _pendingExperts = [];
  ServiceProvider?      _currentProfile;
  ProviderAction        _action = ProviderAction.none;
  String?               _error;
  StreamSubscription?   _profileSub;

  List<ServiceProvider> get searchResults  => _searchResults;
  List<ServiceProvider> get pendingExperts => _pendingExperts;
  ServiceProvider?      get currentProfile => _currentProfile;
  ProviderAction        get activeAction   => _action;
  bool                  get isLoading      => _action != ProviderAction.none;
  String?               get error          => _error;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  /// Watch a provider's profile in real-time (e.g., own profile).
  void watchProfile(String uid) {
    _profileSub?.cancel();
    _profileSub = _repo.watchProvider(uid).listen(
      (provider) {
        _currentProfile = provider;
        notifyListeners();
      },
      onError: (e) {
        _error = 'שגיאה בטעינת פרופיל';
        debugPrint('[ServiceProviderNotifier] watchProfile error: $e');
        notifyListeners();
      },
    );
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ── Search ────────────────────────────────────────────────────────────

  /// Fetch providers by category (paginated).
  Future<void> searchByCategory(String categoryName) async {
    _action = ProviderAction.loading;
    _error  = null;
    notifyListeners();

    try {
      _searchResults = await _repo.searchByCategory(
        categoryName: categoryName,
      );
      _action = ProviderAction.none;
      notifyListeners();
    } catch (e) {
      _error  = 'שגיאה בחיפוש ספקים';
      _action = ProviderAction.none;
      notifyListeners();
    }
  }

  /// Load next page of search results (append).
  Future<void> loadMoreResults(String categoryName) async {
    // Future: implement cursor-based pagination
  }

  // ── Profile ───────────────────────────────────────────────────────────

  /// Update the current provider's profile.
  Future<bool> updateProfile(
      String uid, Map<String, dynamic> updates) async {
    _action = ProviderAction.saving;
    _error  = null;
    notifyListeners();

    try {
      await _repo.updateProfile(uid, updates);
      _action = ProviderAction.none;
      notifyListeners();
      return true;
    } catch (e) {
      _error  = 'שגיאה בעדכון פרופיל';
      _action = ProviderAction.none;
      notifyListeners();
      return false;
    }
  }

  // ── Admin: Verification ───────────────────────────────────────────────

  /// Load pending expert applications.
  Future<void> loadPendingExperts() async {
    _action = ProviderAction.loading;
    notifyListeners();

    try {
      _pendingExperts = await _repo.getPendingExperts();
      _action = ProviderAction.none;
      notifyListeners();
    } catch (e) {
      _error  = 'שגיאה בטעינת בקשות';
      _action = ProviderAction.none;
      notifyListeners();
    }
  }

  /// Approve a pending expert → live provider.
  Future<bool> approveExpert(String uid) async {
    _action = ProviderAction.approving;
    _error  = null;
    notifyListeners();

    try {
      await _repo.approveExpert(uid);
      _pendingExperts.removeWhere((p) => p.uid == uid);
      _action = ProviderAction.none;
      notifyListeners();
      return true;
    } catch (e) {
      _error  = 'שגיאה באישור מומחה';
      _action = ProviderAction.none;
      notifyListeners();
      return false;
    }
  }

  /// Reject a pending expert.
  Future<bool> rejectExpert(String uid) async {
    _action = ProviderAction.rejecting;
    _error  = null;
    notifyListeners();

    try {
      await _repo.rejectExpert(uid);
      _pendingExperts.removeWhere((p) => p.uid == uid);
      _action = ProviderAction.none;
      notifyListeners();
      return true;
    } catch (e) {
      _error  = 'שגיאה בדחיית מומחה';
      _action = ProviderAction.none;
      notifyListeners();
      return false;
    }
  }

  /// Toggle online status.
  Future<void> setOnline(String uid, bool online) async {
    try {
      await _repo.setOnline(uid, online);
    } catch (e) {
      debugPrint('[ServiceProviderNotifier] setOnline failed: $e');
    }
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    super.dispose();
  }
}

class _DummyProvRepo extends ProviderRepository {
  _DummyProvRepo() : super.dummy();
}
