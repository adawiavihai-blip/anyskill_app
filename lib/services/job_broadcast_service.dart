/// AnySkill — Job Broadcast Service
///
/// Handles urgent job broadcasts with first-come-first-served claim logic.
///
/// Flow:
///   1. Client posts urgent request -> broadcastUrgentJob()
///   2. Matching online providers in radius are notified
///   3. First provider to tap "תפוס עכשיו" wins via atomic claimJob()
///   4. All other providers see "המשרה כבר נתפסה" (already taken)
///
/// Uses a separate `job_broadcasts` collection (not `job_requests`) because
/// the claim model is fundamentally different from the interest-expression
/// model used by regular job requests.
library;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class JobBroadcastService {
  JobBroadcastService._();

  static final _db = FirebaseFirestore.instance;

  // ── Constants ──────────────────────────────────────────────────────────────

  /// Broadcast expires after this many minutes if unclaimed.
  static const int broadcastExpiryMinutes = 30;

  /// Max distance (meters) to notify providers. 15 km radius.
  static const double notifyRadiusMeters = 15000.0;

  /// Max providers to notify per broadcast (cost control).
  static const int maxNotifiedProviders = 50;

  // ── Broadcast Creation ─────────────────────────────────────────────────────

  /// Creates a broadcast for an urgent job request and notifies matching
  /// online providers within [notifyRadiusMeters].
  ///
  /// [sourceJobRequestId] links back to the original `job_requests` doc.
  /// Returns the broadcast document ID.
  /// Max broadcasts per user per hour (velocity check, H6 audit fix).
  static const int _maxBroadcastsPerHour = 10;

  static Future<String> broadcastUrgentJob({
    required String clientId,
    required String clientName,
    required String category,
    required String description,
    required String location,
    String? sourceJobRequestId,
    double? clientLat,
    double? clientLng,
  }) async {
    // H6 velocity check: max 10 broadcasts per hour per user
    final oneHourAgo = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(hours: 1)));
    final recentSnap = await _db
        .collection('job_broadcasts')
        .where('clientId', isEqualTo: clientId)
        .where('createdAt', isGreaterThan: oneHourAgo)
        .limit(_maxBroadcastsPerHour + 1)
        .get();
    if (recentSnap.size >= _maxBroadcastsPerHour) {
      throw Exception('הגעת למגבלת הפרסומים ($_maxBroadcastsPerHour/שעה). נסה שוב מאוחר יותר.');
    }

    final expiresAt = Timestamp.fromDate(
      DateTime.now().add(Duration(minutes: broadcastExpiryMinutes)),
    );

    // ── Create broadcast document ─────────────────────────────────────────
    final docRef = await _db.collection('job_broadcasts').add({
      'clientId': clientId,
      'clientName': clientName,
      'category': category,
      'description': description,
      'location': location,
      'status': 'open',
      'urgency': 'urgent',
      'claimedBy': null,
      'claimedByName': null,
      'claimedAt': null,
      'clientLat': clientLat,
      'clientLng': clientLng,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': expiresAt,
      'notifiedCount': 0,
      'sourceJobRequestId': sourceJobRequestId,
    });

    // ── Find and notify matching providers ────────────────────────────────
    final notifiedCount = await _notifyMatchingProviders(
      broadcastId: docRef.id,
      clientId: clientId,
      category: category,
      clientLat: clientLat,
      clientLng: clientLng,
    );

    // Update notified count
    await docRef.update({'notifiedCount': notifiedCount});

    return docRef.id;
  }

  /// Queries online providers in the category, filters by distance,
  /// and sends in-app notifications. Returns the count notified.
  static Future<int> _notifyMatchingProviders({
    required String broadcastId,
    required String clientId,
    required String category,
    required double? clientLat,
    required double? clientLng,
  }) async {
    // Query online providers in this category
    final snap = await _db
        .collection('users')
        .where('isProvider', isEqualTo: true)
        .where('isOnline', isEqualTo: true)
        .where('serviceType', isEqualTo: category)
        .limit(100)
        .get();

    int count = 0;
    final batch = _db.batch();

    for (final doc in snap.docs) {
      // Skip the requesting client
      if (doc.id == clientId) continue;

      // Skip hidden/demo
      final data = doc.data();
      if (data['isHidden'] == true || data['isDemo'] == true) continue;

      // Distance filter (if client has GPS)
      if (clientLat != null && clientLng != null) {
        final provLat = (data['latitude'] as num?)?.toDouble();
        final provLng = (data['longitude'] as num?)?.toDouble();
        if (provLat != null && provLng != null) {
          final dist = Geolocator.distanceBetween(
              clientLat, clientLng, provLat, provLng);
          if (dist > notifyRadiusMeters) continue;
        }
      }

      // Create notification
      final notifRef = _db.collection('notifications').doc();
      batch.set(notifRef, {
        'userId': doc.id,
        'title': '🚨 עבודה דחופה בקטגוריה שלך!',
        'body': '$clientId צריך/ה עזרה דחופה ב"$category". הראשון שתופס — מקבל!',
        'type': 'broadcast_urgent',
        'relatedUserId': clientId,
        'category': category,
        'broadcastId': broadcastId,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      count++;
      if (count >= maxNotifiedProviders) break;
    }

    if (count > 0) {
      await batch.commit();
    }

    return count;
  }

  // ── Atomic Claim ───────────────────────────────────────────────────────────

  /// Attempts to claim a broadcast for the given provider.
  ///
  /// Uses a Firestore transaction for first-writer-wins atomicity.
  /// Returns a [ClaimResult] with the outcome.
  static Future<ClaimResult> claimJob({
    required String broadcastId,
    required String providerId,
    required String providerName,
  }) async {
    try {
      final docRef = _db.collection('job_broadcasts').doc(broadcastId);

      final result = await _db.runTransaction<ClaimResult>((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) {
          return ClaimResult.error('המשרה לא נמצאה');
        }

        final data = snap.data()!;
        final status = data['status'] as String? ?? '';
        final clientId = data['clientId'] as String? ?? '';

        // ── Already claimed by someone else ──────────────────────────────
        if (status == 'claimed') {
          final claimedByName = data['claimedByName'] as String? ?? 'מישהו';
          return ClaimResult.taken(claimedByName);
        }

        // ── Expired ──────────────────────────────────────────────────────
        if (status == 'expired') {
          return ClaimResult.error('המשרה פגה תוקף');
        }

        // ── Check expiry time ────────────────────────────────────────────
        final expiresAt = data['expiresAt'] as Timestamp?;
        if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
          tx.update(docRef, {'status': 'expired'});
          return ClaimResult.error('המשרה פגה תוקף');
        }

        // ── Anti-fraud: provider can't claim their own broadcast ─────────
        if (providerId == clientId) {
          return ClaimResult.error('לא ניתן לתפוס משרה שפרסמת בעצמך');
        }

        // ── Status must be 'open' ────────────────────────────────────────
        if (status != 'open') {
          return ClaimResult.error('המשרה אינה זמינה');
        }

        // ── Claim it! ────────────────────────────────────────────────────
        tx.update(docRef, {
          'status': 'claimed',
          'claimedBy': providerId,
          'claimedByName': providerName,
          'claimedAt': FieldValue.serverTimestamp(),
        });

        return ClaimResult.success(clientId);
      });

      // ── Post-claim side effects (outside transaction) ──────────────────
      if (result.isSuccess) {
        final broadcastDoc = await docRef.get();
        final data = broadcastDoc.data() ?? {};
        final clientId = data['clientId'] as String? ?? '';
        final category = data['category'] as String? ?? '';

        // Notify the client
        await _db.collection('notifications').add({
          'userId': clientId,
          'title': '✅ מומחה תפס את המשרה שלך!',
          'body': '$providerName קיבל/ה את הבקשה הדחופה שלך ב"$category".',
          'type': 'broadcast_claimed',
          'relatedUserId': providerId,
          'broadcastId': broadcastId,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Also close the source job_request if linked
        final sourceId = data['sourceJobRequestId'] as String?;
        if (sourceId != null && sourceId.isNotEmpty) {
          await _db.collection('job_requests').doc(sourceId).update({
            'status': 'closed',
            'claimedByBroadcast': broadcastId,
          });
        }
      }

      return result;
    } catch (e) {
      debugPrint('[JobBroadcastService] claimJob error: $e');
      return ClaimResult.error('שגיאה: $e');
    }
  }

  // ── Query Helpers ──────────────────────────────────────────────────────────

  /// Streams open broadcasts in the given category (for opportunities screen).
  static Stream<QuerySnapshot> streamOpenBroadcasts(String category) {
    return _db
        .collection('job_broadcasts')
        .where('status', isEqualTo: 'open')
        .where('category', isEqualTo: category)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots();
  }

  /// Streams ALL active broadcasts for admin view (open + recently claimed).
  static Stream<QuerySnapshot> streamAllActive() {
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(hours: 2)),
    );
    return _db
        .collection('job_broadcasts')
        .where('createdAt', isGreaterThan: cutoff)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
  }

  /// Single broadcast stream (for real-time status updates on a claim card).
  static Stream<DocumentSnapshot> streamBroadcast(String broadcastId) {
    return _db.collection('job_broadcasts').doc(broadcastId).snapshots();
  }
}

// ── Claim Result ─────────────────────────────────────────────────────────────

enum ClaimStatus { success, taken, error }

class ClaimResult {
  final ClaimStatus status;
  final String message;

  /// The client ID (only set on success, for opening chat).
  final String? clientId;

  const ClaimResult._(this.status, this.message, {this.clientId});

  factory ClaimResult.success(String clientId) =>
      ClaimResult._(ClaimStatus.success, 'תפסת את המשרה!', clientId: clientId);

  factory ClaimResult.taken(String claimedByName) =>
      ClaimResult._(ClaimStatus.taken, 'המשרה כבר נתפסה ע"י $claimedByName');

  factory ClaimResult.error(String msg) =>
      ClaimResult._(ClaimStatus.error, msg);

  bool get isSuccess => status == ClaimStatus.success;
  bool get isTaken => status == ClaimStatus.taken;
}
