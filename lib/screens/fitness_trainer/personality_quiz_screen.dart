// Fitness Trainer CSM — 5-question personality quiz.
// Launched from FitnessTrainerBookingBlock's "AI Match Quiz CTA" section.
// Auto-advances 300ms after each selection (HapticFeedback.lightImpact each).
// Submits to Cloud Function `recommendTrainersByGoals` (Gemini 2.5 Flash Lite).
// Falls back to 87% + 4 generic reasons if the CF is unavailable — so the
// quiz always returns a working result even before the CF is deployed.
//
// Design tokens match the provider settings block (Orange / Gold / Green / Purple).
// Hebrew RTL throughout.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Shape returned from the quiz: `{matchScore: int, reasons: List[String],
/// answers: Map[String,String]}`. The booking block stores this so the
/// "Personality Match Result" section can render the score on return.
class QuizMatchResult {
  final int matchScore;
  final List<String> reasons;
  final Map<String, String> answers;
  final bool isFallback;

  const QuizMatchResult({
    required this.matchScore,
    required this.reasons,
    required this.answers,
    this.isFallback = false,
  });
}

class PersonalityQuizScreen extends StatefulWidget {
  /// Trainer id evaluated against — optional. If omitted, the CF scores
  /// against the category's "ideal fit" rather than a specific trainer.
  final String? trainerId;
  final String? trainerName;

  const PersonalityQuizScreen({
    super.key,
    this.trainerId,
    this.trainerName,
  });

  @override
  State<PersonalityQuizScreen> createState() => _PersonalityQuizScreenState();
}

