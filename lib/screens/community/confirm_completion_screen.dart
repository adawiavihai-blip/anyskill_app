/// Mockup 05 — Requester confirms the volunteer's completion.
///
/// **When this screen is shown:**
/// - Tap on a `community_pending_confirmation` push notification
///   (handled by [NotificationRouter] — gated on
///   [isCommunityV2EnabledFor]).
/// - Phase E may add an inline action card to the requester's "Pending"
///   feed for in-app discovery.
///
/// **Data sources:**
/// - `users/{volunteerId}` for first name + avatar (referenced as
///   "{name} סיים/ה את ההתנדבות").
/// - `community_requests/{requestId}` for proof photo + optional note +
///   status (must be `pending_confirmation` to allow action).
///
/// **CTA behavior:**
/// - **Primary "אשר ותודה"**: enabled iff (rating > 0) AND (review ≥
///   10 chars). Calls [CommunityHubService.completeRequest] with the
///   rating, review, and optional thank-you note. On success, pops back.
/// - **Secondary "עוד לא"**: calls
///   [CommunityHubService.rejectCompletion] which reverts the task to
///   `in_progress`. Pops back.
///
/// **Rating writes** to `community_requests/{id}.rating` ONLY if the
/// requester actually picked stars — never defaulted (per Phase C/D-2
/// kickoff "no fake placeholders to Firestore").
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/community_hub_service.dart';
import '../../theme/community_theme.dart';
import '../../widgets/community/avatar_with_gold_heart.dart';
import '../../widgets/community/primary_button.dart';
import '../../widgets/community/secondary_button.dart';

class ConfirmCompletionScreen extends StatefulWidget {
  const ConfirmCompletionScreen({super.key, required this.requestId});
  final String requestId;

  @override
  State<ConfirmCompletionScreen> createState() =>
      _ConfirmCompletionScreenState();
}

class _ConfirmCompletionScreenState extends State<ConfirmCompletionScreen> {
  late final Future<_ConfirmData?> _future = _loadData();

