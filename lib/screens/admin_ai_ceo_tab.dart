/// AnySkill — אילון (Ilon) Strategic Dashboard — v12.4 Genius
///
/// Two-column layout (wide) / stacked (narrow):
///   LEFT  — strategic briefing: headline, 6 KPI cards, morning brief,
///           recommendations, red flags, opportunities, category health,
///           top performers.
///   RIGHT — interactive chat with the agent. Uses the briefing snapshot as
///           context and can invoke read-only Firestore tools on demand.
///
/// Powered by: Claude Opus 4.6 (strategy) + Claude Sonnet 4.6 (chat) with
/// Gemini fallback. Full admin tab — read-only; no destructive actions.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
// `intl` exports its own TextDirection enum which shadows dart:ui's.
// Hide it so `TextDirection.rtl` resolves to dart:ui and keeps its `rtl` getter.
import 'package:intl/intl.dart' hide TextDirection;
import 'package:url_launcher/url_launcher.dart';
import '../services/ai_ceo_service.dart';

// ── Dark Premium Palette ─────────────────────────────────────────────────────
const _kBgDark      = Color(0xFF0F0F1A);
const _kCardDark    = Color(0xFF1A1A2E);
const _kCardDarker  = Color(0xFF12121F);
const _kIndigo      = Color(0xFF6366F1);
const _kIndigoLight = Color(0xFF818CF8);
const _kPurple      = Color(0xFF8B5CF6);
const _kAmber       = Color(0xFFF59E0B);
const _kRed         = Color(0xFFEF4444);
const _kGreen       = Color(0xFF10B981);
const _kBlue        = Color(0xFF3B82F6);
const _kTextPrimary = Color(0xFFF1F5F9);
const _kTextMuted   = Color(0xFF94A3B8);
const _kBorderFaint = Color(0xFF2A2A40);

class AdminAiCeoTab extends StatefulWidget {
  const AdminAiCeoTab({super.key});

  @override
  State<AdminAiCeoTab> createState() => _AdminAiCeoTabState();
}

class _AdminAiCeoTabState extends State<AdminAiCeoTab> {
  CeoInsight? _insight;
  bool _loading = false;
  String? _error;

