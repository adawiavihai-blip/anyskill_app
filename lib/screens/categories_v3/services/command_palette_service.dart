import 'package:flutter/material.dart';

import '../models/category_v3_model.dart';
import '../models/command_palette_action.dart';

/// Builds a flat list of [CommandPaletteAction]s + ranks them against a
/// fuzzy query. Pure-function class — no Firestore reads. The screen passes
/// in the current category list and gets back a ranked, capped list ready
/// for the modal.
class CommandPaletteService {
  /// Catalog of static "global" actions always available regardless of search.
  /// Ordered by frequency-of-use so the empty-query state shows the most
  /// likely first.
  List<CommandPaletteAction> _staticActions() => const [
        CommandPaletteAction(
          id: 'static.create',
          kind: CommandKind.createCategory,
          primaryText: 'צור קטגוריה חדשה',
          secondaryText: 'אשף 3 שלבים: פרטים → תמונה → תתי-קטגוריות',
          icon: Icons.add_circle_outline,
          shortcut: 'N',
        ),
        CommandPaletteAction(
          id: 'static.refresh',
          kind: CommandKind.refreshAnalytics,
          primaryText: 'רענן אנליטיקה עכשיו',
          secondaryText: 'הרץ את updateCategoryAnalytics מיידית',
          icon: Icons.sync_rounded,
        ),
        CommandPaletteAction(
          id: 'static.activity',
          kind: CommandKind.openActivityLog,
          primaryText: 'פתח יומן פעולות',
          secondaryText: 'היסטוריית כל השינויים שלך',
          icon: Icons.history_rounded,
        ),
        CommandPaletteAction(
          id: 'static.undo',
          kind: CommandKind.undoLast,
          primaryText: 'בטל פעולה אחרונה',
          secondaryText: 'משחזר את המצב לפני השינוי',
          icon: Icons.undo_rounded,
          shortcut: '⌘Z',
        ),
        CommandPaletteAction(
          id: 'static.export',
          kind: CommandKind.exportJson,
          primaryText: 'ייצא JSON של כל הקטגוריות',
          secondaryText: 'הורד גיבוי מקומי',
          icon: Icons.download_rounded,
        ),
        CommandPaletteAction(
          id: 'static.import',
          kind: CommandKind.importJson,
          primaryText: 'ייבא JSON של קטגוריות',
          secondaryText: 'מיזוג עם המצב הנוכחי (תאומת לפני שמירה)',
          icon: Icons.upload_rounded,
        ),
        CommandPaletteAction(
          id: 'static.view.tree',
          kind: CommandKind.switchView,
          primaryText: 'מעבר לתצוגת עץ',
          icon: Icons.account_tree_outlined,
          targetId: 'tree',
        ),
        CommandPaletteAction(
          id: 'static.view.grid',
          kind: CommandKind.switchView,
          primaryText: 'מעבר לתצוגת רשת',
          icon: Icons.grid_view_rounded,
          targetId: 'grid',
        ),
        CommandPaletteAction(
          id: 'static.view.analytics',
          kind: CommandKind.switchView,
          primaryText: 'מעבר לתצוגת אנליטיקה',
          icon: Icons.insert_chart_outlined_rounded,
          targetId: 'analytics',
        ),
      ];

  /// Builds + ranks the action list for the current query.
  ///
  /// [query] is whatever the user typed. Empty query → return statics +
  /// jump-to actions for ALL root categories (capped at 30 for ergonomics).
  List<CommandPaletteAction> buildActions({
    required String query,
    required List<CategoryV3Model> categories,
    int maxResults = 25,
  }) {
    final dynamic_ = <CommandPaletteAction>[];

    // Jump-to root categories
    for (final c in categories.where((c) => c.isRoot)) {
      dynamic_.add(CommandPaletteAction(
        id: 'cat.${c.id}',
        kind: CommandKind.jumpToCategory,
        primaryText: c.name,
        secondaryText: c.isCsm ? 'CSM: ${c.csmModule}' : 'קטגוריית שורש',
        icon: Icons.bookmark_outline_rounded,
        targetId: c.id,
      ));
    }

    // Jump-to sub-categories
    for (final c in categories.where((c) => !c.isRoot)) {
      dynamic_.add(CommandPaletteAction(
        id: 'sub.${c.id}',
        kind: CommandKind.jumpToSubcategory,
        primaryText: c.name,
        secondaryText: 'תת-קטגוריה',
        icon: Icons.subdirectory_arrow_left_rounded,
        targetId: c.id,
      ));
    }

    // Custom-tag filters (deduplicated)
    final tags = <String>{};
    for (final c in categories) {
      tags.addAll(c.customTags);
    }
    for (final t in tags) {
      dynamic_.add(CommandPaletteAction(
        id: 'tag.$t',
        kind: CommandKind.filterByTag,
        primaryText: 'סנן לפי תגית: $t',
        icon: Icons.label_outline_rounded,
        targetId: t,
      ));
    }

    final all = [..._staticActions(), ...dynamic_];

    if (query.trim().isEmpty) {
      return all.take(maxResults).toList();
    }

    final scored = all
        .map((a) => a.copyWithScore(_fuzzyScore(query, a)))
        .where((a) => a.score > 0)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return scored.take(maxResults).toList();
  }

  /// Lightweight scoring: full substring > prefix > char-by-char hits. Case-
  /// insensitive, accent-insensitive for Hebrew is a no-op (Hebrew has no
  /// diacritics in our text). Range: 0..1.
  double _fuzzyScore(String rawQuery, CommandPaletteAction a) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return 0;

    final p = a.primaryText.toLowerCase();
    final s = a.secondaryText.toLowerCase();
    final t = a.targetId?.toLowerCase() ?? '';

    if (p == q) return 1.0;
    if (p.contains(q)) return 0.8;
    if (s.contains(q)) return 0.55;
    if (t.contains(q)) return 0.35;

    // Char hit-rate fallback
    var hits = 0;
    var qi = 0;
    for (var i = 0; i < p.length && qi < q.length; i++) {
      if (p[i] == q[qi]) {
        hits++;
        qi++;
      }
    }
    if (qi == q.length) {
      // All query chars matched in order
      return 0.20 + (hits / p.length) * 0.10;
    }
    return 0;
  }
}
