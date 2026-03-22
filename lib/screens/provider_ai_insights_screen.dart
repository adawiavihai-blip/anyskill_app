// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/pro_service.dart';
import '../widgets/pro_badge.dart';

// Brand tokens
const _kPurple = Color(0xFF6366F1);
const _kGreen  = Color(0xFF10B981);
const _kRed    = Color(0xFFEF4444);
const _kAmber  = Color(0xFFF59E0B);
const _kSlate  = Color(0xFF1A1A2E);

/// Provider-facing AI insights screen.
/// Shows personalised feedback on each Pro criterion + overall progress.
/// Navigated to from the "ה-AI שלנו מצא דרך לשפר אותך!" notification.
class ProviderAiInsightsScreen extends StatefulWidget {
  const ProviderAiInsightsScreen({super.key});

  @override
  State<ProviderAiInsightsScreen> createState() =>
      _ProviderAiInsightsScreenState();
}

class _ProviderAiInsightsScreenState
    extends State<ProviderAiInsightsScreen> {
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  late Future<ProMetrics> _future;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _future = ProService.fetchProviderMetrics(_uid);
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await ProService.checkAndRefreshProStatus(_uid);
    } finally {
      if (mounted) {
        setState(() {
          _future    = ProService.fetchProviderMetrics(_uid);
          _refreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _kSlate,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_kPurple, Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.asset(
                'assets/images/NEW_LOGO1.png.png',
                width: 18, height: 18, fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'תובנות AI עבורך',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: _kSlate,
              ),
            ),
          ],
        ),
        actions: [
          _refreshing
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _kPurple),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: _kPurple),
                  tooltip: 'רענן נתונים',
                  onPressed: _refresh,
                ),
        ],
      ),
      body: FutureBuilder<ProMetrics>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: _kPurple),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Text('שגיאה: ${snap.error}',
                  style: const TextStyle(color: _kRed)),
            );
          }
          return _buildBody(snap.data!);
        },
      ),
    );
  }

  Widget _buildBody(ProMetrics m) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // ── Overall progress header ─────────────────────────────────────────
        _buildOverallCard(m),
        const SizedBox(height: 16),

        // ── Per-criterion cards ─────────────────────────────────────────────
        _buildCriterionCard(
          emoji: '⭐',
          title: 'דירוג',
          passed: m.ratingOk,
          current: '${m.rating.toStringAsFixed(1)} / 5.0',
          target: 'מינימום ${m.thresholdMinRating.toStringAsFixed(1)}',
          progress: (m.rating / 5.0).clamp(0.0, 1.0),
          tip: m.ratingOk
              ? 'כל הכבוד! הדירוג שלך עומד בדרישה.'
              : 'בקש מלקוחות מרוצים להשאיר ביקורת. כל כוכב חשוב.',
        ),
        const SizedBox(height: 12),

        _buildCriterionCard(
          emoji: '🏆',
          title: 'הזמנות שהושלמו',
          passed: m.ordersOk,
          current: '${m.completedOrders} עסקאות',
          target: 'מינימום ${m.thresholdMinOrders}',
          progress: (m.completedOrders / m.thresholdMinOrders).clamp(0.0, 1.0),
          tip: m.ordersOk
              ? 'ניסיון מוכח ✓ — ${m.completedOrders} הזמנות שהושלמו.'
              : 'נותרו ${m.thresholdMinOrders - m.completedOrders} הזמנות להשלמה. '
                'הגדל את הנוכחות שלך בפלטפורמה.',
        ),
        const SizedBox(height: 12),

        _buildCriterionCard(
          emoji: '⚡',
          title: 'זמן תגובה',
          passed: m.responseOk,
          current: m.avgResponseMinutes == 0
              ? 'אין נתונים עדיין'
              : '${m.avgResponseMinutes} דקות בממוצע',
          target: 'מתחת ל-${m.thresholdMaxResponseMins} דקות',
          progress: m.avgResponseMinutes == 0
              ? 1.0
              : (1.0 - (m.avgResponseMinutes - m.thresholdMaxResponseMins) /
                      m.thresholdMaxResponseMins.toDouble())
                  .clamp(0.0, 1.0),
          tip: m.responseOk
              ? 'תגובה מהירה ✓ — לקוחות מעריכים את המהירות שלך!'
              : 'נסה להגיב ללקוחות תוך ${m.thresholdMaxResponseMins} דקות. '
                'הפעל התראות push כדי לא לפספס.',
        ),
        const SizedBox(height: 12),

        _buildCriterionCard(
          emoji: '🛡️',
          title: 'ביטולים ב-30 הימים האחרונים',
          passed: m.cancelOk,
          current: '${m.recentCancellations} ביטולים',
          target: 'אפס ביטולים',
          progress: m.cancelOk ? 1.0 : 0.0,
          tip: m.cancelOk
              ? 'אמינות מושלמת ✓ — לא ביטלת אף הזמנה לאחרונה.'
              : 'זיהינו ${m.recentCancellations} ביטולים מצדך. '
                'המנע מביטולים כדי לשמור על מעמד ה-Pro.',
        ),

        // ── Manual override notice ──────────────────────────────────────────
        if (m.isManualOverride) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _kAmber.withValues(alpha: 0.4)),
            ),
            child: const Row(
              children: [
                Icon(Icons.admin_panel_settings_rounded,
                    color: _kAmber, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'הסטטוס שלך הוגדר ידנית על-ידי מנהל המערכת.',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF92400E),
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 24),

        // ── Refresh Pro status button ──────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _refreshing ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(
              'עדכן סטטוס Pro',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }

  // ── Overall header card ───────────────────────────────────────────────────

  Widget _buildOverallCard(ProMetrics m) {
    final pct = (m.overallProgress * 100).round();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _kPurple,
            const Color(0xFF8B5CF6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _kPurple.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (m.isAnySkillPro)
                const ProBadge(large: true)
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'בדרך ל-Pro',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              const Text(
                'ביצועים שלך',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: m.overallProgress,
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: AlwaysStoppedAnimation<Color>(
                  m.isAnySkillPro ? _kGreen : Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                m.isAnySkillPro
                    ? '✓ עומד בכל הדרישות'
                    : '$pct% הושלמו',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${m.eligibleForPro ? 4 : [m.ratingOk, m.ordersOk, m.responseOk, m.cancelOk].where((b) => b).length}/4 קריטריונים',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Single criterion card ─────────────────────────────────────────────────

  Widget _buildCriterionCard({
    required String emoji,
    required String title,
    required bool   passed,
    required String current,
    required String target,
    required double progress,
    required String tip,
  }) {
    final statusColor = passed ? _kGreen : _kRed;
    final barColor    = passed ? _kGreen : _kPurple;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: passed
              ? _kGreen.withValues(alpha: 0.2)
              : Colors.grey.shade100,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Status chip
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      passed
                          ? Icons.check_circle_rounded
                          : Icons.cancel_rounded,
                      color: statusColor,
                      size: 13,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      passed ? 'עומד בדרישה' : 'דרוש שיפור',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // Title
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: _kSlate,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(emoji, style: const TextStyle(fontSize: 16)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          const SizedBox(height: 8),

          // Current / target row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'יעד: $target',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              Text(
                current,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: passed ? _kGreen : _kSlate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // AI tip
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  tip,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('💡', style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
