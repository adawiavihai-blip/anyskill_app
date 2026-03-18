// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/academy_service.dart';
import '../widgets/xp_progress_bar.dart';
import 'course_player_screen.dart';

class AcademyScreen extends StatefulWidget {
  const AcademyScreen({super.key});

  @override
  State<AcademyScreen> createState() => _AcademyScreenState();
}

class _AcademyScreenState extends State<AcademyScreen> {
  String _selectedCategory = 'הכל';
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream;

  @override
  void initState() {
    super.initState();
    _userStream = _uid.isEmpty
        ? const Stream.empty()
        : FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: AcademyService.streamProgress(_uid),
          builder: (context, progressSnap) {
            // Build progress map: courseId → CourseProgress
            final progressMap = <String, CourseProgress>{};
            for (final doc in progressSnap.data?.docs ?? []) {
              progressMap[doc.id] = CourseProgress.fromMap(doc.data());
            }

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: AcademyService.streamCourses(),
              builder: (context, coursesSnap) {
                final allCourses = (coursesSnap.data?.docs ?? [])
                    .map(AcademyCourse.fromDoc)
                    .toList();

                // Unique categories for filter chips
                final categories = [
                  'הכל',
                  ...{for (final c in allCourses) c.category}
                      .where((c) => c.isNotEmpty),
                ];

                final filtered = _selectedCategory == 'הכל'
                    ? allCourses
                    : allCourses
                        .where((c) => c.category == _selectedCategory)
                        .toList();

                return CustomScrollView(
                  slivers: [
                    // ── Header ─────────────────────────────────────────────
                    SliverToBoxAdapter(child: _buildHeader()),

                    // ── Category filter chips ───────────────────────────────
                    SliverToBoxAdapter(
                        child: _buildCategoryChips(categories)),

                    // ── Loading ─────────────────────────────────────────────
                    if (coursesSnap.connectionState ==
                        ConnectionState.waiting)
                      const SliverFillRemaining(
                        child: Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFF6366F1)),
                        ),
                      )

                    // ── Empty ────────────────────────────────────────────────
                    else if (filtered.isEmpty)
                      SliverFillRemaining(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.school_outlined,
                                  size: 64,
                                  color: Colors.white.withValues(alpha: 0.3)),
                              const SizedBox(height: 16),
                              Text(
                                'אין קורסים בקטגוריה זו עדיין',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )

                    // ── Course grid ───────────────────────────────────────────
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        sliver: SliverGrid(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) {
                              final course = filtered[i];
                              return _CourseCard(
                                course:   course,
                                progress: progressMap[course.id],
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CoursePlayerScreen(
                                      course:   course,
                                      progress: progressMap[course.id],
                                      uid:      _uid,
                                    ),
                                  ),
                                ),
                              );
                            },
                            childCount: filtered.length,
                          ),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount:  2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing:  12,
                            childAspectRatio: 0.70,
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userStream,
      builder: (context, snap) {
        final xp = ((snap.data?.data() ?? {})['xp'] as num? ?? 0).toInt();
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios,
                        color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Text(
                    '🎓 AnySkill Academy',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              // XP progress bar
              if (_uid.isNotEmpty)
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: XpProgressBar(xp: xp, darkMode: true),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryChips(List<String> categories) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final cat = categories[i];
          final isSelected = cat == _selectedCategory;
          return ChoiceChip(
            label: Text(cat),
            selected: isSelected,
            onSelected: (_) => setState(() => _selectedCategory = cat),
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : Colors.white70,
              fontWeight:
                  isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            selectedColor: const Color(0xFF6366F1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: isSelected
                    ? const Color(0xFF6366F1)
                    : Colors.white.withValues(alpha: 0.15),
              ),
            ),
            showCheckmark: false,
          );
        },
      ),
    );
  }
}

// ── Course card ────────────────────────────────────────────────────────────────

class _CourseCard extends StatelessWidget {
  final AcademyCourse   course;
  final CourseProgress? progress;
  final VoidCallback    onTap;

  const _CourseCard({
    required this.course,
    required this.progress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final videoId = AcademyService.extractVideoId(course.videoUrl);
    final thumb   = (course.thumbnailUrl?.isNotEmpty == true)
        ? course.thumbnailUrl!
        : AcademyService.thumbnailUrl(videoId);

    final pct      = progress?.watchedPercent ?? 0.0;
    final isPassed = progress?.passed ?? false;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Thumbnail area ────────────────────────────────────────
              Expanded(
                flex: 5,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFF2D2D44),
                        child: const Icon(Icons.play_circle_outline,
                            color: Colors.white54, size: 48),
                      ),
                    ),
                    // Dark gradient at bottom
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.5),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Certified badge
                    if (isPassed)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified,
                                  color: Colors.white, size: 12),
                              SizedBox(width: 3),
                              Text(
                                'מוסמך',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // Play icon
                    if (!isPassed)
                      const Center(
                        child: Icon(
                          Icons.play_circle_filled,
                          color: Colors.white70,
                          size: 40,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                        ),
                      ),
                    // Duration chip at bottom-left
                    if (course.duration.isNotEmpty)
                      Positioned(
                        bottom: 6,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            course.duration,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Progress bar (only if started) ────────────────────────
              if (pct > 0)
                LinearProgressIndicator(
                  value: (pct / 100).clamp(0.0, 1.0),
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isPassed
                        ? const Color(0xFF10B981)
                        : const Color(0xFF6366F1),
                  ),
                  minHeight: 3,
                ),

              // ── Text info + button ─────────────────────────────────────
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      // CTA button
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isPassed
                                ? [
                                    const Color(0xFF10B981),
                                    const Color(0xFF059669)
                                  ]
                                : [
                                    const Color(0xFF6366F1),
                                    const Color(0xFF4F46E5)
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isPassed
                              ? 'צפה שוב'
                              : pct > 0
                                  ? 'המשך'
                                  : 'התחל ללמוד',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
