/// AnySkill — Pet Stay Service (Pet Stay Tracker v13.0.0)
///
/// Helpers around the `jobs/{jobId}/petStay/data` snapshot.
/// The initial snapshot is written INSIDE the same `runTransaction` that
/// creates the job doc — see [writeInitialSnapshotInTransaction].
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/pet_stay.dart';
import '../models/schedule_item.dart';

class PetStayService {
  PetStayService._();
  static final instance = PetStayService._();

  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> dataRef(String jobId) =>
      _db.collection('jobs').doc(jobId).collection('petStay').doc('data');

  /// Writes the snapshot inside an existing transaction. Caller must pass
  /// the same `tx` they're using for the job doc create — guarantees both
  /// docs land atomically (or both fail).
  void writeInitialSnapshotInTransaction({
    required Transaction tx,
    required String jobId,
    required PetStay snapshot,
  }) {
    tx.set(dataRef(jobId), {
      ...snapshot.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<PetStay?> stream(String jobId) =>
      dataRef(jobId).snapshots().map((d) {
        if (!d.exists) return null;
        return PetStay.fromMap(d.data()!);
      });

  Future<PetStay?> get(String jobId) async {
    final d = await dataRef(jobId).get();
    if (!d.exists) return null;
    return PetStay.fromMap(d.data()!);
  }

  /// Called by the customer after editing their dog profile — pushes the
  /// fresh master profile Map into `petStay/data.dogSnapshot` so the
  /// provider sees the updated info on the live booking. Firestore rules
  /// allow the customer to touch only `dogSnapshot` (plus rating/review).
  Future<void> updateDogSnapshot({
    required String jobId,
    required Map<String, dynamic> dogSnapshot,
  }) async {
    await dataRef(jobId).update({'dogSnapshot': dogSnapshot});
  }

  // ── Schedule (Step 5) ────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> scheduleCol(String jobId) =>
      dataRef(jobId).collection('schedule');

  /// Writes every schedule item inside an existing transaction. Must be
  /// called from the same `runTransaction` that creates the parent job +
  /// petStay doc.
  ///
  /// **Do NOT call for large stays** — Firestore transactions cap at
  /// 500 total ops (reads + writes combined). Use
  /// [writeScheduleItemsBatched] for anything >~80 days of routine.
  void writeScheduleItemsInTransaction({
    required Transaction tx,
    required String jobId,
    required List<ScheduleItem> items,
  }) {
    final col = scheduleCol(jobId);
    for (final it in items) {
      tx.set(col.doc(), it.toMap());
    }
  }

  /// Writes schedule items in chunks of 400 via WriteBatch — safe for
  /// arbitrarily long pension stays. Called AFTER the booking transaction
  /// commits. Any failure is logged but does not roll back the booking;
  /// an empty/partial schedule is acceptable graceful degradation.
  Future<void> writeScheduleItemsBatched({
    required String jobId,
    required List<ScheduleItem> items,
  }) async {
    if (items.isEmpty) return;
    final col = scheduleCol(jobId);
    const chunkSize = 400;
    for (var i = 0; i < items.length; i += chunkSize) {
      final end = (i + chunkSize < items.length) ? i + chunkSize : items.length;
      final batch = _db.batch();
      for (final it in items.sublist(i, end)) {
        batch.set(col.doc(), it.toMap());
      }
      await batch.commit();
    }
  }

  Stream<List<ScheduleItem>> streamSchedule(String jobId) =>
      scheduleCol(jobId)
          .orderBy('dayKey')
          .orderBy('time')
          .orderBy('sortOrder')
          .limit(500)
          .snapshots()
          .map((snap) => snap.docs
              .map((d) => ScheduleItem.fromMap(d.id, d.data()))
              .toList());

  /// Marks a schedule item completed / uncompleted.
  /// Caller must be the expert on the parent job — enforced by rules.
  Future<void> toggleScheduleItem({
    required String jobId,
    required String itemId,
    required bool completed,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await scheduleCol(jobId).doc(itemId).update({
      'completed': completed,
      'completedAt':
          completed ? FieldValue.serverTimestamp() : FieldValue.delete(),
      'completedBy': completed ? uid : FieldValue.delete(),
    });
  }

  // ── Rating (Step 8) ──────────────────────────────────────────────────

  /// Customer-only end-of-stay rating + free-text review. NO TIP.
  /// Rules accept either party on update; we trust the caller is the
  /// customer because only the owner's UI calls this method.
  Future<void> submitRating({
    required String jobId,
    required double rating,
    required String reviewText,
  }) async {
    await dataRef(jobId).update({
      'rating': rating,
      'reviewText': reviewText.trim(),
      'ratedAt': FieldValue.serverTimestamp(),
      'status': 'completed',
    });
  }
}
