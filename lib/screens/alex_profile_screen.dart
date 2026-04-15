// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/ai_teacher_service.dart';
import 'ai_teacher_lesson_modal.dart';
import 'finance_screen.dart';

const _kPurple     = Color(0xFF6366F1);
const _kPurpleSoft = Color(0xFFF0F0FF);
const _kGold       = Color(0xFFD4AF37);
const _kDark       = Color(0xFF1A1A2E);

/// Full Airbnb-style profile page for Alex, the AI English teacher.
/// Layout mirrors ExpertProfileScreen: specialist card, action squares,
/// about, reviews, calendar, and a sticky bottom CTA.
/// All data streams from `ai_teachers/alex` Firestore doc so the admin
/// can change everything live.
class AlexProfileScreen extends StatefulWidget {
  const AlexProfileScreen({super.key});

  @override
  State<AlexProfileScreen> createState() => _AlexProfileScreenState();
}

class _AlexProfileScreenState extends State<AlexProfileScreen> {
  // Calendar state
  DateTime? _selectedDay;
  String? _selectedTimeSlot;
  final bool _bioExpanded = false;
  bool _reviewsExpanded = false;
  String _reviewSearchQuery = '';
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Alex', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: AiTeacherService.stream(),
        builder: (context, snap) {
          final data = snap.data ?? AiTeacherService.defaultProfile;
          return Stack(
            children: [
              RefreshIndicator(
                onRefresh: () async {},
                color: _kPurple,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildSpecialistCard(data)),
                    SliverToBoxAdapter(child: _buildActionSquares(data)),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const SizedBox(height: 20),
                            _buildAboutSection(data),
                            const SizedBox(height: 24),
                            _buildScheduleSection(data),
                            const SizedBox(height: 24),
                            _buildReviewsSection(data),
                            // Extra space for sticky bottom bar
                            const SizedBox(height: 100),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _buildBottomBar(data),
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. SPECIALIST CARD (profile header)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSpecialistCard(Map<String, dynamic> data) {
    final name     = data['name'] as String? ?? 'Alex';
    final title    = data['title'] as String? ?? 'AI English Teacher';
    final bio      = data['bio'] as String? ?? '';
    final rating   = (data['rating'] as num?)?.toDouble() ?? 5.0;
    final reviews  = (data['reviewsCount'] as num?)?.toInt() ?? 0;
    final level    = data['level'] as String? ?? 'Intermediate (B1-B2)';
    final letter   = data['avatarLetter'] as String? ?? 'A';
    final isOnline = data['isOnline'] == true;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ── LEFT: details ────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Name + verified
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Icon(Icons.verified, color: Color(0xFF1877F2), size: 18),
                    const SizedBox(width: 5),
                    Text(name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 2),
                // Title
                Text(title, style: const TextStyle(fontSize: 13, color: _kPurple, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                // Level
                Text(level, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 10),

                // Bio (short)
                if (bio.isNotEmpty)
                  Text(
                    bio,
                    maxLines: _bioExpanded ? null : 3,
                    overflow: _bioExpanded ? null : TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.6),
                  ),
                const SizedBox(height: 12),

                // Stat rows
                _statRow(Icons.star_rounded, _kGold, rating.toStringAsFixed(1), 'דירוג'),
                const Divider(height: 16, color: Color(0xFFF3F4F6)),
                _statRow(Icons.chat_bubble_outline_rounded, _kPurple, '$reviews', 'ביקורות'),
                const Divider(height: 16, color: Color(0xFFF3F4F6)),
                _statRow(Icons.access_time_rounded, const Color(0xFF10B981), '24/7', 'זמינות'),

                // Online badge
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isOnline ? const Color(0xFF22C55E).withValues(alpha: 0.1) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isOnline ? const Color(0xFF22C55E).withValues(alpha: 0.3) : Colors.grey[300]!,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 8, color: isOnline ? const Color(0xFF22C55E) : Colors.grey),
                      const SizedBox(width: 5),
                      Text(
                        isOnline ? 'Online 24/7' : 'Offline',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isOnline ? const Color(0xFF22C55E) : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // ── RIGHT: avatar ────────────────────────────────────────────────
          Column(
            children: [
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _kPurple.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    letter,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 44,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // AI Teacher badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, color: Colors.white, size: 12),
                    SizedBox(width: 4),
                    Text('AI Teacher',
                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statRow(IconData icon, Color color, String value, String label) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        const SizedBox(width: 8),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(width: 6),
        Icon(icon, color: color, size: 16),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. ACTION SQUARES (Video + Gallery)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildActionSquares(Map<String, dynamic> data) {
    final gallery = List<String>.from((data['galleryImages'] as List?) ?? []);
    final price = (data['pricePerHour'] as num?)?.toInt() ?? 30;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          // Pricing card
          Expanded(
            child: _actionSquare(
              icon: Icons.monetization_on_rounded,
              label: '₪$price לשעה',
              color: const Color(0xFF10B981),
              onTap: null,
            ),
          ),
          const SizedBox(width: 14),
          // Gallery
          Expanded(
            child: _actionSquare(
              icon: Icons.photo_library_outlined,
              label: 'גלריית עבודות',
              color: gallery.isEmpty ? Colors.grey : _kPurple,
              badge: gallery.isNotEmpty ? '${gallery.length}' : null,
              onTap: gallery.isEmpty
                  ? null
                  : () => _showGallery(context, gallery),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionSquare({
    required IconData icon,
    required String label,
    required Color color,
    String? badge,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 32, color: color),
                if (badge != null)
                  Positioned(
                    top: -4,
                    right: -8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: _kPurple,
                        shape: BoxShape.circle,
                      ),
                      child: Text(badge,
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  void _showGallery(BuildContext context, List<String> images) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Stack(
            children: [
              PageView.builder(
                itemCount: images.length,
                itemBuilder: (_, i) => InteractiveViewer(
                  child: Center(
                    child: Image.network(images[i], fit: BoxFit.contain),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. ABOUT SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAboutSection(Map<String, dynamic> data) {
    final bio = data['bio'] as String? ?? '';
    final features = <String>[
      'שיחה חופשית באנגלית בזמן אמת',
      'תיקון טעויות מיידי עם הסבר',
      'התאמה אישית לרמה שלך',
      'זמין 24/7 — ללא המתנה',
      'סביבה נוחה ללא שיפוטיות',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Text('אודות', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        if (bio.isNotEmpty)
          Text(
            bio,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.6),
          ),
        const SizedBox(height: 14),
        // Feature list
        ...features.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(f,
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
                ],
              ),
            )),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. SCHEDULE / AVAILABILITY SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildScheduleSection(Map<String, dynamic> data) {
    final fromHour = data['availableHoursFrom'] as String? ?? '06:00';
    final toHour   = data['availableHoursTo'] as String? ?? '23:00';
    final days     = List<int>.from((data['availableDays'] as List?) ?? [0, 1, 2, 3, 4, 5, 6]);

    final dayNames = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת'];

    // Generate time slots
    final fromH = int.tryParse(fromHour.split(':').first) ?? 6;
    final toH   = int.tryParse(toHour.split(':').first) ?? 23;
    final slots  = <String>[];
    for (int h = fromH; h < toH; h++) {
      slots.add('${h.toString().padLeft(2, '0')}:00');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Text('זמינות', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),

        // Available days
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey[200]!),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Day chips
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('שעות: $fromHour - $toHour',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(width: 8),
                  const Icon(Icons.access_time, size: 14, color: _kPurple),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: List.generate(7, (i) {
                  final active = days.contains(i);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? _kPurple.withValues(alpha: 0.1) : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: active ? _kPurple.withValues(alpha: 0.3) : Colors.grey[300]!,
                      ),
                    ),
                    child: Text(
                      dayNames[i],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: active ? _kPurple : Colors.grey,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),

              // ── Select a day ─────────────────────────────────────────────
              const Align(
                alignment: Alignment.centerRight,
                child: Text('בחר יום', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 70,
                child: ListView.builder(
                  reverse: true,
                  scrollDirection: Axis.horizontal,
                  itemCount: 14,
                  itemBuilder: (_, i) {
                    final day = DateTime.now().add(Duration(days: i));
                    final dayIdx = day.weekday == 7 ? 0 : day.weekday;
                    final isAvailable = days.contains(dayIdx);
                    final isSelected = _selectedDay != null &&
                        _selectedDay!.year == day.year &&
                        _selectedDay!.month == day.month &&
                        _selectedDay!.day == day.day;

                    return GestureDetector(
                      onTap: isAvailable
                          ? () => setState(() {
                                _selectedDay = day;
                                _selectedTimeSlot = null;
                              })
                          : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 52,
                        margin: const EdgeInsetsDirectional.only(start: 8),
                        decoration: BoxDecoration(
                          color: !isAvailable
                              ? Colors.grey[100]
                              : isSelected
                                  ? _kPurple
                                  : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected ? _kPurple : Colors.grey[300]!,
                          ),
                          boxShadow: isSelected
                              ? [BoxShadow(color: _kPurple.withValues(alpha: 0.25), blurRadius: 8)]
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              dayNames[dayIdx],
                              style: TextStyle(
                                fontSize: 9,
                                color: isSelected ? Colors.white70 : Colors.grey[500],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${day.day}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: !isAvailable
                                    ? Colors.grey
                                    : isSelected
                                        ? Colors.white
                                        : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // ── Time slots ───────────────────────────────────────────────
              if (_selectedDay != null) ...[
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text('בחר שעה', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: ListView.builder(
                    reverse: true,
                    scrollDirection: Axis.horizontal,
                    itemCount: slots.length,
                    itemBuilder: (_, i) {
                      final slot = slots[i];
                      final isSelected = _selectedTimeSlot == slot;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedTimeSlot = slot),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsetsDirectional.only(start: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected ? _kPurple : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? _kPurple : Colors.grey[300]!,
                            ),
                            boxShadow: isSelected
                                ? [BoxShadow(color: _kPurple.withValues(alpha: 0.25), blurRadius: 8)]
                                : null,
                          ),
                          child: Text(
                            slot,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. REVIEWS SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildReviewsSection(Map<String, dynamic> data) {
    final reviews    = List<Map<String, dynamic>>.from((data['reviews'] as List?) ?? []);
    final rating     = (data['rating'] as num?)?.toDouble() ?? 5.0;
    final breakdown  = data['ratingBreakdown'] as Map<String, dynamic>? ?? {};
    final accuracy       = (breakdown['accuracy'] as num?)?.toDouble() ?? 0;
    final responsiveness = (breakdown['responsiveness'] as num?)?.toDouble() ?? 0;
    final quality        = (breakdown['teachingQuality'] as num?)?.toDouble() ?? 0;

    // Filter
    final filtered = _reviewSearchQuery.isEmpty
        ? reviews
        : reviews.where((r) {
            final comment = (r['comment'] as String? ?? '').toLowerCase();
            final name    = (r['name'] as String? ?? '').toLowerCase();
            return comment.contains(_reviewSearchQuery.toLowerCase()) ||
                name.contains(_reviewSearchQuery.toLowerCase());
          }).toList();

    final visible = _reviewsExpanded ? filtered : filtered.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // ── Trust header ───────────────────────────────────────────────────
        if (reviews.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${reviews.length} ביקורות',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500])),
              Row(
                children: [
                  Text(rating.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: _kDark)),
                  const SizedBox(width: 6),
                  const Icon(Icons.star_rounded, color: _kGold, size: 28),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Rating bars
          if (accuracy > 0 || responsiveness > 0 || quality > 0) ...[
            _ratingBar('דיוק ובהירות', accuracy),
            const SizedBox(height: 8),
            _ratingBar('זמן תגובה', responsiveness),
            const SizedBox(height: 8),
            _ratingBar('איכות הוראה', quality),
            const SizedBox(height: 16),
          ],

          // Search
          SizedBox(
            height: 40,
            child: TextField(
              onChanged: (v) => setState(() => _reviewSearchQuery = v),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'חפש בביקורות...',
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                filled: true,
                fillColor: const Color(0xFFF4F7F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                prefixIcon: Icon(Icons.search, color: Colors.grey[400], size: 18),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Review cards ───────────────────────────────────────────────────
        ...visible.map((r) => _buildReviewCard(r)),

        // Show more
        if (filtered.length > 3 && !_reviewsExpanded)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: TextButton(
                onPressed: () => setState(() => _reviewsExpanded = true),
                child: Text('הצג את כל ${filtered.length} הביקורות',
                    style: const TextStyle(color: _kPurple, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _ratingBar(String label, double value) {
    return Row(
      children: [
        Text(value.toStringAsFixed(1),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value / 5.0,
              minHeight: 6,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor: const AlwaysStoppedAnimation<Color>(_kGold),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: Text(label,
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ),
      ],
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    final name    = review['name'] as String? ?? '';
    final rating  = (review['rating'] as num?)?.toDouble() ?? 5.0;
    final comment = review['comment'] as String? ?? '';
    final date    = review['date'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Header: name + date + stars
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(date, style: TextStyle(fontSize: 11, color: Colors.grey[400])),
              Row(
                children: [
                  // Stars
                  ...List.generate(5, (i) {
                    return Icon(
                      i < rating.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: _kGold,
                      size: 14,
                    );
                  }),
                  const SizedBox(width: 8),
                  // Initials avatar
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: _kPurpleSoft,
                    child: Text(
                      name.isNotEmpty ? name[0] : '?',
                      style: const TextStyle(
                          color: _kPurple, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Comment
          Text(
            comment,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.5),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. STICKY BOTTOM BAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBottomBar(Map<String, dynamic> data) {
    final price = (data['pricePerHour'] as num?)?.toInt() ?? 30;
    final hasSelection = _selectedDay != null && _selectedTimeSlot != null;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: ClipRect(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            border: Border(top: BorderSide(color: Colors.grey[200]!)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPurple,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  elevation: 0,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _isProcessing ? null : () => _handlePayAndStart(price.toDouble()),
                child: _isProcessing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : hasSelection
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Icon(Icons.arrow_back_rounded, size: 20),
                              Text('שלם והתחל ב-$_selectedTimeSlot',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              Text('₪$price',
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('₪$price',
                                  style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),
                              const Text('שלם והתחל שיעור',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            ],
                          ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 7. PAYMENT GATE
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _handlePayAndStart(double price) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 1. Check balance first (fast read before showing confirm dialog)
    final balance = await AiTeacherService.getUserBalance(user.uid);

    if (balance < price) {
      // Insufficient balance → show top-up prompt
      if (!mounted) return;
      _showInsufficientBalanceSheet(price, balance);
      return;
    }

    // 2. Confirm payment
    if (!mounted) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PaymentConfirmSheet(price: price, balance: balance),
    );
    if (confirmed != true || !mounted) return;

    // 3. Process payment
    setState(() => _isProcessing = true);
    final error = await AiTeacherService.purchaseLesson(
      userId: user.uid,
      userName: user.displayName ?? '',
    );

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: const Color(0xFFEF4444)),
      );
      return;
    }

    // 4. Payment succeeded → open lesson
    final newBalance = await AiTeacherService.getUserBalance(user.uid);
    if (!mounted) return;
    AiTeacherLessonModal.show(context, remainingCredits: newBalance);
  }

  void _showInsufficientBalanceSheet(double price, double balance) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final maxH = MediaQuery.of(ctx).size.height * 0.90;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Scrollable content ─────────────────────────────────────
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: const Color(0xFFEF4444)
                                    .withValues(alpha: 0.2)),
                          ),
                          child: const Icon(
                              Icons.account_balance_wallet_outlined,
                              color: Color(0xFFEF4444),
                              size: 30),
                        ),
                        const SizedBox(height: 16),
                        const Text('אין מספיק יתרה',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(
                          'עלות השיעור ₪${price.toStringAsFixed(0)} — היתרה שלך ₪${balance.toStringAsFixed(0)}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'חסרים ₪${(price - balance).toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFEF4444)),
                        ),
                      ],
                    ),
                  ),
                ),
                // ── Pinned bottom buttons ──────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const FinanceScreen()));
                            },
                            icon:
                                const Icon(Icons.add_card_rounded, size: 20),
                            label: const Text('הוסף כסף לארנק',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kPurple,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text('ביטול',
                              style: TextStyle(color: Colors.grey[500])),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Payment confirmation bottom sheet
// ═══════════════════════════════════════════════════════════════════════════════

class _PaymentConfirmSheet extends StatelessWidget {
  final double price;
  final double balance;
  const _PaymentConfirmSheet({required this.price, required this.balance});

  @override
  Widget build(BuildContext context) {
    final remaining = balance - price;
    // Cap at 90% of viewport so the button never falls below the fold
    final maxH = MediaQuery.of(context).size.height * 0.90;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        // Flex column: scrollable content on top, pinned buttons at bottom
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Scrollable content ─────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle bar
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // AI avatar
                    Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                      ),
                      child: const Center(
                        child: Text('A',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('אישור תשלום',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text('שיעור אנגלית עם Alex',
                        style: TextStyle(fontSize: 14, color: Colors.grey)),
                    const SizedBox(height: 20),
                    // Price breakdown
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F7F9),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          _row('יתרה נוכחית',
                              '₪${balance.toStringAsFixed(0)}'),
                          const Divider(height: 16),
                          _row('עלות שיעור',
                              '- ₪${price.toStringAsFixed(0)}',
                              valueColor: const Color(0xFFEF4444)),
                          const Divider(height: 16),
                          _row('יתרה לאחר',
                              '₪${remaining.toStringAsFixed(0)}',
                              valueColor: const Color(0xFF10B981),
                              bold: true),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Pinned bottom buttons ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context, true),
                        icon: const Icon(Icons.lock_rounded, size: 18),
                        label: Text(
                            'שלם ₪${price.toStringAsFixed(0)} והתחל שיעור',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text('ביטול',
                          style: TextStyle(color: Colors.grey[500])),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {Color? valueColor, bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              color: valueColor ?? Colors.black87,
            )),
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
      ],
    );
  }
}
