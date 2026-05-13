/// AnySkill — Publish Task Screen (AnyTasks v14.2.0 — 4-step Wizard)
///
/// Client publishes a new task through a 4-step wizard:
///   1. קטגוריה     — grid of 10 categories (3 per row)
///   2. פרטים       — title + description + optional image
///   3. תשלום       — quick amount buttons + manual, urgency, proof, location
///   4. סיכום       — review all + escrow notice + publish
///
/// Smart Pricing hooks (placeholder for Phase 2): `kCategoryPriceRange`
/// surfaces a recommended min/max per category that Step 3 consumes.
library;

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../utils/error_mapper.dart';
import '../../../widgets/address_input.dart';
import '../../../widgets/primary_cta.dart';
import '../models/any_task.dart';
import '../services/any_task_service.dart';
import '../theme/any_tasks_palette.dart';
import 'live_offers_screen.dart';

/// Smart Pricing v1 — hardcoded ranges per category. Phase 2 will swap
/// to dynamic calc from platform history.
const Map<String, (int, int)> kCategoryPriceRange = {
  'delivery':     (30, 120),
  'cleaning':     (80, 250),
  'handyman':     (100, 400),
  'moving':       (200, 800),
  'pet_care':     (50, 200),
  'tech_support': (80, 300),
  'tutoring':     (60, 200),
  'other':        (50, 300),
};

class PublishTaskScreen extends StatefulWidget {
  final String? presetCategory;

  /// When non-null, the screen opens in EDIT mode and pre-fills every
  /// field from this task. On submit it calls `AnyTaskService.updateTask`
  /// instead of `publishTask` and pops back to the caller. Only allowed
  /// while `existingTask.status == 'open'` (enforced by rules + service).
  final AnyTask? existingTask;

  const PublishTaskScreen({
    super.key,
    this.presetCategory,
    this.existingTask,
  });

  @override
  State<PublishTaskScreen> createState() => _PublishTaskScreenState();
}

class _PublishTaskScreenState extends State<PublishTaskScreen> {
  int _step = 0;

  // ── Step 1 ──
  String _category = 'other';

  // ── Step 2 ──
  final _title = TextEditingController();
  final _desc = TextEditingController();
  File? _pickedFile;
  Uint8List? _pickedBytes;
  String? _pickedMime;

  // ── Step 3 ──
  final _budget = TextEditingController();
  String _urgency = 'flexible';
  String _proofType = 'photo';
  final _locationFrom = TextEditingController();
  final _locationTo = TextEditingController();
  bool _isRemote = false;

  /// Product deadline — "I need this finished by …". When past, the CF
  /// `expireOpenTasks` flips the task to `expired`. Optional; default 7
  /// days from publish when the user doesn't pick one explicitly.
  DateTime? _deadline;

  bool _submitting = false;

