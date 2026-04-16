// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/escrow_service.dart';
import '../../services/offline_message_queue.dart';
import '../../utils/safe_image_provider.dart';
import '../walk_route_screen.dart';

class ChatUIHelper {
  // ── Main entry point ──────────────────────────────────────────────────────
  static Widget buildMessageBubble({
    required BuildContext context,
    required Map<String, dynamic> data,
    required bool isMe,
    String senderName     = '',
    String senderImageUrl = '',
    String currentUserId  = '',
    String chatRoomId     = '',
    VoidCallback? onPaymentTap,
  }) {
    final String type  = (data['type']?.toString())    ?? 'text';
    final String msg   = (data['message']?.toString()) ?? '';
    final dynamic ts   = data['timestamp'];
    final bool isRead  = data['isRead'] == true;

    // v12.2 offline queue flags (added by OfflineMessageQueue.toDocMap).
    final bool   isPending  = data['__isPending'] == true;
    final String pendStatus = (data['__pendingStatus']?.toString()) ?? '';
    final String localId    = (data['__localId']?.toString()) ?? '';
    final int?   pendMs     = (data['__createdAtMs'] is num)
        ? (data['__createdAtMs'] as num).toInt()
        : null;

    // Full-width transaction cards
    if (type == 'payment_request') {
      return _TransactionCard(data: data, isMe: isMe, onTap: onPaymentTap);
    }
    if (type == 'payment_complete') {
      return _PaymentCompleteCard(data: data);
    }
    if (type == 'official_quote') {
      return _OfficialQuoteCard(
        data:          data,
        isMe:          isMe,
        currentUserId: currentUserId,
        chatRoomId:    chatRoomId,
      );
    }
    if (type == 'walk_summary') {
      return _WalkSummaryCard(data: data, isMe: isMe);
    }
    if (type == 'boarding_proof') {
      return _BoardingProofCard(data: data, isMe: isMe);
    }

    // ── Bubble container ────────────────────────────────────────────────────
    final bubble = Container(
      padding: type == 'image'
          ? const EdgeInsets.all(4)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFF6366F1) : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft:     const Radius.circular(18),
          topRight:    const Radius.circular(18),
          bottomLeft:  Radius.circular(isMe ? 18 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 18),
        ),
        boxShadow: [
          BoxShadow(
            color: isMe
                ? const Color(0xFF6366F1).withValues(alpha: 0.22)
                : Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: isMe ? null : Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildContent(type, msg, isMe),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Timestamp(ts: ts, isMe: isMe, fallbackMs: pendMs),
              if (isMe) ...[
                const SizedBox(width: 3),
                _StatusIcon(
                  isPending:  isPending,
                  pendStatus: pendStatus,
                  isRead:     isRead,
                ),
              ],
            ],
          ),
        ],
      ),
    );

    // Failed messages are tappable to retry; long-press to cancel.
    final bool isFailed = isPending && pendStatus == 'failed';
    final Widget bubbleOrAction = (isFailed && localId.isNotEmpty)
        ? GestureDetector(
            onTap: () => OfflineMessageQueue.instance.retry(localId),
            onLongPress: () => _showCancelSheet(context, localId),
            child: Opacity(opacity: 0.75, child: bubble),
          )
        : (isPending
            ? Opacity(opacity: 0.6, child: bubble)
            : bubble);

    return Padding(
      padding: EdgeInsets.only(
        top: 2,
        bottom: 2,
        left:  isMe ? 60 : 8,
        right: isMe ? 8 : 60,
      ),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: isMe
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  bubbleOrAction,
                  if (isFailed)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 4),
                      child: Text(
                        'הקש לשליחה חוזרת',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.red.shade400,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SenderAvatar(name: senderName, imageUrl: senderImageUrl),
                  const SizedBox(width: 6),
                  Flexible(child: bubbleOrAction),
                ],
              ),
      ),
    );
  }

  static void _showCancelSheet(BuildContext context, String localId) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.refresh_rounded, color: Color(0xFF6366F1)),
              title: const Text('נסה לשלוח שוב'),
              onTap: () {
                Navigator.pop(context);
                OfflineMessageQueue.instance.retry(localId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              title: const Text('בטל ומחק'),
              onTap: () {
                Navigator.pop(context);
                OfflineMessageQueue.instance.remove(localId);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Content by type ───────────────────────────────────────────────────────
  static Widget _buildContent(String type, String msg, bool isMe) {
    switch (type) {
      case 'image':
        if (msg.isEmpty || !msg.startsWith('http')) {
          return const SizedBox(
            width: 220,
            height: 60,
            child: Center(child: Icon(Icons.broken_image, color: Colors.grey)),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: CachedNetworkImage(
            imageUrl: msg,
            width: 220,
            fit: BoxFit.cover,
            placeholder: (_, __) => const SizedBox(
                width: 220,
                height: 140,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            errorWidget: (_, __, ___) =>
                const SizedBox(
                  width: 220,
                  height: 60,
                  child: Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                ),
          ),
        );

      case 'location':
        return GestureDetector(
          onTap: () => launchUrl(Uri.parse(msg)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isMe
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.blue.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isMe
                    ? Colors.white.withValues(alpha: 0.3)
                    : Colors.blue.withValues(alpha: 0.25),
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.location_on_rounded,
                  color: isMe ? Colors.white : Colors.redAccent, size: 18),
              const SizedBox(width: 6),
              Text(
                'צפה במיקום',
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.blue[700],
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  decoration: TextDecoration.underline,
                ),
              ),
            ]),
          ),
        );

      default:
        return Text(
          msg,
          textAlign: TextAlign.right,
          style: TextStyle(
            color: isMe ? Colors.white : const Color(0xFF1A1A2E),
            fontSize: 14,
            height: 1.35,
          ),
        );
    }
  }

  // ── System event card ─────────────────────────────────────────────────────
  // Tinted card that adapts its color and icon to the message intent.
  // Success (✅) → green  |  Error (❌) → red  |  Default → indigo
  static Widget buildSystemAlert(String msg) {
    final bool isSuccess = msg.contains('✅') || msg.contains('שוחרר') ||
        msg.contains('הושלם') || msg.contains('סיים');
    final bool isError   = msg.contains('❌') || msg.contains('שגיאה');

    final Color tint = isSuccess
        ? const Color(0xFF16A34A)
        : isError
            ? const Color(0xFFDC2626)
            : const Color(0xFF6366F1);

    final IconData iconData = isSuccess
        ? Icons.check_circle_rounded
        : isError
            ? Icons.error_rounded
            : Icons.info_rounded;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tint.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: tint.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(iconData, size: 15, color: tint),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  msg,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12,
                      color: tint,
                      fontWeight: FontWeight.w600,
                      height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sender avatar (shown on left side for !isMe messages) ────────────────────

class _SenderAvatar extends StatelessWidget {
  final String name;
  final String imageUrl;
  const _SenderAvatar({required this.name, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final imgProvider = safeImageProvider(imageUrl);
    return CircleAvatar(
      radius: 16,
      backgroundColor: const Color(0xFFEDE9FE),
      backgroundImage: imgProvider,
      child: imgProvider == null
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6366F1)),
            )
          : null,
    );
  }
}

