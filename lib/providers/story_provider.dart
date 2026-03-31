import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/story.dart';
import '../repositories/story_repository.dart';

/// Global state for the Stories system.
///
/// UI widgets call action methods (upload, delete, like).
/// This provider handles loading/error state so widgets never need
/// `if (loading)` checks — they just watch [state].
enum StoryAction { none, uploading, deleting, liking }

class StoryProvider extends ChangeNotifier {
  StoryProvider({StoryRepository? repository})
      : _repo = repository ?? StoryRepository();

  /// Test-only constructor — no Firebase dependency.
  /// Safe for unit-testing state logic (ownStory, otherStories, clearError).
  @visibleForTesting
  StoryProvider.test() : _repo = _DummyRepo();

  final StoryRepository _repo;

  // ── State ─────────────────────────────────────────────────────────────

  List<Story>  _stories       = [];
  StoryAction  _activeAction  = StoryAction.none;
  String?      _error;
  double       _uploadProgress = 0;
  StreamSubscription? _sub;

  List<Story>  get stories        => _stories;
  StoryAction  get activeAction   => _activeAction;
  bool         get isLoading      => _activeAction != StoryAction.none;
  String?      get error          => _error;
  double       get uploadProgress => _uploadProgress;

  /// The current user's own story (if any).
  Story? ownStory(String uid) {
    try {
      return _stories.firstWhere((s) => s.uid == uid);
    } catch (_) {
      return null;
    }
  }

  /// All stories except the current user's.
  List<Story> otherStories(String uid) =>
      _stories.where((s) => s.uid != uid).toList();

  // ── Lifecycle ─────────────────────────────────────────────────────────

  /// Start listening to the active stories stream.
  void startWatching() {
    _sub?.cancel();
    _sub = _repo.watchActiveStories().listen(
      (stories) {
        _stories = stories;
        notifyListeners();
      },
      onError: (e) {
        _error = 'שגיאה בטעינת סטוריז';
        debugPrint('[StoryProvider] stream error: $e');
        notifyListeners();
      },
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────

  /// Clear any displayed error.
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Upload a new story from pre-read bytes.
  Future<bool> upload({
    required Uint8List videoBytes,
    required String fileName,
    required String mimeType,
  }) async {
    _activeAction   = StoryAction.uploading;
    _uploadProgress = 0;
    _error          = null;
    notifyListeners();

    try {
      await _repo.uploadStory(
        videoBytes: videoBytes,
        fileName:   fileName,
        mimeType:   mimeType,
        onProgress: (p) {
          _uploadProgress = p;
          notifyListeners();
        },
      );
      _activeAction = StoryAction.none;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _translateError(e);
      _activeAction = StoryAction.none;
      notifyListeners();
      return false;
    }
  }

  /// Delete a story.
  Future<bool> delete(String storyUid, String? videoUrl) async {
    _activeAction = StoryAction.deleting;
    _error        = null;
    notifyListeners();

    try {
      await _repo.deleteStory(storyUid, videoUrl);
      _activeAction = StoryAction.none;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _translateError(e);
      _activeAction = StoryAction.none;
      notifyListeners();
      return false;
    }
  }

  /// Like a story.
  Future<void> like(String storyUid) async {
    try {
      await _repo.likeStory(storyUid);
    } catch (e) {
      debugPrint('[StoryProvider] like failed: $e');
    }
  }

  /// Record a view.
  Future<void> recordView(String storyUid) async {
    try {
      await _repo.incrementViewCount(storyUid);
    } catch (e) {
      debugPrint('[StoryProvider] recordView failed: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  String _translateError(Object e) {
    final msg = e.toString();
    if (msg.contains('permission') || msg.contains('PERMISSION_DENIED')) {
      return 'שגיאת הרשאה — נסה להתחבר מחדש';
    }
    if (msg.contains('network') || msg.contains('timeout')) {
      return 'שגיאת רשת — בדוק את החיבור';
    }
    if (msg.contains('not-found') || msg.contains('storage/unknown')) {
      return 'שגיאה בשרת האחסון — נסה שוב';
    }
    return 'שגיאה — נסה שוב';
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Minimal stub so StoryProvider.test() compiles without Firebase.
class _DummyRepo extends StoryRepository {
  _DummyRepo() : super.dummy();
}
