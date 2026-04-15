/// AnySkill — PetStay Snapshot Model (Pet Stay Tracker v13.0.0)
///
/// Lives at `jobs/{jobId}/petStay/data` and is created atomically inside
/// the same transaction that creates the job doc. Frozen at booking time:
/// the `dogSnapshot` is a deep copy of the customer's dog profile from
/// `users/{ownerId}/dogProfiles/{dogId}` so subsequent owner edits don't
/// retroactively affect in-flight stays.
///
/// Schedule items + feed updates are siblings under
/// `jobs/{jobId}/petStay/data/{schedule|updates}/...` (added in Step 5).
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'dog_profile.dart';

class PetStay {
  /// Reference back to the live profile (for "view current profile" UX).
  /// Null is allowed — the snapshot is the source of truth.
  final String? dogProfileId;

  /// Frozen copy of the dog profile at booking time. Provider reads from
  /// here, NOT from `users/{ownerId}/dogProfiles/{dogId}`.
  final Map<String, dynamic> dogSnapshot;

  /// Denormalized for rules / quick reads (avoids extra `get(/jobs/...)`).
  final String customerId;
  final String expertId;

  /// Date range. For dog-walker: `startDate == endDate`, `totalNights == 0`.
  final DateTime startDate;
  final DateTime endDate;
  final int totalNights;

  /// Aggregated counters — updated by provider in transactions.
  final int totalWalks;
  final double totalDistanceKm;
  final int totalPhotos;
  final int totalVideos;
  final int totalReports;

  /// 'upcoming' | 'active' | 'completed' | 'cancelled'
  final String status;

  /// End-of-stay only. NO TIP — rating + text review only.
  final double? rating;
  final String? reviewText;
  final DateTime? ratedAt;

  /// Derived gates (cached for fast reads).
  final bool isPension;
  final bool isDogWalker;

  const PetStay({
    this.dogProfileId,
    required this.dogSnapshot,
    required this.customerId,
    required this.expertId,
    required this.startDate,
    required this.endDate,
    required this.totalNights,
    this.totalWalks = 0,
    this.totalDistanceKm = 0.0,
    this.totalPhotos = 0,
    this.totalVideos = 0,
    this.totalReports = 0,
    this.status = 'upcoming',
    this.rating,
    this.reviewText,
    this.ratedAt,
    required this.isPension,
    required this.isDogWalker,
  });

  /// Build a fresh snapshot at booking time.
  factory PetStay.initial({
    required DogProfile dog,
    required String customerId,
    required String expertId,
    required DateTime startDate,
    required DateTime endDate,
    required bool isPension,
    required bool isDogWalker,
  }) {
    final nights = endDate.difference(startDate).inDays.clamp(0, 365);
    return PetStay(
      dogProfileId: dog.id,
      dogSnapshot: dog.toMap(),
      customerId: customerId,
      expertId: expertId,
      startDate: startDate,
      endDate: endDate,
      totalNights: nights,
      isPension: isPension,
      isDogWalker: isDogWalker,
    );
  }

  Map<String, dynamic> toMap() => {
        if (dogProfileId != null) 'dogProfileId': dogProfileId,
        'dogSnapshot': dogSnapshot,
        'customerId': customerId,
        'expertId': expertId,
        'startDate': Timestamp.fromDate(startDate),
        'endDate': Timestamp.fromDate(endDate),
        'totalNights': totalNights,
        'totalWalks': totalWalks,
        'totalDistanceKm': totalDistanceKm,
        'totalPhotos': totalPhotos,
        'totalVideos': totalVideos,
        'totalReports': totalReports,
        'status': status,
        if (rating != null) 'rating': rating,
        if (reviewText != null) 'reviewText': reviewText,
        if (ratedAt != null) 'ratedAt': Timestamp.fromDate(ratedAt!),
        'isPension': isPension,
        'isDogWalker': isDogWalker,
      };

  factory PetStay.fromMap(Map<String, dynamic> d) => PetStay(
        dogProfileId: d['dogProfileId'] as String?,
        dogSnapshot:
            Map<String, dynamic>.from(d['dogSnapshot'] as Map? ?? const {}),
        customerId: (d['customerId'] ?? '') as String,
        expertId: (d['expertId'] ?? '') as String,
        startDate: (d['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
        endDate: (d['endDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
        totalNights: (d['totalNights'] as num?)?.toInt() ?? 0,
        totalWalks: (d['totalWalks'] as num?)?.toInt() ?? 0,
        totalDistanceKm: (d['totalDistanceKm'] as num?)?.toDouble() ?? 0.0,
        totalPhotos: (d['totalPhotos'] as num?)?.toInt() ?? 0,
        totalVideos: (d['totalVideos'] as num?)?.toInt() ?? 0,
        totalReports: (d['totalReports'] as num?)?.toInt() ?? 0,
        status: (d['status'] ?? 'upcoming') as String,
        rating: (d['rating'] as num?)?.toDouble(),
        reviewText: d['reviewText'] as String?,
        ratedAt: (d['ratedAt'] as Timestamp?)?.toDate(),
        isPension: (d['isPension'] ?? false) as bool,
        isDogWalker: (d['isDogWalker'] ?? false) as bool,
      );
}