// ── Timestamp helper widget ───────────────────────────────────────────────────

class _Timestamp extends StatelessWidget {
  final dynamic ts;
  final bool isMe;
  final int? fallbackMs; // used for offline/pending messages with no serverTimestamp
  const _Timestamp({required this.ts, required this.isMe, this.fallbackMs});

  @override
  Widget build(BuildContext context) {
    DateTime? date;
    if (ts is Timestamp) {
      date = (ts as Timestamp).toDate();
    } else if (fallbackMs != null) {
      date = DateTime.fromMillisecondsSinceEpoch(fallbackMs!);
    }
    if (date == null) return const SizedBox.shrink();
    return Text(
      DateFormat('HH:mm', 'he').format(date),
      style: TextStyle(
        fontSize: 10,
        color: isMe
            ? Colors.white.withValues(alpha: 0.55)
            : Colors.grey[400],
      ),
    );
  }
}

/// WhatsApp-style delivery indicator for my own bubbles.
///
///   pending → rotating clock (still in local outbox)
///   failed  → red exclamation (tap bubble to retry)
///   sent    → single grey tick (reached Firestore, not yet read)
///   read    → double blue tick (receiver marked it read)
class _StatusIcon extends StatelessWidget {
  final bool   isPending;
  final String pendStatus;
  final bool   isRead;
  const _StatusIcon({
    required this.isPending,
    required this.pendStatus,
    required this.isRead,
  });

