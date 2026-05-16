/// Mockup 04 — Volunteer marks the task as completed by uploading a
/// proof photo.
///
/// **When this screen is shown:**
/// - From `MyVolunteeringContent` "סיימתי" CTA on a card whose status
///   is `in_progress`.
///
/// **Flow:**
/// 1. Loads `community_requests/{id}` to render the summary card +
///    compute the elapsed-since-start time (the 15-minute minimum is
///    enforced on the server in [CommunityHubService.markTaskDone] —
///    we just SHOW the elapsed minutes here so the volunteer knows
///    they're past the threshold).
/// 2. User picks a photo (camera by default, gallery as fallback) →
///    uploads to Firebase Storage at
///    `community_evidence/{requestId}/{timestamp}.jpg` — participant-
///    gated by the parent community_requests doc (pen-test fix VULN-009).
/// 3. User taps "סיימתי לעזור" → calls
///    [CommunityHubService.markTaskDone] with the URL. On success the
///    request transitions to `pending_confirmation` and the requester
///    receives a notification.
///
/// **Privacy guard:** the blue alert text reminds volunteers not to
/// photograph faces without consent — same wording as mockup 04.
library;

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/community_hub_service.dart';
import '../../theme/community_theme.dart';
import '../../widgets/community/primary_button.dart';
import '../../widgets/community/secondary_button.dart';

class CompleteVolunteeringScreen extends StatefulWidget {
  const CompleteVolunteeringScreen({super.key, required this.requestId});
  final String requestId;

  @override
  State<CompleteVolunteeringScreen> createState() =>
      _CompleteVolunteeringScreenState();
}

