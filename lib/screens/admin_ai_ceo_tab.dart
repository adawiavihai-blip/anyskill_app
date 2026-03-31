/// AnySkill — AI CEO Strategic Dashboard (סוכן AI מנכ"ל)
///
/// Dark premium Indigo theme. Displays:
///   - Morning Brief (סיכום בוקר)
///   - Strategic Recommendations (המלצות לשיפור)
///   - Red Flags (נורות אדומות)
///
/// Data powered by AiCeoService → Cloud Function → Claude Sonnet.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/ai_ceo_service.dart';

// ── Dark Premium Palette ─────────────────────────────────────────────────────
const _kBgDark      = Color(0xFF0F0F1A);
const _kCardDark    = Color(0xFF1A1A2E);
const _kIndigo      = Color(0xFF6366F1);
const _kIndigoLight = Color(0xFF818CF8);
const _kPurple      = Color(0xFF8B5CF6);
const _kAmber       = Color(0xFFF59E0B);
const _kRed         = Color(0xFFEF4444);
const _kGreen       = Color(0xFF10B981);
const _kTextPrimary = Color(0xFFF1F5F9);
const _kTextMuted   = Color(0xFF94A3B8);

class AdminAiCeoTab extends StatefulWidget {
  const AdminAiCeoTab({super.key});

  @override
  State<AdminAiCeoTab> createState() => _AdminAiCeoTabState();
}

class _AdminAiCeoTabState extends State<AdminAiCeoTab> {
  CeoInsight? _insight;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    setState(() { _loading = true; _error = null; });
    try {
      final insight = await AiCeoService.generateInsight();
      if (mounted) setState(() { _insight = insight; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgDark,
      body: _loading ? _buildLoading() : _buildContent(),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kIndigo, _kPurple],
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: _kIndigo.withValues(alpha: 0.4),
                  blurRadius: 32,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Icon(Icons.psychology_rounded,
                color: Colors.white, size: 40),
          ),
          const SizedBox(height: 24),
          const Text(
            'הסוכן מנתח את הנתונים...',
            style: TextStyle(
              color: _kTextPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'מאסף מדדים מכל המערכות',
            style: TextStyle(
              color: _kTextMuted.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 160,
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
    if (_error != null) {
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
              _actionButton('נסה שוב', Icons.refresh, _generate),
            ],
          ),
        ),
      );
    }

    final insight = _insight;
    if (insight == null) return const SizedBox.shrink();

    return RefreshIndicator(
      color: _kIndigo,
      backgroundColor: _kCardDark,
      onRefresh: _generate,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          // ── Header ──────────────────────────────────────────────────
          _buildHeader(insight),
          const SizedBox(height: 12),

          // ── Quick Actions Row ──────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _quickActionChip(
                  icon: Icons.bug_report_rounded,
                  label: 'Firebase Crashlytics',
                  onTap: () => launchUrl(
                    Uri.parse('https://console.firebase.google.com/project/anyskill-6fdf3/crashlytics'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _quickActionChip(
                  icon: Icons.analytics_rounded,
                  label: 'Firebase Console',
                  onTap: () => launchUrl(
                    Uri.parse('https://console.firebase.google.com/project/anyskill-6fdf3/overview'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Morning Brief ───────────────────────────────────────────
          _buildSection(
            icon: Icons.wb_sunny_rounded,
            iconColor: _kAmber,
            title: 'סיכום בוקר',
            subtitle: DateFormat('dd/MM/yyyy HH:mm').format(insight.generatedAt),
            child: Text(
              insight.morningBrief,
              style: const TextStyle(
                color: _kTextPrimary,
                fontSize: 14,
                height: 1.7,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Recommendations ─────────────────────────────────────────
          if (insight.recommendations.isNotEmpty) ...[
            _buildSection(
              icon: Icons.lightbulb_rounded,
              iconColor: _kGreen,
              title: 'המלצות אסטרטגיות',
              subtitle: '${insight.recommendations.length} פעולות',
              child: Column(
                children: insight.recommendations.asMap().entries.map((e) =>
                    _buildRecommendationCard(e.key + 1, e.value)).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Red Flags ───────────────────────────────────────────────
          if (insight.redFlags.isNotEmpty) ...[
            _buildSection(
              icon: Icons.warning_amber_rounded,
              iconColor: _kRed,
              title: 'נורות אדומות',
              subtitle: '${insight.redFlags.length} התראות',
              child: Column(
                children: insight.redFlags.map((f) =>
                    _buildRedFlagCard(f)).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Refresh button ──────────────────────────────────────────
          Center(child: _actionButton('רענן ניתוח', Icons.refresh, _generate)),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

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
            color: _kIndigo.withValues(alpha: 0.2),
            blurRadius: 24,
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
                  'AI CEO',
                  style: TextStyle(
                    color: _kIndigoLight,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'סוכן אסטרטגי',
                  style: TextStyle(
                    color: _kTextPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'עודכן: ${DateFormat('HH:mm').format(insight.generatedAt)}',
                  style: const TextStyle(color: _kTextMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kIndigo, _kPurple],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _kPurple.withValues(alpha: 0.4),
                  blurRadius: 16,
                ),
              ],
            ),
            child: const Icon(Icons.psychology_rounded,
                color: Colors.white, size: 30),
          ),
        ],
      ),
    );
  }

  // ── Section container ──────────────────────────────────────────────────────

  Widget _buildSection({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kCardDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: iconColor.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
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
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  // ── Recommendation card ────────────────────────────────────────────────────

  Widget _buildRecommendationCard(int index, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kGreen.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kGreen.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: _kGreen.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$index',
                style: const TextStyle(
                  color: _kGreen,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
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

  // ── Red flag card ──────────────────────────────────────────────────────────

  Widget _buildRedFlagCard(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kRed.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_rounded, color: _kRed, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFFFCA5A5),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Action button ──────────────────────────────────────────────────────────

  Widget _quickActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _kCardDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kIndigo.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _kIndigoLight, size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _kTextMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.open_in_new, color: _kTextMuted, size: 12),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, VoidCallback onTap) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: _kIndigo,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      onPressed: _loading ? null : onTap,
    );
  }
}
