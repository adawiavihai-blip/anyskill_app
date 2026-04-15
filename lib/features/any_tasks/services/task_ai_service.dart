/// AnySkill — TaskAiService (AnyTasks v14.0.0)
///
/// Thin wrapper around the `generateTaskTags` Cloud Function. Given a
/// task title + description, returns suggested category + urgency +
/// Hebrew tags so the publish form can auto-fill (psychology hook —
/// reduces friction on the hardest step).
library;

import 'package:cloud_functions/cloud_functions.dart';

class TaskAiSuggestion {
  final String suggestedCategory;
  final String suggestedUrgency;
  final List<String> tags;

  const TaskAiSuggestion({
    required this.suggestedCategory,
    required this.suggestedUrgency,
    required this.tags,
  });
}

class TaskAiService {
  TaskAiService._();
  static final instance = TaskAiService._();

  Future<TaskAiSuggestion?> suggest({
    required String title,
    required String description,
  }) async {
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('generateTaskTags')
          .call({'title': title, 'description': description});
      final data = Map<String, dynamic>.from(res.data as Map);
      return TaskAiSuggestion(
        suggestedCategory:
            (data['suggestedCategory'] ?? 'other') as String,
        suggestedUrgency:
            (data['suggestedUrgency'] ?? 'flexible') as String,
        tags: List<String>.from(data['tags'] ?? const []),
      );
    } catch (_) {
      return null;
    }
  }
}
