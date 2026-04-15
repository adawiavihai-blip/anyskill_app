/// AnySkill — AI CEO Strategic Agent Service (v12.2 Genius)
///
/// Two endpoints:
///   1. [generateInsight]   → one-shot strategic briefing (7 rich sections)
///   2. [askAgent]          → interactive follow-up chat with tool use
///
/// Both run server-side (Admin SDK) so they bypass Firestore security rules.
/// Primary brain: Claude Opus 4.6 (strategy) / Claude Sonnet 4.6 (chat).
/// Fallback: Gemini 3.1 Flash Lite.
library;

import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

// ── Rich data models ────────────────────────────────────────────────────────

/// One of the six headline KPIs rendered as a card.
class CeoKeyMetric {
  final String label;
  final String value;
  final String trend; // 'up' | 'down' | 'flat'
  final int deltaPct;

  const CeoKeyMetric({
    required this.label,
    required this.value,
    required this.trend,
    required this.deltaPct,
  });

  factory CeoKeyMetric.fromMap(Map<String, dynamic> m) => CeoKeyMetric(
        label: m['label'] as String? ?? '',
        value: m['value']?.toString() ?? '',
        trend: (m['trend'] as String?) ?? 'flat',
        deltaPct: (m['deltaPct'] as num?)?.toInt() ?? 0,
      );
}

/// A structured recommendation with priority and expected impact.
class CeoRecommendation {
  final String title;
  final String body;
  final String priority; // 'high' | 'medium' | 'low'
  final String impact;

  const CeoRecommendation({
    required this.title,
    required this.body,
    required this.priority,
    required this.impact,
  });

  factory CeoRecommendation.fromMap(Map<String, dynamic> m) => CeoRecommendation(
        title: m['title'] as String? ?? '',
        body: m['body'] as String? ?? '',
        priority: (m['priority'] as String?) ?? 'medium',
        impact: m['impact'] as String? ?? '',
      );

  /// Lossy fallback when only a legacy string is available.
  factory CeoRecommendation.fromString(String s) => CeoRecommendation(
        title: s.length > 60 ? s.substring(0, 60) : s,
        body: s,
        priority: 'medium',
        impact: '',
      );
}

/// A structured red flag with severity and suggested action.
class CeoRedFlag {
  final String severity; // 'critical' | 'warning' | 'info'
  final String title;
  final String body;
  final String suggestedAction;

  const CeoRedFlag({
    required this.severity,
    required this.title,
    required this.body,
    required this.suggestedAction,
  });

  factory CeoRedFlag.fromMap(Map<String, dynamic> m) => CeoRedFlag(
        severity: (m['severity'] as String?) ?? 'warning',
        title: m['title'] as String? ?? '',
        body: m['body'] as String? ?? '',
        suggestedAction: m['suggestedAction'] as String? ?? '',
      );

  factory CeoRedFlag.fromString(String s) => CeoRedFlag(
        severity: 'warning',
        title: s.length > 60 ? s.substring(0, 60) : s,
        body: s,
        suggestedAction: '',
      );
}

class CeoCategoryHealth {
  final String category;
  final String status; // 'healthy' | 'growing' | 'declining' | 'dead'
  final String note;

  const CeoCategoryHealth({
    required this.category,
    required this.status,
    required this.note,
  });

  factory CeoCategoryHealth.fromMap(Map<String, dynamic> m) => CeoCategoryHealth(
        category: m['category'] as String? ?? '',
        status: (m['status'] as String?) ?? 'healthy',
        note: m['note'] as String? ?? '',
      );
}

class CeoTopPerformer {
  final String type; // 'provider' | 'customer'
  final String name;
  final String uid;
  final String highlight;

  const CeoTopPerformer({
    required this.type,
    required this.name,
    required this.uid,
    required this.highlight,
  });

  factory CeoTopPerformer.fromMap(Map<String, dynamic> m) => CeoTopPerformer(
        type: (m['type'] as String?) ?? 'provider',
        name: m['name'] as String? ?? '',
        uid: m['uid'] as String? ?? '',
        highlight: m['highlight'] as String? ?? '',
      );
}

