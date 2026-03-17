import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';

class MyCalendarScreen extends StatefulWidget {
  const MyCalendarScreen({super.key});

  @override
  State<MyCalendarScreen> createState() => _MyCalendarScreenState();
}

class _MyCalendarScreenState extends State<MyCalendarScreen> {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay   = DateTime.now();
  DateTime? _selectedDay = DateTime.now();

  // Map from date (midnight) → list of job docs
  final Map<DateTime, List<Map<String, dynamic>>> _events = {};

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  // ── Load all active/upcoming jobs for this provider ─────────────────────────
  Future<void> _loadJobs() async {
    if (_uid == null) return;

    final snap = await FirebaseFirestore.instance
        .collection('jobs')
        .where('expertId', isEqualTo: _uid)
        .where('status', whereIn: ['paid_escrow', 'expert_completed', 'completed'])
        .limit(100)
        .get();

    final Map<DateTime, List<Map<String, dynamic>>> events = {};

    for (final doc in snap.docs) {
      final data = doc.data();
      final ts = data['appointmentDate'] as Timestamp?;
      if (ts == null) continue;

      final date = _midnight(ts.toDate());
      events[date] = [...(events[date] ?? []), {...data, 'jobId': doc.id}];
    }

    if (mounted) setState(() => _events.addAll(events));
  }

  DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

  List<Map<String, dynamic>> _eventsForDay(DateTime day) =>
      _events[_midnight(day)] ?? [];

  // ── Color by status ──────────────────────────────────────────────────────────
  Color _statusColor(String? status) {
    switch (status) {
      case 'paid_escrow':      return const Color(0xFF6366F1);
      case 'expert_completed': return Colors.orange;
      case 'completed':        return Colors.green;
      default:                 return Colors.grey;
    }
  }

  String _statusLabel(String? status, AppLocalizations l10n) {
    switch (status) {
      case 'paid_escrow':      return l10n.calendarStatusPending;
      case 'expert_completed': return l10n.calendarStatusWaiting;
      case 'completed':        return l10n.calendarStatusCompleted;
      default:                 return status ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selectedEvents = _eventsForDay(_selectedDay ?? _focusedDay);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        title: Text(
          l10n.calendarTitle,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n.calendarRefresh,
            onPressed: () {
              setState(() => _events.clear());
              _loadJobs();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Calendar widget ────────────────────────────────────────────────
          Card(
            margin: const EdgeInsets.all(12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 2,
            child: TableCalendar<Map<String, dynamic>>(
              locale: 'he_IL',
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay:  DateTime.utc(2030, 12, 31),
              focusedDay:    _focusedDay,
              selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
              calendarFormat: _calendarFormat,
              eventLoader:   _eventsForDay,
              startingDayOfWeek: StartingDayOfWeek.sunday,
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                selectedDecoration: const BoxDecoration(
                  color: Color(0xFF6366F1),
                  shape: BoxShape.circle,
                ),
                markerDecoration: const BoxDecoration(
                  color: Color(0xFF6366F1),
                  shape: BoxShape.circle,
                ),
                weekendTextStyle: const TextStyle(color: Color(0xFF6366F1)),
              ),
              headerStyle: const HeaderStyle(
                formatButtonVisible: true,
                titleCentered: true,
                formatButtonDecoration: BoxDecoration(
                  color: Color(0xFF6366F1),
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                formatButtonTextStyle: TextStyle(color: Colors.white, fontSize: 12),
              ),
              onDaySelected: (selected, focused) {
                setState(() {
                  _selectedDay  = selected;
                  _focusedDay   = focused;
                });
              },
              onFormatChanged: (format) {
                if (_calendarFormat != format) {
                  setState(() => _calendarFormat = format);
                }
              },
              onPageChanged: (focused) => _focusedDay = focused,
            ),
          ),

          // ── Selected day header ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  _selectedDay != null
                      ? DateFormat('EEEE, d בMMMM', 'he_IL').format(_selectedDay!)
                      : '',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(width: 8),
                if (selectedEvents.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${selectedEvents.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),

          // ── Event list ─────────────────────────────────────────────────────
          Expanded(
            child: selectedEvents.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.event_available, size: 48, color: Colors.grey),
                        const SizedBox(height: 8),
                        Text(l10n.calendarNoEvents, style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: selectedEvents.length,
                    itemBuilder: (context, i) {
                      final job = selectedEvents[i];
                      final status = job['status'] as String?;
                      final time   = job['appointmentTime'] as String? ?? '';
                      final customer = job['customerName'] as String? ?? l10n.disputePartyCustomer;
                      final amount = (job['totalAmount'] as num?)?.toStringAsFixed(0) ?? '—';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: _statusColor(status).withValues(alpha: 0.3)),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _statusColor(status).withValues(alpha: 0.1),
                            child: Icon(Icons.person_outline, color: _statusColor(status)),
                          ),
                          title: Text(customer, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (time.isNotEmpty)
                                Row(children: [
                                  const Icon(Icons.access_time, size: 13, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text(time, style: const TextStyle(fontSize: 12)),
                                ]),
                              Row(children: [
                                Icon(Icons.circle, size: 8, color: _statusColor(status)),
                                const SizedBox(width: 4),
                                Text(_statusLabel(status, l10n), style: TextStyle(fontSize: 12, color: _statusColor(status))),
                              ]),
                            ],
                          ),
                          trailing: Text(
                            '₪$amount',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
