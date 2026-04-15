/// AnySkill — PetUpdate Model (Pet Stay Tracker v13.0.0)
///
/// Lives at `jobs/{jobId}/petStay/data/updates/{updateId}` — the feed
/// timeline the owner sees. Created by the provider when something
/// noteworthy happens (pee/poop marker, walk completed, photo, note,
/// daily report). Step 6 writes pee/poop/walk_completed. Step 7 extends
/// with media (photo/video/note). Step 10 adds daily_report. Step 9
/// adds reactions + replies.
///
/// Bootstrap-safe: `customerId` + `expertId` are duplicated so rules
/// don't need a cross-doc `get()` (created during the booking tx and
/// by the provider at runtime — both stable callers).
library;

import 'package:cloud_firestore/cloud_firestore.dart';

/// All supported types — keep in sync with rendering in Step 7+.
const Set<String> kPetUpdateTypes = {
  'walk_started',
  'walk_completed',
  'pee',
  'poop',
  'photo',
  'video',
  'note',
  'daily_report',
  'food',
  'medication',
};

class PetUpdate {
  final String? id;
  final String type;
  final String providerId;
  final DateTime timestamp;

  /// Rules + quick-display denormalization.
  final String customerId;
  final String expertId;

  // Content (optional by type)
  final String? text;
  final String? mediaUrl;
  final String? mediaType; // "image" | "video" | null
  final String? walkId;
  final String? dayKey;

  // Geo for pee/poop markers (also stored on dog_walks.markers).
  final double? lat;
  final double? lng;

  // Walk-completed inline stats (so feed can render without another read).
  final num? distanceKm;
  final int? durationSeconds;
  final int? steps;
  final String? pacePerKm;

  // daily_report payload (Step 10).
  final Map<String, dynamic>? reportData;

  // Interactions (Step 9). Empty at create.
  final Map<String, String> reactions;
  final List<Map<String, dynamic>> replies;

  const PetUpdate({
    this.id,
    required this.type,
    required this.providerId,
    required this.timestamp,
    required this.customerId,
    required this.expertId,
    this.text,
    this.mediaUrl,
    this.mediaType,
    this.walkId,
    this.dayKey,
    this.lat,
    this.lng,
    this.distanceKm,
    this.durationSeconds,
    this.steps,
    this.pacePerKm,
    this.reportData,
    this.reactions = const {},
    this.replies = const [],
  });

  Map<String, dynamic> toMap() => {
        'type': type,
        'providerId': providerId,
        'timestamp': Timestamp.fromDate(timestamp),
        'customerId': customerId,
        'expertId': expertId,
        if (text != null) 'text': text,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        if (mediaType != null) 'mediaType': mediaType,
        if (walkId != null) 'walkId': walkId,
        if (dayKey != null) 'dayKey': dayKey,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (distanceKm != null) 'distanceKm': distanceKm,
        if (durationSeconds != null) 'durationSeconds': durationSeconds,
        if (steps != null) 'steps': steps,
        if (pacePerKm != null) 'pacePerKm': pacePerKm,
        if (reportData != null) 'reportData': reportData,
        'reactions': reactions,
        'replies': replies,
      };

  factory PetUpdate.fromMap(String id, Map<String, dynamic> d) => PetUpdate(
        id: id,
        type: (d['type'] ?? 'note') as String,
        providerId: (d['providerId'] ?? '') as String,
        timestamp: (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
        customerId: (d['customerId'] ?? '') as String,
        expertId: (d['expertId'] ?? '') as String,
        text: d['text'] as String?,
        mediaUrl: d['mediaUrl'] as String?,
        mediaType: d['mediaType'] as String?,
        walkId: d['walkId'] as String?,
        dayKey: d['dayKey'] as String?,
        lat: (d['lat'] as num?)?.toDouble(),
        lng: (d['lng'] as num?)?.toDouble(),
        distanceKm: d['distanceKm'] as num?,
        durationSeconds: (d['durationSeconds'] as num?)?.toInt(),
        steps: (d['steps'] as num?)?.toInt(),
        pacePerKm: d['pacePerKm'] as String?,
        reportData: d['reportData'] == null
            ? null
            : Map<String, dynamic>.from(d['reportData'] as Map),
        reactions: Map<String, String>.from(d['reactions'] ?? const {}),
        replies: (d['replies'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
}
