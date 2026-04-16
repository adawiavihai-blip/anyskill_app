import 'package:cloud_firestore/cloud_firestore.dart';

/// Canned (template) responses for support agents.
///
/// Templates live in `canned_responses/{id}` and can be edited by admins.
/// On first run, if the collection is empty, the agent dashboard auto-seeds
/// it with the [defaultTemplates] below so the workspace is immediately useful.
///
/// Templates support `{customerName}` and `{ticketId}` placeholders that get
/// substituted when the agent picks one to insert into the chat composer.
class CannedResponsesService {
  CannedResponsesService._();

  static final _db = FirebaseFirestore.instance;

  // ── Default templates (Hebrew, Wolt/Airbnb-flavor) ─────────────────────

  static const List<Map<String, String>> defaultTemplates = [
    {
      'title': '👋 ברוך הבא',
      'category': 'greeting',
      'body':
          'שלום {customerName}, אני {agentName} מצוות התמיכה של AnySkill. '
              'אני כאן לעזור לך. תוכל לתאר לי במילים שלך מה הבעיה?',
    },
    {
      'title': '⏳ בודק עכשיו',
      'category': 'investigating',
      'body':
          'תודה על המידע {customerName}. אני בודק את הפנייה שלך מול המערכת '
              'כעת — אחזור אליך תוך מספר דקות עם מענה.',
    },
    {
      'title': '💰 בקשת החזר התקבלה',
      'category': 'refund',
      'body':
          'הבקשה שלך להחזר אושרה ועובדת. הסכום יחזור לארנק שלך תוך מספר דקות. '
              'אם יש לך שאלות נוספות, אני כאן.',
    },
    {
      'title': '🛡️ אימות זהות הושלם',
      'category': 'verify',
      'body':
          'זהותך אומתה בהצלחה {customerName}. תוכל כעת להשתמש בכל הפיצ\'רים '
              'של האפליקציה ללא הגבלה.',
    },
    {
      'title': '🔑 איפוס סיסמה',
      'category': 'password',
      'body':
          'שלחנו לך כעת מייל לאיפוס הסיסמה. אם לא רואה אותו תוך 5 דקות, '
              'בדוק בתיקיית הספאם. אם עדיין יש בעיה — תגיד לי ואני אעזור.',
    },
    {
      'title': '📞 צריך לתאם שיחה',
      'category': 'callback',
      'body':
          'הנושא הזה ידרוש בירור מעמיק יותר. אני יכול לתאם איתך שיחה טלפונית '
              'או להמשיך כאן בכתב — מה נוח לך?',
    },
    {
      'title': '✅ הבעיה נפתרה',
      'category': 'resolved',
      'body':
          'אני שמח שהצלחנו לפתור את הבעיה {customerName}! '
              'אני סוגר את הפנייה. אם תזדקק לעזרה נוספת, אנחנו כאן 24/7.',
    },
    {
      'title': '🙏 תודה על הסבלנות',
      'category': 'apology',
      'body':
          'אני מתנצל על אי הנוחות {customerName}. אנחנו מטפלים בזה כעת '
              'ואחזור אליך עם עדכון בהקדם האפשרי.',
    },
    {
      'title': '📋 צריך פרטים נוספים',
      'category': 'info_request',
      'body':
          'כדי לעזור לך בצורה הטובה ביותר, אני צריך כמה פרטים נוספים:\n'
              '1. מתי הבעיה התחילה?\n'
              '2. האם יש מספר הזמנה רלוונטי?\n'
              '3. צילום מסך של הבעיה אם אפשר',
    },
    {
      'title': '⏰ מחוץ לשעות פעילות',
      'category': 'after_hours',
      'body':
          'תודה שפנית אלינו {customerName}. צוות התמיכה שלנו זמין בין השעות '
              '08:00-22:00. נחזור אליך מחר בבוקר עם מענה מלא.',
    },
  ];

  // ── Stream + load ───────────────────────────────────────────────────────

  /// Phase 2 — derive the slash-shortcut for autocomplete. If the doc has
  /// an explicit `shortcut` field that wins; otherwise we fall back to
  /// `/<category>` so legacy templates seeded before the shortcut feature
  /// still match.
  static String shortcutFor(Map<String, dynamic> template) {
    final raw = (template['shortcut'] as String?)?.trim();
    if (raw != null && raw.isNotEmpty) {
      return raw.startsWith('/') ? raw : '/$raw';
    }
    final cat = (template['category'] as String?)?.trim();
    if (cat != null && cat.isNotEmpty) return '/$cat';
    return '';
  }

  /// Filters a templates list to those whose shortcut starts with the
  /// given query (excluding the leading '/'). Empty query returns all.
  static List<Map<String, dynamic>> filterByShortcut(
    List<Map<String, dynamic>> templates,
    String rawQuery,
  ) {
    final q = rawQuery.trim().toLowerCase();
    final stripped = q.startsWith('/') ? q.substring(1) : q;
    if (stripped.isEmpty) return templates;
    return templates.where((t) {
      final s = shortcutFor(t).toLowerCase();
      return s.startsWith('/$stripped');
    }).toList();
  }

  /// Stream all canned responses for the picker UI.
  static Stream<List<Map<String, dynamic>>> streamAll() {
    return _db
        .collection('canned_responses')
        .orderBy('category')
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final m = d.data();
              m['templateId'] = d.id;
              return m;
            }).toList());
  }

  /// Seeds the collection with default templates if it's empty.
  /// Safe to call multiple times — checks for existing docs first.
  /// Should be called by the SupportDashboardScreen on first mount.
  static Future<void> seedIfEmpty() async {
    try {
      final snap = await _db.collection('canned_responses').limit(1).get();
      if (snap.docs.isNotEmpty) return; // Already seeded

      final batch = _db.batch();
      for (final tmpl in defaultTemplates) {
        final ref = _db.collection('canned_responses').doc();
        batch.set(ref, {
          ...tmpl,
          'isDefault': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (_) {
      // Best-effort. If the agent doesn't have admin write rights to the
      // collection, the seeding silently fails — admin will seed manually.
    }
  }

  /// Substitutes {customerName} and {ticketId} placeholders in a template body.
  static String fillPlaceholders(
    String body, {
    required String customerName,
    required String ticketId,
    required String agentName,
  }) {
    return body
        .replaceAll('{customerName}', customerName)
        .replaceAll('{ticketId}', ticketId.length >= 8 ? ticketId.substring(0, 8) : ticketId)
        .replaceAll('{agentName}', agentName);
  }
}
