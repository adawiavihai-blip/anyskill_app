/// Mockup 02 — Request detail screen.
///
/// **When this screen is shown:**
/// - From [CommunityHubScreenV2] open-requests feed → tap on a card.
///
/// **Data sources:**
/// - `community_requests/{requestId}` for title/desc/category/urgency.
/// - `users/{requesterId}` for the "מי ביקש/ה" section (name + tenure).
///
/// **Primary CTA "אני יכול/ה להתנדב":**
/// - Calls [CommunityHubService.claimRequest] inside a confirm dialog.
/// - On success, opens the existing [ChatScreen] with the requester so
///   the volunteer can coordinate. (Per CLAUDE.md §47/§54 we do NOT fork
///   the chat screen — reuse the existing one.)
/// - On any error, shows a friendly Hebrew snackbar via the service's
///   own error string.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/community_hub_service.dart';
import '../../theme/community_theme.dart';
import '../../widgets/community/primary_button.dart';
import '../chat_screen.dart';

class RequestDetailScreen extends StatefulWidget {
  const RequestDetailScreen({super.key, required this.requestId});
  final String requestId;

  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen> {
  late final Future<_DetailData?> _future = _loadData();
  bool _claiming = false;

  Future<_DetailData?> _loadData() async {
    try {
      final reqSnap = await FirebaseFirestore.instance
          .collection('community_requests')
          .doc(widget.requestId)
          .get();
      if (!reqSnap.exists) return null;
      final reqData = reqSnap.data() ?? {};
      final requesterId = (reqData['requesterId'] as String? ?? '').trim();
      Map<String, dynamic> requesterData = {};
      if (requesterId.isNotEmpty) {
        try {
          final userSnap = await FirebaseFirestore.instance
              .collection('users')
              .doc(requesterId)
              .get();
          requesterData = userSnap.data() ?? {};
        } catch (_) {/* tolerate missing user doc */}
      }
      return _DetailData(
        requestData: reqData,
        requesterData: requesterData,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _claim(_DetailData data) async {
    if (_claiming) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: CommunityColors.primaryWhite,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(CommunityRadius.cardLg),
        ),
        title: const Text(
          'להתנדב לעזרה זו?',
          style: TextStyle(
            fontFamily: CommunityType.fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: CommunityColors.textPrimary,
          ),
        ),
        content: Text(
          '"${data.requestData['title'] ?? ''}"',
          style: const TextStyle(
            fontFamily: CommunityType.fontFamily,
            fontSize: 13,
            color: CommunityColors.textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: const Text(
              'ביטול',
              style: TextStyle(
                fontFamily: CommunityType.fontFamily,
                color: CommunityColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(true),
            child: const Text(
              'אישור',
              style: TextStyle(
                fontFamily: CommunityType.fontFamily,
                fontWeight: FontWeight.w600,
                color: CommunityColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _claiming = true);

    final myName = (FirebaseAuth.instance.currentUser?.displayName ?? '').trim();
    final result = await CommunityHubService.claimRequest(
      requestId: widget.requestId,
      volunteerId: uid,
      volunteerName: myName.isEmpty ? 'מתנדב/ת' : myName,
    );

    if (!mounted) return;
    setState(() => _claiming = false);

    // claimRequest returns null on success, error string on failure.
    if (result == null) {
      // Open the existing chat with the requester so the pair can
      // coordinate. (No new community-chat screen — per project rule.)
      final requesterId =
          (data.requestData['requesterId'] as String? ?? '').trim();
      final requesterName =
          (data.requestData['requesterName'] as String? ?? '').trim();
      // Phase H QA defensive guard: if the request doc is somehow
      // missing the requesterId (data integrity issue — shouldn't
      // happen since createRequest sets it from the auth uid), pop
      // back instead of crashing the chat screen with an empty id.
      if (requesterId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'תפסת את ההתנדבות. פתח/י את "ההתנדבויות שלי" לצ׳אט.',
              style: TextStyle(fontFamily: CommunityType.fontFamily),
            ),
            backgroundColor: CommunityColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).maybePop();
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            receiverId: requesterId,
            receiverName: requesterName,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result,
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
        child: FutureBuilder<_DetailData?>(
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
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'לא הצלחנו לטעון את הבקשה',
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

  Widget _buildBody(_DetailData data) {
    final req = data.requestData;
    final user = data.requesterData;
    final isOpen = (req['status'] as String? ?? '') == 'open';

    final title    = req['title'] as String? ?? 'בקשת התנדבות';
    final desc     = req['description'] as String? ?? '';
    final urgency  = req['urgency'] as String? ?? 'normal';
    final category = req['category'] as String? ?? '';
    final reqType  = req['requesterType'] as String? ?? '';
    final createdAt = req['createdAt'] as Timestamp?;
    final isAnon   = req['isAnonymous'] == true;
    final reqName  = isAnon
        ? 'אנונימי'
        : (req['requesterName'] as String? ?? 'הפונה').trim();

    return Column(
      children: [
        _Header(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (urgency == 'high') _urgentChip(),
                    if (urgency == 'high') const SizedBox(width: 8),
                    Text(
                      _relativePosted(createdAt),
                      style: const TextStyle(
                        fontFamily: CommunityType.fontFamily,
                        fontSize: 11,
                        color: CommunityColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                    height: 1.25,
                    color: CommunityColors.textPrimary,
                  ),
                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    desc,
                    style: const TextStyle(
                      fontFamily: CommunityType.fontFamily,
                      fontSize: 14,
                      color: CommunityColors.textSecondary,
                      height: 1.65,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                // ── Meta rows: קטגוריה / סוג / מיקום / משך ──────────
                _metaRow('קטגוריה', _categoryLabel(category)),
                _metaRow('סוג', _requesterTypeLabel(reqType)),
                _metaRow('מיקום', 'השכונה שלך'), // TBD by Phase E geo
                _metaRow(
                  'משך',
                  // The model has no estimatedDurationMinutes today —
                  // legacy `community_requests` doc shape doesn't include
                  // it, so we render "—" for now. Phase E request_form
                  // (mockup 08) can capture it.
                  '—',
                  isLast: true,
                ),

                const SizedBox(height: 20),

                // ── Requester section ────────────────────────────────
                const Text(
                  'מי ביקש/ה',
                  style: TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                    color: CommunityColors.textMuted,
                  ),
                ),
                const SizedBox(height: 12),
                _RequesterRow(
                  name: reqName,
                  isAnon: isAnon,
                  tenureLabel: _tenureLabel(user['createdAt'] as Timestamp?),
                ),

                const SizedBox(height: 20),

                // ── Reward card ──────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: CommunityDecorations.cardSoft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.favorite,
                            color: CommunityColors.goldHeart, size: 16),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'לב זהב + 30 יום קידום',
                              style: TextStyle(
                                fontFamily: CommunityType.fontFamily,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.1,
                                color: CommunityColors.textPrimary,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'לאחר השלמה — לב זהב יוצג על הפרופיל שלך '
                              'למשך 30 יום + קידום בחיפוש.',
                              style: TextStyle(
                                fontFamily: CommunityType.fontFamily,
                                fontSize: 11,
                                color: CommunityColors.textTertiary,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          decoration: CommunityDecorations.footerWithTopDivider,
          child: CommunityPrimaryButton(
            label: isOpen
                ? 'אני יכול/ה להתנדב'
                : 'הבקשה כבר נתפסה',
            icon: isOpen ? Icons.favorite : null,
            isLoading: _claiming,
            onPressed: isOpen ? () => _claim(data) : null,
          ),
        ),
      ],
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────
  Widget _metaRow(String key, String value, {bool isLast = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          top: const BorderSide(
              color: CommunityColors.borderSubtle, width: 0.5),
          bottom: isLast
              ? const BorderSide(
                  color: CommunityColors.borderSubtle, width: 0.5)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              key,
              style: const TextStyle(
                fontFamily: CommunityType.fontFamily,
                fontSize: 11,
                color: CommunityColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: CommunityType.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
                color: CommunityColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _urgentChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: CommunityColors.dangerBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'דחוף',
        style: TextStyle(
          fontFamily: CommunityType.fontFamily,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          color: CommunityColors.danger,
        ),
      ),
    );
  }

  static String _relativePosted(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1)  return 'פורסם זה עתה';
    if (diff.inMinutes < 60) return 'פורסם לפני ${diff.inMinutes} דקות';
    if (diff.inHours   < 24) return 'פורסם לפני ${diff.inHours} שעות';
    return 'פורסם לפני ${diff.inDays} ימים';
  }

  static String _requesterTypeLabel(String id) {
    switch (id) {
      case 'elderly':            return 'קשישים';
      case 'lone_soldier':       return 'חייל בודד';
      case 'struggling_family':  return 'משפחה';
      case 'general':            return 'כללי';
      default:                   return id.isEmpty ? '—' : id;
    }
  }

  static String _categoryLabel(String id) {
    switch (id) {
      case 'repair':         return 'תיקונים';
      case 'cleaning':       return 'ניקיון';
      case 'delivery':       return 'הובלות';
      case 'teaching':       return 'שיעורים';
      case 'tech':           return 'טכנולוגיה';
      case 'cooking':        return 'בישול';
      case 'companionship':  return 'ליווי וחברות';
      case 'other':          return 'אחר';
      default:               return id.isEmpty ? '—' : id;
    }
  }

  static String _tenureLabel(Timestamp? createdAt) {
    if (createdAt == null) return 'חבר/ה באפליקציה';
    final months =
        DateTime.now().difference(createdAt.toDate()).inDays ~/ 30;
    if (months <= 0) return 'חדש/ה באפליקציה';
    if (months < 12) return 'חבר/ה באפליקציה · $months חודשים';
    final years = months ~/ 12;
    return 'חבר/ה באפליקציה · $years שנים';
  }
}

class _DetailData {
  _DetailData({required this.requestData, required this.requesterData});
  final Map<String, dynamic> requestData;
  final Map<String, dynamic> requesterData;
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
                'בקשת התנדבות',
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

// ── Requester row ────────────────────────────────────────────────────────
class _RequesterRow extends StatelessWidget {
  const _RequesterRow({
    required this.name,
    required this.isAnon,
    required this.tenureLabel,
  });

  final String name;
  final bool isAnon;
  final String tenureLabel;

  @override
  Widget build(BuildContext context) {
    final initials = _initialsFrom(name);
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: CommunityColors.dangerBg,
          ),
          alignment: Alignment.center,
          child: isAnon
              ? const Icon(Icons.person_off_outlined,
                  color: CommunityColors.danger, size: 18)
              : Text(
                  initials,
                  style: const TextStyle(
                    fontFamily: CommunityType.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: CommunityColors.danger,
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _shortName(name),
                style: const TextStyle(
                  fontFamily: CommunityType.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                  color: CommunityColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                tenureLabel,
                style: const TextStyle(
                  fontFamily: CommunityType.fontFamily,
                  fontSize: 11,
                  color: CommunityColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _initialsFrom(String name) {
    final t = name.trim();
    if (t.isEmpty) return '?';
    final parts = t.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) {
      return parts.first.characters.take(1).toString();
    }
    return parts.first.characters.take(1).toString() +
        parts.last.characters.take(1).toString();
  }

  /// Shortens "רחל בנימיני" → "רחל ב.".
  static String _shortName(String name) {
    final t = name.trim();
    if (t.isEmpty) return '—';
    final parts = t.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts.first;
    return '${parts.first} ${parts.last.characters.take(1)}.';
  }
}
