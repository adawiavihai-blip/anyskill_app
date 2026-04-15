// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import '../services/ai_teacher_service.dart';

const _kPurple     = Color(0xFF6366F1);
const _kPurpleSoft = Color(0xFFF0F0FF);

/// Admin control panel for managing the AI Teacher (Alex).
/// All changes write to `ai_teachers/alex` in Firestore and update
/// the profile page + category card in real-time.
class AdminAiTeacherTab extends StatefulWidget {
  const AdminAiTeacherTab({super.key});

  @override
  State<AdminAiTeacherTab> createState() => _AdminAiTeacherTabState();
}

class _AdminAiTeacherTabState extends State<AdminAiTeacherTab> {
  final _nameCtrl      = TextEditingController();
  final _titleCtrl     = TextEditingController();
  final _bioCtrl       = TextEditingController();
  final _letterCtrl    = TextEditingController();
  final _priceCtrl     = TextEditingController();
  final _levelCtrl     = TextEditingController();
  final _ratingCtrl    = TextEditingController();
  final _reviewsCtrl   = TextEditingController();
  final _didUrlCtrl    = TextEditingController();
  final _hoursFromCtrl = TextEditingController();
  final _hoursToCtrl   = TextEditingController();

  bool _isOnline = true;
  List<int> _availableDays = [0, 1, 2, 3, 4, 5, 6];
  bool _loaded = false;
  bool _saving = false;

  // Review form
  final _revNameCtrl    = TextEditingController();
  final _revCommentCtrl = TextEditingController();
  final _revRatingCtrl  = TextEditingController(text: '5.0');

  // Rating breakdown
  final _accCtrl  = TextEditingController();
  final _respCtrl = TextEditingController();
  final _qualCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final data = await AiTeacherService.fetch();
    if (!mounted) return;
    _nameCtrl.text      = data['name'] as String? ?? 'Alex';
    _titleCtrl.text     = data['title'] as String? ?? 'AI English Teacher';
    _bioCtrl.text       = data['bio'] as String? ?? '';
    _letterCtrl.text    = data['avatarLetter'] as String? ?? 'A';
    _priceCtrl.text     = '${(data['pricePerHour'] as num?) ?? 30}';
    _levelCtrl.text     = data['level'] as String? ?? 'Intermediate (B1-B2)';
    _ratingCtrl.text    = '${(data['rating'] as num?) ?? 5.0}';
    _reviewsCtrl.text   = '${(data['reviewsCount'] as num?) ?? 128}';
    _didUrlCtrl.text    = data['didAgentUrl'] as String? ?? '';
    _hoursFromCtrl.text = data['availableHoursFrom'] as String? ?? '06:00';
    _hoursToCtrl.text   = data['availableHoursTo'] as String? ?? '23:00';
    _isOnline           = data['isOnline'] == true;
    _availableDays      = List<int>.from((data['availableDays'] as List?) ?? [0, 1, 2, 3, 4, 5, 6]);

    final bd = data['ratingBreakdown'] as Map<String, dynamic>? ?? {};
    _accCtrl.text  = '${(bd['accuracy'] as num?) ?? 4.9}';
    _respCtrl.text = '${(bd['responsiveness'] as num?) ?? 5.0}';
    _qualCtrl.text = '${(bd['teachingQuality'] as num?) ?? 4.8}';

