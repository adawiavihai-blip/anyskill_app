// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../widgets/bookings/booking_shared_widgets.dart';
import '../../widgets/bookings/calendar_widgets.dart';

/// Self-contained calendar tab that owns ALL calendar/availability state.
///
/// Extracted from my_bookings_screen.dart. Receives the expert Firestore
/// stream and the current user ID from the parent screen.
class CalendarTab extends StatefulWidget {
  final String currentUserId;
  final Stream<QuerySnapshot> expertStream;

  const CalendarTab({
    super.key,
    required this.currentUserId,
    required this.expertStream,
  });

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  // ── Calendar / availability state ─────────────────────────────────────
  Set<DateTime> _unavailableDates = {};
  DateTime _calendarFocusedDay = DateTime.now();
  DateTime? _selectedCalendarDay;
  bool _calendarSaving = false;

  /// Hourly time blocks: [{date: 'YYYY-MM-DD', from: 'HH:mm', to: 'HH:mm', reason: 'personal'|'break'|'appointment'}]
  List<Map<String, dynamic>> _timeBlocks = [];

  /// Recurring weekly rules: [{dayIndex: 0-6, type: 'off'|'hours', from?: 'HH:mm', to?: 'HH:mm'}]
  List<Map<String, dynamic>> _recurringRules = [];

  /// Working hours from user doc (read-only in calendar, edited in profile)
  Map<int, Map<String, String>> _workingHours = {};

  /// Hebrew day names
  static const _kDayNamesHe = [
    'ראשון',
    'שני',
    'שלישי',
    'רביעי',
    'חמישי',
    'שישי',
    'שבת'
  ];

  @override
  void initState() {
    super.initState();
    _loadUnavailableDates();
  }

  // ── Availability data loading ──────────────────────────────────────────
  Future<void> _loadUnavailableDates() async {
    if (widget.currentUserId.isEmpty) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.currentUserId)
        .get();
    final data = doc.data() ?? {};

    // Legacy full-day blocks
    final List<dynamic> raw =
        (data['unavailableDates'] as List<dynamic>?) ?? [];

    // Hourly time blocks
    final List<dynamic> rawBlocks =
        (data['timeBlocks'] as List<dynamic>?) ?? [];

    // Recurring rules
    final List<dynamic> rawRules =
        (data['recurringRules'] as List<dynamic>?) ?? [];

    // Working hours
    final rawHours = data['workingHours'] as Map<String, dynamic>? ?? {};
    final parsedHours = <int, Map<String, String>>{};
    for (final entry in rawHours.entries) {
      final day = int.tryParse(entry.key);
      if (day != null && entry.value is Map) {
        final m = entry.value as Map;
        parsedHours[day] = {
          'from': m['from']?.toString() ?? '09:00',
          'to': m['to']?.toString() ?? '17:00',
        };
      }
    }

