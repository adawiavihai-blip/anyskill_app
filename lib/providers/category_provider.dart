import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' hide Category;

import '../models/category.dart';
import '../repositories/category_repository.dart';

enum CategoryAction { none, saving, deleting, uploadingImage }

/// Global state for the Categories system.
///
/// UI watches [mainCategories], [isLoading], [error].
/// UI dispatches [updateCategory], [deleteCategory], [uploadImage].
class CategoryProvider extends ChangeNotifier {
  CategoryProvider({CategoryRepository? repository})
      : _repo = repository ?? CategoryRepository();

  @visibleForTesting
  CategoryProvider.test() : _repo = _DummyCatRepo();

  final CategoryRepository _repo;

  // ── State ─────────────────────────────────────────────────────────────

  List<Category> _all       = [];
  CategoryAction _action    = CategoryAction.none;
  String?        _error;
  StreamSubscription? _sub;

  List<Category> get allCategories  => _all;
  List<Category> get mainCategories =>
      _all.where((c) => c.isTopLevel && !c.isHidden).toList();
  CategoryAction get activeAction   => _action;
  bool           get isLoading      => _action != CategoryAction.none;
  String?        get error          => _error;

  /// Get sub-categories for a parent.
  List<Category> subCategoriesOf(String parentId) =>
      _all.where((c) => c.parentId == parentId).toList();

  /// Find a category by name.
  Category? findByName(String name) {
    try {
      return _all.firstWhere((c) => c.name == name);
    } catch (_) {
      return null;
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────

  void startWatching() {
    _sub?.cancel();
    _sub = _repo.watchAll().listen(
      (categories) {
        _all = categories;
        notifyListeners();
      },
      onError: (e) {
        _error = 'שגיאה בטעינת קטגוריות';
        debugPrint('[CategoryProvider] stream error: $e');
        notifyListeners();
      },
    );
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ── Actions ───────────────────────────────────────────────────────────

  /// Update category fields + optional image upload.
  /// Shows success only after server verification.
  Future<bool> updateCategory({
    required String docId,
    required String name,
    double? cardScale,
    Uint8List? imageBytes,
  }) async {
    _action = CategoryAction.saving;
    _error  = null;
    notifyListeners();

    try {
      // 1. Upload image if provided
      String? imageUrl;
      if (imageBytes != null) {
        _action = CategoryAction.uploadingImage;
        notifyListeners();
        imageUrl = await _repo.uploadImage(docId, imageBytes);
      }

      // 2. Write to Firestore
      final updates = <String, dynamic>{
        'name':     name,
        'iconName': FieldValue.delete(),
      };
      if (cardScale != null) updates['cardScale'] = cardScale;
      if (imageUrl != null) updates['img'] = imageUrl;
      await _repo.update(docId, updates);

      // 3. Server verification
      final verified = await _repo.verifyOnServer(docId);
      if (verified == null || verified.name != name) {
        throw Exception('השמירה נכשלה בשרת');
      }
      if (imageUrl != null && verified.img != imageUrl) {
        throw Exception('עדכון התמונה נכשל בשרת');
      }

      _action = CategoryAction.none;
      notifyListeners();
      return true;
    } catch (e) {
      _error  = _translateError(e);
      _action = CategoryAction.none;
      notifyListeners();
      return false;
    }
  }

  /// Delete a category (admin).
  Future<bool> deleteCategory(String docId, String imageUrl) async {
    _action = CategoryAction.deleting;
    _error  = null;
    notifyListeners();

    try {
      await _repo.delete(docId, imageUrl);
      _action = CategoryAction.none;
      notifyListeners();
      return true;
    } catch (e) {
      _error  = _translateError(e);
      _action = CategoryAction.none;
      notifyListeners();
      return false;
    }
  }

  /// Track a category tap for analytics.
  void recordClick(String docId) {
    _repo.incrementClick(docId);
  }

  /// How many providers are in this category (for admin delete warning).
  Future<int> providerCount(String categoryName) =>
      _repo.activeProviderCount(categoryName);

  // ── Helpers ───────────────────────────────────────────────────────────

  String _translateError(Object e) {
    final msg = e.toString();
    if (msg.contains('permission') || msg.contains('PERMISSION_DENIED')) {
      return 'שגיאת הרשאה — ייתכן שאין לך הרשאת עריכה';
    }
    if (msg.contains('network') || msg.contains('timeout')) {
      return 'שגיאת רשת — בדוק את החיבור';
    }
    return 'שגיאה — נסה שוב';
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

class _DummyCatRepo extends CategoryRepository {
  _DummyCatRepo() : super.dummy();
}