    setState(() => _loaded = true);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AiTeacherService.update({
        'name':               _nameCtrl.text.trim(),
        'title':              _titleCtrl.text.trim(),
        'bio':                _bioCtrl.text.trim(),
        'avatarLetter':       _letterCtrl.text.trim(),
        'pricePerHour':       int.tryParse(_priceCtrl.text.trim()) ?? 30,
        'level':              _levelCtrl.text.trim(),
        'rating':             double.tryParse(_ratingCtrl.text.trim()) ?? 5.0,
        'reviewsCount':       int.tryParse(_reviewsCtrl.text.trim()) ?? 128,
        'didAgentUrl':        _didUrlCtrl.text.trim(),
        'isOnline':           _isOnline,
        'availableDays':      _availableDays,
        'availableHoursFrom': _hoursFromCtrl.text.trim(),
        'availableHoursTo':   _hoursToCtrl.text.trim(),
        'ratingBreakdown': {
          'accuracy':       double.tryParse(_accCtrl.text.trim()) ?? 4.9,
          'responsiveness': double.tryParse(_respCtrl.text.trim()) ?? 5.0,
          'teachingQuality': double.tryParse(_qualCtrl.text.trim()) ?? 4.8,
        },
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הפרופיל של Alex עודכן בהצלחה ✓'),
          backgroundColor: Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _titleCtrl.dispose();
    _bioCtrl.dispose();
    _letterCtrl.dispose();
    _priceCtrl.dispose();
    _levelCtrl.dispose();
    _ratingCtrl.dispose();
    _reviewsCtrl.dispose();
    _didUrlCtrl.dispose();
    _hoursFromCtrl.dispose();
    _hoursToCtrl.dispose();
    _revNameCtrl.dispose();
    _revCommentCtrl.dispose();
    _revRatingCtrl.dispose();
    _accCtrl.dispose();
    _respCtrl.dispose();
    _qualCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildSection('פרטי פרופיל', Icons.person_rounded, [
              _field('שם', _nameCtrl),
              _field('כותרת', _titleCtrl),
              _field('אות אווטאר', _letterCtrl),
              _field('ביו', _bioCtrl, maxLines: 3),
              _field('רמה', _levelCtrl),
            ]),
            const SizedBox(height: 16),
            _buildSection('תמחור וסטטוס', Icons.attach_money_rounded, [
              _field('מחיר לשעה (₪)', _priceCtrl, numeric: true),
              _onlineToggle(),
            ]),
            const SizedBox(height: 16),
            _buildSection('דירוג', Icons.star_rounded, [
              _field('דירוג כללי (1-5)', _ratingCtrl, numeric: true),
              _field('מספר ביקורות', _reviewsCtrl, numeric: true),
              const Divider(height: 20),
              const Align(
                alignment: Alignment.centerRight,
                child: Text('פילוח דירוג', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              const SizedBox(height: 8),
              _field('דיוק ובהירות', _accCtrl, numeric: true),
              _field('זמן תגובה', _respCtrl, numeric: true),
              _field('איכות הוראה', _qualCtrl, numeric: true),
            ]),
            const SizedBox(height: 16),
            _buildSection('זמינות', Icons.schedule_rounded, [
              _field('שעת התחלה (HH:mm)', _hoursFromCtrl),
              _field('שעת סיום (HH:mm)', _hoursToCtrl),
              const SizedBox(height: 8),
              _daySelector(),
            ]),
            const SizedBox(height: 16),
            _buildSection('D-ID Agent', Icons.smart_toy_rounded, [
              _field('D-ID Agent URL', _didUrlCtrl, maxLines: 2),
            ]),
            const SizedBox(height: 16),
            _buildReviewsManager(),
          ],
        ),
        // Sticky save button
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey[200]!)),
            ),
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 20),
              label: Text(_saving ? 'שומר...' : 'שמור שינויים'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPurple,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('ניהול מורה AI',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('שנה את כל ההגדרות של Alex ללא קוד',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(Icons.smart_toy_rounded, color: Colors.white, size: 28),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section wrapper ────────────────────────────────────────────────────────

  Widget _buildSection(String title, IconData icon, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Icon(icon, color: _kPurple, size: 20),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  // ── Field helpers ──────────────────────────────────────────────────────────

  Widget _field(String label, TextEditingController ctrl,
      {int maxLines = 1, bool numeric = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        textAlign: TextAlign.right,
        maxLines: maxLines,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 13, color: Colors.grey[600]),
          filled: true,
          fillColor: _kPurpleSoft.withValues(alpha: 0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _kPurple, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }

  Widget _onlineToggle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Switch(
          value: _isOnline,
          onChanged: (v) => setState(() => _isOnline = v),
          activeColor: _kPurple,
        ),
        const SizedBox(width: 8),
        Text(_isOnline ? 'Online 24/7' : 'Offline',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _isOnline ? const Color(0xFF22C55E) : Colors.grey,
            )),
        const SizedBox(width: 6),
        Icon(Icons.circle, size: 10, color: _isOnline ? const Color(0xFF22C55E) : Colors.grey),
      ],
    );
  }

  Widget _daySelector() {
    const dayNames = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת'];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: List.generate(7, (i) {
        final active = _availableDays.contains(i);
        return GestureDetector(
          onTap: () {
            setState(() {
              if (active) {
                _availableDays.remove(i);
              } else {
                _availableDays.add(i);
              }
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: active ? _kPurple : Colors.grey[100],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              dayNames[i],
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : Colors.grey[600],
              ),
            ),
          ),
        );
      }),
    );
  }

  // ── Reviews manager ────────────────────────────────────────────────────────

  Widget _buildReviewsManager() {
    return StreamBuilder<Map<String, dynamic>>(
      stream: AiTeacherService.stream(),
      builder: (context, snap) {
        final data = snap.data ?? AiTeacherService.defaultProfile;
        final reviews = List<Map<String, dynamic>>.from(
            (data['reviews'] as List?) ?? []);

        return _buildSection('ביקורות (${reviews.length})', Icons.rate_review_rounded, [
          // Add review form
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kPurpleSoft.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('הוסף ביקורת', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                _field('שם הכותב', _revNameCtrl),
                _field('דירוג (1-5)', _revRatingCtrl, numeric: true),
                _field('תוכן הביקורת', _revCommentCtrl, maxLines: 2),
                const SizedBox(height: 4),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (_revNameCtrl.text.trim().isEmpty || _revCommentCtrl.text.trim().isEmpty) return;
                      await AiTeacherService.addReview({
                        'name': _revNameCtrl.text.trim(),
                        'rating': double.tryParse(_revRatingCtrl.text.trim()) ?? 5.0,
                        'comment': _revCommentCtrl.text.trim(),
                        'date': DateTime.now().toString().substring(0, 10),
                      });
                      _revNameCtrl.clear();
                      _revCommentCtrl.clear();
                      _revRatingCtrl.text = '5.0';
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('הוסף'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Existing reviews
          ...List.generate(reviews.length, (i) {
            final r = reviews[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                    onPressed: () => _confirmDeleteReview(i, r['name'] as String? ?? ''),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('⭐ ${r['rating'] ?? 5.0}',
                                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                            const SizedBox(width: 8),
                            Text(r['name'] as String? ?? '',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(r['comment'] as String? ?? '',
                            textAlign: TextAlign.right,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ]);
      },
    );
  }

  void _confirmDeleteReview(int index, String name) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('מחק ביקורת?', textAlign: TextAlign.right),
        content: Text('האם למחוק את הביקורת של $name?', textAlign: TextAlign.right),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              AiTeacherService.removeReview(index);
            },
            child: const Text('מחק', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
