// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/volunteer_service.dart';
import '../../services/location_service.dart';
import '../../services/audio_service.dart';
import '../../widgets/anyskill_logo.dart';
import '../../l10n/app_localizations.dart';
import '../chat_modules/payment_module.dart';
import '../chat_modules/chat_stream_module.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 1. Safety banner — small green strip
// ═══════════════════════════════════════════════════════════════════════════

class ChatSafetyBanner extends StatelessWidget {
  const ChatSafetyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FFF4),
        border: Border(
            bottom: BorderSide(
                color: const Color(0xFF22C55E).withValues(alpha: 0.20))),
      ),
      child: Row(children: [
        const Icon(Icons.shield_rounded,
            size: 13, color: Color(0xFF16A34A)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'התשלום שלך מוגן על ידי AnySkill עד לאישורך על סיום העבודה',
            style: TextStyle(
                fontSize: 11,
                color: Colors.green[700],
                fontWeight: FontWeight.w500),
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 2. Anti-bypass info banner — dismissible amber strip
// ═══════════════════════════════════════════════════════════════════════════

class ChatGuardBanner extends StatelessWidget {
  final bool showBanner;
  final VoidCallback onDismiss;

  const ChatGuardBanner({
    super.key,
    required this.showBanner,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (!showBanner) return const SizedBox.shrink();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border(
          bottom: BorderSide(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.30)),
          right: const BorderSide(color: Color(0xFFF59E0B), width: 3),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onDismiss,
            child: Icon(Icons.close_rounded,
                size: 14, color: Colors.amber[700]),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.lock_rounded,
              size: 13, color: Color(0xFFD97706)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'שמירה על התשלום בתוך AnySkill מבטיחה לכם ביטוח והגנה על העבודה',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 11,
                  color:    Colors.amber[800],
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 3. Volunteer task banner — provider GPS + client confirm
// ═══════════════════════════════════════════════════════════════════════════

class ChatVolunteerBanner extends StatelessWidget {
  final String currentUserId;
  final String receiverId;

  const ChatVolunteerBanner({
    super.key,
    required this.currentUserId,
    required this.receiverId,
  });

  @override
  Widget build(BuildContext context) {
    final ids = [currentUserId, receiverId];
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('volunteer_tasks')
          .where('clientId', whereIn: ids)
          .where('status', isEqualTo: 'pending')
          .limit(2)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        QueryDocumentSnapshot? match;
        for (final doc in snap.data!.docs) {
          final d = doc.data() as Map<String, dynamic>? ?? {};
          final cId = d['clientId'] as String? ?? '';
          final pId = d['providerId'] as String? ?? '';
          if ((cId == currentUserId && pId == receiverId) ||
              (pId == currentUserId && cId == receiverId)) {
            match = doc;
            break;
          }
        }
        if (match == null) return const SizedBox.shrink();

        final taskData = match.data() as Map<String, dynamic>? ?? {};
        final clientId = taskData['clientId'] as String? ?? '';
        final isClient = clientId == currentUserId;
        final category = taskData['category'] as String? ?? '';
        final gpsValidated = taskData['gpsValidated'] == true;
        final gpsDistance = (taskData['gpsDistanceMeters'] as num?)?.toDouble();

        if (isClient) {
          return _ClientVolunteerCard(
            taskId: match.id,
            category: category,
            gpsValidated: gpsValidated,
            gpsDistance: gpsDistance,
            currentUserId: currentUserId,
          );
        } else {
          return _ProviderVolunteerCard(
            taskId: match.id,
            category: category,
            gpsValidated: gpsValidated,
            gpsDistance: gpsDistance,
          );
        }
      },
    );
  }
}

// ── Provider sub-banner: "הגעתי" GPS validation ─────────────────────────────

class _ProviderVolunteerCard extends StatelessWidget {
  final String taskId;
  final String category;
  final bool gpsValidated;
  final double? gpsDistance;

  const _ProviderVolunteerCard({
    required this.taskId,
    required this.category,
    required this.gpsValidated,
    required this.gpsDistance,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEDE9FE), Color(0xFFECFDF5)],
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: gpsValidated
              ? const Color(0xFF10B981).withValues(alpha: 0.5)
              : const Color(0xFF6366F1).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                gpsValidated ? Icons.check_circle : Icons.volunteer_activism,
                color: gpsValidated
                    ? const Color(0xFF10B981)
                    : const Color(0xFF6366F1),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gpsValidated ? 'המיקום אומת בהצלחה' : 'משימת התנדבות פעילה',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: gpsValidated
                            ? const Color(0xFF065F46)
                            : const Color(0xFF312E81),
                      ),
                    ),
                    if (category.isNotEmpty)
                      Text(
                        category,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!gpsValidated)
                ElevatedButton.icon(
                  icon: const Icon(Icons.location_on, size: 16),
                  label: const Text('הגעתי'),
                  onPressed: () => _handleGpsCheck(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                )
              else
                _GpsStatusChip(validated: true, distance: gpsDistance),
            ],
          ),

          if (gpsValidated && gpsDistance != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.gps_fixed, size: 14, color: Color(0xFF10B981)),
                const SizedBox(width: 6),
                Text(
                  'מרחק: ${gpsDistance! < 1000 ? '${gpsDistance!.toInt()} מ\'' : '${(gpsDistance! / 1000).toStringAsFixed(1)} ק"מ'}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF065F46)),
                ),
                const SizedBox(width: 8),
                const Text(
                  'הלקוח יכול לאשר את השלמת ההתנדבות',
                  style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleGpsCheck(BuildContext context) async {
    final position = await LocationService.requestAndGet(context);

    if (position == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('לא ניתן לקבל מיקום. אנא אפשר גישה למיקום בהגדרות.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    final isValid = await VolunteerService.validateGpsProximity(
      taskId: taskId,
      providerLat: position.latitude,
      providerLng: position.longitude,
    );

    if (!context.mounted) return;

    if (isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ המיקום אומת בהצלחה! הלקוח יכול כעת לאשר את ההתנדבות.'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('המיקום שלך רחוק מהלקוח. נא להגיע למיקום השירות ולנסות שוב.'),
          backgroundColor: Color(0xFFF59E0B),
        ),
      );
    }
  }
}

