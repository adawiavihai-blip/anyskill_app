import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'models.dart';

/// Firestore-backed CRUD for Chat Guard admin tab (Phase 1).
///
/// Collections used:
///   • `blocked_words/{id}`          — word catalog (admin-managed)
///   • `chat_guard_incidents/{id}`   — live feed of every detection
///                                     (written by CF in Phase 2+)
///   • `chat_guard_settings/main`    — single settings doc
///
/// All reads are `.snapshots()` so the dashboard stays live; writes are
/// plain document mutations (the collections are small — no batching
/// complexity yet).
class ChatGuardService {
  ChatGuardService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _words =>
      _db.collection('blocked_words');
  CollectionReference<Map<String, dynamic>> get _incidents =>
      _db.collection('chat_guard_incidents');
  DocumentReference<Map<String, dynamic>> get _settingsDoc =>
      _db.collection('chat_guard_settings').doc('main');

  // ── Words ──────────────────────────────────────────────────────────────

  Stream<List<BlockedWord>> streamWords() {
    return _words.limit(500).snapshots().map((snap) {
      final out = <BlockedWord>[];
      for (final d in snap.docs) {
        try {
          out.add(BlockedWord.fromDoc(d));
        } catch (_) {/* skip bad doc */}
      }
      out.sort((a, b) {
        // active first, then by hits desc (most-triggered at the top)
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        return b.hits.compareTo(a.hits);
      });
      return out;
    });
  }

  Future<void> addWord({
    required String text,
    required WordCategory category,
    required WordSeverity severity,
    String notes = '',
  }) async {
    final adminUid = _auth.currentUser?.uid ?? '';
    await _words.add(<String, dynamic>{
      'text': text.trim(),
      'category': category.wire,
      'severity': severity.wire,
      'notes': notes,
      'hits': 0,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': adminUid,
    });
  }

  Future<void> updateWord(String id, {
    String? text,
    WordCategory? category,
    WordSeverity? severity,
    String? notes,
    bool? isActive,
  }) async {
    final patch = <String, dynamic>{};
    if (text != null)     patch['text'] = text.trim();
    if (category != null) patch['category'] = category.wire;
    if (severity != null) patch['severity'] = severity.wire;
    if (notes != null)    patch['notes'] = notes;
    if (isActive != null) patch['isActive'] = isActive;
    if (patch.isEmpty) return;
    patch['updatedAt'] = FieldValue.serverTimestamp();
    await _words.doc(id).update(patch);
  }

  Future<void> deleteWord(String id) => _words.doc(id).delete();

  // ── Incidents ──────────────────────────────────────────────────────────

