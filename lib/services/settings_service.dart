import 'package:cloud_firestore/cloud_firestore.dart';

/// Wrapper around the `system_settings/global` Firestore document.
///
/// All global UI settings (card scale, future toggles) are stored here
/// so any widget can stream them without knowing the collection path.
class SettingsService {
  SettingsService._();

  static final _ref = FirebaseFirestore.instance
      .collection('system_settings')
      .doc('global');

  /// Real-time stream of the global settings document.
  static Stream<DocumentSnapshot<Map<String, dynamic>>> get stream =>
      _ref.snapshots();

  /// Persist a new global category-card scale (0.6 – 1.5).
  static Future<void> setCategoryCardScale(double scale) =>
      _ref.set({'categoryCardScale': scale}, SetOptions(merge: true));

  /// Extract card scale from a settings snapshot with safe default.
  static double cardScaleFrom(DocumentSnapshot<Map<String, dynamic>>? snap) =>
      ((snap?.data()?['categoryCardScale']) as num? ?? 1.0).toDouble();
}
