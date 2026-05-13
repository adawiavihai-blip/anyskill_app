// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../theme/app_theme.dart';
import '../widgets/bookings/booking_shared_widgets.dart';
import 'service_history_detail_screen.dart';

/// Premium "Services Received" screen — full lifetime history of every service
/// the customer ever booked. Reads `jobs` where `customerId == currentUser`,
/// groups by date buckets (this month / last month / older years), supports
/// status filtering + search, and pushes a rich detail screen on tap.
///
/// Wired from [ProfileScreen]'s "שירות שהתקבל" card.
class ServiceHistoryScreen extends StatefulWidget {
  const ServiceHistoryScreen({super.key});

  @override
  State<ServiceHistoryScreen> createState() => _ServiceHistoryScreenState();
}

enum _StatusFilter { all, completed, active, cancelled }

class _ServiceHistoryScreenState extends State<ServiceHistoryScreen> {
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  late final Stream<QuerySnapshot> _stream;

  _StatusFilter _filter = _StatusFilter.all;
  String _query = '';
  final TextEditingController _searchCtrl = TextEditingController();

  bool _streamTimedOut = false;
  Timer? _timeoutTimer;

  static const _activeStatuses = {
    'paid_escrow',
    'expert_completed',
    'disputed',
    'pending',
    'accepted',
    'in_progress',
    'awaiting_payment',
  };

  static const _cancelledStatuses = {
    'cancelled',
    'cancelled_with_penalty',
    'refunded',
  };

