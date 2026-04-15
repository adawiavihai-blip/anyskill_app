/// AnySkill — Feed Composer Buttons (Pet Stay Tracker v13.0.0, Step 7)
///
/// Row of three buttons on the provider Pet Mode screen:
///   📸 תמונה  |  🎥 וידאו  |  📝 הערה
///
/// Each button wraps a tap handler that performs the pick / upload /
/// Firestore write via [PetUpdateService]. Errors surface via
/// ScaffoldMessenger snackbars.
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../utils/image_compressor.dart';
import '../services/pet_update_service.dart';

class FeedComposer extends StatefulWidget {
  final String jobId;
  final String customerId;
  final String expertId;

  const FeedComposer({
    super.key,
    required this.jobId,
    required this.customerId,
    required this.expertId,
  });

  @override
  State<FeedComposer> createState() => _FeedComposerState();
}

class _FeedComposerState extends State<FeedComposer> {
  bool _busyPhoto = false;
  bool _busyVideo = false;
  bool _busyNote = false;

  Future<void> _pickPhoto() async {
    setState(() => _busyPhoto = true);
    try {
      final picked = await ImageCompressor.pick(
        ImagePreset.chatImage,
        source: ImageSource.camera,
      );
      if (picked == null) return;
      if (!mounted) return;
      final caption = await _askCaption('הוסף כיתוב (אופציונלי)');
      if (!mounted) return;
      await PetUpdateService.instance.uploadPhoto(
        jobId: widget.jobId,
        customerId: widget.customerId,
        expertId: widget.expertId,
        bytes: picked.bytes,
        ext: picked.ext,
        caption: caption,
      );
      if (!mounted) return;
      _ok('📸 התמונה נשלחה');
    } catch (e) {
      _err('שגיאה: $e');
    } finally {
      if (mounted) setState(() => _busyPhoto = false);
    }
  }

  Future<void> _pickVideo() async {
    setState(() => _busyVideo = true);
    try {
      final picker = ImagePicker();
      final file = await picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(seconds: 30),
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final ext = file.name.contains('.')
          ? file.name.split('.').last.toLowerCase()
          : 'mp4';
      if (!mounted) return;
      final caption = await _askCaption('הוסף כיתוב (אופציונלי)');
      if (!mounted) return;
      await PetUpdateService.instance.uploadVideo(
        jobId: widget.jobId,
        customerId: widget.customerId,
        expertId: widget.expertId,
        bytes: bytes,
        ext: ext,
        caption: caption,
      );
      if (!mounted) return;
      _ok('🎥 הווידאו נשלח');
    } catch (e) {
      _err('שגיאה: $e');
    } finally {
      if (mounted) setState(() => _busyVideo = false);
    }
  }

  Future<void> _writeNote() async {
    final text = await _askCaption('כתוב הערה', multiline: true);
    if (text == null || text.trim().isEmpty) return;
    setState(() => _busyNote = true);
    try {
      await PetUpdateService.instance.writeNote(
        jobId: widget.jobId,
        customerId: widget.customerId,
        expertId: widget.expertId,
        text: text,
      );
      if (!mounted) return;
      _ok('📝 ההערה נשלחה');
    } catch (e) {
      _err('שגיאה: $e');
    } finally {
      if (mounted) setState(() => _busyNote = false);
    }
  }

  Future<String?> _askCaption(String title,
      {bool multiline = false}) async {
    final ctrl = TextEditingController();
    return showDialog<String?>(
      context: context,
      builder: (c) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: multiline ? 4 : 1,
            minLines: multiline ? 3 : 1,
            decoration: const InputDecoration(
              hintText: 'הקלד/י כאן...',
            ),
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
        );
      },
    );
  }

  void _ok(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _err(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'שתף עם הבעלים',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _btn(
                  icon: Icons.camera_alt_rounded,
                  label: '📸 תמונה',
                  color: const Color(0xFF2563EB),
                  busy: _busyPhoto,
                  onTap: _pickPhoto,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _btn(
                  icon: Icons.videocam_rounded,
                  label: '🎥 וידאו',
                  color: const Color(0xFF7C3AED),
                  busy: _busyVideo,
                  onTap: _pickVideo,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _btn(
                  icon: Icons.edit_note_rounded,
                  label: '📝 הערה',
                  color: const Color(0xFFEA580C),
                  busy: _busyNote,
                  onTap: _writeNote,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _btn({
    required IconData icon,
    required String label,
    required Color color,
    required bool busy,
    required VoidCallback onTap,
  }) {
    final disabled = _busyPhoto || _busyVideo || _busyNote;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color, width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      onPressed: disabled ? null : onTap,
      child: busy
          ? SizedBox(
              width: 18,
              height: 18,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          : Text(
              label,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
    );
  }
}