// ── Client sub-banner: GPS status + confirm button ──────────────────────────

class _ClientVolunteerCard extends StatelessWidget {
  final String taskId;
  final String category;
  final bool gpsValidated;
  final double? gpsDistance;
  final String currentUserId;

  const _ClientVolunteerCard({
    required this.taskId,
    required this.category,
    required this.gpsValidated,
    required this.gpsDistance,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFECFDF5), Color(0xFFEDE9FE)],
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.volunteer_activism,
                  color: Color(0xFF10B981), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'התנדבות בתהליך',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF065F46),
                      ),
                    ),
                    if (category.isNotEmpty)
                      Text(
                        category,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _GpsStatusChip(validated: gpsValidated, distance: gpsDistance),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _confirmTask(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
                child: const Text('אשר סיום'),
              ),
            ],
          ),

          if (gpsValidated && gpsDistance != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.gps_fixed,
                    size: 14, color: Color(0xFF10B981)),
                const SizedBox(width: 6),
                Text(
                  'נותן השירות אימת הגעה — ${gpsDistance! < 1000 ? '${gpsDistance!.toInt()} מ\'' : '${(gpsDistance! / 1000).toStringAsFixed(1)} ק"מ'} ממך',
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF065F46)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmTask(BuildContext context) async {
    final gpsLine = gpsValidated
        ? 'נותן השירות אימת הגעה למיקום שלך '
          '(${gpsDistance != null && gpsDistance! < 1000 ? '${gpsDistance!.toInt()} מ\'' : gpsDistance != null ? '${(gpsDistance! / 1000).toStringAsFixed(1)} ק"מ' : ''}).'
        : 'שים לב: נותן השירות טרם אימת מיקום באמצעות GPS.';

    final reviewCtrl = TextEditingController();

    final reviewText = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final charCount = reviewCtrl.text.trim().length;
          final isValid = charCount >= VolunteerService.minReviewLength;

          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Text('אישור השלמת התנדבות',
                textAlign: TextAlign.start),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('האם נותן השירות השלים את ההתנדבות?'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: gpsValidated
                          ? const Color(0xFFECFDF5)
                          : const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: gpsValidated
                            ? const Color(0xFF10B981).withValues(alpha: 0.3)
                            : const Color(0xFFF59E0B).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          gpsValidated ? Icons.gps_fixed : Icons.gps_off,
                          size: 18,
                          color: gpsValidated
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF59E0B),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            gpsLine,
                            style: TextStyle(
                              fontSize: 12,
                              color: gpsValidated
                                  ? const Color(0xFF065F46)
                                  : const Color(0xFF92400E),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'ספר/י בקצרה על השירות שקיבלת:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reviewCtrl,
                    textAlign: TextAlign.start,
                    textDirection: TextDirection.rtl,
                    maxLines: 3,
                    maxLength: 300,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      hintText: 'לדוגמה: "תיקן את הברז במטבח, עבודה מקצועית"',
                      hintStyle: const TextStyle(
                          fontSize: 13, color: Color(0xFF9CA3AF)),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isValid
                              ? const Color(0xFF10B981)
                              : const Color(0xFFD1D5DB),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isValid
                              ? const Color(0xFF10B981)
                              : const Color(0xFFD1D5DB),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: Color(0xFF6366F1), width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                      counterText:
                          '$charCount/${VolunteerService.minReviewLength} תווים מינימום',
                      counterStyle: TextStyle(
                        fontSize: 11,
                        color: isValid
                            ? const Color(0xFF10B981)
                            : const Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'אישור ייתן לנותן השירות '
                    '+${VolunteerService.volunteerXpReward} XP '
                    'ותג "מתנדב פעיל".',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('עוד לא'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isValid
                      ? const Color(0xFF10B981)
                      : const Color(0xFFD1D5DB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: isValid
                    ? () => Navigator.pop(ctx, reviewCtrl.text.trim())
                    : null,
                child: const Text('כן, אשר!'),
              ),
            ],
          );
        },
      ),
    );

    reviewCtrl.dispose();

    if (reviewText == null || reviewText.isEmpty) return;

    final result = await VolunteerService.confirmCompletion(
      taskId: taskId,
      confirmingUserId: currentUserId,
      reviewText: reviewText,
    );

    if (!context.mounted) return;
    final isOk = result == VolunteerService.confirmOk;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isOk ? '✓ ההתנדבות אושרה! תודה רבה.' : result),
        backgroundColor: isOk ? Colors.green : Colors.red,
      ),
    );
  }
}

