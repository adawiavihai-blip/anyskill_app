import 'package:cloud_functions/cloud_functions.dart';

// ── Result types ──────────────────────────────────────────────────────────────

enum CategoryAction { match, newPending }

class CategoryResult {
  final CategoryAction action;

  // action == match
  final String? categoryId;
  final String? categoryName;

  // action == newPending
  final String? pendingId;
  final String? suggestedCategoryName;

  // both
  final double confidence;
  final String reasoning;

  const CategoryResult._({
    required this.action,
    required this.confidence,
    required this.reasoning,
    this.categoryId,
    this.categoryName,
    this.pendingId,
    this.suggestedCategoryName,
  });

  factory CategoryResult.fromMap(Map<String, dynamic> m) {
    final action = m['action'] == 'match'
        ? CategoryAction.match
        : CategoryAction.newPending;
    return CategoryResult._(
      action:                action,
      confidence:            (m['confidence'] as num? ?? 0).toDouble(),
      reasoning:             m['reasoning']             as String? ?? '',
      categoryId:            m['categoryId']            as String?,
      categoryName:          m['categoryName']          as String?,
      pendingId:             m['pendingId']             as String?,
      suggestedCategoryName: m['suggestedCategoryName'] as String?,
    );
  }
}

// ── Service ───────────────────────────────────────────────────────────────────

class CategoryAiService {
  CategoryAiService._();

  static final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Sends a provider's service description to the AI engine.
  /// Returns a [CategoryResult] — either an auto-matched category or a
  /// "pending review" token the provider sees while admin reviews.
  static Future<CategoryResult> categorize(String serviceDescription) async {
    final callable = _functions.httpsCallable('categorizeprovider');
    final result   = await callable.call<Map<String, dynamic>>({
      'serviceDescription': serviceDescription,
    });
    return CategoryResult.fromMap(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  /// Admin-only: approve or reject a pending category.
  /// [action] must be `'approve'` or `'reject'`.
  static Future<void> reviewPending({
    required String pendingId,
    required String action, // 'approve' | 'reject'
  }) async {
    final callable = _functions.httpsCallable('approvecategory');
    await callable.call<Map<String, dynamic>>({
      'pendingId': pendingId,
      'action':    action,
    });
  }
}