  Stream<List<ChatGuardIncident>> streamIncidents({int limit = 100}) {
    return _incidents
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final out = <ChatGuardIncident>[];
      for (final d in snap.docs) {
        try {
          out.add(ChatGuardIncident.fromDoc(d));
        } catch (_) {/* skip bad doc */}
      }
      return out;
    });
  }

  /// Aggregate KPIs for the Stats tab. Runs once per settings change —
  /// the caller handles refresh.
  Future<ChatGuardKpis> computeKpis() async {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    // Read the incidents from the last 7 days (capped at 500 for cost).
    final snap = await _incidents
        .where('timestamp', isGreaterThan: Timestamp.fromDate(weekAgo))
        .limit(500)
        .get();
    var blocked = 0, warned = 0, rewritten = 0, suspended = 0, allowed = 0;
    final distinctUsers = <String>{};
    for (final d in snap.docs) {
      try {
        final inc = ChatGuardIncident.fromDoc(d);
        distinctUsers.add(inc.userId);
        switch (inc.action) {
          case IncidentAction.allowed:   allowed   += 1;
          case IncidentAction.warned:    warned    += 1;
          case IncidentAction.rewritten: rewritten += 1;
          case IncidentAction.blocked:   blocked   += 1;
          case IncidentAction.suspended: suspended += 1;
        }
      } catch (_) {}
    }
    final wordsSnap = await _words.limit(500).get();
    var totalWords = 0, activeWords = 0;
    for (final d in wordsSnap.docs) {
      totalWords += 1;
      if ((d.data()['isActive'] as bool?) ?? true) activeWords += 1;
    }
    return ChatGuardKpis(
      totalIncidents7d: snap.docs.length,
      blocked: blocked,
      warned: warned,
      rewritten: rewritten,
      suspended: suspended,
      allowed: allowed,
      distinctUsers: distinctUsers.length,
      totalWords: totalWords,
      activeWords: activeWords,
    );
  }

  // ── Settings ───────────────────────────────────────────────────────────

  Stream<ChatGuardSettings> streamSettings() {
    return _settingsDoc.snapshots().map((doc) {
      if (!doc.exists) return ChatGuardSettings.defaults;
      try {
        return ChatGuardSettings.fromDoc(doc);
      } catch (_) {
        return ChatGuardSettings.defaults;
      }
    });
  }

  Future<void> saveSettings(ChatGuardSettings s) async {
    await _settingsDoc.set(<String, dynamic>{
      ...s.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _auth.currentUser?.uid,
    }, SetOptions(merge: true));
  }

  // ── Seeder (idempotent) ────────────────────────────────────────────────

  /// Writes the 12 starter words from the spec if no words exist.
  /// Safe to call repeatedly — skips when the collection is non-empty.
  Future<SeedResult> seedInitialWordsIfEmpty() async {
    final existing = await _words.limit(1).get();
    if (existing.docs.isNotEmpty) {
      return const SeedResult(scanned: 1, added: 0, skipped: true);
    }
    final batch = _db.batch();
    final now = Timestamp.now();
    final adminUid = _auth.currentUser?.uid ?? '';

    final seeds = <Map<String, dynamic>>[
      {'text': 'מזומן',          'category': 'payment',  'severity': 'high'},
      {'text': 'ביט',            'category': 'payment',  'severity': 'high'},
      {'text': 'paybox',         'category': 'payment',  'severity': 'high'},
      {'text': 'cash',           'category': 'payment',  'severity': 'medium'},
      {'text': 'כסף',            'category': 'payment',  'severity': 'medium'},
      {'text': 'העברה בנקאית',    'category': 'payment',  'severity': 'medium'},
      {'text': 'וואטסאפ',         'category': 'contact',  'severity': 'high'},
      {'text': 'whatsapp',       'category': 'contact',  'severity': 'high'},
      {'text': 'טלגרם',           'category': 'contact',  'severity': 'high'},
      {'text': 'טלפון',           'category': 'contact',  'severity': 'medium'},
      {'text': 'wa.me',          'category': 'external', 'severity': 'critical'},
      {'text': 't.me',           'category': 'external', 'severity': 'critical'},
    ];

    for (final seed in seeds) {
      final ref = _words.doc();
      batch.set(ref, <String, dynamic>{
        ...seed,
        'notes': 'ברירת מחדל',
        'hits': 0,
        'isActive': true,
        'createdAt': now,
        'createdBy': adminUid,
      });
    }
    await batch.commit();
    return SeedResult(scanned: seeds.length, added: seeds.length, skipped: false);
  }
}

class ChatGuardKpis {
  const ChatGuardKpis({
    required this.totalIncidents7d,
    required this.blocked,
    required this.warned,
    required this.rewritten,
    required this.suspended,
    required this.allowed,
    required this.distinctUsers,
    required this.totalWords,
    required this.activeWords,
  });

  final int totalIncidents7d;
  final int blocked;
  final int warned;
  final int rewritten;
  final int suspended;
  final int allowed;
  final int distinctUsers;
  final int totalWords;
  final int activeWords;

  static const empty = ChatGuardKpis(
    totalIncidents7d: 0,
    blocked: 0,
    warned: 0,
    rewritten: 0,
    suspended: 0,
    allowed: 0,
    distinctUsers: 0,
    totalWords: 0,
    activeWords: 0,
  );
}

class SeedResult {
  const SeedResult({required this.scanned, required this.added, required this.skipped});
  final int scanned;
  final int added;
  final bool skipped;
}
