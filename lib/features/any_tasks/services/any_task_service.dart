/// AnySkill — AnyTaskService (AnyTasks v14.0.0)
///
/// CRUD + streams for `any_tasks/*` and its subcollections. Escrow math
/// and payment release are delegated to `TaskEscrowService` (separate
/// file) to keep this module focused on read/write plumbing.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/any_task.dart';
import '../models/task_milestone.dart';
import '../models/task_response.dart';
import '../models/task_review.dart';

class AnyTaskService {
  AnyTaskService._();
  static final instance = AnyTaskService._();

  final _db = FirebaseFirestore.instance;

  // ═══════════════════════════════════════════════════════════════
  // TASK CRUD
  // ═══════════════════════════════════════════════════════════════

  CollectionReference<Map<String, dynamic>> get _tasks =>
      _db.collection('any_tasks');

  /// Publish a new task. Returns the created doc id.
  /// Default milestones are seeded based on category.
  Future<String> publishTask(AnyTask task) async {
    final ref = _tasks.doc();
    final batch = _db.batch();

    batch.set(ref, {
      ...task.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    final steps = kDefaultMilestones[task.category] ??
        kDefaultMilestones['other']!;
    for (var i = 0; i < steps.length; i++) {
      final mRef = ref.collection('milestones').doc();
      batch.set(mRef, TaskMilestone(title: steps[i], order: i).toMap());
    }

    await batch.commit();
    return ref.id;
  }

  Stream<AnyTask?> streamTask(String taskId) =>
      _tasks.doc(taskId).snapshots().map(
            (s) => s.exists ? AnyTask.fromMap(s.id, s.data()!) : null,
          );

  /// Open-tasks feed for providers — filtered by category whitelist.
  /// Sorted by urgency + recency. Client-side distance filter happens
  /// in the feed screen (requires GeoPoint math Firestore can't do).
  Stream<List<AnyTask>> streamOpenTasksForProvider({
    List<String>? categories,
    int limit = 50,
  }) {
    Query<Map<String, dynamic>> q = _tasks
        .where('status', isEqualTo: 'open')
        .orderBy('createdAt', descending: true)
        .limit(limit);
    if (categories != null && categories.isNotEmpty) {
      q = q.where('category', whereIn: categories.take(10).toList());
    }
    return q.snapshots().map(
          (s) => s.docs.map((d) => AnyTask.fromMap(d.id, d.data())).toList(),
        );
  }

  /// Client's own tasks across all statuses.
  Stream<List<AnyTask>> streamMyTasks(String clientId, {int limit = 50}) =>
      _tasks
          .where('clientId', isEqualTo: clientId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) =>
              s.docs.map((d) => AnyTask.fromMap(d.id, d.data())).toList());

  /// Active tasks for a provider (chosen + in progress).
  Stream<List<AnyTask>> streamProviderActiveTasks(
    String providerId, {
    int limit = 30,
  }) =>
      _tasks
          .where('selectedProviderId', isEqualTo: providerId)
          .where('status', whereIn: ['in_progress', 'proof_submitted'])
          .orderBy('acceptedAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) =>
              s.docs.map((d) => AnyTask.fromMap(d.id, d.data())).toList());

  Future<void> cancelTask(String taskId) async {
    await _tasks.doc(taskId).update({
      'status': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // RESPONSES
  // ═══════════════════════════════════════════════════════════════

  /// Provider submits an Accept or Counter-offer. Denormalizes the
  /// response count onto the parent task for FOMO badges.
  Future<String> submitResponse(TaskResponse r) async {
    final ref = _tasks.doc(r.taskId).collection('responses').doc();
    await _db.runTransaction((tx) async {
      final taskSnap = await tx.get(_tasks.doc(r.taskId));
      if (!taskSnap.exists) {
        throw StateError('task-not-found');
      }
      final data = taskSnap.data()!;
      if (data['status'] != 'open') {
        throw StateError('task-not-open');
      }
      if (data['clientId'] == r.providerId) {
        throw StateError('self-response-not-allowed');
      }
      tx.set(ref, {
        ...r.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.update(_tasks.doc(r.taskId), {
        'responseCount': FieldValue.increment(1),
      });
    });
    return ref.id;
  }

  Stream<List<TaskResponse>> streamResponses(String taskId) => _tasks
      .doc(taskId)
      .collection('responses')
      .orderBy('createdAt', descending: false)
      .limit(50)
      .snapshots()
      .map((s) =>
          s.docs.map((d) => TaskResponse.fromMap(d.id, d.data())).toList());

  // ═══════════════════════════════════════════════════════════════
  // MILESTONES
  // ═══════════════════════════════════════════════════════════════

  Stream<List<TaskMilestone>> streamMilestones(String taskId) => _tasks
      .doc(taskId)
      .collection('milestones')
      .orderBy('order')
      .snapshots()
      .map((s) =>
          s.docs.map((d) => TaskMilestone.fromMap(d.id, d.data())).toList());

  Future<void> completeMilestone({
    required String taskId,
    required String milestoneId,
    String? proofUrl,
  }) async {
    await _tasks
        .doc(taskId)
        .collection('milestones')
        .doc(milestoneId)
        .update({
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
      if (proofUrl != null) 'proofUrl': proofUrl,
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // PROOF SUBMISSION
  // ═══════════════════════════════════════════════════════════════

  Future<void> submitProof({
    required String taskId,
    String? proofUrl,
    String? proofText,
  }) async {
    await _tasks.doc(taskId).update({
      if (proofUrl != null) 'proofUrl': proofUrl,
      if (proofText != null) 'proofText': proofText,
      'status': 'proof_submitted',
      'proofSubmittedAt': FieldValue.serverTimestamp(),
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // REVIEWS
  // ═══════════════════════════════════════════════════════════════

  Future<void> submitReview(TaskReview r) async {
    await _tasks.doc(r.taskId).collection('reviews').add({
      ...r.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<TaskReview>> streamReviews(String taskId) => _tasks
      .doc(taskId)
      .collection('reviews')
      .orderBy('createdAt', descending: true)
      .limit(20)
      .snapshots()
      .map((s) =>
          s.docs.map((d) => TaskReview.fromMap(d.id, d.data())).toList());
}