// ── v12.3 GENIUS MODELS ─────────────────────────────────────────────────────

/// Predictions on 6 core KPIs — computed server-side via linear regression.
class CeoPrediction {
  final String label;
  final String field;
  final num current;
  final num projectedIn30Days;
  final int weeklyGrowthPct;
  final String trend;      // 'growing' | 'declining' | 'flat' | 'unknown'
  final String confidence; // 'high' | 'medium' | 'low' | 'insufficient_data'
  final double r2;
  final String unit;
  final String narrative;

  const CeoPrediction({
    required this.label,
    required this.field,
    required this.current,
    required this.projectedIn30Days,
    required this.weeklyGrowthPct,
    required this.trend,
    required this.confidence,
    required this.r2,
    required this.unit,
    required this.narrative,
  });

  factory CeoPrediction.fromMap(Map<String, dynamic> m) => CeoPrediction(
        label: m['label'] as String? ?? '',
        field: m['field'] as String? ?? '',
        current: (m['current'] as num?) ?? 0,
        projectedIn30Days: (m['projectedIn30Days'] as num?) ?? 0,
        weeklyGrowthPct: (m['weeklyGrowthPct'] as num?)?.toInt() ?? 0,
        trend: (m['trend'] as String?) ?? 'unknown',
        confidence: (m['confidence'] as String?) ?? 'insufficient_data',
        r2: (m['r2'] as num?)?.toDouble() ?? 0,
        unit: m['unit'] as String? ?? '',
        narrative: m['narrative'] as String? ?? '',
      );
}

/// Anomalies detected via z-score vs 4-week baseline.
class CeoAnomaly {
  final String label;
  final String field;
  final num currentValue;
  final num historicalAvg;
  final double zScore;
  final int deltaPct;
  final String severity; // 'critical' | 'warning' | 'info'
  final String narrative;

  const CeoAnomaly({
    required this.label,
    required this.field,
    required this.currentValue,
    required this.historicalAvg,
    required this.zScore,
    required this.deltaPct,
    required this.severity,
    required this.narrative,
  });

  factory CeoAnomaly.fromMap(Map<String, dynamic> m) => CeoAnomaly(
        label: m['label'] as String? ?? '',
        field: m['field'] as String? ?? '',
        currentValue: (m['currentValue'] as num?) ?? 0,
        historicalAvg: (m['historicalAvg'] as num?) ?? 0,
        zScore: (m['zScore'] as num?)?.toDouble() ?? 0,
        deltaPct: (m['deltaPct'] as num?)?.toInt() ?? 0,
        severity: (m['severity'] as String?) ?? 'warning',
        narrative: m['narrative'] as String? ?? '',
      );
}

/// Rule-engine action items (distinct from AI-written recommendations).
class CeoActionItem {
  final String title;
  final String body;
  final String urgency; // 'critical' | 'urgent' | 'warning'
  final String owner;   // 'founder' | 'admin' | 'support' | 'ops'
  final String category;

  const CeoActionItem({
    required this.title,
    required this.body,
    required this.urgency,
    required this.owner,
    required this.category,
  });

  factory CeoActionItem.fromMap(Map<String, dynamic> m) => CeoActionItem(
        title: m['title'] as String? ?? '',
        body: m['body'] as String? ?? '',
        urgency: (m['urgency'] as String?) ?? 'warning',
        owner: (m['owner'] as String?) ?? 'founder',
        category: m['category'] as String? ?? '',
      );
}

/// Comparison row vs a competitor.
class CeoBenchmark {
  final String name;
  final num theirWeeklyGmvUsd;
  final num ourWeeklyGmvUsd;
  final double gapPct;
  final int gapMultiplier;
  final num theirTakeRate;
  final num ourTakeRate;
  final String takeRateAdvantage;
  final num theirProviderCount;
  final num ourProviderCount;
  final String note;

