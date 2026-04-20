import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/categories_v3_controller.dart';

/// 3-step wizard for creating a new category (spec §2):
///   1. פרטים   — name + parent + color + csm_module + custom_tags
///   2. תמונה   — iconUrl + imageUrl preview
///   3. סיכום   — review then create
///
/// Returns the new category id when creation succeeds, `null` on cancel.
class AddCategoryDialog extends ConsumerStatefulWidget {
  const AddCategoryDialog({super.key, this.parentId = ''});
  final String parentId;

  static Future<String?> show(BuildContext context, {String parentId = ''}) =>
      showDialog<String>(
        context: context,
        builder: (_) => AddCategoryDialog(parentId: parentId),
      );

  @override
  ConsumerState<AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends ConsumerState<AddCategoryDialog> {
  int _step = 0;

  // Step 1: details
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _colorCtrl = TextEditingController();
  final TextEditingController _customTagsCtrl = TextEditingController();
  String? _csmModule;

  // Step 2: image
  final TextEditingController _iconCtrl = TextEditingController();
  final TextEditingController _imageCtrl = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _colorCtrl.dispose();
    _customTagsCtrl.dispose();
    _iconCtrl.dispose();
    _imageCtrl.dispose();
    super.dispose();
  }

  bool get _step1Valid => _nameCtrl.text.trim().length >= 2;
  bool get _canFinish => _step1Valid; // image step is optional

  void _next() {
    if (_step < 2) setState(() => _step += 1);
  }

  void _back() {
    if (_step > 0) setState(() => _step -= 1);
  }

  Future<void> _create() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await ref.read(categoriesV3ServiceProvider).create(
            name: _nameCtrl.text.trim(),
            iconUrl: _iconCtrl.text.trim(),
            parentId: widget.parentId,
            imageUrl: _imageCtrl.text.trim().isEmpty
                ? null
                : _imageCtrl.text.trim(),
            color: _colorCtrl.text.trim().isEmpty
                ? null
                : _colorCtrl.text.trim(),
            csmModule: _csmModule,
            customTags: _customTagsCtrl.text
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
          );
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'יצירה נכשלה: $e';
        });
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
          constraints: const BoxConstraints(maxWidth: 540, maxHeight: 540),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Header(
                step: _step,
                onClose: () => Navigator.pop(context, null),
              ),
              _StepperStrip(step: _step),
              const Divider(height: 1, thickness: 0.5),
              Expanded(
                child: _step == 0
                    ? _DetailsStep(
                        nameCtrl: _nameCtrl,
                        colorCtrl: _colorCtrl,
                        customTagsCtrl: _customTagsCtrl,
                        csmModule: _csmModule,
                        onCsmChanged: (v) => setState(() => _csmModule = v),
                        onChanged: () => setState(() {}),
                      )
                    : _step == 1
                        ? _ImageStep(
                            iconCtrl: _iconCtrl,
                            imageCtrl: _imageCtrl,
                          )
                        : _ReviewStep(
                            name: _nameCtrl.text.trim(),
                            color: _colorCtrl.text.trim(),
                            iconUrl: _iconCtrl.text.trim(),
                            imageUrl: _imageCtrl.text.trim(),
                            csmModule: _csmModule,
                            customTags: _customTagsCtrl.text,
                            error: _error,
                          ),
              ),
              const Divider(height: 1, thickness: 0.5),
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    if (_step > 0)
                      TextButton.icon(
                        onPressed: _saving ? null : _back,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                        label: const Text('הקודם'),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed:
                          _saving ? null : () => Navigator.pop(context, null),
                      child: const Text('ביטול',
                          style: TextStyle(color: Color(0xFF6B7280))),
                    ),
                    const SizedBox(width: 8),
                    if (_step < 2)
                      FilledButton.icon(
                        onPressed: !_step1Valid && _step == 0 ? null : _next,
                        icon: const Icon(Icons.arrow_back_rounded, size: 16),
                        label: const Text('הבא'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                        ),
                      )
                    else
                      FilledButton(
                        onPressed: !_canFinish || _saving ? null : _create,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('צור קטגוריה'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.step, required this.onClose});
  final int step;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final titles = ['קטגוריה חדשה — פרטים', 'קטגוריה חדשה — תמונה', 'אישור ויצירה'];
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 8, 8),
      child: Row(
        children: [
          const Icon(Icons.add_circle_outline_rounded,
              color: Color(0xFF10B981), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              titles[step],
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

class _StepperStrip extends StatelessWidget {
  const _StepperStrip({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            _Dot(active: i <= step, label: ['פרטים', 'תמונה', 'אישור'][i]),
            if (i < 2)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsetsDirectional.symmetric(horizontal: 6),
                  color: i < step
                      ? const Color(0xFF6366F1)
                      : const Color(0xFFE5E7EB),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active, required this.label});
  final bool active;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF6366F1) : const Color(0xFFE5E7EB);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Icon(
            Icons.check_rounded,
            size: 14,
            color: active ? Colors.white : const Color(0xFF9CA3AF),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: active ? const Color(0xFF1A1A2E) : const Color(0xFF9CA3AF),
          ),
        ),
      ],
    );
  }
}

