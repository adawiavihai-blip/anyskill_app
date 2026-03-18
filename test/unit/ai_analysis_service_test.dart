// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:anyskill_app/services/ai_analysis_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Unit tests: AiAnalysisService — keyword matching + provider scoring
//
// Run:  flutter test test/unit/ai_analysis_service_test.dart
//
// Pure Dart — no Firebase, no network, fully offline.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('analyze(): short text guard', () {
    test('text shorter than 6 chars returns empty analysis', () {
      final result = AiAnalysisService.analyze('שרב');
      expect(result.suggestedCategory, isNull);
      expect(result.urgency, 'normal');
      expect(result.missingDate, isFalse);
      expect(result.missingLocation, isFalse);
      expect(result.hasInsights, isFalse);
    });

    test('empty string returns empty analysis', () {
      final result = AiAnalysisService.analyze('');
      expect(result.hasInsights, isFalse);
    });
  });

  group('analyze(): category detection', () {
    test('detects שרברבות from plumbing keywords', () {
      final result = AiAnalysisService.analyze('יש נזילה מהברז במטבח');
      expect(result.suggestedCategory, 'שרברבות');
    });

    test('detects חשמל from electrical keywords', () {
      final result = AiAnalysisService.analyze('השקע החשמלי לא עובד יש בעיה בחיווט');
      expect(result.suggestedCategory, 'חשמל');
    });

    test('detects ניקיון from cleaning keywords', () {
      final result = AiAnalysisService.analyze('צריך ניקיון עמוק לדירה כולל חלונות');
      expect(result.suggestedCategory, 'ניקיון');
    });

    test('detects גינון from garden keywords', () {
      final result = AiAnalysisService.analyze('גיזום עצים ועשב בגינה');
      expect(result.suggestedCategory, 'גינון');
    });

    test('detects מחשבים וטכנולוגיה from tech keywords', () {
      final result = AiAnalysisService.analyze('המחשב נגוע בוירוס צריך IT לתקן');
      expect(result.suggestedCategory, 'מחשבים וטכנולוגיה');
    });

    test('detects הוראה פרטית from tutoring keywords', () {
      final result = AiAnalysisService.analyze('מחפש מורה לשיעור פרטי במתמטיקה לבגרות');
      expect(result.suggestedCategory, 'הוראה פרטית');
    });

    test('detects רכב from car repair keywords', () {
      final result = AiAnalysisService.analyze('תקר בגלגל הרכב צריך מכאניק');
      expect(result.suggestedCategory, 'רכב');
    });

    test('no category detected when no keywords match', () {
      final result = AiAnalysisService.analyze('צריך עזרה כללית עם משהו לא ברור');
      expect(result.suggestedCategory, isNull);
    });

    test('most matching category wins when multiple categories overlap', () {
      // Many plumbing keywords → שרברבות should win over שיפוצים
      final result = AiAnalysisService.analyze(
          'נזילה מהברז בכיור, צנרת ישנה, ביוב סתום, דוד מים מקולקל');
      expect(result.suggestedCategory, 'שרברבות');
    });
  });

  group('analyze(): urgency detection', () {
    test('detects urgency from דחוף', () {
      final result = AiAnalysisService.analyze('דחוף! יש נזילה גדולה מהצינור');
      expect(result.urgency, 'urgent');
    });

    test('detects urgency from עכשיו', () {
      final result = AiAnalysisService.analyze('צריך שרברב עכשיו הברז שבור');
      expect(result.urgency, 'urgent');
    });

    test('detects urgency from ASAP (English)', () {
      final result = AiAnalysisService.analyze('need electrician asap the power is out');
      expect(result.urgency, 'urgent');
    });

    test('normal request has urgency=normal', () {
      final result = AiAnalysisService.analyze('מחפש שרברב לבדיקה שגרתית');
      expect(result.urgency, 'normal');
    });
  });

  group('analyze(): missing date/location hints', () {
    test('long text without date triggers missingDate', () {
      final result = AiAnalysisService.analyze(
          'צריך חשמלאי לתקן את השקע בסלון כבר כמה זמן');
      // No date keyword → missingDate = true (text > 20 chars)
      expect(result.missingDate, isTrue);
    });

    test('text with date does NOT trigger missingDate', () {
      final result = AiAnalysisService.analyze(
          'צריך חשמלאי מחר בבוקר לתיקון השקע');
      expect(result.missingDate, isFalse);
    });

    test('text with numeric date pattern does NOT trigger missingDate', () {
      final result = AiAnalysisService.analyze(
          'צריך שרברב ב-15/03 לתיקון הברז הזה');
      expect(result.missingDate, isFalse);
    });

    test('long text without location triggers missingLocation', () {
      // No city name and no ב+word pattern — only generic request text
      final result = AiAnalysisService.analyze(
          'צריך חשמלאי לתיקון שקע שרוף ומנורה ישנה שלא עובדת');
      expect(result.missingLocation, isTrue);
    });

    test('text with city name does NOT trigger missingLocation', () {
      final result = AiAnalysisService.analyze(
          'צריך חשמלאי בתל אביב לתיקון השקע בסלון מהר');
      expect(result.missingLocation, isFalse);
    });

    test('short text (≤20 chars) does not trigger missing hints', () {
      final result = AiAnalysisService.analyze('שרברב לברז');
      // text.trim().length <= 20 → missingDate/missingLocation stay false
      expect(result.missingDate, isFalse);
      expect(result.missingLocation, isFalse);
    });
  });

  group('analyze(): hasInsights flag', () {
    test('urgent request has insights', () {
      final result = AiAnalysisService.analyze('דחוף מאוד צריך עזרה כעת');
      expect(result.hasInsights, isTrue);
    });

    test('category match produces insights', () {
      final result = AiAnalysisService.analyze('שרברב לברז נזילה');
      expect(result.hasInsights, isTrue);
    });
  });

  group('scoreProvider()', () {
    test('perfect rating (5.0) scores 40 rating points', () {
      final score = AiAnalysisService.scoreProvider(
        {'rating': 5.0, 'aboutMe': '', 'serviceType': '', 'orderCount': 0},
        'some request',
      );
      expect(score, closeTo(40.0, 0.01));
    });

    test('zero rating scores 0 rating points', () {
      final score = AiAnalysisService.scoreProvider(
        {'rating': 0.0, 'aboutMe': '', 'serviceType': '', 'orderCount': 0},
        'some request',
      );
      expect(score, closeTo(0.0, 0.01));
    });

    test('null rating defaults to 4.5', () {
      final score = AiAnalysisService.scoreProvider(
        {'aboutMe': '', 'serviceType': '', 'orderCount': 0},
        'test',
      );
      // 4.5/5 * 40 = 36
      expect(score, closeTo(36.0, 0.01));
    });

    test('keyword overlap contributes up to 40 pts', () {
      final score = AiAnalysisService.scoreProvider(
        {
          'rating': 0.0,
          'aboutMe': 'שרברב מומחה לתיקון נזילות וצנרת',
          'serviceType': 'שרברבות',
          'orderCount': 0,
        },
        'שרברב נזילה צנרת תיקון',
      );
      // Should score well on keyword overlap (≥2 matches out of capped 6)
      expect(score, greaterThan(10.0));
    });

    test('10 orders gives max social proof (20 pts)', () {
      final score = AiAnalysisService.scoreProvider(
        {'rating': 0.0, 'aboutMe': '', 'serviceType': '', 'orderCount': 10},
        'test',
      );
      expect(score, closeTo(20.0, 0.01));
    });

    test('orders capped at 10 (>10 orders = same as 10)', () {
      final score10 = AiAnalysisService.scoreProvider(
        {'rating': 0.0, 'aboutMe': '', 'serviceType': '', 'orderCount': 10},
        'test',
      );
      final score50 = AiAnalysisService.scoreProvider(
        {'rating': 0.0, 'aboutMe': '', 'serviceType': '', 'orderCount': 50},
        'test',
      );
      expect(score10, closeTo(score50, 0.01));
    });

    test('max possible score is 100', () {
      final score = AiAnalysisService.scoreProvider(
        {
          'rating': 5.0,
          'aboutMe': 'שרברב נזילה צנרת ביוב מים כיור',  // 6 words matching
          'serviceType': '',
          'orderCount': 10,
        },
        'שרברב נזילה צנרת ביוב מים כיור',
      );
      expect(score, closeTo(100.0, 0.1));
    });
  });

  group('topMatchIndex()', () {
    test('returns 0 for empty list', () {
      expect(AiAnalysisService.topMatchIndex([], 'request'), 0);
    });

    test('returns index of highest-rated provider', () {
      final providers = [
        {'rating': 3.0, 'aboutMe': '', 'serviceType': '', 'orderCount': 0},
        {'rating': 5.0, 'aboutMe': '', 'serviceType': '', 'orderCount': 0},
        {'rating': 2.0, 'aboutMe': '', 'serviceType': '', 'orderCount': 0},
      ];
      expect(AiAnalysisService.topMatchIndex(providers, 'test'), 1);
    });

    test('keyword-matching provider beats higher-rated but irrelevant provider', () {
      final providers = [
        // High rating, no keyword match
        {'rating': 5.0, 'aboutMe': 'שף קייטרינג', 'serviceType': 'בישול', 'orderCount': 0},
        // Lower rating but direct keyword match + orders
        {'rating': 4.0, 'aboutMe': 'שרברב מומחה לנזילות', 'serviceType': 'שרברבות', 'orderCount': 10},
      ];
      final request = 'שרברב לנזילה מהברז';
      final idx = AiAnalysisService.topMatchIndex(providers, request);
      expect(idx, 1);
    });
  });
}
