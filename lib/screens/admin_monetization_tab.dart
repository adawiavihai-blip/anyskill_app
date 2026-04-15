import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../utils/web_utils.dart';

/// Self-contained Monetization tab extracted from AdminScreen.
/// Owns admin settings state (fee sliders), escrow section, earnings chart,
/// CSV export, and promoted providers list.
class AdminMonetizationTab extends StatefulWidget {
  const AdminMonetizationTab({super.key});

  @override
  State<AdminMonetizationTab> createState() => _AdminMonetizationTabState();
}

class _AdminMonetizationTabState extends State<AdminMonetizationTab> {
  double _feePct        = 10.0;
  double _urgencyFeePct = 5.0;
  bool   _settingsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAdminSettings();
  }

  Future<void> _loadAdminSettings() async {
    final doc = await FirebaseFirestore.instance
        .collection('admin').doc('admin')
        .collection('settings').doc('settings').get();
    if (!mounted) return;
    final d = doc.data() ?? {};
    setState(() {
      // Firestore stores decimal fraction (0.10 = 10%) -- multiply x100 for UI display
      _feePct        = (((d['feePercentage']       as num?) ?? 0.10) * 100).toDouble();
      _urgencyFeePct = (((d['urgencyFeePercentage'] as num?) ?? 0.05) * 100).toDouble();
      _settingsLoaded = true;
    });
  }

  Future<void> _saveAdminSettings() async {
    await FirebaseFirestore.instance
        .collection('admin').doc('admin')
        .collection('settings').doc('settings')
        .set({
          // Divide /100 to store as decimal fraction (10% -> 0.10)
          'feePercentage':       _feePct / 100,
          'urgencyFeePercentage': _urgencyFeePct / 100,
        }, SetOptions(merge: true));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Colors.green, content: Text("ההגדרות נשמרו")));
    }
  }

  Future<void> _exportTransactionsCsv() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
        const SnackBar(content: Text("מכין קובץ CSV...")));

    try {
      final snap = await FirebaseFirestore.instance
          .collection('transactions')
          .orderBy('timestamp', descending: true)
          .get();

      final buf = StringBuffer();
      // UTF-8 BOM for Excel compatibility
      buf.write('\uFEFF');
      buf.writeln('מזהה,משתמש,כותרת,סכום,סוג,תאריך');

      for (final doc in snap.docs) {
        final d  = doc.data();
        final ts = (d['timestamp'] as Timestamp?)?.toDate();
        final dateStr = ts != null
            ? DateFormat('dd/MM/yyyy HH:mm').format(ts)
            : '';
        final amount = (d['amount'] as num? ?? 0).toStringAsFixed(2);
        // Escape any commas or quotes inside fields
        String esc(dynamic v) {
          final s = (v ?? '').toString().replaceAll('"', '""');
          return '"$s"';
        }
        buf.writeln([
          esc(doc.id),
          esc(d['userId']),
          esc(d['title']),
          esc(amount),
          esc(d['type']),
          esc(dateStr),
        ].join(','));
      }

      final csvStr  = buf.toString();
      final filename =
          'anyskill_transactions_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';

      triggerCsvDownload(csvStr, filename);

      if (mounted) {
        messenger.showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text("${snap.size} רשומות יוצאו ל-$filename"),
        ));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
            backgroundColor: Colors.red, content: Text("שגיאה: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── Global Commission % ───────────────────────────────────────
          _monoCard(
            icon: Icons.percent_rounded,
            color: const Color(0xFF6366F1),
            title: "עמלת פלטפורמה גלובלית",
            child: _settingsLoaded
                ? Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("${_feePct.toStringAsFixed(0)}%",
                              style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF6366F1))),
                          const Text("מכל עסקה (ברירת מחדל)",
                              style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFF6366F1),
                          thumbColor: const Color(0xFF6366F1),
                          inactiveTrackColor: Colors.grey[200],
                          overlayColor: const Color(0xFF6366F1).withValues(alpha: 0.1),
                        ),
                        child: Slider(
                          value: _feePct,
                          min: 0,
                          max: 30,
                          divisions: 30,
                          onChanged: (v) => setState(() => _feePct = v),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text("0%", style: TextStyle(fontSize: 11, color: Colors.grey)),
                          Text("30%", style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          "ניתן לדרוס לספקים ספציפיים דרך רשימת הספקים ← עמלה מותאמת",
                          style: TextStyle(fontSize: 11, color: Color(0xFF6366F1)),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          const SizedBox(height: 14),

          // ── Urgency Fee ───────────────────────────────────────────────
          _monoCard(
            icon: Icons.local_fire_department_rounded,
            color: const Color(0xFFEA580C),
            title: "תוספת דחיפות (בקשות דחופות)",
            child: _settingsLoaded
                ? Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("+${_urgencyFeePct.toStringAsFixed(0)}%",
                              style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFEA580C))),
                          const Text("על בקשות דחופות",
                              style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFFEA580C),
                          thumbColor: const Color(0xFFEA580C),
                          inactiveTrackColor: Colors.grey[200],
                          overlayColor:
                              const Color(0xFFEA580C).withValues(alpha: 0.1),
                        ),
                        child: Slider(
                          value: _urgencyFeePct,
                          min: 0,
                          max: 20,
                          divisions: 20,
                          onChanged: (v) => setState(() => _urgencyFeePct = v),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text("0%", style: TextStyle(fontSize: 11, color: Colors.grey)),
                          Text("20%", style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ],
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          const SizedBox(height: 14),

          // ── Save button ───────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.save_rounded, color: Colors.white),
              label: const Text("שמור הגדרות",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              onPressed: _saveAdminSettings,
            ),
          ),
          const SizedBox(height: 22),

          // ── Promoted Providers ────────────────────────────────────────
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('isPromoted', isEqualTo: true)
                .limit(100)
                .snapshots(),
            builder: (ctx, snap) {
              final promotedUsers = snap.data?.docs ?? [];
              return _monoCard(
                icon: Icons.star_rounded,
                color: Colors.amber[700]!,
                title: "ספקים מקודמים (${promotedUsers.length})",
                child: promotedUsers.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text("אין ספקים מקודמים כרגע",
                            style: TextStyle(color: Colors.grey, fontSize: 13)),
                      )
                    : Column(
                        children: promotedUsers.map((doc) {
                          final d = doc.data() as Map<String, dynamic>;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundImage: (d['profileImage'] != null &&
                                      d['profileImage'] != '')
                                  ? NetworkImage(d['profileImage'])
                                  : null,
                              child: d['profileImage'] == null
                                  ? const Icon(Icons.person)
                                  : null,
                            ),
                            title: Text(d['name'] ?? '—',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(d['serviceType'] ?? d['email'] ?? '',
                                style: const TextStyle(fontSize: 12)),
                            trailing: IconButton(
                              icon: const Icon(Icons.star_rounded,
                                  color: Colors.amber, size: 22),
                              tooltip: "בטל קידום",
                              onPressed: () {
                                FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(doc.id)
                                    .update({'isPromoted': false});
                              },
                            ),
                          );
                        }).toList(),
                      ),
              );
            },
          ),
          const SizedBox(height: 22),

          // ── Monthly Earnings Chart ────────────────────────────────────
          _monoCard(
            icon: Icons.bar_chart_rounded,
            color: Colors.green[700]!,
            title: "עמלות החודש",
            child: _buildEarningsChart(),
          ),
          const SizedBox(height: 22),

          // ── Escrow Commissions (pending jobs) ─────────────────────────
          _monoCard(
            icon: Icons.lock_clock_rounded,
            color: Colors.orange[700]!,
            title: "עמלות בהמתנה (Escrow)",
            child: _buildEscrowSection(),
          ),
          const SizedBox(height: 22),

          // ── CSV Export ────────────────────────────────────────────────
          _monoCard(
            icon: Icons.download_rounded,
            color: Colors.teal[700]!,
            title: "ייצוא לרואה חשבון",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "הורד את כל תנועות הארנק כקובץ CSV מוכן לפתיחה ב-Excel.",
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.5),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal[700],
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.table_chart_outlined, size: 18),
                    label: const Text("ייצא עסקאות ל-CSV",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    onPressed: _exportTransactionsCsv,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // ── Reusable mono card container ──────────────────────────────────────────
  static Widget _monoCard({
    required IconData icon,
    required Color color,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  // ── Escrow section: live list of jobs in paid_escrow ─────────────────────
  Widget _buildEscrowSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('jobs')
          .where('status', isEqualTo: 'paid_escrow')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final docs = snap.data!.docs;
        double total = 0;
        for (final d in docs) {
          total += (((d.data() as Map<String, dynamic>)['totalAmount']) as num? ?? 0).toDouble();
        }

        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                  SizedBox(width: 6),
                  Text("אין עסקאות בהמתנה כרגע",
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // ── Total badge ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("${docs.length} עסקאות",
                      style: TextStyle(color: Colors.orange[700], fontSize: 13)),
                  Text("סה״כ: ₪${total.toStringAsFixed(0)}",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[800],
                          fontSize: 15)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // ── Per-job rows ─────────────────────────────────────────────
            ...docs.map((doc) {
              final j    = doc.data() as Map<String, dynamic>;
              final amt  = ((j['totalAmount']) as num? ?? 0).toDouble();
              final expert   = j['expertName']   as String? ?? '—';
              final customer = j['customerName'] as String? ?? '—';
              final ts   = (j['createdAt'] as Timestamp?)?.toDate();
              final date = ts != null ? DateFormat('dd/MM HH:mm').format(ts) : '—';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade100),
                ),
                child: Row(
                  children: [
                    Text("₪${amt.toStringAsFixed(0)}",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("$customer ← $expert",
                              style: const TextStyle(fontSize: 12),
                              textAlign: TextAlign.right),
                          Text(date,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[500])),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    // ── Admin refund button (Red Button) ──────────
                    IconButton(
                      icon: const Icon(Icons.undo_rounded, size: 18),
                      color: Colors.red,
                      tooltip: 'החזר כספי',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36, minHeight: 36),
                      onPressed: () => _showAdminRefundDialog(
                        context,
                        jobId:        doc.id,
                        amount:       amt,
                        customerName: customer,
                        customerId:   j['customerId'] as String? ?? '',
                        expertName:   expert,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  // ── Admin refund dialog — "Red Button" ───────────────────────────────────
  // Phase 2 NOTE: Stripe Connect was removed. All refunds now flow through the
  // legacy internal-credits batch (return amount to user balance + write
  // refund transaction). When the Israeli payment provider is integrated,
  // restore the conditional branch that routes card payments through the
  // provider's refund API.
  Future<void> _showAdminRefundDialog(
    BuildContext ctx, {
    required String jobId,
    required double amount,
    required String customerName,
    required String customerId,
    required String expertName,
  }) async {
    // Capture before async gap (showDialog)
    final messenger = ScaffoldMessenger.of(ctx);

    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('החזר כספי', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('האם להחזיר ₪${amount.toStringAsFixed(0)} ללקוח?',
                style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 12),
            _refundRow('לקוח', customerName),
            _refundRow('ספק', expertName),
            _refundRow('סכום', '₪${amount.toStringAsFixed(2)}'),
            _refundRow('אמצעי', 'יתרה פנימית'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'פעולה זו אינה הפיכה. הכספים יוחזרו ללקוח והעבודה תבוטל.',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12, color: Colors.red),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('ביטול'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dCtx, true),
            icon: const Icon(Icons.undo_rounded, size: 16, color: Colors.white),
            label: const Text('אשר החזר', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    messenger.showSnackBar(
      const SnackBar(content: Text('מבצע החזר כספי...'), duration: Duration(seconds: 2)),
    );

    try {
      // Legacy credits path: refund to customer balance + update job.
      final batch = FirebaseFirestore.instance.batch();

      // Update job status
      batch.update(
        FirebaseFirestore.instance.collection('jobs').doc(jobId),
        {
          'status':      'refunded',
          'resolvedAt':  FieldValue.serverTimestamp(),
          'resolvedBy':  'admin',
          'resolution':  'refund',
        },
      );

      // Credit customer balance
      batch.update(
        FirebaseFirestore.instance.collection('users').doc(customerId),
        {'balance': FieldValue.increment(amount)},
      );

      // Transaction record
      batch.set(
        FirebaseFirestore.instance.collection('transactions').doc(),
        {
          'senderId':    'platform',
          'receiverId':  customerId,
          'amount':      amount,
          'type':        'refund',
          'jobId':       jobId,
          'timestamp':   FieldValue.serverTimestamp(),
          'payoutStatus': 'completed',
        },
      );

      await batch.commit();

      // Log to Watchtower
      try {
        FirebaseFirestore.instance.collection('activity_log').add({
          'type':      'admin_refund',
          'title':     'החזר כספי ע"י אדמין',
          'detail':    '₪${amount.toStringAsFixed(0)} → $customerName (עבודה: $jobId)',
          'userId':    customerId,
          'priority':  'high',
          'createdAt': FieldValue.serverTimestamp(),
          'expireAt':  Timestamp.fromDate(
              DateTime.now().add(const Duration(days: 30))),
        });
      } catch (_) {}

      // Notify customer
      try {
        FirebaseFirestore.instance.collection('notifications').add({
          'userId':    customerId,
          'title':     'החזר כספי',
          'body':      'קיבלת החזר של ₪${amount.toStringAsFixed(0)} לארנק שלך.',
          'type':      'refund',
          'isRead':    false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}

      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('הוחזרו ₪${amount.toStringAsFixed(0)} ל-$customerName'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      debugPrint('[AdminRefund] Error: $e');
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('שגיאה בהחזר: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  static Widget _refundRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildEarningsChart() {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);

    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('platform_earnings')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .orderBy('timestamp')
          .get(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(),
          ));
        }

        // Group by day-of-month
        final Map<int, double> byDay = {};
        for (final doc in snap.data!.docs) {
          final d = doc.data() as Map<String, dynamic>;
          final ts = (d['timestamp'] as Timestamp?)?.toDate();
          if (ts == null) continue;
          final fee = ((d['platformFee'] ?? d['amount'] ?? 0) as num).toDouble();
          byDay[ts.day] = (byDay[ts.day] ?? 0) + fee;
        }

        final total = byDay.values.fold(0.0, (a, b) => a + b);
        final maxVal = byDay.values.fold(0.0, (a, b) => a > b ? a : b);

        if (byDay.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text("אין עמלות החודש עדיין",
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Total badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text("סה״כ החודש: ₪${total.toStringAsFixed(0)}",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                      fontSize: 15)),
            ),
            const SizedBox(height: 16),
            // Bar chart
            SizedBox(
              height: 110,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(daysInMonth, (i) {
                  final day = i + 1;
                  final val = byDay[day] ?? 0;
                  final frac = maxVal > 0 ? val / maxVal : 0.0;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (val > 0)
                            Tooltip(
                              message: "יום $day: ₪${val.toStringAsFixed(0)}",
                              child: Container(
                                height: (frac * 85).clamp(3.0, 85.0),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            )
                          else
                            Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          const SizedBox(height: 2),
                          if (day % 7 == 1 || day == daysInMonth)
                            Text("$day",
                                style: TextStyle(
                                    fontSize: 7, color: Colors.grey[500]))
                          else
                            const SizedBox(height: 9),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        );
      },
    );
  }
}
