import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/categories_v3_controller.dart';
import '../models/category_v3_model.dart';

/// Full-feature category editor with 5 tabs (spec §2):
///   1. פרטים    — name / parent / color / csm_module / custom_tags
///   2. תמונה    — iconUrl + imageUrl preview
///   3. תתי      — sub-categories list (read-only here, edit via row dialog)
///   4. ספקים    — providers count + open users-tab CTA
///   5. סטטיסטיקה — analytics snapshot (orders/revenue/health/sparkline)
///
/// Phase D ships the structure + tabs 1, 2, 5 fully wired. Tabs 3+4 are
/// read-only here — full sub-cat editor + providers manager land in Phase E.
class EditCategoryDialog extends ConsumerStatefulWidget {
  const EditCategoryDialog({super.key, required this.categoryId});

  final String categoryId;

  static Future<bool?> show(BuildContext context, String categoryId) =>
      showDialog<bool>(
        context: context,
        builder: (_) => EditCategoryDialog(categoryId: categoryId),
      );

  @override
  ConsumerState<EditCategoryDialog> createState() =>
      _EditCategoryDialogState();
}

class _EditCategoryDialogState extends ConsumerState<EditCategoryDialog> {
  // Form state — initialized from the loaded category in didChangeDependencies
  late final TextEditingController _nameCtrl;
  late final TextEditingController _iconUrlCtrl;
  late final TextEditingController _imageUrlCtrl;
  late final TextEditingController _colorCtrl;
  late final TextEditingController _customTagsCtrl;
  late final TextEditingController _notesCtrl;
  String? _csmModule;
  CategoryV3Model? _initial;
  bool _saving = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _iconUrlCtrl = TextEditingController();
    _imageUrlCtrl = TextEditingController();
    _colorCtrl = TextEditingController();
    _customTagsCtrl = TextEditingController();
    _notesCtrl = TextEditingController();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final c = await ref
        .read(categoriesV3ServiceProvider)
        .getOnce(widget.categoryId);
    if (!mounted || c == null) return;
    setState(() {
      _initial = c;
      _nameCtrl.text = c.name;
      _iconUrlCtrl.text = c.iconUrl;
      _imageUrlCtrl.text = c.imageUrl ?? '';
      _colorCtrl.text = c.color ?? '';
      _customTagsCtrl.text = c.customTags.join(', ');
      _notesCtrl.text = c.adminMeta?.notes ?? '';
      _csmModule = c.csmModule;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _iconUrlCtrl.dispose();
    _imageUrlCtrl.dispose();
    _colorCtrl.dispose();
    _customTagsCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final patch = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'iconUrl': _iconUrlCtrl.text.trim(),
        if (_imageUrlCtrl.text.trim().isNotEmpty)
          'imageUrl': _imageUrlCtrl.text.trim(),
        if (_colorCtrl.text.trim().isNotEmpty)
          'color': _colorCtrl.text.trim(),
        if (_csmModule != null) 'csm_module': _csmModule,
        'custom_tags': _customTagsCtrl.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        'admin_meta.notes': _notesCtrl.text.trim(),
      };
      await ref
          .read(categoriesV3ServiceProvider)
          .update(widget.categoryId, patch);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שמירה נכשלה: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 600),
          child: !_loaded || _initial == null
              ? const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                )
              : DefaultTabController(
                  length: 5,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Header(
                        category: _initial!,
                        onClose: () => Navigator.pop(context, false),
                      ),
                      const TabBar(
                        labelColor: Color(0xFF6366F1),
                        unselectedLabelColor: Color(0xFF6B7280),
                        indicatorColor: Color(0xFF6366F1),
                        indicatorSize: TabBarIndicatorSize.label,
                        labelStyle: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700),
                        tabs: [
                          Tab(text: 'פרטים'),
                          Tab(text: 'תמונה'),
                          Tab(text: 'תתי'),
                          Tab(text: 'ספקים'),
                          Tab(text: 'סטטיסטיקה'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _DetailsTab(
                              nameCtrl: _nameCtrl,
                              colorCtrl: _colorCtrl,
                              customTagsCtrl: _customTagsCtrl,
                              notesCtrl: _notesCtrl,
                              csmModule: _csmModule,
                              onCsmChanged: (v) =>
                                  setState(() => _csmModule = v),
                            ),
                            _ImageTab(
                              iconCtrl: _iconUrlCtrl,
                              imageCtrl: _imageUrlCtrl,
                            ),
                            _SubcatTab(parentId: widget.categoryId),
                            _ProvidersTab(category: _initial!),
                            _StatsTab(category: _initial!),
                          ],
                        ),
                      ),
                      const Divider(height: 1, thickness: 0.5),
                      Padding(
                        padding: const EdgeInsetsDirectional.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _saving
                                  ? null
                                  : () => Navigator.pop(context, false),
                              child: const Text('ביטול',
                                  style:
                                      TextStyle(color: Color(0xFF6B7280))),
                            ),
                            const SizedBox(width: 8),
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
                                          strokeWidth: 2,
                                          color: Colors.white))
                                  : const Text('שמור שינויים'),
                            ),
                          ],
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

