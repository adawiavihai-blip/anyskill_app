/// AnySkill — Schedule Item Model (Pet Stay Tracker v13.0.0)
///
/// Lives at `jobs/{jobId}/petStay/data/schedule/{itemId}`.
/// Generated at booking time from the dog's routine × stay duration
/// (see [ScheduleGenerator]). Provider marks items completed during the
/// stay; both parties read.
///
/// `customerId` / `expertId` are duplicated on each item so Firestore
/// rules can authorize WITHOUT a cross-doc `get()` — necessary because
/// schedule items are created in the same transaction as the parent job,
/// when the job doc isn't yet committed.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

enum ScheduleType { feed, walk, medication, play, sleep }

const kScheduleTypes = ['feed', 'walk', 'medication', 'play', 'sleep'];

const Map<String, String> kScheduleTypeLabels = {
  'feed': 'ארוחה',
  'walk': 'הליכון',
  'medication': 'תרופה',
  'play': 'משחק',
  'sleep': 'שינה',
};

class ScheduleItem {
  final String? id;

  /// "YYYY-MM-DD" — which day of the stay this item belongs to.
  final String dayKey;

  /// "HH:MM" 24-hour.
  final String time;

  /// One of [kScheduleTypes].
  final String type;

  final String title;
  final String description;

  final bool completed;
  final DateTime? completedAt;
  final String? completedBy;

  /// Within a single day, items are sorted by this value (or by time if tied).
  final int sortOrder;

  /// Duplicated from the parent job for Firestore rules.
  final String customerId;
  final String expertId;

  const ScheduleItem({
    this.id,
    required this.dayKey,
    required this.time,
    required this.type,
    required this.title,
    required this.description,
    required this.sortOrder,
    required this.customerId,
    required this.expertId,
    this.completed = false,
    this.completedAt,
    this.completedBy,
  });

  Map<String, dynamic> toMap() => {
        'dayKey': dayKey,
        'time': time,
        'type': type,
        'title': title,
        'description': description,
        'completed': completed,
        if (completedAt != null)
          'completedAt': Timestamp.fromDate(completedAt!),
        if (completedBy != null) 'completedBy': completedBy,
        'sortOrder': sortOrder,
        'customerId': customerId,
        'expertId': expertId,
      };

  factory ScheduleItem.fromMap(String id, Map<String, dynamic> d) =>
      ScheduleItem(
        id: id,
        dayKey: (d['dayKey'] ?? '') as String,
        time: (d['time'] ?? '00:00') as String,
        type: (d['type'] ?? 'feed') as String,
        title: (d['title'] ?? '') as String,
        description: (d['description'] ?? '') as String,
        completed: (d['completed'] ?? false) as bool,
        completedAt: (d['completedAt'] as Timestamp?)?.toDate(),
        completedBy: d['completedBy'] as String?,
        sortOrder: (d['sortOrder'] as num?)?.toInt() ?? 0,
        customerId: (d['customerId'] ?? '') as String,
        expertId: (d['expertId'] ?? '') as String,
      );
}

String dayKeyOf(DateTime d) =>
    '${d.year.toString().padLeft(4, "0")}-'
    '${d.month.toString().padLeft(2, "0")}-'
    '${d.day.toString().padLeft(2, "0")}';
