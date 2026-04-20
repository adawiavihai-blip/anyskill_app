import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/categories_v3_controller.dart';
import '../models/saved_view.dart';

/// Search + sort + view-mode strip below the KPI row.
///
/// Per §7.1 row 3:
///   - Search input (debounced 200ms per spec §10)
///   - Saved views dropdown — minimal placeholder in Phase B (full picker
///     comes with `SavedViewDialog` in Phase D)
///   - Sort dropdown
///   - View-mode segmented switcher (tree / grid / analytics)
///
/// Filter dropdown (per §7.1) lives inside the saved view dialog (Phase D).
/// In Phase B, the user sets filters via `applySavedView` — for now we ship
/// just sort + view + search.
class ToolbarBar extends ConsumerStatefulWidget {
  const ToolbarBar({super.key});

  @override
  ConsumerState<ToolbarBar> createState() => _ToolbarBarState();
}

class _ToolbarBarState extends ConsumerState<ToolbarBar> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl.text =
        ref.read(categoriesV3ControllerProvider).searchQuery;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      ref.read(categoriesV3ControllerProvider.notifier).setSearch(v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(categoriesV3ControllerProvider);
    final ctrl = ref.read(categoriesV3ControllerProvider.notifier);

    return LayoutBuilder(builder: (context, c) {
      final compact = c.maxWidth < 720;
      final children = <Widget>[
        // Search input
        Expanded(
          flex: compact ? 1 : 2,
          child: TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              hintText: 'חיפוש קטגוריה / תגית...',
              isDense: true,
              contentPadding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Colors.black.withValues(alpha: 0.12)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Colors.black.withValues(alpha: 0.12)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: Color(0xFF6366F1), width: 1.5),
              ),
              suffixIcon: state.searchQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        ctrl.setSearch('');
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(maxWidth: 36),
                    ),
            ),
          ),
        ),

        // Sort
        SizedBox(
          width: compact ? 130 : 180,
          child: _PillDropdown<CategorySort>(
            value: state.sortBy,
            items: CategorySort.values
                .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(s.hebrewLabel,
                          style: const TextStyle(fontSize: 13)),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) ctrl.setSort(v);
            },
            icon: Icons.sort_rounded,
          ),
        ),

        // View mode
        _ViewModeToggle(
          current: state.viewMode,
          onChanged: ctrl.setViewMode,
        ),
      ];

      return Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children
            .map((w) => SizedBox(
                  height: 40,
                  child: Align(alignment: AlignmentDirectional.centerStart, child: w),
                ))
            .toList(),
      );
    });
  }
}

/// Small wrapped dropdown with a leading icon — keeps the toolbar visually
/// dense without sacrificing tap targets.
class _PillDropdown<T> extends StatelessWidget {
  const _PillDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.icon,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.only(start: 10, end: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF6B7280)),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                items: items,
                onChanged: onChanged,
                isDense: true,
                isExpanded: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.current, required this.onChanged});
  final ViewMode current;
  final ValueChanged<ViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ViewMode>(
      segments: const [
        ButtonSegment(
          value: ViewMode.tree,
          icon: Icon(Icons.account_tree_outlined, size: 16),
          tooltip: 'תצוגת עץ',
        ),
        ButtonSegment(
          value: ViewMode.grid,
          icon: Icon(Icons.grid_view_rounded, size: 16),
          tooltip: 'תצוגת רשת',
        ),
        ButtonSegment(
          value: ViewMode.analytics,
          icon: Icon(Icons.insert_chart_outlined_rounded, size: 16),
          tooltip: 'תצוגת אנליטיקה',
        ),
      ],
      selected: {current},
      onSelectionChanged: (s) => onChanged(s.first),
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: WidgetStateProperty.all(
          const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 6),
        ),
      ),
    );
  }
}
