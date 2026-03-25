// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AdminPayoutsTab extends StatefulWidget {
  const AdminPayoutsTab({super.key});

  @override
  State<AdminPayoutsTab> createState() => _AdminPayoutsTabState();
}

class _AdminPayoutsTabState extends State<AdminPayoutsTab> {
  List<_PayoutGroup> _groups = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error   = null;
    });
    try {
      final now  = DateTime.now();
      final cutoff = now.subtract(const Duration(days: 7));

      final snap = await FirebaseFirestore.instance
          .collection('transactions')
          .limit(400)
          .get();

      // Group eligible transactions by receiverId
      final Map<String, double>        totals = {};
      final Map<String, List<String>>  docIds = {};

      for (final doc in snap.docs) {
        final d   = doc.data();
        final receiverId  = (d['receiverId'] as String? ?? '').trim();
        final amount      = (d['amount'] as num?)?.toDouble() ?? 0;
        final type        = (d['type'] as String? ?? '').trim();
        final payoutStatus = (d['payoutStatus'] as String? ?? '').trim();
        final ts          = d['timestamp'] as Timestamp?;

        if (receiverId.isEmpty) continue;
        if (amount <= 0) continue;
        if (type == 'refund' || type == 'admin_topup') continue;
        if (payoutStatus == 'paid') continue;
        if (ts == null) continue;
        if (!ts.toDate().isBefore(cutoff)) continue;

        totals[receiverId] = (totals[receiverId] ?? 0) + amount;
        docIds.putIfAbsent(receiverId, () => []).add(doc.id);
      }

      final groups = totals.entries
          .where((e) => e.value > 0)
          .map((e) => _PayoutGroup(
                receiverId: e.key,
                total:      e.value,
                docIds:     docIds[e.key] ?? [],
              ))
          .toList()
        ..sort((a, b) => b.total.compareTo(a.total));

      if (mounted) {
        setState(() {
          _groups  = groups;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error   = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 48),
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('נסה שוב'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: CustomScrollView(
                    slivers: [
                      // ── Header ────────────────────────────────────────────
                      SliverToBoxAdapter(
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF1A0E3C), Color(0xFF3D1F8B)],
                              begin: Alignment.topLeft,
                              end:   Alignment.bottomRight,
                            ),
                          ),
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(
                                    onPressed: _load,
                                    icon: const Icon(Icons.refresh,
                                        color: Colors.white70),
                                  ),
                                  const Text(
                                    'תשלומים שבועיים',
                                    style: TextStyle(
                                      color:      Colors.white,
                                      fontSize:   20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${_groups.length} ספקים ממתינים לתשלום',
                                style: TextStyle(
                                  color:    Colors.white.withValues(alpha: 0.70),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'הכנסות ישנות מ-7 ימים שטרם שולמו',
                                style: TextStyle(
                                  color:    Colors.white.withValues(alpha: 0.50),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ── Empty state ───────────────────────────────────────
                      if (_groups.isEmpty)
                        const SliverFillRemaining(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_outline_rounded,
                                    size: 64, color: Colors.green),
                                SizedBox(height: 12),
                                Text('אין תשלומים ממתינים',
                                    style: TextStyle(
                                        fontSize:   18,
                                        fontWeight: FontWeight.bold,
                                        color:      Color(0xFF1A1A2E))),
                                SizedBox(height: 6),
                                Text('כל הספקים שולמו',
                                    style:
                                        TextStyle(color: Colors.grey)),
                              ],
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.all(16),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final group = _groups[index];
                                return _PayoutExpertCard(
                                  group:   group,
                                  onPaid: () {
                                    if (!mounted) return;
                                    setState(() => _groups.removeAt(index));
                                  },
                                );
                              },
                              childCount: _groups.length,
                            ),
                          ),
                        ),

                      const SliverPadding(
                          padding: EdgeInsets.only(bottom: 80)),
                    ],
                  ),
                ),
    );
  }
}

// ── Model ─────────────────────────────────────────────────────────────────────

class _PayoutGroup {
  final String       receiverId;
  final double       total;
  final List<String> docIds;
  const _PayoutGroup({
    required this.receiverId,
    required this.total,
    required this.docIds,
  });
}

