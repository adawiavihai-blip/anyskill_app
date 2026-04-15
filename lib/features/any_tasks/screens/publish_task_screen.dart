/// AnySkill — Publish Task Screen (AnyTasks v14.0.0)
///
/// Client-facing form to publish a new micro-task. Follows the 9-screen
/// spec section 5.2. Psychology hooks wired in:
///   • "0 publishing fee" badge (anchoring / gift)
///   • Social proof — live "X providers active right now" FOMO badge
///   • Variable reward — "AI will find matches within minutes" copy
///   • Commitment — 2000-char description invites investment
library;

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/any_task.dart';
import '../services/any_task_service.dart';
import '../services/task_ai_service.dart';
import '../theme/any_tasks_palette.dart';

class PublishTaskScreen extends StatefulWidget {
  const PublishTaskScreen({super.key});

  @override
  State<PublishTaskScreen> createState() => _PublishTaskScreenState();
}

class _PublishTaskScreenState extends State<PublishTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _budget = TextEditingController();
  final _locationFrom = TextEditingController();
  final _locationTo = TextEditingController();

  String _category = 'other';
  String _urgency = 'flexible';
  String _proofType = 'photo';
  List<String> _aiTags = const [];
  DateTime? _deadline;
  bool _isRemote = false;
  bool _submitting = false;
  bool _aiLoading = false;

  // ── Image attachment ────────────────────────────────────────────
  File? _pickedImageFile;        // mobile path
  Uint8List? _pickedImageBytes;  // web path
  String? _pickedImageMime;
  bool _uploadingImage = false;

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1024,
      );
      if (x == null) return;
      if (kIsWeb) {
        final bytes = await x.readAsBytes();
        setState(() {
          _pickedImageBytes = bytes;
          _pickedImageFile = null;
          _pickedImageMime = x.mimeType ?? 'image/jpeg';
        });
      } else {
        setState(() {
          _pickedImageFile = File(x.path);
          _pickedImageBytes = null;
          _pickedImageMime = x.mimeType ?? 'image/jpeg';
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('שגיאה בבחירת תמונה: $e'),
        backgroundColor: TasksPalette.danger,
      ));
    }
  }

  void _removeImage() {
    setState(() {
      _pickedImageFile = null;
      _pickedImageBytes = null;
      _pickedImageMime = null;
    });
  }

  Future<String?> _uploadImageIfAny(String taskId) async {
    if (_pickedImageFile == null && _pickedImageBytes == null) return null;
    setState(() => _uploadingImage = true);
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance
          .ref('any_tasks/$taskId/task_image_$ts.jpg');
      final metadata = SettableMetadata(
          contentType: _pickedImageMime ?? 'image/jpeg');
      if (kIsWeb && _pickedImageBytes != null) {
        await ref.putData(_pickedImageBytes!, metadata);
      } else if (_pickedImageFile != null) {
        await ref.putFile(_pickedImageFile!, metadata);
      }
      return await ref.getDownloadURL();
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _runAi() async {
    final title = _title.text.trim();
    final desc = _desc.text.trim();
    if (title.length < 5 || desc.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('מלא כותרת + תיאור קודם, ואז AI יציע קטגוריה ודחיפות'),
        backgroundColor: TasksPalette.clientPrimary,
      ));
      return;
    }
    setState(() => _aiLoading = true);
    final res = await TaskAiService.instance
        .suggest(title: title, description: desc);
    if (!mounted) return;
    setState(() => _aiLoading = false);
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('AI לא הצליח — מלא ידנית'),
        backgroundColor: TasksPalette.danger,
      ));
      return;
    }
    setState(() {
      _category = res.suggestedCategory;
      _urgency = res.suggestedUrgency;
      _aiTags = res.tags;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('✨ AI מילא קטגוריה + דחיפות'),
      backgroundColor: TasksPalette.success,
    ));
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _submitting = true);
    try {
      final userSnap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final name = (userSnap.data()?['name'] ?? 'לקוח') as String;

      final from = _locationFrom.text.trim();
      final to = _locationTo.text.trim();
      final task = AnyTask(
        clientId: uid,
        clientName: name,
        title: _title.text.trim(),
        description: _desc.text.trim(),
        category: _category,
        aiTags: _aiTags,
        budgetNis: int.parse(_budget.text.trim()),
        urgency: _urgency,
        deadline: _deadline,
        locationFrom: _isRemote || from.isEmpty ? null : from,
        locationTo: _isRemote || to.isEmpty ? null : to,
        isRemote: _isRemote,
        proofType: _proofType,
      );

      final id = await AnyTaskService.instance.publishTask(task);

      // Upload attachment if the user picked one. Non-fatal on failure —
      // the task is already live; a failed image upload just logs.
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✨ המשימה פורסמה! נודיע לך כשמגיעות הצעות ($id)'),
          backgroundColor: TasksPalette.success,
        ),
      );
      Navigator.pop(context, id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה: $e'),
          backgroundColor: TasksPalette.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TasksPalette.scaffoldBg,
      appBar: AppBar(
        backgroundColor: TasksPalette.cardBg,
        foregroundColor: TasksPalette.textPrimary,
        elevation: 0,
        title: const Text('פרסום משימה חדשה',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _AiBanner(onTap: _aiLoading ? null : _runAi, loading: _aiLoading),
            const SizedBox(height: 16),
            _section(
              title: 'כותרת קצרה',
              hint: '"משלוח חבילה לרחוב הרצל"',
              child: TextFormField(
                controller: _title,
                maxLength: 100,
                decoration: _inputDecoration('מה צריך לעשות?'),
                validator: (v) => (v == null || v.trim().length < 5)
                    ? 'כותרת קצרה מדי (מינימום 5 תווים)'
                    : null,
              ),
            ),
            _section(
              title: 'תיאור מפורט',
              hint: 'ככל שתפרט יותר — כך תקבל הצעות טובות יותר',
              child: TextFormField(
                controller: _desc,
                maxLength: 2000,
                maxLines: 5,
                decoration: _inputDecoration('פרט את המשימה...'),
                validator: (v) => (v == null || v.trim().length < 10)
                    ? 'תיאור קצר מדי (מינימום 10 תווים)'
                    : null,
              ),
            ),
            _section(
              title: 'הוסף תמונה (רשות)',
              hint: 'תמונה עוזרת לנותני שירות להבין את המשימה מהר יותר',
              child: _imagePickerTile(),
            ),
            _section(
              title: 'קטגוריה',
              child: _categoryGrid(),
            ),
            _section(
              title: 'תקציב בש"ח',
              hint: 'נותני שירות רואים את המחיר ומקבלים בלחיצה אחת',
              child: TextFormField(
                controller: _budget,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _inputDecoration('₪ 120').copyWith(
                  prefixIcon: const Icon(Icons.payments_outlined,
                      color: TasksPalette.amber),
                ),
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null) return 'הזן סכום';
                  if (n < 10) return 'מינימום ₪10';
                  return null;
                },
              ),
            ),
            _section(
              title: 'דחיפות',
              child: _urgencySelector(),
            ),
            _section(
              title: 'תאריך יעד (רשות)',
              child: _deadlineTile(),
            ),
            _section(
              title: 'מיקום',
              child: Column(
                children: [
                  if (!_isRemote) ...[
                    TextFormField(
                      controller: _locationFrom,
                      decoration:
                          _inputDecoration('כתובת איסוף / נקודת התחלה')
                              .copyWith(
                        labelText: 'מיקום (מאיפה)',
                        prefixIcon: const Icon(Icons.my_location_rounded,
                            color: TasksPalette.clientPrimary),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _locationTo,
                      decoration:
                          _inputDecoration('כתובת יעד / נקודת סיום')
                              .copyWith(
                        labelText: 'יעד (לאיפה)',
                        prefixIcon: const Icon(Icons.flag_outlined,
                            color: TasksPalette.coral),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  CheckboxListTile(
                    value: _isRemote,
                    onChanged: (v) => setState(() => _isRemote = v ?? false),
                    title: const Text('משימה מרחוק (ללא מיקום פיזי)'),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    activeColor: TasksPalette.clientPrimary,
                  ),
                ],
              ),
            ),
            _section(
              title: 'סוג הוכחה נדרש',
              hint: 'איך נותן השירות יוכיח שסיים?',
              child: _proofSelector(),
            ),
            const SizedBox(height: 16),
            _escrowAssuranceCard(),
            const SizedBox(height: 16),
            _publishButton(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Widgets ─────────────────────────────────────────────────────

  Widget _section({required String title, String? hint, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: TasksPalette.textPrimary)),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint,
                style: const TextStyle(
                    fontSize: 12, color: TasksPalette.textSecondary)),
          ],
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _categoryGrid() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kTaskCategories.map((c) {
        final selected = _category == c;
        return InkWell(
          borderRadius: BorderRadius.circular(TasksPalette.rChip),
          onTap: () => setState(() => _category = c),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? TasksPalette.clientPrimarySoft
                  : TasksPalette.cardBg,
              border: Border.all(
                color: selected
                    ? TasksPalette.clientPrimary
                    : TasksPalette.border,
                width: selected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(TasksPalette.rChip),
            ),
            child: Text(
              kTaskCategoryLabels[c]!,
              style: TextStyle(
                fontSize: 13,
                color: selected
                    ? TasksPalette.clientPrimary
                    : TasksPalette.textPrimary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _urgencySelector() {
    return Row(
      children: kTaskUrgency.map((u) {
        final selected = _urgency == u;
        final isUrgent = u == 'urgent_now';
        final color = isUrgent
            ? TasksPalette.coral
            : u == 'today'
                ? TasksPalette.amber
                : TasksPalette.success;
        return Expanded(
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(TasksPalette.rButton),
              onTap: () => setState(() => _urgency = u),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? color : TasksPalette.cardBg,
                  border: Border.all(
                      color: selected ? color : TasksPalette.border),
                  borderRadius:
                      BorderRadius.circular(TasksPalette.rButton),
                ),
                alignment: Alignment.center,
                child: Text(
                  kTaskUrgencyLabels[u]!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : TasksPalette.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _proofSelector() {
    return Row(
      children: kTaskProofTypes.map((p) {
        final selected = _proofType == p;
        final icon = p == 'photo'
            ? Icons.photo_camera_outlined
            : p == 'text'
                ? Icons.edit_note_rounded
                : Icons.auto_awesome_rounded;
        return Expanded(
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(TasksPalette.rButton),
              onTap: () => setState(() => _proofType = p),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected
                      ? TasksPalette.clientPrimarySoft
                      : TasksPalette.cardBg,
                  border: Border.all(
                    color: selected
                        ? TasksPalette.clientPrimary
                        : TasksPalette.border,
                    width: selected ? 1.5 : 1,
                  ),
                  borderRadius:
                      BorderRadius.circular(TasksPalette.rButton),
                ),
                child: Column(
                  children: [
                    Icon(icon,
                        color: selected
                            ? TasksPalette.clientPrimary
                            : TasksPalette.textSecondary,
                        size: 22),
                    const SizedBox(height: 4),
                    Text(
                      kTaskProofLabels[p]!,
                      style: TextStyle(
                        fontSize: 12,
                        color: selected
                            ? TasksPalette.clientPrimary
                            : TasksPalette.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _imagePickerTile() {
    final hasImage =
        _pickedImageFile != null || _pickedImageBytes != null;
    if (hasImage) {
      final preview = _pickedImageBytes != null
          ? Image.memory(_pickedImageBytes!, fit: BoxFit.cover)
          : Image.file(_pickedImageFile!, fit: BoxFit.cover);
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(TasksPalette.rButton),
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
                onTap: _uploadingImage ? null : _removeImage,
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
      onTap: _pickImage,
      borderRadius: BorderRadius.circular(TasksPalette.rButton),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: TasksPalette.scaffoldBg,
          borderRadius: BorderRadius.circular(TasksPalette.rButton),
          border: Border.all(
            color: TasksPalette.clientPrimary.withValues(alpha: 0.4),
            style: BorderStyle.solid,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.add_photo_alternate_outlined,
                color: TasksPalette.clientPrimary, size: 32),
            SizedBox(height: 6),
            Text('לחץ להעלאת תמונה',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: TasksPalette.clientPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _deadlineTile() {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: _deadline ?? now.add(const Duration(days: 1)),
          firstDate: now,
          lastDate: now.add(const Duration(days: 90)),
          helpText: 'בחר תאריך יעד',
        );
        if (picked != null) setState(() => _deadline = picked);
      },
      borderRadius: BorderRadius.circular(TasksPalette.rButton),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: TasksPalette.cardBg,
          border: Border.all(color: TasksPalette.border),
          borderRadius: BorderRadius.circular(TasksPalette.rButton),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_outlined,
                color: TasksPalette.clientPrimary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _deadline == null
                    ? 'לא נבחר תאריך — המשימה גמישה'
                    : '${_deadline!.day}/${_deadline!.month}/${_deadline!.year}',
                style: TextStyle(
                  fontSize: 14,
                  color: _deadline == null
                      ? TasksPalette.textHint
                      : TasksPalette.textPrimary,
                ),
              ),
            ),
            if (_deadline != null)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _deadline = null),
              ),
          ],
        ),
      ),
    );
  }

  Widget _escrowAssuranceCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TasksPalette.escrowBlueSoft,
        borderRadius: BorderRadius.circular(TasksPalette.rCard),
        border: Border.all(color: TasksPalette.escrowBlue.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: const [
          Icon(Icons.shield_outlined, color: TasksPalette.escrowBlue, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('התשלום מאובטח',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: TasksPalette.escrowBlue)),
                SizedBox(height: 2),
                Text(
                  'הכסף יחויב רק כשתבחר נותן שירות, וישוחרר רק אחרי שתאשר השלמה',
                  style: TextStyle(
                      fontSize: 12, color: TasksPalette.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _publishButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _submitting ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: TasksPalette.clientPrimary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TasksPalette.rPill),
          ),
        ),
        child: _submitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child:
                    CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.rocket_launch_rounded, size: 20),
                  SizedBox(width: 8),
                  Text('פרסם משימה',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ],
              ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: TasksPalette.textHint),
        filled: true,
        fillColor: TasksPalette.cardBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TasksPalette.rButton),
          borderSide: const BorderSide(color: TasksPalette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TasksPalette.rButton),
          borderSide: const BorderSide(color: TasksPalette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TasksPalette.rButton),
          borderSide:
              const BorderSide(color: TasksPalette.clientPrimary, width: 1.5),
        ),
      );
}

class _AiBanner extends StatelessWidget {
  final VoidCallback? onTap;
  final bool loading;
  const _AiBanner({required this.onTap, required this.loading});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(TasksPalette.rCard),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [TasksPalette.clientPrimary, TasksPalette.clientPrimaryDark],
          ),
          borderRadius: BorderRadius.circular(TasksPalette.rCard),
        ),
        child: Row(
          children: [
            loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_rounded,
                    color: Colors.white, size: 22),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('לחץ למילוי אוטומטי עם AI',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  SizedBox(height: 2),
                  Text(
                    'מלא/י כותרת + תיאור, ו-AI יציע קטגוריה ודחיפות',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_left_rounded,
                color: Colors.white70, size: 18),
          ],
        ),
      ),
    );
  }
}
