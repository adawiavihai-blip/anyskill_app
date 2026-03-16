import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Shows a professional digital receipt as a scrollable bottom sheet.
///
/// [jobData] — the Firestore document data from `jobs/{jobId}`.
/// [providerTaxId] — optional ח.פ/ת.ז of the provider (fetched separately).
void showReceiptSheet(
  BuildContext context, {
  required Map<String, dynamic> jobData,
  String? providerTaxId,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReceiptSheet(jobData: jobData, providerTaxId: providerTaxId),
  );
}

class _ReceiptSheet extends StatelessWidget {
  final Map<String, dynamic> jobData;
  final String? providerTaxId;

  const _ReceiptSheet({required this.jobData, this.providerTaxId});

  @override
  Widget build(BuildContext context) {
    final jobId      = jobData['jobId'] as String? ?? '';
    final total      = (jobData['totalPaidByCustomer'] as num? ?? 0).toDouble();
    final commission = (jobData['commissionAmount']    as num? ?? 0).toDouble();
    final net        = (jobData['netAmountForExpert']  as num? ?? 0).toDouble();
    // Guard against legacy corrupted data (commission > total means wrong format stored)
    final feePctRaw  = total > 0 ? (commission / total * 100) : 0.0;
    final feePct     = (feePctRaw > 100 || feePctRaw < 0) ? 0 : feePctRaw.round();

    final customerName = jobData['customerName'] as String? ?? '—';
    final expertName   = jobData['expertName']   as String? ?? '—';
    final serviceType  = jobData['serviceType']  as String? ?? '';

    final apptDate = jobData['appointmentDate'] is Timestamp
        ? (jobData['appointmentDate'] as Timestamp).toDate()
        : (jobData['appointmentDate'] as DateTime?);
    final apptTime  = jobData['appointmentTime'] as String? ?? '';
    final dateLabel = apptDate != null
        ? DateFormat('dd/MM/yyyy', 'he_IL').format(apptDate)
        : '—';

    final createdAt = (jobData['createdAt'] as Timestamp?)?.toDate();
    final createdLabel = createdAt != null
        ? DateFormat('dd/MM/yyyy HH:mm', 'he_IL').format(createdAt)
        : '—';

    final receiptNum = jobId.length >= 8
        ? jobId.substring(0, 8).toUpperCase()
        : jobId.toUpperCase();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // ── Handle ──────────────────────────────────────────────────
            const SizedBox(height: 12),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 4),

            // ── Scrollable content ───────────────────────────────────────
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                children: [
                  // Header
                  _header(receiptNum, createdLabel),
                  const SizedBox(height: 20),

                  // Parties
                  _sectionLabel("פרטי עסקה"),
                  const SizedBox(height: 10),
                  _infoRow("לקוח",        customerName),
                  _infoRow("נותן שירות",  expertName),
                  if (serviceType.isNotEmpty)
                    _infoRow("שירות",     serviceType),
                  _infoRow("תאריך",       "$dateLabel${apptTime.isNotEmpty ? ' · $apptTime' : ''}"),
                  if (providerTaxId != null && providerTaxId!.isNotEmpty)
                    _infoRow("ח.פ / ת.ז ספק", providerTaxId!),

                  const SizedBox(height: 22),
                  const Divider(thickness: 1),
                  const SizedBox(height: 16),

                  // Financial breakdown
                  _sectionLabel("פירוט תשלום"),
                  const SizedBox(height: 12),
                  _priceRow("מחיר השירות",         "₪${net.toStringAsFixed(2)}"),
                  const SizedBox(height: 8),
                  _priceRow(
                    feePct > 0 ? "עמלת פלטפורמה ($feePct%)" : "עמלת פלטפורמה",
                    "₪${commission.toStringAsFixed(2)}",
                    isGrey: true,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("₪${total.toStringAsFixed(2)}",
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900)),
                        const Text("סה\"כ שולם",
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),
                  const Divider(thickness: 1),
                  const SizedBox(height: 16),

                  // Status badge
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(30),
                        border:
                            Border.all(color: Colors.green.shade200, width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded,
                              color: Colors.green[700], size: 16),
                          const SizedBox(width: 6),
                          Text("העסקה הושלמה בהצלחה",
                              style: TextStyle(
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  // Legal note
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      "מסמך זה הוא אישור עסקה ואינו חשבונית מס רשמית. "
                      "לקבלת חשבונית מס, פנה ישירות לנותן השירות.",
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          height: 1.5),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey.shade300),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.copy_outlined, size: 16),
                          label: const Text("העתק מספר עסקה"),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: receiptNum));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text("מספר עסקה הועתק ✓"),
                                  duration: Duration(seconds: 2)),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A1A2E),
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.share_outlined, size: 16),
                          label: const Text("שתף קבלה"),
                          onPressed: () {
                            final text =
                                'קבלה #$receiptNum\n'
                                'שירות: ${serviceType.isNotEmpty ? serviceType : expertName}\n'
                                'תאריך: $dateLabel\n'
                                'סה"כ: ₪${total.toStringAsFixed(2)}\n'
                                'עמלת פלטפורמה: ₪${commission.toStringAsFixed(2)}\n'
                                'AnySkill — עסקה מאובטחת';
                            Clipboard.setData(ClipboardData(text: text));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text("פרטי הקבלה הועתקו ✓"),
                                  duration: Duration(seconds: 2)),
                            );
                          },
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
    );
  }

  Widget _header(String receiptNum, String date) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("#$receiptNum",
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontFamily: 'monospace')),
                  Text(date,
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 11)),
                ],
              ),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("AnySkill",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5)),
                  Text("קבלה דיגיטלית",
                      style: TextStyle(
                          color: Colors.white60, fontSize: 11)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Align(
      alignment: Alignment.centerRight,
      child: Text(label,
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.black54)),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(value,
                textAlign: TextAlign.left,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          Text(label,
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _priceRow(String label, String value, {bool isGrey = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isGrey ? Colors.grey[500] : Colors.black87)),
        Text(label,
            style: TextStyle(
                fontSize: 13,
                color: isGrey ? Colors.grey[500] : Colors.black87)),
      ],
    );
  }
}