// ── Expert payout card ────────────────────────────────────────────────────────

class _PayoutExpertCard extends StatefulWidget {
  final _PayoutGroup  group;
  final VoidCallback  onPaid;
  const _PayoutExpertCard({
    required this.group,
    required this.onPaid,
  });

  @override
  State<_PayoutExpertCard> createState() => _PayoutExpertCardState();
}

class _PayoutExpertCardState extends State<_PayoutExpertCard> {
  String? _name;
  Map<String, dynamic> _bankDetails = {};
  bool _loadingUser = true;
  bool _marking     = false;

  @override
  void initState() {
    super.initState();
    _fetchUser();
  }

  Future<void> _fetchUser() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.group.receiverId)
          .get();
      if (!mounted) return;
      final data = doc.data() ?? {};
      setState(() {
        _name        = data['name'] as String? ??
                       data['displayName'] as String? ??
                       widget.group.receiverId;
        _bankDetails = (data['bankDetails'] as Map<String, dynamic>?) ?? {};
        _loadingUser = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _name        = widget.group.receiverId;
          _loadingUser = false;
        });
      }
    }
  }

  Future<void> _markAsPaid() async {
    setState(() => _marking = true);
    try {
      final db      = FirebaseFirestore.instance;
      final docIds  = widget.group.docIds;

      // Firestore batch limit = 500 writes per batch
      for (var i = 0; i < docIds.length; i += 500) {
        final chunk = docIds.sublist(
            i, (i + 500) > docIds.length ? docIds.length : i + 500);
        final bat = db.batch();
        for (final id in chunk) {
          bat.update(db.collection('transactions').doc(id),
              {'payoutStatus': 'paid'});
        }
        await bat.commit();
      }

      widget.onPaid();
    } catch (e) {
      if (mounted) {
        setState(() => _marking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'he_IL', symbol: '₪', decimalDigits: 0);

    return Card(
      elevation:   2,
      margin:      const EdgeInsets.only(bottom: 14),
      shape:       RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: _loadingUser
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child:   CircularProgressIndicator(),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // ── Expert name ────────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Total amount chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFDE68A), Color(0xFFF59E0B)],
                          ),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          fmt.format(widget.group.total),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize:   16,
                            color:      Color(0xFF78350F),
                          ),
                        ),
                      ),
                      // Name
                      Expanded(
                        child: Text(
                          _name ?? '',
                          textAlign:  TextAlign.right,
                          overflow:   TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize:   16,
                            color:      Color(0xFF1A1A2E),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // ── Bank details ───────────────────────────────────────
                  if (_bankDetails.isEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'לא הוזנו פרטי בנק',
                        style: TextStyle(color: Colors.grey[500], fontSize: 13),
                      ),
                    )
                  else ...[
                    _bankRow(Icons.person_outline_rounded,
                        'שם בעל החשבון',
                        _bankDetails['accountHolder'] as String? ?? '—'),
                    _bankRow(Icons.business_outlined,
                        'בנק',
                        _bankDetails['bankName'] as String? ?? '—'),
                    _bankRow(Icons.pin_outlined,
                        'סניף',
                        _bankDetails['branch'] as String? ?? '—'),
                    _bankRow(Icons.credit_card_outlined,
                        'מספר חשבון',
                        _bankDetails['accountNumber'] as String? ?? '—'),
                  ],

                  const SizedBox(height: 16),

                  // ── Mark as paid button ────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        elevation:       0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: _marking ? null : _markAsPaid,
                      icon: _marking
                          ? const SizedBox(
                              width:  16,
                              height: 16,
                              child:  CircularProgressIndicator(
                                color:      Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline_rounded,
                              size: 18),
                      label: Text(
                        _marking ? 'מעדכן...' : 'סמן כשולם ✓',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),

                  // ── Doc count ─────────────────────────────────────────
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${widget.group.docIds.length} עסקאות',
                      style: TextStyle(color: Colors.grey[400], fontSize: 11),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _bankRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF374151)),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$label:',
            style: const TextStyle(
                fontSize: 12,
                color:    Colors.grey,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 6),
          Icon(icon, size: 16, color: const Color(0xFF6366F1)),
        ],
      ),
    );
  }
}
