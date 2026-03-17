// ignore_for_file: use_build_context_synchronously
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../../../services/gamification_service.dart';
import '../../expert_profile_screen.dart';
import '../../../l10n/app_localizations.dart'; // ignore: unused_import — partial i18n pass

// ─────────────────────────────────────────────────────────────────────────────
// Colour palette used throughout this file
// ─────────────────────────────────────────────────────────────────────────────
const _kGradStart  = Color(0xFF6366F1);
const _kGradMid    = Color(0xFFEC4899);
const _kGradEnd    = Color(0xFFF59E0B);
const _kAdminEmail = 'adawiavihai@gmail.com';

// ─────────────────────────────────────────────────────────────────────────────
// 1.  StoriesRow — public entry point
// ─────────────────────────────────────────────────────────────────────────────

/// Horizontal row of circular skill-story avatars.
/// • Shows providers where `hasActive == true` in the `stories` collection.
/// • First slot is the current user's own story (if they are a provider).
/// • Collapses entirely when there is nothing to show.
class StoriesRow extends StatefulWidget {
  final bool isProvider;

  const StoriesRow({super.key, required this.isProvider});

  @override
  State<StoriesRow> createState() => _StoriesRowState();
}

class _StoriesRowState extends State<StoriesRow> {
  final _uid     = FirebaseAuth.instance.currentUser?.uid ?? '';
  final _isAdmin = FirebaseAuth.instance.currentUser?.email == _kAdminEmail;

  @override
  Widget build(BuildContext context) {
    // QA: StoriesRow is rendering
    debugPrint('QA: StoriesRow.build — isProvider=${widget.isProvider}');
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('stories')
          // NOTE: No orderBy here — combining where()+orderBy() on different
          // fields requires a composite Firestore index that silently fails on
          // web and returns 0 results. We sort client-side instead.
          .where('hasActive', isEqualTo: true)
          .limit(30)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.waiting) {
          final docs = snap.data?.docs ?? [];
          debugPrint('QA: StoriesRow — fetched ${docs.length} docs from Firestore');
          for (final d in docs) {
            final data = d.data() as Map<String, dynamic>? ?? {};
            debugPrint('  • doc=${d.id} hasActive=${data['hasActive']} '
                'providerName=${data['providerName']} '
                'timestamp=${data['timestamp']} '
                'videoUrl=${(data['videoUrl'] as String? ?? '').isNotEmpty ? 'SET' : 'EMPTY'}');
          }
          if (snap.hasError) debugPrint('QA: StoriesRow ERROR — ${snap.error}');
        }

