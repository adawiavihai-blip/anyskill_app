import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/category_service.dart';
import '../services/ai_schema_service.dart';
import '../widgets/category_specs_widget.dart';

/// Admin Catalog Manager — CRUD for categories with multi-locale names,
/// image URLs, visibility toggle, and sub-category management.
///
/// Directly edits Firestore `categories/{docId}` documents.
class AdminCatalogTab extends StatefulWidget {
  const AdminCatalogTab({super.key});

  @override
  State<AdminCatalogTab> createState() => _AdminCatalogTabState();
}

class _AdminCatalogTabState extends State<AdminCatalogTab> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'ניהול קטלוג',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _showAddCategoryDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('הוסף קטגוריה'),
                ),
              ],
            ),
          ),
          // Category List
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: CategoryService.streamMainCategories(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snap.hasData || snap.data!.isEmpty) {
                  return const Center(child: Text('אין קטגוריות'));
                }

                final categories = snap.data!;

                return ListView.builder(
                  itemCount: categories.length,
                  itemBuilder: (ctx, idx) {
                    final cat = categories[idx];
                    final catId = cat['id'] as String? ?? '';
                    final name = cat['name'] as String? ?? '';
                    final nameEn = cat['nameEn'] as String?;
                    final nameEs = cat['nameEs'] as String?;
                    final imgUrl = cat['img'] as String? ?? '';
                    final isHidden = cat['isHidden'] as bool? ?? false;

                    return _CategoryCard(
                      catId: catId,
                      name: name,
                      nameEn: nameEn,
                      nameEs: nameEs,
                      imgUrl: imgUrl,
                      isHidden: isHidden,
                      onUpdate: () => setState(() {}),
                      onDelete: () => setState(() {}),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showAddCategoryDialog() {
    final nameCtrl = TextEditingController();
    final imgCtrl = TextEditingController();
    String? selectedIcon;
    List<SchemaField> generatedSchema = [];
    bool isGenerating = false;
    String? aiError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: const Text('הוסף קטגוריה חדשה'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Category name ────────────────────────────────────────
                TextField(
                  controller: nameCtrl,
                  textAlign: TextAlign.start,
                  decoration: const InputDecoration(
                    labelText: 'שם (עברית)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Image URL ────────────────────────────────────────────
                TextField(
                  controller: imgCtrl,
                  textAlign: TextAlign.start,
                  decoration: const InputDecoration(
                    labelText: 'URL תמונה',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),

                // ── Icon selector ────────────────────────────────────────
                DropdownButton<String>(
                  isExpanded: true,
                  hint: const Text('בחר אייקון'),
                  value: selectedIcon,
                  items: CategoryService.iconMap.keys
                      .map((k) =>
                          DropdownMenuItem(value: k, child: Text(k)))
                      .toList(),
                  onChanged: (v) =>
                      setDialogState(() => selectedIcon = v),
                ),

                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),

                // ── AI Schema Generator ──────────────────────────────────
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'סכמת שירות (שדות מותאמים)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 34,
                      child: ElevatedButton.icon(
                        icon: isGenerating
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                            : const Icon(Icons.auto_awesome, size: 16),
                        label: Text(
                          isGenerating ? 'יוצר...' : 'צור עם AI',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12),
                        ),
                        onPressed: isGenerating
                            ? null
                            : () async {
                                final name = nameCtrl.text.trim();
                                if (name.length < 2) {
                                  setDialogState(() => aiError =
                                      'הזן שם קטגוריה לפני יצירת סכמה');
                                  return;
                                }
                                setDialogState(() {
                                  isGenerating = true;
                                  aiError = null;
                                });
                                try {
                                  final schema =
                                      await AiSchemaService.generate(
                                          name);
                                  setDialogState(() {
                                    generatedSchema = schema;
                                    isGenerating = false;
                                  });
                                } on AiSchemaException catch (e) {
                                  setDialogState(() {
                                    aiError = e.message;
                                    isGenerating = false;
                                  });
                                }
                              },
                      ),
                    ),
                  ],
                ),

                // ── AI error ─────────────────────────────────────────────
                if (aiError != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      aiError!,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFFDC2626)),
                    ),
                  ),
                ],

                // ── Schema preview ───────────────────────────────────────
                if (generatedSchema.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F0FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFF6366F1)
                              .withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.auto_awesome,
                                size: 14, color: Color(0xFF6366F1)),
                            const SizedBox(width: 6),
                            const Text(
                              'תצוגה מקדימה — שדות שנוצרו',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF6366F1),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${generatedSchema.length} שדות',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF9CA3AF)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ...generatedSchema.map((f) => Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  // Type icon
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6366F1)
                                          .withValues(alpha: 0.1),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: Icon(
                                      _typeIcon(f.type),
                                      size: 14,
                                      color:
                                          const Color(0xFF6366F1),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      f.label,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight:
                                              FontWeight.w500),
                                    ),
                                  ),
                                  if (f.unit.isNotEmpty)
                                    Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2),
                                      decoration: BoxDecoration(
                                        color:
                                            const Color(0xFF6366F1)
                                                .withValues(
                                                    alpha: 0.08),
                                        borderRadius:
                                            BorderRadius.circular(
                                                6),
                                      ),
                                      child: Text(
                                        f.unit,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight:
                                              FontWeight.w600,
                                          color:
                                              Color(0xFF6366F1),
                                        ),
                                      ),
                                    ),
                                  if (f.type == 'bool')
                                    const Icon(
                                        Icons.toggle_on_outlined,
                                        size: 16,
                                        color: Color(0xFF10B981)),
                                  if (f.type == 'dropdown')
                                    Text(
                                      '${f.options.length} אפשרויות',
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color:
                                              Color(0xFF9CA3AF)),
                                    ),
                                ],
                              ),
                            )),
                        const SizedBox(height: 6),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton.icon(
                            icon: const Icon(Icons.delete_outline,
                                size: 14),
                            label: const Text('נקה סכמה',
                                style: TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            onPressed: () => setDialogState(
                                () => generatedSchema = []),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                if (nameCtrl.text.isEmpty || selectedIcon == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('נא למלא את כל השדות')),
                  );
                  return;
                }

                try {
                  final payload = <String, dynamic>{
                    'name': nameCtrl.text.trim(),
                    'iconName': selectedIcon,
                    'img': imgCtrl.text.trim(),
                    'parentId': '',
                    'order':
                        DateTime.now().millisecondsSinceEpoch,
                    'clickCount': 0,
                  };

                  // Include AI-generated schema if present
                  if (generatedSchema.isNotEmpty) {
                    payload['serviceSchema'] =
                        generatedSchema.map((f) => f.toMap()).toList();
                  }

                  await FirebaseFirestore.instance
                      .collection('categories')
                      .add(payload);

                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(generatedSchema.isNotEmpty
                            ? '✓ קטגוריה + סכמת שירות נוספו בהצלחה'
                            : '✓ קטגוריה נוספה בהצלחה'),
                        backgroundColor: const Color(0xFF10B981),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('שגיאה: $e')),
                    );
                  }
                }
              },
              child: const Text('הוסף'),
            ),
          ],
        ),
      ),
    );
  }

  IconData _typeIcon(String type) => switch (type) {
        'number' => Icons.tag,
        'text' => Icons.text_fields,
        'bool' => Icons.toggle_on_outlined,
        'dropdown' => Icons.list,
        _ => Icons.help_outline,
      };
}