    if (mounted) {
      setState(() {
        _unavailableDates = raw
            .map((d) => DateTime.tryParse(d.toString()))
            .whereType<DateTime>()
            .map((d) => DateTime.utc(d.year, d.month, d.day))
            .toSet();
        _timeBlocks = rawBlocks
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        _recurringRules = rawRules
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        _workingHours = parsedHours;
      });
    }
  }

  Future<void> _saveAvailability() async {
    setState(() => _calendarSaving = true);
    try {
      final isoStrings = _unavailableDates
          .map((d) => '${d.year.toString().padLeft(4, '0')}-'
              '${d.month.toString().padLeft(2, '0')}-'
              '${d.day.toString().padLeft(2, '0')}')
          .toList();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.currentUserId)
          .update({
        'unavailableDates': isoStrings,
        'timeBlocks': _timeBlocks,
        'recurringRules': _recurringRules,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              backgroundColor: const Color(0xFF16A34A),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              content: const Row(children: [
                Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('הזמינות עודכנה בהצלחה',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ])),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              backgroundColor: Colors.red,
              content: Text('שגיאה בשמירה: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _calendarSaving = false);
    }
  }

  /// Check if a specific day is blocked by a recurring rule
  bool _isDayBlockedByRule(DateTime day) {
    final dayIndex = day.weekday == 7 ? 0 : day.weekday;
    return _recurringRules
        .any((r) => r['dayIndex'] == dayIndex && r['type'] == 'off');
  }

  /// Get recurring hours override for a day (null = use workingHours)
  Map<String, dynamic>? _getRecurringHoursForDay(DateTime day) {
    final dayIndex = day.weekday == 7 ? 0 : day.weekday;
    try {
      return _recurringRules.firstWhere(
          (r) => r['dayIndex'] == dayIndex && r['type'] == 'hours');
    } catch (_) {
      return null;
    }
  }

  /// Get time blocks for a specific date
  List<Map<String, dynamic>> _getBlocksForDate(DateTime day) {
    final key = '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    return _timeBlocks.where((b) => b['date'] == key).toList()
      ..sort((a, b) => (a['from'] ?? '').compareTo(b['from'] ?? ''));
  }

  /// Check if a day is fully blocked (full-day block OR recurring off)
  bool _isDayFullyBlocked(DateTime day) {
    final norm = DateTime.utc(day.year, day.month, day.day);
    return _unavailableDates.contains(norm) || _isDayBlockedByRule(day);
  }

  /// Get working hours for a given day (considering recurring overrides)
  (String from, String to)? _getEffectiveHours(DateTime day) {
    if (_isDayFullyBlocked(day)) return null;
    final recurring = _getRecurringHoursForDay(day);
    if (recurring != null) {
      return (
        recurring['from'] as String? ?? '09:00',
        recurring['to'] as String? ?? '17:00'
      );
    }
    final dayIndex = day.weekday == 7 ? 0 : day.weekday;
    final wh = _workingHours[dayIndex];
    if (wh == null) return null;
    return (wh['from'] ?? '09:00', wh['to'] ?? '17:00');
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: widget.expertStream,
      builder: (context, snap) {
        // ── Build appointment-day lookup from stream data ──────────────
        final appointmentDays = <DateTime>{};
        final jobsByDay = <DateTime, List<Map<String, dynamic>>>{};
        int weekJobCount = 0;
        final now = DateTime.now();
        final weekStart =
            now.subtract(Duration(days: now.weekday == 7 ? 0 : now.weekday));
        final weekEnd = weekStart.add(const Duration(days: 7));

        for (final doc in snap.data?.docs ?? []) {
          final d = doc.data() as Map<String, dynamic>;
          final ts = d['appointmentDate'] as Timestamp?;
          if (ts == null) continue;
          final dt = ts.toDate();
          final norm = DateTime.utc(dt.year, dt.month, dt.day);
          appointmentDays.add(norm);
          jobsByDay.putIfAbsent(norm, () => []).add(d);
          // Count jobs this week
          if (dt.isAfter(weekStart) && dt.isBefore(weekEnd)) weekJobCount++;
        }

        // ── Weekly available hours calculation ─────────────────────────
        int weekAvailableHours = 0;
        for (int i = 0; i < 7; i++) {
          final day = weekStart.add(Duration(days: i));
          final hours = _getEffectiveHours(day);
          if (hours != null) {
            final fromH = int.tryParse(hours.$1.split(':').first) ?? 0;
            final toH = int.tryParse(hours.$2.split(':').first) ?? 0;
            weekAvailableHours += (toH - fromH).clamp(0, 24);
          }
        }

        // Jobs for the currently selected day
        final selNorm = _selectedCalendarDay == null
            ? null
            : DateTime.utc(_selectedCalendarDay!.year,
                _selectedCalendarDay!.month, _selectedCalendarDay!.day);
        final selJobs = selNorm == null
            ? <Map<String, dynamic>>[]
            : (jobsByDay[selNorm] ?? []);
        final selBlocks = _selectedCalendarDay == null
            ? <Map<String, dynamic>>[]
            : _getBlocksForDate(_selectedCalendarDay!);

        return Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ══════════════════════════════════════════════════════
                  // HEADER — Title + Google Calendar placeholder
                  // ══════════════════════════════════════════════════════
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('יומן עסקי',
                                style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1A1A2E))),
                            const SizedBox(height: 2),
                            Text(
                              'נהל זמינות, חסימות וסדר יום',
                              style: TextStyle(
                                  color: Colors.grey[500], fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      // Google Calendar sync placeholder
                      Material(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFF6366F1),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                content: const Row(children: [
                                  Icon(Icons.info_outline_rounded,
                                      color: Colors.white, size: 18),
                                  SizedBox(width: 8),
                                  Text('סנכרון Google Calendar — בקרוב!',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600)),
                                ]),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.sync_rounded,
                                      size: 16, color: Colors.grey[600]),
                                  const SizedBox(width: 6),
                                  Text('Google',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                          fontWeight: FontWeight.w600)),
                                ]),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // ══════════════════════════════════════════════════════
                  // WEEKLY SUMMARY — Jobs + Hours
                  // ══════════════════════════════════════════════════════
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1)
                              .withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Jobs this week
                        Expanded(
                          child: Row(children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.work_rounded,
                                  color: Colors.white, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$weekJobCount',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800)),
                                const Text('הזמנות השבוע',
                                    style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11)),
                              ],
                            ),
                          ]),
                        ),
                        // Divider
                        Container(
                          width: 1,
                          height: 36,
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                        const SizedBox(width: 16),
                        // Available hours
                        Expanded(
                          child: Row(children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.schedule_rounded,
                                  color: Colors.white, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$weekAvailableHours שעות',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800)),
                                const Text('זמינות השבוע',
                                    style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11)),
                              ],
                            ),
                          ]),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ══════════════════════════════════════════════════════
                  // LEGEND BAR
                  // ══════════════════════════════════════════════════════
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: const Color(0xFFEEEEEE)),
                    ),
                    child: Row(children: [
                      _buildLegendDot(
                          const Color(0xFF6366F1), 'הזמנה'),
                      const SizedBox(width: 16),
                      _buildLegendDot(
                          const Color(0xFFEF4444), 'חסום'),
                      const SizedBox(width: 16),
                      _buildLegendDot(
                          const Color(0xFFF97316), 'חלקי'),
                      const SizedBox(width: 16),
                      _buildLegendDot(
                          const Color(0xFF10B981), 'זמין'),
                      const Spacer(),
                      Text('לחיצה ארוכה = חסימה',
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey[400])),
                    ]),
                  ),

                  const SizedBox(height: 12),

                  // ══════════════════════════════════════════════════════
                  // TABLE CALENDAR
                  // ══════════════════════════════════════════════════════
                  Container(
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
                    child: TableCalendar(
                      firstDay: DateTime.now()
                          .subtract(const Duration(days: 365)),
                      lastDay: DateTime.now()
                          .add(const Duration(days: 365)),
                      focusedDay: _calendarFocusedDay,
                      calendarFormat: CalendarFormat.month,
                      availableCalendarFormats: const {
                        CalendarFormat.month: 'חודש'
                      },
                      startingDayOfWeek: StartingDayOfWeek.sunday,
                      headerStyle: HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                        titleTextStyle: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16),
                        leftChevronIcon: Icon(
                            Icons.chevron_left_rounded,
                            color: Colors.grey[700]),
                        rightChevronIcon: Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.grey[700]),
                      ),
                      daysOfWeekStyle: DaysOfWeekStyle(
                        weekdayStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[500]),
                        weekendStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[500]),
                      ),
                      eventLoader: (day) {
                        final norm =
                            DateTime.utc(day.year, day.month, day.day);
                        final jobs = jobsByDay[norm];
                        if (jobs == null) return [];
                        return jobs; // count = number of dot markers
                      },
                      calendarStyle: CalendarStyle(
                        cellMargin: const EdgeInsets.all(3),
                        selectedDecoration: const BoxDecoration(
                            color: Color(0xFF6366F1),
                            shape: BoxShape.circle),
                        selectedTextStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                        todayDecoration: BoxDecoration(
                            color: const Color(0xFF6366F1)
                                .withValues(alpha: 0.15),
                            shape: BoxShape.circle),
                        todayTextStyle: const TextStyle(
                            color: Color(0xFF6366F1),
                            fontWeight: FontWeight.bold),
                        markersMaxCount: 3,
                        markerSize: 5,
                        markerDecoration: const BoxDecoration(
                            color: Color(0xFF6366F1),
                            shape: BoxShape.circle),
                        markerMargin:
                            const EdgeInsets.symmetric(horizontal: 1),
                      ),
                      calendarBuilders: CalendarBuilders(
                        // ── Blocked day cells ─────────────────────────
                        defaultBuilder: (context, day, focusedDay) {
                          return _buildCalendarCell(
                              day, false, appointmentDays, jobsByDay);
                        },
                        selectedBuilder: (context, day, focusedDay) {
                          return _buildCalendarCell(
                              day, true, appointmentDays, jobsByDay);
                        },
                        todayBuilder: (context, day, focusedDay) {
                          final isSelected =
                              _selectedCalendarDay != null &&
                                  isSameDay(_selectedCalendarDay, day);
                          return _buildCalendarCell(day, isSelected,
                              appointmentDays, jobsByDay,
                              isToday: true);
                        },
                        // ── Multi-dot markers ─────────────────────────
                        markerBuilder: (context, day, events) {
                          if (events.isEmpty) return null;
                          final count = events.length.clamp(1, 3);
                          return Positioned(
                            bottom: 4,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(
                                count,
                                (_) => Container(
                                  width: 5,
                                  height: 5,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 0.5),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF6366F1),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      selectedDayPredicate: (day) =>
                          _selectedCalendarDay != null &&
                          isSameDay(_selectedCalendarDay, day),
                      onDaySelected: (selectedDay, focusedDay) {
                        setState(() {
                          _selectedCalendarDay = selectedDay;
                          _calendarFocusedDay = focusedDay;
                        });
                      },
                      onDayLongPressed: (selectedDay, focusedDay) {
                        final norm = DateTime.utc(selectedDay.year,
                            selectedDay.month, selectedDay.day);
                        setState(() {
                          if (_unavailableDates.contains(norm)) {
                            _unavailableDates.remove(norm);
                          } else {
                            _unavailableDates.add(norm);
                          }
                          _calendarFocusedDay = focusedDay;
                        });
                      },
                      onPageChanged: (focusedDay) => setState(
                          () => _calendarFocusedDay = focusedDay),
                    ),
                  ),

                  // ══════════════════════════════════════════════════════
                  // DAILY AGENDA — Selected day detail
                  // ══════════════════════════════════════════════════════
                  if (_selectedCalendarDay != null) ...[
                    const SizedBox(height: 16),
                    _buildDailyAgenda(selJobs, selBlocks),
                  ],

                  // ══════════════════════════════════════════════════════
                  // RECURRING RULES SECTION
                  // ══════════════════════════════════════════════════════
                  const SizedBox(height: 20),
                  _buildRecurringRulesSection(),

                  // ══════════════════════════════════════════════════════
                  // BLOCKED DATES CHIPS
                  // ══════════════════════════════════════════════════════
                  if (_unavailableDates.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _buildBlockedDatesSection(),
                  ],

                  const SizedBox(height: 20),
                ],
              ),
            ),

            // ══════════════════════════════════════════════════════════════
            // FAB — Add block / Save
            // ══════════════════════════════════════════════════════════════
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  // Save button
                  Expanded(
                    child: _calendarSaving
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton.icon(
                            onPressed: _saveAvailability,
                            icon: const Icon(Icons.cloud_upload_rounded,
                                size: 18),
                            label: const Text('שמור שינויים',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A1A2E),
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 50),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14)),
                              elevation: 4,
                            ),
                          ),
                  ),
                  const SizedBox(width: 10),
                  // FAB — add time block
                  FloatingActionButton(
                    heroTag: 'cal_fab',
                    onPressed: () => _showAddBlockSheet(context),
                    backgroundColor: const Color(0xFF6366F1),
                    elevation: 4,
                    child: const Icon(Icons.add_rounded,
                        color: Colors.white, size: 26),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Calendar cell builder ─────────────────────────────────────────────────
  Widget? _buildCalendarCell(
    DateTime day,
    bool isSelected,
    Set<DateTime> appointmentDays,
    Map<DateTime, List<Map<String, dynamic>>> jobsByDay, {
    bool isToday = false,
  }) {
    final norm = DateTime.utc(day.year, day.month, day.day);
    final isFullyBlocked = _isDayFullyBlocked(day);
    final hasBlocks = _getBlocksForDate(day).isNotEmpty;
    final jobCount = jobsByDay[norm]?.length ?? 0;

    // Fully blocked -> striped red cell
    if (isFullyBlocked) {
      return StripedBlockedDay(day: day, isSelected: isSelected);
    }

    // Partial block -> orange tinted cell
    if (hasBlocks) {
      return Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected
              ? const Color(0xFF6366F1)
              : const Color(0xFFFFF7ED),
          border: isSelected
              ? null
              : Border.all(
                  color:
                      const Color(0xFFF97316).withValues(alpha: 0.5),
                  width: 1.5),
        ),
        child: Center(
          child: Text(
            '${day.day}',
            style: TextStyle(
              color: isSelected
                  ? Colors.white
                  : const Color(0xFFF97316),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    // Today highlight (if not selected and not blocked)
    if (isToday && !isSelected) {
      return Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF6366F1).withValues(alpha: 0.15),
        ),
        child: Center(
          child: Text(
            '${day.day}',
            style: const TextStyle(
              color: Color(0xFF6366F1),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    // Normal day with jobs -> green tint
    if (jobCount > 0 && !isSelected) {
      return Container(
        margin: const EdgeInsets.all(3),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFFF0FDF4),
        ),
        child: Center(
          child: Text(
            '${day.day}',
            style: const TextStyle(
              color: Color(0xFF1A1A2E),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    // Selected day (including today+selected combo) -> solid purple
    if (isSelected) {
      return Container(
        margin: const EdgeInsets.all(3),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF6366F1),
        ),
        child: Center(
          child: Text(
            '${day.day}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return null; // default rendering
  }

  // ── Legend dot helper ──────────────────────────────────────────────────────
  Widget _buildLegendDot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label,
          style: TextStyle(fontSize: 11, color: Colors.grey[600])),
    ]);
  }

  // ── Daily Agenda ──────────────────────────────────────────────────────────
  Widget _buildDailyAgenda(
      List<Map<String, dynamic>> jobs, List<Map<String, dynamic>> blocks) {
    final day = _selectedCalendarDay!;
    final isBlocked = _isDayFullyBlocked(day);
    final effectiveHours = _getEffectiveHours(day);

    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              const Icon(Icons.event_note_rounded,
                  size: 18, color: Color(0xFF6366F1)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  DateFormat('EEEE, d בMMMM yyyy', 'he').format(day),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFF1A1A2E)),
                ),
              ),
              // Day status badge
              if (isBlocked)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF5F5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('יום חסום',
                      style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFEF4444),
                          fontWeight: FontWeight.w600)),
                )
              else if (effectiveHours != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                      '${effectiveHours.$1} - ${effectiveHours.$2}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF16A34A),
                          fontWeight: FontWeight.w600)),
                ),
            ]),
          ),

          // Content
          if (isBlocked)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Icon(Icons.block_rounded, size: 32, color: Colors.red[300]),
                const SizedBox(height: 8),
                Text('יום זה חסום',
                    style: TextStyle(
                        color: Colors.grey[500], fontSize: 14)),
                const SizedBox(height: 4),
                Text('לחיצה ארוכה על התאריך בלוח כדי לשחרר',
                    style: TextStyle(
                        color: Colors.grey[400], fontSize: 12)),
              ]),
            )
          else if (jobs.isEmpty && blocks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Icon(Icons.event_available_rounded,
                    size: 32, color: Colors.green[300]),
                const SizedBox(height: 8),
                Text('יום פנוי — אין הזמנות',
                    style: TextStyle(
                        color: Colors.grey[500], fontSize: 14)),
              ]),
            )
          else ...[
            // ── Time blocks (partial blocks) ──────────────────────
            for (final block in blocks) _buildAgendaBlockItem(block),

            // ── Jobs ──────────────────────────────────────────────
            for (final j in jobs) _buildAgendaJobItem(j),
          ],
        ],
      ),
    );
  }

  Widget _buildAgendaJobItem(Map<String, dynamic> j) {
    final time = j['appointmentTime'] as String? ?? '';
    final name = j['customerName'] as String? ?? 'לקוח';
    final status = j['status'] as String? ?? '';
    final amount = ((j['totalAmount'] ??
                j['totalPaidByCustomer'] ??
                0) as num)
            .toDouble();
    final service = j['serviceType'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        // Time pill
        Container(
          width: 50,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            time.isNotEmpty ? time : '--:--',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6366F1),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Customer info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFF1A1A2E))),
              if (service.isNotEmpty)
                Text(service,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF64748B))),
            ],
          ),
        ),
        // Amount
        if (amount > 0)
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '₪${amount.toStringAsFixed(0)}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF16A34A)),
            ),
          ),
        const SizedBox(width: 6),
        BookingStatusBadge(status),
      ]),
    );
  }

  Widget _buildAgendaBlockItem(Map<String, dynamic> block) {
    final from = block['from'] as String? ?? '';
    final to = block['to'] as String? ?? '';
    final reason = block['reason'] as String? ?? 'personal';

    final reasonLabel = switch (reason) {
      'break' => 'הפסקה',
      'appointment' => 'פגישה אישית',
      _ => 'חסום',
    };
    final reasonIcon = switch (reason) {
      'break' => Icons.coffee_rounded,
      'appointment' => Icons.person_rounded,
      _ => Icons.block_rounded,
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFFF97316).withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        // Time range pill
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$from - $to',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFFF97316),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Icon(reasonIcon, size: 16, color: const Color(0xFFF97316)),
        const SizedBox(width: 6),
        Text(reasonLabel,
            style: const TextStyle(
                fontSize: 13,
                color: Color(0xFFF97316),
                fontWeight: FontWeight.w600)),
        const Spacer(),
        // Delete block
        GestureDetector(
          onTap: () {
            setState(() => _timeBlocks.remove(block));
          },
          child:
              Icon(Icons.close_rounded, size: 18, color: Colors.red[400]),
        ),
      ]),
    );
  }

  // ── Recurring Rules Section ───────────────────────────────────────────────
  Widget _buildRecurringRulesSection() {
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              const Icon(Icons.repeat_rounded,
                  size: 18, color: Color(0xFF8B5CF6)),
              const SizedBox(width: 8),
              const Text('חוקים חוזרים',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFF1A1A2E))),
              const Spacer(),
              GestureDetector(
                onTap: () => _showAddRecurringRuleSheet(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded,
                            size: 14, color: Color(0xFF8B5CF6)),
                        SizedBox(width: 4),
                        Text('הוסף',
                            style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8B5CF6),
                                fontWeight: FontWeight.w600)),
                      ]),
                ),
              ),
            ]),
          ),

          // Rules list
          if (_recurringRules.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Column(children: [
                  Icon(Icons.event_repeat_rounded,
                      size: 28, color: Colors.grey[300]),
                  const SizedBox(height: 6),
                  Text('אין חוקים חוזרים',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[400])),
                  const SizedBox(height: 2),
                  Text(
                      'לדוגמה: "סגור בכל שישי" או "זמין 08-12 בראשון"',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[350])),
                ]),
              ),
            )
          else
            for (int i = 0; i < _recurringRules.length; i++)
              _buildRecurringRuleItem(i),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildRecurringRuleItem(int index) {
    final rule = _recurringRules[index];
    final dayIndex = rule['dayIndex'] as int? ?? 0;
    final type = rule['type'] as String? ?? 'off';
    final dayName = _kDayNamesHe[dayIndex.clamp(0, 6)];

    final isOff = type == 'off';
    final from = rule['from'] as String? ?? '';
    final to = rule['to'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isOff
            ? const Color(0xFFFFF5F5)
            : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isOff
              ? const Color(0xFFEF4444).withValues(alpha: 0.2)
              : const Color(0xFF10B981).withValues(alpha: 0.2),
        ),
      ),
      child: Row(children: [
        // Day badge
        Container(
          width: 60,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            dayName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isOff
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF10B981),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Icon(
          isOff ? Icons.block_rounded : Icons.schedule_rounded,
          size: 16,
          color: isOff
              ? const Color(0xFFEF4444)
              : const Color(0xFF10B981),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            isOff ? 'סגור כל יום $dayName' : 'זמין $from - $to',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isOff
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF10B981),
            ),
          ),
        ),
        GestureDetector(
          onTap: () =>
              setState(() => _recurringRules.removeAt(index)),
          child: Icon(Icons.close_rounded,
              size: 18, color: Colors.grey[400]),
        ),
      ]),
    );
  }

  // ── Blocked dates chips section ───────────────────────────────────────────
  Widget _buildBlockedDatesSection() {
    final sortedDates = _unavailableDates.toList()..sort();
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              const Icon(Icons.event_busy_rounded,
                  size: 18, color: Color(0xFFEF4444)),
              const SizedBox(width: 8),
              Text('ימים חסומים (${sortedDates.length})',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFF1A1A2E))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: sortedDates.map((d) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF5F5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFFEF4444)
                            .withValues(alpha: 0.2)),
                  ),
                  child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormat('dd/MM').format(d),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFEF4444)),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => setState(
                              () => _unavailableDates.remove(d)),
                          child: const Icon(Icons.close_rounded,
                              size: 14, color: Color(0xFFEF4444)),
                        ),
                      ]),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom sheet: Add time block ──────────────────────────────────────────
  void _showAddBlockSheet(BuildContext context) {
    String blockType = 'full_day'; // full_day | time_range
    String reason = 'personal';
    DateTime blockDate = _selectedCalendarDay ?? DateTime.now();
    String fromTime = '09:00';
    String toTime = '17:00';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24,
                MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('הוסף חסימה',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E))),
                const SizedBox(height: 16),

                // Block type toggle
                Row(children: [
                  Expanded(
                    child: BlockTypeChip(
                      label: 'יום מלא',
                      icon: Icons.event_busy_rounded,
                      isSelected: blockType == 'full_day',
                      onTap: () => setSheetState(
                          () => blockType = 'full_day'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: BlockTypeChip(
                      label: 'טווח שעות',
                      icon: Icons.schedule_rounded,
                      isSelected: blockType == 'time_range',
                      onTap: () => setSheetState(
                          () => blockType = 'time_range'),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),

                // Date picker
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: blockDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now()
                          .add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setSheetState(() => blockDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.calendar_today_rounded,
                          size: 16, color: Color(0xFF6366F1)),
                      const SizedBox(width: 10),
                      Text(
                        DateFormat('EEEE, d/M/yyyy', 'he')
                            .format(blockDate),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                ),

                // Time range pickers (only for time_range)
                if (blockType == 'time_range') ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: CalendarTimeDropdown(
                        label: 'מ-',
                        value: fromTime,
                        onChanged: (v) =>
                            setSheetState(() => fromTime = v),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10),
                      child: Text('עד',
                          style:
                              TextStyle(color: Colors.grey[500])),
                    ),
                    Expanded(
                      child: CalendarTimeDropdown(
                        label: 'עד-',
                        value: toTime,
                        onChanged: (v) =>
                            setSheetState(() => toTime = v),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  // Reason chips
                  Row(children: [
                    ReasonChip(
                      label: 'אישי',
                      icon: Icons.person_rounded,
                      isSelected: reason == 'personal',
                      onTap: () => setSheetState(
                          () => reason = 'personal'),
                    ),
                    const SizedBox(width: 8),
                    ReasonChip(
                      label: 'הפסקה',
                      icon: Icons.coffee_rounded,
                      isSelected: reason == 'break',
                      onTap: () =>
                          setSheetState(() => reason = 'break'),
                    ),
                    const SizedBox(width: 8),
                    ReasonChip(
                      label: 'פגישה',
                      icon: Icons.groups_rounded,
                      isSelected: reason == 'appointment',
                      onTap: () => setSheetState(
                          () => reason = 'appointment'),
                    ),
                  ]),
                ],

                const SizedBox(height: 20),

                // Submit
                ElevatedButton(
                  onPressed: () {
                    if (blockType == 'full_day') {
                      final norm = DateTime.utc(blockDate.year,
                          blockDate.month, blockDate.day);
                      setState(
                          () => _unavailableDates.add(norm));
                    } else {
                      final dateKey =
                          '${blockDate.year.toString().padLeft(4, '0')}-'
                          '${blockDate.month.toString().padLeft(2, '0')}-'
                          '${blockDate.day.toString().padLeft(2, '0')}';
                      setState(() => _timeBlocks.add({
                            'date': dateKey,
                            'from': fromTime,
                            'to': toTime,
                            'reason': reason,
                          }));
                    }
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    minimumSize:
                        const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(14)),
                  ),
                  child: const Text('הוסף חסימה',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Bottom sheet: Add recurring rule ──────────────────────────────────────
  void _showAddRecurringRuleSheet(BuildContext context) {
    int selectedDay = 5; // Friday default
    String ruleType = 'off'; // off | hours
    String fromTime = '08:00';
    String toTime = '12:00';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24,
                MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('חוק חוזר שבועי',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E))),
                const SizedBox(height: 16),

                // Day selector
                const Text('בחר יום:',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B))),
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: 7,
                    itemBuilder: (_, i) {
                      final isSelected = selectedDay == i;
                      return GestureDetector(
                        onTap: () => setSheetState(
                            () => selectedDay = i),
                        child: Container(
                          width: 46,
                          margin:
                              const EdgeInsets.only(left: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF6366F1)
                                : const Color(0xFFF8FAFC),
                            borderRadius:
                                BorderRadius.circular(10),
                            border: isSelected
                                ? null
                                : Border.all(
                                    color: const Color(
                                        0xFFE2E8F0)),
                          ),
                          child: Center(
                            child: Text(
                              _kDayNamesHe[i],
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.grey[700],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),

                // Rule type
                Row(children: [
                  Expanded(
                    child: BlockTypeChip(
                      label: 'סגור ביום זה',
                      icon: Icons.block_rounded,
                      isSelected: ruleType == 'off',
                      onTap: () =>
                          setSheetState(() => ruleType = 'off'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: BlockTypeChip(
                      label: 'שעות מותאמות',
                      icon: Icons.schedule_rounded,
                      isSelected: ruleType == 'hours',
                      onTap: () => setSheetState(
                          () => ruleType = 'hours'),
                    ),
                  ),
                ]),

                if (ruleType == 'hours') ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: CalendarTimeDropdown(
                        label: 'מ-',
                        value: fromTime,
                        onChanged: (v) =>
                            setSheetState(() => fromTime = v),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10),
                      child: Text('עד',
                          style:
                              TextStyle(color: Colors.grey[500])),
                    ),
                    Expanded(
                      child: CalendarTimeDropdown(
                        label: 'עד-',
                        value: toTime,
                        onChanged: (v) =>
                            setSheetState(() => toTime = v),
                      ),
                    ),
                  ]),
                ],

                const SizedBox(height: 20),

                ElevatedButton(
                  onPressed: () {
                    // Remove existing rule for this day
                    setState(() {
                      _recurringRules.removeWhere(
                          (r) => r['dayIndex'] == selectedDay);
                      _recurringRules.add({
                        'dayIndex': selectedDay,
                        'type': ruleType,
                        if (ruleType == 'hours')
                          'from': fromTime,
                        if (ruleType == 'hours') 'to': toTime,
                      });
                    });
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    foregroundColor: Colors.white,
                    minimumSize:
                        const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(14)),
                  ),
                  child: const Text('שמור חוק',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