  const CeoBenchmark({
    required this.name,
    required this.theirWeeklyGmvUsd,
    required this.ourWeeklyGmvUsd,
    required this.gapPct,
    required this.gapMultiplier,
    required this.theirTakeRate,
    required this.ourTakeRate,
    required this.takeRateAdvantage,
    required this.theirProviderCount,
    required this.ourProviderCount,
    required this.note,
  });

  factory CeoBenchmark.fromMap(Map<String, dynamic> m) => CeoBenchmark(
        name: m['name'] as String? ?? '',
        theirWeeklyGmvUsd: (m['theirWeeklyGmvUsd'] as num?) ?? 0,
        ourWeeklyGmvUsd: (m['ourWeeklyGmvUsd'] as num?) ?? 0,
        gapPct: (m['gapPct'] as num?)?.toDouble() ?? 0,
        gapMultiplier: (m['gapMultiplier'] as num?)?.toInt() ?? 0,
        theirTakeRate: (m['theirTakeRate'] as num?) ?? 0,
        ourTakeRate: (m['ourTakeRate'] as num?) ?? 0,
        takeRateAdvantage: m['takeRateAdvantage'] as String? ?? '',
        theirProviderCount: (m['theirProviderCount'] as num?) ?? 0,
        ourProviderCount: (m['ourProviderCount'] as num?) ?? 0,
        note: m['note'] as String? ?? '',
      );
}

/// Monthly cohort — retention + avg XP + providers ratio.
class CeoCohort {
  final String monthKey;
  final int size;
  final int providers;
  final int active30d;
  final int retentionPct;
  final int avgXp;

  const CeoCohort({
    required this.monthKey,
    required this.size,
    required this.providers,
    required this.active30d,
    required this.retentionPct,
    required this.avgXp,
  });

  factory CeoCohort.fromMap(Map<String, dynamic> m) => CeoCohort(
        monthKey: m['monthKey'] as String? ?? '',
        size: (m['size'] as num?)?.toInt() ?? 0,
        providers: (m['providers'] as num?)?.toInt() ?? 0,
        active30d: (m['active30d'] as num?)?.toInt() ?? 0,
        retentionPct: (m['retentionPct'] as num?)?.toInt() ?? 0,
        avgXp: (m['avgXp'] as num?)?.toInt() ?? 0,
      );
}

/// Per-user churn risk with concrete signals + suggested intervention.
class CeoChurnRisk {
  final String uid;
  final String name;
  final String serviceType;
  final double riskScore;
  final num rating;
  final int orderCount;
  final List<String> signals;
  final String suggestedAction;

  const CeoChurnRisk({
    required this.uid,
    required this.name,
    required this.serviceType,
    required this.riskScore,
    required this.rating,
    required this.orderCount,
    required this.signals,
    required this.suggestedAction,
  });

  factory CeoChurnRisk.fromMap(Map<String, dynamic> m) => CeoChurnRisk(
        uid: m['uid'] as String? ?? '',
        name: m['name'] as String? ?? '',
        serviceType: m['serviceType'] as String? ?? '',
        riskScore: (m['riskScore'] as num?)?.toDouble() ?? 0,
        rating: (m['rating'] as num?) ?? 0,
        orderCount: (m['orderCount'] as num?)?.toInt() ?? 0,
        signals: ((m['signals'] as List?) ?? const [])
            .whereType<String>()
            .toList(),
        suggestedAction: m['suggestedAction'] as String? ?? '',
      );
}

/// Weighted launch readiness score across 4 categories.
class CeoLaunchReadiness {
  final int total;
  final String verdict;      // 'GO' | 'CAUTION' | 'NO_GO'
  final String verdictLabel;
  final Map<String, Map<String, dynamic>> categoryScores;
  final List<CeoLaunchBlocker> topBlockers;

  const CeoLaunchReadiness({
    required this.total,
    required this.verdict,
    required this.verdictLabel,
    required this.categoryScores,
    required this.topBlockers,
  });

