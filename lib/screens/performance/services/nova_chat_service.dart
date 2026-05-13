import 'package:cloud_functions/cloud_functions.dart';

import '../models/performance_metric.dart';
import 'performance_service.dart';

/// Represents a single turn in the Nova conversation.
class NovaMessage {
  final String role; // 'user' | 'assistant'
  final String text;
  final DateTime at;

  NovaMessage({required this.role, required this.text, DateTime? at})
      : at = at ?? DateTime.now();

  bool get isUser => role == 'user';
}

/// Calls the `askNovaChat` Cloud Function (Gemini 2.5 Flash Lite) with the
/// current metrics context pre-assembled. Client never talks to Gemini
/// directly — the key is held server-side.
class NovaChatService {
  NovaChatService._();
  static final instance = NovaChatService._();

  Future<String> ask(String question) async {
    final metrics = await PerformanceService.instance.readCurrent();
    final context = _buildContext(metrics);

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'askNovaChat',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
      );
      final result = await callable.call({
        'question': question,
        'context': context,
      });
      final data = (result.data ?? {}) as Map;
      final text = (data['text'] ?? '').toString().trim();
      if (text.isEmpty) {
        return 'מצטער, לא הצלחתי לנסח תשובה. נסה שוב בעוד רגע.';
      }
      return text;
    } catch (_) {
      return 'אירעה שגיאה בתקשורת עם Nova. בדוק חיבור אינטרנט ונסה שוב.';
    }
  }

  String _buildContext(PerformanceMetric m) {
    return '''
- DAU: ${m.dailyActiveUsers}
- MAU: ${m.monthlyActiveUsers}
- משתמשים רשומים: ${m.totalRegistered}
- הכנסות היום: ₪${m.revenueToday.toStringAsFixed(0)}
- הזמנות היום: ${m.bookingsToday}
- הזמנות שבוע: ${m.bookingsThisWeek}
- מחלוקות פתוחות: ${m.openDisputes}
- שגיאות בשעה האחרונה: ${m.errorsLastHour}
- Happiness Score: ${m.happinessScore}/100
- סיכון עזיבה: ${m.churnRiskCount} משתמשים
- Firestore עלות חודשית: \$${m.firestoreMonthlyCostUsd.toStringAsFixed(0)}
- Dashboard load: ${m.dashboardLoadTimeMs}ms
- p95 API latency: ${m.apiP95LatencyMs}ms
- Error rate: ${m.errorRatePercent.toStringAsFixed(2)}%
- Uptime: ${m.uptimePercent.toStringAsFixed(2)}%
''';
  }
}
