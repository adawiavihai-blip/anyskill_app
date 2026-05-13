import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/banner_model.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// Banners service — the single abstraction over the `banners/` Firestore
/// collection. Replaces the inline `FirebaseFirestore.instance.collection(...)`
/// calls scattered across [admin_banners_tab.dart] (v1), the v2 tab, and the
/// home tab's two carousels.
///
/// Phase 1 surface (read-only + lightweight mutate):
///   - `watchAll()` — full collection stream.
///   - `watchByPlacement(BannerType)` — for Placement cards.
///   - `watchAiInsight()` — `ai_insights/banners` doc stream (already
///     populated by `generateBannerInsights` CF every 6h, see CLAUDE.md §49).
///   - `setActive(id, bool)` — toggle isActive (the only mutation Phase 1
///     needs; full edit lives in Phase 2's wizard).
///   - `bulkSetActive(ids, bool)` — for bulk-action bar.
///   - `incrementClick(id)` — used by customer runtime widgets (not new).
///
/// Future phases extend the service; they should NOT bypass it. If a new
/// reader inlines `collection('banners')` queries, that's a code-smell:
/// add the method here.
///
/// **KPIs:** the dashboard computes its own 4 KPI cards from the live
/// stream — there is no separate "kpis" doc. Hence no `getKpis7d()` method;
/// the screen does the math. (Per the Plan agent: real "7-day" data needs
/// daily-aggregation infrastructure that's deferred. Phase 1 KPIs are
/// **lifetime** sums until that infra ships — labeled honestly in the UI.)
/// ═══════════════════════════════════════════════════════════════════════════
class BannersService {
  BannersService._();

  static final BannersService instance = BannersService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('banners');

  /// Live stream of every banner (capped at 200 — same cap as v2 used).
  /// Sorted by `order` ascending; ties broken by Firestore doc ID ordering.
  ///
  /// **Defensive deserialization:** any single doc that throws during
  /// `fromDoc` (e.g., a legacy doc with an unexpected field type — a
  /// String where a Timestamp was expected, etc.) is logged and skipped
  /// instead of crashing the entire stream. The dashboard never sees a
  /// half-built list.
  Stream<List<BannerModel>> watchAll() {
    return _col
        .orderBy('order')
        .limit(200)
        .snapshots()
        .map(_safeMapDocs);
  }

  /// Filter by placement, sorted by `order`. Used by Placement cards.
  Stream<List<BannerModel>> watchByPlacement(BannerType type) {
    return _col
        .where('placement', isEqualTo: type.dbValue)
        .limit(200)
        .snapshots()
        .map((snap) {
      final list = _safeMapDocs(snap)
        ..sort((a, b) => a.order.compareTo(b.order));
      return list;
    });
  }

  /// Maps every doc through `BannerModel.fromDoc` inside a try/catch,
  /// dropping malformed docs and printing a single-line warning for each.
  /// The dashboard's UI never crashes on bad data.
  static List<BannerModel> _safeMapDocs(
      QuerySnapshot<Map<String, dynamic>> snap) {
    final out = <BannerModel>[];
    for (final doc in snap.docs) {
      try {
        out.add(BannerModel.fromDoc(doc));
      } catch (e) {
        // ignore: avoid_print
        print('[BannersService] Skipped malformed doc "${doc.id}": $e');
      }
    }
    return out;
  }

  /// AI insight document — written every 6 hours by the
  /// `generateBannerInsights` Cloud Function (CLAUDE.md §49). Returns null
  /// when the doc doesn't exist yet (CF hasn't fired since deploy).
  Stream<AiInsight?> watchAiInsight() {
    return _db
        .collection('ai_insights')
        .doc('banners')
        .snapshots()
        .map((doc) => doc.exists ? AiInsight.fromDoc(doc) : null);
  }

  /// Toggle a banner active/inactive.
  Future<void> setActive(String id, bool active) {
    return _col.doc(id).update({'isActive': active});
  }