  int _rating = 0;
  final _reviewCtrl = TextEditingController();
  final _thankYouCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reviewCtrl.dispose();
    _thankYouCtrl.dispose();
    super.dispose();
  }

  Future<_ConfirmData?> _loadData() async {
    try {
      final reqSnap = await FirebaseFirestore.instance
          .collection('community_requests')
          .doc(widget.requestId)
          .get();
      if (!reqSnap.exists) return null;
      final reqData = reqSnap.data() ?? {};
      final volunteerId = (reqData['volunteerId'] as String? ?? '').trim();
      if (volunteerId.isEmpty) return null;
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(volunteerId)
          .get();
      return _ConfirmData(
        requestData: reqData,
        volunteerData: userSnap.data() ?? {},
      );
    } catch (_) {
      return null;
    }
  }

  bool get _canSubmit =>
      !_busy && _rating > 0 && _reviewCtrl.text.trim().length >= 10;

  Future<void> _submit(_ConfirmData data) async {
    if (!_canSubmit) return;
    setState(() => _busy = true);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final result = await CommunityHubService.completeRequest(
      requestId: widget.requestId,
      confirmingUserId: uid,
      reviewText: _reviewCtrl.text.trim(),
      thankYouNote: _thankYouCtrl.text.trim().isEmpty
          ? null
          : _thankYouCtrl.text.trim(),
      rating: _rating,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result == 'ok' || result == 'ok_partial') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('תודה! ההתנדבות אושרה',
              style: TextStyle(fontFamily: CommunityType.fontFamily)),
          backgroundColor: CommunityColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).maybePop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result,
              style:
                  const TextStyle(fontFamily: CommunityType.fontFamily)),
          backgroundColor: CommunityColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    setState(() => _busy = true);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final err = await CommunityHubService.rejectCompletion(
      requestId: widget.requestId,
      requesterId: uid,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == null) {
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
        child: FutureBuilder<_ConfirmData?>(
          future: _future,
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
              return _ErrorView(
                onBack: () => Navigator.of(context).maybePop(),
              );
            }
            return _buildBody(data);
          },
        ),
      ),
    );
  }

  Widget _buildBody(_ConfirmData data) {
    final req = data.requestData;
    final vol = data.volunteerData;

    final volName = (vol['name'] as String? ?? '').trim();
    final volFirst = volName.split(RegExp(r'\s+')).first.isEmpty
        ? 'המתנדב/ת'
        : volName.split(RegExp(r'\s+')).first;
    final volAvatar = vol['profileImage'] as String?;
    final goldExpiry = vol['goldHeartExpiresAt'] as Timestamp?;

    final proofUrl = (req['completionPhotoUrl'] as String? ?? '').trim();

    return Column(
      children: [
        _Header(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Hero row ────────────────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AvatarWithGoldHeart(
                      imageUrl: volAvatar,
                      name: volName,
                      size: 48,
                      goldHeartExpiresAt: goldExpiry,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$volFirst סיים/ה את ההתנדבות',
                            style: const TextStyle(
                              fontFamily: CommunityType.fontFamily,
                              fontSize: 13,
                              color: CommunityColors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'האם הוא/היא באמת עזר/ה?',
                            style: TextStyle(
                              fontFamily: CommunityType.fontFamily,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                              color: CommunityColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // ── Proof photo + optional volunteer note ───────────────
                _ProofCard(
                  photoUrl: proofUrl,
                  volunteerName: volFirst,
                  // The volunteer's optional note isn't currently captured
                  // (the legacy markTaskDone has no `note` param). When
                  // added in a future PR, surface it here. For now show
                  // null → ProofCard renders nothing under the photo.
                  note: null,
                ),

                const SizedBox(height: 18),

                // ── Star rating ────────────────────────────────────────
                const Text(
                  'דרגי את ההתנדבות',
                  style: TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1,
                    color: CommunityColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (int i = 1; i <= 5; i++)
                      _StarButton(
                        active: i <= _rating,
                        onTap: () => setState(() => _rating = i),
                      ),
                  ],
                ),

                const SizedBox(height: 18),

                // ── Review (10+ chars) ─────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'ביקורת קצרה',
                      style: TextStyle(
                        fontFamily: CommunityType.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                        color: CommunityColors.textPrimary,
                      ),
                    ),
                    Builder(builder: (_) {
                      final len = _reviewCtrl.text.trim().length;
                      final ok = len >= CommunityHubService.minReviewLength;
                      return Text(
                        '$len / ${CommunityHubService.minReviewLength} מינ׳',
                        style: TextStyle(
                          fontFamily: CommunityType.fontFamily,
                          fontSize: 10,
                          color: ok
                              ? CommunityColors.success
                              : CommunityColors.warningText,
                        ),
                      );
                    }),
                  ],
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
                    controller: _reviewCtrl,
                    maxLines: 3,
                    minLines: 3,
                    onChanged: (_) => setState(() {}),
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
                      hintText: 'מה היה טוב? מה אהבת?',
                      hintStyle: TextStyle(
                        fontFamily: CommunityType.fontFamily,
                        fontSize: 13,
                        color: CommunityColors.textMuted,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // ── Optional thank-you note (gold tinted) ──────────────
                Row(
                  children: [
                    const Text(
                      'פתק תודה',
                      style: TextStyle(
                        fontFamily: CommunityType.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                        color: CommunityColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      '(לא חובה)',
                      style: TextStyle(
                        fontFamily: CommunityType.fontFamily,
                        fontSize: 12,
                        color: CommunityColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: CommunityColors.goldHeartBg,
                    border: Border.all(
                      color: const Color(0x40A87F2A), // gold @ 25%
                      width: 0.5,
                    ),
                    borderRadius:
                        const BorderRadius.all(CommunityRadius.field),
                  ),
                  child: TextField(
                    controller: _thankYouCtrl,
                    maxLines: 2,
                    minLines: 2,
                    style: const TextStyle(
                      fontFamily: CommunityType.fontFamily,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: CommunityColors.goldHeartText,
                      height: 1.5,
                    ),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      border: InputBorder.none,
                      hintText: 'תודה רבה!',
                      hintStyle: TextStyle(
                        fontFamily: CommunityType.fontFamily,
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: Color(0x80A87F2A), // gold @ 50%
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'יוצג בפרופיל הציבורי של המתנדב/ת',
                  style: TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 10,
                    color: CommunityColors.textMuted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        _BottomCta(
          canSubmit: _canSubmit,
          isBusy: _busy,
          onSubmit: () => _submit(data),
          onReject: _reject,
        ),
      ],
    );
  }
}

class _ConfirmData {
  _ConfirmData({required this.requestData, required this.volunteerData});
  final Map<String, dynamic> requestData;
  final Map<String, dynamic> volunteerData;
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
                'אישור התנדבות',
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

// ── Star button ───────────────────────────────────────────────────────────
class _StarButton extends StatelessWidget {
  const _StarButton({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            active ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 28,
            color: active
                ? CommunityColors.starGold
                : CommunityColors.textMuted,
          ),
        ),
      ),
    );
  }
}

// ── Proof photo card ──────────────────────────────────────────────────────
class _ProofCard extends StatelessWidget {
  const _ProofCard({
    required this.photoUrl,
    required this.volunteerName,
    required this.note,
  });

  final String photoUrl;
  final String volunteerName;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: CommunityDecorations.cardSoft,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: photoUrl.isEmpty
                ? Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFE7E5E4), Color(0xFFD6D3D1)],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.image_outlined,
                      size: 32,
                      color: Color(0x40000000),
                    ),
                  )
                : Image.network(
                    photoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFFE7E5E4),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.broken_image_outlined,
                        color: Color(0x40000000),
                        size: 32,
                      ),
                    ),
                  ),
          ),
          if (note != null && note!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'הערה מ$volunteerName',
                    style: const TextStyle(
                      fontFamily: CommunityType.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                      color: CommunityColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    note!,
                    style: const TextStyle(
                      fontFamily: CommunityType.fontFamily,
                      fontSize: 13,
                      color: CommunityColors.textPrimary,
                      height: 1.5,
                      letterSpacing: -0.1,
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

// ── Sticky bottom CTA bar ─────────────────────────────────────────────────
class _BottomCta extends StatelessWidget {
  const _BottomCta({
    required this.canSubmit,
    required this.isBusy,
    required this.onSubmit,
    required this.onReject,
  });

  final bool canSubmit;
  final bool isBusy;
  final VoidCallback onSubmit;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: CommunityDecorations.footerWithTopDivider,
      child: Row(
        children: [
          CommunitySecondaryButton(
            label: 'עוד לא',
            onPressed: isBusy ? null : onReject,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: CommunityPrimaryButton(
              label: 'אשר ותודה',
              isLoading: isBusy,
              onPressed: canSubmit ? onSubmit : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 28, color: CommunityColors.textTertiary),
            const SizedBox(height: 12),
            const Text(
              'לא הצלחנו לטעון את פרטי ההתנדבות',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: CommunityType.fontFamily,
                fontSize: 14,
                color: CommunityColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            CommunitySecondaryButton(label: 'חזרה', onPressed: onBack),
          ],
        ),
      ),
    );
  }
}