  factory CeoLaunchReadiness.fromMap(Map<String, dynamic> m) {
    final cs = <String, Map<String, dynamic>>{};
    ((m['categoryScores'] as Map?) ?? const {}).forEach((k, v) {
      if (v is Map) cs[k.toString()] = Map<String, dynamic>.from(v);
    });
    return CeoLaunchReadiness(
      total: (m['total'] as num?)?.toInt() ?? 0,
      verdict: (m['verdict'] as String?) ?? 'NO_GO',
      verdictLabel: m['verdictLabel'] as String? ?? '',
      categoryScores: cs,
      topBlockers: ((m['topBlockers'] as List?) ?? const [])
          .whereType<Map>()
          .map((b) => CeoLaunchBlocker.fromMap(Map<String, dynamic>.from(b)))
          .toList(),
    );
  }
}

class CeoLaunchBlocker {
  final String id;
  final String category;
  final String title;
  final int importance;
  final int impact;
  final int weight;
  final String note;

  const CeoLaunchBlocker({
    required this.id,
    required this.category,
    required this.title,
    required this.importance,
    required this.impact,
    required this.weight,
    required this.note,
  });

  factory CeoLaunchBlocker.fromMap(Map<String, dynamic> m) => CeoLaunchBlocker(
        id: m['id'] as String? ?? '',
        category: m['category'] as String? ?? '',
        title: m['title'] as String? ?? '',
        importance: (m['importance'] as num?)?.toInt() ?? 0,
        impact: (m['impact'] as num?)?.toInt() ?? 0,
        weight: (m['weight'] as num?)?.toInt() ?? 0,
        note: m['note'] as String? ?? '',
      );
}

/// Threshold-based smart alert (sorted critical > urgent > warning > info).
class CeoSmartAlert {
  final String severity; // 'critical' | 'urgent' | 'warning' | 'info'
  final String title;
  final String body;
  final String category;

  const CeoSmartAlert({
    required this.severity,
    required this.title,
    required this.body,
    required this.category,
  });

  factory CeoSmartAlert.fromMap(Map<String, dynamic> m) => CeoSmartAlert(
        severity: (m['severity'] as String?) ?? 'info',
        title: m['title'] as String? ?? '',
        body: m['body'] as String? ?? '',
        category: m['category'] as String? ?? '',
      );
}

/// Full strategic briefing returned by [AiCeoService.generateInsight].
///
/// Contains BOTH the AI-written narrative (headline, morning brief,
/// recommendations, red flags, opportunities, category health, top
/// performers) AND the server-computed v12.3 "genius" intelligence
/// (predictions, anomalies, action items, benchmarks, cohorts, churn risks,
/// launch readiness, smart alerts).
class CeoInsight {
  // AI narrative
  final String headline;
  final String morningBrief;
  final List<CeoKeyMetric> keyMetrics;
  final List<CeoRecommendation> recommendations;
  final List<CeoRedFlag> redFlags;
  final List<String> opportunities;
  final List<CeoCategoryHealth> categoryHealth;
  final List<CeoTopPerformer> topPerformers;
  // v12.3 GENIUS — server-computed
  final List<CeoPrediction> predictions;
  final List<CeoAnomaly> anomalies;
  final List<CeoActionItem> actionItems;
  final List<CeoBenchmark> benchmarks;
  final List<CeoCohort> cohorts;
  final List<CeoChurnRisk> churnRisks;
  final CeoLaunchReadiness? launchReadiness;
  final List<CeoSmartAlert> smartAlerts;
  final int historyDays;
  // Meta
  final String usedModel;
  final Map<String, dynamic> metricsSnapshot;
  final DateTime generatedAt;
  // v12.5 — cost + memory
  final double costUsd;
  final int inputTokens;
  final int outputTokens;
  final IlonMemoryStats memoryStats;

  const CeoInsight({
    required this.headline,
    required this.morningBrief,
    required this.keyMetrics,
    required this.recommendations,
    required this.redFlags,
    required this.opportunities,
    required this.categoryHealth,
    required this.topPerformers,
    this.predictions = const [],
    this.anomalies = const [],
    this.actionItems = const [],
    this.benchmarks = const [],
    this.cohorts = const [],
    this.churnRisks = const [],
    this.launchReadiness,
    this.smartAlerts = const [],
    this.historyDays = 0,
    required this.usedModel,
    required this.metricsSnapshot,
    required this.generatedAt,
    this.costUsd = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.memoryStats = IlonMemoryStats.empty,
  });

