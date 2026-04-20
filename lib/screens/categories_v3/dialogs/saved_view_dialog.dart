import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/categories_v3_controller.dart';
import '../models/saved_view.dart';

/// Save the current toolbar combination (search + filters + sort + view) as
/// a named preset under the current admin's `admin_saved_views`.
class SavedViewDialog extends ConsumerStatefulWidget {
  const SavedViewDialog({super.key});

  static Future<bool?> show(BuildContext context) =>
      showDialog<bool>(
        context: context,
        builder: (_) => const SavedViewDialog(),
      );

  @override
  ConsumerState<SavedViewDialog> createState() => _SavedViewDialogState();
}

class _SavedViewDialogState extends ConsumerState<SavedViewDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  bool _saving = false;
  bool _isDefault = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'נא לתת שם לתצוגה');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final state = ref.read(categoriesV3ControllerProvider);
      await ref.read(savedViewsServiceProvider).save(
            name: name,
            filters: state.filters,
            sortBy: state.sortBy,
            viewMode: state.viewMode,
            isDefault: _isDefault,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'שמירה נכשלה: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(categoriesV3ControllerProvider);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.bookmark_add_outlined,
                color: Color(0xFF6366F1), size: 20),
            SizedBox(width: 8),
            Text('שמור תצוגה',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'שמור את שילוב הפילטרים, הסידור והתצוגה הנוכחי כקיצור.',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 12),
            // Summary of what will be saved
            _SummaryBox(state: state),
            const SizedBox(height: 14),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                labelText: 'שם התצוגה',
                hintText: 'לדוגמה: "קטגוריות עם בעיות"',
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _isDefault,
              onChanged: (v) => setState(() => _isDefault = v ?? false),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'הגדר כברירת מחדל',
                style: TextStyle(fontSize: 13),
              ),
              subtitle: const Text(
                'תיטען אוטומטית בכניסה לטאב',
                style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(
                _error!,
                style: const TextStyle(
                    color: Color(0xFFEF4444), fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, null),
            child: const Text('ביטול',
                style: TextStyle(color: Color(0xFF6B7280))),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
            ),
            child: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('שמור'),
          ),
        ],
      ),
    );
  }
}

class _SummaryBox extends StatelessWidget {
  const _SummaryBox({required this.state});
  final CategoriesScreenState state;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[];
    lines.add('סדר: ${state.sortBy.hebrewLabel}');
    lines.add('תצוגה: ${_viewLabel(state.viewMode)}');
    if (state.searchQuery.isNotEmpty) {
      lines.add('חיפוש: "${state.searchQuery}"');
    }
    if (state.filters.isAnyApplied) {
      lines.add('פילטרים פעילים');
    }

    return Container(
      padding:
          const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in lines)
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(vertical: 1),
              child: Row(
                children: [
                  const Icon(Icons.fiber_manual_record,
                      size: 6, color: Color(0xFF9CA3AF)),
                  const SizedBox(width: 6),
                  Text(l,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF374151))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _viewLabel(ViewMode m) {
    switch (m) {
      case ViewMode.tree:
        return 'עץ';
      case ViewMode.grid:
        return 'רשת';
      case ViewMode.analytics:
        return 'אנליטיקה';
    }
  }
}
