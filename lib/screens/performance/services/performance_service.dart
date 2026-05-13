import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/performance_metric.dart';

/// Reads the snapshot produced by the `updateMetricsSnapshot` Cloud Function
/// every 5 minutes. The doc lives at `performance_metrics/current`.
///
/// Falls back to an empty metric if the doc does not exist yet (pre-CF-deploy).
class PerformanceService {
  PerformanceService._();
  static final instance = PerformanceService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Live stream of the current metrics snapshot. Every widget on the
  /// Performance tab should share this stream (read via a single
  /// `StreamBuilder` at the root).
  Stream<PerformanceMetric> streamCurrent() {
    return _db.collection('performance_metrics').doc('current').snapshots().map(
      (snap) {
        final data = snap.data();
        if (data == null) return PerformanceMetric.empty();
        return PerformanceMetric.fromMap(data);
      },
    );
  }

  /// One-shot read of the current snapshot. Used by the Nova chat service
  /// to assemble the context prompt.
  Future<PerformanceMetric> readCurrent() async {
    final snap =
        await _db.collection('performance_metrics').doc('current').get();
    final data = snap.data();
    if (data == null) return PerformanceMetric.empty();
    return PerformanceMetric.fromMap(data);
  }
}
