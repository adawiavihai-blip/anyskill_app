import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/categories_v3_controller.dart';
import '../models/category_v3_model.dart';

/// Bottom-of-page footer with the heavyweight admin power-tools per spec
/// §7.1 row 10: refresh analytics · reset popularity · export JSON · import JSON.
///
/// Each button shows a loading indicator while running and surfaces a snackbar
/// on success/error. Reset and Import are gated by a confirm dialog because
/// they're destructive.
class PowerToolsFooter extends ConsumerStatefulWidget {
  const PowerToolsFooter({super.key});

  @override
  ConsumerState<PowerToolsFooter> createState() => _PowerToolsFooterState();
}

class _PowerToolsFooterState extends ConsumerState<PowerToolsFooter> {
  bool _refreshing = false;
  bool _resetting = false;
  bool _exporting = false;
  bool _importing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res =
          await ref.read(categoriesV3ServiceProvider).triggerAnalyticsRefresh();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content:
            Text('האנליטיקה רוענה — ${res['updated'] ?? 0} קטגוריות עודכנו'),
        backgroundColor: const Color(0xFF10B981),
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('הרענון נכשל: $e'),
        backgroundColor: const Color(0xFFEF4444),
      ));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _reset() async {
    // Capture context-derived objects BEFORE the first await.
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('איפוס מוני פופולריות'),
        content: const Text(
          'הפעולה תאפס את clickCount של כל הקטגוריות ל-0. '
          'הדירוג הדינמי יתחיל מחדש.\n\nלהמשיך?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול',
                style: TextStyle(color: Color(0xFF6B7280))),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              foregroundColor: const Color(0xFFB45309),
              backgroundColor: const Color(0xFFFEF3C7),
            ),
            child: const Text('אפס'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _resetting = true);
    try {
      final db = FirebaseFirestore.instance;
      final snap = await db.collection('categories').limit(500).get();
      final batch = db.batch();
      for (final d in snap.docs) {
        batch.update(d.reference, {'clickCount': 0});
      }
      await batch.commit();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('${snap.docs.length} קטגוריות אופסו'),
        backgroundColor: const Color(0xFF10B981),
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('איפוס נכשל: $e'),
        backgroundColor: const Color(0xFFEF4444),
      ));
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final cats = ref.read(categoriesV3StreamProvider).maybeWhen(
            data: (d) => d,
            orElse: () => const <CategoryV3Model>[],
          );
      // Strip CF-owned + transient state before export.
      final dump = cats
          .map((c) => <String, dynamic>{
                'id': c.id,
                'name': c.name,
                'parentId': c.parentId,
                'iconUrl': c.iconUrl,
                if (c.imageUrl != null) 'imageUrl': c.imageUrl,
                if (c.color != null) 'color': c.color,
                'order': c.order,
                if (c.csmModule != null) 'csm_module': c.csmModule,
                'custom_tags': c.customTags,
                'admin_meta': {
                  'is_pinned': c.isPinned,
                  'is_hidden': c.isHidden,
                  'notes': c.adminMeta?.notes ?? '',
                },
              })
          .toList();
      final json = const JsonEncoder.withIndent('  ').convert(dump);
      await Clipboard.setData(ClipboardData(text: json));
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(
            '${cats.length} קטגוריות הועתקו ללוח (JSON). הדבק לקובץ לשמירה.'),
        backgroundColor: const Color(0xFF10B981),
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('ייצוא נכשל: $e'),
        backgroundColor: const Color(0xFFEF4444),
      ));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _import() async {
    // Capture context-derived objects BEFORE the first await.
    final messenger = ScaffoldMessenger.of(context);
    final pasted = await _showImportDialog();
    if (pasted == null || pasted.trim().isEmpty) return;

    setState(() => _importing = true);
    try {
      final raw = jsonDecode(pasted);
      if (raw is! List) throw 'JSON חייב להיות מערך';
      var updated = 0;
      var created = 0;
      final svc = ref.read(categoriesV3ServiceProvider);
      for (final item in raw) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final id = m['id'] as String?;
        final name = m['name'] as String?;
        if (name == null || name.trim().isEmpty) continue;

        if (id != null && id.isNotEmpty) {
          // Existing → patch
          await svc.update(id, <String, dynamic>{
            'name': name,
            if (m['iconUrl'] != null) 'iconUrl': m['iconUrl'],
            if (m['imageUrl'] != null) 'imageUrl': m['imageUrl'],
            if (m['color'] != null) 'color': m['color'],
            if (m['csm_module'] != null) 'csm_module': m['csm_module'],
            if (m['custom_tags'] is List) 'custom_tags': m['custom_tags'],
          });
          updated += 1;
        } else {
          await svc.create(
            name: name,
            iconUrl: (m['iconUrl'] as String?) ?? '',
            parentId: (m['parentId'] as String?) ?? '',
            imageUrl: m['imageUrl'] as String?,
            color: m['color'] as String?,
            csmModule: m['csm_module'] as String?,
            customTags: m['custom_tags'] is List
                ? List<String>.from(
                    (m['custom_tags'] as List).whereType<String>())
                : const [],
          );
          created += 1;
        }
      }
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content:
            Text('יובאו: $created נוצרו, $updated עודכנו'),
        backgroundColor: const Color(0xFF10B981),
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('ייבוא נכשל: $e'),
        backgroundColor: const Color(0xFFEF4444),
      ));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<String?> _showImportDialog() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('ייבוא JSON'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'הדבק כאן את ה-JSON המיוצא. רשומות עם id יעודכנו, אחרות ייווצרו.',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 220,
                child: TextField(
                  controller: ctrl,
                  maxLines: null,
                  expands: true,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  decoration: const InputDecoration(
                    hintText: '[{"name": "..."}]',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('ביטול',
                style: TextStyle(color: Color(0xFF6B7280))),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
            ),
            child: const Text('ייבא'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsetsDirectional.only(top: 24),
      padding: const EdgeInsetsDirectional.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.handyman_rounded,
                  color: Color(0xFF6B7280), size: 16),
              SizedBox(width: 6),
              Text(
                'כלי-עוצמה',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280),
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ToolBtn(
                icon: Icons.sync_rounded,
                label: 'רענן אנליטיקה',
                running: _refreshing,
                onTap: _refresh,
              ),
              _ToolBtn(
                icon: Icons.download_rounded,
                label: 'ייצא JSON',
                running: _exporting,
                onTap: _export,
              ),
              _ToolBtn(
                icon: Icons.upload_rounded,
                label: 'ייבא JSON',
                running: _importing,
                onTap: _import,
              ),
              _ToolBtn(
                icon: Icons.restart_alt_rounded,
                label: 'אפס פופולריות',
                running: _resetting,
                onTap: _reset,
                destructive: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  const _ToolBtn({
    required this.icon,
    required this.label,
    required this.running,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final bool running;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color =
        destructive ? const Color(0xFFB45309) : const Color(0xFF6366F1);
    final bg =
        destructive ? const Color(0xFFFEF3C7) : const Color(0xFFEFF0FF);
    return InkWell(
      onTap: running ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            running
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: color),
                  )
                : Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
