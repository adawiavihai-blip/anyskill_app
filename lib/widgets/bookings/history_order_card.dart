/// Rich history card for completed/cancelled/refunded jobs.
///
/// Extracted from my_bookings_screen.dart (Phase 1 refactor).
library;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'booking_shared_widgets.dart';

class HistoryOrderCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final String jobId;
  final VoidCallback? onReceipt;

  const HistoryOrderCard({
    super.key,
    required this.job,
    required this.jobId,
    this.onReceipt,
  });

  @override
  Widget build(BuildContext context) {
    final expertId    = job['expertId']   as String? ?? '';
    final expertName  = job['expertName'] as String? ?? 'מומחה';
    final status      = job['status']     as String? ?? '';
    final amount      = ((job['totalAmount'] ?? job['totalPaidByCustomer'] ?? 0.0) as num).toDouble();
    final serviceType = job['serviceType'] as String? ?? '';
    final description = job['description'] as String? ?? '';

    // ── Date + time extraction ──────────────────────────────────────────
    DateTime? appointmentDate;
    String? appointmentTime;
    if (job['appointmentDate'] is Timestamp) {
      appointmentDate = (job['appointmentDate'] as Timestamp).toDate();
    }
    if (job['appointmentTime'] is String) {
      appointmentTime = job['appointmentTime'] as String;
    }

    DateTime? completedDate;
    if (job['completedAt'] is Timestamp) {
      completedDate = (job['completedAt'] as Timestamp).toDate();
    }

    DateTime? createdDate;
    if (job['createdAt'] is Timestamp) {
      createdDate = (job['createdAt'] as Timestamp).toDate();
    }

    // Best date to display: appointment > completed > created
    final displayDate = appointmentDate ?? completedDate ?? createdDate;
    final dateStr = displayDate != null
        ? DateFormat('dd/MM/yyyy').format(displayDate)
        : '';
    final timeStr = appointmentTime ??
        (displayDate != null ? DateFormat('HH:mm').format(displayDate) : '');

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
          // ── Main content row ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BookingProfileAvatar(uid: expertId, name: expertName, size: 50),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name + status badge
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              expertName,
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
                          BookingStatusBadge(status),
                        ],
                      ),

                      // Category tag
                      if (serviceType.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            serviceType,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6366F1),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],

                      // Service description
                      if (description.isNotEmpty &&
                          description != serviceType) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],

                      const SizedBox(height: 8),

                      // Date + time + amount row
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
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '₪${amount.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF16A34A),
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

          // ── Bottom action row ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFFAFAFC),
              borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(16)),
            ),
            child: Row(
              children: [
                if (onReceipt != null)
                  GestureDetector(
                    onTap: onReceipt,
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
                  ),
                const Spacer(),
                Text(
                  '#${jobId.substring(0, jobId.length.clamp(0, 6))}',
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
