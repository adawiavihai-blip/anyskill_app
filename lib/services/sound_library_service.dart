/// Sound Studio §53 — `sound_metadata` library + analytics queries.
///
/// `sound_metadata/{id}` is the canonical source of truth for the admin
/// LibraryTab: every sound the app COULD play (active + archived + AI
/// suggestions), with psycho-acoustic + UX metadata. Disjoint from
/// `app_settings/sounds` which only holds CURRENT mappings.
///
/// `sound_events_log/{id}` (written by AudioService.playEvent) feeds the
/// AnalyticsTab — KPIs, ranking, daily breakdown.
library;

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'audio_service.dart';
import 'sounds_log_service.dart';

// ── Library metadata model ───────────────────────────────────────────────────

enum SoundStatus { active, archived, suggested }

extension SoundStatusName on SoundStatus {
  String get wireName => name;
}

/// Mirrors the LibraryTab card schema. Fields match the spec
/// (CLAUDE_CODE_PROMPT.md Library section).
class SoundMetadata {
  final String id;
  final String name;
  final String category;
  final String categoryFilter; // payments | notifications | achievements | login
  final String file;
  final int sizeBytes;
  final String frequencyHz; // '528' or '440→880'
  final double durationSeconds;
  final int bpm;
  final String cognitiveLoad; // נמוך | בינוני | גבוה
  final SoundStatus status;
  final List<String> tags;
  final Map<String, int> emotionScores; // {label: 0-100}
  final String psychDescription;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SoundMetadata({
    required this.id,
    required this.name,
    this.category = '',
    this.categoryFilter = 'payments',
    this.file = '',
    this.sizeBytes = 0,
    this.frequencyHz = '',
    this.durationSeconds = 0,
    this.bpm = 80,
    this.cognitiveLoad = 'בינוני',
    this.status = SoundStatus.archived,
    this.tags = const [],
    this.emotionScores = const {},
    this.psychDescription = '',
    this.createdAt,
    this.updatedAt,
  });

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).round()} KB';
    return '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  String get durationLabel {
    if (durationSeconds <= 0) return '—';
    return '${durationSeconds.toStringAsFixed(1)} שנ׳';
  }

  factory SoundMetadata.fromDoc(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? const {};
    final statusStr = d['status'] as String? ?? 'archived';
    final status = SoundStatus.values.firstWhere(
      (s) => s.wireName == statusStr,
      orElse: () => SoundStatus.archived,
    );
    final emotionsRaw = d['emotionScores'];
    final Map<String, int> emotions = {};
    if (emotionsRaw is Map) {
      emotionsRaw.forEach((k, v) {
        if (v is num) emotions[k.toString()] = v.toInt();
      });
    }
    final tagsRaw = d['tags'];
    final tags = <String>[
      if (tagsRaw is List)
        ...tagsRaw.whereType<String>(),
    ];
    return SoundMetadata(
      id: doc.id,
      name: (d['name'] as String?) ?? doc.id,
      category: (d['category'] as String?) ?? '',
      categoryFilter: (d['categoryFilter'] as String?) ?? 'payments',
      file: (d['file'] as String?) ?? '',
      sizeBytes: (d['sizeBytes'] as num?)?.toInt() ?? 0,
      frequencyHz: (d['frequencyHz'] as String?) ?? '',
      durationSeconds: (d['durationSeconds'] as num?)?.toDouble() ?? 0,
      bpm: (d['bpm'] as num?)?.toInt() ?? 80,
      cognitiveLoad: (d['cognitiveLoad'] as String?) ?? 'בינוני',
      status: status,
      tags: tags,
      emotionScores: emotions,
      psychDescription: (d['psychDescription'] as String?) ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toCreateMap() => {
        'name': name,
        'category': category,
        'categoryFilter': categoryFilter,
        'file': file,
        'sizeBytes': sizeBytes,
        'frequencyHz': frequencyHz,
        'durationSeconds': durationSeconds,
        'bpm': bpm,
        'cognitiveLoad': cognitiveLoad,
        'status': status.wireName,
        'tags': tags,
        'emotionScores': emotionScores,
        'psychDescription': psychDescription,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

// ── Aggregated analytics shapes for the AnalyticsTab ─────────────────────────

class SoundAnalyticsSnapshot {
  final int totalPlays;
  final double avgCtrPercent;       // 0-100
  final double mutePercent;         // 0-100
  final String topSoundId;
  final String topSoundLabel;
  final double topSoundCtr;
  final List<SoundDailyBucket> daily; // 7 buckets, oldest first
  final List<SoundRanking> ranking;

  const SoundAnalyticsSnapshot({
    required this.totalPlays,
    required this.avgCtrPercent,
    required this.mutePercent,
    required this.topSoundId,
    required this.topSoundLabel,
    required this.topSoundCtr,
    required this.daily,
    required this.ranking,
  });

  factory SoundAnalyticsSnapshot.empty() => const SoundAnalyticsSnapshot(
        totalPlays: 0,
        avgCtrPercent: 0,
        mutePercent: 0,
        topSoundId: '',
        topSoundLabel: '—',
        topSoundCtr: 0,
        daily: [],
        ranking: [],
      );
}

class SoundDailyBucket {
  final DateTime day;
  final Map<String, int> bySoundId; // soundId -> count
  const SoundDailyBucket({required this.day, required this.bySoundId});

  int get total => bySoundId.values.fold(0, (a, b) => a + b);
}

class SoundRanking {
  final int rank;
  final String soundId;
  final int plays;
  final double ctrPercent;
  const SoundRanking({
    required this.rank,
    required this.soundId,
    required this.plays,
    required this.ctrPercent,
  });
}

enum AnalyticsRange { last24h, last7d, last30d }

extension AnalyticsRangeWindow on AnalyticsRange {
  Duration get window => switch (this) {
        AnalyticsRange.last24h => const Duration(hours: 24),
        AnalyticsRange.last7d => const Duration(days: 7),
        AnalyticsRange.last30d => const Duration(days: 30),
      };
  String get label => switch (this) {
        AnalyticsRange.last24h => '24 שעות',
        AnalyticsRange.last7d => '7 ימים',
        AnalyticsRange.last30d => '30 ימים',
      };
  int get bucketCount => switch (this) {
        AnalyticsRange.last24h => 24, // 24 hourly buckets
        AnalyticsRange.last7d => 7,
        AnalyticsRange.last30d => 30,
      };
}

// ── Service ──────────────────────────────────────────────────────────────────

class SoundLibraryService {
  SoundLibraryService._();
  static final SoundLibraryService instance = SoundLibraryService._();

  static const _metaCollection = 'sound_metadata';
  static const _eventsCollection = 'sound_events_log';
  static const _storageRoot = 'sounds/uploaded';
  static const _maxBytes = 5 * 1024 * 1024; // 5 MB cap per spec

  CollectionReference<Map<String, dynamic>> get _meta =>
      FirebaseFirestore.instance.collection(_metaCollection);
  CollectionReference<Map<String, dynamic>> get _events =>
      FirebaseFirestore.instance.collection(_eventsCollection);

  /// Live stream of every sound in the library, newest first. The admin
  /// LibraryTab filters client-side by status/category — fewer than 50 docs
  /// expected over the app's lifetime, so a single stream is fine.
  Stream<List<SoundMetadata>> streamAll() {
    return _meta
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs.map(SoundMetadata.fromDoc).toList());
  }

  /// Seeds the four built-in AppSounds + three suggested/archived stubs the
  /// first time the LibraryTab opens. Idempotent — skips ids that already
  /// exist. Called once from the admin tab init.
  Future<void> ensureSeeded() async {
    try {
      final existing = await _meta.get();
      final existingIds = existing.docs.map((d) => d.id).toSet();
      final batch = FirebaseFirestore.instance.batch();
      var wrote = 0;
      for (final seed in _seeds()) {
        if (existingIds.contains(seed.id)) continue;
        batch.set(_meta.doc(seed.id), seed.toCreateMap());
        wrote++;
      }
      if (wrote > 0) {
        await batch.commit();
        await SoundsLogService.instance.write(
          type: SoundsLogType.system,
          title: 'ספריית הצלילים אותחלה',
          description: 'נוצרו $wrote רשומות מטא-דאטה בסיסיות',
        );
      }
    } catch (e) {
      debugPrint('SoundLibraryService.ensureSeeded error: $e');
    }
  }

  static List<SoundMetadata> _seeds() => [
        // Active — mirror the four built-in AppSounds with realistic metadata.
        SoundMetadata(
          id: AppSound.wealthCrystal.name,
          name: 'Wealth Crystal',
          category: 'תשלומים',
          categoryFilter: 'payments',
          file: 'audio/wealth_crystal.mp3',
          sizeBytes: 47000,
          frequencyHz: '528',
          durationSeconds: 1.2,
          bpm: 72,
          cognitiveLoad: 'נמוך',
          status: SoundStatus.active,
          tags: const ['סיפוק', 'שגשוג', 'נמוך עומס'],
          emotionScores: const {'סיפוק': 92, 'שגשוג': 87, 'אמינות': 81},
          psychDescription: 'תדר השגשוג',
        ),
        SoundMetadata(
          id: AppSound.solutionSnap.name,
          name: 'Solution Snap',
          category: 'התאמת AI',
          categoryFilter: 'notifications',
          file: 'audio/solution_snap.mp3',
          sizeBytes: 38000,
          frequencyHz: '880',
          durationSeconds: 0.4,
          bpm: 110,
          cognitiveLoad: 'בינוני',
          status: SoundStatus.active,
          tags: const ['התרגשות', 'חד'],
          emotionScores: const {'התרגשות': 88, 'סקרנות': 79, 'ערנות': 91},
          psychDescription: 'תדר התרעה גבוה',
        ),
        SoundMetadata(
          id: AppSound.opportunityPulse.name,
          name: 'Opportunity Pulse',
          category: 'התראות',
          categoryFilter: 'notifications',
          file: 'audio/opportunity_pulse.mp3',
          sizeBytes: 52000,
          frequencyHz: '660',
          durationSeconds: 0.8,
          bpm: 96,
          cognitiveLoad: 'נמוך',
          status: SoundStatus.active,
          tags: const ['דחיפות', 'אורגני'],
          emotionScores: const {'דחיפות': 85, 'סקרנות': 78, 'אופטימיות': 82},
          psychDescription: 'פעימה אורגנית',
        ),
        SoundMetadata(
          id: AppSound.growthAscend.name,
          name: 'Growth Ascend',
          category: 'עלייה ב-XP',
          categoryFilter: 'achievements',
          file: 'audio/growth_ascend.mp3',
          sizeBytes: 64000,
          frequencyHz: '440→880',
          durationSeconds: 1.5,
          bpm: 88,
          cognitiveLoad: 'בינוני',
          status: SoundStatus.active,
          tags: const ['הישג', 'עולה'],
          emotionScores: const {'הישג': 94, 'גאווה': 86, 'מוטיבציה': 89},
          psychDescription: 'גליסנדו עולה',
        ),
        // Suggested + archived — keep the LibraryTab non-empty pre-upload.
        SoundMetadata(
          id: 'crystalBell',
          name: 'Crystal Bell',
          category: 'חלופה לתשלומים',
          categoryFilter: 'payments',
          file: 'audio/wealth_crystal.mp3',
          sizeBytes: 41000,
          frequencyHz: '528',
          durationSeconds: 1.0,
          bpm: 70,
          cognitiveLoad: 'נמוך',
          status: SoundStatus.archived,
          tags: const ['בודהיסטי', 'רך'],
          emotionScores: const {'רוגע': 92, 'סיפוק': 84, 'אמינות': 76},
          psychDescription: 'פעמון מדיטציה',
        ),
        SoundMetadata(
          id: 'coinDrop',
          name: 'Coin Drop',
          category: 'הצעת AI · 89% התאמה',
          categoryFilter: 'payments',
          file: 'audio/wealth_crystal.mp3',
          sizeBytes: 34000,
          frequencyHz: '640',
          durationSeconds: 0.8,
          bpm: 80,
          cognitiveLoad: 'נמוך',
          status: SoundStatus.suggested,
          tags: const [],
          emotionScores: const {'סיפוק': 88, 'שגשוג': 82, 'התרגשות': 76},
          psychDescription: 'מתכת חמה',
        ),
        SoundMetadata(
          id: 'softChime',
          name: 'Soft Chime',
          category: 'חלופה רכה',
          categoryFilter: 'achievements',
          file: 'audio/growth_ascend.mp3',
          sizeBytes: 38000,
          frequencyHz: '432',
          durationSeconds: 1.4,
          bpm: 68,
          cognitiveLoad: 'נמוך',
          status: SoundStatus.archived,
          tags: const ['רך'],
          emotionScores: const {'רוגע': 88, 'גאווה': 70, 'אמינות': 81},
          psychDescription: 'תדר טבעי',
        ),
      ];

  /// Updates an existing metadata document. Caller passes only the fields it
  /// wants to change. Logs a `change` entry to sound_system_log.
  Future<void> update(String id, Map<String, dynamic> patch) async {
    final merged = {...patch, 'updatedAt': FieldValue.serverTimestamp()};
    await _meta.doc(id).set(merged, SetOptions(merge: true));
    await SoundsLogService.instance.write(
      type: SoundsLogType.change,
      title: 'מטא-דאטה של צליל עודכן',
      description: 'sound_metadata/$id עודכן (${patch.keys.join(", ")})',
      metadata: {'soundId': id, 'fields': patch.keys.toList()},
    );
  }

  /// Marks a suggested/archived sound as active so it shows in the
  /// "פעילים" filter and becomes selectable in the StudioTab dropdowns.
  Future<void> activate(String id) async {
    await update(id, {'status': SoundStatus.active.wireName});
  }

  /// Validates + uploads a new sound file. Returns the created metadata.
  /// Throws an [ArgumentError] for bad extensions / oversize files.
  Future<SoundMetadata> uploadNew({
    required String filename,
    required Uint8List bytes,
    String displayName = '',
    String category = '',
    String categoryFilter = 'payments',
  }) async {
    final lower = filename.toLowerCase();
    if (!lower.endsWith('.mp3') && !lower.endsWith('.wav')) {
      throw ArgumentError('רק קבצי MP3 או WAV נתמכים');
    }
    if (bytes.length > _maxBytes) {
      throw ArgumentError('הקובץ חורג מ-5 מגה-בייט');
    }

    final id = _slugForFile(filename);
    final storagePath = '$_storageRoot/$id-${DateTime.now().millisecondsSinceEpoch}-$filename';
    final ref = FirebaseStorage.instance.ref(storagePath);
    final contentType = lower.endsWith('.wav') ? 'audio/wav' : 'audio/mpeg';
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    final url = await ref.getDownloadURL();

    final meta = SoundMetadata(
      id: id,
      name: displayName.isEmpty ? id : displayName,
      category: category,
      categoryFilter: categoryFilter,
      file: url,
      sizeBytes: bytes.length,
      frequencyHz: '',
      durationSeconds: 0,
      bpm: 80,
      cognitiveLoad: 'בינוני',
      status: SoundStatus.archived, // safe default — admin promotes manually
      tags: const [],
      emotionScores: const {},
      psychDescription: '',
    );
    await _meta.doc(id).set(meta.toCreateMap(), SetOptions(merge: true));
    await SoundsLogService.instance.write(
      type: SoundsLogType.upload,
      title: 'צליל חדש הועלה',
      description: '$filename נוסף לספרייה · ${meta.sizeLabel}',
      metadata: {
        'soundId': id,
        'filename': filename,
        'sizeBytes': bytes.length,
        'storagePath': storagePath,
      },
    );
    return meta;
  }

  String _slugForFile(String filename) {
    final base = filename.split(Platform.pathSeparator).last;
    final stem = base.replaceAll(RegExp(r'\.[^.]+$'), '');
    final cleaned = stem
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return 'upl_${cleaned.isEmpty ? "sound" : cleaned}_${DateTime.now().millisecondsSinceEpoch}';
  }

  // ── Analytics ──────────────────────────────────────────────────────────────

  /// One-shot aggregation over `sound_events_log` in the chosen [range].
  /// Caps at 1000 documents (per spec) — for higher volumes, swap to a
  /// Cloud Function in a future PR.
  Future<SoundAnalyticsSnapshot> fetchAnalytics({
    AnalyticsRange range = AnalyticsRange.last7d,
  }) async {
    try {
      final now = DateTime.now();
      final since = now.subtract(range.window);
      final snap = await _events
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
          .orderBy('timestamp', descending: true)
          .limit(1000)
          .get();

      if (snap.docs.isEmpty) return SoundAnalyticsSnapshot.empty();

      final totalPlays = snap.docs.length;
      var followUpHits = 0;
      var muted = 0;
      final perSound = <String, _SoundAggregate>{};
      final daily = <DateTime, Map<String, int>>{};

      for (final doc in snap.docs) {
        final d = doc.data();
        final soundId = (d['soundId'] as String?) ?? 'unknown';
        final ts = d['timestamp'];
        final t = ts is Timestamp ? ts.toDate() : now;
        final wasMuted = d['wasMuted'] == true;
        final followUp = d['followUpAction'] == true;
        if (wasMuted) muted++;
        if (followUp) followUpHits++;
        final agg = perSound.putIfAbsent(
          soundId,
          () => _SoundAggregate(soundId: soundId),
        );
        agg.plays++;
        if (followUp) agg.followUps++;
        // Bucket by day OR by hour for the 24h range.
        final bucketKey = range == AnalyticsRange.last24h
            ? DateTime(t.year, t.month, t.day, t.hour)
            : DateTime(t.year, t.month, t.day);
        final bucket = daily.putIfAbsent(bucketKey, () => {});
        bucket[soundId] = (bucket[soundId] ?? 0) + 1;
      }

      final ranking = perSound.values.toList()
        ..sort((a, b) => b.plays.compareTo(a.plays));
      var rank = 1;
      final rankings = ranking
          .map((a) => SoundRanking(
                rank: rank++,
                soundId: a.soundId,
                plays: a.plays,
                ctrPercent:
                    a.plays == 0 ? 0 : (a.followUps / a.plays) * 100,
              ))
          .toList();

      // Sort buckets oldest-first for the chart.
      final orderedDays = daily.keys.toList()..sort();
      final dailyBuckets = orderedDays
          .map((d) => SoundDailyBucket(day: d, bySoundId: daily[d]!))
          .toList();

      final top = rankings.isEmpty ? null : rankings.first;
      return SoundAnalyticsSnapshot(
        totalPlays: totalPlays,
        avgCtrPercent: (followUpHits / totalPlays) * 100,
        mutePercent: (muted / totalPlays) * 100,
        topSoundId: top?.soundId ?? '',
        topSoundLabel: top?.soundId ?? '—',
        topSoundCtr: top?.ctrPercent ?? 0,
        daily: dailyBuckets,
        ranking: rankings,
      );
    } catch (e) {
      debugPrint('SoundLibraryService.fetchAnalytics error: $e');
      return SoundAnalyticsSnapshot.empty();
    }
  }

  /// Helper for SystemLogsTab — get the current admin's email/name (best
  /// effort) so the actor field on log entries is human-readable.
  String currentActorLabel() {
    final u = FirebaseAuth.instance.currentUser;
    return u?.email ?? u?.displayName ?? u?.uid ?? 'אדמין';
  }
}

class _SoundAggregate {
  final String soundId;
  int plays = 0;
  int followUps = 0;
  _SoundAggregate({required this.soundId});
}
