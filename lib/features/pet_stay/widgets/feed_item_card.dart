/// AnySkill — Feed Item Card (Pet Stay Tracker v13.0.0, Step 7)
///
/// Renders a single [PetUpdate] as a card in the timeline. Used by both
/// the provider Pet Mode screen and the (upcoming Step 8) owner feed.
///
/// Reactions + replies are NOT rendered here yet — that's Step 9. The
/// card reserves spacing for them via a bottom row that stays empty.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../models/pet_update.dart';
import '../services/pet_update_service.dart';

/// Step 9 reactions palette — keep in sync with prompt's product spec.
const List<String> kReactionEmojis = ['❤️', '😍', '🐾', '😂', '👏', '🙏'];

class FeedItemCard extends StatelessWidget {
  final PetUpdate update;
  final String jobId;

  const FeedItemCard({
    super.key,
    required this.update,
    required this.jobId,
  });

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(update.type);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 6),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: style.bg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(style.icon, color: style.fg, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        style.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: style.fg,
                        ),
                      ),
                      Text(
                        _relativeTime(update.timestamp),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Body
          _body(context),

          const SizedBox(height: 8),

          // Reactions + replies (Step 9)
          _ReactionRow(jobId: jobId, update: update),
          if (update.replies.isNotEmpty) _RepliesList(replies: update.replies),

          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (update.type) {
      case 'walk_completed':
        return _walkCompleted();
      case 'pee':
      case 'poop':
        return _marker();
      case 'photo':
        return _photo(context);
      case 'video':
        return _video(context);
      case 'note':
        return _note();
      case 'daily_report':
        return _dailyReport();
      default:
        return _genericText();
    }
  }

  Widget _dailyReport() {
    final r = update.reportData ?? const {};
    final mood = (r['mood'] ?? '') as String;
    final moodLabel = _moodLabel(mood);
    final moodEmoji = _moodEmoji(mood);
    final meals = (r['mealsEaten'] ?? '—').toString();
    final walks = (r['walksCompleted'] ?? 0).toString();
    final km = (r['totalDistanceKm'] as num?)?.toDouble() ?? 0;
    final medsOk = r['medicationGiven'] == true;
    final pee = (r['peeCount'] ?? 0).toString();
    final poop = (r['poopCount'] ?? 0).toString();
    final notes = (r['notes'] ?? '') as String;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mood hero
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFAF5FF), Color(0xFFEEF2FF)],
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD8B4FE)),
            ),
            child: Row(
              children: [
                Text(moodEmoji, style: const TextStyle(fontSize: 32)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('מצב רוח',
                          style: TextStyle(
                              color: Color(0xFF6B21A8),
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                      Text(
                        moodLabel,
                        style: const TextStyle(
                          color: Color(0xFF581C87),
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Stats grid
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _drStat(Icons.restaurant_rounded, 'ארוחות',
                          meals, const Color(0xFFF59E0B)),
                    ),
                    Expanded(
                      child: _drStat(Icons.directions_walk_rounded,
                          'הליכונים', walks, const Color(0xFF10B981)),
                    ),
                    Expanded(
                      child: _drStat(
                          Icons.straighten_rounded,
                          'ק"מ',
                          km.toStringAsFixed(1),
                          const Color(0xFF3B82F6)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _drStat(
                        Icons.medication_rounded,
                        'תרופות',
                        medsOk ? '✓' : '—',
                        const Color(0xFFEF4444),
                      ),
                    ),
                    Expanded(
                      child: _drStat(Icons.water_drop_rounded, '💧',
                          pee, const Color(0xFFCA8A04)),
                    ),
                    Expanded(
                      child: _drStat(Icons.pest_control_rounded, '💩',
                          poop, const Color(0xFF92400E)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (notes.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Text(
                notes,
                style: const TextStyle(
                  color: Color(0xFF78350F),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _drStat(IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color)),
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: Color(0xFF6B7280))),
      ],
    );
  }

  String _moodEmoji(String key) => switch (key) {
        'excellent' => '😄',
        'good' => '😊',
        'okay' => '😐',
        'poor' => '😔',
        _ => '🐾',
      };

  String _moodLabel(String key) => switch (key) {
        'excellent' => 'מצוין',
        'good' => 'טוב',
        'okay' => 'בסדר',
        'poor' => 'לא טוב',
        _ => '—',
      };

  Widget _walkCompleted() {
    final km = (update.distanceKm ?? 0).toStringAsFixed(2);
    final dur = _formatDuration(update.durationSeconds ?? 0);
    final steps = update.steps ?? 0;
    final pace = update.pacePerKm ?? '—';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF86EFAC)),
        ),
        child: Row(
          children: [
            Expanded(child: _stat('מרחק', '$km ק"מ')),
            Expanded(child: _stat('משך', dur)),
            Expanded(child: _stat('צעדים', '$steps')),
            Expanded(child: _stat('קצב/ק"מ', pace)),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF065F46),
              fontSize: 14,
            )),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF6B7280),
            )),
      ],
    );
  }

  Widget _marker() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 0),
      child: Text(
        update.type == 'pee' ? 'סומן במהלך ההליכון 💧' : 'סומן במהלך ההליכון 💩',
        style: const TextStyle(color: Color(0xFF4B5563), fontSize: 13),
      ),
    );
  }

  Widget _note() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 0),
      child: Text(
        update.text ?? '',
        style: const TextStyle(
          color: Color(0xFF1A1A2E),
          fontSize: 14,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _photo(BuildContext context) {
    final url = update.mediaUrl;
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => _openPhotoFullscreen(context, url),
          child: ClipRRect(
            borderRadius: BorderRadius.zero,
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFFF3F4F6),
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_rounded,
                      color: Color(0xFF9CA3AF)),
                ),
                loadingBuilder: (c, child, progress) =>
                    progress == null
                        ? child
                        : Container(
                            color: const Color(0xFFF9FAFB),
                            alignment: Alignment.center,
                            child: const CircularProgressIndicator(
                                strokeWidth: 2),
                          ),
              ),
            ),
          ),
        ),
        if ((update.text ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 0),
            child: Text(
              update.text!,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF1A1A2E),
                height: 1.4,
              ),
            ),
          ),
      ],
    );
  }

  Widget _video(BuildContext context) {
    final url = update.mediaUrl;
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => _openVideoFullscreen(context, url),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: const Color(0xFF1A1A2E)),
                const Center(
                  child: Icon(Icons.play_circle_filled_rounded,
                      color: Colors.white, size: 64),
                ),
                const PositionedDirectional(
                  top: 8,
                  end: 8,
                  child: _VideoBadge(),
                ),
              ],
            ),
          ),
        ),
        if ((update.text ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 0),
            child: Text(
              update.text!,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF1A1A2E),
                height: 1.4,
              ),
            ),
          ),
      ],
    );
  }

  Widget _genericText() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 0),
      child: Text(
        update.text ?? '—',
        style: const TextStyle(color: Color(0xFF4B5563)),
      ),
    );
  }

  void _openPhotoFullscreen(BuildContext context, String url) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _FullscreenPhoto(url: url),
    ));
  }

  void _openVideoFullscreen(BuildContext context, String url) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _FullscreenVideo(url: url),
    ));
  }

  // ── Utilities ──────────────────────────────────────────────────────

  _ItemStyle _styleFor(String type) {
    switch (type) {
      case 'walk_completed':
        return const _ItemStyle(
          label: 'הליכון הסתיים',
          icon: Icons.directions_walk_rounded,
          fg: Color(0xFF059669),
          bg: Color(0xFFECFDF5),
        );
      case 'pee':
        return const _ItemStyle(
          label: '💧 פיפי',
          icon: Icons.water_drop_rounded,
          fg: Color(0xFFCA8A04),
          bg: Color(0xFFFEF9C3),
        );
      case 'poop':
        return const _ItemStyle(
          label: '💩 קקי',
          icon: Icons.pest_control_rounded,
          fg: Color(0xFF92400E),
          bg: Color(0xFFFEF3C7),
        );
      case 'photo':
        return const _ItemStyle(
          label: 'תמונה',
          icon: Icons.camera_alt_rounded,
          fg: Color(0xFF2563EB),
          bg: Color(0xFFEFF6FF),
        );
      case 'video':
        return const _ItemStyle(
          label: 'וידאו',
          icon: Icons.videocam_rounded,
          fg: Color(0xFF2563EB),
          bg: Color(0xFFEFF6FF),
        );
      case 'note':
        return const _ItemStyle(
          label: 'הערה',
          icon: Icons.edit_note_rounded,
          fg: Color(0xFF6B21A8),
          bg: Color(0xFFFAF5FF),
        );
      case 'daily_report':
        return const _ItemStyle(
          label: 'דו"ח יומי',
          icon: Icons.assignment_rounded,
          fg: Color(0xFF7C3AED),
          bg: Color(0xFFFAF5FF),
        );
      default:
        return const _ItemStyle(
          label: 'עדכון',
          icon: Icons.info_outline_rounded,
          fg: Color(0xFF6B7280),
          bg: Color(0xFFF3F4F6),
        );
    }
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'עכשיו';
    if (diff.inMinutes < 60) return 'לפני ${diff.inMinutes} ד׳';
    if (diff.inHours < 24) return 'לפני ${diff.inHours} ש׳';
    if (diff.inDays < 7) return 'לפני ${diff.inDays} ימים';
    return '${t.day}/${t.month}/${t.year}';
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '$h ש׳ $m ד׳';
    return '$m ד׳';
  }
}

