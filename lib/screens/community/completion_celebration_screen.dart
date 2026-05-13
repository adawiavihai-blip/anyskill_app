/// Mockup 06 — Volunteer's celebration after the requester confirms.
///
/// **When this screen is shown:**
/// - Tap on a `community_completed` push notification (handled by
///   [NotificationRouter] — gated on [isCommunityV2EnabledFor]).
/// - Phase D will additionally auto-push it from the volunteer's open
///   active-tasks stream when their pending task transitions to completed.
///
/// **Data sources:**
/// - `users/{volunteerUid}` — for first name, total `volunteerTaskCount`,
///   and `goldHeartExpiresAt`.
/// - `community_requests/{requestId}` — for the requester name (in the
///   subtitle) and the optional `thankYouNote`.
///
/// **CTA behavior:**
/// - Primary "צפה בהתנדבויות נוספות": if this is the volunteer's first
///   ever completion (`volunteerTaskCount == 1`) → push
///   [FirstGoldHeartScreen]. Otherwise pop back to the previous route
///   (or fall through to root if pushed from cold-start notification).
/// - Ghost "חזרה לבית": always pops to the first route.
///
/// **Rating placeholder:** mockup shows "דירוג שקיבלת 5.0". Per the
/// Phase C kickoff (שאלה 1, אופציה א), the rating is a DISPLAY-ONLY
/// placeholder until Phase D ships the requester-side capture in
/// mockup 05. We never write a fake rating to Firestore.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../theme/community_theme.dart';
import '../../utils/gold_heart_helper.dart';
import 'first_gold_heart_screen.dart';

class CompletionCelebrationScreen extends StatefulWidget {
  const CompletionCelebrationScreen({
    super.key,
    required this.requestId,
  });

  final String requestId;

  @override
  State<CompletionCelebrationScreen> createState() =>
      _CompletionCelebrationScreenState();
}

class _CompletionCelebrationScreenState
    extends State<CompletionCelebrationScreen> {
  late final Future<_CelebrationData?> _future = _loadData();

  Future<_CelebrationData?> _loadData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('users').doc(uid).get(),
        FirebaseFirestore.instance
            .collection('community_requests')
            .doc(widget.requestId)
            .get(),
      ]);
      final userSnap = results[0];
      final reqSnap  = results[1];
      if (!userSnap.exists || !reqSnap.exists) return null;
      return _CelebrationData(
        userData:    userSnap.data() ?? {},
        requestData: reqSnap.data() ?? {},
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CommunityColors.darkSurface,
      body: SafeArea(
        child: FutureBuilder<_CelebrationData?>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(CommunityColors.goldHeart),
                ),
              );
            }
            final data = snap.data;
            if (data == null) {
              // Graceful fallback — back button only, no fake celebration.
              return _ErrorView(
                onBack: () => Navigator.of(context).maybePop(),
              );
            }
            return _CelebrationBody(
              data: data,
              onPrimaryCta: () => _handlePrimaryCta(data),
              onGhostCta: () => Navigator.of(context)
                  .popUntil((r) => r.isFirst),
            );
          },
        ),
      ),
    );
  }

  void _handlePrimaryCta(_CelebrationData data) {
    final count = (data.userData['volunteerTaskCount'] as num? ?? 0).toInt();
    if (count <= 1) {
      // First-ever completion — push the dedicated first-heart screen.
      // (Use `<=` so a tx race that didn't increment yet still routes here.)
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const FirstGoldHeartScreen(),
        ),
      );
    } else {
      Navigator.of(context).maybePop();
    }
  }
}

class _CelebrationData {
  _CelebrationData({required this.userData, required this.requestData});
  final Map<String, dynamic> userData;
  final Map<String, dynamic> requestData;
}

// ─────────────────────────────────────────────────────────────────────────────

class _CelebrationBody extends StatelessWidget {
  const _CelebrationBody({
    required this.data,
    required this.onPrimaryCta,
    required this.onGhostCta,
  });

  final _CelebrationData data;
  final VoidCallback onPrimaryCta;
  final VoidCallback onGhostCta;