class _DetailsStep extends StatelessWidget {
  const _DetailsStep({
    required this.nameCtrl,
    required this.colorCtrl,
    required this.customTagsCtrl,
    required this.csmModule,
    required this.onCsmChanged,
    required this.onChanged,
  });
  final TextEditingController nameCtrl;
  final TextEditingController colorCtrl;
  final TextEditingController customTagsCtrl;
  final String? csmModule;
  final ValueChanged<String?> onCsmChanged;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsetsDirectional.all(16),
      children: [
        TextField(
          controller: nameCtrl,
          autofocus: true,
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(
            labelText: 'שם הקטגוריה (חובה)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: colorCtrl,
          decoration: const InputDecoration(
            labelText: 'צבע (Hex אופציונלי, e.g. #6366F1)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          value: csmModule,
          decoration: const InputDecoration(
            labelText: 'מודול CSM (אופציונלי)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: null, child: Text('— ללא —')),
            DropdownMenuItem(value: 'cleaning', child: Text('cleaning')),
            DropdownMenuItem(value: 'massage', child: Text('massage')),
            DropdownMenuItem(value: 'delivery', child: Text('delivery')),
            DropdownMenuItem(value: 'handyman', child: Text('handyman')),
            DropdownMenuItem(value: 'pest_control', child: Text('pest_control')),
            DropdownMenuItem(
                value: 'fitness_trainer', child: Text('fitness_trainer')),
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
      ],
    );
  }
}

class _ImageStep extends StatefulWidget {
  const _ImageStep({required this.iconCtrl, required this.imageCtrl});
  final TextEditingController iconCtrl;
  final TextEditingController imageCtrl;

  @override
  State<_ImageStep> createState() => _ImageStepState();
}

class _ImageStepState extends State<_ImageStep> {
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
        const Text(
          'שלב אופציונלי — אפשר להשאיר ריק וליצור קטגוריה ללא תמונה.',
          style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.iconCtrl,
          decoration: const InputDecoration(
            labelText: 'iconUrl',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        _Preview(url: widget.iconCtrl.text),
        const SizedBox(height: 12),
        TextField(
          controller: widget.imageCtrl,
          decoration: const InputDecoration(
            labelText: 'imageUrl',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        _Preview(url: widget.imageCtrl.text),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: url.trim().isEmpty
          ? const Icon(Icons.image_not_supported_outlined,
              color: Color(0xFF9CA3AF))
          : ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    color: Color(0xFFEF4444)),
              ),
            ),
    );
  }
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.name,
    required this.color,
    required this.iconUrl,
    required this.imageUrl,
    required this.csmModule,
    required this.customTags,
    required this.error,
  });

  final String name;
  final String color;
  final String iconUrl;
  final String imageUrl;
  final String? csmModule;
  final String customTags;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsetsDirectional.all(16),
      children: [
        const Text(
          'בדוק את הפרטים לפני יצירה. ניתן לחזור ולערוך.',
          style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 12),
        _Row(label: 'שם', value: name),
        if (color.isNotEmpty) _Row(label: 'צבע', value: color),
        if (csmModule != null) _Row(label: 'CSM', value: csmModule!),
        if (customTags.trim().isNotEmpty)
          _Row(label: 'תגיות', value: customTags),
        if (iconUrl.isNotEmpty) _Row(label: 'iconUrl', value: iconUrl),
        if (imageUrl.isNotEmpty) _Row(label: 'imageUrl', value: imageUrl),
        if (error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFEF4444)),
            ),
            child: Text(
              error!,
              style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF9CA3AF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF1A1A2E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
