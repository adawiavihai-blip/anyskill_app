import 'package:flutter/material.dart';

/// One row in the ⌘K command palette. Built dynamically from:
///   - matched categories (jump-to)
///   - matched sub-categories (jump-to)
///   - matched custom_tags
///   - static action verbs (create, undo, refresh, etc.)
///
/// Lives in memory only — never persisted. Constructed by
/// [CommandPaletteService.buildActions].
class CommandPaletteAction {
  const CommandPaletteAction({
    required this.id,
    required this.kind,
    required this.primaryText,
    this.secondaryText = '',
    this.icon = Icons.bolt_rounded,
    this.shortcut,
    this.targetId,
    this.score = 0,
  });

  final String id;
  final CommandKind kind;
  final String primaryText;
  final String secondaryText;
  final IconData icon;
  final String? shortcut;     // e.g. '⌘E' — display hint only
  final String? targetId;     // category / sub-category id when relevant
  final double score;         // fuzzy match score, used by sorter

  CommandPaletteAction copyWithScore(double newScore) => CommandPaletteAction(
        id: id,
        kind: kind,
        primaryText: primaryText,
        secondaryText: secondaryText,
        icon: icon,
        shortcut: shortcut,
        targetId: targetId,
        score: newScore,
      );
}

enum CommandKind {
  jumpToCategory,
  jumpToSubcategory,
  createCategory,
  editCategory,
  deleteCategory,
  togglePin,
  toggleHide,
  reorderCategory,
  refreshAnalytics,
  exportJson,
  importJson,
  openActivityLog,
  closeActivityLog,
  undoLast,
  filterByTag,
  switchView,
}