class _GpsStatusChip extends StatelessWidget {
  final bool validated;
  final double? distance;

  const _GpsStatusChip({required this.validated, required this.distance});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: validated
            ? const Color(0xFF10B981).withValues(alpha: 0.12)
            : const Color(0xFF9CA3AF).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            validated ? Icons.gps_fixed : Icons.gps_off,
            size: 12,
            color: validated
                ? const Color(0xFF10B981)
                : const Color(0xFF9CA3AF),
          ),
          const SizedBox(width: 4),
          Text(
            validated ? 'מיקום אומת' : 'ממתין לאימות',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: validated
                  ? const Color(0xFF065F46)
                  : const Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 4. Job status banner — escrow status + release escrow flow
// ═══════════════════════════════════════════════════════════════════════════

class ChatJobStatusBanner extends StatelessWidget {
  final String chatRoomId;
  final String currentUserId;
  final String receiverId;
  final String receiverName;
  final Future<String> Function() getCurrentUserName;

  const ChatJobStatusBanner({
    super.key,
    required this.chatRoomId,
    required this.currentUserId,
    required this.receiverId,
    required this.receiverName,
    required this.getCurrentUserName,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: ChatStreamModule.getJobStatusStream(chatRoomId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        const terminalStatuses = {
          'completed', 'cancelled', 'cancelled_with_penalty',
          'refunded', 'split_resolved', 'disputed',
        };

        Map<String, dynamic>? activeJobData;
        Map<String, dynamic>? lastTerminalData;
        QueryDocumentSnapshot? activeJobDoc;
        QueryDocumentSnapshot? lastTerminalDoc;

        for (final doc in snapshot.data!.docs) {
          final d = doc.data() as Map<String, dynamic>? ?? {};
          final s = d['status'] as String? ?? '';
          if (!terminalStatuses.contains(s)) {
            activeJobData = d;
            activeJobDoc = doc;
            break;
          } else {
            lastTerminalData ??= d;
            lastTerminalDoc ??= doc;
          }
        }

        final jobData = activeJobData ?? lastTerminalData ?? {};
        final jobDoc  = activeJobDoc ?? lastTerminalDoc;
        final status  = jobData['status'] as String? ?? '';

        if (jobDoc == null) return const SizedBox.shrink();
        final jobDocId = jobDoc.id;

        if (activeJobData == null && terminalStatuses.contains(status)) {
          return const SizedBox.shrink();
        }

        final isExpert = jobData['expertId'] == currentUserId;

        if (isExpert && status == 'paid_escrow') {
          return _StatusBanner(
            color:       const Color(0xFFFFFBEB),
            borderColor: const Color(0xFFF59E0B),
            icon:        Icons.lock_clock_rounded,
            iconColor:   const Color(0xFFD97706),
            text:        'התשלום מוגן בנאמנות — סמן כשתסיים',
            buttonText:  'סיימתי ✅',
            buttonColor: Colors.green,
            onTap: () => _markExpertCompleted(context, jobDocId),
          );
        }

        if (!isExpert && status == 'expert_completed') {
          return _StatusBanner(
            color:       const Color(0xFFF0FFF4),
            borderColor: const Color(0xFF22C55E),
            icon:        Icons.check_circle_rounded,
            iconColor:   const Color(0xFF16A34A),
            text:        'המומחה סיים! אשר לשחרור התשלום.',
            buttonText:  'אשר ושחרר 💚',
            buttonColor: const Color(0xFF16A34A),
            onTap: () => _releaseEscrow(context, jobDocId, jobData),
          );
        }

        return const _StatusBanner(
          color:       Color(0xFFFFFBEB),
          borderColor: Color(0xFFF59E0B),
          icon:        Icons.security_rounded,
          iconColor:   Color(0xFFD97706),
          text:        'התשלום מוגן בחשבון נאמנות',
        );
      },
    );
  }

  Future<void> _markExpertCompleted(BuildContext context, String jobDocId) async {
    final msgr = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(jobDocId)
          .update({
        'status':            'expert_completed',
        'expertCompletedAt': FieldValue.serverTimestamp(),
      });
      AudioService.instance.playEvent(AppEvent.onPaymentSuccess);
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatRoomId)
          .collection('messages')
          .add({
        'senderId':  'system',
        'message':   '✅ המומחה סיים את העבודה! לחץ על "אשר ושחרר" כדי לשחרר את התשלום.',
        'type':      'text',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      msgr.showSnackBar(SnackBar(
        backgroundColor: Colors.red,
        content: Text('שגיאה בעדכון הסטטוס: $e'),
      ));
    }
  }

  Future<void> _releaseEscrow(
      BuildContext context, String jobDocId, Map<String, dynamic> jobData) async {
    BuildContext? loadingCtx;

    void hideLoading() {
      final ctx = loadingCtx;
      loadingCtx = null;
      if (ctx != null && ctx.mounted && Navigator.canPop(ctx)) {
        Navigator.of(ctx).pop();
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        loadingCtx = ctx;
        return const PopScope(
          canPop: false,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
        );
      },
    );

    String? error;
    try {
      final realName = await getCurrentUserName();
      error = await PaymentModule.releaseEscrowFundsWithError(
        jobId:        jobDocId,
        expertId:     jobData['expertId'] ?? receiverId,
        expertName:   receiverName,
        customerName: realName,
        totalAmount:  (jobData['totalAmount'] ??
                jobData['totalPaidByCustomer'] ??
                0.0)
            .toDouble(),
      );

      if (error == null) {
        final snap = await FirebaseFirestore.instance
            .collection('jobs')
            .doc(jobDocId)
            .get();
        final confirmedStatus =
            (snap.data() ?? {})['status'] as String? ?? '';
        if (confirmedStatus != 'completed') {
          error = 'הסטטוס לא עודכן — נסה שוב (status: $confirmedStatus)';
        } else {
          // Award Community Hero badge if this is a volunteer job
          final freshJobData = snap.data() ?? {};
          final isVolunteerJob = (freshJobData['isVolunteer'] as bool?) ?? false;
          if (isVolunteerJob) {
            final expertId = freshJobData['expertId'] as String? ?? receiverId;
            try {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(expertId)
                  .update({
                'hasCommunityHeroBadge': true,
                'xp': FieldValue.increment(100),
              });

              await FirebaseFirestore.instance
                  .collection('notifications')
                  .add({
                'userId': expertId,
                'title': '🦸 קיבלת תג גיבור קהילה!',
                'body': 'תודה על ההתנדבות שלך — הקהילה מודה לך.',
                'type': 'community_hero',
                'isRead': false,
                'createdAt': FieldValue.serverTimestamp(),
              });
            } catch (e) {
              debugPrint('Error awarding Community Hero badge: $e');
            }
          }
        }
      }
    } catch (e) {
      error = e.toString();
    } finally {
      hideLoading();
    }

    if (!context.mounted) return;

    if (error == null) {
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: AnySkillBrandIcon(size: 44),
                ),
              ),
              const SizedBox(height: 16),
              const Text('התשלום שוחרר בהצלחה! 🎉',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('הכסף הועבר למומחה.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Color(0xFF64748B), fontSize: 13)),
              const SizedBox(height: 20),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('סגור',
                  style: TextStyle(color: Color(0xFF6366F1))),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('שגיאה בשחרור התשלום'),
          content: SelectableText(error!),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: Text(AppLocalizations.of(context).close)),
          ],
        ),
      );
    }
  }
}

// ── Status banner row used by ChatJobStatusBanner ───────────────────────────

class _StatusBanner extends StatelessWidget {
  final Color    color;
  final Color    borderColor;
  final IconData icon;
  final Color    iconColor;
  final String   text;
  final String?  buttonText;
  final Color?   buttonColor;
  final VoidCallback? onTap;

  const _StatusBanner({
    required this.color,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.text,
    this.buttonText,
    this.buttonColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: color,
        border: Border(
          bottom: BorderSide(color: borderColor.withValues(alpha: 0.30)),
          right:  BorderSide(color: borderColor, width: 3),
        ),
      ),
      child: Row(
        children: [
          if (buttonText != null && onTap != null) ...[
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: buttonColor ?? const Color(0xFF6366F1),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
              ),
              onPressed: onTap,
              child: Text(buttonText!,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 12),
                textAlign: TextAlign.right),
          ),
          const SizedBox(width: 8),
          Icon(icon, color: iconColor, size: 18),
        ],
      ),
    );
  }
}
