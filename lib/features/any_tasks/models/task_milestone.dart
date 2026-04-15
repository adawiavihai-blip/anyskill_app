/// AnySkill — TaskMilestone Model (AnyTasks v14.0.0)
///
/// Lives at `any_tasks/{taskId}/milestones/{milestoneId}`.
/// Provider ticks each step as they progress. Client sees a vertical
/// stepper with goal-gradient psychology (progress to goal drives
/// completion per spec section 4.4).
///
/// For v1 we generate a default 3-step milestone set at task creation
/// time based on the category (see `default_milestones.dart`). In the
/// future this can be provider-customizable at accept time.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

class TaskMilestone {
  final String? id;
  final String title;
  final int order;

  /// 'pending' | 'completed'
  final String status;
  final DateTime? completedAt;

  /// Optional per-step proof (photo + timestamp).
  final String? proofUrl;

  const TaskMilestone({
    this.id,
    required this.title,
    required this.order,
    this.status = 'pending',
    this.completedAt,
    this.proofUrl,
  });

  bool get isDone => status == 'completed';

  factory TaskMilestone.fromMap(String id, Map<String, dynamic> d) =>
      TaskMilestone(
        id: id,
        title: (d['title'] ?? '') as String,
        order: (d['order'] as num?)?.toInt() ?? 0,
        status: (d['status'] ?? 'pending') as String,
        completedAt: (d['completedAt'] as Timestamp?)?.toDate(),
        proofUrl: d['proofUrl'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'title': title,
        'order': order,
        'status': status,
        if (completedAt != null) 'completedAt': Timestamp.fromDate(completedAt!),
        if (proofUrl != null) 'proofUrl': proofUrl,
      };
}

/// Default 3-step milestone sets per category. Keeps the goal-gradient
/// narrow enough to feel achievable (spec: 2–4 steps is the sweet spot).
const Map<String, List<String>> kDefaultMilestones = {
  'delivery': ['איסוף מהמוצא', 'בדרך ליעד', 'נמסר בהצלחה'],
  'cleaning': ['הגעה למקום', 'ניקיון בעיצומו', 'סיום וצילום'],
  'handyman': ['הגעה וסקירה', 'ביצוע התיקון', 'בדיקה וצילום'],
  'moving': ['הגעה לבית המקור', 'העמסה ונסיעה', 'פריקה ביעד'],
  'pet_care': ['פגישה עם החיה', 'ביצוע השירות', 'תיעוד וסיום'],
  'tech_support': ['איבחון הבעיה', 'ביצוע התיקון', 'בדיקה ומסירה'],
  'tutoring': ['פתיחת השיעור', 'מהלך השיעור', 'סיכום ומשוב'],
  'other': ['התחלת העבודה', 'ביצוע', 'סיום ותיעוד'],
};