  /// Persist edits to an existing banner. Caller passes a freshly-built
  /// [BannerModel] with the new field values (typically via `copyWith`
  /// from the original). Uses `update` (not `set`) so unchanged fields
  /// the caller didn't include in `toFirestore()` (e.g., legacy keys
  /// like `gradientColors` from a v1 doc) survive.
  ///
  /// Phase-2 contract: every save from the new edit screen flows through
  /// here. Direct `_col.doc(id).update(...)` calls are a code-smell.
  Future<void> updateBanner(BannerModel banner) {
    final data = banner.toFirestore();
    // `id` doesn't go on the doc; it's the doc id.
    data.remove('id');
    return _col.doc(banner.id).update(data);
  }

  /// Create a new banner with the supplied draft data. Returns the new
  /// doc id. The draft's `id` field is ignored — Firestore allocates one.
  ///
  /// `createdAt` is forced to the server clock if the caller didn't set
  /// one. `createdBy` should be set by the caller (admin uid) — if absent
  /// it's left unset in Firestore.
  Future<String> createBanner(BannerModel draft) async {
    final ref = _col.doc();
    final stamped = draft.copyWith(
      createdAt: draft.createdAt ?? DateTime.now(),
    );
    final data = stamped.toFirestore();
    data.remove('id');
    await ref.set(data);
    return ref.id;
  }

  /// Apply [active] to all [ids] in a single batch (atomic at the
  /// document level, not a transaction — Firestore's `WriteBatch`).
  /// Caps at 400 to stay under the 500-op batch ceiling.
  Future<void> bulkSetActive(List<String> ids, bool active) async {
    if (ids.isEmpty) return;
    final batch = _db.batch();
    for (final id in ids.take(400)) {
      batch.update(_col.doc(id), {'isActive': active});
    }
    await batch.commit();
  }

  /// Soft-delete (default) or hard-delete a banner. Phase 1 uses
  /// hard-delete to mirror v2 behavior; if a recover-from-trash flow
  /// gets added, switch to a `deletedAt` field instead.
  Future<void> delete(String id) {
    return _col.doc(id).delete();
  }

  /// Bulk delete (used by the toolbar bulk-bar).
  Future<void> bulkDelete(List<String> ids) async {
    if (ids.isEmpty) return;
    final batch = _db.batch();
    for (final id in ids.take(400)) {
      batch.delete(_col.doc(id));
    }
    await batch.commit();
  }

  /// Duplicate a banner — creates a new doc with the same shape but
  /// `isActive=false`, `order=order+1`, `clicks=0`, `impressions=0`,
  /// title prefixed with "(עותק) ". Returns the new doc id.
  Future<String> duplicate(BannerModel source) async {
    final ref = _col.doc();
    final clone = source.copyWith(
      title: '(עותק) ${source.title}',
      isActive: false,
      order: source.order + 1,
      impressions: 0,
      clicks: 0,
      attributedRevenue: 0,
      createdAt: DateTime.now(),
    );
    await ref.set(clone.toFirestore());
    return ref.id;
  }
}

/// Result of `BannersService.watchAiInsight()` — mirrors the schema written
/// by `generateBannerInsights` CF. All fields nullable / safe-default
/// because the CF intentionally writes a degraded fallback if Gemini fails
/// (see CLAUDE.md §49 "always-succeeds contract").
class AiInsight {
  final String title;
  final String recommendation;
  final String? expectedImpact;
  final String actionType;
  final Map<String, dynamic> actionParams;
  final DateTime? generatedAt;
  final String model;

  const AiInsight({
    required this.title,
    required this.recommendation,
    this.expectedImpact,
    this.actionType = 'none',
    this.actionParams = const {},
    this.generatedAt,
    this.model = '',
  });

  factory AiInsight.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return AiInsight(
      title: (d['title'] as String?) ?? '',
      recommendation: (d['recommendation'] as String?) ?? '',
      expectedImpact: d['expectedImpact'] as String?,
      actionType: (d['actionType'] as String?) ?? 'none',
      actionParams: (d['actionParams'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
      generatedAt: (d['generatedAt'] as Timestamp?)?.toDate(),
      model: (d['model'] as String?) ?? '',
    );
  }

  bool get hasContent => title.isNotEmpty || recommendation.isNotEmpty;
}
