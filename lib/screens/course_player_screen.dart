// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../services/academy_service.dart';
import '../services/audio_service.dart';

class CoursePlayerScreen extends StatefulWidget {
  final AcademyCourse   course;
  final CourseProgress? progress;
  final String          uid;

  const CoursePlayerScreen({
    super.key,
    required this.course,
    required this.progress,
    required this.uid,
  });

  @override
  State<CoursePlayerScreen> createState() => _CoursePlayerScreenState();
}

class _CoursePlayerScreenState extends State<CoursePlayerScreen> {
  late final YoutubePlayerController _ytController;
  late final String _videoId;

  // ── Watch-progress state ────────────────────────────────────────────────────
  double  _watchedPercent = 0;
  bool    _canTakeQuiz    = false;
  Timer?  _progressTimer;

  // ── Quiz state ──────────────────────────────────────────────────────────────
  bool      _showQuiz       = false;
  List<int?> _answers       = [];
  bool      _quizSubmitted  = false;
  bool      _passed         = false;
  bool      _completing     = false;

  // ── Celebration overlay ─────────────────────────────────────────────────────
  bool _showCelebration = false;

  @override
  void initState() {
    super.initState();

    _videoId        = AcademyService.extractVideoId(widget.course.videoUrl);
    _watchedPercent = widget.progress?.watchedPercent ?? 0;
    _passed         = widget.progress?.passed ?? false;
    _canTakeQuiz    = _watchedPercent >= 80 || _passed;

    if (widget.course.quizQuestions.isNotEmpty) {
      _answers = List.filled(widget.course.quizQuestions.length, null);
    }

    _ytController = YoutubePlayerController.fromVideoId(
      videoId:  _videoId,
      autoPlay: false,
      params: const YoutubePlayerParams(
        showControls:       true,
        showFullscreenButton: true,
        enableCaption:      false,
        playsInline:        true,
        mute:               false,
      ),
    );

    // Poll player position every 5 seconds to track progress
    _progressTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _trackProgress());
  }

  Future<void> _trackProgress() async {
    if (!mounted) return;
    try {
      final currentSec = await _ytController.currentTime;
      final durSec     =
          _ytController.value.metaData.duration.inSeconds.toDouble();
      if (durSec <= 0) return;

      final pct = (currentSec / durSec * 100).clamp(0.0, 100.0);
      if (pct > _watchedPercent) {
        if (mounted) {
          setState(() {
            _watchedPercent = pct;
            if (pct >= 80) _canTakeQuiz = true;
          });
        }
        await AcademyService.saveWatchProgress(
            widget.uid, widget.course.id, pct);
      }
    } catch (_) {
      // Player not ready yet — ignore
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _ytController.close();
    super.dispose();
  }

  // ── Quiz submit ─────────────────────────────────────────────────────────────

  void _submitQuiz() {
    final questions = widget.course.quizQuestions;
    if (questions.isEmpty) {
      _awardCertification();
      return;
    }

    int correct = 0;
    for (int i = 0; i < questions.length; i++) {
      final correctIdx = (questions[i]['correctIndex'] as num?)?.toInt() ?? -1;
      if (_answers[i] == correctIdx) correct++;
    }

    final passPct = correct / questions.length;
    final passed  = passPct >= 0.7; // 70% pass threshold

    setState(() {
      _quizSubmitted = true;
      _passed        = passed;
    });

    if (passed) _awardCertification();
  }

  Future<void> _awardCertification() async {
    if (widget.uid.isEmpty || _completing) return;
    setState(() {
      _completing      = true;
      _showCelebration = true;
    });

    // Sound: course completed (resolved via admin event mapping)
    AudioService.instance.playEvent(AppEvent.onCourseCompleted);

    await AcademyService.completeCourse(
      uid:         widget.uid,
      courseId:    widget.course.id,
      courseTitle: widget.course.title,
      category:    widget.course.category,
      xpReward:    widget.course.xpReward,
    );

    // Brief celebration before the dialog
    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) {
      setState(() => _showCelebration = false);
      _showCertificationDialog();
    }
  }

  void _showCertificationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding:
            const EdgeInsets.fromLTRB(24, 28, 24, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎓', style: TextStyle(fontSize: 72)),
            const SizedBox(height: 12),
            const Text(
              'מזל טוב!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'השלמת את "${widget.course.title}" בהצלחה!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.35)),
              ),
              child: Column(
                children: [
                  Text(
                    '+${widget.course.xpReward} XP',
                    style: const TextStyle(
                      color: Color(0xFF6366F1),
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '🏅 הסמכת ${widget.course.category}',
                    style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: () {
                Navigator.of(context).pop(); // close dialog
                Navigator.of(context).pop(); // back to academy
              },
              child: const Text(
                'חזרה לאקדמיה',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return YoutubePlayerScaffold(
      controller: _ytController,
      builder: (context, player) => Stack(
        children: [
          Scaffold(
        backgroundColor: const Color(0xFF0F0F1A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F0F1A),
          foregroundColor: Colors.white,
          title: Text(
            widget.course.title,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold),
          ),
          elevation: 0,
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── YouTube player ────────────────────────────────────────
              player,

              // ── Watch progress bar ────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'צפית ב-${_watchedPercent.toInt()}% מהסרטון',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                        if (_canTakeQuiz && !_passed)
                          const Text(
                            '✅ החידון פתוח',
                            style: TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (_watchedPercent / 100).clamp(0.0, 1.0),
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.1),
                        valueColor: const AlwaysStoppedAnimation(
                            Color(0xFF6366F1)),
                        minHeight: 5,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Course metadata ───────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.course.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1)
                                .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            widget.course.category,
                            style: const TextStyle(
                              color: Color(0xFF6366F1),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (widget.course.duration.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Icon(Icons.schedule,
                              size: 14,
                              color: Colors.white.withValues(alpha: 0.5)),
                          const SizedBox(width: 4),
                          Text(
                            widget.course.duration,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (widget.course.description.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        widget.course.description,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 14,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Certified banner (already passed) ─────────────────────
              if (_passed && !_completing)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFF10B981)
                              .withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified,
                            color: Color(0xFF10B981), size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'קורס הושלם בהצלחה!',
                                style: TextStyle(
                                  color: Color(0xFF10B981),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'הסמכת ${widget.course.category} + ${widget.course.xpReward} XP',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Quiz section ──────────────────────────────────────────
              if (widget.course.quizQuestions.isNotEmpty && !_passed)
                _buildQuizSection(),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),      // ← closes Scaffold

      // ── Celebration overlay ───────────────────────────────────────────────
      if (_showCelebration) _buildCelebrationOverlay(),
    ],         // ← closes Stack children
  ),           // ← closes Stack
);             // ← closes YoutubePlayerScaffold builder
  }

  Widget _buildCelebrationOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.4, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, scale, _) => Transform.scale(
              scale: scale,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Giant trophy emoji
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutBack,
                    builder: (_, v, __) => Opacity(
                      opacity: v.clamp(0.0, 1.0),
                      child: const Text('🎓',
                          style: TextStyle(fontSize: 88)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'קורס הושלם!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Animated XP badge
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => Opacity(
                      opacity: v.clamp(0.0, 1.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF6366F1),
                              Color(0xFFA855F7),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6366F1)
                                  .withValues(alpha: 0.5),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Text(
                          '+${widget.course.xpReward} XP',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Quiz widget ─────────────────────────────────────────────────────────────

  Widget _buildQuizSection() {
    // Locked — not enough video watched
    if (!_canTakeQuiz) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline,
                  color: Colors.white.withValues(alpha: 0.45), size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'צפה ב-80% מהסרטון כדי לפתוח את החידון',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // CTA to open quiz
    if (!_showQuiz) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            minimumSize: const Size(double.infinity, 52),
          ),
          icon: const Icon(Icons.quiz, color: Colors.white),
          label: const Text(
            'גש לחידון וקבל הסמכה',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          onPressed: () => setState(() => _showQuiz = true),
        ),
      );
    }

    // Quiz open
    final questions = widget.course.quizQuestions;
    final allAnswered = _answers.every((a) => a != null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Row(
            children: [
              Text('📝', style: TextStyle(fontSize: 22)),
              SizedBox(width: 8),
              Text(
                'חידון',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'ענה על ${questions.length} שאלות — נדרש 70% להסמכה',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),

          // Questions
          ...List.generate(questions.length, (qi) {
            final q          = questions[qi];
            final qText      = q['question'] as String? ?? '';
            final options    = List<String>.from(q['options'] as List? ?? []);
            final correctIdx = (q['correctIndex'] as num?)?.toInt() ?? -1;

            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${qi + 1}. $qText',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...List.generate(options.length, (oi) {
                    final isSelected = _answers[qi] == oi;
                    final isCorrect  = _quizSubmitted && oi == correctIdx;
                    final isWrong    =
                        _quizSubmitted && isSelected && oi != correctIdx;

                    Color borderColor =
                        Colors.white.withValues(alpha: 0.12);
                    Color bgColor =
                        Colors.white.withValues(alpha: 0.04);

                    if (isCorrect) {
                      borderColor = const Color(0xFF10B981);
                      bgColor = const Color(0xFF10B981)
                          .withValues(alpha: 0.12);
                    } else if (isWrong) {
                      borderColor = const Color(0xFFEF4444);
                      bgColor = const Color(0xFFEF4444)
                          .withValues(alpha: 0.08);
                    } else if (isSelected) {
                      borderColor = const Color(0xFF6366F1);
                      bgColor = const Color(0xFF6366F1)
                          .withValues(alpha: 0.1);
                    }

                    return GestureDetector(
                      onTap: _quizSubmitted
                          ? null
                          : () =>
                              setState(() => _answers[qi] = oi),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                options[oi],
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14),
                              ),
                            ),
                            if (isCorrect)
                              const Icon(Icons.check_circle,
                                  color: Color(0xFF10B981), size: 18),
                            if (isWrong)
                              const Icon(Icons.cancel,
                                  color: Color(0xFFEF4444), size: 18),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          }),

          // ── Result or submit ──────────────────────────────────────────
          if (_quizSubmitted)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: (_passed
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444))
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (_passed
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEF4444))
                      .withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    _passed ? '🎉 עברת!' : '😔 לא עברת',
                    style: TextStyle(
                      color: _passed
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEF4444),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (!_passed)
                    TextButton(
                      onPressed: () => setState(() {
                        _quizSubmitted = false;
                        _answers = List.filled(
                            widget.course.quizQuestions.length, null);
                      }),
                      child: const Text(
                        'נסה שוב',
                        style: TextStyle(color: Color(0xFF6366F1)),
                      ),
                    ),
                ],
              ),
            )
          else
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                disabledBackgroundColor:
                    const Color(0xFF6366F1).withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size(double.infinity, 52),
              ),
              onPressed: allAnswered ? _submitQuiz : null,
              child: Text(
                allAnswered
                    ? 'שלח תשובות וקבל הסמכה'
                    : 'ענה על כל השאלות',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
