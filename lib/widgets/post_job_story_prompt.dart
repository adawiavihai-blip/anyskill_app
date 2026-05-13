import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/app_localizations.dart';
import '../repositories/story_repository.dart';
import '../utils/error_mapper.dart';

/// Post-job nudge: after a provider submits their review on the customer,
/// give them a one-tap path to share the result as a Skills Story.
///
/// Shown by [showPostJobStoryPrompt], which sets `jobs/{id}.storyPromptShown`
/// before the modal opens (idempotent — same pattern as `providerReviewShown`).
///
/// The user picks "תמונה" or "וידאו"; each pre-pick on web defaults to
/// gallery (camera-on-web is unreliable), and on native shows a small
/// camera/gallery sheet — same UX as [stories_row.dart]'s upload flow.
Future<void> showPostJobStoryPrompt({
  required BuildContext context,
  required String jobId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PostJobStoryPromptSheet(jobId: jobId),
  );
}

class _PostJobStoryPromptSheet extends StatefulWidget {
  final String jobId;
  const _PostJobStoryPromptSheet({required this.jobId});

  @override
  State<_PostJobStoryPromptSheet> createState() =>
      _PostJobStoryPromptSheetState();
}

class _PostJobStoryPromptSheetState extends State<_PostJobStoryPromptSheet> {
  bool _uploading = false;
  double _progress = 0;
  final _repo = StoryRepository();

  static const _kIndigo = Color(0xFF6366F1);
  static const _kPurple = Color(0xFF8B5CF6);

  Future<void> _pick({required bool video}) async {
    final l10n = AppLocalizations.of(context);
    // Capture before await — async-safe.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final successText = l10n.postJobStorySuccess;

    // Source: web → gallery only (camera unreliable). Native → small sheet.
    ImageSource source = ImageSource.gallery;
    if (!kIsWeb) {
      final picked = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetCtx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(l10n.postJobStorySourceTitle,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _SourceTile(
                  icon: Icons.photo_library_rounded,
                  label: l10n.postJobStorySourceGallery,
                  onTap: () => Navigator.pop(sheetCtx, ImageSource.gallery),
                ),
                const SizedBox(height: 8),
                _SourceTile(
                  icon: video
                      ? Icons.videocam_rounded
                      : Icons.photo_camera_rounded,
                  label: l10n.postJobStorySourceCamera,
                  onTap: () => Navigator.pop(sheetCtx, ImageSource.camera),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
      if (picked == null) return;
      source = picked;
    }

    final picker = ImagePicker();
    final XFile? file = video
        ? await picker.pickVideo(
            source: source,
            maxDuration: const Duration(seconds: 60),
          )
        : await picker.pickImage(
            source: source,
            imageQuality: 85,
            maxWidth: 1600,
          );
    if (file == null) return;

    if (!mounted) return;
    setState(() {
      _uploading = true;
      _progress = 0;
    });

    try {
      // Read bytes — fallback to streaming on Blob URL revocation (same
      // pattern as stories_row.dart's video picker).
      Uint8List bytes;
      try {
        bytes = await file.readAsBytes();
      } catch (_) {
        final chunks = <int>[];
        await for (final chunk in file.openRead()) {
          chunks.addAll(chunk);
        }
        bytes = Uint8List.fromList(chunks);
      }

      const maxBytes = 50 * 1024 * 1024; // 50 MB
      if (bytes.length > maxBytes) {
        throw Exception(l10n.postJobStoryFileTooLarge);
      }

      final mime = file.mimeType ??
          (video ? 'video/mp4' : 'image/jpeg');

      await _repo.uploadStory(
        videoBytes: bytes,
        fileName: file.name,
        mimeType: mime,
        mediaType: video ? 'video' : 'image',
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );

      // Mark this prompt as handled so it never re-fires for this job.
      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.jobId)
          .update({'storyPromptCompleted': true}).catchError((_) {});

      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        backgroundColor: const Color(0xFF22C55E),
        behavior: SnackBarBehavior.floating,
        content: Text(successText,
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ErrorMapper.show(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 18),

            // Hero icon — gradient circle with story emoji
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [_kIndigo, _kPurple],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Center(
                child: Text('🎬', style: TextStyle(fontSize: 36)),
              ),
            ),
            const SizedBox(height: 14),

            // Title
            Text(
              l10n.postJobStoryTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.postJobStorySubtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),

            if (_uploading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation(_kIndigo),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.postJobStoryUploading,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ] else ...[
              // Two big action buttons
              Row(
                children: [
                  Expanded(
                    child: _ActionCard(
                      icon: Icons.photo_camera_rounded,
                      label: l10n.postJobStoryPhotoBtn,
                      onTap: () => _pick(video: false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionCard(
                      icon: Icons.videocam_rounded,
                      label: l10n.postJobStoryVideoBtn,
                      onTap: () => _pick(video: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF6B7280),
                ),
                child: Text(l10n.postJobStoryLater),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionCard(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SourceTile(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F7F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF6366F1), size: 22),
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
