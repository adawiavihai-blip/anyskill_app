// CSM Text Override Service.
//
// CMS layer for category-specific module (CSM) settings blocks. Admin can
// edit visible labels (section titles, hero text, banners) from the
// "CSM 🔧" admin tab; providers see the overrides when they open their
// own profile-edit screen.
//
// Storage: a single Firestore doc per CSM:
//
//   csm_text_overrides/{csmId}
//     'fitness.hero.title':    'הקריירה שלך'      ← admin override
//     'fitness.pricing.title': 'מחירים' (override)
//     ...
//
// Reads are cached in memory + kept fresh via a real-time stream so admin
// edits propagate to any provider currently on the edit-profile screen
// without a refresh. Service is a [ChangeNotifier] — call sites that want
// reactive rebuilds simply `addListener(setState)`.
//
// Design rules (CLAUDE.md §50 hardening):
//   • Reads: any verified user (providers need to read overrides)
//   • Writes: admin-only (enforced in firestore.rules)
//
// Stage 1 of the CSM CMS rollout — only "title-level" strings (section
// headers, hero, banners). See `csm_text_keys.dart` for the registry.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class CsmTextOverrideService extends ChangeNotifier {
  CsmTextOverrideService._();
  static final CsmTextOverrideService instance = CsmTextOverrideService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// In-memory cache: `{csmId: {key: overrideValue}}`.
  /// Empty inner map = no overrides (every key resolves to fallback).
  final Map<String, Map<String, String>> _cache = {};

  /// Active subscriptions per csmId so we can safely re-subscribe.
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>
      _subs = {};

  /// `csmId`s whose first snapshot has landed at least once. Used so callers
  /// can render "loading vs. empty" without flicker if they care.
  final Set<String> _ready = {};

  bool isReady(String csmId) => _ready.contains(csmId);

  /// Synchronous resolver. Returns the admin override if one exists for this
  /// `(csmId, key)`, otherwise returns [fallback]. Always returns non-null.
  ///
  /// Safe to call before [ensureLoaded] — just returns the fallback until the
  /// snapshot lands and notifies listeners.
  String t(String csmId, String key, String fallback) {
    final overrides = _cache[csmId];
    if (overrides == null) return fallback;
    final v = overrides[key];
    if (v == null || v.isEmpty) return fallback;
    return v;
  }

  /// Returns the full override map for a CSM (admin UI uses this to render
  /// the edit form pre-populated with current overrides).
  Map<String, String> snapshotFor(String csmId) {
    return Map.unmodifiable(_cache[csmId] ?? const {});
  }

  /// Subscribes to `csm_text_overrides/{csmId}` if not already subscribed.
  /// Idempotent. Notifies listeners on every snapshot.
  void ensureLoaded(String csmId) {
    if (_subs.containsKey(csmId)) return;
    final sub = _db
        .collection('csm_text_overrides')
        .doc(csmId)
        .snapshots()
        .listen((doc) {
      final data = doc.data() ?? const <String, dynamic>{};
      final next = <String, String>{};
      for (final entry in data.entries) {
        final v = entry.value;
        if (v is String) next[entry.key] = v;
      }
      _cache[csmId] = next;
      _ready.add(csmId);
      notifyListeners();
    }, onError: (e, st) {
      // Permission errors etc. are non-fatal — fallbacks remain in effect.
      debugPrint('[CsmTextOverrideService] stream error ($csmId): $e');
      _ready.add(csmId);
      notifyListeners();
    });
    _subs[csmId] = sub;
  }

  /// Admin-only writer. Empty / whitespace-only values are stored as
  /// `FieldValue.delete()` so a key falls back to default cleanly.
  ///
  /// Throws on permission denial — caller should surface a Hebrew snackbar.
  Future<void> bulkSetOverrides(
    String csmId,
    Map<String, String?> edits,
  ) async {
    if (edits.isEmpty) return;
    final ref = _db.collection('csm_text_overrides').doc(csmId);
    final payload = <String, dynamic>{};
    edits.forEach((key, value) {
      if (value == null || value.trim().isEmpty) {
        payload[key] = FieldValue.delete();
      } else {
        payload[key] = value;
      }
    });
    await ref.set(payload, SetOptions(merge: true));
  }

  /// Single-key reset (writes `FieldValue.delete()` so the key disappears
  /// from the doc). Same auth surface as [bulkSetOverrides].
  Future<void> resetOverride(String csmId, String key) async {
    await _db.collection('csm_text_overrides').doc(csmId).set(
      {key: FieldValue.delete()},
      SetOptions(merge: true),
    );
  }

  @override
  void dispose() {
    for (final s in _subs.values) {
      s.cancel();
    }
    _subs.clear();
    super.dispose();
  }
}