class _CompleteVolunteeringScreenState
    extends State<CompleteVolunteeringScreen> {
  late final Future<Map<String, dynamic>?> _requestFuture = _loadRequest();

  Uint8ListLite? _pickedBytes;
  String? _uploadedUrl;
  bool _busyUpload = false;
  bool _busySubmit = false;

  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _loadRequest() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('community_requests')
          .doc(widget.requestId)
          .get();
      if (!snap.exists) return null;
      return snap.data() ?? {};
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickPhoto({required ImageSource source}) async {
    if (_busyUpload || _busySubmit) return;
    try {
      setState(() => _busyUpload = true);
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 1600,
      );
      if (xfile == null) {
        if (mounted) setState(() => _busyUpload = false);
        return;
      }
      // Read bytes once — keeps the preview snappy on web where File
      // path doesn't exist.
      final bytes = await xfile.readAsBytes();
      _pickedBytes = Uint8ListLite(bytes);

      // Upload immediately so the submit CTA can fire fast.
      // Pen-test fix VULN-009: nested-path layout so the Storage rule can
      // gate read+write by the parent community_requests participants.
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance.ref(
        'community_evidence/${widget.requestId}/$ts.jpg',
      );
      await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() {
        _uploadedUrl = url;
        _busyUpload = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busyUpload = false;
        _pickedBytes = null;
        _uploadedUrl = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('העלאת התמונה נכשלה: $e',
              style: const TextStyle(fontFamily: CommunityType.fontFamily)),
          backgroundColor: CommunityColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showPickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: CommunityColors.primaryWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: CommunityRadius.sheet),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0x14000000),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: CommunityColors.textPrimary),
              title: const Text(
                'צלם עכשיו',
                style: TextStyle(
                  fontFamily: CommunityType.fontFamily,
                  fontSize: 14,
                  color: CommunityColors.textPrimary,
                ),
              ),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _pickPhoto(source: ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: CommunityColors.textPrimary),
              title: const Text(
                'בחר מהגלריה',
                style: TextStyle(
                  fontFamily: CommunityType.fontFamily,
                  fontSize: 14,
                  color: CommunityColors.textPrimary,
                ),
              ),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _pickPhoto(source: ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  bool get _canSubmit =>
      _uploadedUrl != null && !_busyUpload && !_busySubmit;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _busySubmit = true);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final err = await CommunityHubService.markTaskDone(
      requestId: widget.requestId,
      volunteerId: uid,
      completionPhotoUrl: _uploadedUrl!,
    );
    if (!mounted) return;
    setState(() => _busySubmit = false);
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'מעולה! הפונה יקבל/ת התראה לאשר את הסיום',
            style: TextStyle(fontFamily: CommunityType.fontFamily),
          ),
          backgroundColor: CommunityColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).maybePop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err,
              style: const TextStyle(fontFamily: CommunityType.fontFamily)),
          backgroundColor: CommunityColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CommunityColors.primaryWhite,
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>?>(
          future: _requestFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            final data = snap.data;
            if (data == null) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'לא הצלחנו לטעון את פרטי ההתנדבות',
                    style: TextStyle(
                      fontFamily: CommunityType.fontFamily,
                      color: CommunityColors.textSecondary,
                    ),
                  ),
                ),
              );
            }
            return _buildBody(data);
          },
        ),
      ),
    );
  }

  Widget _buildBody(Map<String, dynamic> data) {
    final requesterName = (data['requesterName'] as String? ?? '').trim();
    final requesterFirst = requesterName.split(RegExp(r'\s+')).first.isEmpty
        ? 'הפונה'
        : requesterName.split(RegExp(r'\s+')).first;

    return Column(
      children: [
        _Header(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'סיימת לעזור?',
                  style: CommunityType.h22,
                ),
                const SizedBox(height: 6),
                Text(
                  'צרף תמונה כהוכחה ל$requesterFirst. ההתנדבות תאושר תוך 15 דקות.',
                  style: CommunityType.body13.copyWith(
                    color: CommunityColors.textTertiary,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 20),
                _SummaryCard(data: data, requesterFirst: requesterFirst),
                const SizedBox(height: 16),
                const Text(
                  'תמונת הוכחה',
                  style: TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1,
                    color: CommunityColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                _PhotoArea(
                  busy: _busyUpload,
                  url: _uploadedUrl,
                  bytes: _pickedBytes,
                  onTap: _showPickerSheet,
                ),
                const SizedBox(height: 12),
                const _PrivacyAlert(),
                const SizedBox(height: 18),
                Text(
                  'הערה ל$requesterFirst (לא חובה)',
                  style: const TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1,
                    color: CommunityColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: CommunityColors.surface,
                    border: Border.all(
                        color: const Color(0x14000000), width: 0.5),
                    borderRadius:
                        const BorderRadius.all(CommunityRadius.field),
                  ),
                  child: TextField(
                    controller: _noteCtrl,
                    maxLines: 2,
                    minLines: 2,
                    style: const TextStyle(
                      fontFamily: CommunityType.fontFamily,
                      fontSize: 13,
                      color: CommunityColors.textPrimary,
                      height: 1.5,
                    ),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      border: InputBorder.none,
                      hintText: 'הקניות בדירה. תרגישי טוב!',
                      hintStyle: TextStyle(
                        fontFamily: CommunityType.fontFamily,
                        fontSize: 13,
                        color: CommunityColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          decoration: CommunityDecorations.footerWithTopDivider,
          child: Row(
            children: [
              CommunitySecondaryButton(
                label: 'ביטול',
                onPressed: _busySubmit
                    ? null
                    : () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CommunityPrimaryButton(
                  label: 'סיימתי לעזור',
                  isLoading: _busySubmit,
                  onPressed: _canSubmit ? _submit : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: CommunityColors.borderSofter, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            iconSize: 18,
            color: CommunityColors.textPrimary,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'סיום התנדבות',
                style: TextStyle(
                  fontFamily: CommunityType.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1,
                  color: CommunityColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 26),
        ],
      ),
    );
  }
}

// ── Summary card showing elapsed time vs 15-min minimum ────────────────────
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.data, required this.requesterFirst});

  final Map<String, dynamic> data;
  final String requesterFirst;

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String? ?? 'התנדבות';
    final startedAt = data['startedAt'] as Timestamp?;
    final startTimeStr = startedAt == null
        ? '—'
        : _hhmm(startedAt.toDate());
    final elapsed = startedAt == null
        ? null
        : DateTime.now().difference(startedAt.toDate()).inMinutes;
    final isOk = elapsed != null &&
        elapsed >= CommunityHubService.minTaskDurationMinutes;
    final elapsedColor = isOk
        ? CommunityColors.success
        : CommunityColors.warningText;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: CommunityDecorations.cardSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ההתנדבות',
            style: TextStyle(
              fontFamily: CommunityType.fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
              color: CommunityColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontFamily: CommunityType.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: CommunityColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                requesterFirst,
                style: const TextStyle(
                  fontFamily: CommunityType.fontFamily,
                  fontSize: 11,
                  color: CommunityColors.textTertiary,
                ),
              ),
              const SizedBox(width: 8),
              _dot(),
              const SizedBox(width: 8),
              Text(
                'התחיל ב-$startTimeStr',
                style: const TextStyle(
                  fontFamily: CommunityType.fontFamily,
                  fontSize: 11,
                  color: CommunityColors.textTertiary,
                ),
              ),
              if (elapsed != null) ...[
                const SizedBox(width: 8),
                _dot(),
                const SizedBox(width: 8),
                Text(
                  "$elapsed דק'",
                  style: TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: elapsedColor,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static Widget _dot() => Container(
        width: 2,
        height: 2,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFFD4D4D8),
        ),
      );

  static String _hhmm(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ── Photo upload area ─────────────────────────────────────────────────────
class _PhotoArea extends StatelessWidget {
  const _PhotoArea({
    required this.busy,
    required this.url,
    required this.bytes,
    required this.onTap,
  });

  final bool busy;
  final String? url;
  final Uint8ListLite? bytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = url != null || bytes != null;

    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: const BorderRadius.all(CommunityRadius.card),
      child: Container(
        width: double.infinity,
        height: 180,
        decoration: BoxDecoration(
          color: CommunityColors.surface,
          border: Border.all(
            color: const Color(0x26000000), // ~15% black for dashed feel
            width: 1,
          ),
          borderRadius: const BorderRadius.all(CommunityRadius.card),
        ),
        clipBehavior: Clip.antiAlias,
        child: hasPhoto
            ? Stack(
                fit: StackFit.expand,
                children: [
                  if (bytes != null)
                    Image.memory(bytes!.data, fit: BoxFit.cover)
                  else
                    Image.network(url!, fit: BoxFit.cover),
                  if (busy)
                    Container(
                      color: const Color(0x80000000),
                      alignment: Alignment.center,
                      child: const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              CommunityColors.primaryWhite),
                        ),
                      ),
                    )
                  else
                    Positioned(
                      bottom: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius:
                              const BorderRadius.all(CommunityRadius.pill),
                        ),
                        child: const Text(
                          'החלף תמונה',
                          style: TextStyle(
                            fontFamily: CommunityType.fontFamily,
                            fontSize: 11,
                            color: CommunityColors.primaryWhite,
                          ),
                        ),
                      ),
                    ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: CommunityColors.primaryWhite,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: CommunityColors.borderSubtle, width: 0.5),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.photo_camera_outlined,
                      size: 20,
                      color: CommunityColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'צלם תמונה',
                    style: TextStyle(
                      fontFamily: CommunityType.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1,
                      color: CommunityColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    kIsWeb ? 'או בחר מהגלריה' : 'או גרור קובץ לכאן',
                    style: const TextStyle(
                      fontFamily: CommunityType.fontFamily,
                      fontSize: 11,
                      color: CommunityColors.textMuted,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Privacy alert ─────────────────────────────────────────────────────────
class _PrivacyAlert extends StatelessWidget {
  const _PrivacyAlert();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CommunityColors.infoBg,
        border: Border.all(
          color: const Color(0x33_0EA5E9), // info @ 20%
          width: 0.5,
        ),
        borderRadius: const BorderRadius.all(CommunityRadius.field),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.info_outline_rounded,
              size: 14,
              color: CommunityColors.infoText,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'תמונה כללית בלבד',
                  style: TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: CommunityColors.infoTextDeep,
                    height: 1.55,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'לא לצלם פנים ללא רשות. צלם את המקום, האובייקט, או התוצאה.',
                  style: TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 11,
                    color: CommunityColors.infoText,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lightweight wrapper around `Uint8List` so we don't need to import
/// `dart:typed_data` at the call sites — keeps the file imports tight.
class Uint8ListLite {
  Uint8ListLite(this.data);
  final Uint8List data;
}
