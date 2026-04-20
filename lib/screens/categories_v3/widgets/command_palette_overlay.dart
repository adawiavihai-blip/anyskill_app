import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/categories_v3_controller.dart';
import '../models/category_v3_model.dart';
import '../models/command_palette_action.dart';

/// ⌘K command palette modal per spec §7.8. Centered, 480px max wide, dark
/// scrim. Auto-focus search. Fuzzy match via [CommandPaletteService] against
/// every category name + sub-category name + custom_tag + static action verb.
///
/// Keyboard nav: ↑↓ between rows, ↵ executes, Esc closes. Click outside
/// also closes. Implemented as a stateful overlay rather than a route push
/// so the underlying Focus node keeps the keyboard bindings live.
class CommandPaletteOverlay extends ConsumerStatefulWidget {
  const CommandPaletteOverlay({
    super.key,
    required this.open,
    required this.onClose,
    required this.onActionSelected,
  });

  final bool open;
  final VoidCallback onClose;
  final ValueChanged<CommandPaletteAction> onActionSelected;

  @override
  ConsumerState<CommandPaletteOverlay> createState() =>
      _CommandPaletteOverlayState();
}

class _CommandPaletteOverlayState
    extends ConsumerState<CommandPaletteOverlay> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _scrollCtrl = ScrollController();
  String _query = '';
  int _selectedIdx = 0;

  @override
  void didUpdateWidget(covariant CommandPaletteOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open && !oldWidget.open) {
      // Reset state on open
      _searchCtrl.clear();
      _query = '';
      _selectedIdx = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event,
      List<CommandPaletteAction> actions) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (actions.isEmpty) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIdx = (_selectedIdx + 1).clamp(0, actions.length - 1);
      });
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIdx = (_selectedIdx - 1).clamp(0, actions.length - 1);
      });
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter) {
      _execute(actions[_selectedIdx]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _execute(CommandPaletteAction action) {
    widget.onActionSelected(action);
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.open) return const SizedBox.shrink();

    final svc = ref.watch(commandPaletteServiceProvider);
    final categories = ref.watch(categoriesV3StreamProvider).maybeWhen<List<CategoryV3Model>>(
          data: (d) => d,
          orElse: () => const <CategoryV3Model>[],
        );
    final actions = svc.buildActions(query: _query, categories: categories);

    // Clamp selected index in case query shortened the list
    if (_selectedIdx >= actions.length) {
      _selectedIdx = actions.isEmpty ? 0 : actions.length - 1;
    }

    return Stack(
      children: [
        // Scrim
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.4)),
          ),
        ),
        // Modal
        Center(
          child: Material(
            elevation: 20,
            borderRadius: BorderRadius.circular(16),
            color: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 480,
                maxHeight: 520,
              ),
              child: Focus(
                onKeyEvent: (n, e) => _onKey(n, e, actions),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SearchInput(
                      controller: _searchCtrl,
                      focus: _searchFocus,
                      onChanged: (v) => setState(() {
                        _query = v;
                        _selectedIdx = 0;
                      }),
                    ),
                    const Divider(height: 1, thickness: 0.5),
                    Flexible(
                      child: actions.isEmpty
                          ? const _NoMatch()
                          : _ResultsList(
                              actions: actions,
                              selectedIdx: _selectedIdx,
                              scrollCtrl: _scrollCtrl,
                              onTap: _execute,
                              onHover: (i) =>
                                  setState(() => _selectedIdx = i),
                            ),
                    ),
                    const _Footer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchInput extends StatelessWidget {
  const _SearchInput({
    required this.controller,
    required this.focus,
    required this.onChanged,
  });
  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 16, vertical: 8),
      child: TextField(
        controller: controller,
        focusNode: focus,
        autofocus: true,
        textDirection: TextDirection.rtl,
        decoration: const InputDecoration(
          hintText: 'הקלד פעולה / שם קטגוריה / תגית...',
          prefixIcon: Icon(Icons.search_rounded),
          border: InputBorder.none,
        ),
        onChanged: onChanged,
        style: const TextStyle(fontSize: 15),
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.actions,
    required this.selectedIdx,
    required this.scrollCtrl,
    required this.onTap,
    required this.onHover,
  });

  final List<CommandPaletteAction> actions;
  final int selectedIdx;
  final ScrollController scrollCtrl;
  final ValueChanged<CommandPaletteAction> onTap;
  final ValueChanged<int> onHover;

  @override
  Widget build(BuildContext context) {
    // Group by section ("תוצאות" for jump-to + tag, "פעולות מהירות" for static)
    final results = <CommandPaletteAction>[];
    final quickActions = <CommandPaletteAction>[];
    for (final a in actions) {
      final isJump = a.kind == CommandKind.jumpToCategory ||
          a.kind == CommandKind.jumpToSubcategory ||
          a.kind == CommandKind.filterByTag;
      (isJump ? results : quickActions).add(a);
    }

    final children = <Widget>[];
    var runningIdx = 0;
    if (results.isNotEmpty) {
      children.add(const _SectionHeader(text: 'תוצאות'));
      for (final a in results) {
        final myIdx = runningIdx++;
        children.add(_Row(
          action: a,
          selected: actions.indexOf(a) == selectedIdx,
          onTap: () => onTap(a),
          onHover: () => onHover(myIdx),
        ));
      }
    }
    if (quickActions.isNotEmpty) {
      children.add(const _SectionHeader(text: 'פעולות מהירות'));
      for (final a in quickActions) {
        children.add(_Row(
          action: a,
          selected: actions.indexOf(a) == selectedIdx,
          onTap: () => onTap(a),
          onHover: () => onHover(actions.indexOf(a)),
        ));
      }
    }

    return ListView(
      controller: scrollCtrl,
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      shrinkWrap: true,
      children: children,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF9CA3AF),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.action,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });
  final CommandPaletteAction action;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: Material(
        color:
            selected ? const Color(0xFFF0F1FF) : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(action.icon,
                    size: 16,
                    color: selected
                        ? const Color(0xFF6366F1)
                        : const Color(0xFF6B7280)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        action.primaryText,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? const Color(0xFF1A1A2E)
                              : const Color(0xFF1A1A2E),
                        ),
                      ),
                      if (action.secondaryText.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          action.secondaryText,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9CA3AF),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (action.shortcut != null)
                  Container(
                    padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      action.shortcut!,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontFamily: 'monospace',
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoMatch extends StatelessWidget {
  const _NoMatch();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsetsDirectional.all(24),
        child: Center(
          child: Text(
            'אין תוצאות',
            style: TextStyle(color: Color(0xFF9CA3AF)),
          ),
        ),
      );
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB), width: 0.5)),
      ),
      child: Row(
        children: [
          _kbd('↑↓'),
          const SizedBox(width: 4),
          const Text('נווט',
              style: TextStyle(fontSize: 10.5, color: Color(0xFF6B7280))),
          const SizedBox(width: 12),
          _kbd('↵'),
          const SizedBox(width: 4),
          const Text('בחר',
              style: TextStyle(fontSize: 10.5, color: Color(0xFF6B7280))),
          const SizedBox(width: 12),
          _kbd('Esc'),
          const SizedBox(width: 4),
          const Text('סגור',
              style: TextStyle(fontSize: 10.5, color: Color(0xFF6B7280))),
        ],
      ),
    );
  }

  Widget _kbd(String s) => Container(
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          s,
          style: const TextStyle(
            fontSize: 10,
            fontFamily: 'monospace',
            color: Color(0xFF374151),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

