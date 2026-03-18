
import 'package:cloud_functions/cloud_functions.dart';

// ── Result types ──────────────────────────────────────────────────────────────

enum CategoryAction { match, autoCreated }

class CategoryResult {
  final CategoryAction action;

  /// Firestore category doc ID (present for both match and autoCreated).
  final String? categoryId;
  final String? categoryName;

  /// Firestore subcategory doc ID — only set for autoCreated.
  final String? subCategoryId;
  final String? subCategoryName;

  final double confidence;
  final String reasoning;

  const CategoryResult._({
    required this.action,
    required this.confidence,
    required this.reasoning,
    this.categoryId,
    this.categoryName,
    this.subCategoryId,
    this.subCategoryName,
  });

  factory CategoryResult.fromMap(Map<String, dynamic> m) {
    final action = m['action'] == 'match'
        ? CategoryAction.match
        : CategoryAction.autoCreated; // "new" and "auto_created" both map here
    return CategoryResult._(
      action:          action,
      confidence:      (m['confidence'] as num? ?? 0).toDouble(),
      reasoning:       m['reasoning']       as String? ?? '',
      categoryId:      m['categoryId']      as String?,
      categoryName:    (m['categoryName'] ?? m['suggestedCategoryName']) as String?,
      subCategoryId:   m['subCategoryId']   as String?,
      subCategoryName: m['subCategoryName'] as String?,
    );
  }
}

// ── Typed exception ───────────────────────────────────────────────────────────

class CategoryAiException implements Exception {
  final String message;
  final String code;
  const CategoryAiException(this.message, {required this.code});
  @override
  String toString() => message;
}

// ── Service ───────────────────────────────────────────────────────────────────

class CategoryAiService {
  CategoryAiService._();

  static final _fn = FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Sends a provider's service description to the AI engine.
  ///
  /// Throws [CategoryAiException] with a human-readable Hebrew message for
  /// every known failure mode (not deployed, secret missing, unauthenticated…).
  static Future<CategoryResult> categorize(String serviceDescription) async {
    try {
      final callable = _fn.httpsCallable(
        'categorizeprovider',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final result = await callable.call<Map<String, dynamic>>({
        'serviceDescription': serviceDescription,
      });
      return CategoryResult.fromMap(
        Map<String, dynamic>.from(result.data as Map),
      );
    } on FirebaseFunctionsException catch (e) {
      throw CategoryAiException(_friendlyMessage(e), code: e.code);
    } catch (e) {
      throw CategoryAiException(
        'שגיאה לא צפויה בסיווג: $e',
        code: 'unknown',
      );
    }
  }

  /// Called on 'Create Profile' — creates/finds category + subcategory in
  /// Firestore (via Admin SDK), updates the user doc, writes admin_log, sends email.
  /// Must be called AFTER FirebaseAuth user is created (requires auth).
  static Future<({String categoryId, String? subCategoryId})> finalizeSetup({
    required String categoryName,
    String? subCategoryName,
    String? matchedCategoryId, // pass when action == match
    String serviceDescription = '',
    double confidence = 0,
    String reasoning = '',
  }) async {
    try {
      final callable = _fn.httpsCallable('finalizecategorysetup',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final result = await callable.call<Map<String, dynamic>>({
        'categoryName':     categoryName,
        if (subCategoryName    != null) 'subCategoryName':    subCategoryName,
        if (matchedCategoryId  != null) 'matchedCategoryId':  matchedCategoryId,
        'serviceDescription': serviceDescription,
        'confidence':         confidence,
        'reasoning':          reasoning,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return (
        categoryId:    data['categoryId']    as String,
        subCategoryId: data['subCategoryId'] as String?,
      );
    } on FirebaseFunctionsException catch (e) {
      throw CategoryAiException(_friendlyMessage(e), code: e.code);
    } catch (e) {
      throw CategoryAiException('שגיאה בשמירת הקטגוריה: $e', code: 'unknown');
    }
  }

  /// Admin-only: approve or reject a pending category.
  static Future<void> reviewPending({
    required String pendingId,
    required String action, // 'approve' | 'reject'
  }) async {
    try {
      final callable = _fn.httpsCallable('approvecategory');
      await callable.call<Map<String, dynamic>>({
        'pendingId': pendingId,
        'action':    action,
      });
    } on FirebaseFunctionsException catch (e) {
      throw CategoryAiException(_friendlyMessage(e), code: e.code);
    }
  }

  // ── Error messages ─────────────────────────────────────────────────────────

  static String _friendlyMessage(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'not-found':
        // Function doesn't exist in the project — most common cause of
        // [firebase_functions/internal] when the code was never deployed.
        return 'הפונקציה "categorizeprovider" לא נמצאת בשרת.\n'
            'ייתכן שהיא עדיין לא פורסה. הרץ בטרמינל:\n'
            'firebase deploy --only functions:categorizeprovider';

      case 'unauthenticated':
        // Should no longer occur — function is now public.
        return 'שגיאת הרשאה בלתי צפויה בסיווג (unauthenticated).';

      case 'internal':
        // The function now surfaces the real error in e.message.
        // e.g. "[AuthenticationError] 401 Invalid API key"
        final detail = e.message ?? 'no details';
        return 'שגיאה פנימית בסיווג AI:\n$detail';

      case 'deadline-exceeded':
        return 'הסיווג לקח יותר מדי זמן (timeout). נסה שוב עם תיאור קצר יותר.';

      case 'invalid-argument':
        return 'תיאור השירות קצר מדי. הוסף לפחות 6 תווים.';

      case 'resource-exhausted':
        return 'חרגת ממגבלת הקריאות. נסה שוב בעוד מספר שניות.';

      case 'permission-denied':
        return 'אין הרשאה לקרוא לפונקציה זו.';

      default:
        return 'שגיאה בסיווג (${e.code}): ${e.message ?? "שגיאה לא ידועה"}';
    }
  }
}
