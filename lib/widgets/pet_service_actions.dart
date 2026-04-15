/// AnySkill — Pet Service Actions Widget
///
/// A single dual-mode card the provider sees on a pet-service job:
///
///   • [walkTracking == true]  → "Start Walk" / "End Walk" with live timer
///   • [dailyProof == true]    → "Upload Photo" + "Upload Video" + status
///
/// The widget is rendered ONLY on jobs whose expert's sub-category schema
/// has the matching flag enabled. The host screen (`my_bookings_screen.dart`)
/// passes the relevant booleans + the job context.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/boarding_proof_service.dart';
import '../services/dog_walk_service.dart';
import '../utils/safe_image_provider.dart';

class PetServiceActions extends StatefulWidget {
  final String jobId;
  final String customerId;
  final String customerName;
  final String providerId;
  final String providerName;
  final String chatRoomId;
  final bool walkTracking;
  final bool dailyProof;

  const PetServiceActions({
    super.key,
    required this.jobId,
    required this.customerId,
    required this.customerName,
    required this.providerId,
    required this.providerName,
    required this.chatRoomId,
    this.walkTracking = false,
    this.dailyProof = false,
  });

  @override
  State<PetServiceActions> createState() => _PetServiceActionsState();
}

class _PetServiceActionsState extends State<PetServiceActions> {
  // Walk state
  bool _starting = false;
  bool _ending = false;
  bool _markingPee = false;
  bool _markingPoop = false;

  // Boarding state
  bool _uploadingPhoto = false;
  bool _uploadingVideo = false;
  Map<String, dynamic>? _todayProof;

  @override
  void initState() {
    super.initState();
    if (widget.dailyProof) {
      _refreshTodayProof();
    }
    if (widget.walkTracking) {
      _attemptResumeWalk();
    }
  }

  /// Checks SharedPreferences for an interrupted walk against THIS job.
  /// If found and still marked `walking` in Firestore, re-attaches the
  /// GPS stream silently and tells the user via snackbar.
  Future<void> _attemptResumeWalk() async {
    final info = await DogWalkService.readPersistedActiveWalk();
    if (info == null) return;
    // Only resume if the persisted walk belongs to this job — other jobs'
    // walks are someone else's state and should be left alone.
    if (info.jobId != widget.jobId) return;
    final resumed = await DogWalkService.tryResumeActiveWalk();
    if (!mounted) return;
    if (resumed) {
      setState(() {}); // refresh button state
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🐕 ההליכון ממשיך — חזרה מהפסקה'),
          backgroundColor: Color(0xFF10B981),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _refreshTodayProof() async {
    final p = await BoardingProofService.todayProof(jobId: widget.jobId);
    if (mounted) setState(() => _todayProof = p);
  }

  // ──────────────────────────────────────────────────────────────────────
  // WALK
  // ──────────────────────────────────────────────────────────────────────

  Future<void> _addMarker(String type) async {
    final isPee = type == 'pee';
    setState(() {
      if (isPee) {
        _markingPee = true;
      } else {
        _markingPoop = true;
      }
    });
    try {
      final ok = await DogWalkService.addMarker(
        type: type,
        chatRoomId: widget.chatRoomId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? (isPee ? '💧 פיפי סומן' : '💩 קקי סומן')
                : 'אין הליכון פעיל',
          ),
          backgroundColor: ok ? const Color(0xFF10B981) : Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() {
          _markingPee = false;
          _markingPoop = false;
        });
      }
    }
  }