  @override
  Widget build(BuildContext context) {
    final user = data.userData;
    final req  = data.requestData;

    final volunteerName = (user['name'] as String? ?? '').trim();
    final firstName = volunteerName.split(RegExp(r'\s+')).first.isNotEmpty
        ? volunteerName.split(RegExp(r'\s+')).first
        : 'מתנדב/ת';

    final requesterName = (req['requesterName'] as String? ?? '').trim();
    final requesterDisplay =
        requesterName.isEmpty ? 'הפונה' : requesterName.split(RegExp(r'\s+')).first;

    final taskCount = (user['volunteerTaskCount'] as num? ?? 0).toInt();
    final expiresAt = user['goldHeartExpiresAt'] as Timestamp?;
    final expiryHe  = GoldHeartHelper.expiryDateHebrew(expiresAt);

    final note = (req['thankYouNote'] as String? ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _heroIcon(),
                const SizedBox(height: 24),
                const Text(
                  'התנדבות הושלמה',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    color: Color(0xE6A87F2A), // gold @ ~90%
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'תודה שעזרת,\n$firstName',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                    height: 1.25,
                    color: CommunityColors.whiteHigh,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$requesterDisplay אישר/ה את ההתנדבות. הנה ההשפעה שלך.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 13,
                    color: CommunityColors.whiteMid,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                _StatRow(label: 'XP שהורווח',     value: '+450'),
                _StatRow(label: 'סה״כ התנדבויות', value: '$taskCount'),
                _StatRow(
                  label: 'לב זהב פעיל עד',
                  value: expiryHe ?? '—',
                  valueColor: const Color(0xF2A87F2A), // gold @ ~95%
                ),
                _StatRow(
                  label: 'דירוג שקיבלת',
                  // Phase D-2 (v15.x): rating now read from the real
                  // `community_requests/{id}.rating` field set by the
                  // requester via mockup 05. Renders "—" when absent so
                  // we never display a fake value.
                  valueWidget: Builder(builder: (_) {
                    final r = req['rating'];
                    final has = r is num && r >= 1 && r <= 5;
                    if (!has) {
                      return const Text(
                        '—',
                        style: TextStyle(
                          fontFamily: CommunityType.fontFamily,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: CommunityColors.whiteMid,
                        ),
                      );
                    }
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 13, color: CommunityColors.starGold),
                        const SizedBox(width: 4),
                        Text(
                          r.toDouble().toStringAsFixed(1),
                          style: const TextStyle(
                            fontFamily: CommunityType.fontFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            color: CommunityColors.whiteHigh,
                          ),
                        ),
                      ],
                    );
                  }),
                  isLast: true,
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _ThankYouNote(
                    requesterDisplay: requesterDisplay,
                    note: note,
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            children: [
              _whiteCta(label: 'צפה בהתנדבויות נוספות', onPressed: onPrimaryCta),
              const SizedBox(height: 8),
              TextButton(
                onPressed: onGhostCta,
                style: TextButton.styleFrom(
                  minimumSize: const Size(double.infinity, 40),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: const Text(
                  'חזרה לבית',
                  style: TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 12,
                    color: CommunityColors.whiteMid,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Hero gold-heart medallion ──────────────────────────────────────────
  Widget _heroIcon() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: CommunityColors.goldHeartLight,
        border: Border.all(
          color: const Color(0x4DA87F2A), // gold @ 30%
          width: 0.5,
        ),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.favorite,
        color: CommunityColors.goldHeart,
        size: 36,
      ),
    );
  }

  /// Mockup 06 uses a white pill button on the dark background.
  Widget _whiteCta({required String label, required VoidCallback onPressed}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: CommunityColors.primaryWhite,
          foregroundColor: CommunityColors.textPrimary,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(CommunityRadius.pill),
          ),
          minimumSize: const Size(double.infinity, 46),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: CommunityType.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }
}

// ── Inline stat row with bottom divider, on dark background ────────────────
class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    this.value,
    this.valueWidget,
    this.valueColor = CommunityColors.whiteHigh,
    this.isLast = false,
  }) : assert(value != null || valueWidget != null);

  final String label;
  final String? value;
  final Widget? valueWidget;
  final Color valueColor;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : const BorderSide(
                  color: Color(0x14FFFFFF), // 8% white
                  width: 0.5,
                ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: CommunityType.fontFamily,
                fontSize: 12,
                color: CommunityColors.whiteMid,
              ),
            ),
          ),
          if (valueWidget != null)
            valueWidget!
          else
            Text(
              value!,
              style: TextStyle(
                fontFamily: CommunityType.fontFamily,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: valueColor,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Thank-you note card with gold tint ────────────────────────────────────
class _ThankYouNote extends StatelessWidget {
  const _ThankYouNote({required this.requesterDisplay, required this.note});

  final String requesterDisplay;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x14A87F2A), // gold @ 8%
        borderRadius: const BorderRadius.all(CommunityRadius.card),
        border: Border.all(
          color: const Color(0x33A87F2A), // gold @ 20%
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 12,
                color: Color(0xB3A87F2A), // gold @ 70%
              ),
              const SizedBox(width: 6),
              Text(
                'פתק תודה מ$requesterDisplay',
                style: const TextStyle(
                  fontFamily: CommunityType.fontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: Color(0xE6A87F2A), // gold @ 90%
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '"$note"',
            style: const TextStyle(
              fontFamily: CommunityType.fontFamily,
              fontSize: 13,
              fontStyle: FontStyle.italic,
              height: 1.55,
              color: CommunityColors.whiteHigh,
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: CommunityColors.whiteMid, size: 28),
          const SizedBox(height: 12),
          const Text(
            'לא הצלחנו לטעון את פרטי ההתנדבות',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: CommunityType.fontFamily,
              fontSize: 14,
              color: CommunityColors.whiteMid,
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: onBack,
            child: const Text(
              'חזרה',
              style: TextStyle(
                fontFamily: CommunityType.fontFamily,
                color: CommunityColors.whiteHigh,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
