import 'dart:async';

import 'package:flutter/material.dart';

import '_did_iframe_registry.dart';

/// D-ID Agent embed URL for Alex AI Teacher.
const _kDIdAgentUrl =
    'https://studio.d-id.com/agents/share?id=v2_agt_foW6KwWc&utm_source=copy&key=Y2tfeERFSVZNb3ZueDlEejcyVnhNNzFq';

/// Full-screen modal overlay that embeds the D-ID AI teacher agent in an
/// iframe, with an AnySkill sidebar showing lesson timer, credit balance,
/// and a close button. The user stays inside the app.
class AiTeacherLessonModal extends StatefulWidget {
  /// Remaining wallet credits after payment (shown in sidebar).
  final double? remainingCredits;

  const AiTeacherLessonModal({super.key, this.remainingCredits});

  /// Shows the modal as a full-screen dialog.
  static Future<void> show(BuildContext context, {double? remainingCredits}) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close AI Lesson',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 350),
      transitionBuilder: (ctx, a1, a2, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: a1, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0)
                .animate(CurvedAnimation(parent: a1, curve: Curves.easeOutCubic)),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, a1, a2) =>
          AiTeacherLessonModal(remainingCredits: remainingCredits),
    );
  }

  @override
  State<AiTeacherLessonModal> createState() => _AiTeacherLessonModalState();
}

class _AiTeacherLessonModalState extends State<AiTeacherLessonModal> {
  static const _kPurple = Color(0xFF6366F1);
  static const _kDark   = Color(0xFF1A1A2E);

  // ── Lesson timer ─────────────────────────────────────────────────────────
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _tick;
  String _elapsed = '00:00';

  // ── Iframe registration ──────────────────────────────────────────────────
  final String _viewType = 'did-agent-iframe-${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _registerIframe();
    _stopwatch.start();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final secs = _stopwatch.elapsed.inSeconds;
      setState(() {
        _elapsed =
            '${(secs ~/ 60).toString().padLeft(2, '0')}:${(secs % 60).toString().padLeft(2, '0')}';
      });
    });
  }

  void _registerIframe() {
    // §65: delegated to a conditional-import bridge so the test VM can
    // compile this file without `dart:html` / `dart:ui_web`. On non-web
    // the call is a no-op (the modal itself is web-gated upstream).
    registerDIDAgentIframe(viewType: _viewType, url: _kDIdAgentUrl);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    final isNarrow = w < 700;

    // On mobile: go full-screen so the iframe + controls fit the viewport.
    // On desktop: use the 92%/90% windowed look.
    if (isNarrow) {
      return Material(
        color: _kDark,
        child: SafeArea(child: _buildNarrowLayout()),
      );
    }

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: w * 0.92,
          height: h * 0.90,
          decoration: BoxDecoration(
            color: _kDark,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: _kPurple.withValues(alpha: 0.3),
                blurRadius: 40,
                spreadRadius: 2,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: _buildWideLayout(),
        ),
      ),
    );
  }

  // ── Wide layout: iframe (left ~72%) + sidebar (right ~28%) ───────────────
  Widget _buildWideLayout() {
    return Row(
      children: [
        // D-ID Agent iframe
        Expanded(
          flex: 72,
          child: _buildIframe(),
        ),
        // Sidebar
        SizedBox(
          width: 240,
          child: _buildSidebar(),
        ),
      ],
    );
  }

  // ── Narrow/mobile layout: iframe (flex 3) + session panel (flex 0) ───────
  // The iframe gets ~65% of screen; the panel is scrollable below it
  // so the D-ID "Start conversation" button stays visible inside the iframe.
  Widget _buildNarrowLayout() {
    return Column(
      children: [
        // ── Top: close pill + timer row ─────────────────────────────────
        _buildMobileTopBar(),
        // ── Middle: iframe takes available space but never starves panel ─
        Expanded(child: _buildIframe()),
        // ── Bottom: session details panel ───────────────────────────────
        _buildMobilePanel(),
      ],
    );
  }

  Widget _buildIframe() {
    return Container(
      color: Colors.black,
      child: HtmlElementView(viewType: _viewType),
    );
  }

  // ── Sidebar (wide screens) ───────────────────────────────────────────────
  Widget _buildSidebar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1A),
        border: Border(
          left: BorderSide(color: _kPurple.withValues(alpha: 0.3), width: 1),
        ),
      ),
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_kPurple.withValues(alpha: 0.2), Colors.transparent],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              children: [
                // AI avatar
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _kPurple.withValues(alpha: 0.4),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text('A',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Alex',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('AI English Teacher',
                    style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 13)),
              ],
            ),
          ),

          const Divider(color: Colors.white12, height: 1),

          // ── Timer ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: _buildStatCard(
              icon: Icons.timer_outlined,
              label: 'זמן שיעור',
              value: _elapsed,
              color: const Color(0xFF10B981),
            ),
          ),

          // ── Credits ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildStatCard(
              icon: Icons.account_balance_wallet_outlined,
              label: 'יתרה בארנק',
              value: widget.remainingCredits != null
                  ? '₪${widget.remainingCredits!.toStringAsFixed(0)}'
                  : '—',
              color: const Color(0xFFF59E0B),
            ),
          ),

          const SizedBox(height: 20),

          // ── Tips ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kPurple.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline, color: _kPurple, size: 16),
                      const SizedBox(width: 6),
                      Text('טיפ',
                          style: TextStyle(
                              color: _kPurple,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'דבר/י עם Alex באנגלית — הוא יתקן ויעזור לך להשתפר!',
                    style: TextStyle(color: Colors.grey[300], fontSize: 12, height: 1.4),
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // ── Rate button ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('הדירוג יהיה זמין בסוף השיעור'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.star_rounded, size: 18),
              label: const Text('דרג את השיעור'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFF59E0B),
                side: const BorderSide(color: Color(0xFFF59E0B)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── Close button ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('סיים שיעור'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Mobile top bar: timer + close button ──────────────────────────────────
  Widget _buildMobileTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF0F0F1A),
      child: Row(
        children: [
          // Timer pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_outlined,
                    color: Color(0xFF10B981), size: 14),
                const SizedBox(width: 5),
                Text(_elapsed,
                    style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Balance pill
          if (widget.remainingCredits != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                  '₪${widget.remainingCredits!.toStringAsFixed(0)}',
                  style: const TextStyle(
                      color: Color(0xFFF59E0B),
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
          const Spacer(),
          // Close
          SizedBox(
            height: 34,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, size: 14),
              label: const Text('סיים שיעור', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Mobile bottom panel: tip + details ──────────────────────────────────
  Widget _buildMobilePanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1A),
        border: Border(
          top: BorderSide(color: _kPurple.withValues(alpha: 0.25), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Tip (compact)
          Expanded(
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline,
                    color: _kPurple.withValues(alpha: 0.7), size: 14),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'דבר/י עם Alex באנגלית!',
                    style: TextStyle(
                        color: Colors.grey[400], fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Rate button (small)
          SizedBox(
            height: 30,
            child: OutlinedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('הדירוג יהיה זמין בסוף השיעור'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFF59E0B),
                side: BorderSide(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rounded, size: 13),
                  SizedBox(width: 4),
                  Text('דרג', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(color: Colors.grey[500], fontSize: 11)),
              const SizedBox(height: 2),
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace')),
            ],
          ),
        ],
      ),
    );
  }
}
