import 'package:flutter/foundation.dart';

/// Tracks which category ids are currently bulk-selected. Independent of
/// [CategoriesV3Controller] so that toggling selection doesn't trigger a
/// re-stream of the underlying category list.
class SelectionController extends ChangeNotifier {
  final Set<String> _selected = <String>{};

  Set<String> get selectedIds => Set.unmodifiable(_selected);
  int get count => _selected.length;
  bool get isEmpty => _selected.isEmpty;
  bool get isNotEmpty => _selected.isNotEmpty;
  bool contains(String id) => _selected.contains(id);

  void toggle(String id) {
    if (_selected.remove(id)) {
      notifyListeners();
      return;
    }
    _selected.add(id);
    notifyListeners();
  }

  void selectAll(Iterable<String> ids) {
    final before = _selected.length;
    _selected.addAll(ids);
    if (_selected.length != before) notifyListeners();
  }

  void clear() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  /// Drops any id NOT in [validIds]. Use this after a list refresh so the
  /// selection doesn't dangle on deleted docs.
  void prune(Set<String> validIds) {
    final before = _selected.length;
    _selected.removeWhere((id) => !validIds.contains(id));
    if (_selected.length != before) notifyListeners();
  }
}