  @override
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collection('jobs')
        .where('customerId', isEqualTo: _uid)
        .limit(500)
        .snapshots();
    _timeoutTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && !_streamTimedOut) {
        setState(() => _streamTimedOut = true);
      }
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matchesFilter(String status) {
    switch (_filter) {
      case _StatusFilter.all:
        return true;
      case _StatusFilter.completed:
        return status == 'completed' || status == 'split_resolved';
      case _StatusFilter.active:
        return _activeStatuses.contains(status);
      case _StatusFilter.cancelled:
        return _cancelledStatuses.contains(status);
    }
  }

  bool _matchesQuery(Map<String, dynamic> job) {
    if (_query.trim().isEmpty) return true;
    final q = _query.toLowerCase();
    final hay = [
      job['expertName'],
      job['serviceType'],
      job['description'],
      job['address'],
    ].whereType<String>().join(' ').toLowerCase();
    return hay.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FB),
      body: StreamBuilder<QuerySnapshot>(
        stream: _stream,
        builder: (context, snap) {
          if (!snap.hasData && !_streamTimedOut) {
            return _buildLoadingScaffold();
          }

          if (snap.hasError) {
            return _buildErrorScaffold(snap.error.toString());
          }

          final all = snap.data?.docs ?? [];
          final visible = all.where((d) {
            final job = d.data() as Map<String, dynamic>? ?? {};
            final status = job['status'] as String? ?? '';
            return _matchesFilter(status) && _matchesQuery(job);
          }).toList()
            ..sort((a, b) {
              final ta = (a.data() as Map)['createdAt'];
              final tb = (b.data() as Map)['createdAt'];
              if (ta is Timestamp && tb is Timestamp) {
                return tb.compareTo(ta);
              }
              return 0;
            });

          return CustomScrollView(
            slivers: [
              _buildSliverAppBar(all),
              SliverToBoxAdapter(child: _buildHeroStatsRow(all)),
              SliverToBoxAdapter(child: _buildFilterChips()),
              SliverToBoxAdapter(child: _buildSearchBar()),
              if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(all.isEmpty),
                )
              else
                ..._buildGroupedSlivers(visible),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
      ),
    );
  }

  // ── App bar with gradient ─────────────────────────────────────────────
  Widget _buildSliverAppBar(List<QueryDocumentSnapshot> all) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 0,
      elevation: 0,
      backgroundColor: Brand.indigo,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded,
            color: Colors.white, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Brand.indigo, Brand.purple],
          ),
        ),
      ),
      title: const Text(
        'השירותים שקיבלתי',
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      centerTitle: true,
    );
  }

  // ── Hero stats: count, total spent, avg rating ────────────────────────
  Widget _buildHeroStatsRow(List<QueryDocumentSnapshot> all) {
    int completedCount = 0;
    double totalSpent = 0;
    String? favoriteCategory;
    final catCounts = <String, int>{};

    for (final d in all) {
      final job = d.data() as Map<String, dynamic>? ?? {};
      final status = job['status'] as String? ?? '';
      if (status == 'completed' || status == 'split_resolved') {
        completedCount++;
        final amount =
            (job['totalAmount'] ?? job['totalPaidByCustomer'] ?? 0) as num;
        totalSpent += amount.toDouble();
      }
      final cat = (job['serviceType'] as String? ?? '').trim();
      if (cat.isNotEmpty) {
        catCounts[cat] = (catCounts[cat] ?? 0) + 1;
      }
    }
    if (catCounts.isNotEmpty) {
      catCounts.forEach((k, v) {
        favoriteCategory ??= k;
        if (v > (catCounts[favoriteCategory!] ?? 0)) {
          favoriteCategory = k;
        }
      });
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Brand.indigo, Brand.purple],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Brand.indigo.withValues(alpha: 0.30),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatTile(
              icon: Icons.assignment_turned_in_rounded,
              value: '$completedCount',
              label: 'שירותים\nשהושלמו',
            ),
          ),
          _Divider(),
          Expanded(
            child: _StatTile(
              icon: Icons.account_balance_wallet_rounded,
              value: '₪${totalSpent.toStringAsFixed(0)}',
              label: 'סה"כ\nהוצאה',
            ),
          ),
          _Divider(),
          Expanded(
            child: _StatTile(
              icon: Icons.favorite_rounded,
              value: favoriteCategory == null
                  ? '—'
                  : (favoriteCategory!.length > 8
                      ? '${favoriteCategory!.substring(0, 8)}…'
                      : favoriteCategory!),
              label: 'תחום\nמועדף',
            ),
          ),
        ],
      ),
    );
  }

  // ── Filter pills ──────────────────────────────────────────────────────
  Widget _buildFilterChips() {
    final entries = [
      (_StatusFilter.all, 'הכל', Icons.list_rounded),
      (_StatusFilter.completed, 'הושלם', Icons.check_circle_outline_rounded),
      (_StatusFilter.active, 'פעיל', Icons.bolt_rounded),
      (_StatusFilter.cancelled, 'בוטל', Icons.cancel_outlined),
    ];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (filter, label, icon) = entries[i];
          final selected = filter == _filter;
          return GestureDetector(
            onTap: () => setState(() => _filter = filter),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? Brand.indigo : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? Brand.indigo : const Color(0xFFE5E7EB),
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: Brand.indigo.withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Icon(icon,
                      size: 16,
                      color: selected ? Colors.white : Brand.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : Brand.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Search field ──────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: TextField(
          controller: _searchCtrl,
          textInputAction: TextInputAction.search,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'חפש לפי נותן שירות, קטגוריה או תיאור…',
            hintStyle: const TextStyle(
                color: Color(0xFF9CA3AF), fontSize: 13),
            prefixIcon: const Icon(Icons.search_rounded,
                color: Color(0xFF9CA3AF), size: 20),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Color(0xFF9CA3AF), size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                  ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  // ── Grouped slivers (this month / last month / year buckets) ──────────
  List<Widget> _buildGroupedSlivers(List<QueryDocumentSnapshot> docs) {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 1);
    final lastMonth = DateTime(now.year, now.month - 1, 1);

    final groups = <String, List<QueryDocumentSnapshot>>{};
    for (final doc in docs) {
      final job = doc.data() as Map<String, dynamic>? ?? {};
      final ts = job['createdAt'] as Timestamp?;
      final date = ts?.toDate() ?? DateTime(2000);

      String key;
      if (!date.isBefore(thisMonth)) {
        key = 'החודש';
      } else if (!date.isBefore(lastMonth)) {
        key = 'חודש שעבר';
      } else {
        key = '${date.year}';
      }
      groups.putIfAbsent(key, () => []).add(doc);
    }

    // Preserve order: החודש → חודש שעבר → years descending
    final orderedKeys = <String>[];
    if (groups.containsKey('החודש')) orderedKeys.add('החודש');
    if (groups.containsKey('חודש שעבר')) orderedKeys.add('חודש שעבר');
    final yearKeys = groups.keys
        .where((k) => k != 'החודש' && k != 'חודש שעבר')
        .toList()
      ..sort((a, b) => b.compareTo(a));
    orderedKeys.addAll(yearKeys);

    return [
      for (final k in orderedKeys) ...[
        SliverToBoxAdapter(
          child: _buildGroupHeader(k, groups[k]!.length),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, idx) => _buildServiceCard(groups[k]![idx]),
            childCount: groups[k]!.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
      ],
    ];
  }

  Widget _buildGroupHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 8),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Brand.textMuted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Brand.indigo,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Service card (premium) ────────────────────────────────────────────
  Widget _buildServiceCard(QueryDocumentSnapshot doc) {
    final job = doc.data() as Map<String, dynamic>? ?? {};
    final jobId = doc.id;
    final expertId = job['expertId'] as String? ?? '';
    final expertName = job['expertName'] as String? ?? 'נותן שירות';
    final status = job['status'] as String? ?? '';
    final amount = ((job['totalAmount'] ??
            job['totalPaidByCustomer'] ??
            0.0) as num)
        .toDouble();
    final serviceType = job['serviceType'] as String? ?? '';
    final description = job['description'] as String? ?? '';

    DateTime? appt;
    String? apptTimeStr;
    if (job['appointmentDate'] is Timestamp) {
      appt = (job['appointmentDate'] as Timestamp).toDate();
    }
    if (job['appointmentTime'] is String) {
      apptTimeStr = job['appointmentTime'] as String;
    }
    DateTime? completed;
    if (job['completedAt'] is Timestamp) {
      completed = (job['completedAt'] as Timestamp).toDate();
    }
    DateTime? created;
    if (job['createdAt'] is Timestamp) {
      created = (job['createdAt'] as Timestamp).toDate();
    }
    final dateForDisplay = appt ?? completed ?? created;
    final dateStr = dateForDisplay != null
        ? DateFormat('dd/MM/yyyy', 'he').format(dateForDisplay)
        : '—';
    final timeStr = apptTimeStr ??
        (dateForDisplay != null
            ? DateFormat('HH:mm', 'he').format(dateForDisplay)
            : '');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ServiceHistoryDetailScreen(
                jobId: jobId,
                initialJob: job,
              ),
            ),
          ),
          child: Container(
            padding:
                const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
              border: Border.all(color: const Color(0xFFEEF0F5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BookingProfileAvatar(
                    uid: expertId, name: expertName, size: 54),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              expertName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Brand.textDark,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          BookingStatusBadge(status),
                        ],
                      ),
                      if (serviceType.isNotEmpty) ...[
                        const SizedBox(height: 4),
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
                              color: Brand.indigo,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      if (description.isNotEmpty &&
                          description != serviceType) ...[
                        const SizedBox(height: 6),
                        Text(
                          description,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: Brand.textMuted,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded,
                              size: 12, color: Brand.textLight),
                          const SizedBox(width: 4),
                          Text(
                            dateStr,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Brand.textLight,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (timeStr.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.schedule_rounded,
                                size: 12, color: Brand.textLight),
                            const SizedBox(width: 3),
                            Text(
                              timeStr,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Brand.textLight,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
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
                const SizedBox(width: 4),
                const Icon(Icons.chevron_left_rounded,
                    color: Brand.textLight),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── States ────────────────────────────────────────────────────────────
  Widget _buildLoadingScaffold() {
    return Column(
      children: [
        Container(
          height: kToolbarHeight + MediaQuery.of(context).padding.top,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Brand.indigo, Brand.purple],
            ),
          ),
          child: SafeArea(
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded,
                      color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                const Expanded(
                  child: Center(
                    child: Text(
                      'השירותים שקיבלתי',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),
        ),
        const Expanded(child: BookingsShimmer()),
      ],
    );
  }

  Widget _buildErrorScaffold(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 56, color: Brand.error),
            const SizedBox(height: 14),
            const Text(
              'לא הצלחנו לטעון את ההיסטוריה',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Brand.textDark),
            ),
            const SizedBox(height: 6),
            Text(
              'נסה שוב בעוד רגע',
              style: TextStyle(
                  fontSize: 13, color: Brand.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool fullEmpty) {
    final title = fullEmpty
        ? 'עדיין אין שירותים בהיסטוריה'
        : 'לא נמצאו שירותים תואמים';
    final subtitle = fullEmpty
        ? 'כל שירות שתזמין יופיע כאן ברגע שיתחיל.'
        : 'נסה להחליף סינון או לנקות את החיפוש.';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              color: Color(0xFFEEF2FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.history_rounded,
                size: 48, color: Brand.indigo),
          ),
          const SizedBox(height: 18),
          Text(title,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Brand.textDark)),
          const SizedBox(height: 6),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, color: Brand.textMuted, height: 1.4)),
        ],
      ),
    );
  }
}

// ── Hero stat tile ─────────────────────────────────────────────────────────
class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 10.5,
            height: 1.2,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.white.withValues(alpha: 0.20),
    );
  }
}