class _ItemStyle {
  final String label;
  final IconData icon;
  final Color fg;
  final Color bg;
  const _ItemStyle({
    required this.label,
    required this.icon,
    required this.fg,
    required this.bg,
  });
}

class _VideoBadge extends StatelessWidget {
  const _VideoBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'וידאו',
        style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _FullscreenPhoto extends StatelessWidget {
  final String url;
  const _FullscreenPhoto({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4.0,
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class _FullscreenVideo extends StatefulWidget {
  final String url;
  const _FullscreenVideo({required this.url});
  @override
  State<_FullscreenVideo> createState() => _FullscreenVideoState();
}

class _FullscreenVideoState extends State<_FullscreenVideo> {
  VideoPlayerController? _ctrl;
  bool _initFailed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _ctrl = c);
      await c.play();
      c.setLooping(false);
    } catch (_) {
      if (mounted) setState(() => _initFailed = true);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded, color: Colors.white),
            onPressed: () async {
              final uri = Uri.parse(widget.url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
      ),
      body: Center(
        child: _initFailed
            ? const _VideoFallback()
            : (_ctrl == null || !_ctrl!.value.isInitialized)
                ? const CircularProgressIndicator(color: Colors.white)
                : AspectRatio(
                    aspectRatio: _ctrl!.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        VideoPlayer(_ctrl!),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _ctrl!.value.isPlaying
                                  ? _ctrl!.pause()
                                  : _ctrl!.play();
                            });
                          },
                          child: Container(
                            color: Colors.transparent,
                            child: AnimatedOpacity(
                              opacity: _ctrl!.value.isPlaying ? 0 : 1,
                              duration:
                                  const Duration(milliseconds: 250),
                              child: const Icon(
                                Icons.play_circle_filled_rounded,
                                color: Colors.white,
                                size: 80,
                              ),
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

class _VideoFallback extends StatelessWidget {
  const _VideoFallback();
  @override
  Widget build(BuildContext context) {
    return const Text(
      'שגיאה בטעינת הווידאו — פתח/י בנגן חיצוני',
      style: TextStyle(color: Colors.white70, fontSize: 14),
      textAlign: TextAlign.center,
    );
  }
}

// ── Step 9 — Reactions ─────────────────────────────────────────────────

class _ReactionRow extends StatelessWidget {
  final String jobId;
  final PetUpdate update;

  const _ReactionRow({required this.jobId, required this.update});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // Count by emoji + figure out which one (if any) belongs to me.
    final counts = <String, int>{};
    String? mine;
    update.reactions.forEach((userId, emoji) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
      if (userId == uid) mine = emoji;
    });

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 10, 0),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final e in kReactionEmojis)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: _ReactionPill(
                        emoji: e,
                        count: counts[e] ?? 0,
                        active: mine == e,
                        onTap: uid == null
                            ? null
                            : () => PetUpdateService.instance.toggleReaction(
                                  jobId: jobId,
                                  updateId: update.id!,
                                  emoji: e,
                                ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            iconSize: 20,
            color: const Color(0xFF6366F1),
            icon: const Icon(Icons.reply_rounded),
            tooltip: 'הגב',
            onPressed: update.id == null
                ? null
                : () => _openReplyDialog(context),
          ),
        ],
      ),
    );
  }

  Future<void> _openReplyDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    final text = await showDialog<String?>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('הגב לעדכון'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          minLines: 2,
          decoration: const InputDecoration(hintText: 'הקלד/י תגובה...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, null),
            child: const Text('ביטול'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
            ),
            onPressed: () => Navigator.pop(c, ctrl.text),
            child: const Text('שלח'),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      await PetUpdateService.instance.addReply(
        jobId: jobId,
        updateId: update.id!,
        text: text,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
      );
    }
  }
}

