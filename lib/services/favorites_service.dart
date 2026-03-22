import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Manages the current user's favorites list stored as
/// `favorites: List<String>` on their `users/{uid}` document.
class FavoritesService {
  FavoritesService._();

  static final _db = FirebaseFirestore.instance;

  // ── Toggle ────────────────────────────────────────────────────────────────

  /// Adds [providerId] to favorites if absent, removes it if present.
  /// Uses Firestore atomic operations — safe to call from any widget.
  static Future<void> toggle(String providerId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty || providerId.isEmpty) return;

    final ref  = _db.collection('users').doc(uid);
    final snap = await ref.get();
    final favs = List<String>.from(
        (snap.data()?['favorites'] as List?) ?? []);

    if (favs.contains(providerId)) {
      await ref.update(
          {'favorites': FieldValue.arrayRemove([providerId])});
    } else {
      await ref.update(
          {'favorites': FieldValue.arrayUnion([providerId])});
    }
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  /// Live stream of favorite provider IDs for [userId].
  static Stream<List<String>> streamIds(String userId) {
    if (userId.isEmpty) return const Stream.empty();
    return _db
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((snap) => List<String>.from(
            (snap.data()?['favorites'] as List?) ?? []));
  }
}
