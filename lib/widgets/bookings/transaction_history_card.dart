/// Transaction-based history card (fallback when no jobs exist).
///
/// Extracted from my_bookings_screen.dart (Phase 1 refactor).
library;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'booking_shared_widgets.dart';

class TransactionHistoryCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;

  const TransactionHistoryCard({super.key, required this.data, required this.docId});

  // ── Transaction type mapping ──────────────────────────────────────────
  static const _typeConfig = <String, (String, IconData, Color, Color)>{
    'quote_payment':       ('תשלום עבור שירות',  Icons.payments_rounded,     Color(0xFFF0FDF4), Color(0xFF16A34A)),
    'anytask_escrow_lock': ('נעילה באסקרו',      Icons.lock_rounded,         Color(0xFFFFF7ED), Color(0xFFF97316)),
    'anytask_auto_release':('שחרור אוטומטי',     Icons.check_circle_rounded, Color(0xFFF0FDF4), Color(0xFF16A34A)),
    'anytask_refund':      ('החזר כספי',          Icons.replay_rounded,       Color(0xFFF0FDFA), Color(0xFF0D9488)),
    'anytask_expired_refund':('החזר — פג תוקף',   Icons.timer_off_rounded,    Color(0xFFFFF5F5), Color(0xFFEF4444)),
    'tip':                 ('טיפ',               Icons.favorite_rounded,     Color(0xFFFAF5FF), Color(0xFF9333EA)),
    'top_up':              ('טעינת ארנק',         Icons.account_balance_wallet_rounded, Color(0xFFEFF6FF), Color(0xFF3B82F6)),
    'credit':              ('זיכוי',              Icons.card_giftcard_rounded, Color(0xFFEFF6FF), Color(0xFF3B82F6)),
    'refund':              ('החזר כספי',          Icons.replay_rounded,       Color(0xFFF0FDFA), Color(0xFF0D9488)),
  };

  @override
  Widget build(BuildContext context) {
    final type   = data['type'] as String? ?? '';
    final amount = (data['amount'] as num? ?? 0).toDouble();

    final senderId     = data['senderId']     as String? ?? '';
    final senderName   = data['senderName']   as String? ?? '';
    final receiverId   = data['receiverId']   as String? ?? '';
    final receiverName = data['receiverName'] as String? ?? '';

    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final bool isReceiver = receiverId == currentUid;
    final otherName = isReceiver
        ? (senderName.isNotEmpty ? senderName : 'לקוח')
        : (receiverName.isNotEmpty ? receiverName : 'נותן שירות');
    final otherUid  = isReceiver ? senderId : receiverId;

    final title = data['title'] as String? ?? '';
    final jobId  = data['jobId']  as String? ?? '';
    final taskId = data['taskId'] as String? ?? '';
    final refId  = jobId.isNotEmpty ? jobId : taskId;
    final payoutStatus = data['payoutStatus'] as String? ?? '';

    final ts   = data['timestamp'] as Timestamp?;
    final date = ts?.toDate();
    final dateStr = date != null ? DateFormat('dd/MM/yyyy', 'he').format(date) : '';
    final timeStr = date != null ? DateFormat('HH:mm', 'he').format(date)     : '';

    final (typeLabel, typeIcon, badgeBg, badgeFg) = _typeConfig[type]
        ?? ('תנועה', Icons.swap_horiz_rounded, const Color(0xFFF8FAFC), const Color(0xFF94A3B8));

    final isIncome = isReceiver && type != 'anytask_refund' && type != 'anytask_expired_refund';
    final amountColor = isIncome ? const Color(0xFF16A34A) : const Color(0xFFEF4444);
    final amountBg    = isIncome ? const Color(0xFFF0FDF4) : const Color(0xFFFFF5F5);
    final amountPrefix = isIncome ? '+' : '-';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BookingProfileAvatar(uid: otherUid, name: otherName, size: 50),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              otherName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: Color(0xFF1A1A2E),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(typeIcon, size: 12, color: badgeFg),
                                const SizedBox(width: 4),
                                Text(
                                  typeLabel,
                                  style: TextStyle(
                                    color: badgeFg,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (title.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (payoutStatus.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              payoutStatus == 'completed'
                                  ? Icons.check_circle_rounded
                                  : Icons.hourglass_top_rounded,
                              size: 12,
                              color: payoutStatus == 'completed'
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFFF97316),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              payoutStatus == 'completed' ? 'הושלם' : 'ממתין',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: payoutStatus == 'completed'
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFFF97316),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (dateStr.isNotEmpty) ...[
                            const Icon(Icons.calendar_today_rounded,
                                size: 12, color: Color(0xFF94A3B8)),
                            const SizedBox(width: 3),
                            Text(dateStr,
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF94A3B8))),
                          ],
                          if (timeStr.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.schedule_rounded,
                                size: 12, color: Color(0xFF94A3B8)),
                            const SizedBox(width: 2),
                            Text(timeStr,
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF94A3B8))),
                          ],
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: amountBg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$amountPrefix₪${amount.toStringAsFixed(amount.truncateToDouble() == amount ? 0 : 2)}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: amountColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFFAFAFC),
              borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(16)),
            ),
            child: Row(
              children: [
                if (refId.isNotEmpty)
                  ReceiptButton(jobId: refId),
                const Spacer(),
                Text(
                  '#${docId.length > 6 ? docId.substring(0, 6) : docId}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFFCBD5E1),
                    fontWeight: FontWeight.w500,
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

/// Fetches the invoice URL from the linked job doc and renders a "צפה בקבלה"
/// button. Shows nothing if no invoice exists.
class ReceiptButton extends StatefulWidget {
  final String jobId;
  const ReceiptButton({super.key, required this.jobId});
  @override
  State<ReceiptButton> createState() => _ReceiptButtonState();
}

class _ReceiptButtonState extends State<ReceiptButton> {
  String? _invoiceUrl;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _fetchInvoice();
  }

  Future<void> _fetchInvoice() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.jobId)
          .get();
      final data = doc.data() ?? {};
      final url = data['invoiceBUrl'] as String?
          ?? data['invoiceAUrl'] as String?
          ?? '';
      if (mounted) setState(() { _invoiceUrl = url; _loaded = true; });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || (_invoiceUrl?.isEmpty ?? true)) {
      return const SizedBox.shrink();
    }
    return GestureDetector(
      onTap: () async {
        final uri = Uri.tryParse(_invoiceUrl!);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_rounded,
              size: 14, color: Color(0xFF6366F1)),
          SizedBox(width: 4),
          Text(
            'צפה בקבלה',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF6366F1),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