class _ReactionPill extends StatelessWidget {
  final String emoji;
  final int count;
  final bool active;
  final VoidCallback? onTap;

  const _ReactionPill({
    required this.emoji,
    required this.count,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEEF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? const Color(0xFF6366F1)
                : const Color(0xFFE5E7EB),
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: active
                      ? const Color(0xFF6366F1)
                      : const Color(0xFF6B7280),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Step 9 — Replies ───────────────────────────────────────────────────

class _RepliesList extends StatelessWidget {
  final List<Map<String, dynamic>> replies;
  const _RepliesList({required this.replies});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in replies)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 8),
              decoration: const BoxDecoration(
                color: Color(0xFFF9FAFB),
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(8),
                  right: Radius.circular(2),
                ),
                border: BorderDirectional(
                  start: BorderSide(color: Color(0xFF6366F1), width: 3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        (r['userName'] ?? 'משתמש').toString(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _relTime(r['timestamp']),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    (r['text'] ?? '').toString(),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1A1A2E),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _relTime(dynamic ts) {
    DateTime? t;
    if (ts is Timestamp) t = ts.toDate();
    if (t == null) return '';
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'עכשיו';
    if (diff.inMinutes < 60) return 'לפני ${diff.inMinutes} ד׳';
    if (diff.inHours < 24) return 'לפני ${diff.inHours} ש׳';
    return 'לפני ${diff.inDays} ימים';
  }
}
