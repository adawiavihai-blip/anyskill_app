// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/review_service.dart';

class ReviewScreen extends StatefulWidget {
  final String jobId;
  final String revieweeId;
  final String revieweeName;
  final String revieweeAvatar;
  final bool isClientReview;

  const ReviewScreen({
    super.key,
    required this.jobId,
    required this.revieweeId,
    required this.revieweeName,
    required this.revieweeAvatar,
    required this.isClientReview,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final Map<String, double> _ratings;
  final TextEditingController _publicCtrl  = TextEditingController();
  final TextEditingController _privateCtrl = TextEditingController();
  bool _submitting = false;
  bool _submitted  = false;

  /// Criteria when a CUSTOMER reviews an EXPERT (isClientReview == true)
  static const _clientCategories = [
    ('professional',  'מקצועיות',             Icons.workspace_premium_rounded),
    ('timing',        'דיוק בזמנים',          Icons.schedule_rounded),
    ('communication', 'תקשורת',               Icons.chat_bubble_outline_rounded),
    ('value',         'תמורה למחיר',          Icons.price_check_rounded),
  ];

  /// Criteria when an EXPERT reviews a CUSTOMER (isClientReview == false)
  static const _expertCategories = [
    ('communication', 'תקשורת',               Icons.chat_bubble_outline_rounded),
    ('timing',        'דיוק בזמנים',          Icons.schedule_rounded),
    ('workspace',     'סביבת עבודה / נוחות',  Icons.home_work_rounded),
    ('fairness',      'הוגנות',               Icons.handshake_rounded),
  ];

  List<(String, String, IconData)> get _categories =>
      widget.isClientReview ? _clientCategories : _expertCategories;

  @override
  void initState() {
    super.initState();
    // Initialize rating keys based on the review direction
    _ratings = {for (final c in _categories) c.$1: 0};
  }

  @override
  void dispose() {
    _publicCtrl.dispose();
    _privateCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_ratings.values.any((v) => v == 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('אנא דרג את כל 4 הקריטריונים'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    setState(() => _submitting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final name = userSnap.data()?['name']?.toString() ?? 'משתמש';

      await ReviewService.submitReview(
        jobId:               widget.jobId,
        reviewerId:          uid,
        reviewerName:        name,
        revieweeId:          widget.revieweeId,
        isClientReview:      widget.isClientReview,
        ratingParams:        Map.from(_ratings),
        publicComment:       _publicCtrl.text.trim(),
        privateAdminComment: _privateCtrl.text.trim(),
      );
      setState(() {
        _submitted  = true;
        _submitting = false;
      });
    } catch (e) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('שגיאה: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.isClientReview ? 'דרג את המומחה' : 'דרג את הלקוח',
          style: const TextStyle(
            color:      Color(0xFF1A1A2E),
            fontWeight: FontWeight.bold,
            fontSize:   18,
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)),
      ),
      body: _submitted ? _buildSuccessState() : _buildForm(),
    );
  }

  // ── Success state ──────────────────────────────────────────────────────────
  Widget _buildSuccessState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width:  90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                ),
              ),
              child: const Icon(Icons.check_rounded,
                  size: 50, color: Colors.white),
            ),
            const SizedBox(height: 24),
            const Text(
              'תודה! חוות דעתך נשמרה בהצלחה',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize:   20,
                fontWeight: FontWeight.bold,
                color:      Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:        const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'חוות דעתך תפורסם לאחר שהצד השני ישתף את שלו, או באופן אוטומטי לאחר 7 ימים.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color:    Color(0xFF92400E),
                ),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon:  const Icon(Icons.close_rounded),
                label: const Text('✕ סגור'),
                style: OutlinedButton.styleFrom(
                  padding:      const EdgeInsets.symmetric(vertical: 14),
                  shape:        RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  side:         const BorderSide(color: Color(0xFF6366F1)),
                  foregroundColor: const Color(0xFF6366F1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Main form ──────────────────────────────────────────────────────────────
  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Hero card ──────────────────────────────────────────────────────
          _buildHeroCard(),
          const SizedBox(height: 20),

          // ── Category ratings ──────────────────────────────────────────────
          _buildRatingsCard(),
          const SizedBox(height: 16),

          // ── Public comment ────────────────────────────────────────────────
          _buildTextField(
            controller: _publicCtrl,
            label:      '💬 חוות דעת פומבית',
            hint:       widget.isClientReview
                ? 'ספר על החוויה שלך עם המומחה... (אופציונלי)'
                : 'ספר על החוויה שלך עם הלקוח... (אופציונלי)',
            maxLines:   4,
            bgColor:    Colors.white,
          ),
          const SizedBox(height: 12),

          // ── Private admin message ─────────────────────────────────────────
          _buildTextField(
            controller: _privateCtrl,
            label:      '🔒 הודעה פרטית למנהל',
            hint:       'משהו שרוצה לציין בפרטיות... (אופציונלי)',
            maxLines:   3,
            bgColor:    const Color(0xFFFFFBEB),
          ),
          const SizedBox(height: 16),

          // ── Info card ─────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color:        const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
              border:       Border.all(color: const Color(0xFFFCD34D)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ℹ️', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.isClientReview
                        ? 'חוות דעתך תפורסם רק לאחר שגם הצד השני ישתף חוות דעתו, או לאחר 7 ימים.'
                        : 'הדירוג שלך בונה את המוניטין של הלקוח ועוזר למומחים אחרים. יפורסם לאחר שגם הלקוח ישתף חוות דעת, או לאחר 7 ימים.',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      color:    Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Submit button ─────────────────────────────────────────────────
          _submitting
              ? const Center(child: CircularProgressIndicator())
              : DecoratedBox(
                  decoration: BoxDecoration(
                    gradient:     const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor:     Colors.transparent,
                      padding:         const EdgeInsets.symmetric(vertical: 16),
                      shape:           RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text(
                      'שלח חוות דעת ⭐',
                      style: TextStyle(
                        color:      Colors.white,
                        fontSize:   16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Hero card ──────────────────────────────────────────────────────────────
  Widget _buildHeroCard() {
    final hasAvatar = widget.revieweeAvatar.startsWith('http');
    final initials  = widget.revieweeName.isNotEmpty
        ? widget.revieweeName[0].toUpperCase()
        : '?';

    return Card(
      elevation:    0,
      color:        Colors.white,
      shape:        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CircleAvatar(
              radius:          40,
              backgroundColor: const Color(0xFFEEF2FF),
              backgroundImage: hasAvatar
                  ? CachedNetworkImageProvider(widget.revieweeAvatar)
                  : null,
              child: hasAvatar
                  ? null
                  : Text(
                      initials,
                      style: const TextStyle(
                        fontSize:   28,
                        fontWeight: FontWeight.bold,
                        color:      Color(0xFF6366F1),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.revieweeName,
              style: const TextStyle(
                fontSize:   18,
                fontWeight: FontWeight.bold,
                color:      Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color:        const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                widget.isClientReview ? 'מומחה' : 'לקוח',
                style: const TextStyle(
                  fontSize:   12,
                  fontWeight: FontWeight.w600,
                  color:      Color(0xFF6366F1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Ratings card ───────────────────────────────────────────────────────────
  Widget _buildRatingsCard() {
    return Card(
      elevation:    0,
      color:        Colors.white,
      shape:        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              'דרג לפי קריטריונים',
              textAlign:  TextAlign.right,
              style:      TextStyle(
                fontSize:   16,
                fontWeight: FontWeight.bold,
                color:      Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 16),
            ..._categories.map((cat) {
              final key     = cat.$1;
              final label   = cat.$2;
              final icon    = cat.$3;
              final current = _ratings[key] ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    // Stars (LTR order — left side)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(5, (i) {
                        final starVal = i + 1.0;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _ratings[key] = starVal),
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 3),
                            child: Icon(
                              i < current
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: i < current
                                  ? const Color(0xFFFBBF24)
                                  : Colors.grey.shade300,
                              size: 28,
                            ),
                          ),
                        );
                      }),
                    ),
                    const Spacer(),
                    // Label + icon (right side, RTL)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize:   14,
                            fontWeight: FontWeight.w600,
                            color:      Color(0xFF374151),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(icon,
                            size:  20,
                            color: const Color(0xFF6366F1)),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ── Text field helper ──────────────────────────────────────────────────────
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required int maxLines,
    required Color bgColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize:   14,
            fontWeight: FontWeight.w600,
            color:      Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller:   controller,
          maxLines:     maxLines,
          textAlign:    TextAlign.right,
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(
            hintText:     hint,
            hintStyle:    const TextStyle(color: Colors.grey, fontSize: 13),
            filled:       true,
            fillColor:    bgColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:   BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:   BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:   const BorderSide(color: Color(0xFF6366F1)),
            ),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
      ],
    );
  }
}
