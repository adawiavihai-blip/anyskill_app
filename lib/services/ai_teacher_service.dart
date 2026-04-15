import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for managing the AI Teacher (Alex) profile data in Firestore.
/// All profile settings are stored in `ai_teachers/alex` so the admin
/// can customise everything without code changes.
class AiTeacherService {
  AiTeacherService._();
  static final _db = FirebaseFirestore.instance;
  static final _ref = _db.collection('ai_teachers').doc('alex');

  // ── Default profile (used when Firestore doc doesn't exist yet) ────────
  static const defaultProfile = <String, dynamic>{
    'name': 'Alex',
    'title': 'AI English Teacher',
    'bio': 'מורה AI מקצועי לאנגלית מבית D-ID',
    'avatarLetter': 'A',
    'rating': 5.0,
    'reviewsCount': 128,
    'pricePerHour': 30,
    'level': 'Intermediate (B1-B2)',
    'isOnline': true,
    'didAgentUrl':
        'https://studio.d-id.com/agents/share?id=v2_agt_foW6KwWc&utm_source=copy&key=Y2tfeERFSVZNb3ZueDlEejcyVnhNNzFq',
    'reviews': <Map<String, dynamic>>[
      {
        'name': 'שרה כ.',
        'rating': 5.0,
        'date': '2026-04-01',
        'comment': 'Alex עזר לי לשפר את האנגלית שלי בצורה משמעותית! שיעורים מעולים ואינטראקטיביים.',
      },
      {
        'name': 'דוד מ.',
        'rating': 5.0,
        'date': '2026-03-28',
        'comment': 'מורה סבלני שתמיד זמין. מומלץ בחום למי שרוצה לתרגל אנגלית.',
      },
      {
        'name': 'מיכל א.',
        'rating': 5.0,
        'date': '2026-03-22',
        'comment': 'שיעור ראשון היה מצוין! הרגשתי נוח לדבר באנגלית בלי לחץ.',
      },
      {
        'name': 'יוסי ר.',
        'rating': 4.5,
        'date': '2026-03-15',
        'comment': 'טוב מאוד לתרגול שיחה. עוזר לתקן טעויות בזמן אמת.',
      },
      {
        'name': 'נועה ב.',
        'rating': 5.0,
        'date': '2026-03-10',
        'comment': 'פשוט וואו! שיפור משמעותי בביטחון שלי באנגלית אחרי כמה שיעורים.',
      },
    ],
    'ratingBreakdown': {
      'accuracy': 4.9,
      'responsiveness': 5.0,
      'teachingQuality': 4.8,
    },
    'galleryImages': <String>[],
    'availableDays': [0, 1, 2, 3, 4, 5, 6], // 0=Sun..6=Sat (all days)
    'availableHoursFrom': '06:00',
    'availableHoursTo': '23:00',
  };

  /// Real-time stream of the Alex profile doc.
  static Stream<Map<String, dynamic>> stream() {
    return _ref.snapshots().map((snap) {
      if (!snap.exists) return Map<String, dynamic>.from(defaultProfile);
      final data = snap.data() ?? {};
      // Merge defaults for any missing fields
      return {...defaultProfile, ...data};
    });
  }

  /// One-shot fetch (with fallback to defaults).
  static Future<Map<String, dynamic>> fetch() async {
    try {
      final snap = await _ref.get();
      if (!snap.exists) return Map<String, dynamic>.from(defaultProfile);
      return {...defaultProfile, ...snap.data()!};
    } catch (_) {
      return Map<String, dynamic>.from(defaultProfile);
    }
  }

  /// Admin: update profile fields (merge).
  static Future<void> update(Map<String, dynamic> fields) {
    return _ref.set(fields, SetOptions(merge: true));
  }

  /// Admin: replace the entire reviews list.
  static Future<void> setReviews(List<Map<String, dynamic>> reviews) {
    return _ref.set({'reviews': reviews}, SetOptions(merge: true));
  }

  /// Admin: add a single review.
  static Future<void> addReview(Map<String, dynamic> review) async {
    final data = await fetch();
    final existing = List<Map<String, dynamic>>.from(
        (data['reviews'] as List?) ?? []);
    existing.insert(0, review);
    await _ref.set({
      'reviews': existing,
      'reviewsCount': existing.length,
    }, SetOptions(merge: true));
  }

  /// Admin: remove review at index.
  static Future<void> removeReview(int index) async {
    final data = await fetch();
    final existing = List<Map<String, dynamic>>.from(
        (data['reviews'] as List?) ?? []);
    if (index >= 0 && index < existing.length) {
      existing.removeAt(index);
      await _ref.set({
        'reviews': existing,
        'reviewsCount': existing.length,
      }, SetOptions(merge: true));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Payment gate — deduct balance + log transaction atomically
  // ═══════════════════════════════════════════════════════════════════════════

  /// Attempts to purchase an AI lesson for [userId].
  /// Returns `null` on success, or a Hebrew error string on failure.
  /// Uses the same Firestore transaction pattern as EscrowService.payQuote().
  static Future<String?> purchaseLesson({
    required String userId,
    required String userName,
  }) async {
    try {
      final profile = await fetch();
      final price = (profile['pricePerHour'] as num?)?.toDouble() ?? 30;

      await _db.runTransaction((tx) async {
        // 1. Read user balance inside transaction
        final userDoc = await tx.get(_db.collection('users').doc(userId));
        final balance =
            ((userDoc.data() ?? {})['balance'] as num? ?? 0).toDouble();

        if (balance < price) {
          throw Exception(
              'אין מספיק יתרה בארנק. נדרש ₪${price.toStringAsFixed(0)}, יתרה נוכחית ₪${balance.toStringAsFixed(0)}.');
        }

        // 2. Deduct balance
        tx.update(_db.collection('users').doc(userId), {
          'balance': FieldValue.increment(-price),
        });

        // 3. Platform earnings (100% to platform — no provider split)
        tx.set(_db.collection('platform_earnings').doc(), {
          'amount':    price,
          'source':    'ai_lesson',
          'teacherId': 'alex',
          'userId':    userId,
          'timestamp': FieldValue.serverTimestamp(),
          'status':    'settled',
        });

        // 4. Transaction log
        tx.set(_db.collection('transactions').doc(), {
          'senderId':     userId,
          'senderName':   userName,
          'receiverId':   'ai_teacher_alex',
          'receiverName': profile['name'] ?? 'Alex',
          'amount':       price,
          'type':         'ai_lesson',
          'payoutStatus': 'completed',
          'timestamp':    FieldValue.serverTimestamp(),
        });
      });

      return null; // success
    } on Exception catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      return msg;
    } catch (e) {
      return 'שגיאה בתשלום. נסה שוב.';
    }
  }

  /// Reads user balance (convenience helper).
  static Future<double> getUserBalance(String userId) async {
    try {
      final doc = await _db.collection('users').doc(userId).get();
      return ((doc.data() ?? {})['balance'] as num? ?? 0).toDouble();
    } catch (_) {
      return 0;
    }
  }
}
