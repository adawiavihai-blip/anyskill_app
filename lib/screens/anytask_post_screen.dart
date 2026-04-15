/// AnyTasks 3.0 — Post Task Screen
///
/// Full-screen form for customers to create a new micro-task.
/// Fields: title, description, category, amount, location, deadline,
/// proof type, urgency toggle.
library;

import 'package:flutter/material.dart';
import '../services/anytask_service.dart';
import '../services/anytask_category_service.dart';
import '../constants.dart';

class AnytaskPostScreen extends StatefulWidget {
  const AnytaskPostScreen({super.key});

  @override
  State<AnytaskPostScreen> createState() => _AnytaskPostScreenState();
}

class _AnytaskPostScreenState extends State<AnytaskPostScreen> {
  static const _kIndigo = Color(0xFF6366F1);
  static const _kDark   = Color(0xFF1A1A2E);
  static const _kMuted  = Color(0xFF6B7280);
  static const _kGreen  = Color(0xFF10B981);
  static const _kRed    = Color(0xFFEF4444);

  final _titleCtrl  = TextEditingController();
  final _descCtrl   = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  String? _selectedCategory;
  String _proofType = 'photo';
  bool _isUrgent = false;
  DateTime? _deadline;
  bool _submitting = false;

  List<Map<String, dynamic>> _categories = ANYTASK_CATEGORIES;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final cats = await AnytaskCategoryService.getAll();
    if (mounted) setState(() => _categories = cats);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _amountCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _titleCtrl.text.trim().length >= 3 &&
      _descCtrl.text.trim().length >= 10 &&
      _selectedCategory != null &&
      (_amountCtrl.text.isNotEmpty &&
          (double.tryParse(_amountCtrl.text) ?? 0) >= AnytaskService.minTaskAmount) &&
      !_submitting;

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() => _submitting = true);

    final result = await AnytaskService.createTask(
      title: _titleCtrl.text,
      description: _descCtrl.text,
      category: _selectedCategory!,
      amount: double.parse(_amountCtrl.text),
      locationText: _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
      deadline: _deadline,
      proofType: _proofType,
      isUrgent: _isUrgent,
    );

    if (!mounted) return;

    // If result is a doc ID (not an error), it succeeded
    final isError = result.contains(' ') || result.contains('שגיאה') || result.contains('אין');

    if (isError) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result), backgroundColor: _kRed),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('המשימה פורסמה בהצלחה! 🎉'),
          backgroundColor: _kGreen,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  Future<void> _pickDeadline() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: const TimeOfDay(hour: 18, minute: 0),
      );
      if (time != null && mounted) {
        setState(() {
          _deadline = DateTime(date.year, date.month, date.day, time.hour, time.minute);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        title: const Text('פרסם משימה חדשה'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: _kDark,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title ─────────────────────────────────────────────────
            _SectionLabel('כותרת המשימה *'),
            const SizedBox(height: 6),
            _buildTextField(
              controller: _titleCtrl,
              hint: 'לדוגמה: צלם תמונות של חנות חדשה',
              maxLength: 100,
            ),
            const SizedBox(height: 16),

            // ── Description ───────────────────────────────────────────
            _SectionLabel('תיאור מפורט *'),
            const SizedBox(height: 6),
            _buildTextField(
              controller: _descCtrl,
              hint: 'מה בדיוק צריך לעשות? הוסף כמה שיותר פרטים',
              maxLines: 4,
              maxLength: 2000,
            ),
            const SizedBox(height: 16),

            // ── Category ──────────────────────────────────────────────
            _SectionLabel('קטגוריה *'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.map((cat) {
                final catId = cat['id'] as String;
                final selected = _selectedCategory == catId;
                return ChoiceChip(
                  label: Text(cat['nameHe'] as String? ?? catId),
                  selected: selected,
                  onSelected: (v) => setState(() => _selectedCategory = v ? catId : null),
                  selectedColor: _kIndigo.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    color: selected ? _kIndigo : _kMuted,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                  avatar: Icon(
                    cat['icon'] as IconData? ?? Icons.task_alt_rounded,
                    size: 16,
                    color: selected ? _kIndigo : _kMuted,
                  ),
                  side: BorderSide(
                    color: selected ? _kIndigo : Colors.grey[300]!,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // ── Amount ────────────────────────────────────────────────
            _SectionLabel('תקציב (₪) *'),
            const SizedBox(height: 6),
            _buildTextField(
              controller: _amountCtrl,
              hint: 'מינימום ${AnytaskService.minTaskAmount.toStringAsFixed(0)}₪',
              keyboardType: TextInputType.number,
              prefixIcon: Icons.payments_rounded,
            ),
            const SizedBox(height: 16),

            // ── Location ──────────────────────────────────────────────
            _SectionLabel('מיקום (לא חובה)'),
            const SizedBox(height: 6),
            _buildTextField(
              controller: _locationCtrl,
              hint: 'כתובת או אזור',
              prefixIcon: Icons.location_on_outlined,
            ),
            const SizedBox(height: 16),

            // ── Deadline ──────────────────────────────────────────────
            _SectionLabel('דדליין (לא חובה)'),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickDeadline,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 18, color: _kIndigo),
                    const SizedBox(width: 10),
                    Text(
                      _deadline != null
                          ? '${_deadline!.day}/${_deadline!.month}/${_deadline!.year} ${_deadline!.hour}:${_deadline!.minute.toString().padLeft(2, '0')}'
                          : 'בחר תאריך ושעה',
                      style: TextStyle(
                        fontSize: 14,
                        color: _deadline != null ? _kDark : _kMuted,
                      ),
                    ),
                    if (_deadline != null) ...[
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(() => _deadline = null),
                        child: const Icon(Icons.close, size: 18, color: _kMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Proof type ────────────────────────────────────────────
            _SectionLabel('סוג הוכחה נדרש'),
            const SizedBox(height: 6),
            Row(
              children: [
                _proofChip('תמונה', 'photo', Icons.camera_alt_rounded),
                const SizedBox(width: 8),
                _proofChip('טקסט', 'text', Icons.description_rounded),
                const SizedBox(width: 8),
                _proofChip('שניהם', 'both', Icons.photo_library_rounded),
              ].map((w) => Expanded(child: w)).toList(),
            ),
            const SizedBox(height: 16),

            // ── Urgent toggle ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _isUrgent ? _kRed.withValues(alpha: 0.06) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _isUrgent ? _kRed.withValues(alpha: 0.3) : Colors.grey[300]!,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.bolt_rounded, color: _isUrgent ? _kRed : _kMuted),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('סמן כדחוף', style: TextStyle(fontSize: 14, color: _kDark)),
                  ),
                  Switch(
                    value: _isUrgent,
                    onChanged: (v) => setState(() => _isUrgent = v),
                    activeColor: _kRed,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Submit button ─────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _canSubmit ? _submit : null,
                icon: _submitting
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.rocket_launch_rounded, size: 20),
                label: Text(
                  _submitting ? 'מפרסם...' : 'פרסם משימה',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kIndigo,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    int? maxLength,
    TextInputType? keyboardType,
    IconData? prefixIcon,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      textAlign: TextAlign.start,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400]),
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: _kIndigo, size: 20) : null,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _kIndigo, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  Widget _proofChip(String label, String value, IconData icon) {
    final selected = _proofType == value;
    return GestureDetector(
      onTap: () => setState(() => _proofType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _kIndigo.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _kIndigo : Colors.grey[300]!,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: selected ? _kIndigo : _kMuted),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? _kIndigo : _kMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF1A1A2E),
      ),
    );
  }
}