        // ── Loading skeleton — shown until first Firestore frame ──────────
        if (snap.connectionState == ConnectionState.waiting) {
          return _StoriesShell(
            activeCount: 0,
            child: SizedBox(
              height: 98,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 5,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, __) => _ShimmerCircle(),
              ),
            ),
          );
        }

        // Sort client-side: newest first (avoids composite index requirement)
        final rawDocs = List<QueryDocumentSnapshot>.from(snap.data?.docs ?? []);
        rawDocs.sort((a, b) {
          final ta = ((a.data() as Map)['timestamp'] as Timestamp?)?.seconds ?? 0;
          final tb = ((b.data() as Map)['timestamp'] as Timestamp?)?.seconds ?? 0;
          return tb.compareTo(ta); // descending
        });

        final allDocs   = rawDocs;
        final ownDoc    = allDocs.where((d) => d.id == _uid).firstOrNull;
        final otherDocs = allDocs.where((d) => d.id != _uid).toList();

        final itemCount = (widget.isProvider ? 1 : 0) + otherDocs.length;

        // ── No stories + not a provider → show empty placeholder row ─────
        if (itemCount == 0) {
          return _StoriesShell(
            activeCount: 0,
            child: SizedBox(
              height: 98,
              child: Center(
                child: Text(
                  'עדיין אין סטוריז פעילים',
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                ),
              ),
            ),
          );
        }

        return _StoriesShell(
          activeCount: allDocs.length,
          child: SizedBox(
            height: 98,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: itemCount,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (ctx, i) {
                if (widget.isProvider && i == 0) {
                  return _MyStorySlot(
                    uid:        _uid,
                    ownDoc:     ownDoc,
                    onUploaded: () => setState(() {}),
                  );
                }
                final doc  = otherDocs[widget.isProvider ? i - 1 : i];
                final data = doc.data() as Map<String, dynamic>;
                return _StoryCircle(
                  uid:        doc.id,
                  data:       data,
                  currentUid: _uid,
                  isAdmin:    _isAdmin,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shell widget — section label + active badge + arbitrary child
// ─────────────────────────────────────────────────────────────────────────────

class _StoriesShell extends StatelessWidget {
  final int    activeCount;
  final Widget child;

  const _StoriesShell({required this.activeCount, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Row(
              children: [
                Container(
                  width: 3, height: 16,
                  decoration: BoxDecoration(
                    color: _kGradStart,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 7),
                const Text(
                  'סטורי נותני השירות',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                if (activeCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F0FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$activeCount פעיל${activeCount == 1 ? '' : 'ים'}',
                      style: const TextStyle(
                        fontSize: 11, color: _kGradStart, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),
          child,
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading shimmer circle placeholder
// ─────────────────────────────────────────────────────────────────────────────

class _ShimmerCircle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 44, height: 9,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2.  _MyStorySlot — current user's first circle
// ─────────────────────────────────────────────────────────────────────────────

class _MyStorySlot extends StatefulWidget {
  final String              uid;
  final QueryDocumentSnapshot? ownDoc;
  final VoidCallback        onUploaded;

  const _MyStorySlot({
    required this.uid,
    required this.ownDoc,
    required this.onUploaded,
  });

  @override
  State<_MyStorySlot> createState() => _MyStorySlotState();
}

class _MyStorySlotState extends State<_MyStorySlot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _hasStory => widget.ownDoc != null;

  void _onTap(BuildContext context) {
    if (_hasStory) {
      // View own story
      _openViewer(context, widget.uid,
          widget.ownDoc!.data() as Map<String, dynamic>);
    } else {
      // Upload new story
      _showUploadSheet(context, widget.uid, widget.onUploaded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userSnap = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid);

    return StreamBuilder<DocumentSnapshot>(
      stream: userSnap.snapshots(),
      builder: (context, snap) {
        final data   = snap.data?.data() as Map<String, dynamic>? ?? {};
        final avatar = data['profileImage'] as String? ?? '';
        final name   = data['name']         as String? ?? 'אני';

        return GestureDetector(
          onTap: () => _onTap(context),
          onLongPress: _hasStory
              ? () {
                  final videoUrl = (widget.ownDoc!.data()
                          as Map<String, dynamic>)['videoUrl'] as String? ??
                      '';
                  _confirmAndDeleteStory(context, widget.uid, videoUrl);
                }
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 68,
                height: 68,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Animated gradient ring
                    AnimatedBuilder(
                      animation: _ctrl,
                      builder: (_, __) => CustomPaint(
                        size: const Size(68, 68),
                        painter: _RingPainter(
                          colors: const [_kGradStart, _kGradMid, _kGradEnd, _kGradStart],
                          progress: _ctrl.value,
                          strokeWidth: 3.0,
                          active: true,
                        ),
                      ),
                    ),
                    // White gap
                    Container(
                      width: 60,
                      height: 60,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    // Avatar
                    ClipOval(
                      child: avatar.isNotEmpty
                          ? Image.network(avatar,
                              width: 56, height: 56, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _avatarFallback(name))
                          : _avatarFallback(name),
                    ),
                    // "+" badge when no story
                    if (!_hasStory)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: _kGradStart,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: const Icon(Icons.add,
                              color: Colors.white, size: 13),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _hasStory ? 'הסיפור שלי' : 'הוסף סטורי',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _hasStory ? Colors.black87 : _kGradStart,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3.  _StoryCircle — other providers' circles
// ─────────────────────────────────────────────────────────────────────────────

class _StoryCircle extends StatelessWidget {
  final String               uid;
  final Map<String, dynamic> data;
  final String               currentUid;
  final bool                 isAdmin;

  const _StoryCircle({
    required this.uid,
    required this.data,
    required this.currentUid,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context) {
    final name       = data['providerName']   as String? ?? 'ספק';
    final avatar     = data['providerAvatar'] as String? ?? '';
    final ts         = data['timestamp']      as Timestamp?;
    final timeLabel  = _timeLabel(ts);

    final canDelete = (uid == currentUid) || isAdmin;
    final videoUrl  = data['videoUrl'] as String? ?? '';

    return GestureDetector(
      onTap: () => _openViewer(context, uid, data),
      onLongPress: canDelete
          ? () => _confirmAndDeleteStory(context, uid, videoUrl)
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 68,
            height: 68,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Static gradient ring
                CustomPaint(
                  size: const Size(68, 68),
                  painter: _RingPainter(
                    colors: const [_kGradStart, _kGradMid, _kGradEnd],
                    progress: 0,
                    strokeWidth: 3.0,
                    active: true,
                  ),
                ),
                Container(
                  width: 60,
                  height: 60,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                ClipOval(
                  child: avatar.isNotEmpty
                      ? Image.network(avatar,
                          width: 56, height: 56, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _avatarFallback(name))
                      : _avatarFallback(name),
                ),
                // Time-remaining badge
                if (timeLabel != null)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        timeLabel,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: 68,
            child: Text(
              name,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  String? _timeLabel(Timestamp? ts) {
    if (ts == null) return null;
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inHours >= 24) return null;
    if (diff.inHours >= 1)  return '${24 - diff.inHours}שע׳';
    return '${60 - diff.inMinutes}ד׳';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4.  _RingPainter — gradient ring CustomPainter
// ─────────────────────────────────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  final List<Color> colors;
  final double      progress;   // 0.0–1.0; controls start angle for rotation
  final double      strokeWidth;
  final bool        active;

  const _RingPainter({
    required this.colors,
    required this.progress,
    required this.strokeWidth,
    required this.active,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!active) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - (strokeWidth / 2);
    final rect   = Rect.fromCircle(center: center, radius: radius);

    final paint = Paint()
      ..style       = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap   = StrokeCap.round
      ..shader      = SweepGradient(
          colors:     colors,
          startAngle: progress * 2 * math.pi,
          endAngle:   (progress + 1) * 2 * math.pi,
          tileMode:   TileMode.mirror,
        ).createShader(rect);

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// 4b. Delete Story — shared logic used by both _MyStorySlot & _StoryCircle
// ─────────────────────────────────────────────────────────────────────────────

/// Shows a confirmation dialog, then:
///   1. Deletes the Storage file (best-effort — failure is non-fatal)
///   2. Deletes the Firestore `stories/{expertUid}` document
///   3. Sets `users/{expertUid}.hasActiveStory = false`
///   4. Shows a success SnackBar
Future<void> _confirmAndDeleteStory(
    BuildContext context, String expertUid, String videoUrl) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'למחוק את הסטורי?',
        textAlign: TextAlign.right,
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: const Text(
        'הסטורי יימחק לצמיתות ולא ניתן יהיה לשחזרו.',
        textAlign: TextAlign.right,
        style: TextStyle(color: Colors.grey),
      ),
      actionsAlignment: MainAxisAlignment.start,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('ביטול',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('מחק',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  // 1. Delete from Storage (best-effort — network errors are non-fatal)
  if (videoUrl.isNotEmpty) {
    try {
      await FirebaseStorage.instance.refFromURL(videoUrl).delete();
    } catch (e) {
      debugPrint('Story Storage delete failed (non-fatal): $e');
    }
  }

  // 2. Delete Firestore document
  await FirebaseFirestore.instance
      .collection('stories')
      .doc(expertUid)
      .delete();

  // 3. Clear ranking signal on user doc
  await FirebaseFirestore.instance
      .collection('users')
      .doc(expertUid)
      .update({'hasActiveStory': false, 'storyTimestamp': null});

  // 4. Success feedback
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      backgroundColor: Color(0xFF22C55E),
      behavior: SnackBarBehavior.floating,
      content: Text(
        'הסטורי נמחק בהצלחה 🗑️',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5.  Story Viewer — full-screen overlay
// ─────────────────────────────────────────────────────────────────────────────

void _openViewer(
    BuildContext context, String uid, Map<String, dynamic> data) {
  final videoUrl   = data['videoUrl']       as String? ?? '';
  final name       = data['providerName']   as String? ?? 'ספק';
  final avatar     = data['providerAvatar'] as String? ?? '';
  final ts         = data['timestamp']      as Timestamp?;
  final serviceType = data['serviceType']   as String? ?? '';

  if (videoUrl.isEmpty) return;

  showGeneralDialog(
    context:    context,
    barrierDismissible: true,
    barrierLabel: 'story',
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: child,
    ),
    pageBuilder: (ctx, _, __) => _StoryViewerScreen(
      videoUrl:    videoUrl,
      providerUid: uid,
      providerName: name,
      providerAvatar: avatar,
      serviceType: serviceType,
      timestamp:   ts?.toDate(),
    ),
  );
}

class _StoryViewerScreen extends StatefulWidget {
  final String   videoUrl;
  final String   providerUid;
  final String   providerName;
  final String   providerAvatar;
  final String   serviceType;
  final DateTime? timestamp;

  const _StoryViewerScreen({
    required this.videoUrl,
    required this.providerUid,
    required this.providerName,
    required this.providerAvatar,
    required this.serviceType,
    required this.timestamp,
  });

  @override
  State<_StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<_StoryViewerScreen> {
  late VideoPlayerController _ctrl;
  bool _initialized = false;
  bool _error       = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
    _incrementViewCount();
  }

  Future<void> _initVideo() async {
    try {
      _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await _ctrl.initialize();
      if (!mounted) return;
      _ctrl.addListener(_onUpdate);
      await _ctrl.play();
      setState(() => _initialized = true);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  void _onUpdate() {
    if (!mounted) return;
    setState(() {});
    // Auto-navigate to expert profile when video finishes
    if (_ctrl.value.isInitialized &&
        !_ctrl.value.isPlaying &&
        _ctrl.value.position >= _ctrl.value.duration &&
        _ctrl.value.duration > Duration.zero) {
      _goToProfile();
    }
  }

  void _goToProfile() {
    Navigator.of(context).pop();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExpertProfileScreen(
          expertId:   widget.providerUid,
          expertName: widget.providerName,
        ),
      ),
    );
  }

  void _incrementViewCount() {
    FirebaseFirestore.instance
        .collection('stories')
        .doc(widget.providerUid)
        .update({'viewCount': FieldValue.increment(1)})
        .catchError((_) {});
  }

  @override
  void dispose() {
    if (_initialized) {
      _ctrl.removeListener(_onUpdate);
      _ctrl.dispose();
    }
    super.dispose();
  }

  String _timeAgo(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return 'לפני ${diff.inMinutes} ד׳';
    return 'לפני ${diff.inHours} שע׳';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Video ──────────────────────────────────────────────────
            if (_initialized)
              Center(
                child: AspectRatio(
                  aspectRatio: _ctrl.value.aspectRatio,
                  child: VideoPlayer(_ctrl),
                ),
              )
            else if (_error)
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image_rounded,
                        color: Colors.white54, size: 64),
                    SizedBox(height: 12),
                    Text('לא ניתן לטעון את הסיפור',
                        style: TextStyle(color: Colors.white54)),
                  ],
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // ── Progress bar at top ───────────────────────────────────
            if (_initialized)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _ProgressBar(controller: _ctrl),
              ),

            // ── Provider info overlay (top) ───────────────────────────
            Positioned(
              top: 10,
              right: 0,
              left: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    // Avatar
                    ClipOval(
                      child: widget.providerAvatar.isNotEmpty
                          ? Image.network(widget.providerAvatar,
                              width: 42, height: 42, fit: BoxFit.cover)
                          : _avatarFallback(widget.providerName, size: 42),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.providerName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                shadows: [
                                  Shadow(
                                      color: Colors.black54,
                                      blurRadius: 4)
                                ]),
                          ),
                          if (widget.serviceType.isNotEmpty)
                            Text(
                              widget.serviceType,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          if (widget.timestamp != null)
                            Text(
                              _timeAgo(widget.timestamp),
                              style: const TextStyle(
                                  color: Colors.white60, fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                    // Close
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── "Book Now" CTA at bottom ──────────────────────────────
            Positioned(
              bottom: 24,
              left: 24,
              right: 24,
              child: Row(
                children: [
                  // View count
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('stories')
                          .doc(widget.providerUid)
                          .snapshots(),
                      builder: (_, snap) {
                        final views = ((snap.data?.data()
                                as Map<String, dynamic>?)?['viewCount']
                            as num?) ??
                            0;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.visibility_outlined,
                                color: Colors.white70, size: 14),
                            const SizedBox(width: 4),
                            Text('$views',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                          ],
                        );
                      },
                    ),
                  ),
                  const Spacer(),
                  // View Profile CTA
                  GestureDetector(
                    onTap: _goToProfile,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_kGradStart, _kGradMid],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: _kGradStart.withValues(alpha: 0.5),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('צפה בפרופיל',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                          SizedBox(width: 6),
                          Icon(Icons.person_outline_rounded,
                              color: Colors.white, size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6.  _ProgressBar — thin animated top bar
// ─────────────────────────────────────────────────────────────────────────────

class _ProgressBar extends StatefulWidget {
  final VideoPlayerController controller;

  const _ProgressBar({required this.controller});

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final dur  = widget.controller.value.duration;
    final pos  = widget.controller.value.position;
    final frac = dur.inMilliseconds > 0
        ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value:            frac,
          backgroundColor:  Colors.white30,
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          minHeight:        3,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 7.  _StoryUploadSheet — provider uploads a video story
// ─────────────────────────────────────────────────────────────────────────────

void _showUploadSheet(
    BuildContext context, String uid, VoidCallback onSuccess) {
  showModalBottomSheet(
    context:     context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _StoryUploadSheet(uid: uid, onSuccess: onSuccess),
  );
}

class _StoryUploadSheet extends StatefulWidget {
  final String   uid;
  final VoidCallback onSuccess;

  const _StoryUploadSheet({required this.uid, required this.onSuccess});

  @override
  State<_StoryUploadSheet> createState() => _StoryUploadSheetState();
}

class _StoryUploadSheetState extends State<_StoryUploadSheet> {
  XFile?   _pickedVideo;
  bool     _uploading    = false;
  double   _uploadProgress = 0;
  String?  _errorMessage;

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final file = await picker.pickVideo(
      source:        ImageSource.gallery,
      maxDuration:   const Duration(seconds: 60),
    );
    if (file != null && mounted) setState(() => _pickedVideo = file);
  }

  Future<void> _upload() async {
    if (_pickedVideo == null) return;
    setState(() { _uploading = true; _errorMessage = null; });

    try {
      // 1. Read user profile for thumbnail + name
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .get();
      final userData    = userDoc.data() ?? {};
      final name        = userData['name']         as String? ?? 'ספק';
      final avatar      = userData['profileImage'] as String? ?? '';
      final serviceType = userData['serviceType']  as String? ?? '';

      // 2. Upload video to Firebase Storage
      final bytes    = await _pickedVideo!.readAsBytes();
      // Detect the actual MIME type — iOS returns video/quicktime (.mov),
      // Android returns video/mp4, web may return video/webm, etc.
      final mimeType = _pickedVideo!.mimeType ?? 'video/mp4';
      // Preserve the original extension so Storage serves the right Content-Type.
      final origName = _pickedVideo!.name;
      final ext      = origName.contains('.')
          ? origName.split('.').last.toLowerCase()
          : 'mp4';

      final ts = DateTime.now().millisecondsSinceEpoch;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('stories/${widget.uid}_$ts.$ext');

      final uploadTask = storageRef.putData(
        bytes,
        SettableMetadata(contentType: mimeType),
      );

      // Track upload progress
      uploadTask.snapshotEvents.listen((snap) {
        if (!mounted || snap.totalBytes == 0) return;
        setState(() {
          _uploadProgress = snap.bytesTransferred / snap.totalBytes;
        });
      });

      final snapshot  = await uploadTask;
      final videoUrl  = await snapshot.ref.getDownloadURL();

      // 3. Write to stories/{uid}
      final now       = Timestamp.now();
      final expiresAt = Timestamp.fromDate(
          now.toDate().add(const Duration(hours: 24)));

      await FirebaseFirestore.instance
          .collection('stories')
          .doc(widget.uid)
          .set({
            'uid':            widget.uid,
            'expertId':       widget.uid,        // spec field
            'expertName':     name,              // spec field
            'videoUrl':       videoUrl,
            'thumbnailUrl':   avatar,            // provider's profile image as thumbnail
            'providerName':   name,              // kept for viewer compatibility
            'providerAvatar': avatar,
            'serviceType':    serviceType,
            'timestamp':      now,
            'createdAt':      FieldValue.serverTimestamp(), // spec field
            'expiresAt':      expiresAt,
            'hasActive':      true,
            'views':          0,                // spec field
            'viewCount':      0,                // kept for viewer/Firestore rule compatibility
          });

      // 4. Update users/{uid} for ranking signal
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .update({
            'hasActiveStory':  true,
            'storyTimestamp':  now,
          });

      // 5. Award XP for story_upload event (fire-and-forget)
      _awardStoryXP(widget.uid);

      if (!mounted) return;
      widget.onSuccess();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('הסיפור שלך פורסם! ✨ תקף ל-24 שעות'),
          backgroundColor: _kGradStart,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploading = false;
          // Translate common Firebase Storage errors to Hebrew
          final msg = e.toString();
          if (msg.contains('unauthorized') || msg.contains('permission')) {
            _errorMessage = 'שגיאת הרשאה — נסה להתחבר מחדש';
          } else if (msg.contains('canceled')) {
            _errorMessage = 'ההעלאה בוטלה';
          } else if (msg.contains('network') || msg.contains('timeout')) {
            _errorMessage = 'שגיאת רשת — בדוק את החיבור ונסה שוב';
          } else {
            _errorMessage = 'שגיאה בהעלאה — נסה שוב';
          }
        });
      }
    }
  }

  void _awardStoryXP(String uid) {
    // Non-blocking — Cloud Function updateUserXP handles XP + level update
    // We trigger it via a Firestore write to xp_events (lightweight trigger pattern)
    FirebaseFirestore.instance.collection('xp_events').add({
      'userId':  uid,
      'eventId': GamificationService.evStoryUpload,
      'timestamp': FieldValue.serverTimestamp(),
    // ignore: avoid_types_on_closure_parameters
    }).catchError((Object _) => FirebaseFirestore.instance.collection('xp_events').doc());
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 20),

              // Title
              Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [_kGradStart, _kGradMid]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.play_circle_outline_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('סיפור מיומנות',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('הצג את הכישרון שלך • תקף 24 שעות',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ]),
              const SizedBox(height: 20),

              // Perks row
              Row(children: [
                _perkChip(Icons.trending_up_rounded, 'בוסט בחיפוש'),
                const SizedBox(width: 8),
                _perkChip(Icons.star_rounded, '+5 XP'),
                const SizedBox(width: 8),
                _perkChip(Icons.access_time_rounded, '24 שעות'),
              ]),
              const SizedBox(height: 20),

              // Video picker area
              GestureDetector(
                onTap: _uploading ? null : _pickVideo,
                child: Container(
                  height: 120,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color:        const Color(0xFFF5F5FF),
                    borderRadius: BorderRadius.circular(16),
                    border:       Border.all(
                        color: _kGradStart.withValues(alpha: 0.3),
                        width: 1.5,
                        style: _pickedVideo == null
                            ? BorderStyle.solid
                            : BorderStyle.solid),
                  ),
                  child: _pickedVideo == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.video_call_rounded,
                                size: 40,
                                color: _kGradStart.withValues(alpha: 0.7)),
                            const SizedBox(height: 8),
                            const Text('בחר סרטון מהגלריה',
                                style: TextStyle(
                                    color: _kGradStart,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('מומלץ עד 60 שניות',
                                style: TextStyle(
                                    color: Colors.grey[500], fontSize: 12)),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle_rounded,
                                size: 36, color: Colors.green),
                            const SizedBox(height: 6),
                            Text(
                              _pickedVideo!.name.length > 30
                                  ? '...${_pickedVideo!.name.substring(_pickedVideo!.name.length - 30)}'
                                  : _pickedVideo!.name,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                              textAlign: TextAlign.center,
                            ),
                            TextButton(
                              onPressed: _uploading ? null : _pickVideo,
                              child: const Text('החלף סרטון'),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),

              // Error
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 13)),
                ),

              // Upload progress
              if (_uploading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value:           _uploadProgress > 0 ? _uploadProgress : null,
                    backgroundColor: Colors.grey[200],
                    valueColor:      const AlwaysStoppedAnimation(_kGradStart),
                    minHeight:       6,
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _uploadProgress > 0
                        ? 'מעלה... ${(_uploadProgress * 100).toStringAsFixed(0)}%'
                        : 'מכין...',
                    style: const TextStyle(
                        color: _kGradStart, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Upload button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGradStart,
                    padding:   const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  onPressed: _pickedVideo == null || _uploading ? null : _upload,
                  child: _uploading
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text(
                          'פרסם סיפור',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _perkChip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0FF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: _kGradStart),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    color: _kGradStart,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

Widget _avatarFallback(String name, {double size = 56}) => Container(
      width:  size,
      height: size,
      color:  const Color(0xFFE8E8FF),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
              fontSize: size * 0.4,
              fontWeight: FontWeight.bold,
              color: _kGradStart),
        ),
      ),
    );