class _PersonalityQuizScreenState extends State<PersonalityQuizScreen>
    with SingleTickerProviderStateMixin {
  int _currentQuestion = 0;
  final Map<String, String> _answers = {};
  bool _isLoading = false;
  QuizMatchResult? _result;

  // Green glow animation on the result number
  late AnimationController _glowCtrl;

  static const List<_QuizQuestion> _questions = [
    _QuizQuestion(
      icon: '🎯',
      title: 'מה המטרה שלך?',
      keyName: 'goal',
      options: [
        _QuizOption('build_muscle', 'לבנות שריר', '💪'),
        _QuizOption('lose_weight', 'להוריד במשקל', '🔥'),
        _QuizOption('endurance', 'לשפר סיבולת', '🏃'),
        _QuizOption('flexibility', 'גמישות והרגעה', '🧘'),
        _QuizOption('event_prep', 'הכנה לאירוע', '🏆'),
      ],
    ),
    _QuizQuestion(
      icon: '📊',
      title: 'רמת ניסיון?',
      keyName: 'experience',
      options: [
        _QuizOption('beginner', 'מתחיל', '🌱'),
        _QuizOption('intermediate', 'בינוני', '🌳'),
        _QuizOption('advanced', 'מתקדם', '🏔️'),
      ],
    ),
    _QuizQuestion(
      icon: '📅',
      title: 'כמה ימים בשבוע?',
      keyName: 'frequency',
      options: [
        _QuizOption('1-2', '1-2 ימים', '☝️'),
        _QuizOption('3-4', '3-4 ימים', '✊'),
        _QuizOption('5+', '5+ ימים', '🙌'),
      ],
    ),
    _QuizQuestion(
      icon: '📍',
      title: 'איפה תעדיפי להתאמן?',
      keyName: 'location',
      options: [
        _QuizOption('home', 'בבית', '🏠'),
        _QuizOption('park', 'בפארק', '🌳'),
        _QuizOption('gym', 'חדר כושר', '🏋️'),
      ],
    ),
    _QuizQuestion(
      icon: '🎭',
      title: 'איזה סגנון מאמן?',
      keyName: 'style',
      options: [
        _QuizOption('motivator', 'מוטיבטור', '🔥'),
        _QuizOption('calm', 'רגוע', '🧘'),
        _QuizOption('data', 'דאטה', '📊'),
        _QuizOption('friendly', 'חברותי', '💝'),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFFAF5FF),
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _result != null
                ? _buildResultView()
                : _isLoading
                    ? _buildLoadingView()
                    : _buildQuizView(),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // QUIZ VIEW
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildQuizView() {
    final question = _questions[_currentQuestion];
    final progress = (_currentQuestion + 1) / _questions.length;

    return Column(
      key: const ValueKey('quiz'),
      children: [
        // Header with close + progress
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded,
                    color: Color(0xFF6B7280)),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '${_currentQuestion + 1} / ${_questions.length}',
                      style: const TextStyle(
                        color: Color(0xFF8B5CF6),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: progress),
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        builder: (ctx, v, _) => LinearProgressIndicator(
                          value: v,
                          minHeight: 6,
                          backgroundColor: const Color(0xFFE5E7EB),
                          valueColor: const AlwaysStoppedAnimation(
                              Color(0xFF8B5CF6)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),

        // Question body
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            switchInCurve: Curves.easeOut,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.08, 0),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: Padding(
              key: ValueKey(question.keyName),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 32),
                    Text(
                      question.icon,
                      style: const TextStyle(fontSize: 56),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      question.title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1F2937),
                        height: 1.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    ...question.options.map((opt) => _buildOption(question, opt)),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOption(_QuizQuestion question, _QuizOption option) {
    final isSelected = _answers[question.keyName] == option.value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : () => _selectOption(question, option),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF8B5CF6) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF8B5CF6)
                    : const Color(0xFFE5E7EB),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color:
                            const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Row(
              children: [
                Text(option.emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    option.label,
                    style: TextStyle(
                      fontSize: 16,
                      color: isSelected ? Colors.white : const Color(0xFF1F2937),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check_circle_rounded,
                      color: Colors.white, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _selectOption(_QuizQuestion question, _QuizOption option) {
    HapticFeedback.lightImpact();
    setState(() {
      _answers[question.keyName] = option.value;
    });

    // Auto-advance after 300ms
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      if (_currentQuestion < _questions.length - 1) {
        setState(() => _currentQuestion++);
      } else {
        _submitQuiz();
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // LOADING VIEW
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildLoadingView() {
    return Center(
      key: const ValueKey('loading'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const CircularProgressIndicator(
              color: Color(0xFF8B5CF6),
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '🤖 מנתח את התשובות שלך...',
            style: TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Gemini מחשב את אחוז ההתאמה',
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // RESULT VIEW (green glow on the 94%)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildResultView() {
    final score = _result!.matchScore;
    final reasons = _result!.reasons;
    return SingleChildScrollView(
      key: const ValueKey('result'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          const Text('🎯',
              style: TextStyle(fontSize: 64), textAlign: TextAlign.center),
          const SizedBox(height: 14),
          const Text(
            'התאמה של',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          // Glowing green score
          AnimatedBuilder(
            animation: _glowCtrl,
            builder: (ctx, _) {
              final t = _glowCtrl.value; // 0..1
              final blur = 18 + t * 22;
              final spread = 2 + t * 6;
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 6),
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981)
                          .withValues(alpha: 0.35 + t * 0.25),
                      blurRadius: blur,
                      spreadRadius: spread,
                    ),
                  ],
                ),
                child: Text(
                  '$score%',
                  style: const TextStyle(
                    fontSize: 80,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF10B981),
                    height: 1,
                  ),
                  textAlign: TextAlign.center,
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            widget.trainerName == null
                ? 'עם המאמן הזה!'
                : 'עם ${widget.trainerName}!',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1F2937),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // 4 reason cards
          ...reasons.take(4).map(
                (r) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          color: Color(0xFF10B981), size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          r,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF1F2937),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

          if (_result!.isFallback) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFDBA74).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Text('ℹ️', style: TextStyle(fontSize: 16)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ציון תקציר — הציון המלא יתעדכן לאחר חיבור ה-AI',
                      style: TextStyle(
                        color: Color(0xFF92400E),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B35), Color(0xFFF59E0B)],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF6B35).withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                Navigator.pop(context, _result);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'חזרי לפרופיל והזמיני ←',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() {
                _result = null;
                _answers.clear();
                _currentQuestion = 0;
              });
            },
            child: const Text(
              'ענו שוב',
              style: TextStyle(
                color: Color(0xFF8B5CF6),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CF SUBMIT (with fallback)
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _submitQuiz() async {
    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(
        'recommendTrainersByGoals',
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 15),
        ),
      );
      final payload = <String, dynamic>{
        ..._answers,
        if (widget.trainerId != null) 'trainerId': widget.trainerId,
      };
      final res = await callable.call(payload);
      final data = Map<String, dynamic>.from(res.data as Map);
      final score = (data['matchScore'] as num?)?.toInt() ?? 87;
      final reasons = ((data['reasons'] as List?) ?? const [])
          .map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _result = QuizMatchResult(
          matchScore: score.clamp(50, 100),
          reasons: reasons.isEmpty ? _fallbackReasons() : reasons,
          answers: Map<String, String>.from(_answers),
          isFallback: data['fallback'] == true,
        );
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _result = QuizMatchResult(
          matchScore: 87, // spec's fallback
          reasons: _fallbackReasons(),
          answers: Map<String, String>.from(_answers),
          isFallback: true,
        );
        _isLoading = false;
      });
    }
  }

  List<String> _fallbackReasons() {
    final goal = _answers['goal'];
    final loc = _answers['location'];
    final styleKey = _answers['style'];
    final goalReasons = {
      'build_muscle': '💪 מתמחה בבניית שריר',
      'lose_weight': '🔥 נותן שירות להרזיה',
      'endurance': '🏃 מאמן סיבולת',
      'flexibility': '🧘 מתמחה בגמישות',
      'event_prep': '🏆 הכנה לאירועים ספורטיביים',
    };
    final locReasons = {
      'home': '🏠 מגיע עד הבית',
      'park': '🌳 אימונים בפארק',
      'gym': '🏋️ אימוני חדר כושר',
    };
    final styleReasons = {
      'motivator': '🔥 סגנון מוטיבטור אנרגטי',
      'calm': '🧘 סגנון רגוע וסבלני',
      'data': '📊 מבוסס דאטה ומדידות',
      'friendly': '💝 חברותי ונגיש',
    };
    return [
      goalReasons[goal] ?? '🎯 מתאים למטרות שלך',
      locReasons[loc] ?? '📍 באזור שלך',
      styleReasons[styleKey] ?? '⭐ סגנון תואם',
      '✓ מאמן מאומת עם דירוגים גבוהים',
    ];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// INTERNAL QUESTION MODEL
// ═══════════════════════════════════════════════════════════════════════════

class _QuizQuestion {
  final String icon;
  final String title;
  final String keyName;
  final List<_QuizOption> options;

  const _QuizQuestion({
    required this.icon,
    required this.title,
    required this.keyName,
    required this.options,
  });
}

class _QuizOption {
  final String value;
  final String label;
  final String emoji;

  const _QuizOption(this.value, this.label, this.emoji);
}