class _Header extends StatelessWidget {
  const _Header({required this.category, required this.onClose});
  final CategoryV3Model category;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsetsDirectional.fromSTEB(16, 14, 8, 8),
      child: Row(
        children: [
          const Icon(Icons.edit_rounded, color: Color(0xFF6366F1), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'עריכה: ${category.name}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded)),
        ],
      ),
    );
  }
}

class _DetailsTab extends StatelessWidget {
  const _DetailsTab({
    required this.nameCtrl,
    required this.colorCtrl,
    required this.customTagsCtrl,
    required this.notesCtrl,
    required this.csmModule,
    required this.onCsmChanged,
  });
  final TextEditingController nameCtrl;
  final TextEditingController colorCtrl;
  final TextEditingController customTagsCtrl;
  final TextEditingController notesCtrl;
  final String? csmModule;
  final ValueChanged<String?> onCsmChanged;

  @override
  Widget build(BuildContext context) {
    final csmOptions = const <String?>[
      null,
      'cleaning',
      'massage',
      'delivery',
      'handyman',
      'pest_control',
      'fitness_trainer',
    ];
    return ListView(
      padding: const EdgeInsetsDirectional.all(16),
      children: [
        TextField(
          controller: nameCtrl,
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(
            labelText: 'שם הקטגוריה',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: colorCtrl,
          decoration: const InputDecoration(
            labelText: 'צבע (Hex, e.g. #6366F1)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          value: csmModule,
          decoration: const InputDecoration(
            labelText: 'מודול CSM (Category-Specific Module)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final v in csmOptions)
              DropdownMenuItem(
                value: v,
                child: Text(v ?? '— ללא —'),
              ),
          ],
          onChanged: onCsmChanged,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: customTagsCtrl,
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(
            labelText: 'תגיות מותאמות (מופרדות בפסיקים)',
            hintText: 'לדוגמה: 🔥 חם, 🚀 צמיחה',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: notesCtrl,
          textDirection: TextDirection.rtl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'הערות פנימיות',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }
}

class _ImageTab extends StatefulWidget {
  const _ImageTab({required this.iconCtrl, required this.imageCtrl});
  final TextEditingController iconCtrl;
  final TextEditingController imageCtrl;

  @override
  State<_ImageTab> createState() => _ImageTabState();
}

class _ImageTabState extends State<_ImageTab> {
  @override
  void initState() {
    super.initState();
    widget.iconCtrl.addListener(_repaint);
    widget.imageCtrl.addListener(_repaint);
  }

  @override
  void dispose() {
    widget.iconCtrl.removeListener(_repaint);
    widget.imageCtrl.removeListener(_repaint);
    super.dispose();
  }

  void _repaint() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsetsDirectional.all(16),
      children: [
        TextField(
          controller: widget.iconCtrl,
          decoration: const InputDecoration(
            labelText: 'iconUrl (תמונה זעירה)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        _Preview(url: widget.iconCtrl.text, label: 'תצוגה מקדימה — Icon'),
        const SizedBox(height: 16),
        TextField(
          controller: widget.imageCtrl,
          decoration: const InputDecoration(
            labelText: 'imageUrl (תמונה ראשית)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        _Preview(url: widget.imageCtrl.text, label: 'תצוגה מקדימה — Image'),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.url, required this.label});
  final String url;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: Color(0xFF6B7280))),
        const SizedBox(height: 6),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          ),
          child: url.trim().isEmpty
              ? const Center(
                  child: Icon(Icons.image_not_supported_outlined,
                      color: Color(0xFF9CA3AF)))
              : ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_outlined,
                          color: Color(0xFFEF4444)),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _SubcatTab extends ConsumerWidget {
  const _SubcatTab({required this.parentId});
  final String parentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(categoriesV3StreamProvider).maybeWhen(
          data: (d) => d,
          orElse: () => const <CategoryV3Model>[],
        );
    final subs = all.where((c) => c.parentId == parentId).toList();

    return Padding(
      padding: const EdgeInsetsDirectional.all(16),
      child: subs.isEmpty
          ? const Center(
              child: Text(
                'אין תתי-קטגוריות.\nניתן להוסיף דרך מסך הקטגוריות הראשי.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF9CA3AF)),
              ),
            )
          : ListView.builder(
              itemCount: subs.length,
              itemBuilder: (_, i) {
                final s = subs[i];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor:
                        const Color(0xFF6366F1).withValues(alpha: 0.12),
                    child: Text(
                      s.name.isNotEmpty ? s.name.characters.first : '?',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                  ),
                  title: Text(s.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${s.analytics?.activeProviders ?? 0} ספקים',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: const Icon(Icons.chevron_left_rounded, size: 18),
                );
              },
            ),
    );
  }
}

class _ProvidersTab extends StatelessWidget {
  const _ProvidersTab({required this.category});
  final CategoryV3Model category;

  @override
  Widget build(BuildContext context) {
    final activeProviders = category.analytics?.activeProviders ?? 0;
    return Padding(
      padding: const EdgeInsetsDirectional.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsetsDirectional.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEFF6FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.groups_rounded,
                      color: Color(0xFF3B82F6), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$activeProviders ספקים פעילים',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${category.analytics?.coverageCities ?? 0} ערים שונות',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'לעריכת ספקים בודדים, השתמש בטאב "ניהול → משתמשים" באדמין.',
            style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
          ),
        ],
      ),
    );
  }
}

class _StatsTab extends ConsumerStatefulWidget {
  const _StatsTab({required this.category});
  final CategoryV3Model category;

  @override
  ConsumerState<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends ConsumerState<_StatsTab> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await ref.read(categoriesV3ServiceProvider).triggerAnalyticsRefresh();
    } catch (_) {
      // No-op — toast comes from the service
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.category.analytics;
    return Padding(
      padding: const EdgeInsetsDirectional.all(16),
      child: a == null
          ? const Center(
              child: Text(
                'אין נתוני אנליטיקה עדיין.\nרוץ Refresh לאסוף עכשיו.',
                style: TextStyle(color: Color(0xFF9CA3AF)),
                textAlign: TextAlign.center,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Stat(label: 'הזמנות (30 ימים)', value: '${a.orders30d}'),
                _Stat(
                    label: 'הכנסות',
                    value: '₪${a.revenue30d.toStringAsFixed(0)}'),
                _Stat(
                    label: 'צמיחה',
                    value:
                        '${a.growth30d >= 0 ? "+" : ""}${a.growth30d.toStringAsFixed(0)}%'),
                _Stat(
                    label: 'ספקים פעילים', value: '${a.activeProviders}'),
                _Stat(label: 'ערים', value: '${a.coverageCities}'),
                _Stat(label: 'ציון בריאות', value: '${a.healthScore}/100'),
                if (a.lastUpdated != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 8),
                    child: Text(
                      'מעודכן: ${_fmtTime(a.lastUpdated!)}',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF9CA3AF)),
                    ),
                  ),
                const SizedBox(height: 16),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _refreshing ? null : _refresh,
                    icon: _refreshing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync_rounded, size: 16),
                    label: Text(
                        _refreshing ? 'מרענן...' : 'הרץ Refresh עכשיו'),
                  ),
                ),
              ],
            ),
    );
  }

  String _fmtTime(DateTime t) {
    final ts = Timestamp.fromDate(t);
    return ts.toDate().toLocal().toString().substring(0, 19);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF6B7280))),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ],
      ),
    );
  }
}