  @override
  Widget build(BuildContext context) {
    if (isPending) {
      if (pendStatus == 'failed') {
        return const Icon(
          Icons.error_outline_rounded,
          size: 12,
          color: Color(0xFFFCA5A5), // soft red, readable on indigo bubble
        );
      }
      return Icon(
        Icons.schedule_rounded,
        size: 12,
        color: Colors.white.withValues(alpha: 0.70),
      );
    }
    return Icon(
      Icons.done_all_rounded,
      size: 12,
      color: isRead
          ? Colors.lightBlueAccent
          : Colors.white.withValues(alpha: 0.45),
    );
  }
}

// ── Transaction request card ──────────────────────────────────────────────────

class _TransactionCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isMe;
  final VoidCallback? onTap;

  const _TransactionCard({
    required this.data,
    required this.isMe,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final amount      = (data['amount'] as num? ?? 0).toDouble();
    final description = data['message'] as String? ?? 'בקשת תשלום';
    final ts          = data['timestamp'];

    final amountStr = amount % 1 == 0
        ? '₪${amount.toInt()}'
        : '₪${amount.toStringAsFixed(2)}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isMe
                ? [const Color(0xFF4F46E5), const Color(0xFF7C3AED)]
                : [const Color(0xFF1C1917), const Color(0xFF2D2520)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // ── Header ──────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.40)),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.bolt_rounded,
                          size: 12, color: Color(0xFFF59E0B)),
                      SizedBox(width: 4),
                      Text('בקשת תשלום',
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFFF59E0B),
                              fontWeight: FontWeight.bold)),
                    ]),
                  ),
                  const Icon(Icons.payments_rounded,
                      color: Colors.white38, size: 18),
                ],
              ),
              const SizedBox(height: 14),

              // ── Amount ──────────────────────────────────────────────────
              Text(
                amountStr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
              ),

              const SizedBox(height: 14),
              Divider(color: Colors.white.withValues(alpha: 0.10), height: 1),
              const SizedBox(height: 14),

              // ── Action ──────────────────────────────────────────────────
              if (!isMe) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.lock_rounded, size: 16),
                    label: const Text('אשר ושלם',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    onPressed: onTap,
                  ),
                ),
                const SizedBox(height: 7),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.shield_rounded,
                      size: 11,
                      color: Colors.white.withValues(alpha: 0.35)),
                  const SizedBox(width: 4),
                  Text('התשלום מוגן בנאמנות על ידי AnySkill',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.35))),
                ]),
              ] else ...[
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  const Icon(Icons.hourglass_top_rounded,
                      size: 13, color: Colors.white38),
                  const SizedBox(width: 5),
                  Text('ממתין לאישור הלקוח',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.45))),
                ]),
              ],
              const SizedBox(height: 8),
              _Timestamp(ts: ts, isMe: true),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Payment complete card ─────────────────────────────────────────────────────

class _PaymentCompleteCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _PaymentCompleteCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final amount = (data['amount'] as num? ?? 0).toDouble();
    final ts     = data['timestamp'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FFF4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: const Color(0xFF22C55E).withValues(alpha: 0.40)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF22C55E).withValues(alpha: 0.10),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                      color: Color(0xFFDCFCE7), shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded,
                      color: Color(0xFF16A34A), size: 20),
                ),
                const Text('תשלום הושלם! 🎉',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF16A34A))),
              ],
            ),
            if (amount > 0) ...[
              const SizedBox(height: 8),
              Text(
                amount % 1 == 0
                    ? '₪${amount.toInt()}'
                    : '₪${amount.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF16A34A)),
              ),
            ],
            const SizedBox(height: 6),
            _Timestamp(ts: ts, isMe: false),
          ],
        ),
      ),
    );
  }
}

// ── Official Quote Card ───────────────────────────────────────────────────────
// Receipt-style card shown in chat when a provider sends an Official Quote.
// The client sees a "Pay & Secure in Escrow" button; the provider sees the
// waiting state. Both see the status badge once the quote is paid/rejected.

class _OfficialQuoteCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool   isMe;
  final String currentUserId;
  final String chatRoomId;

  const _OfficialQuoteCard({
    required this.data,
    required this.isMe,
    required this.currentUserId,
    required this.chatRoomId,
  });

  @override
  State<_OfficialQuoteCard> createState() => _OfficialQuoteCardState();
}

class _OfficialQuoteCardState extends State<_OfficialQuoteCard> {
  bool _paying = false;

