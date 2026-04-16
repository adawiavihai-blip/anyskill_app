/// AnySkill — TaskEscrowService (AnyTasks v14.0.0)
///
/// v15.x audit: atomic transaction moved server-side via `createTaskEscrow`
/// CF. Client no longer writes pendingBalance directly.
library;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class TaskEscrowService {
  TaskEscrowService._();

  /// Called when a client taps "Choose [provider]" on the Compare Offers
  /// screen. Returns null on success, Hebrew error string otherwise.
  static Future<String?> chooseProvider({
    required String taskId,
    required String responseId,
    required String providerId,
    required String providerName,
    required String clientId,
    required String clientName,
    required int agreedPriceNis,
    required String taskTitle,
  }) async {
    if (clientId == providerId) {
      return 'לא ניתן להזמין שירות מעצמך';
    }
    if (agreedPriceNis < 10) {
      return 'המחיר חייב להיות לפחות ₪10';
    }

    try {
      await FirebaseFunctions.instance
          .httpsCallable('createTaskEscrow')
          .call({
        'taskId': taskId,
        'responseId': responseId,
        'providerId': providerId,
        'providerName': providerName,
        'clientName': clientName,
        'agreedPriceNis': agreedPriceNis,
        'taskTitle': taskTitle,
      }).timeout(const Duration(seconds: 30));

      return null;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('TaskEscrowService.chooseProvider CF error: ${e.code} ${e.message}');
      return e.message ?? 'שגיאת שרת.';
    } catch (e) {
      debugPrint('TaskEscrowService.chooseProvider error: $e');
      return e.toString().replaceAll('Exception: ', '');
    }
  }
}
