/// AnySkill — Daily Report Form (Pet Stay Tracker v13.0.0, Step 10)
///
/// Pension-only. Modal bottom sheet the provider fills at end of day
/// to summarise the dog's day. Auto-fills `walksCompleted`,
/// `mealsEaten`, `medicationGiven`, pee/poop counts from today's
/// Firestore state (schedule items + finished walks + feed markers).
/// Provider only has to pick a mood + optional notes.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/schedule_item.dart' show dayKeyOf;
import '../services/pet_update_service.dart';

class DailyReportForm extends StatefulWidget {
  final String jobId;
  final String customerId;
  final String expertId;

  const DailyReportForm({
    super.key,
    required this.jobId,
    required this.customerId,
    required this.expertId,
  });

  static Future<bool> show(
    BuildContext context, {
    required String jobId,
    required String customerId,
    required String expertId,
  }) async {
    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DailyReportForm(
        jobId: jobId,
        customerId: customerId,
        expertId: expertId,
      ),
    );
    return res == true;
  }

  @override
  State<DailyReportForm> createState() => _DailyReportFormState();
}

class _DailyReportFormState extends State<DailyReportForm> {
  String? _mood;
  final _notesCtrl = TextEditingController();
  bool _submitting = false;
  bool _loading = true;

  // Computed from Firestore
  int _walksCompleted = 0;
  double _totalKm = 0;
  int _peeCount = 0;
  int _poopCount = 0;
  int _mealsDone = 0;
  int _mealsTotal = 0;
  bool _medicationAllDone = false;
  int _medsTotal = 0;
  int _medsDone = 0;

  static const _moods = [
    ('excellent', '😄', 'מצוין'),
    ('good', '😊', 'טוב'),
    ('okay', '😐', 'בסדר'),
    ('poor', '😔', 'לא טוב'),
  ];

  @override
  void initState() {
    super.initState();
    _autofill();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  /// Reads today's schedule items, finished walks, and pee/poop updates
  /// to pre-populate the report. Everything is local date-based.
  Future<void> _autofill() async {
    final db = FirebaseFirestore.instance;
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final todayKey = dayKeyOf(today);

    try {
      // Schedule items for today
      final schedSnap = await db
          .collection('jobs')
          .doc(widget.jobId)
          .collection('petStay')
          .doc('data')
          .collection('schedule')
          .where('dayKey', isEqualTo: todayKey)
          .get();

      int mealsDone = 0, mealsTotal = 0;
      int medsDone = 0, medsTotal = 0;
      for (final d in schedSnap.docs) {
        final type = d.data()['type'] as String? ?? '';
        final done = d.data()['completed'] == true;
        if (type == 'feed') {
          mealsTotal++;
          if (done) mealsDone++;
        }
        if (type == 'medication') {
          medsTotal++;
          if (done) medsDone++;
        }
      }

      // Finished walks today
      final walksSnap = await db
          .collection('dog_walks')
          .where('jobId', isEqualTo: widget.jobId)
          .where('startedAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .get();

      int walks = 0;
      double km = 0;
      int pee = 0, poop = 0;
      for (final d in walksSnap.docs) {
        final status = d.data()['status'] as String? ?? '';
        if (status != 'finished') continue;
        walks++;
        km += ((d.data()['totalDistanceMeters'] as num?)?.toDouble() ?? 0) /
            1000;
        final markers = (d.data()['markers'] as List? ?? const []);
        for (final m in markers) {
          if (m is Map && m['type'] == 'pee') pee++;
          if (m is Map && m['type'] == 'poop') poop++;
        }
      }

      if (!mounted) return;
      setState(() {
        _mealsDone = mealsDone;
        _mealsTotal = mealsTotal;
        _medsDone = medsDone;
        _medsTotal = medsTotal;
        _medicationAllDone = medsTotal > 0 && medsDone == medsTotal;
        _walksCompleted = walks;
        _totalKm = double.parse(km.toStringAsFixed(2));
        _peeCount = pee;
        _poopCount = poop;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_mood == null) return;
    setState(() => _submitting = true);
    try {
      await PetUpdateService.instance.writeDailyReport(
        jobId: widget.jobId,
        customerId: widget.customerId,
        expertId: widget.expertId,
        reportData: {
          'mood': _mood,
          'mealsEaten': _mealsTotal > 0 ? '$_mealsDone/$_mealsTotal' : '—',
          'walksCompleted': _walksCompleted,
          'totalDistanceKm': _totalKm,
          'medicationGiven': _medicationAllDone,
          'peeCount': _peeCount,
          'poopCount': _poopCount,
          'notes': _notesCtrl.text.trim(),
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📊 הדו"ח נשלח ללקוח'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '📊 דו"ח יומי',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'עדכון קצר לבעלים — מצב הכלב ופעילות היום',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
            ),
            const SizedBox(height: 20),

            // Mood
            const Text('מצב רוח',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Color(0xFF1A1A2E))),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final m in _moods)
                  Expanded(child: _moodPill(m.$1, m.$2, m.$3)),
              ],
            ),

            const SizedBox(height: 20),

            // Auto-filled stats
            const Text('מה קרה היום',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Color(0xFF1A1A2E))),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              _statsGrid(),

            const SizedBox(height: 20),

            // Notes
            const Text('הערות',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Color(0xFF1A1A2E))),
            const SizedBox(height: 10),
            TextField(
              controller: _notesCtrl,
              maxLines: 4,
              minLines: 3,
              enabled: !_submitting,
              decoration: InputDecoration(
                hintText:
                    'איך היה היום? משהו מיוחד לציין? (אופציונלי)',
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: Color(0xFF6366F1), width: 2),
                ),
              ),
            ),

            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _mood != null
                      ? const Color(0xFF6366F1)
                      : const Color(0xFFD1D5DB),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, color: Colors.white),
                label: Text(
                  _submitting ? 'שולח...' : 'שלח דו"ח',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onPressed:
                    (_mood == null || _submitting) ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moodPill(String key, String emoji, String label) {
    final selected = _mood == key;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _submitting ? null : () => setState(() => _mood = key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFEEF2FF)
                : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFF6366F1)
                  : const Color(0xFFE5E7EB),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? const Color(0xFF6366F1)
                      : const Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statsGrid() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _stat(
                  Icons.restaurant_rounded,
                  'ארוחות',
                  _mealsTotal > 0 ? '$_mealsDone/$_mealsTotal' : '—',
                  const Color(0xFFF59E0B),
                ),
              ),
              Expanded(
                child: _stat(
                  Icons.directions_walk_rounded,
                  'הליכונים',
                  '$_walksCompleted',
                  const Color(0xFF10B981),
                ),
              ),
              Expanded(
                child: _stat(
                  Icons.straighten_rounded,
                  'ק"מ',
                  _totalKm.toStringAsFixed(1),
                  const Color(0xFF3B82F6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _stat(
                  Icons.medication_rounded,
                  'תרופות',
                  _medsTotal == 0
                      ? '—'
                      : (_medicationAllDone ? '✓ הכל' : '$_medsDone/$_medsTotal'),
                  const Color(0xFFEF4444),
                ),
              ),
              Expanded(
                child: _stat(
                  Icons.water_drop_rounded,
                  'פיפי',
                  '$_peeCount',
                  const Color(0xFFCA8A04),
                ),
              ),
              Expanded(
                child: _stat(
                  Icons.pest_control_rounded,
                  'קקי',
                  '$_poopCount',
                  const Color(0xFF92400E),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: color,
              fontSize: 15,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }
}