  Future<void> _pay() async {
    if (_paying) return;
    setState(() => _paying = true);

    final messenger = ScaffoldMessenger.of(context);
    final quoteId      = widget.data['quoteId']?.toString() ?? '';
    final chatMessageId = widget.data['messageId']?.toString() ?? '';
    final amount       = (widget.data['amount'] as num? ?? 0).toDouble();
    final description  = widget.data['message']?.toString() ?? '';

    if (quoteId.isEmpty) {
      setState(() => _paying = false);
      messenger.showSnackBar(const SnackBar(
        content: Text('הצעת המחיר אינה תקינה'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    try {
      // Fetch the quote document to resolve provider/client identities.
      final db = FirebaseFirestore.instance;
      final quoteSnap = await db.collection('quotes').doc(quoteId).get();
      final qData = quoteSnap.data() ?? {};
      final providerId = qData['providerId']?.toString() ?? '';
      final clientId   = qData['clientId']?.toString()   ?? widget.currentUserId;

      // Resolve display names from user docs (best-effort, fallback to '').
      final results = await Future.wait([
        db.collection('users').doc(providerId).get(),
        db.collection('users').doc(clientId).get(),
      ]);
      final providerName =
          (results[0].data() ?? {})['name']?.toString() ?? '';
      final clientName =
          (results[1].data() ?? {})['name']?.toString() ??
          FirebaseAuth.instance.currentUser?.displayName ?? '';

      // Phase 2 NOTE: this uses the legacy internal-credits escrow path.
      // Stripe was removed pending Israeli payment provider integration.
      final error = await EscrowService.payQuote(
        quoteId:       quoteId,
        chatMessageId: chatMessageId,
        chatRoomId:    widget.chatRoomId,
        providerId:    providerId,
        providerName:  providerName,
        clientId:      clientId,
        clientName:    clientName,
        amount:        amount,
        description:   description,
      );

      if (!mounted) return;
      setState(() => _paying = false);

      if (error != null) {
        messenger.showSnackBar(SnackBar(
          content: Text(error),
          backgroundColor: Colors.red,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _paying = false);
      messenger.showSnackBar(SnackBar(
        content: Text('שגיאה בעיבוד התשלום: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d           = widget.data;
    final amount      = (d['amount'] as num? ?? 0).toDouble();
    final description = d['message']?.toString()       ?? '';
    final quoteStatus = d['quoteStatus']?.toString()   ?? 'pending';
    final ts          = d['timestamp'];

    final amountStr = amount % 1 == 0
        ? '₪${amount.toInt()}'
        : '₪${amount.toStringAsFixed(2)}';

    final isPaid      = quoteStatus == 'paid';
    final isRejected  = quoteStatus == 'rejected';
    final isPending   = !isPaid && !isRejected;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A0E3C), Color(0xFF2D1A6B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isPaid
                ? const Color(0xFF22C55E).withValues(alpha: 0.5)
                : const Color(0xFF6366F1).withValues(alpha: 0.4),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.25),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // ── Header ────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isPaid
                          ? const Color(0xFF22C55E).withValues(alpha: 0.18)
                          : isRejected
                              ? Colors.red.withValues(alpha: 0.18)
                              : const Color(0xFF6366F1).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isPaid
                            ? const Color(0xFF22C55E).withValues(alpha: 0.5)
                            : isRejected
                                ? Colors.red.withValues(alpha: 0.4)
                                : const Color(0xFF6366F1).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      isPaid
                          ? '✅ שולם לאסקרו'
                          : isRejected
                              ? '❌ נדחה'
                              : '📋 הצעת מחיר רשמית',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isPaid
                            ? const Color(0xFF22C55E)
                            : isRejected
                                ? Colors.redAccent
                                : const Color(0xFFA5B4FC),
                      ),
                    ),
                  ),
                  const Icon(Icons.receipt_long_rounded,
                      color: Colors.white30, size: 20),
                ],
              ),

              const SizedBox(height: 16),

              // ── Amount ────────────────────────────────────────────────
              Text(
                amountStr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1.5,
                ),
              ),

              // ── Description ───────────────────────────────────────────
              if (description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  description,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],

              const SizedBox(height: 16),
              Divider(
                  color: Colors.white.withValues(alpha: 0.10), height: 1),
              const SizedBox(height: 16),

              // ── Action area ───────────────────────────────────────────
              if (isPending && !widget.isMe) ...[
                // Client: Pay button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: _paying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.lock_rounded, size: 16),
                    label: Text(
                      _paying ? 'מעבד...' : 'אשר ושלם',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    onPressed: _paying ? null : _pay,
                  ),
                ),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.shield_rounded,
                      size: 11,
                      color: Colors.white.withValues(alpha: 0.35)),
                  const SizedBox(width: 4),
                  Text('הסכום נעול בנאמנות AnySkill עד השלמת העבודה',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.35))),
                ]),
              ] else if (isPending && widget.isMe) ...[
                // Provider: waiting state
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  const Icon(Icons.hourglass_top_rounded,
                      size: 13, color: Colors.white38),
                  const SizedBox(width: 5),
                  Text(
                    'ממתין לאישור הלקוח',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.5)),
                  ),
                ]),
              ] else if (isPaid) ...[
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  const Icon(Icons.verified_rounded,
                      size: 14, color: Color(0xFF22C55E)),
                  const SizedBox(width: 5),
                  const Text('תשלום נעול באסקרו — העבודה יכולה להתחיל!',
                      style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF22C55E),
                          fontWeight: FontWeight.w600)),
                ]),
              ],

              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: _Timestamp(ts: ts, isMe: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Walk Summary Card — pet services / walkTracking
// Tapping the card opens an interactive route map (`WalkRouteScreen`).
// ═══════════════════════════════════════════════════════════════════════════
class _WalkSummaryCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isMe;
  const _WalkSummaryCard({required this.data, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final mapUrl = data['mapUrl'] as String? ?? '';
    final walkId = data['walkId'] as String? ?? '';
    final message = (data['message'] as String? ?? '').trim();
    final ts = data['timestamp'];

    return Padding(
      padding: EdgeInsets.only(
        top: 4,
        bottom: 4,
        left: isMe ? 40 : 8,
        right: isMe ? 8 : 40,
      ),
      child: GestureDetector(
        onTap: walkId.isEmpty
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WalkRouteScreen(walkId: walkId),
                  ),
                ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFED7AA), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Static OSM map preview (full width, no API key required)
              if (mapUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16)),
                  child: AspectRatio(
                    aspectRatio: 3 / 2,
                    child: CachedNetworkImage(
                      imageUrl: mapUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: const Color(0xFFF3F4F6),
                        child: const Center(
                            child: CircularProgressIndicator()),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: const Color(0xFFF3F4F6),
                        child: const Icon(Icons.map_outlined,
                            size: 48, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.pets_rounded,
                              color: Color(0xFFF97316), size: 18),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'סיכום ההליכון',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (message.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        message,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF374151),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.touch_app_rounded,
                                size: 12, color: Color(0xFF6366F1)),
                            SizedBox(width: 4),
                            Text(
                              'הקש לצפייה במפה אינטראקטיבית',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF6366F1),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        _Timestamp(ts: ts, isMe: false),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Boarding Proof Card — pet services / dailyProof
// Shows the daily photo + video updates the provider posts during boarding.
// ═══════════════════════════════════════════════════════════════════════════
class _BoardingProofCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isMe;
  const _BoardingProofCard({required this.data, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final photoUrl = data['photoUrl'] as String? ?? '';
    final videoUrl = data['videoUrl'] as String? ?? '';
    final message = (data['message'] as String? ?? '').trim();
    final ts = data['timestamp'];

    return Padding(
      padding: EdgeInsets.only(
        top: 4,
        bottom: 4,
        left: isMe ? 40 : 8,
        right: isMe ? 8 : 40,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFED7AA), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (photoUrl.isNotEmpty)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: CachedNetworkImage(
                    imageUrl: photoUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: const Color(0xFFF3F4F6),
                      child: const Center(
                          child: CircularProgressIndicator()),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: const Color(0xFFF3F4F6),
                      child: const Icon(Icons.broken_image_outlined,
                          size: 48, color: Colors.grey),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.pets_rounded,
                            color: Color(0xFFF97316), size: 18),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'עדכון יומי מהפנסיון',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (message.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      message,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF374151)),
                    ),
                  ],
                  if (videoUrl.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF97316),
                        side: const BorderSide(color: Color(0xFFF97316)),
                      ),
                      icon:
                          const Icon(Icons.play_circle_outline, size: 16),
                      label: const Text('צפה בוידאו'),
                      onPressed: () async {
                        final uri = Uri.tryParse(videoUrl);
                        if (uri != null) {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _Timestamp(ts: ts, isMe: false),
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