  Future<void> _startWalk() async {
    setState(() => _starting = true);
    try {
      await DogWalkService.startWalk(
        jobId: widget.jobId,
        customerId: widget.customerId,
        customerName: widget.customerName,
        providerId: widget.providerId,
        providerName: widget.providerName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🐕 ההליכון התחיל — המסלול נרשם'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _endWalk() async {
    setState(() => _ending = true);
    try {
      final summary = await DogWalkService.endWalk(chatRoomId: widget.chatRoomId);
      if (!mounted) return;
      if (summary != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ ההליכון הסתיים — '
              '${(summary.distanceMeters / 1000).toStringAsFixed(2)} ק"מ',
            ),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _ending = false);
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // BOARDING
  // ──────────────────────────────────────────────────────────────────────

  Future<void> _uploadPhoto() async {
    setState(() => _uploadingPhoto = true);
    try {
      final url = await BoardingProofService.uploadDailyPhoto(jobId: widget.jobId);
      if (!mounted) return;
      if (url != null) {
        await _refreshTodayProof();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ התמונה היומית נשלחה ללקוח'),
              backgroundColor: Color(0xFF10B981),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _uploadVideo() async {
    setState(() => _uploadingVideo = true);
    try {
      final url = await BoardingProofService.uploadDailyVideo(jobId: widget.jobId);
      if (!mounted) return;
      if (url != null) {
        await _refreshTodayProof();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ הוידאו היומי נשלח ללקוח'),
              backgroundColor: Color(0xFF10B981),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.walkTracking && !widget.dailyProof) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.pets_rounded,
                  color: Color(0xFFF97316), size: 18),
              SizedBox(width: 6),
              Text(
                'פעולות פנסיון / הליכון',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF7C2D12),
                ),
              ),
            ],
          ),
          // v13.0.0: walk controls are unlocked for BOTH dog-walker and
          // pension bookings — pension providers often take the boarded
          // dog out for walks too.
          if (widget.walkTracking || widget.dailyProof) ...[
            const SizedBox(height: 12),
            _buildWalkRow(),
          ],
          if (widget.dailyProof) ...[
            const SizedBox(height: 12),
            _buildBoardingRow(),
          ],
        ],
      ),
    );
  }

  Widget _buildWalkRow() {
    final isWalking = DogWalkService.isWalking;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isWalking ? Colors.red : const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: (isWalking ? _ending : _starting)
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Icon(isWalking
                        ? Icons.stop_circle_rounded
                        : Icons.play_circle_rounded),
                label: Text(
                  isWalking ? 'סיים טיול' : 'התחל טיול',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: (_starting || _ending)
                    ? null
                    : (isWalking ? _endWalk : _startWalk),
              ),
            ),
          ],
        ),
        if (isWalking) ...[
          const SizedBox(height: 10),
          _buildMarkerRow(),
        ],
      ],
    );
  }

  Widget _buildMarkerRow() {
    final walkId = DogWalkService.activeWalkId;
    final marked = _markingPee || _markingPoop;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: walkId == null
          ? const Stream.empty()
          : FirebaseFirestore.instance
              .collection('dog_walks')
              .doc(walkId)
              .snapshots(),
      builder: (context, snap) {
        int peeCount = 0;
        int poopCount = 0;
        if (snap.hasData && snap.data!.exists) {
          final markers =
              (snap.data!.data()?['markers'] as List? ?? const []);
          for (final m in markers) {
            if (m is Map && m['type'] == 'pee') peeCount++;
            if (m is Map && m['type'] == 'poop') poopCount++;
          }
        }
        return Row(
          children: [
            Expanded(
              child: _markerButton(
                emoji: '💧',
                label: 'סמן פיפי',
                count: peeCount,
                color: const Color(0xFFEAB308),
                busy: _markingPee,
                enabled: !marked,
                onTap: () => _addMarker('pee'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _markerButton(
                emoji: '💩',
                label: 'סמן קקי',
                count: poopCount,
                color: const Color(0xFF92400E),
                busy: _markingPoop,
                enabled: !marked,
                onTap: () => _addMarker('poop'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _markerButton({
    required String emoji,
    required String label,
    required int count,
    required Color color,
    required bool busy,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color, width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      onPressed: (busy || !enabled) ? null : onTap,
      child: busy
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: color),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$count',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: color,
                        )),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildBoardingRow() {
    final hasPhoto =
        (_todayProof?['photoUrl'] as String?)?.isNotEmpty ?? false;
    final hasVideo =
        (_todayProof?['videoUrl'] as String?)?.isNotEmpty ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'עדכון יומי ללקוח (היום ${BoardingProofService.dayKey()})',
          style: const TextStyle(fontSize: 11, color: Color(0xFF7C2D12)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor:
                      hasPhoto ? const Color(0xFF10B981) : const Color(0xFFF97316),
                  side: BorderSide(
                    color: hasPhoto
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF97316),
                  ),
                ),
                icon: _uploadingPhoto
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(hasPhoto ? Icons.check : Icons.add_a_photo_outlined),
                label: Text(hasPhoto ? 'תמונה ✓' : 'תמונה'),
                onPressed: _uploadingPhoto ? null : _uploadPhoto,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor:
                      hasVideo ? const Color(0xFF10B981) : const Color(0xFFF97316),
                  side: BorderSide(
                    color: hasVideo
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF97316),
                  ),
                ),
                icon: _uploadingVideo
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(hasVideo ? Icons.check : Icons.videocam_outlined),
                label: Text(hasVideo ? 'וידאו ✓' : 'וידאו'),
                onPressed: _uploadingVideo ? null : _uploadVideo,
              ),
            ),
          ],
        ),
        if (hasPhoto && _todayProof?['photoUrl'] != null) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 120,
              width: double.infinity,
              child: safeImageProvider(_todayProof!['photoUrl'] as String) != null
                  ? Image(
                      image: safeImageProvider(_todayProof!['photoUrl'] as String)!,
                      fit: BoxFit.cover,
                    )
                  : const ColoredBox(color: Color(0xFFF3F4F6)),
            ),
          ),
        ],
      ],
    );
  }
}