  /// True when the screen was launched with `existingTask` — pops
  /// mode-specific behaviour across submit, labels, locked fields.
  bool get _isEdit => widget.existingTask != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final t = widget.existingTask!;
      _category = t.category;
      _title.text = t.title;
      _desc.text = t.description;
      _budget.text = t.budgetNis.toString();
      _urgency = t.urgency;
      _proofType = t.proofType;
      _locationFrom.text = t.locationFrom ?? '';
      _locationTo.text = t.locationTo ?? '';
      _isRemote = t.isRemote;
      _deadline = t.deadline;
      _step = 1; // category is locked — skip to details
    } else if (widget.presetCategory != null &&
        kTaskCategories.contains(widget.presetCategory)) {
      _category = widget.presetCategory!;
      _step = 1; // skip straight to details
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _budget.dispose();
    _locationFrom.dispose();
    _locationTo.dispose();
    super.dispose();
  }

  // ── Image pick ──────────────────────────────────────────────────

  Future<void> _pickImage() async {
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1024,
      );
      if (x == null) return;
      if (kIsWeb) {
        final bytes = await x.readAsBytes();
        setState(() {
          _pickedBytes = bytes;
          _pickedFile = null;
          _pickedMime = x.mimeType ?? 'image/jpeg';
        });
      } else {
        setState(() {
          _pickedFile = File(x.path);
          _pickedBytes = null;
          _pickedMime = x.mimeType ?? 'image/jpeg';
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('שגיאה בבחירת תמונה: $e'),
          backgroundColor: TasksPalette.dangerRed));
    }
  }

  Future<String?> _uploadImageIfAny(String taskId) async {
    if (_pickedFile == null && _pickedBytes == null) return null;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ref = FirebaseStorage.instance
        .ref('any_tasks/$taskId/task_image_$ts.jpg');
    final metadata =
        SettableMetadata(contentType: _pickedMime ?? 'image/jpeg');
    if (kIsWeb && _pickedBytes != null) {
      await ref.putData(_pickedBytes!, metadata);
    } else if (_pickedFile != null) {
      await ref.putFile(_pickedFile!, metadata);
    }
    return ref.getDownloadURL();
  }

  // ── Navigation between steps ────────────────────────────────────

  bool _canContinue() {
    switch (_step) {
      case 0:
        return true; // a category is always selected
      case 1:
        return _title.text.trim().length >= 5 &&
            _desc.text.trim().length >= 10;
      case 2:
        final b = int.tryParse(_budget.text.trim());
        return b != null && b >= 10;
      default:
        return true;
    }
  }

  void _next() {
    if (!_canContinue()) return;
    if (_step < 3) {
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      Navigator.maybePop(context);
    }
  }

  // ── Submit ──────────────────────────────────────────────────────

  Future<void> _submit() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _submitting = true);
    try {
      final from = _locationFrom.text.trim();
      final to = _locationTo.text.trim();

      // Default the product deadline to 7 days if the user didn't pick
      // one — matches the typical service SLA and gives the safety-net
      // CF something concrete to act on.
      final effectiveDeadline = _deadline ??
          DateTime.now().add(const Duration(days: 7));

      if (_isEdit) {
        // ── EDIT MODE ── allowlist: title, desc, deadline, location,
        // imageUrl. Budget/urgency/proofType are NOT changeable post-
        // publish (providers already saw them).
        final updates = <String, dynamic>{
          'title': _title.text.trim(),
          'description': _desc.text.trim(),
          'deadline': Timestamp.fromDate(effectiveDeadline),
          'isRemote': _isRemote,
          'locationFrom':
              _isRemote || from.isEmpty ? null : from,
          'locationTo': _isRemote || to.isEmpty ? null : to,
        };
        // 'isRemote' isn't in the client allowlist — drop it from the
        // update payload and rely on locationFrom/To null to signal it.
        updates.remove('isRemote');

        await AnyTaskService.instance
            .updateTask(widget.existingTask!.id!, updates);

        // Image upload (optional). Wrap in its own try so a failure
        // here doesn't roll back the text updates.
        try {
          final url = await _uploadImageIfAny(widget.existingTask!.id!);
          if (url != null) {
            await FirebaseFirestore.instance
                .collection('any_tasks')
                .doc(widget.existingTask!.id!)
                .update({'imageUrl': url});
          }
        } catch (e) {
          debugPrint('[PublishTask] image upload failed: $e');
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ השינויים נשמרו'),
          backgroundColor: TasksPalette.success,
        ));
        Navigator.of(context).pop(true);
        return;
      }

      // ── PUBLISH MODE ──
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final name = (userSnap.data()?['name'] ?? 'לקוח') as String;

      final task = AnyTask(
        clientId: uid,
        clientName: name,
        title: _title.text.trim(),
        description: _desc.text.trim(),
        category: _category,
        budgetNis: int.parse(_budget.text.trim()),
        urgency: _urgency,
        deadline: effectiveDeadline,
        locationFrom: _isRemote || from.isEmpty ? null : from,
        locationTo: _isRemote || to.isEmpty ? null : to,
        isRemote: _isRemote,
        proofType: _proofType,
      );

      final id = await AnyTaskService.instance.publishTask(task);

      try {
        final url = await _uploadImageIfAny(id);
        if (url != null) {
          await FirebaseFirestore.instance
              .collection('any_tasks')
              .doc(id)
              .update({'imageUrl': url});
        }
      } catch (e) {
        debugPrint('[PublishTask] image upload failed: $e');
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => LiveOffersScreen(taskId: id)),
      );
    } catch (e) {
      if (!mounted) return;
      // Domain codes from updateTask tx: task-not-editable / task-not-found.
      final err = e.toString();
      if (err.contains('task-not-editable')) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('המשימה כבר לא ניתנת לעריכה — נבחר נותן שירות'),
          backgroundColor: TasksPalette.danger,
        ));
      } else if (err.contains('task-not-found')) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('המשימה לא נמצאה — ייתכן שנמחקה'),
          backgroundColor: TasksPalette.danger,
        ));
      } else {
        ErrorMapper.show(context, e);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TasksPalette.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            _WizardHeader(step: _step, isEdit: _isEdit, onBack: _back),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Padding(
                  key: ValueKey(_step),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: _stepBody(),
                ),
              ),
            ),
            _BottomBar(
              step: _step,
              canContinue: _canContinue(),
              submitting: _submitting,
              isEdit: _isEdit,
              onNext: _next,
              onBack: _back,
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return _CategoryStep(
          selected: _category,
          onSelect: (c) => setState(() => _category = c),
        );
      case 1:
        return _DetailsStep(
          title: _title,
          desc: _desc,
          pickedFile: _pickedFile,
          pickedBytes: _pickedBytes,
          onPick: _pickImage,
          onRemove: () => setState(() {
            _pickedFile = null;
            _pickedBytes = null;
            _pickedMime = null;
          }),
          refresh: () => setState(() {}),
        );
      case 2:
        return _PaymentStep(
          category: _category,
          budget: _budget,
          urgency: _urgency,
          onUrgency: (u) => setState(() => _urgency = u),
          proofType: _proofType,
          onProof: (p) => setState(() => _proofType = p),
          locationFrom: _locationFrom,
          locationTo: _locationTo,
          isRemote: _isRemote,
          onRemoteChange: (v) => setState(() => _isRemote = v),
          deadline: _deadline,
          onDeadline: (d) => setState(() => _deadline = d),
          isEdit: _isEdit,
          refresh: () => setState(() {}),
        );
      case 3:
        return _SummaryStep(state: this);
      default:
        return const SizedBox.shrink();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// WIZARD HEADER — back + title + progress bar
// ═══════════════════════════════════════════════════════════════════

class _WizardHeader extends StatelessWidget {
  final int step;
  final bool isEdit;
  final VoidCallback onBack;
  const _WizardHeader({
    required this.step,
    required this.isEdit,
    required this.onBack,
  });

  static const _titles = [
    'בחר קטגוריה',
    'פרטי המשימה',
    'תשלום ולוגיסטיקה',
    'סיכום ופרסום',
  ];

  static const _editTitles = [
    '—',
    'עריכת פרטים',
    'עריכת תשלום ולוגיסטיקה',
    'סיכום שינויים',
  ];

  @override
  Widget build(BuildContext context) {
    final progress = (step + 1) / 4;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
      decoration: const BoxDecoration(
        color: TasksPalette.cardWhite,
        border: Border(
            bottom: BorderSide(color: TasksPalette.borderLight, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_forward_rounded,
                    color: TasksPalette.darkNavy, size: 22),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(isEdit ? _editTitles[step] : _titles[step],
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: TasksPalette.darkNavy)),
              ),
              if (!isEdit)
                Text('${step + 1}/4',
                    style: const TextStyle(
                        fontSize: 12, color: TasksPalette.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor:
                  const AlwaysStoppedAnimation(TasksPalette.primaryGreen),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// STEP 1 — CATEGORY GRID
// ═══════════════════════════════════════════════════════════════════

class _CategoryStep extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _CategoryStep({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final items = kTaskCategories;
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.0,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final c = items[i];
        final sel = c == selected;
        return InkWell(
          onTap: () => onSelect(c),
          borderRadius: BorderRadius.circular(TasksPalette.rCard),
          child: Container(
            decoration: BoxDecoration(
              color: sel
                  ? TasksPalette.primaryGreen.withValues(alpha: 0.08)
                  : TasksPalette.cardWhite,
              borderRadius: BorderRadius.circular(TasksPalette.rCard),
              border: Border.all(
                color: sel
                    ? TasksPalette.primaryGreen
                    : TasksPalette.borderLight,
                width: sel ? 2 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_iconFor(c),
                    color: sel
                        ? TasksPalette.primaryGreenDark
                        : TasksPalette.darkNavy,
                    size: 30),
                const SizedBox(height: 8),
                Text(kTaskCategoryLabels[c] ?? c,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: sel
                            ? TasksPalette.primaryGreenDark
                            : TasksPalette.darkNavy)),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _iconFor(String c) {
    switch (c) {
      case 'delivery':     return Icons.local_shipping_rounded;
      case 'cleaning':     return Icons.cleaning_services_rounded;
      case 'handyman':     return Icons.build_rounded;
      case 'moving':       return Icons.fire_truck_rounded;
      case 'pet_care':     return Icons.pets_rounded;
      case 'tech_support': return Icons.computer_rounded;
      case 'tutoring':     return Icons.school_rounded;
      default:             return Icons.more_horiz_rounded;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// STEP 2 — DETAILS (title + description + image)
// ═══════════════════════════════════════════════════════════════════

class _DetailsStep extends StatelessWidget {
  final TextEditingController title;
  final TextEditingController desc;
  final File? pickedFile;
  final Uint8List? pickedBytes;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final VoidCallback refresh;
  const _DetailsStep({
    required this.title,
    required this.desc,
    required this.pickedFile,
    required this.pickedBytes,
    required this.onPick,
    required this.onRemove,
    required this.refresh,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _label('כותרת קצרה'),
        TextField(
          controller: title,
          maxLength: 100,
          onChanged: (_) => refresh(),
          decoration: _input('"משלוח חבילה לרחוב הרצל"'),
        ),
        const SizedBox(height: 6),
        _label('תיאור מפורט'),
        TextField(
          controller: desc,
          maxLength: 2000,
          maxLines: 6,
          onChanged: (_) => refresh(),
          decoration: _input('ככל שתפרט יותר — תקבל הצעות טובות יותר'),
        ),
        const SizedBox(height: 6),
        _label('הוסף תמונה (רשות)'),
        _ImagePicker(
            file: pickedFile,
            bytes: pickedBytes,
            onPick: onPick,
            onRemove: onRemove),
      ],
    );
  }
}

Widget _label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(text,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: TasksPalette.textSecondary)),
    );

InputDecoration _input(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
          fontSize: 13, color: TasksPalette.textMuted),
      filled: true,
      fillColor: TasksPalette.cardWhite,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TasksPalette.rInput),
          borderSide:
              const BorderSide(color: TasksPalette.borderLight, width: 1)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TasksPalette.rInput),
          borderSide:
              const BorderSide(color: TasksPalette.borderLight, width: 1)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TasksPalette.rInput),
          borderSide: const BorderSide(
              color: TasksPalette.primaryGreen, width: 1.5)),
    );

class _ImagePicker extends StatelessWidget {
  final File? file;
  final Uint8List? bytes;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  const _ImagePicker({
    required this.file,
    required this.bytes,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = file != null || bytes != null;
    if (hasImage) {
      final preview = bytes != null
          ? Image.memory(bytes!, fit: BoxFit.cover)
          : Image.file(file!, fit: BoxFit.cover);
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(TasksPalette.rInput),
            child: SizedBox(
                height: 160, width: double.infinity, child: preview),
          ),
          PositionedDirectional(
            top: 6,
            end: 6,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.close_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(TasksPalette.rInput),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: TasksPalette.cardWhite,
          borderRadius: BorderRadius.circular(TasksPalette.rInput),
          border: Border.all(
              color: TasksPalette.borderLight,
              width: 1.5,
              style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.add_photo_alternate_outlined,
                color: TasksPalette.textSecondary, size: 30),
            SizedBox(height: 6),
            Text('לחץ להעלאת תמונה',
                style: TextStyle(
                    fontSize: 13, color: TasksPalette.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// STEP 3 — PAYMENT + LOGISTICS (Smart Pricing preview)
// ═══════════════════════════════════════════════════════════════════

class _PaymentStep extends StatelessWidget {
  final String category;
  final TextEditingController budget;
  final String urgency;
  final ValueChanged<String> onUrgency;
  final String proofType;
  final ValueChanged<String> onProof;
  final TextEditingController locationFrom;
  final TextEditingController locationTo;
  final bool isRemote;
  final ValueChanged<bool> onRemoteChange;
  final DateTime? deadline;
  final ValueChanged<DateTime?> onDeadline;
  final bool isEdit;
  final VoidCallback refresh;

  const _PaymentStep({
    required this.category,
    required this.budget,
    required this.urgency,
    required this.onUrgency,
    required this.proofType,
    required this.onProof,
    required this.locationFrom,
    required this.locationTo,
    required this.isRemote,
    required this.onRemoteChange,
    required this.deadline,
    required this.onDeadline,
    required this.isEdit,
    required this.refresh,
  });

  static const _quickAmounts = [50, 80, 100, 150, 200, 300, 500];

  @override
  Widget build(BuildContext context) {
    final range = kCategoryPriceRange[category] ?? (50, 300);
    final value = int.tryParse(budget.text.trim()) ?? 0;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _label('תשלום על המשימה'),
        _SmartPriceBanner(category: category, value: value, range: range),
        const SizedBox(height: 10),
        TextField(
          controller: budget,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => refresh(),
          decoration: _input('₪ ${range.$1}–${range.$2}').copyWith(
            prefixIcon: const Icon(Icons.payments_outlined,
                color: TasksPalette.amber),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _quickAmounts.map((n) {
            final sel = value == n;
            return InkWell(
              onTap: () {
                budget.text = n.toString();
                refresh();
              },
              borderRadius: BorderRadius.circular(TasksPalette.rChip),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: sel
                      ? TasksPalette.primaryGreen
                      : TasksPalette.cardWhite,
                  borderRadius:
                      BorderRadius.circular(TasksPalette.rChip),
                  border: Border.all(
                      color: sel
                          ? TasksPalette.primaryGreen
                          : TasksPalette.borderLight),
                ),
                child: Text('₪$n',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: sel
                            ? Colors.white
                            : TasksPalette.darkNavy)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        _label('דחיפות'),
        Row(
          children: [
            _urgencyChip('🕐', 'גמיש', 'flexible'),
            const SizedBox(width: 8),
            _urgencyChip('⚡', 'היום', 'today'),
            const SizedBox(width: 8),
            _urgencyChip('🔥', 'דחוף', 'urgent_now'),
          ],
        ),
        const SizedBox(height: 16),
        _label('עד מתי צריך את המשימה?'),
        _DeadlinePicker(
          deadline: deadline,
          onChanged: onDeadline,
        ),
        const SizedBox(height: 16),
        _label('מיקום'),
        if (!isRemote) ...[
          // Address from — bridges the legacy single-string `locationFrom`
          // field to the new two-field AddressInput. Parse on init, recombine
          // back into the controller on every change so the submit path at
          // line 215 still reads from `locationFrom.text`.
          Builder(builder: (_) {
            final initial = AddressValue.fromCombined(locationFrom.text);
            return AddressInput(
              key: const ValueKey('anytasks-location-from'),
              initialCity: initial.city,
              initialStreet: initial.street,
              accentColor: TasksPalette.primaryGreen,
              cityLabel: 'עיר (מאיפה)',
              streetLabel: 'רחוב ומספר (איסוף)',
              streetHint: 'לדוגמה: הרצל 10',
              onChanged: (v) {
                locationFrom.text = v.combined;
                refresh();
              },
            );
          }),
          const SizedBox(height: 12),
          Builder(builder: (_) {
            final initial = AddressValue.fromCombined(locationTo.text);
            return AddressInput(
              key: const ValueKey('anytasks-location-to'),
              initialCity: initial.city,
              initialStreet: initial.street,
              accentColor: TasksPalette.coral,
              cityLabel: 'עיר (לאיפה)',
              streetLabel: 'רחוב ומספר (יעד)',
              streetHint: 'לדוגמה: דיזנגוף 50',
              onChanged: (v) {
                locationTo.text = v.combined;
                refresh();
              },
            );
          }),
          const SizedBox(height: 8),
        ],
        CheckboxListTile(
          value: isRemote,
          onChanged: (v) => onRemoteChange(v ?? false),
          title: const Text('משימה מרחוק (ללא מיקום פיזי)',
              style: TextStyle(fontSize: 13)),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          activeColor: TasksPalette.primaryGreen,
        ),
        const SizedBox(height: 8),
        _label('סוג הוכחה נדרש'),
        Row(
          children: [
            _proofChip('📷', 'תמונה', 'photo'),
            const SizedBox(width: 8),
            _proofChip('📝', 'טקסט', 'text'),
            const SizedBox(width: 8),
            _proofChip('📋', 'שניהם', 'both'),
          ],
        ),
      ],
    );
  }

  Widget _urgencyChip(String emoji, String label, String value) {
    final sel = urgency == value;
    return Expanded(
      child: InkWell(
        onTap: () => onUrgency(value),
        borderRadius: BorderRadius.circular(TasksPalette.rInput),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: sel
                ? TasksPalette.primaryGreen.withValues(alpha: 0.08)
                : TasksPalette.cardWhite,
            borderRadius: BorderRadius.circular(TasksPalette.rInput),
            border: Border.all(
                color: sel
                    ? TasksPalette.primaryGreen
                    : TasksPalette.borderLight,
                width: sel ? 1.5 : 1),
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: sel
                          ? TasksPalette.primaryGreenDark
                          : TasksPalette.darkNavy)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _proofChip(String emoji, String label, String value) {
    final sel = proofType == value;
    return Expanded(
      child: InkWell(
        onTap: () => onProof(value),
        borderRadius: BorderRadius.circular(TasksPalette.rInput),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel
                ? TasksPalette.escrowBlueLight
                : TasksPalette.cardWhite,
            borderRadius: BorderRadius.circular(TasksPalette.rInput),
            border: Border.all(
                color: sel
                    ? TasksPalette.escrowBlue
                    : TasksPalette.borderLight,
                width: sel ? 1.5 : 1),
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: sel
                          ? TasksPalette.escrowBlue
                          : TasksPalette.darkNavy)),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// DEADLINE PICKER — quick chips + custom date sheet
// ═══════════════════════════════════════════════════════════════════

class _DeadlinePicker extends StatelessWidget {
  final DateTime? deadline;
  final ValueChanged<DateTime?> onChanged;

  const _DeadlinePicker({required this.deadline, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // End-of-day for a given offset (=23:59:59 local on day N).
    DateTime eod(int daysFromNow) {
      final now = DateTime.now();
      final d = DateTime(now.year, now.month, now.day)
          .add(Duration(days: daysFromNow));
      return DateTime(d.year, d.month, d.day, 23, 59, 59);
    }

    final chips = <({String label, DateTime when})>[
      (label: 'היום', when: eod(0)),
      (label: 'מחר', when: eod(1)),
      (label: 'השבוע', when: eod(7)),
      (label: 'החודש', when: eod(30)),
    ];

    bool isSame(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    String fmt(DateTime d) {
      final day = d.day.toString().padLeft(2, '0');
      final m = d.month.toString().padLeft(2, '0');
      return '$day/$m/${d.year}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in chips)
              _DeadlineChip(
                label: c.label,
                selected: deadline != null && isSame(deadline!, c.when),
                onTap: () => onChanged(c.when),
              ),
            _DeadlineChip(
              label: deadline != null &&
                      !chips.any((c) => isSame(c.when, deadline!))
                  ? 'תאריך: ${fmt(deadline!)}'
                  : 'תאריך אחר…',
              selected: deadline != null &&
                  !chips.any((c) => isSame(c.when, deadline!)),
              icon: Icons.event_rounded,
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: deadline ??
                      now.add(const Duration(days: 7)),
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 90)),
                  locale: const Locale('he'),
                  helpText: 'בחר/י תאריך יעד',
                  cancelText: 'ביטול',
                  confirmText: 'אישור',
                );
                if (picked != null) {
                  onChanged(DateTime(
                      picked.year, picked.month, picked.day, 23, 59, 59));
                }
              },
            ),
          ],
        ),
        if (deadline != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: TasksPalette.bgPrimary,
              borderRadius:
                  BorderRadius.circular(TasksPalette.rButton),
              border: Border.all(color: TasksPalette.borderLight),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 14, color: TasksPalette.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'אם לא ייתפס עד ${fmt(deadline!)} — המשימה תפוג אוטומטית.',
                    style: const TextStyle(
                        fontSize: 11,
                        color: TasksPalette.textSecondary),
                  ),
                ),
                TextButton(
                  onPressed: () => onChanged(null),
                  style: TextButton.styleFrom(
                    foregroundColor: TasksPalette.danger,
                    minimumSize: const Size(0, 24),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  child: const Text('נקה',
                      style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 6),
          const Text(
            'ללא דד-ליין מפורש תוגדר תפוגה אוטומטית של 7 ימים.',
            style: TextStyle(
                fontSize: 11, color: TasksPalette.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _DeadlineChip extends StatelessWidget {
  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;
  const _DeadlineChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(TasksPalette.rChip),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? TasksPalette.primaryGreen
              : TasksPalette.cardWhite,
          borderRadius: BorderRadius.circular(TasksPalette.rChip),
          border: Border.all(
              color: selected
                  ? TasksPalette.primaryGreen
                  : TasksPalette.borderLight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 14,
                  color:
                      selected ? Colors.white : TasksPalette.darkNavy),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color:
                        selected ? Colors.white : TasksPalette.darkNavy)),
          ],
        ),
      ),
    );
  }
}

/// Smart Pricing banner — shows category range, progress indicator where
/// the user's value sits, and color-coded tip (low/ok/high).
class _SmartPriceBanner extends StatelessWidget {
  final String category;
  final int value;
  final (int, int) range;
  const _SmartPriceBanner({
    required this.category,
    required this.value,
    required this.range,
  });

  @override
  Widget build(BuildContext context) {
    final (min, max) = range;
    final clamped = value.clamp(min - (max - min) ~/ 2, max + (max - min));
    final ratio = ((clamped - min) / (max - min)).clamp(0.0, 1.0);

    // Color + tip
    late final Color fill;
    late final String tip;
    if (value == 0) {
      fill = TasksPalette.escrowBlue;
      tip = '💡 הזן סכום כדי לראות ניתוח';
    } else if (value < min) {
      fill = TasksPalette.amber;
      tip = '⚠️ מחיר נמוך — ייתכן שתקבל פחות הצעות';
    } else if (value > max) {
      fill = TasksPalette.dangerRed;
      tip = '🔝 מחיר גבוה — תקבל את נותני השירות הטובים ביותר';
    } else {
      fill = TasksPalette.primaryGreen;
      tip = '✅ מחיר מצוין — צפי להצעות רבות';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TasksPalette.escrowBlueLight,
        borderRadius: BorderRadius.circular(TasksPalette.rInput),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '💡 משימות דומות ב${kTaskCategoryLabels[category] ?? category} עלו בין ₪$min ל-₪$max',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: TasksPalette.escrowBlue),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: Colors.white,
              valueColor: AlwaysStoppedAnimation(fill),
            ),
          ),
          const SizedBox(height: 6),
          Text(tip,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: fill)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// STEP 4 — SUMMARY
// ═══════════════════════════════════════════════════════════════════

class _SummaryStep extends StatelessWidget {
  final _PublishTaskScreenState state;
  const _SummaryStep({required this.state});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _summaryCard([
          _row('קטגוריה',
              kTaskCategoryLabels[state._category] ?? state._category),
          _row('כותרת', state._title.text.trim()),
          _row('תיאור', state._desc.text.trim(), maxLines: 4),
        ]),
        const SizedBox(height: 10),
        _summaryCard([
          _row('תשלום', '₪${state._budget.text.trim()}'),
          _row('דחיפות',
              kTaskUrgencyLabels[state._urgency] ?? state._urgency),
          _row('הוכחה',
              kTaskProofLabels[state._proofType] ?? state._proofType),
          if (state._isRemote)
            _row('מיקום', 'משימה מרחוק')
          else ...[
            if (state._locationFrom.text.trim().isNotEmpty)
              _row('מאיפה', state._locationFrom.text.trim()),
            if (state._locationTo.text.trim().isNotEmpty)
              _row('לאיפה', state._locationTo.text.trim()),
          ],
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: TasksPalette.escrowBlueLight,
            borderRadius: BorderRadius.circular(TasksPalette.rInput),
          ),
          child: Row(
            children: const [
              Icon(Icons.shield_outlined,
                  color: TasksPalette.escrowBlue, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                    'התשלום יאובטח ב-Escrow ויחויב רק אחרי בחירת נותן שירות',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: TasksPalette.escrowBlue)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryCard(List<Widget> rows) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TasksPalette.cardWhite,
        borderRadius: BorderRadius.circular(TasksPalette.rCard),
        boxShadow: TasksPalette.cardShadow,
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              const Divider(
                  height: 16,
                  thickness: 0.5,
                  color: TasksPalette.borderLight),
          ],
        ],
      ),
    );
  }

  Widget _row(String k, String v, {int maxLines = 2}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 78,
          child: Text(k,
              style: const TextStyle(
                  fontSize: 12,
                  color: TasksPalette.textSecondary)),
        ),
        Expanded(
          child: Text(v,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: TasksPalette.darkNavy)),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// BOTTOM BAR — back + next / publish
// ═══════════════════════════════════════════════════════════════════

class _BottomBar extends StatelessWidget {
  final int step;
  final bool canContinue;
  final bool submitting;
  final bool isEdit;
  final VoidCallback onNext;
  final VoidCallback onBack;
  const _BottomBar({
    required this.step,
    required this.canContinue,
    required this.submitting,
    required this.isEdit,
    required this.onNext,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        color: TasksPalette.cardWhite,
        border: Border(
            top: BorderSide(color: TasksPalette.borderLight, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (step > 0)
              SizedBox(
                height: 50,
                child: OutlinedButton(
                  onPressed: submitting ? null : onBack,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: TasksPalette.darkNavy,
                    side: const BorderSide(
                        color: TasksPalette.borderLight),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 22),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(TasksPalette.rButton)),
                  ),
                  child: const Text('חזור',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                ),
              ),
            if (step > 0) const SizedBox(width: 8),
            Expanded(
              child: PrimaryCTA(
                label: step == 3
                    ? (isEdit ? 'שמור שינויים' : 'פרסם משימה')
                    : 'המשך',
                variant: PrimaryCTAVariant.success,
                loading: submitting,
                height: 50,
                onPressed: !canContinue ? null : onNext,
                semanticHint: step == 3
                    ? 'מפרסם את המשימה ופותח את משפך ההצעות'
                    : 'ממשיך לשלב הבא בפרסום',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
