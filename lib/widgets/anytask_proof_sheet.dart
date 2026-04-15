/// AnyTasks 3.0 — Proof Submission Bottom Sheet
///
/// Bottom sheet for providers to submit completion proof (photo + text).
/// Uses image_picker for camera/gallery, uploads to Firebase Storage.
library;

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

class AnytaskProofSheet extends StatefulWidget {
  final String taskId;
  final String taskTitle;

  const AnytaskProofSheet({
    super.key,
    required this.taskId,
    required this.taskTitle,
  });

  /// Shows the sheet and returns the proof photo URL + optional text,
  /// or null if cancelled.
  static Future<ProofResult?> show(
    BuildContext context, {
    required String taskId,
    required String taskTitle,
  }) {
    return showModalBottomSheet<ProofResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AnytaskProofSheet(taskId: taskId, taskTitle: taskTitle),
    );
  }

  @override
  State<AnytaskProofSheet> createState() => _AnytaskProofSheetState();
}

class _AnytaskProofSheetState extends State<AnytaskProofSheet> {
  static const _kGreen  = Color(0xFF10B981);
  static const _kDark   = Color(0xFF1A1A2E);
  static const _kMuted  = Color(0xFF6B7280);
  static const _kIndigo = Color(0xFF6366F1);

  final _textCtrl = TextEditingController();
  XFile? _pickedImage;
  bool _uploading = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final xFile = await picker.pickImage(
        source: source,
        maxWidth: 1200,
        imageQuality: 70,
      );
      if (xFile != null && mounted) {
        setState(() => _pickedImage = xFile);
      }
    } catch (e) {
      debugPrint('[AnytaskProofSheet] pickImage error: $e');
    }
  }

  Future<void> _submit() async {
    if (_pickedImage == null) return;

    setState(() => _uploading = true);

    try {
      // Upload to Firebase Storage
      final ext = _pickedImage!.path.split('.').last;
      final ref = FirebaseStorage.instance
          .ref('anytask_proofs/${widget.taskId}/proof_${DateTime.now().millisecondsSinceEpoch}.$ext');

      UploadTask uploadTask;
      if (kIsWeb) {
        final bytes = await _pickedImage!.readAsBytes();
        uploadTask = ref.putData(bytes, SettableMetadata(contentType: 'image/$ext'));
      } else {
        uploadTask = ref.putFile(File(_pickedImage!.path));
      }

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      if (mounted) {
        Navigator.pop(
          context,
          ProofResult(
            photoUrl: downloadUrl,
            text: _textCtrl.text.trim().isEmpty ? null : _textCtrl.text.trim(),
          ),
        );
      }
    } catch (e) {
      debugPrint('[AnytaskProofSheet] upload error: $e');
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('שגיאה בהעלאת התמונה. נסה שוב.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              const Icon(Icons.camera_alt_rounded, color: _kIndigo, size: 48),
              const SizedBox(height: 12),
              const Text(
                'שלח הוכחת ביצוע',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kDark),
              ),
              const SizedBox(height: 4),
              Text(
                widget.taskTitle,
                style: const TextStyle(fontSize: 13, color: _kMuted),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),

              // ── Photo picker ────────────────────────────────────────────
              if (_pickedImage == null)
                Row(
                  children: [
                    Expanded(
                      child: _PickerButton(
                        icon: Icons.camera_alt_rounded,
                        label: 'מצלמה',
                        onTap: () => _pickImage(ImageSource.camera),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PickerButton(
                        icon: Icons.photo_library_rounded,
                        label: 'גלריה',
                        onTap: () => _pickImage(ImageSource.gallery),
                      ),
                    ),
                  ],
                )
              else
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: kIsWeb
                          ? Image.network(
                              _pickedImage!.path,
                              height: 180,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            )
                          : Image.file(
                              File(_pickedImage!.path),
                              height: 180,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: GestureDetector(
                        onTap: () => setState(() => _pickedImage = null),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 16),

              // ── Text note (optional) ────────────────────────────────────
              TextField(
                controller: _textCtrl,
                maxLines: 3,
                textAlign: TextAlign.start,
                decoration: InputDecoration(
                  hintText: 'הוסף הערה (לא חובה)',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _kIndigo, width: 2),
                  ),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
              const SizedBox(height: 20),

              // ── Submit button ───────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: (_pickedImage != null && !_uploading) ? _submit : null,
                  icon: _uploading
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 20),
                  label: Text(
                    _uploading ? 'מעלה...' : 'שלח הוכחה',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
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

class _PickerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PickerButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F7F9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: const Color(0xFF6366F1)),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Result returned from the proof sheet.
class ProofResult {
  final String photoUrl;
  final String? text;
  const ProofResult({required this.photoUrl, this.text});
}