  // Chat state
  final List<CeoChatMessage> _chat = [];
  final _chatCtrl = TextEditingController();
  final _chatScroll = ScrollController();
  bool _asking = false;
  // v12.5 — running session cost (briefing + all chat turns)
  double _sessionCostUsd = 0;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    _chatCtrl.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
      _chat.clear();
      _sessionCostUsd = 0; // new briefing = new session
    });
    try {
      final insight = await AiCeoService.generateInsight();
      if (!mounted) return;
      setState(() {
        _insight = insight;
        _loading = false;
        _sessionCostUsd += insight.costUsd;
        if (insight.isError) _error = insight.morningBrief;
      });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _ask() async {
    final q = _chatCtrl.text.trim();
    if (q.isEmpty || _asking || _insight == null) return;

    final userMsg = CeoChatMessage(
      role: 'user',
      content: q,
      timestamp: DateTime.now(),
    );
    setState(() {
      _chat.add(userMsg);
      _chatCtrl.clear();
      _asking = true;
    });
    _scrollChatToBottom();

    try {
      // Only include prior turns in history — NOT the current question
      // (the server re-appends it).
      final history = List<CeoChatMessage>.from(_chat)..removeLast();
      final reply = await AiCeoService.askAgent(
        question: q,
        history: history,
        metricsSnapshot: _insight!.metricsSnapshot,
      );
      if (!mounted) return;
      setState(() {
        _chat.add(reply);
        _sessionCostUsd += reply.costUsd;
        _asking = false;
      });
      _scrollChatToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chat.add(CeoChatMessage(
          role: 'assistant',
          content: 'שגיאה: $e',
          timestamp: DateTime.now(),
        ));
        _asking = false;
      });
    }
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        if (_chatScroll.hasClients &&
            _chatScroll.position.hasContentDimensions) {
          _chatScroll.animateTo(
            _chatScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      } catch (_) {/* ignore */}
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _kBgDark,
        body: _loading ? _buildLoading() : _buildContent(),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kIndigo, _kPurple],
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: _kIndigo.withValues(alpha: 0.45),
                  blurRadius: 40,
                  spreadRadius: 6,
                ),
              ],
            ),
            child: const Icon(Icons.psychology_rounded,
                color: Colors.white, size: 48),
          ),
          const SizedBox(height: 28),
          const Text(
            'אילון חושב...',
            style: TextStyle(
              color: _kTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'אוסף 40+ מדדים ומעביר ל-Claude Opus לניתוח אסטרטגי',
            style: TextStyle(
              color: _kTextMuted.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: 200,
            child: LinearProgressIndicator(
              backgroundColor: _kCardDark,
              color: _kIndigo,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_error != null && _insight == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: _kRed, size: 48),
              const SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _kTextMuted, fontSize: 14)),
              const SizedBox(height: 16),
              _primaryButton('נסה שוב', Icons.refresh_rounded, _generate),
            ],
          ),
        ),
      );
    }

    final insight = _insight;
    if (insight == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final isWide = constraints.maxWidth >= 1100;
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 7, child: _buildBriefingPane(insight)),
              Container(width: 1, color: _kBorderFaint),
              Expanded(flex: 5, child: _buildChatPane()),
            ],
          );
        }
        // Narrow — stacked, chat below briefing
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildBriefingPane(insight),
            Container(height: 1, color: _kBorderFaint),
            SizedBox(
              height: 600,
              child: _buildChatPane(),
            ),
          ],
        );
      },
    );
  }

  // ── LEFT PANE: Strategic briefing ──────────────────────────────────────

  Widget _buildBriefingPane(CeoInsight insight) {
    return RefreshIndicator(
      color: _kIndigo,
      backgroundColor: _kCardDark,
      onRefresh: _generate,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          _buildHeader(insight),
          const SizedBox(height: 14),
          _buildQuickLinks(),
          const SizedBox(height: 18),

          // ── v12.3 GENIUS: Smart Alerts ribbon (top priority) ─────────
          if (insight.smartAlerts.isNotEmpty) ...[
            _buildSmartAlertsRibbon(insight.smartAlerts),
            const SizedBox(height: 16),
          ],

          // ── v12.3 GENIUS: Launch Readiness gauge ─────────────────────
          if (insight.launchReadiness != null) ...[
            _buildLaunchReadinessCard(insight.launchReadiness!),
            const SizedBox(height: 16),
          ],

          // Headline banner
          if (insight.headline.isNotEmpty) ...[
            _buildHeadlineBanner(insight.headline),
            const SizedBox(height: 16),
          ],

          // Key Metrics Grid
          if (insight.keyMetrics.isNotEmpty) ...[
            _sectionLabel('מדדים מרכזיים', Icons.dashboard_rounded, _kIndigoLight),
            const SizedBox(height: 10),
            _buildMetricsGrid(insight.keyMetrics),
            const SizedBox(height: 20),
          ],

          // ── v12.3 GENIUS: Predictions ────────────────────────────────
          if (insight.predictions.isNotEmpty) ...[
            _buildSection(
              icon: Icons.timeline_rounded,
              iconColor: _kIndigoLight,
              title: 'תחזיות 30 ימים',
              subtitle: insight.historyDays < 7
                  ? 'נתונים היסטוריים מצטברים (${insight.historyDays}/7)'
                  : 'על בסיס ${insight.historyDays} ימי snapshots',
              child: Column(
                children: insight.predictions
                    .map(_buildPredictionCard)
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── v12.3 GENIUS: Anomalies ──────────────────────────────────
          if (insight.anomalies.isNotEmpty) ...[
            _buildSection(
              icon: Icons.science_rounded,
              iconColor: _kRed,
              title: 'זיהוי חריגות',
              subtitle: '${insight.anomalies.length} חריגות z-score ≥ 2',
              child: Column(
                children: insight.anomalies
                    .map(_buildAnomalyCard)
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── v12.3 GENIUS: Action Items ───────────────────────────────
          if (insight.actionItems.isNotEmpty) ...[
            _buildSection(
              icon: Icons.flash_on_rounded,
              iconColor: _kAmber,
              title: 'פעולות עכשיו',
              subtitle: '${insight.actionItems.length} פריטים לטיפול',
              child: Column(
                children: insight.actionItems
                    .map(_buildActionItemCard)
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Morning Brief
          _buildSection(
            icon: Icons.wb_sunny_rounded,
            iconColor: _kAmber,
            title: 'סיכום בוקר',
            subtitle: DateFormat('dd/MM/yyyy HH:mm').format(insight.generatedAt),
            actionIcon: Icons.copy_rounded,
            onAction: () => _copyToClipboard(insight.morningBrief),
            child: SelectableText(
              insight.morningBrief,
              style: const TextStyle(
                color: _kTextPrimary,
                fontSize: 14,
                height: 1.75,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Recommendations
          if (insight.recommendations.isNotEmpty) ...[
            _buildSection(
              icon: Icons.lightbulb_rounded,
              iconColor: _kGreen,
              title: 'המלצות אסטרטגיות',
              subtitle: '${insight.recommendations.length} פעולות',
              child: Column(
                children: insight.recommendations
                    .map((r) => _buildRecommendationCard(r))
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Red Flags
          if (insight.redFlags.isNotEmpty) ...[
            _buildSection(
              icon: Icons.warning_amber_rounded,
              iconColor: _kRed,
              title: 'נורות אדומות',
              subtitle: '${insight.redFlags.length} התראות',
              child: Column(
                children: insight.redFlags
                    .map((f) => _buildRedFlagCard(f))
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Opportunities
          if (insight.opportunities.isNotEmpty) ...[
            _buildSection(
              icon: Icons.rocket_launch_rounded,
              iconColor: _kPurple,
              title: 'הזדמנויות צמיחה',
              subtitle: '${insight.opportunities.length} רעיונות',
              child: Column(
                children: insight.opportunities
                    .map((o) => _buildOpportunityCard(o))
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Category Health
          if (insight.categoryHealth.isNotEmpty) ...[
            _buildSection(
              icon: Icons.category_rounded,
              iconColor: _kBlue,
              title: 'בריאות קטגוריות',
              subtitle: 'מצב כל תחום',
              child: Column(
                children: insight.categoryHealth
                    .map((c) => _buildCategoryRow(c))
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Top Performers
          if (insight.topPerformers.isNotEmpty) ...[
            _buildSection(
              icon: Icons.emoji_events_rounded,
              iconColor: _kAmber,
              title: 'כוכבי הפלטפורמה',
              subtitle: '${insight.topPerformers.length} מובילים',
              child: Column(
                children: insight.topPerformers
                    .map((p) => _buildPerformerCard(p))
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── v12.3 GENIUS: Churn Risks ─────────────────────────────
          if (insight.churnRisks.isNotEmpty) ...[
            _buildSection(
              icon: Icons.trending_down_rounded,
              iconColor: _kRed,
              title: 'סיכוני נטישה',
              subtitle: '${insight.churnRisks.length} ספקים בסיכון',
              child: Column(
                children: insight.churnRisks
                    .map(_buildChurnRiskCard)
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── v12.3 GENIUS: Competitive Benchmarks ─────────────────
          if (insight.benchmarks.isNotEmpty) ...[
            _buildSection(
              icon: Icons.leaderboard_rounded,
              iconColor: _kBlue,
              title: 'השוואה מול מתחרים',
              subtitle: 'Fiverr / Upwork / TaskRabbit / Thumbtack',
              child: Column(
                children: insight.benchmarks
                    .map(_buildBenchmarkCard)
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── v12.3 GENIUS: Cohort Analysis ────────────────────────
          if (insight.cohorts.isNotEmpty) ...[
            _buildSection(
              icon: Icons.group_rounded,
              iconColor: _kPurple,
              title: 'ניתוח קוהורטים',
              subtitle: '${insight.cohorts.length} חודשים אחרונים',
              child: Column(
                children: insight.cohorts
                    .map(_buildCohortCard)
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── v12.5: Memory + Cost footer ───────────────────────────
          _buildMemoryAndCostFooter(insight),
          const SizedBox(height: 10),

          // Footer meta
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kCardDarker,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBorderFaint),
            ),
            child: Row(
              children: [
                const Icon(Icons.memory_rounded, color: _kTextMuted, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    insight.usedModel.isEmpty
                        ? 'נוצר ב-${DateFormat('HH:mm').format(insight.generatedAt)}'
                        : 'מודל: ${insight.usedModel}  •  ${DateFormat('HH:mm').format(insight.generatedAt)}',
                    style: const TextStyle(
                      color: _kTextMuted,
                      fontSize: 11,
                    ),
                  ),
                ),
                _primaryButton('רענן', Icons.refresh_rounded, _generate),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── RIGHT PANE: Interactive chat ────────────────────────────────────────

  Widget _buildChatPane() {
    return Container(
      color: _kCardDarker,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kCardDark,
              border: Border(bottom: BorderSide(color: _kBorderFaint)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_kIndigo, _kPurple]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.chat_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'שאל את אילון',
                        style: TextStyle(
                          color: _kTextPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _sessionCostUsd > 0
                            ? 'עלות session: \$${_sessionCostUsd.toStringAsFixed(4)}'
                            : 'יכול לקרוא collections ולחקור נתונים',
                        style: const TextStyle(color: _kTextMuted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                if (_chat.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_rounded,
                        color: _kTextMuted, size: 18),
                    tooltip: 'נקה שיחה',
                    onPressed: () => setState(() => _chat.clear()),
                  ),
              ],
            ),
          ),

          // Messages
          Expanded(
            child: _chat.isEmpty
                ? _buildChatEmptyState()
                : ListView.builder(
                    controller: _chatScroll,
                    padding: const EdgeInsets.all(14),
                    itemCount: _chat.length + (_asking ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == _chat.length) return _buildTypingIndicator();
                      return _buildChatBubble(_chat[i]);
                    },
                  ),
          ),

          // Composer
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kCardDark,
              border: Border(top: BorderSide(color: _kBorderFaint)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _kBgDark,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _kBorderFaint),
                    ),
                    child: TextField(
                      controller: _chatCtrl,
                      enabled: !_asking && _insight != null,
                      style: const TextStyle(color: _kTextPrimary, fontSize: 13),
                      maxLines: 4,
                      minLines: 1,
                      textDirection: TextDirection.rtl,
                      decoration: const InputDecoration(
                        hintText: 'שאל שאלה... (למשל: "מי 3 הספקים הכי פעילים השבוע?")',
                        hintStyle: TextStyle(color: _kTextMuted, fontSize: 12),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onSubmitted: (_) => _ask(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: _asking ? _kCardDarker : _kIndigo,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _asking ? null : _ask,
                    child: Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      child: _asking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatEmptyState() {
    final suggestions = [
      'מי 5 הספקים הכי רווחיים השבוע?',
      'למה GMV ירד לעומת השבוע שעבר?',
      'אילו קטגוריות צומחות הכי מהר?',
      'כמה משתמשים ממתינים לאימות ומה הזמן הממוצע?',
      'תראה לי את כל המחלוקות הפעילות',
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 20),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _kIndigo.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.forum_rounded, color: _kIndigoLight, size: 32),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'שאל אותי כל דבר על הפלטפורמה',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _kTextPrimary,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'יש לי גישה לכל ה-collections ויכול לחקור נתונים בזמן אמת',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _kTextMuted.withValues(alpha: 0.8),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'הצעות לשאלות:',
          style: TextStyle(
            color: _kTextMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        ...suggestions.map(_buildSuggestionChip),
      ],
    );
  }

  Widget _buildSuggestionChip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          _chatCtrl.text = text;
          _ask();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kCardDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorderFaint),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  color: _kIndigoLight, size: 14),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(color: _kTextPrimary, fontSize: 12),
                ),
              ),
              const Icon(Icons.arrow_forward_rounded,
                  color: _kTextMuted, size: 14),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatBubble(CeoChatMessage msg) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: isUser
              ? _kIndigo.withValues(alpha: 0.18)
              : _kCardDark,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
          border: Border.all(
            color: isUser ? _kIndigo.withValues(alpha: 0.3) : _kBorderFaint,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              msg.content,
              style: const TextStyle(
                color: _kTextPrimary,
                fontSize: 13,
                height: 1.55,
              ),
            ),
            if (msg.toolsUsed.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: msg.toolsUsed.map((t) {
                  final name = t['name'] as String? ?? 'tool';
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _kPurple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _kPurple.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.build_rounded,
                            color: _kPurple, size: 9),
                        const SizedBox(width: 4),
                        Text(
                          name,
                          style: const TextStyle(
                            color: _kPurple,
                            fontSize: 9,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
            // v12.5 — cost + model footer on assistant turns
            if (!isUser && msg.costUsd > 0) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.payments_rounded,
                      color: _kGreen, size: 10),
                  const SizedBox(width: 3),
                  Text(
                    '\$${msg.costUsd.toStringAsFixed(5)}',
                    style: const TextStyle(
                      color: _kGreen,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (msg.usedModel.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: msg.usedModel.startsWith('claude')
                            ? _kIndigo.withValues(alpha: 0.15)
                            : _kAmber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        msg.usedModel,
                        style: TextStyle(
                          color: msg.usedModel.startsWith('claude')
                              ? _kIndigoLight
                              : _kAmber,
                          fontSize: 8,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                  if (msg.memoryLearnedFacts > 0) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'אילון זוכר ${msg.memoryLearnedFacts} תובנות מ-${msg.memorySessionCount} פגישות',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome_rounded,
                              color: _kPurple, size: 9),
                          const SizedBox(width: 2),
                          Text(
                            '${msg.memoryLearnedFacts}',
                            style: const TextStyle(
                              color: _kPurple,
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _kCardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorderFaint),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _kIndigoLight,
              ),
            ),
            SizedBox(width: 10),
            Text(
              'חושב וחוקר...',
              style: TextStyle(color: _kTextMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header / banners ──────────────────────────────────────────────────

  Widget _buildHeader(CeoInsight insight) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _kIndigo.withValues(alpha: 0.25),
            blurRadius: 28,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'אילון  •  GENIUS',
                  style: TextStyle(
                    color: _kIndigoLight,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'הסוכן האסטרטגי שלך',
                  style: TextStyle(
                    color: _kTextPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'עודכן ${DateFormat('HH:mm').format(insight.generatedAt)}  •  40+ מדדים',
                  style: const TextStyle(color: _kTextMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_kIndigo, _kPurple]),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: _kPurple.withValues(alpha: 0.45),
                  blurRadius: 18,
                ),
              ],
            ),
            child: const Icon(Icons.psychology_rounded,
                color: Colors.white, size: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildHeadlineBanner(String headline) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _kIndigo.withValues(alpha: 0.12),
            _kPurple.withValues(alpha: 0.12),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kIndigo.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.campaign_rounded, color: _kIndigoLight, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              headline,
              style: const TextStyle(
                color: _kTextPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickLinks() {
    return Row(
      children: [
        Expanded(
          child: _quickActionChip(
            icon: Icons.bug_report_rounded,
            label: 'Crashlytics',
            onTap: () => _openUrl('https://console.firebase.google.com/project/anyskill-6fdf3/crashlytics'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _quickActionChip(
            icon: Icons.analytics_rounded,
            label: 'Firebase',
            onTap: () => _openUrl('https://console.firebase.google.com/project/anyskill-6fdf3/overview'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _quickActionChip(
            icon: Icons.storage_rounded,
            label: 'Firestore',
            onTap: () => _openUrl('https://console.firebase.google.com/project/anyskill-6fdf3/firestore'),
          ),
        ),
      ],
    );
  }

  // ── Metrics grid ──────────────────────────────────────────────────────

  Widget _buildMetricsGrid(List<CeoKeyMetric> metrics) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final cols = constraints.maxWidth > 680 ? 3 : 2;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: cols,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.9,
          children: metrics.map(_buildMetricCard).toList(),
        );
      },
    );
  }

  Widget _buildMetricCard(CeoKeyMetric m) {
    final isUp = m.trend == 'up';
    final isDown = m.trend == 'down';
    final trendColor = isUp ? _kGreen : (isDown ? _kRed : _kTextMuted);
    final trendIcon = isUp
        ? Icons.trending_up_rounded
        : (isDown ? Icons.trending_down_rounded : Icons.trending_flat_rounded);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderFaint),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            m.label,
            style: const TextStyle(
              color: _kTextMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            m.value,
            style: const TextStyle(
              color: _kTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Row(
            children: [
              Icon(trendIcon, color: trendColor, size: 14),
              const SizedBox(width: 4),
              Text(
                m.deltaPct == 0 ? 'ללא שינוי' : '${m.deltaPct > 0 ? '+' : ''}${m.deltaPct}%',
                style: TextStyle(
                  color: trendColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Section container ──────────────────────────────────────────────────

  Widget _sectionLabel(String label, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildSection({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget child,
    IconData? actionIcon,
    VoidCallback? onAction,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kCardDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: iconColor.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                          color: _kTextPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        )),
                    Text(subtitle,
                        style: const TextStyle(
                          color: _kTextMuted,
                          fontSize: 11,
                        )),
                  ],
                ),
              ),
              if (actionIcon != null && onAction != null)
                IconButton(
                  icon: Icon(actionIcon, color: _kTextMuted, size: 16),
                  tooltip: 'העתק',
                  onPressed: onAction,
                ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  // ── Cards ──────────────────────────────────────────────────────────────

  Widget _buildRecommendationCard(CeoRecommendation r) {
    final (priorityColor, priorityLabel) = switch (r.priority) {
      'high'   => (_kRed, 'עדיפות גבוהה'),
      'medium' => (_kAmber, 'עדיפות רגילה'),
      _        => (_kGreen, 'עדיפות נמוכה'),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kGreen.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kGreen.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.title,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: priorityColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  priorityLabel,
                  style: TextStyle(
                    color: priorityColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            r.body,
            style: const TextStyle(
              color: _kTextPrimary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          if (r.impact.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.arrow_forward_rounded,
                    color: _kGreen, size: 12),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    r.impact,
                    style: const TextStyle(
                      color: _kGreen,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRedFlagCard(CeoRedFlag f) {
    final (color, icon) = switch (f.severity) {
      'critical' => (_kRed, Icons.dangerous_rounded),
      'warning'  => (_kAmber, Icons.warning_amber_rounded),
      _          => (_kBlue, Icons.info_outline_rounded),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  f.title,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            f.body,
            style: const TextStyle(
              color: _kTextPrimary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          if (f.suggestedAction.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '💡 ${f.suggestedAction}',
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOpportunityCard(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kPurple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kPurple.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.rocket_launch_rounded, color: _kPurple, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: _kTextPrimary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryRow(CeoCategoryHealth c) {
    final (color, emoji) = switch (c.status) {
      'growing'   => (_kGreen, '📈'),
      'healthy'   => (_kGreen, '✅'),
      'declining' => (_kAmber, '⚠️'),
      _           => (_kRed, '⛔'),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCardDarker,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.category,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  c.note,
                  style: TextStyle(
                    color: _kTextMuted.withValues(alpha: 0.9),
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              c.status,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── v12.3 GENIUS UI builders ──────────────────────────────────────────

  /// Smart alerts ribbon — horizontally scrollable severity-ordered chips.
  Widget _buildSmartAlertsRibbon(List<CeoSmartAlert> alerts) {
    // Only show top 5 in the ribbon; the rest live inside red flags below.
    final top = alerts.take(5).toList();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: _kCardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kRed.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_rounded,
                  color: _kRed, size: 16),
              const SizedBox(width: 8),
              Text(
                'התראות חכמות',
                style: TextStyle(
                  color: _kRed.withValues(alpha: 0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _kRed.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${alerts.length}',
                  style: const TextStyle(
                    color: _kRed,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...top.map(_buildSmartAlertRow),
        ],
      ),
    );
  }

  Widget _buildSmartAlertRow(CeoSmartAlert a) {
    final (color, icon) = switch (a.severity) {
      'critical' => (_kRed,    Icons.dangerous_rounded),
      'urgent'   => (_kAmber,  Icons.warning_amber_rounded),
      'warning'  => (_kAmber,  Icons.info_outline_rounded),
      _          => (_kBlue,   Icons.info_rounded),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  a.body,
                  style: const TextStyle(
                    color: _kTextMuted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Launch readiness gauge — big headline-level score card.
  Widget _buildLaunchReadinessCard(CeoLaunchReadiness lr) {
    final (gaugeColor, gaugeLabel) = switch (lr.verdict) {
      'GO'      => (_kGreen,  'מוכן להשקה'),
      'CAUTION' => (_kAmber,  'זהירות'),
      _         => (_kRed,    'לא מוכן'),
    };
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            gaugeColor.withValues(alpha: 0.12),
            gaugeColor.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: gaugeColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: gaugeColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: gaugeColor, width: 2),
                ),
                child: Center(
                  child: Text(
                    '${lr.total}',
                    style: TextStyle(
                      color: gaugeColor,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Launch Readiness',
                      style: TextStyle(
                        color: gaugeColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      gaugeLabel,
                      style: const TextStyle(
                        color: _kTextPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      lr.verdictLabel,
                      style: const TextStyle(
                        color: _kTextMuted,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Category score bars
          Row(
            children: [
              _buildLaunchCategoryBar('פונקציונלי', lr.categoryScores['functional']),
              const SizedBox(width: 8),
              _buildLaunchCategoryBar('בטיחות', lr.categoryScores['safety']),
              const SizedBox(width: 8),
              _buildLaunchCategoryBar('חוסן', lr.categoryScores['resilience']),
              const SizedBox(width: 8),
              _buildLaunchCategoryBar('שליטה', lr.categoryScores['founder']),
            ],
          ),
          if (lr.topBlockers.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(color: _kBorderFaint, height: 1),
            const SizedBox(height: 10),
            const Text(
              'חוסמים מובילים (לפי importance × impact):',
              style: TextStyle(
                color: _kTextMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...lr.topBlockers.map(_buildBlockerRow),
          ],
        ],
      ),
    );
  }

  Widget _buildLaunchCategoryBar(String label, Map<String, dynamic>? data) {
    final score = (data?['score'] as num?)?.toInt() ?? 0;
    final barColor = score >= 85 ? _kGreen : (score >= 70 ? _kAmber : _kRed);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _kTextMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: _kBorderFaint,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: (score / 100).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$score',
                style: TextStyle(
                  color: barColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBlockerRow(CeoLaunchBlocker b) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _kRed.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${b.weight}',
              style: const TextStyle(
                color: _kRed,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              b.title,
              style: const TextStyle(
                color: _kTextPrimary,
                fontSize: 11,
                height: 1.4,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Prediction card — current value + 30-day projection + confidence.
  Widget _buildPredictionCard(CeoPrediction p) {
    final (trendColor, trendIcon) = switch (p.trend) {
      'growing'   => (_kGreen,     Icons.trending_up_rounded),
      'declining' => (_kRed,       Icons.trending_down_rounded),
      'flat'      => (_kTextMuted, Icons.trending_flat_rounded),
      _           => (_kTextMuted, Icons.help_outline_rounded),
    };
    final confidenceLabel = switch (p.confidence) {
      'high'              => 'ודאות גבוהה',
      'medium'            => 'ודאות בינונית',
      'low'               => 'ודאות נמוכה',
      'insufficient_data' => 'אין מספיק נתונים',
      _                   => p.confidence,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCardDarker,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: trendColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(trendIcon, color: trendColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  p.label,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (p.confidence != 'insufficient_data')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: trendColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${p.weeklyGrowthPct >= 0 ? '+' : ''}${p.weeklyGrowthPct}% / week',
                    style: TextStyle(
                      color: trendColor,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            p.narrative,
            style: const TextStyle(
              color: _kTextPrimary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.assessment_outlined,
                  color: _kTextMuted, size: 11),
              const SizedBox(width: 4),
              Text(
                '$confidenceLabel  •  r²=${p.r2.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: _kTextMuted,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Anomaly card — z-score + delta from baseline.
  Widget _buildAnomalyCard(CeoAnomaly a) {
    final color = switch (a.severity) {
      'critical' => _kRed,
      'warning'  => _kAmber,
      _          => _kBlue,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.science_rounded, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  a.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'z=${a.zScore.toStringAsFixed(1)}',
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            a.narrative,
            style: const TextStyle(
              color: _kTextPrimary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  /// Rule-engine action item card — urgency + owner badges.
  Widget _buildActionItemCard(CeoActionItem a) {
    final (urgencyColor, urgencyLabel) = switch (a.urgency) {
      'critical' => (_kRed,    'קריטי'),
      'urgent'   => (_kAmber,  'דחוף'),
      _          => (_kBlue,   'רגיל'),
    };
    final ownerLabel = switch (a.owner) {
      'founder' => '👤 מייסד',
      'admin'   => '🛠️ אדמין',
      'support' => '🎧 תמיכה',
      _         => '⚙️ ops',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCardDarker,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: urgencyColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: urgencyColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  urgencyLabel,
                  style: TextStyle(
                    color: urgencyColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                ownerLabel,
                style: const TextStyle(
                  color: _kTextMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            a.title,
            style: const TextStyle(
              color: _kTextPrimary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            a.body,
            style: const TextStyle(
              color: _kTextMuted,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  /// Churn risk card — risk score + signals + suggested intervention.
  Widget _buildChurnRiskCard(CeoChurnRisk c) {
    final riskPct = (c.riskScore * 100).round();
    final riskColor = c.riskScore >= 0.75 ? _kRed : _kAmber;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCardDarker,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: riskColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: riskColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: riskColor),
                ),
                child: Center(
                  child: Text(
                    '$riskPct',
                    style: TextStyle(
                      color: riskColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      style: const TextStyle(
                        color: _kTextPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${c.serviceType} • ${c.orderCount} הזמנות • ⭐ ${c.rating.toStringAsFixed(1)}',
                      style: const TextStyle(
                        color: _kTextMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (c.signals.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: c.signals.map((s) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: riskColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  s,
                  style: TextStyle(
                    color: riskColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )).toList(),
            ),
          ],
          if (c.suggestedAction.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.lightbulb_outline_rounded,
                    color: _kIndigoLight, size: 12),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    c.suggestedAction,
                    style: const TextStyle(
                      color: _kIndigoLight,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Benchmark card — competitor comparison row.
  Widget _buildBenchmarkCard(CeoBenchmark b) {
    final numberFmt = NumberFormat('#,###');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCardDarker,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBlue.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  b.name,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (b.gapPct > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _kBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'אנחנו ב-${b.gapPct.toStringAsFixed(3)}% מהם',
                    style: const TextStyle(
                      color: _kBlue,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            b.note,
            style: const TextStyle(
              color: _kTextMuted,
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildBenchmarkMini(
                  'GMV שבועי',
                  '\$${numberFmt.format(b.theirWeeklyGmvUsd)}',
                  'אנחנו: \$${numberFmt.format(b.ourWeeklyGmvUsd)}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildBenchmarkMini(
                  'Take rate',
                  '${b.theirTakeRate}%',
                  b.takeRateAdvantage,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBenchmarkMini(String label, String their, String ours) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _kTextMuted,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          their,
          style: const TextStyle(
            color: _kTextPrimary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          ours,
          style: const TextStyle(
            color: _kIndigoLight,
            fontSize: 10,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  /// Cohort card — monthly signup cohort stats.
  Widget _buildCohortCard(CeoCohort c) {
    final retentionColor = c.retentionPct >= 60
        ? _kGreen
        : (c.retentionPct >= 40 ? _kAmber : _kRed);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCardDarker,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kPurple.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _kPurple.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              c.monthKey,
              style: const TextStyle(
                color: _kPurple,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${c.size} משתמשים (${c.providers} ספקים)',
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'XP ממוצע: ${c.avgXp}  •  פעילים 30d: ${c.active30d}',
                  style: const TextStyle(
                    color: _kTextMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: retentionColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${c.retentionPct}%',
              style: TextStyle(
                color: retentionColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── v12.5: Memory + Cost footer ───────────────────────────────────────

  /// Shows accumulated memory stats (session count, learned facts) + cost
  /// breakdown for this specific generation + running session total.
  Widget _buildMemoryAndCostFooter(CeoInsight insight) {
    final memSessions = insight.memoryStats.sessionCount;
    final memFacts = insight.memoryStats.learnedFacts;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _kPurple.withValues(alpha: 0.10),
            _kIndigo.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kPurple.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Memory row — "Ilon's brain"
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  color: _kPurple, size: 16),
              const SizedBox(width: 8),
              const Text(
                'המוח של אילון',
                style: TextStyle(
                  color: _kPurple,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kPurple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  memSessions == 0
                      ? 'פגישה ראשונה'
                      : 'פגישה #${memSessions + 1}',
                  style: const TextStyle(
                    color: _kPurple,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _miniStat(
                icon: Icons.psychology_rounded,
                label: 'פגישות',
                value: '$memSessions',
                color: _kIndigoLight,
              ),
              _miniStat(
                icon: Icons.lightbulb_outline_rounded,
                label: 'תובנות נלמדו',
                value: '$memFacts',
                color: _kAmber,
              ),
              _miniStat(
                icon: Icons.trending_up_rounded,
                label: memSessions > 0 ? 'מתחכם' : 'מתחיל',
                value: memFacts > 10 ? '🔥' : memFacts > 3 ? '⚡' : '🌱',
                color: _kGreen,
              ),
            ],
          ),

          const SizedBox(height: 10),
          const Divider(color: _kBorderFaint, height: 1),
          const SizedBox(height: 10),

          // Cost breakdown
          Row(
            children: [
              const Icon(Icons.payments_rounded,
                  color: _kGreen, size: 15),
              const SizedBox(width: 8),
              const Text(
                'עלות',
                style: TextStyle(
                  color: _kGreen,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '\$${insight.costUsd.toStringAsFixed(4)}  (בריפינג זה)',
                style: const TextStyle(
                  color: _kTextMuted,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(width: 23),
              Text(
                'טוקנים: ${insight.inputTokens} input + ${insight.outputTokens} output',
                style: const TextStyle(
                  color: _kTextMuted,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _kGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Text(
                  'סה״כ session (כולל צ׳אט):',
                  style: TextStyle(
                    color: _kTextPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '\$${_sessionCostUsd.toStringAsFixed(4)}',
                  style: const TextStyle(
                    color: _kGreen,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsetsDirectional.only(end: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: _kCardDarker,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 12),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: const TextStyle(
                color: _kTextPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Existing performer card ────────────────────────────────────────────

  Widget _buildPerformerCard(CeoTopPerformer p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kAmber.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kAmber.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _kAmber.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.star_rounded, color: _kAmber, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  p.highlight,
                  style: TextStyle(
                    color: _kTextMuted.withValues(alpha: 0.9),
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Small UI helpers ───────────────────────────────────────────────────

  Widget _quickActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _kCardDark,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: _kIndigo.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _kIndigoLight, size: 14),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _kTextMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.open_in_new, color: _kTextMuted, size: 10),
          ],
        ),
      ),
    );
  }

  Widget _primaryButton(String label, IconData icon, VoidCallback onTap) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: _kIndigo,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      onPressed: _loading ? null : onTap,
    );
  }

  Future<void> _openUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {/* ignore */}
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('הועתק ללוח'),
        backgroundColor: _kGreen,
        duration: Duration(seconds: 2),
      ),
    );
  }
}