  bool get isError => morningBrief.startsWith('שגיאה');
}

/// A single turn in the interactive chat thread.
class CeoChatMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  final List<Map<String, dynamic>> toolsUsed;
  final DateTime timestamp;
  // v12.5 — per-turn cost + model badges (only on assistant turns)
  final double costUsd;
  final String usedModel;
  final int inputTokens;
  final int outputTokens;
  final int memorySessionCount;
  final int memoryLearnedFacts;

  const CeoChatMessage({
    required this.role,
    required this.content,
    this.toolsUsed = const [],
    required this.timestamp,
    this.costUsd = 0,
    this.usedModel = '',
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.memorySessionCount = 0,
    this.memoryLearnedFacts = 0,
  });

  Map<String, dynamic> toApiMap() => {'role': role, 'content': content};
}

/// Ilon's persistent learning state — grows session over session.
class IlonMemoryStats {
  final int sessionCount;
  final int learnedFacts;

  const IlonMemoryStats({
    required this.sessionCount,
    required this.learnedFacts,
  });

  factory IlonMemoryStats.fromMap(Map<String, dynamic>? m) {
    final x = m ?? const {};
    return IlonMemoryStats(
      sessionCount: (x['sessionCount'] as num?)?.toInt() ?? 0,
      learnedFacts: (x['learnedFacts'] as num?)?.toInt() ?? 0,
    );
  }

  static const empty = IlonMemoryStats(sessionCount: 0, learnedFacts: 0);
}

// ── Service ──────────────────────────────────────────────────────────────────

class AiCeoService {
  AiCeoService._();

  static final _fn = FirebaseFunctions.instanceFor(region: 'us-central1');

  /// One-shot strategic briefing. Takes ~15-30s (Claude Opus is thorough).
  static Future<CeoInsight> generateInsight() async {
    try {
      final callable = _fn.httpsCallable(
        'generateCeoInsight',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 180)),
      );

      final result = await callable.call<Map<String, dynamic>>({});
      final data = result.data;

      // Recommendations: prefer rich v2, fall back to legacy strings
      final richRecs = (data['richRecommendations'] as List?) ?? const [];
      final List<CeoRecommendation> recommendations = richRecs.isNotEmpty
          ? richRecs
              .whereType<Map>()
              .map((m) => CeoRecommendation.fromMap(Map<String, dynamic>.from(m)))
              .toList()
          : ((data['recommendations'] as List?) ?? const [])
              .whereType<String>()
              .map(CeoRecommendation.fromString)
              .toList();

      // Red flags: same pattern
      final richFlags = (data['richRedFlags'] as List?) ?? const [];
      final List<CeoRedFlag> redFlags = richFlags.isNotEmpty
          ? richFlags
              .whereType<Map>()
              .map((m) => CeoRedFlag.fromMap(Map<String, dynamic>.from(m)))
              .toList()
          : ((data['redFlags'] as List?) ?? const [])
              .whereType<String>()
              .map(CeoRedFlag.fromString)
              .toList();

      // Helper to parse a list of maps into typed objects
      List<T> parseList<T>(dynamic raw, T Function(Map<String, dynamic>) mapper) {
        if (raw is! List) return <T>[];
        return raw
            .whereType<Map>()
            .map((m) => mapper(Map<String, dynamic>.from(m)))
            .toList();
      }

