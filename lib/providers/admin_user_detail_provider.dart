import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'admin_user_detail_provider.g.dart';

// ── User detail stream (.family — one per userId, autoDispose) ───────────────

@riverpod
Stream<Map<String, dynamic>> userDetail(UserDetailRef ref, String userId) {
  return FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .snapshots()
      .map((snap) => {'uid': snap.id, ...snap.data() ?? {}});
}

// ── User transactions (one-shot, autoDispose) ────────────────────────────────

@riverpod
Future<List<Map<String, dynamic>>> userTransactions(
    UserTransactionsRef ref, String userId) async {
  final db = FirebaseFirestore.instance;

  // Fetch both sent and received transactions
  final results = await Future.wait([
    db
        .collection('transactions')
        .where('senderId', isEqualTo: userId)
        .limit(100)
        .get(),
    db
        .collection('transactions')
        .where('receiverId', isEqualTo: userId)
        .limit(100)
        .get(),
  ]);

  final all = <Map<String, dynamic>>[];
  for (final snap in results) {
    for (final doc in snap.docs) {
      all.add({'id': doc.id, ...doc.data()});
    }
  }
  // Sort by timestamp descending
  all.sort((a, b) {
    final ta = a['timestamp'] as Timestamp?;
    final tb = b['timestamp'] as Timestamp?;
    if (ta == null || tb == null) return 0;
    return tb.compareTo(ta);
  });
  return all;
}

// ── User jobs (one-shot, autoDispose) ────────────────────────────────────────

@riverpod
Future<List<Map<String, dynamic>>> userJobs(
    UserJobsRef ref, String userId) async {
  final db = FirebaseFirestore.instance;

  final results = await Future.wait([
    db
        .collection('jobs')
        .where('customerId', isEqualTo: userId)
        .limit(50)
        .get(),
    db
        .collection('jobs')
        .where('expertId', isEqualTo: userId)
        .limit(50)
        .get(),
  ]);

  final all = <Map<String, dynamic>>[];
  for (final snap in results) {
    for (final doc in snap.docs) {
      all.add({'id': doc.id, ...doc.data()});
    }
  }
  all.sort((a, b) {
    final ta = a['createdAt'] as Timestamp?;
    final tb = b['createdAt'] as Timestamp?;
    if (ta == null || tb == null) return 0;
    return tb.compareTo(ta);
  });
  return all;
}

// ── Admin audit log for this user ────────────────────────────────────────────

@riverpod
Stream<List<Map<String, dynamic>>> userAuditLog(
    UserAuditLogRef ref, String userId) {
  return FirebaseFirestore.instance
      .collection('admin_audit_log')
      .where('targetUserId', isEqualTo: userId)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
}
