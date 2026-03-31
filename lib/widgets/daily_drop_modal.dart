/// AnySkill — Daily Drop Mystery Box Modal
///
/// Full-screen modal with:
///   1. Mystery box scale+glow animation (2 seconds suspense)
///   2. Reward reveal with icon, name, description, expiry
///   3. Dismiss button
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/engagement_service.dart';

/// Shows the Daily Drop modal. Call from initState or post-frame callback.
Future<void> showDailyDropModal(
    BuildContext context, RewardConfig reward) async {
  await showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black87,
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (_, __, ___) => _DailyDropDialog(reward: reward),
  );
}

class _DailyDropDialog extends StatefulWidget {
  final RewardConfig reward;
  const _DailyDropDialog({required this.reward});

  @override
  State<_DailyDropDialog> createState() => _DailyDropDialogState();
}

class _DailyDropDialogState extends State<_DailyDropDialog>
    with TickerProviderStateMixin {
  late final AnimationController _boxCtrl;
  late final AnimationController _revealCtrl;
  late final Animation<double> _boxScale;
  late final Animation<double> _boxGlow;
  late final Animation<double> _revealOpacity;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();

    // ── Box pulse animation (loops during suspense) ──────────────────────
    _boxCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _boxScale = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _boxCtrl, curve: Curves.easeInOut),
    );
    _boxGlow = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _boxCtrl, curve: Curves.easeInOut),
    );
    _boxCtrl.repeat(reverse: true);

    // ── Reveal fade-in ───────────────────────────────────────────────────
    _revealCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _revealOpacity = CurvedAnimation(
      parent: _revealCtrl,
      curve: Curves.easeOutCubic,
    );

    // Auto-reveal after 2 seconds of suspense
    Timer(const Duration(milliseconds: 2000), _reveal);
  }

  void _reveal() {
    if (!mounted) return;
    _boxCtrl.stop();
    setState(() => _revealed = true);
    _revealCtrl.forward();
  }

  @override
  void dispose() {
    _boxCtrl.dispose();
    _revealCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Material(
          color: Colors.transparent,
          child: _revealed ? _buildRevealed() : _buildMysteryBox(),
        ),
      ),
    );
  }

  // ── Mystery Box (suspense phase) ───────────────────────────────────────────

  Widget _buildMysteryBox() {
    return AnimatedBuilder(
      animation: _boxCtrl,
      builder: (context, child) => Transform.scale(
        scale: _boxScale.value,
        child: Container(
          width: 180,
          height: 180,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                widget.reward.color.withValues(alpha: 0.8),
                widget.reward.color,
              ],
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: widget.reward.color.withValues(alpha: _boxGlow.value * 0.6),
                blurRadius: 40 * _boxGlow.value,
                spreadRadius: 8 * _boxGlow.value,
              ),
            ],
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('🎁', style: TextStyle(fontSize: 56)),
              SizedBox(height: 8),
              Text(
                'ההפתעה היומית שלך...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Revealed Reward ────────────────────────────────────────────────────────

  Widget _buildRevealed() {
    final r = widget.reward;
    return FadeTransition(
      opacity: _revealOpacity,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: r.color.withValues(alpha: 0.3),
              blurRadius: 30,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Reward icon ──────────────────────────────────────────────
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    r.color.withValues(alpha: 0.15),
                    r.color.withValues(alpha: 0.05),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(r.icon, color: r.color, size: 40),
            ),
            const SizedBox(height: 20),

            // ── "You won!" header ────────────────────────────────────────
            const Text(
              '🎉 מזל טוב!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // ── Reward name ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: r.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                r.nameHe,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: r.color,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Description ──────────────────────────────────────────────
            Text(
              r.descriptionHe,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF6B7280),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),

            // ── Expiry ───────────────────────────────────────────────────
            Text(
              'בתוקף ל-${r.duration.inHours} שעות',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF9CA3AF),
              ),
            ),
            const SizedBox(height: 24),

            // ── Dismiss ──────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: r.color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                child: const Text('מעולה!'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