      return CeoInsight(
        headline: data['headline'] as String? ?? '',
        morningBrief: data['morningBrief'] as String? ?? 'לא ניתן ליצור סיכום כרגע.',
        keyMetrics: parseList(data['keyMetrics'], CeoKeyMetric.fromMap),
        recommendations: recommendations,
        redFlags: redFlags,
        opportunities: ((data['opportunities'] as List?) ?? const [])
            .whereType<String>()
            .toList(),
        categoryHealth: parseList(data['categoryHealth'], CeoCategoryHealth.fromMap),
        topPerformers: parseList(data['topPerformers'], CeoTopPerformer.fromMap),
        // v12.3 GENIUS server-computed fields
        predictions: parseList(data['predictions'], CeoPrediction.fromMap),
        anomalies: parseList(data['anomalies'], CeoAnomaly.fromMap),
        actionItems: parseList(data['actionItems'], CeoActionItem.fromMap),
        benchmarks: parseList(data['benchmarks'], CeoBenchmark.fromMap),
        cohorts: parseList(data['cohorts'], CeoCohort.fromMap),
        churnRisks: parseList(data['churnRisks'], CeoChurnRisk.fromMap),
        launchReadiness: data['launchReadiness'] is Map
            ? CeoLaunchReadiness.fromMap(
                Map<String, dynamic>.from(data['launchReadiness'] as Map))
            : null,
        smartAlerts: parseList(data['smartAlerts'], CeoSmartAlert.fromMap),
        historyDays: (data['historyDays'] as num?)?.toInt() ?? 0,
        usedModel: data['usedModel'] as String? ?? '',
        metricsSnapshot: Map<String, dynamic>.from(
            (data['metricsSnapshot'] as Map?) ?? const {}),
        generatedAt: DateTime.now(),
        // v12.5 cost + memory
        costUsd: (data['costUsd'] as num?)?.toDouble() ?? 0,
        inputTokens: (data['inputTokens'] as num?)?.toInt() ?? 0,
        outputTokens: (data['outputTokens'] as num?)?.toInt() ?? 0,
        memoryStats: IlonMemoryStats.fromMap(
            (data['memoryStats'] as Map?)?.cast<String, dynamic>()),
      );
    } catch (e) {
      debugPrint('[AiCeoService] generateInsight error: $e');
      return CeoInsight(
        headline: '',
        morningBrief: 'שגיאה ביצירת הסיכום: $e',
        keyMetrics: const [],
        recommendations: const [],
        redFlags: const [],
        opportunities: const [],
        categoryHealth: const [],
        topPerformers: const [],
        usedModel: '',
        metricsSnapshot: const {},
        generatedAt: DateTime.now(),
      );
    }
  }

  /// Interactive follow-up question. The agent has access to read-only
  /// Firestore tools and will drill into specific data on demand.
  ///
  /// Pass the [metricsSnapshot] from the initial briefing so the agent
  /// starts with full context. [history] is the prior chat turns.
  static Future<CeoChatMessage> askAgent({
    required String question,
    required List<CeoChatMessage> history,
    required Map<String, dynamic> metricsSnapshot,
  }) async {
    try {
      final callable = _fn.httpsCallable(
        'askCeoAgent',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 180)),
      );

      final result = await callable.call<Map<String, dynamic>>({
        'question': question,
        'conversationHistory': history.map((m) => m.toApiMap()).toList(),
        'metricsSnapshot': metricsSnapshot,
      });

      final data = result.data;
      final memMap = (data['memoryStats'] as Map?)?.cast<String, dynamic>() ?? const {};
      return CeoChatMessage(
        role: 'assistant',
        content: data['answer'] as String? ?? 'לא התקבלה תשובה.',
        toolsUsed: ((data['toolsUsed'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList(),
        timestamp: DateTime.now(),
        costUsd: (data['costUsd'] as num?)?.toDouble() ?? 0,
        usedModel: data['usedModel'] as String? ?? '',
        inputTokens: (data['inputTokens'] as num?)?.toInt() ?? 0,
        outputTokens: (data['outputTokens'] as num?)?.toInt() ?? 0,
        memorySessionCount: (memMap['sessionCount'] as num?)?.toInt() ?? 0,
        memoryLearnedFacts: (memMap['learnedFacts'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('[AiCeoService] askAgent error: $e');
      return CeoChatMessage(
        role: 'assistant',
        content: 'שגיאה: $e',
        toolsUsed: const [],
        timestamp: DateTime.now(),
      );
    }
  }
}