/// Single category card with expandable details.
class _CategoryCard extends StatefulWidget {
  final String catId;
  final String name;
  final String? nameEn;
  final String? nameEs;
  final String imgUrl;
  final bool isHidden;
  final VoidCallback onUpdate;
  final VoidCallback onDelete;

  const _CategoryCard({
    required this.catId,
    required this.name,
    required this.nameEn,
    required this.nameEs,
    required this.imgUrl,
    required this.isHidden,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  late TextEditingController _nameHeCtrl;
  late TextEditingController _nameEnCtrl;
  late TextEditingController _nameEsCtrl;
  late TextEditingController _imgCtrl;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _nameHeCtrl = TextEditingController(text: widget.name);
    _nameEnCtrl = TextEditingController(text: widget.nameEn ?? '');
    _nameEsCtrl = TextEditingController(text: widget.nameEs ?? '');
    _imgCtrl = TextEditingController(text: widget.imgUrl);
  }

  @override
  void dispose() {
    _nameHeCtrl.dispose();
    _nameEnCtrl.dispose();
    _nameEsCtrl.dispose();
    _imgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: ExpansionTile(
        title: Row(
          children: [
            if (widget.imgUrl.isNotEmpty)
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  image: DecorationImage(
                    image: NetworkImage(widget.imgUrl),
                    fit: BoxFit.cover,
                  ),
                ),
              )
            else
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.grey[300],
                ),
                child: const Icon(Icons.image),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (widget.nameEn != null)
                    Text(
                      widget.nameEn!,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                ],
              ),
            ),
            if (widget.isHidden)
              const Chip(label: Text('מוסתר'), backgroundColor: Colors.orange),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Multi-locale name fields
                const Text(
                  'שמות בשפות שונות',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameHeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'עברית',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _saveField('name', _nameHeCtrl.text),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameEnCtrl,
                  decoration: const InputDecoration(
                    labelText: 'English',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _saveField('nameEn', _nameEnCtrl.text),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameEsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Español',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _saveField('nameEs', _nameEsCtrl.text),
                ),
                const SizedBox(height: 16),

                // Image URL
                const Text(
                  'תמונה',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _imgCtrl,
                  decoration: const InputDecoration(
                    labelText: 'URL',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  onChanged: (_) => _saveField('img', _imgCtrl.text),
                ),
                const SizedBox(height: 16),

                // Visibility toggle
                const Text(
                  'נראות',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('הסתר מחיפוש:'),
                    const SizedBox(width: 12),
                    Switch(
                      value: widget.isHidden,
                      onChanged: (val) {
                        _saveField('isHidden', val);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Delete button
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _deleting ? null : _showDeleteConfirm,
                      icon: const Icon(Icons.delete),
                      label: const Text('מחק'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveField(String field, dynamic value) async {
    try {
      await CategoryService.updateCategory(widget.catId, {field: value});
      widget.onUpdate();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e')),
        );
      }
    }
  }

  void _showDeleteConfirm() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('מחק קטגוריה'),
        content: const Text(
          'פעולה זו תמחק את הקטגוריה וכל תת-הקטגוריות שלה. אי אפשר לשחזר.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _deleting = true);

              try {
                await CategoryService.deleteCategory(widget.catId, widget.imgUrl);
                widget.onDelete();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✓ קטגוריה נמחקה')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('שגיאה: $e')),
                  );
                  setState(() => _deleting = false);
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('מחק'),
          ),
        ],
      ),
    );
  }
}
